(in-package #:lisploop)

;;; Milestones 3B and 6: lossless law and tree corpus compression, occurrence search, locality schedules.

(defstruct (tree-corpus (:constructor %make-tree-corpus))
  domain
  inputs
  sort
  trees
  packet)

;;; Law Corpus Compression (M3B)
(defstruct (law-corpus (:include tree-corpus) (:constructor %make-law-corpus))
  "A tree corpus of sort :bool whose trees are the statements of LAWS, in order."
  laws)

(defun bits-as-values (bits)
  (map 'list (lambda (bit) (= bit 1)) bits))

(defun values-as-bits (values)
  (assert (value-p values (sequence-type :bool)))
  (map 'bit-vector (lambda (value) (if value 1 0)) values))

(defun collect-bit-chunks (writer &optional ledger)
  "Call WRITER with an emitter of (width value) bit fields and a function that appends one
finished item. Return the items in order, with every run of bits emitted between them as one
list of Booleans. Each emitted field is charged as :packet-assembly."
  (let ((items nil)
        (run nil)) ; bits emitted since the last item, latest first
    (flet ((flush ()
             (when run
               (push (nreverse run) items)
               (setf run nil))))
      (funcall writer
               (lambda (width value)
                 (charge ledger :packet-assembly width)
                 (loop for i downfrom (1- width) to 0 do (push (logbitp i value) run)))
               (lambda (item) (flush) (push item items)))
      (flush)
      (nreverse items))))

(defun collect-code-values (writer &optional ledger)
  "The bits that WRITER emits, as one list of Booleans."
  (first (collect-bit-chunks (lambda (emit add) (declare (ignore add)) (funcall writer emit)) ledger)))

(defun model-packet (model inputs &optional ledger)
  "The standalone packet of MODEL under INPUTS, as a list of Booleans."
  (collect-code-values (lambda (emit) (emit-bit-model model inputs emit)) ledger))

(defun length-prefix (size &optional ledger)
  "The code that announces a following packet of SIZE bits."
  (collect-code-values (lambda (emit) (emit-positive (1+ size) emit)) ledger))

(defun law-corpus-type (domain)
  (tuple-type domain (sequence-type (sequence-type :bool))))

(defun encode-corpus-packet (trees inputs domain &optional ledger)
  (let ((packets (mapcar (lambda (tree)
                           (charge ledger :corpus-encoding (syntax-work tree))
                           (model-packet tree inputs ledger))
                         trees)))
    (model-packet (lit (law-corpus-type domain) (list 0 packets)) nil ledger)))

(defun make-law-corpus (laws &optional ledger)
  "Snapshot one domain/schema's ordered statements, including duplicate occurrences.
Evidence/provenance are not part of this syntax-compression task."
  (assert laws)
  (let ((domain (law-domain (first laws))) (inputs (law-inputs (first laws))))
    (assert (every (lambda (law) (and (equal domain (law-domain law))
                                      (equal inputs (law-inputs law)))) laws))
    (let* ((copies (mapcar (lambda (law)
                             (let ((eq-args (rest (law-equation law))))
                               (make-law domain inputs (first eq-args) (second eq-args)
                                         :guard (law-guard law))))
                           laws))
           (statements (mapcar #'law-statement copies)))
      (%make-law-corpus :domain (copy-tree domain) :inputs (copy-tree inputs) :sort :bool
                        :trees statements :laws copies
                        :packet (encode-corpus-packet statements inputs domain ledger)))))

(defun decode-law-corpus (packet)
  "Decode a standalone reconstructed corpus into fresh law proposals, never certificates."
  (multiple-value-bind (statements schema sort domain) (decode-tree-corpus packet)
    (assert (eq :bool sort))
    (loop for statement in statements collect
      (progn
        (assert (and (app-p statement)
                     (equal (op :if :bool) (first statement))
                     (equal (lit :bool t) (fourth statement))))
        (let ((guard (second statement))
              (equation (third statement)))
          (assert (and (app-p equation) (eq := (operator-name (first equation)))))
          (make-law domain schema (second equation) (third equation)
                    :guard guard :origin '(:decoded-syntax)))))))

(defun tree-corpus-prefix (corpus &optional ledger)
  "The leading bits of the packet of CORPUS, up to and including its tree count."
  (let ((domain (tree-corpus-domain corpus)))
    (collect-code-values
     (lambda (emit)
       (emit-bit-header nil (law-corpus-type domain) emit)
       (funcall emit 2 1)
       (emit-bit-value 0 domain emit)
       (emit-positive (1+ (length (tree-corpus-trees corpus))) emit))
     ledger)))

(defun au-packet-pieces (pattern inputs &optional ledger)
  (au-body-pieces pattern inputs :include-header-p t :ledger ledger))

(defun instantiate-packet-pieces (pieces substitution inputs &optional ledger)
  "Replace each hole among PIECES by the bits of its binding; fixed bit runs pass through."
  (mapcar
   (lambda (piece)
     (if (hole-p piece)
         (let ((entry (assoc (ast-id piece) substitution)))
           (assert entry)
           (assert (equal (ast-type piece) (term-sort (cdr entry) inputs)))
           (charge ledger :au-substitution (syntax-work (cdr entry)))
           (collect-code-values
            (lambda (emit)
              (if (operator-p (cdr entry))
                  (emit-operator (cdr entry) emit)
                  (emit-bit-expression (cdr entry) inputs (ast-type piece) emit)))
            ledger))
         piece))
   pieces))

(defun packet-chunks-model (chunks &optional ledger)
  "A normal closed VM program; its dictionary and full occurrence order are encoded."
  (multiple-value-bind (representatives residual) (quotient-values chunks ledger)
    (let ((model (term `(concat ,(quotient-model (sequence-type :bool) representatives residual
                                                 ledger)))))
      (charge ledger :construction (syntax-work model))
      model)))

(defun tree-row-pieces-model (corpus rows &optional ledger)
  "The model that concatenates the prefix of CORPUS and, for each tree, a length code
followed by the bit chunks of its row."
  (assert (= (length rows) (length (tree-corpus-trees corpus))))
  (let ((chunks (list (tree-corpus-prefix corpus ledger))))
    (map nil (lambda (body)
               (push (length-prefix (reduce #'+ body :key #'length) ledger) chunks)
               (dolist (piece body) (push piece chunks)))
         rows)
    (packet-chunks-model (nreverse chunks) ledger)))

(defun law-template-model (corpus pattern substitutions &optional ledger)
  (assert (= (length substitutions) (length (law-corpus-laws corpus))))
  (corpus-abstraction-model corpus pattern (make-list (length substitutions)) substitutions ledger))

(defstruct law-template-group positions pattern substitutions)

(defun law-syntax-shape (term inputs &optional ledger)
  "A supplied structural view, not a learned equivalence: erase leaf values and
compatible operator names, preserving application shape and all types."
  (charge ledger :law-shape)
  (if (app-p term)
      (list :app (operator-type (first term))
            (mapcar (lambda (child) (law-syntax-shape child inputs ledger)) (rest term)))
      (list :leaf (expression-type term inputs))))

(defun grouped-law-template-model (corpus &optional ledger)
  "One supplied shape partition; AU each group and encode all occurrence ordering."
  (let* ((inputs (law-corpus-inputs corpus)) (statements (law-corpus-trees corpus))
         (table (make-hash-table :test #'equal)) (groups nil)
         (rows (make-array (length statements))))
    (loop for statement in statements for i from 0 do
      (let* ((shape (law-syntax-shape statement inputs ledger)) (group (gethash shape table)))
        (unless group
          (setf group (make-law-template-group) (gethash shape table) group)
          (push group groups))
        (push i (law-template-group-positions group))))
    (setf groups (nreverse groups))
    (let ((vector (coerce statements 'vector)))
      (dolist (group groups)
        (setf (law-template-group-positions group) (nreverse (law-template-group-positions group)))
        (multiple-value-bind (pattern substitutions)
            (anti-unify (mapcar (lambda (i) (aref vector i)) (law-template-group-positions group)) inputs ledger)
          (setf (law-template-group-pattern group) pattern (law-template-group-substitutions group) substitutions)
          (let ((pieces (au-packet-pieces pattern inputs ledger)))
            (loop for i in (law-template-group-positions group) for substitution in substitutions do
              (setf (aref rows i) (instantiate-packet-pieces pieces substitution inputs ledger)))))))
    (values (tree-row-pieces-model corpus rows ledger) groups)))

(defun corpus-literal-model (corpus &optional ledger)
  "Baseline proposal: the packet of CORPUS as one literal."
  (let ((literal (lit (sequence-type :bool) (tree-corpus-packet corpus))))
    (charge ledger :construction (syntax-work literal))
    literal))

(defun corpus-dictionary-model (corpus &optional ledger)
  "Baseline proposal: a dictionary whose chunks are the whole length-prefixed tree packets."
  (let ((inputs (tree-corpus-inputs corpus)))
    (packet-chunks-model
     (cons (tree-corpus-prefix corpus ledger)
           (mapcar (lambda (tree)
                     (let ((packet (model-packet tree inputs ledger)))
                       (append (length-prefix (length packet) ledger) packet)))
                   (tree-corpus-trees corpus)))
     ledger)))

(defun propose-law-compressions (corpus &optional ledger)
  "Four complete proposals: literal, whole-packet dictionary, global/grouped AU."
  (let ((literal (corpus-literal-model corpus ledger))
        (dictionary (corpus-dictionary-model corpus ledger)))
    (multiple-value-bind (pattern substitutions)
        (anti-unify (law-corpus-trees corpus) (law-corpus-inputs corpus) ledger)
      (multiple-value-bind (grouped groups) (grouped-law-template-model corpus ledger)
        (values (list literal dictionary (law-template-model corpus pattern substitutions ledger) grouped)
                pattern substitutions groups)))))

(defun tree-corpus-frame (corpus &optional ledger (key :tree-corpus))
  "The one-row frame, keyed KEY, that accepts exactly the packet of CORPUS."
  (let ((req (set-requirement (sequence-type :bool) (list (tree-corpus-packet corpus)))))
    (charge ledger :corpus-frame (syntax-work req))
    (make-frame (make-schema :inputs nil :target (sequence-type :bool))
                (list (make-row :key key :known nil :requirement req)))))

(defun law-corpus-frame (corpus &optional ledger)
  (tree-corpus-frame corpus ledger :law-corpus))

;;; Subexpression Occurrence Search & Corpus Abstraction (M6)
(defun patterns-isomorphic-p (pattern-a pattern-b &optional inputs ledger)
  "Check whether PATTERN-A and PATTERN-B are identical up to a sort-preserving
bijection (alpha-renaming) of hole IDs."
  (multiple-value-bind (bindings matched-p) (match-pattern pattern-a pattern-b inputs ledger)
    (let ((images (mapcar #'cdr bindings)))
      (and matched-p
           (every #'hole-p images)
           (equal images (remove-duplicates images))))))

(defun pattern-hole-counts (pattern)
  "Return an alist (hole-id . multiplicity) for all holes in PATTERN."
  (let ((counts nil))
    (labels ((walk (term)
               (cond
                 ((hole-p term)
                  (incf (cdr (or (assoc (ast-id term) counts)
                                 (first (push (cons (ast-id term) 0) counts))))))
                 ((app-p term) (mapc #'walk term)))))
      (walk pattern)
      (nreverse counts))))

(defun subtree-at-path (term path &optional ledger)
  "Return the subexpression of TERM at PATH (a list of 0-based argument indices)."
  (let ((cur term))
    (dolist (idx path cur)
      (charge ledger :occurrence-access)
      (assert (and (app-p cur) (integerp idx) (<= 0 idx) (< idx (length (rest cur)))) ()
              "Invalid occurrence path ~S on ~S" path term)
      (setf cur (nth idx (rest cur))))))

(defun replace-at-path (term path replacement &optional ledger)
  "Return a copy of TERM with the subexpression at PATH replaced by REPLACEMENT."
  (charge ledger :occurrence-wrapper)
  (if (null path)
      replacement
      (let ((idx (first path))
            (args (rest term)))
        (assert (and (app-p term) (integerp idx) (<= 0 idx) (< idx (length args))) ()
                "Invalid replacement path ~S on ~S" path term)
        (apply #'app (first term)
               (loop for child in args
                     for i from 0
                     collect (if (= i idx)
                                 (replace-at-path child (rest path) replacement ledger)
                                 child))))))

(defstruct tree-occurrence
  (tree-index 0 :type fixnum)
  path
  term
  sort
  signature)

(defun collect-tree-occurrences (tree inputs &key (tree-index 0) ledger)
  "Collect all subexpression occurrences in TREE in pre-order."
  (let ((occurrences nil))
    (labels ((walk (sub rev-path)
               (charge ledger :occurrence-enumeration)
               (push (make-tree-occurrence :tree-index tree-index
                                           :path (reverse rev-path)
                                           :term sub
                                           :sort (expression-type sub inputs t)
                                           :signature (and (app-p sub) (operator-type (first sub))))
                     occurrences)
               (when (app-p sub)
                 (loop for child in (rest sub)
                       for i from 0
                       do (walk child (cons i rev-path))))))
      (walk tree nil)
      (nreverse occurrences))))

(defun make-tree-corpus (trees inputs &key domain sort ledger)
  "Snapshot an ordered sequence of typed ASTs under INPUTS into a standalone bit packet."
  (assert trees)
  (let* ((inputs (input-alist inputs))
         (sort (or sort (expression-type (first trees) inputs)))
         (domain (or domain (infer-domain-from-types (cons sort (mapcar #'cdr inputs)))))
         (copies (mapcar #'copy-tree trees)))
    (dolist (tree copies)
      (assert (equal sort (expression-type tree inputs))))
    (%make-tree-corpus :domain (copy-tree domain) :inputs (copy-tree inputs) :sort (copy-tree sort)
                       :trees copies :packet (encode-corpus-packet copies inputs domain ledger))))

(defun decode-tree-corpus (packet)
  "Decode a standalone tree-corpus packet back into fresh ASTs and verify schema consistency."
  (multiple-value-bind (literal top-inputs) (decode-model (values-as-bits packet))
    (assert (and (null top-inputs) (lit-p literal)))
    (let* ((type (ast-type literal))
           (domain (second type))
           (value (ast-value literal)))
      (assert (equal type (law-corpus-type domain)))
      (assert (eql 0 (first value)))
      (let ((trees nil)
            (first-schema nil)
            (first-sort nil))
        (dolist (bits (second value))
          (multiple-value-bind (tree schema) (decode-model (values-as-bits bits))
            (let ((sort (expression-type tree schema)))
              (if (null trees)
                  (setf first-schema schema
                        first-sort sort)
                  (assert (and (equal schema first-schema)
                               (equal sort first-sort))))
              (push tree trees))))
        (assert trees)
        (values (nreverse trees) first-schema first-sort domain)))))

(defun au-body-pieces (pattern inputs &key include-header-p ledger)
  "Compile a typed AU pattern into fixed bit runs and hole references.
When INCLUDE-HEADER-P is nil, omits the outer packet header so the body pieces
can be spliced at any occurrence path inside an outer wrapper."
  (collect-bit-chunks
   (lambda (emit add)
     (labels ((walk (term)
                (charge ledger :au-compilation (syntax-work term))
                (cond
                  ((hole-p term) (funcall add term))
                  ((operator-p term) (emit-operator term emit))
                  ((not (pattern-has-holes-p term))
                   (emit-bit-expression term inputs (expression-type term inputs) emit))
                  (t (assert (app-p term))
                     (funcall emit 2 2) (walk (first term)) (mapc #'walk (rest term))))))
       (when include-header-p
         (emit-bit-header inputs (expression-type pattern inputs t) emit))
       (walk pattern)))
   ledger))

(defun tree-occurrence-packet-pieces (tree path body-pieces substitution inputs &key header-in-body-p ledger)
  "Emit the ordered bit pieces of TREE when the subexpression at PATH is factored
through BODY-PIECES and SUBSTITUTION. If PATH is :NONE, emits TREE as a single chunk."
  (let ((root-sort (expression-type tree inputs)))
    (cond
      ((eq path :none)
       (list (model-packet tree inputs ledger)))
      ((and (null path) header-in-body-p)
       (instantiate-packet-pieces body-pieces substitution inputs ledger))
      (t
       (collect-bit-chunks
        (lambda (emit add)
          (labels ((walk-wrapper (term rel-path)
                     (if (null rel-path)
                         (mapc add (instantiate-packet-pieces body-pieces substitution inputs ledger))
                         (let ((operator (first term)))
                           (assert (app-p term))
                           (funcall emit 2 2)
                           (emit-operator operator emit)
                           (loop for child in (rest term)
                                 for child-type in (second (operator-type operator))
                                 for k from 0
                                 do (if (= k (first rel-path))
                                        (walk-wrapper child (rest rel-path))
                                        (emit-bit-expression child inputs child-type emit)))))))
            (emit-bit-header inputs root-sort emit)
            (walk-wrapper tree path)))
        ledger)))))

(defun corpus-abstraction-model (corpus pattern paths substitutions &optional ledger)
  "Construct a closed VM program reconstructing CORPUS by factoring each tree i
at `(nth i paths)` (or leaving it unfactored when `(eq :none (nth i paths))`)."
  (let* ((trees (tree-corpus-trees corpus))
         (inputs (tree-corpus-inputs corpus))
         (all-root-p (every #'null paths))
         (body-pieces (au-body-pieces pattern inputs :include-header-p all-root-p :ledger ledger))
         (sub-cursor substitutions)
         (rows
           (loop for tree in trees
                 for path in paths
                 collect (if (eq path :none)
                             (tree-occurrence-packet-pieces tree :none nil nil inputs :ledger ledger)
                             (let ((subst (pop sub-cursor)))
                               (tree-occurrence-packet-pieces tree path body-pieces subst inputs
                                                              :header-in-body-p all-root-p
                                                              :ledger ledger))))))
    (tree-row-pieces-model corpus rows ledger)))

(defstruct subexpression-abstraction
  (kind :subexpression)
  pattern
  substitutions
  paths
  model
  (bits 0 :type fixnum)
  (literal-bits 0 :type fixnum)
  (gain 0 :type fixnum)
  (structural-score 0 :type fixnum))

(defun term-body-bits (term inputs)
  "Return the exact body bit length of a concrete term or operator."
  (if (operator-p term)
      (length (collect-code-values (lambda (emit) (emit-operator term emit))))
      (body-size term inputs)))

(defun occurrence-saved-bits (occ substitution inputs)
  "Exact bit savings inside OCC's tree from factoring `(tree-occurrence-term occ)`
through a pattern whose unique hole bindings are SUBSTITUTION."
  (- (body-size (tree-occurrence-term occ) inputs)
     (loop for (nil . hole-val) in substitution
           sum (term-body-bits hole-val inputs))))

(defun abstraction-structural-score (pattern occurrences substitutions inputs)
  "Compute the structural bit-sharing utility of PATTERN across OCCURRENCES:
shared fixed template bits across (K - 1) occurrences plus repeated-hole savings
within each occurrence."
  (let ((k (length occurrences)))
    (if (or (< k 2) (null pattern) (hole-p pattern))
        0
        (let* ((first-occ (first occurrences))
               (first-subst (first substitutions))
               (fixed-bits
                 (max 0 (- (body-size (tree-occurrence-term first-occ) inputs)
                           (loop for (hid . mult) in (pattern-hole-counts pattern)
                                 for entry = (assoc hid first-subst)
                                 when entry
                                 sum (* mult (term-body-bits (cdr entry) inputs))))))
               (total-saved
                 (loop for occ in occurrences
                       for subst in substitutions
                       sum (occurrence-saved-bits occ subst inputs))))
          (- total-saved fixed-bits)))))

(defun integer-coordinate-vector-p (value)
  "True when VALUE is a non-empty list of integers (a tuple or sequence in Z^d)."
  (and (consp value) (every #'integerp value)))

(defun generated-space-distance (la lb rank-dist)
  "Compute distance between two points LA and LB in a generated locality space:
- Same quotient equivalence class (`equal`): distance 1 when distinct trees (0 when identical),
  with rank-dist preserved for intra-class tie-breaking.
- Multi-coordinate integer tuple/sequence `Z^d`: L1 Manhattan distance sum_k |u_k - v_k|.
- Distinct quotient classes in a coarse partition: (> 1) so cross-class pairs do not pass
  `:locality-only` window <= 1."
  (cond
    ((equal la lb) (min 1 rank-dist))
    ((and (integer-coordinate-vector-p la)
          (integer-coordinate-vector-p lb)
          (= (length la) (length lb)))
     (loop for ua in la
           for ub in lb
           sum (abs (- ua ub))))
    (t (+ 2 rank-dist))))

(defun compute-tree-locality-positions (n locality-key &optional ledger)
  "Compute the induced position vector (0..N-1) and quotient structure for tree indices
under LOCALITY-KEY. When LOCALITY-KEY is nil, position(i) = i. When LOCALITY-KEY is a
function or DSL expression over `((0 . :int))`, evaluates the key for each tree index i
into a generated space (scalars or tuples), partitions via `partition-rows` (verifying
`reassemble-partition`), and quotients via `quotient-values` (verifying `restore-quotient`).
Returns (VALUES pos-vec labels-vec representatives residual partition)."
  (let ((pos-vec (make-array n)))
    (if (null locality-key)
        (progn
          (dotimes (i n)
            (setf (aref pos-vec i) i))
          (values pos-vec nil nil nil nil))
        (let* ((key-expr (if (and (knowledge-entry-p locality-key)
                                  (eq :locality-key (knowledge-entry-kind locality-key)))
                             (knowledge-entry-expression locality-key)
                             locality-key))
               (indices (loop for i below n collect i))
               (labels
                 (loop for i below n
                       collect (if (functionp key-expr)
                                   (progn
                                     (charge ledger :locality-key)
                                     (funcall key-expr i))
                                   (let ((run (evaluate key-expr '((0 . :int)) (list i) :ledger ledger)))
                                     (unless (eq :value (evaluation-status run))
                                       (error "Locality key evaluation failed on ~D: ~S" i run))
                                     (evaluation-value run)))))
               (part (partition-rows indices labels ledger))
               (ordered-indices (apply #'append (partition-groups part))))
          (assert (equal indices (reassemble-partition part ledger)))
          (multiple-value-bind (reps residual) (quotient-values labels ledger)
            (assert (equal labels (restore-quotient reps residual ledger)))
            (loop for tree-idx in ordered-indices
                  for rank from 0
                  do (setf (aref pos-vec tree-idx) rank))
            (values pos-vec (coerce labels 'vector) reps residual part))))))

(defun schedule-occurrence-pairs (canonical-pairs tree-pos schedule pair-budget &optional ledger labels-vec)
  "Order candidate occurrence pairs `(oa . ob)` under SCHEDULE (:CANONICAL, :LOCALITY with 1-in-4
canonical reserve, or :LOCALITY-ONLY restricted to adjacent tree distance <= 1) up to PAIR-BUDGET."
  (assert (member schedule '(:canonical :locality :locality-only)))
  (labels ((index (occ) (tree-occurrence-tree-index occ))
           (depth (occ) (length (tree-occurrence-path occ)))
           (same-tree (pair) ; 0 for a cross-tree pair, so that those sort first
             (if (= (index (car pair)) (index (cdr pair))) 1 0))
           (rank-dist (pair)
             (abs (- (aref tree-pos (index (car pair))) (aref tree-pos (index (cdr pair))))))
           (tree-dist (pair)
             (if labels-vec
                 (generated-space-distance (aref labels-vec (index (car pair)))
                                           (aref labels-vec (index (cdr pair)))
                                           (rank-dist pair))
                 (rank-dist pair)))
           (path-dist (pair) (abs (- (depth (car pair)) (depth (cdr pair)))))
           (depth-sum (pair) (+ (depth (car pair)) (depth (cdr pair))))
           (by-locality (pairs)
             (stable-sort pairs (lambda (a b)
                                  (lex< a b #'same-tree #'tree-dist #'rank-dist #'path-dist #'depth-sum))))
           (within-budget (pairs)
             (if pair-budget (subseq pairs 0 (min pair-budget (length pairs))) pairs)))
    (ecase schedule
      (:canonical (within-budget canonical-pairs))
      (:locality-only
       (let ((local (by-locality (loop for pair in canonical-pairs
                                       when (and (zerop (same-tree pair)) (<= (tree-dist pair) 1))
                                         collect pair))))
         (charge ledger :locality-scheduling (length local))
         (within-budget local)))
      (:locality
       (let ((loc-queue (by-locality (copy-list canonical-pairs)))
             (can-queue canonical-pairs)
             (seen (make-hash-table :test #'equal))
             (selected nil)
             (limit (or pair-budget (length canonical-pairs))))
         (macrolet ((pop-unseen (queue)
                      `(loop while ,queue do
                         (let ((pair (pop ,queue)))
                           (unless (gethash pair seen) (return pair))))))
           (loop for turn from 0
                 while (and (< (length selected) limit) (or loc-queue can-queue))
                 do (charge ledger :locality-scheduling)
                    ;; Every fourth turn is reserved for the canonical order.
                    (let ((pair (if (= 3 (mod turn 4))
                                    (or (pop-unseen can-queue) (pop-unseen loc-queue))
                                    (or (pop-unseen loc-queue) (pop-unseen can-queue)))))
                      (when pair
                        (setf (gethash pair seen) t)
                        (push pair selected)))))
         (nreverse selected))))))

(defun trivial-subexpression-pattern-p (pattern)
  "True for a bare hole and for an application made only of distinct holes, which share no syntax."
  (or (hole-p pattern)
      (and (app-p pattern)
           (every #'hole-p pattern)
           (= (length pattern) (length (pattern-holes pattern))))))

(defun index-tree-occurrences (trees inputs &optional ledger)
  "Return a vector of the occurrences of each tree, and a table from (sort . signature) to the
occurrences of all trees that share it, latest first."
  (let ((per-tree (make-array (length trees)))
        (buckets (make-hash-table :test #'equal)))
    (loop for tree in trees
          for i from 0
          for occs = (collect-tree-occurrences tree inputs :tree-index i :ledger ledger)
          do (setf (aref per-tree i) occs)
             (dolist (occ occs)
               (push occ (gethash (cons (tree-occurrence-sort occ) (tree-occurrence-signature occ))
                                  buckets))))
    (values per-tree buckets)))

(defun candidate-occurrence-pairs (buckets candidates repeats-p)
  "List every pair of occurrences with different terms that share a bucket, in corpus order.
When REPEATS-P, also record in CANDIDATES each non-trivial term that occurs more than once."
  (let ((pairs nil))
    (maphash
     (lambda (key occs)
       (declare (ignore key))
       (let ((counts (make-hash-table :test #'equal)) ; term -> number of occurrences
             (distinct nil))                          ; the first occurrence of each term
         (dolist (occ (reverse occs))
           (when (= 1 (incf (gethash (tree-occurrence-term occ) counts 0)))
             (push occ distinct)))
         (setf distinct (nreverse distinct))
         (when repeats-p
           (dolist (occ distinct)
             (let ((term (tree-occurrence-term occ)))
               (when (and (> (gethash term counts) 1)
                          (not (trivial-subexpression-pattern-p term))
                          (not (gethash term candidates)))
                 (setf (gethash term candidates) (list term term))))))
         (loop for (oa . others) on distinct do
           (dolist (ob others)
             (push (cons oa ob) pairs)))))
     buckets)
    (nreverse pairs)))

(defun relax-candidate-patterns (candidates per-tree-occs inputs &optional ledger)
  "Generalise each candidate pattern over the trees it does not match: tree by tree, anti-unify
its witnesses with the occurrence of that tree that saves the most bits, and record every
pattern relaxed this way as a further candidate."
  (let ((seeds nil))
    (maphash (lambda (pattern witnesses) (push (cons pattern witnesses) seeds)) candidates)
    (dolist (seed (nreverse seeds))
      (let ((pattern (car seed))
            (witnesses (cdr seed)))
        (loop for occs across per-tree-occs
              for sort = (term-sort pattern inputs)
              unless (some (lambda (occ)
                             (and (equal (tree-occurrence-sort occ) sort)
                                  (nth-value 1 (match-pattern pattern (tree-occurrence-term occ)
                                                              inputs ledger))))
                           occs)
                do (let ((best-relaxed nil)
                         (best-witnesses nil)
                         (best-saved 0))
                     (dolist (occ occs)
                       (when (and (equal (tree-occurrence-sort occ) sort)
                                  (equal (tree-occurrence-signature occ)
                                         (and (app-p pattern) (term-sort (first pattern) inputs))))
                         (let ((extended (append witnesses (list (tree-occurrence-term occ)))))
                           (multiple-value-bind (relaxed substitutions)
                               (anti-unify extended inputs ledger)
                             (unless (trivial-subexpression-pattern-p relaxed)
                               (let ((saved (occurrence-saved-bits occ (car (last substitutions)) inputs)))
                                 (when (> saved best-saved)
                                   (setf best-saved saved
                                         best-relaxed relaxed
                                         best-witnesses extended))))))))
                     (when best-relaxed
                       (setf pattern best-relaxed
                             witnesses best-witnesses)
                       (unless (gethash pattern candidates)
                         (setf (gethash pattern candidates) witnesses)))))))))

(defun best-matching-occurrence (pattern occs inputs &optional ledger)
  "The occurrence among OCCS whose match with PATTERN saves the most bits, preferring the
smaller term and then the earlier occurrence among equals; nil when none matches."
  (let ((sort (term-sort pattern inputs))
        (matches nil)) ; (occurrence saved-bits) for every match, latest first
    (dolist (occ occs)
      (when (equal (tree-occurrence-sort occ) sort)
        (multiple-value-bind (substitution matched-p)
            (match-pattern pattern (tree-occurrence-term occ) inputs ledger)
          (when matched-p
            (push (list occ (occurrence-saved-bits occ substitution inputs)) matches)))))
    (first (best-by (nreverse matches)
                    (list :desc #'second)
                    (lambda (match) (body-size (tree-occurrence-term (first match)) inputs))))))

(defun score-candidate-selections (candidates per-tree-occs inputs &optional ledger)
  "Select occurrences to factor: first the root of every tree, then for each candidate pattern
its best match in every tree that has one. Tighten each new selection of two or more occurrences
by anti-unification and return the resulting unpriced abstractions in that order."
  (let ((n (length per-tree-occs))
        (seen (make-hash-table :test #'equal)) ; (kind . paths) of every selection scored so far
        (scored nil))
    (flet ((score (kind occurrences)
             (let* ((paths (loop for i below n
                                 for occ = (find i occurrences :key #'tree-occurrence-tree-index)
                                 collect (if occ (tree-occurrence-path occ) :none)))
                    (key (cons kind paths)))
               (unless (or (< (length occurrences) 2) (gethash key seen))
                 (setf (gethash key seen) t)
                 (multiple-value-bind (pattern substitutions)
                     (anti-unify (mapcar #'tree-occurrence-term occurrences) inputs ledger)
                   (push (make-subexpression-abstraction
                          :kind kind :pattern pattern :substitutions substitutions :paths paths
                          :structural-score (abstraction-structural-score pattern occurrences
                                                                          substitutions inputs))
                         scored))))))
      (when (> n 1)
        (score :aligned-root (map 'list #'first per-tree-occs)))
      (maphash (lambda (pattern witnesses)
                 (declare (ignore witnesses))
                 (score :subexpression
                        (loop for occs across per-tree-occs
                              for best = (best-matching-occurrence pattern occs inputs ledger)
                              when best collect best)))
               candidates))
    (nreverse scored)))

(defun price-abstraction (abstraction model literal-bits)
  "Record MODEL as the corpus model of ABSTRACTION, with its exact size and its gain over a
literal corpus of LITERAL-BITS."
  (let ((bits (description-size model nil)))
    (setf (subexpression-abstraction-model abstraction) model
          (subexpression-abstraction-bits abstraction) bits
          (subexpression-abstraction-literal-bits abstraction) literal-bits
          (subexpression-abstraction-gain abstraction) (- literal-bits bits))
    abstraction))

(defun discover-subexpression-abstractions (trees inputs &key domain rewrite-library
                                                           (schedule :canonical) pair-budget locality-key ledger)
  "Search for shared subexpression abstractions across TREES (even when occurrence
paths are hidden under different outer wrappers or unrelated control trees are present).
Supports :SCHEDULE (:CANONICAL, :LOCALITY with 1-in-4 canonical reserve, or :LOCALITY-ONLY),
optional :PAIR-BUDGET, and optional :LOCALITY-KEY (priced on LEDGER).
Returns (VALUES best-compression best-structural proposals corpus normalized-trees)."
  (let* ((inputs (input-alist inputs))
         (trees (if rewrite-library
                    (normalize-trees-with-library trees inputs rewrite-library :ledger ledger)
                    trees))
         (corpus (make-tree-corpus trees inputs :domain domain :ledger ledger))
         (n (length trees))
         (unfactored (make-list n :initial-element :none))
         (candidates (make-hash-table :test #'equal))) ; pattern -> witness terms, in discovery order
    (multiple-value-bind (tree-pos labels-vec) (compute-tree-locality-positions n locality-key ledger)
      (let* ((literal-model (corpus-literal-model corpus ledger))
             (literal-bits (description-size literal-model nil))
             (literal (price-abstraction (make-subexpression-abstraction :kind :literal :paths unfactored)
                                         literal-model literal-bits))
             (dictionary (price-abstraction (make-subexpression-abstraction :kind :dictionary :paths unfactored)
                                            (corpus-dictionary-model corpus ledger) literal-bits)))
        (multiple-value-bind (per-tree-occs buckets) (index-tree-occurrences trees inputs ledger)
          ;; Candidate patterns: repeated terms, the LGG of every scheduled occurrence pair, their
          ;; relaxations over further trees, and the aligned LGG of the whole trees.
          (dolist (pair (schedule-occurrence-pairs
                         (candidate-occurrence-pairs buckets candidates
                                                     (and (null pair-budget) (eq schedule :canonical)))
                         tree-pos schedule pair-budget ledger labels-vec))
            (let* ((terms (list (tree-occurrence-term (car pair)) (tree-occurrence-term (cdr pair))))
                   (pattern (anti-unify terms inputs ledger)))
              (unless (or (trivial-subexpression-pattern-p pattern) (gethash pattern candidates))
                (setf (gethash pattern candidates) terms))))
          (when (and (null pair-budget) (not (eq schedule :locality-only)))
            (relax-candidate-patterns candidates per-tree-occs inputs ledger))
          (when (> n 1)
            (let ((root-pattern (anti-unify trees inputs ledger)))
              (unless (gethash root-pattern candidates)
                (setf (gethash root-pattern candidates) trees))))
          ;; Price the aligned root and the eight structurally best subexpression selections.
          (let* ((subexpressions 0)
                 (priced
                   (loop for abstraction in (stable-sort (score-candidate-selections
                                                          candidates per-tree-occs inputs ledger)
                                                         #'> :key #'subexpression-abstraction-structural-score)
                         when (or (eq :aligned-root (subexpression-abstraction-kind abstraction))
                                  (<= (incf subexpressions) 8))
                           collect (price-abstraction
                                    abstraction
                                    (corpus-abstraction-model
                                     corpus (subexpression-abstraction-pattern abstraction)
                                     (subexpression-abstraction-paths abstraction)
                                     (subexpression-abstraction-substitutions abstraction) ledger)
                                    literal-bits)))
                 (proposals (list* dictionary literal priced))
                 (best-compression
                   (best-by proposals #'subexpression-abstraction-bits
                            (list :desc #'subexpression-abstraction-structural-score)))
                 (best-structural
                   (or (best-by (remove-if (lambda (pattern) (or (null pattern) (hole-p pattern)))
                                           proposals :key #'subexpression-abstraction-pattern)
                                (list :desc #'subexpression-abstraction-structural-score)
                                #'subexpression-abstraction-bits)
                       best-compression)))
            (values best-compression best-structural proposals corpus trees)))))))
