(in-package #:lisploop)

;;; Module 6: factor.lisp
;;; First-order matching, anti-unification, bounded fiber proposals (infer-fibers),
;;; heuristic condensation (condense-heuristic), and law corpus compression.

(defun pattern-has-holes-p (term)
  (case (ast-kind term)
    (:hole t)
    (:app (or (pattern-has-holes-p (first term))
              (some #'pattern-has-holes-p (rest term))))
    (otherwise nil)))

(defun term-sort (term inputs)
  (if (operator-p term)
      (operator-type term)
      (expression-type term inputs t)))

(defun match-pattern (pattern source &optional inputs ledger)
  "Typed first-order matching, including symbols in operator position.
Return substitutions and a success flag; NIL substitutions can be a valid match."
  (unless (equal (term-sort pattern inputs) (term-sort source inputs))
    (return-from match-pattern (values nil nil)))
  (let ((substitutions nil))
    (labels ((walk (p s)
               (charge ledger :matching)
               (cond
                 ((hole-p p)
                  (and (equal (ast-type p) (term-sort s inputs))
                       (let ((entry (assoc (ast-id p) substitutions)))
                         (if entry (equal (cdr entry) s)
                             (progn (push (cons (ast-id p) s) substitutions) t)))))
                 ((equal p s) t)
                 ((and (app-p p) (app-p s)
                       (= (length (rest p)) (length (rest s))))
                  (and (walk (first p) (first s))
                       (every #'walk (rest p) (rest s))))
                 (t nil))))
      (let ((success (walk pattern source)))
        (values (and success (nreverse substitutions)) success)))))

(defun anti-unify (sources &optional inputs ledger)
  "Aligned typed syntactic LGG. Equal disagreement tuples reuse the same hole.
An incompatible operator signature falls back to a whole-expression hole if the
result types agree. Distinct result types have no common typed AST pattern."
  (assert sources)
  (let ((disagreements (make-hash-table :test #'equal)) (next-id 0))
    (labels ((generalize (terms)
               (charge ledger :anti-unification (length terms))
               (let ((sorts (mapcar (lambda (term) (term-sort term inputs)) terms)))
                 (assert (every (lambda (sort) (equal sort (first sorts))) sorts))
                 (cond
                   ((every (lambda (term) (equal term (first terms))) terms) (first terms))
                   ((and (every #'app-p terms)
                         (let ((signatures (mapcar (lambda (term) (operator-type (first term))) terms)))
                           (every (lambda (signature) (equal signature (first signatures))) signatures)))
                    (apply #'app (generalize (mapcar #'first terms))
                           (loop for i below (length (rest (first terms))) collect
                             (generalize (mapcar (lambda (term) (nth i (rest term))) terms)))))
                   (t (or (gethash terms disagreements)
                          (setf (gethash terms disagreements)
                                (hole (prog1 next-id (incf next-id)) (first sorts)))))))))
      (let ((pattern (generalize sources)))
        (values pattern
                (mapcar (lambda (source)
                          (multiple-value-bind (substitution matched)
                              (match-pattern pattern source inputs ledger)
                            (assert matched)
                            substitution)) sources))))))

(defun compile-au-constructor (pattern scope &optional ledger)
  "A DSL program maps quoted hole fillings to the instantiated quoted expression.
Operator holes are quoted operator values, not callable host functions."
  (let ((inputs nil))
    (labels ((walk (term)
               (charge ledger :au-lowering (syntax-work term))
               (let ((type (code-type scope (term-sort term scope))))
                 (cond
                   ((hole-p term)
                    (let ((previous (assoc (ast-id term) inputs)))
                      (when previous (assert (equal (cdr previous) type)))
                      (unless previous (push (cons (ast-id term) type) inputs)))
                    (var (ast-id term) type))
                   ((not (pattern-has-holes-p term)) (lit type term))
                   (t
                    (let* ((operator-sort (term-sort (first term) scope))
                           (operator-code (code-type scope operator-sort))
                           (arguments (apply #'tuple-type
                                             (mapcar (lambda (sort) (code-type scope sort)) (second operator-sort)))))
                      (app (op :code-apply operator-code) (walk (first term))
                           (apply #'app (op :tuple arguments) (mapcar #'walk (rest term))))))))))
      (let ((model (walk pattern)))
        (charge ledger :construction (syntax-work model))
        (values model (nreverse inputs))))))

(defun term-references-bound-or-self-p (term bound-vars self-name)
  "True when TERM references any variable ID in BOUND-VARS or calls SELF-NAME."
  (cond
    ((var-p term) (not (null (member (ast-id term) bound-vars :test #'eql))))
    ((app-p term)
     (or (and self-name (operator-p (first term))
              (eq (canonical-op-name self-name) (operator-name (first term))))
         (some (lambda (arg) (term-references-bound-or-self-p arg bound-vars self-name))
               (rest term))))
    (t nil)))

(defun shared-subterm-cover (terms inputs &key bound-vars self-name)
  "Extract an ordered list of subterms A_0, ..., A_{m-1} from TERMS that cover all
references to BOUND-VARS (defaulting to all IDs in INPUTS) and SELF-NAME so each term
in TERMS can be abstracted into a closed :code literal over positional variables X0..X_{m-1}."
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (eff-vars (or bound-vars (mapcar #'car norm-inputs)))
         (eff-self (when self-name (canonical-op-name self-name)))
         (common-set (make-hash-table :test #'equal))
         (cover nil))
    (labels ((collect-subterms (node table)
               (when (term-references-bound-or-self-p node eff-vars eff-self)
                 (setf (gethash node table) t)
                 (when (app-p node)
                   (dolist (arg (rest node))
                     (collect-subterms arg table)))))
             (atomic-bound-unit-p (node)
               (or (and (var-p node) (member (ast-id node) eff-vars :test #'eql))
                   (and (app-p node) (operator-p (first node))
                        (let ((op-name (operator-name (first node))))
                          (or (and eff-self (eq op-name eff-self) (gethash node common-set))
                              (and (eq op-name :tail)
                                   (var-p (second node))
                                   (member (ast-id (second node)) eff-vars :test #'eql))
                              (and (eq op-name :at)
                                   (var-p (second node))
                                   (member (ast-id (second node)) eff-vars :test #'eql)
                                   (not (term-references-bound-or-self-p (third node) eff-vars eff-self))))))))
             (atomic-units (expr)
               (let ((acc nil))
                 (labels ((walk (n)
                            (when (term-references-bound-or-self-p n eff-vars eff-self)
                              (if (atomic-bound-unit-p n)
                                  (pushnew n acc :test #'equal)
                                  (when (app-p n)
                                    (dolist (arg (rest n))
                                      (walk arg)))))))
                   (walk expr)
                   (nreverse acc)))))
      (when terms
        (let ((tables (mapcar (lambda (term)
                                (let ((tbl (make-hash-table :test #'equal)))
                                  (collect-subterms term tbl)
                                  tbl))
                              terms)))
          (maphash (lambda (sub present)
                     (declare (ignore present))
                     (when (every (lambda (tbl) (gethash sub tbl)) (rest tables))
                       (setf (gethash sub common-set) t)))
                   (first tables))))
      (labels ((extract-from (node)
                 (when (term-references-bound-or-self-p node eff-vars eff-self)
                   (cond
                     ((and (gethash node common-set)
                           ;; Do not collapse the entire root term if all terms were supposed to diverge
                           (not (every (lambda (term) (equal node term)) terms))
                           ;; Keep shared subterm only if none of its atomic bound units appear outside it
                           (let ((node-units (atomic-units node))
                                 (dummy (let ((ntype (expression-type node norm-inputs)))
                                          (lit ntype (default-value-for-type ntype)))))
                             (and node-units
                                  (every (lambda (term)
                                           (let ((rem (replace-subexpression term node dummy)))
                                             (null (intersection node-units (atomic-units rem) :test #'equal))))
                                         terms))))
                      (pushnew node cover :test #'equal))
                     ((atomic-bound-unit-p node)
                      (pushnew node cover :test #'equal))
                     ((app-p node)
                      (dolist (arg (rest node))
                        (extract-from arg)))))))
        (dolist (term terms)
          (extract-from term))
        (stable-sort (nreverse cover)
                     (lambda (a b)
                       (and (not (term-references-bound-or-self-p a nil eff-self))
                            (term-references-bound-or-self-p b nil eff-self))))))))

(defun abstract-over-subterms (expr subterms inputs &optional ledger &key self-name)
  "Replace each subterm A_j in SUBTERMS within EXPR by positional variable `(var j type_j)`
and package the resulting closed body as `(lit (:code ((0 . type_0) ...) ret-type) body)`.
Returns (VALUES code-literal code-type body) or (VALUES nil nil nil) if EXPR still contains
unbound variables or self-calls outside SUBTERMS."
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (ret-type (expression-type expr norm-inputs))
         (eff-self (when self-name (canonical-op-name self-name)))
         (code-in (loop for sub in subterms
                        for j from 0
                        collect (cons j (expression-type sub norm-inputs))))
         (pairs (loop for sub in subterms
                      for (j . stype) in code-in
                      collect (cons sub (var j stype))))
         (unabstracted-p nil))
    (labels ((rewrite (node)
               (let ((match (assoc node pairs :test #'equal)))
                 (cond
                   (match (cdr match))
                   ((var-p node)
                    (setf unabstracted-p t)
                    node)
                   ((app-p node)
                    (when (and eff-self (operator-p (first node))
                               (eq eff-self (operator-name (first node))))
                      (setf unabstracted-p t))
                    (apply #'app (first node) (mapcar #'rewrite (rest node))))
                   (t node)))))
      (let ((body (rewrite expr)))
        (if unabstracted-p
            (values nil nil nil)
            (let ((c-type (code-type code-in ret-type)))
              (charge ledger :construction (syntax-work body))
              (values (lit c-type body) c-type body)))))))

;;; Operation 2.4: Optional Fiber Partition Proposals (infer-fibers)

(defstruct fiber-class
  (id 0 :type fixnum)
  requirement
  rows
  keys)

(defun tighten-same-input-requirements (frame &optional ledger (budget 10000))
  "Intersect only identical COMPLETE input tuples, including zero-input problems.
Projection onto fewer inputs is a separate synthesis hypothesis."
  (let* ((target (schema-target (frame-schema frame)))
         (rows (frame-rows frame))
         (requirements (map 'vector (lambda (row)
                                     (fold-constants (row-requirement row) nil
                                                     :ledger ledger :budget budget)) rows))
         (groups (make-hash-table :test #'equal)))
    (loop for row in rows for i from 0
          unless (member :unresolved (row-known row))
            do (push i (gethash (row-known row) groups)))
    (maphash (lambda (known indices)
               (declare (ignore known))
               (let ((joint (aref requirements (first indices))))
                 (dolist (i (rest indices))
                   (charge ledger :fiber-inference)
                   (setf joint (conjoin-requirements joint (aref requirements i) target
                                                    :ledger ledger :budget budget)))
                 (dolist (i indices) (setf (aref requirements i) joint)))) groups)
    requirements))

(defstruct req-group
  requirement
  indices
  (count 0 :type fixnum))

(defun %infer-fibers (frame ledger budget branch-limit)
  "Bounded partition proposals over requirements not yet refuted.
Intersect identical complete inputs, then rank partitions by class count,
repeated requirement bits, and concentration. This proxy is neither an exact
model code length nor Shannon entropy; an unresolved intersection is not a witness."
  (let* ((schema (frame-schema frame))
         (target-type (schema-target schema))
         (target-inputs (list (cons 0 target-type)))
         (rows-vec (coerce (frame-rows frame) 'vector))
         (n (length rows-vec))
         (folded-reqs (tighten-same-input-requirements frame ledger budget))
         (groups nil)
         (unsat-indices nil)
         (assignments (make-array n :initial-element nil)))
    ;; 1. Deduplicate identical requirements not structurally refuted.
    (loop for i below n
          for req = (aref folded-reqs i)
          do (if (unsatisfiable-requirement-p req)
                 (push i unsat-indices)
                 (let ((existing (find req groups :key #'req-group-requirement :test #'equal)))
                   (if existing
                       (progn
                         (push i (req-group-indices existing))
                         (incf (req-group-count existing)))
                       (push (make-req-group :requirement req :indices (list i) :count 1)
                             groups)))))
    (setf groups (nreverse groups)
          unsat-indices (nreverse unsat-indices))
    (dolist (g groups)
      (setf (req-group-indices g) (nreverse (req-group-indices g))))
    ;; Order constrained groups before unconstrained `'t` groups, then by ascending body-size
    (setf groups
          (stable-sort groups
                       (lambda (g1 g2)
                         (let ((u1 (unconstrained-requirement-p (req-group-requirement g1)))
                               (u2 (unconstrained-requirement-p (req-group-requirement g2))))
                           (if (not (eq u1 u2))
                               (not u1)
                               (< (body-size (req-group-requirement g1) target-inputs)
                                  (body-size (req-group-requirement g2) target-inputs)))))))
    ;; 2. Bounded branch-and-bound search under the declared lexicographic proxy.
    (let ((u (length groups))
          (groups-vec (coerce groups 'vector))
          (best-classes (mapcar (lambda (g) (list (req-group-requirement g)
                                                 (copy-list (req-group-indices g)))) groups))
          (best-k (length groups))
          (best-bits most-positive-fixnum)
          (best-conc -1)
          (branches 0)
          (max-branches branch-limit))
      (labels ((partition-better-p (k bits conc)
                 (or (< k best-k)
                     (and (= k best-k)
                          (or (< bits best-bits)
                              (and (= bits best-bits)
                                   (> conc best-conc))))))
               (dfs (g-idx current-classes)
                 (when (> (incf branches) max-branches)
                   (return-from dfs))
                 (let ((k (length current-classes)))
                   (when (> k best-k)
                     (return-from dfs))
                   (if (= g-idx u)
                       (let ((total-bits 0)
                             (conc 0))
                         (dolist (c current-classes)
                           (let* ((c-req (first c))
                                  (c-rows (second c))
                                  (cnt (length c-rows)))
                             (incf total-bits (* cnt (body-size c-req target-inputs)))
                             (incf conc (* cnt cnt))))
                         (when (partition-better-p k total-bits conc)
                           (setf best-k k
                                 best-bits total-bits
                                 best-conc conc
                                 best-classes (mapcar (lambda (c)
                                                        (list (first c) (copy-list (second c))))
                                                      current-classes))))
                       (let* ((g (aref groups-vec g-idx))
                              (g-req (req-group-requirement g))
                              (g-rows (req-group-indices g)))
                         ;; Branch A: merge group `g` into each compatible existing class
                         (loop for pos from 0
                               for c in current-classes
                               for c-req = (first c)
                               do (charge ledger :fiber-inference)
                                  (let ((joint (conjoin-requirements c-req g-req target-type
                                                                     :ledger ledger :budget budget)))
                                    (unless (unsatisfiable-requirement-p joint)
                                      (let ((next-classes
                                              (loop for elem in current-classes
                                                    for idx from 0
                                                    collect (if (= idx pos)
                                                                (list joint (append (second elem) g-rows))
                                                                elem))))
                                        (dfs (1+ g-idx) next-classes)))))
                         ;; Branch B: nucleate a new class for group `g` (if within K bound)
                         (when (< k best-k)
                           (dfs (1+ g-idx)
                                (append current-classes
                                        (list (list g-req (copy-list g-rows)))))))))))
        (dfs 0 nil))
      ;; 3. Assemble `fiber-class` records (including any isolated unsatisfiable rows)
      (let ((classes
              (append (loop for c in best-classes
                            for idx from 0
                            collect (make-fiber-class :id idx
                                                      :requirement (first c)
                                                      :rows (second c)))
                      (loop for u-idx in unsat-indices
                            for idx from (length best-classes)
                            collect (make-fiber-class :id idx
                                                      :requirement (aref folded-reqs u-idx)
                                                      :rows (list u-idx))))))
        ;; Canonicalize class ordering and IDs by first-appearance row index in FRAME
        (setf classes (sort classes #'< :key (lambda (c) (reduce #'min (fiber-class-rows c)))))
        (loop for class in classes
              for new-id from 0
              do (setf (fiber-class-id class) new-id
                       (fiber-class-rows class) (sort (copy-list (fiber-class-rows class)) #'<)
                       (fiber-class-keys class) (mapcar (lambda (i) (row-key (aref rows-vec i)))
                                                        (fiber-class-rows class)))
                 (dolist (r-idx (fiber-class-rows class))
                   (setf (aref assignments r-idx) new-id)))
        ;; Build final labels, refined frame (with computed intra-fiber pairs & cross-fiber anchors), and row partition
        (let* ((labels (coerce assignments 'list))
               (part (partition-rows (frame-rows frame) labels ledger))
               (refined-rows
                 (loop for i below n
                       for row = (aref rows-vec i)
                       for cid = (aref assignments i)
                       for class = (nth cid classes)
                       collect (make-row :key (copy-tree (row-key row))
                                         :known (copy-tree (row-known row))
                                         :requirement (copy-tree (fiber-class-requirement class))))))
          (multiple-value-bind (inferred-pairs inferred-anchors)
              (partition-pairs-and-anchors part nil ledger)
            (let ((refined-frame (make-frame (copy-schema schema) refined-rows
                                             :pairs (or (frame-pairs frame) inferred-pairs)
                                             :anchors (or (frame-anchors frame) inferred-anchors))))
              (values classes labels refined-frame part
                      (make-message :claim :partition-proposal
                                    :evidence (list :search-status (if (> branches max-branches) :cutoff :complete)
                                                    :branches branches :feasibility :unresolved
                                                    :objective :lexicographic-proxy))))))))))

(defun infer-fibers (frame &optional ledger (budget 1000000) (branch-limit 2048))
  "Optional bounded partition proposal. Unknown satisfiability is never a certificate.
The fifth value reports work/branch cutoff; BUDGET covers this whole invocation."
  (assert (and (integerp budget) (>= budget 0) (integerp branch-limit) (>= branch-limit 0)))
  (let ((ledger (or ledger (make-ledger))))
    (with-work-limit (ledger budget
                      (values nil nil nil nil (make-message :claim :cutoff
                                              :evidence (list :work (ledger-total ledger) :feasibility :unresolved))))
      (%infer-fibers frame ledger budget branch-limit))))

(defun fiber-pairs-and-anchors (frame &optional ledger (budget 1000000))
  "Compute intra-fiber must-agree `pairs` and cross-fiber must-vary `anchors` from FRAME
via `infer-fibers`. Returns (VALUES pairs anchors refined-frame classes labels partition)."
  (multiple-value-bind (classes labels refined-frame part status)
      (infer-fibers frame ledger budget)
    (unless refined-frame (return-from fiber-pairs-and-anchors (values nil nil nil nil nil nil status)))
    (values (frame-pairs refined-frame)
            (frame-anchors refined-frame)
            refined-frame
            classes
            labels
            part)))

;;; Operation 4: Heuristic Condensation (condense-heuristic)

(defstruct (heuristic-model (:conc-name heuristic-))
  program
  residual
  (unresolved-keys nil)
  (exact-p nil :type boolean)
  (total-p t :type boolean)
  (program-bits 0 :type fixnum)
  (residual-bits 0 :type fixnum)
  (run-work 0 :type fixnum)
  (score 0)
  (alternatives nil))

(defun condense-heuristic (frame language &key description-limit (work-limit 100000) (run-weight 0) stop-on-exact-p ledger)
  "Budgeted selector approximation on ORIGINAL requirements; residuals are training costs.
Return the best completed model and an informative completion/cutoff message."
  (let* ((job (start-heuristic-search frame language :description-limit description-limit
                                     :run-weight run-weight
                                     :stop-on-exact-p stop-on-exact-p))
         (message (resume-heuristic-search job (remaining-work ledger work-limit)))
         (best (heuristic-search-best job)))
    (charge ledger :heuristic-search (ledger-total (heuristic-search-ledger job)))
    (when (and best (heuristic-search-models job))
      (let ((ordered (stable-sort (copy-list (reverse (heuristic-search-models job)))
                                  (lambda (a b)
                                    (or (< (heuristic-score a) (heuristic-score b))
                                        (and (= (heuristic-score a) (heuristic-score b))
                                             (< (heuristic-program-bits a) (heuristic-program-bits b))))))))
        (setf (heuristic-alternatives best)
              (remove best ordered :test #'eq))))
    (values best message)))

;;; Law Corpus Compression (M3B)

(defstruct (law-corpus (:constructor %make-law-corpus)) domain inputs laws packet)

(defun bits-as-values (bits)
  (map 'list (lambda (bit) (= bit 1)) bits))

(defun values-as-bits (values)
  (assert (value-p values (sequence-type :bool)))
  (map 'bit-vector (lambda (value) (if value 1 0)) values))

(defun collect-code-values (writer &optional ledger)
  (let ((values nil))
    (funcall writer (lambda (width value)
                      (charge ledger :packet-assembly width)
                      (loop for i downfrom (1- width) to 0 do
                        (push (logbitp i value) values))))
    (nreverse values)))

(defun law-corpus-type (domain)
  (tuple-type domain (sequence-type (sequence-type :bool))))

(defun encode-corpus-packet (trees inputs domain &optional ledger)
  (let* ((packets (mapcar (lambda (tree)
                            (charge ledger :corpus-encoding (syntax-work tree))
                            (collect-code-values (lambda (emit) (emit-bit-model tree inputs emit)) ledger))
                          trees))
         (literal (lit (law-corpus-type domain) (list 0 packets))))
    (collect-code-values (lambda (emit) (emit-bit-model literal nil emit)) ledger)))

(defun make-law-corpus (laws &optional ledger)
  "Snapshot one domain/schema's ordered statements, including duplicate occurrences.
Evidence/provenance are not part of this syntax-compression task."
  (assert laws)
  (let ((domain (law-domain (first laws))) (inputs (law-inputs (first laws))))
    (assert (every (lambda (law) (and (equal domain (law-domain law))
                                      (equal inputs (law-inputs law)))) laws))
    (let ((copies (mapcar (lambda (law)
                            (let ((eq-args (rest (law-equation law))))
                              (make-law domain inputs (first eq-args) (second eq-args)
                                        :guard (law-guard law))))
                          laws)))
      (%make-law-corpus :domain (copy-tree domain) :inputs (copy-tree inputs) :laws copies
                        :packet (encode-corpus-packet (mapcar #'law-statement copies)
                                                      inputs domain ledger)))))

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

(defun corpus-prefix (domain count &optional ledger)
  (collect-code-values
   (lambda (emit)
     (emit-bit-header nil (law-corpus-type domain) emit)
     (funcall emit 2 1)
     (emit-bit-value 0 domain emit)
     (emit-positive (1+ count) emit)) ledger))

(defun law-corpus-prefix (corpus &optional ledger)
  (corpus-prefix (law-corpus-domain corpus) (length (law-corpus-laws corpus)) ledger))

(defun au-packet-pieces (pattern inputs &optional ledger)
  (au-body-pieces pattern inputs :include-header-p t :ledger ledger))

(defun instantiate-packet-pieces (pieces substitution inputs &optional ledger)
  (mapcar
   (lambda (piece)
     (if (and (consp piece) (eq :fixed (first piece)))
         (second piece)
         (let ((entry (assoc (ast-id piece) substitution)))
           (assert entry)
           (assert (equal (ast-type piece) (term-sort (cdr entry) inputs)))
           (charge ledger :au-substitution (syntax-work (cdr entry)))
           (collect-code-values
            (lambda (emit)
              (if (operator-p (cdr entry))
                  (emit-operator (cdr entry) emit)
                  (emit-bit-expression (cdr entry) inputs (ast-type piece) emit)))
            ledger))))
   pieces))

(defun packet-chunks-model (chunks &optional ledger)
  "A normal closed VM program; its dictionary and full occurrence order are encoded."
  (multiple-value-bind (representatives residual) (quotient-values chunks ledger)
    (let ((model (app (op :concat :bool)
                      (quotient-model (sequence-type :bool) representatives residual ledger))))
      (charge ledger :construction (syntax-work model))
      model)))

(defun corpus-rows-model (prefix rows &optional ledger)
  (let ((chunks (list prefix)))
    (map nil (lambda (body)
               (let ((size (reduce #'+ body :key #'length)))
                 (push (collect-code-values (lambda (emit) (emit-positive (1+ size) emit)) ledger) chunks)
                 (dolist (piece body) (push piece chunks)))) rows)
    (packet-chunks-model (nreverse chunks) ledger)))

(defun law-row-pieces-model (corpus rows &optional ledger)
  (assert (= (length rows) (length (law-corpus-laws corpus))))
  (corpus-rows-model (law-corpus-prefix corpus ledger) rows ledger))

(defun law-template-model (corpus pattern substitutions &optional ledger)
  (assert (= (length substitutions) (length (law-corpus-laws corpus))))
  (let* ((inputs (law-corpus-inputs corpus))
         (pieces (au-packet-pieces pattern inputs ledger)))
    (law-row-pieces-model corpus (mapcar (lambda (substitution)
                                           (instantiate-packet-pieces pieces substitution inputs ledger))
                                         substitutions) ledger)))

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
  (let* ((inputs (law-corpus-inputs corpus)) (statements (mapcar #'law-statement (law-corpus-laws corpus)))
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
    (values (law-row-pieces-model corpus rows ledger) groups)))

(defun propose-law-compressions (corpus &optional ledger)
  "Four complete proposals: literal, whole-packet dictionary, global/grouped AU."
  (let* ((inputs (law-corpus-inputs corpus))
         (statements (mapcar #'law-statement (law-corpus-laws corpus)))
         (literal (lit (sequence-type :bool) (law-corpus-packet corpus)))
         (chunks (list (law-corpus-prefix corpus ledger))))
    (charge ledger :construction (syntax-work literal))
    (dolist (statement statements)
      (let ((packet (collect-code-values (lambda (emit) (emit-bit-model statement inputs emit)) ledger)))
        (push (append (collect-code-values (lambda (emit) (emit-positive (1+ (length packet)) emit)) ledger)
                      packet) chunks)))
    (multiple-value-bind (pattern substitutions) (anti-unify statements inputs ledger)
      (multiple-value-bind (grouped groups) (grouped-law-template-model corpus ledger)
        (values (list literal (packet-chunks-model (nreverse chunks) ledger)
                      (law-template-model corpus pattern substitutions ledger) grouped)
                pattern substitutions groups)))))

(defun law-corpus-frame (corpus &optional ledger)
  (let ((req (set-requirement (sequence-type :bool) (list (law-corpus-packet corpus)))))
    (charge ledger :corpus-frame (syntax-work req))
    (make-frame (make-schema :inputs nil :target (sequence-type :bool))
                (list (make-row :key :law-corpus :known nil :requirement req)))))

;;; Subexpression Occurrence Search & Corpus Abstraction (M6)

(defun patterns-isomorphic-p (pattern-a pattern-b &optional inputs ledger)
  "Check whether PATTERN-A and PATTERN-B are identical up to a sort-preserving
bijection (alpha-renaming) of hole IDs."
  (unless (equal (term-sort pattern-a inputs) (term-sort pattern-b inputs))
    (return-from patterns-isomorphic-p nil))
  (let ((forward nil)
        (reverse nil))
    (labels ((walk (a b)
               (charge ledger :matching)
               (cond
                 ((and (hole-p a) (hole-p b))
                  (and (equal (ast-type a) (ast-type b))
                       (let ((f-entry (assoc (ast-id a) forward))
                             (r-entry (assoc (ast-id b) reverse)))
                         (cond
                           ((and f-entry r-entry)
                            (and (= (cdr f-entry) (ast-id b))
                                 (= (cdr r-entry) (ast-id a))))
                           ((or f-entry r-entry) nil)
                           (t
                            (push (cons (ast-id a) (ast-id b)) forward)
                            (push (cons (ast-id b) (ast-id a)) reverse)
                            t)))))
                 ((or (hole-p a) (hole-p b)) nil)
                 ((equal a b) t)
                 ((and (app-p a) (app-p b)
                       (= (length (rest a)) (length (rest b))))
                  (and (walk (first a) (first b))
                       (every #'walk (rest a) (rest b))))
                 (t nil))))
      (walk pattern-a pattern-b))))

(defun pattern-holes (pattern)
  "Return the ordered list of unique (hole-id . hole-sort) pairs in pre-order."
  (let ((holes nil))
    (labels ((walk (term)
               (cond
                 ((hole-p term)
                  (unless (assoc (ast-id term) holes)
                    (push (cons (ast-id term) (ast-type term)) holes)))
                 ((app-p term)
                  (walk (first term))
                  (mapc #'walk (rest term))))))
      (walk pattern)
      (nreverse holes))))

(defun pattern-hole-counts (pattern)
  "Return an alist (hole-id . multiplicity) for all holes in PATTERN."
  (let ((counts nil))
    (labels ((walk (term)
               (cond
                 ((hole-p term)
                  (let ((entry (assoc (ast-id term) counts)))
                    (if entry
                        (incf (cdr entry))
                        (push (cons (ast-id term) 1) counts))))
                 ((app-p term)
                  (walk (first term))
                  (mapc #'walk (rest term))))))
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
  signature
  wrapper
  (context-hole-id 999 :type fixnum))

(defun collect-tree-occurrences (tree inputs &key (tree-index 0) (context-hole-id 999) ledger)
  "Collect all subexpression occurrences in TREE in pre-order."
  (let ((occurrences nil))
    (labels ((walk (sub rev-path)
               (charge ledger :occurrence-enumeration)
               (let* ((path (nreverse (copy-list rev-path)))
                      (sort (expression-type sub inputs t))
                      (sig (and (app-p sub) (operator-type (first sub))))
                      (wrapper (replace-at-path tree path (hole context-hole-id sort) ledger)))
                 (push (make-tree-occurrence :tree-index tree-index
                                             :path path
                                             :term sub
                                             :sort sort
                                             :signature sig
                                             :wrapper wrapper
                                             :context-hole-id context-hole-id)
                       occurrences)
                 (when (app-p sub)
                   (loop for child in (rest sub)
                         for i from 0
                         do (walk child (cons i rev-path)))))))
      (walk tree nil)
      (nreverse occurrences))))

(defun au-substitutions-frame (pattern substitutions &key keys known inputs ledger)
  "Convert recovered AU SUBSTITUTIONS for PATTERN into an ordinary child frame
whose target is the tuple of quoted hole values `(:tuple (:code inputs hole-sort) ...)`.
When KNOWN is omitted, defaults each row's known input to its occurrence coordinate `(idx)`."
  (let* ((holes (pattern-holes pattern))
         (hole-code-types (mapcar (lambda (h) (code-type inputs (cdr h))) holes))
         (target-type (apply #'tuple-type hole-code-types))
         (effective-known (or known
                              (loop for i below (length substitutions)
                                    collect (list i))))
         (schema-inputs (when (first effective-known)
                          (loop for v in (first effective-known)
                                for i from 0
                                collect (cons i :int))))
         (rows
           (loop for subst in substitutions
                 for idx from 0
                 for key = (if keys (nth idx keys) idx)
                 for row-known = (nth idx effective-known)
                 for tuple-val = (mapcar (lambda (h)
                                           (let ((entry (assoc (car h) subst)))
                                             (assert entry () "Missing binding for hole ~S" (car h))
                                             (cdr entry)))
                                         holes)
                 for req = (set-requirement target-type (list tuple-val))
                 do (charge ledger :au-child-frame (syntax-work req))
                 collect (make-row :key key :known row-known :requirement req))))
    (make-frame (make-schema :inputs schema-inputs :target target-type :lookup-p t) rows)))

(defstruct (tree-corpus (:constructor %make-tree-corpus))
  domain
  inputs
  sort
  trees
  packet)

(defun make-tree-corpus (trees inputs &key domain sort ledger)
  "Snapshot an ordered sequence of typed ASTs under INPUTS into a standalone bit packet."
  (assert trees)
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (inferred-sort (or sort (expression-type (first trees) norm-inputs)))
         (inferred-domain (or domain
                              (if (and (consp inferred-sort) (eq :gf (first inferred-sort)))
                                  inferred-sort
                                  (let ((gf-in (find-if (lambda (spec)
                                                          (and (consp (cdr spec)) (eq :gf (first (cdr spec)))))
                                                        norm-inputs)))
                                    (if gf-in (cdr gf-in) :int)))))
         (copies (mapcar #'copy-tree trees)))
    (dolist (tree copies)
      (assert (equal inferred-sort (expression-type tree norm-inputs))))
    (%make-tree-corpus :domain (copy-tree inferred-domain)
                       :inputs (copy-tree norm-inputs)
                       :sort (copy-tree inferred-sort)
                       :trees copies
                       :packet (encode-corpus-packet copies norm-inputs inferred-domain ledger))))

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

(defun tree-corpus-prefix (corpus &optional ledger)
  (corpus-prefix (tree-corpus-domain corpus) (length (tree-corpus-trees corpus)) ledger))

(defun tree-corpus-frame (corpus &optional ledger)
  (let ((req (set-requirement (sequence-type :bool) (list (tree-corpus-packet corpus)))))
    (charge ledger :corpus-frame (syntax-work req))
    (make-frame (make-schema :inputs nil :target (sequence-type :bool))
                (list (make-row :key :tree-corpus :known nil :requirement req)))))

(defun au-body-pieces (pattern inputs &key include-header-p ledger)
  "Compile a typed AU pattern into fixed bit fragments and hole references.
When INCLUDE-HEADER-P is nil, omits the outer packet header so the body pieces
can be spliced at any occurrence path inside an outer wrapper."
  (let ((pieces nil) (fixed nil))
    (labels ((emit (width value)
               (charge ledger :packet-assembly width)
               (loop for i downfrom (1- width) to 0 do (push (logbitp i value) fixed)))
             (flush-fixed ()
               (when fixed (push (list :fixed (nreverse fixed)) pieces) (setf fixed nil)))
             (walk (term)
               (charge ledger :au-compilation (syntax-work term))
               (cond
                 ((hole-p term) (flush-fixed) (push term pieces))
                 ((operator-p term) (emit-operator term #'emit))
                 ((not (pattern-has-holes-p term))
                  (emit-bit-expression term inputs (expression-type term inputs) #'emit))
                 (t (assert (app-p term))
                    (emit 2 2) (walk (first term)) (mapc #'walk (rest term))))))
      (when include-header-p
        (emit-bit-header inputs (expression-type pattern inputs t) #'emit))
      (walk pattern)
      (flush-fixed)
      (nreverse pieces))))

(defun tree-occurrence-packet-pieces (tree path body-pieces substitution inputs &key header-in-body-p ledger)
  "Emit the ordered bit pieces of TREE when the subexpression at PATH is factored
through BODY-PIECES and SUBSTITUTION. If PATH is :NONE, emits TREE as a single chunk."
  (let ((root-sort (expression-type tree inputs)))
    (cond
      ((eq path :none)
       (list (collect-code-values (lambda (emit) (emit-bit-model tree inputs emit)) ledger)))
      ((and (null path) header-in-body-p)
       (instantiate-packet-pieces body-pieces substitution inputs ledger))
      (t
       (let ((chunks nil)
             (fixed nil))
         (labels ((emit (width value)
                    (charge ledger :packet-assembly width)
                    (loop for i downfrom (1- width) to 0 do (push (logbitp i value) fixed)))
                  (flush-fixed ()
                    (when fixed
                      (push (nreverse fixed) chunks)
                      (setf fixed nil)))
                  (walk-wrapper (term rel-path expected-type)
                    (declare (ignore expected-type))
                    (if (null rel-path)
                        (progn
                          (flush-fixed)
                          (dolist (piece-bits (instantiate-packet-pieces body-pieces substitution inputs ledger))
                            (push piece-bits chunks)))
                        (let ((idx (first rel-path))
                              (operator (first term)))
                          (assert (app-p term))
                          (emit 2 2)
                          (emit-operator operator #'emit)
                          (loop for child in (rest term)
                                for child-type in (second (operator-type operator))
                                for k from 0
                                do (if (= k idx)
                                       (walk-wrapper child (rest rel-path) child-type)
                                       (emit-bit-expression child inputs child-type #'emit)))))))
           (emit-bit-header inputs root-sort #'emit)
           (walk-wrapper tree path root-sort)
           (flush-fixed)
           (nreverse chunks)))))))

(defun tree-row-pieces-model (corpus rows &optional ledger)
  (assert (= (length rows) (length (tree-corpus-trees corpus))))
  (corpus-rows-model (tree-corpus-prefix corpus ledger) rows ledger))

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
  sort
  occurrences
  substitutions
  wrappers
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

(defun occurrence-saved-bits (occ pattern substitution inputs)
  "Exact bit savings inside OCC's tree from factoring `(tree-occurrence-term occ)`
through PATTERN and unique hole bindings in SUBSTITUTION."
  (declare (ignore pattern))
  (let ((sub-bits (body-size (tree-occurrence-term occ) inputs))
        (unique-hole-bits
          (loop for (hole-id . hole-val) in substitution
                sum (term-body-bits hole-val inputs))))
    (- sub-bits unique-hole-bits)))

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
                       sum (occurrence-saved-bits occ pattern subst inputs))))
          (- total-saved fixed-bits)))))

(defun normalize-trees-with-library (trees inputs rewrite-library &key (budget 100000) ledger)
  "Normalize each tree in TREES using validated REWRITE-LIBRARY (or a `knowledge-library`) in the metered VM."
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (domain (infer-domain-from-types (mapcar #'cdr norm-inputs)))
         (eff-lib (if (and (knowledge-library-p rewrite-library) (fboundp 'as-rewrite-library))
                      (funcall 'as-rewrite-library rewrite-library :domain domain)
                      rewrite-library)))
    (if (null eff-lib)
        trees
        (mapcar (lambda (tree)
                  (let ((state (start-rewriting tree norm-inputs eff-lib)))
                    (advance-rewriting state budget)
                    (charge ledger :rewriting (rewriting-work state))
                    (if (eq :complete (rewriting-status state))
                        (rewriting-value state)
                        tree)))
                trees))))

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
        (let* ((indices (loop for i below n collect i))
               (labels
                 (loop for i below n
                       collect (if (functionp locality-key)
                                   (progn
                                     (charge ledger :locality-key)
                                     (funcall locality-key i))
                                   (let ((run (evaluate locality-key '((0 . :int)) (list i) :ledger ledger)))
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
  (if (and (eq schedule :canonical) (null pair-budget))
      canonical-pairs
      (flet ((pair-cross-tree-p (p)
               (/= (tree-occurrence-tree-index (car p))
                   (tree-occurrence-tree-index (cdr p))))
             (pair-rank-dist (p)
               (abs (- (aref tree-pos (tree-occurrence-tree-index (car p)))
                       (aref tree-pos (tree-occurrence-tree-index (cdr p))))))
             (pair-tree-dist (p)
               (let* ((ia (tree-occurrence-tree-index (car p)))
                      (ib (tree-occurrence-tree-index (cdr p)))
                      (rdist (abs (- (aref tree-pos ia) (aref tree-pos ib)))))
                 (if labels-vec
                     (generated-space-distance (aref labels-vec ia) (aref labels-vec ib) rdist)
                     rdist)))
             (pair-path-dist (p)
               (abs (- (length (tree-occurrence-path (car p)))
                       (length (tree-occurrence-path (cdr p))))))
             (pair-depth-sum (p)
               (+ (length (tree-occurrence-path (car p)))
                  (length (tree-occurrence-path (cdr p))))))
        (ecase schedule
          (:canonical
           (if pair-budget
               (subseq canonical-pairs 0 (min pair-budget (length canonical-pairs)))
               canonical-pairs))
          (:locality-only
           (let* ((local-pairs
                    (remove-if-not (lambda (p)
                                     (and (pair-cross-tree-p p)
                                          (<= (pair-tree-dist p) 1)))
                                   canonical-pairs))
                  (sorted (stable-sort (copy-list local-pairs)
                                       (lambda (a b)
                                         (let ((da (pair-tree-dist a))
                                               (db (pair-tree-dist b)))
                                           (if (/= da db)
                                               (< da db)
                                               (let ((ra (pair-rank-dist a))
                                                     (rb (pair-rank-dist b)))
                                                 (if (/= ra rb)
                                                     (< ra rb)
                                                     (let ((pa (pair-path-dist a))
                                                           (pb (pair-path-dist b)))
                                                       (if (/= pa pb)
                                                           (< pa pb)
                                                           (< (pair-depth-sum a) (pair-depth-sum b))))))))))))
             (charge ledger :locality-scheduling (length sorted))
             (if pair-budget
                 (subseq sorted 0 (min pair-budget (length sorted)))
                 sorted)))
          (:locality
           (let* ((loc-queue
                    (stable-sort (copy-list canonical-pairs)
                                 (lambda (a b)
                                   (let ((ca (pair-cross-tree-p a))
                                         (cb (pair-cross-tree-p b)))
                                     (if (not (eq ca cb))
                                         ca
                                         (let ((da (pair-tree-dist a))
                                               (db (pair-tree-dist b)))
                                           (if (/= da db)
                                               (< da db)
                                               (let ((ra (pair-rank-dist a))
                                                     (rb (pair-rank-dist b)))
                                                 (if (/= ra rb)
                                                     (< ra rb)
                                                     (let ((pa (pair-path-dist a))
                                                           (pb (pair-path-dist b)))
                                                       (if (/= pa pb)
                                                           (< pa pb)
                                                           (< (pair-depth-sum a) (pair-depth-sum b)))))))))))))
                  (can-queue (copy-list canonical-pairs))
                  (seen (make-hash-table :test #'equal))
                  (selected nil)
                  (limit (or pair-budget (length canonical-pairs)))
                  (turn 0))
             (loop while (and (< (length selected) limit)
                              (or loc-queue can-queue))
                   do (charge ledger :locality-scheduling)
                      (let* ((reserve-p (= 3 (mod turn 4)))
                             (next-pair nil))
                        (incf turn)
                        (if reserve-p
                            (loop while can-queue
                                  for cand = (pop can-queue)
                                  unless (gethash cand seen)
                                  do (setf next-pair cand) (return))
                            (loop while loc-queue
                                  for cand = (pop loc-queue)
                                  unless (gethash cand seen)
                                  do (setf next-pair cand) (return)))
                        (unless next-pair
                          (loop while loc-queue
                                for cand = (pop loc-queue)
                                unless (gethash cand seen)
                                do (setf next-pair cand) (return))
                          (unless next-pair
                            (loop while can-queue
                                  for cand = (pop can-queue)
                                  unless (gethash cand seen)
                                  do (setf next-pair cand) (return))))
                        (when next-pair
                          (setf (gethash next-pair seen) t)
                          (push next-pair selected))))
             (nreverse selected)))))))

(defun discover-subexpression-abstractions (trees inputs &key domain rewrite-library
                                                           (schedule :canonical) pair-budget locality-key ledger)
  "Search for shared subexpression abstractions across TREES (even when occurrence
paths are hidden under different outer wrappers or unrelated control trees are present).
Supports :SCHEDULE (:CANONICAL, :LOCALITY with 1-in-4 canonical reserve, or :LOCALITY-ONLY),
optional :PAIR-BUDGET, and optional :LOCALITY-KEY (priced on LEDGER).
Returns (VALUES best-compression best-structural proposals corpus normalized-trees)."
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (active-trees (if rewrite-library
                           (normalize-trees-with-library trees norm-inputs rewrite-library :ledger ledger)
                           trees))
         (corpus (make-tree-corpus active-trees norm-inputs :domain domain :ledger ledger))
         (n (length active-trees)))
    (multiple-value-bind (tree-pos labels-vec)
        (compute-tree-locality-positions n locality-key ledger)
      (let* ((literal-model (lit (sequence-type :bool) (tree-corpus-packet corpus)))
         (literal-bits (description-size literal-model nil))
         (dict-chunks (cons (tree-corpus-prefix corpus ledger)
                            (loop for tree in active-trees
                                  for pkt = (collect-code-values
                                             (lambda (emit) (emit-bit-model tree norm-inputs emit))
                                             ledger)
                                  collect (append (collect-code-values
                                                   (lambda (emit) (emit-positive (1+ (length pkt)) emit))
                                                   ledger)
                                                  pkt))))
         (dict-model (packet-chunks-model dict-chunks ledger))
         (dict-bits (description-size dict-model nil))
         (proposals
           (list (make-subexpression-abstraction
                  :kind :literal
                  :pattern nil
                  :sort (tree-corpus-sort corpus)
                  :paths (make-list n :initial-element :none)
                  :model literal-model
                  :bits literal-bits
                  :literal-bits literal-bits
                  :gain 0
                  :structural-score 0)
                 (make-subexpression-abstraction
                  :kind :dictionary
                  :pattern nil
                  :sort (tree-corpus-sort corpus)
                  :paths (make-list n :initial-element :none)
                  :model dict-model
                  :bits dict-bits
                  :literal-bits literal-bits
                  :gain (- literal-bits dict-bits)
                  :structural-score 0)))
         (per-tree-occs (make-array n))
         (buckets (make-hash-table :test #'equal))
         (candidate-patterns (make-hash-table :test #'equal))
         (evaluated-selections (make-hash-table :test #'equal)))
    (charge ledger :construction (syntax-work literal-model))
    ;; 1. Collect and index all subexpression occurrences across all trees by (sort . signature)
    (loop for tree in active-trees
          for i from 0
          for occs = (collect-tree-occurrences tree norm-inputs :tree-index i :ledger ledger)
          do (setf (aref per-tree-occs i) occs)
             (dolist (occ occs)
               (let ((key (cons (tree-occurrence-sort occ)
                                (tree-occurrence-signature occ))))
                 (push occ (gethash key buckets)))))
    ;; 2. Generate candidate LGG patterns per (sort . signature) bucket
    (labels ((trivial-subexpression-pattern-p (pat)
               (or (hole-p pat)
                   (and (app-p pat)
                        (every #'hole-p pat)
                        (every (lambda (entry) (= 1 (cdr entry)))
                               (pattern-hole-counts pat))))))
      ;; 2a. Collect distinct subterms and candidate occurrence pairs across buckets
      (let ((all-canonical-pairs nil))
        (maphash
         (lambda (bucket-key occs)
           (declare (ignore bucket-key))
           (let ((rev-occs (nreverse occs))
                 (distinct-occs nil)
                 (term-counts (make-hash-table :test #'equal)))
             (dolist (o rev-occs)
               (let ((term (tree-occurrence-term o)))
                 (when (zerop (gethash term term-counts 0))
                   (push o distinct-occs))
                 (incf (gethash term term-counts 0))))
             (setf distinct-occs (nreverse distinct-occs))
             ;; Exact repeated subterms (when unconstrained by pair-budget or locality-only schedule)
             (when (and (null pair-budget) (eq schedule :canonical))
               (dolist (o distinct-occs)
                 (let ((term (tree-occurrence-term o)))
                   (when (and (> (gethash term term-counts 0) 1)
                              (not (trivial-subexpression-pattern-p term))
                              (not (gethash term candidate-patterns)))
                     (setf (gethash term candidate-patterns) (list term term))))))
             (loop for tail on distinct-occs
                   for oa = (first tail)
                   do (dolist (ob (rest tail))
                        (push (cons oa ob) all-canonical-pairs)))))
         buckets)
        (setf all-canonical-pairs (nreverse all-canonical-pairs))
        (dolist (pair (schedule-occurrence-pairs all-canonical-pairs tree-pos schedule pair-budget ledger labels-vec))
          (let* ((oa (car pair))
                 (ob (cdr pair))
                 (terms (list (tree-occurrence-term oa)
                              (tree-occurrence-term ob)))
                 (pat (anti-unify terms norm-inputs ledger)))
            (unless (or (trivial-subexpression-pattern-p pat)
                        (gethash pat candidate-patterns))
              (setf (gethash pat candidate-patterns) terms)))))
      ;; 2b. Multi-tree LGG relaxation across non-matching trees (when unconstrained by pair-budget)
      (when (and (null pair-budget) (not (eq schedule :locality-only)))
        (let ((seed-entries nil))
          (maphash (lambda (pat witnesses) (push (cons pat witnesses) seed-entries))
                   candidate-patterns)
          (dolist (entry (nreverse seed-entries))
            (let ((cur-pat (car entry))
                  (cur-witnesses (cdr entry)))
              (loop for i below n
                    for tree-occs = (aref per-tree-occs i)
                    for pat-sort = (term-sort cur-pat norm-inputs)
                    unless (some (lambda (o)
                                   (and (equal (tree-occurrence-sort o) pat-sort)
                                        (nth-value 1 (match-pattern cur-pat (tree-occurrence-term o)
                                                                    norm-inputs ledger))))
                                 tree-occs)
                    do (let ((best-relaxed nil)
                             (best-witnesses nil)
                             (best-saved 0))
                         (dolist (o tree-occs)
                           (when (and (equal (tree-occurrence-sort o) pat-sort)
                                      (equal (tree-occurrence-signature o)
                                             (and (app-p cur-pat) (term-sort (first cur-pat) norm-inputs))))
                             (let ((new-witnesses (append cur-witnesses (list (tree-occurrence-term o)))))
                               (multiple-value-bind (relaxed substs)
                                   (anti-unify new-witnesses norm-inputs ledger)
                                 (unless (trivial-subexpression-pattern-p relaxed)
                                   (let ((saved (occurrence-saved-bits o relaxed (car (last substs)) norm-inputs)))
                                     (when (> saved best-saved)
                                       (setf best-saved saved
                                             best-relaxed relaxed
                                             best-witnesses new-witnesses))))))))
                         (when best-relaxed
                           (setf cur-pat best-relaxed
                                 cur-witnesses best-witnesses)
                           (unless (gethash cur-pat candidate-patterns)
                             (setf (gethash cur-pat candidate-patterns) cur-witnesses))))))))))
    ;; Always include aligned whole-tree AU when all trees share the corpus root sort
    (when (> n 1)
      (let ((root-pat (anti-unify active-trees norm-inputs ledger)))
        (unless (gethash root-pat candidate-patterns)
          (setf (gethash root-pat candidate-patterns) active-trees))))
    ;; 3. For each candidate pattern, select optimal matching occurrences per tree, tighten via AU, and price
    (let ((scored-selections nil))
      (labels ((record-occurrence-selection (selected-occs kind)
                 (when (>= (length selected-occs) 2)
                   (let ((sel-key (cons kind
                                        (mapcar (lambda (o) (cons (tree-occurrence-tree-index o)
                                                                  (tree-occurrence-path o)))
                                                selected-occs))))
                     (unless (gethash sel-key evaluated-selections)
                       (setf (gethash sel-key evaluated-selections) t)
                       (multiple-value-bind (tight-pat substs)
                           (anti-unify (mapcar #'tree-occurrence-term selected-occs) norm-inputs ledger)
                         (let ((struct-score (abstraction-structural-score tight-pat selected-occs substs norm-inputs)))
                           (push (list :kind kind
                                       :selected-occs selected-occs
                                       :tight-pat tight-pat
                                       :substs substs
                                       :struct-score struct-score)
                                 scored-selections)))))))
               (price-selection (entry)
                 (let* ((kind (getf entry :kind))
                        (selected-occs (getf entry :selected-occs))
                        (tight-pat (getf entry :tight-pat))
                        (substs (getf entry :substs))
                        (struct-score (getf entry :struct-score))
                        (paths (loop for i below n
                                     for occ = (find i selected-occs :key #'tree-occurrence-tree-index)
                                     collect (if occ (tree-occurrence-path occ) :none)))
                        (wrappers (loop for i below n
                                        for occ = (find i selected-occs :key #'tree-occurrence-tree-index)
                                        collect (when occ (tree-occurrence-wrapper occ))))
                        (model (corpus-abstraction-model corpus tight-pat paths substs ledger))
                        (bits (description-size model nil)))
                   (push (make-subexpression-abstraction
                          :kind kind
                          :pattern tight-pat
                          :sort (term-sort tight-pat norm-inputs)
                          :occurrences selected-occs
                          :substitutions substs
                          :wrappers wrappers
                          :paths paths
                          :model model
                          :bits bits
                          :literal-bits literal-bits
                          :gain (- literal-bits bits)
                          :structural-score struct-score)
                         proposals))))
        ;; Record whole-tree aligned AU explicitly
        (when (> n 1)
          (record-occurrence-selection
           (loop for i below n collect (first (aref per-tree-occs i)))
           :aligned-root))
        ;; Record each candidate pattern across all trees
        (maphash
         (lambda (pat witnesses)
           (declare (ignore witnesses))
           (let ((selected nil))
             (loop for i below n
                   for tree-occs = (aref per-tree-occs i)
                   do (let ((best-occ nil)
                            (best-saved most-negative-fixnum)
                            (best-sub-bits most-positive-fixnum))
                        (dolist (occ tree-occs)
                          (when (equal (tree-occurrence-sort occ) (term-sort pat norm-inputs))
                            (multiple-value-bind (subst matched-p)
                                (match-pattern pat (tree-occurrence-term occ) norm-inputs ledger)
                              (when matched-p
                                (let ((saved (occurrence-saved-bits occ pat subst norm-inputs))
                                      (sub-bits (body-size (tree-occurrence-term occ) norm-inputs)))
                                  (when (or (null best-occ)
                                            (> saved best-saved)
                                            (and (= saved best-saved)
                                                 (< sub-bits best-sub-bits)))
                                    (setf best-occ occ
                                          best-saved saved
                                          best-sub-bits sub-bits)))))))
                        (when best-occ
                          (push best-occ selected))))
             (setf selected (nreverse selected))
             (record-occurrence-selection selected :subexpression)))
         candidate-patterns)
        ;; Price :aligned-root plus top-ranked structural candidates
        (let* ((ordered (stable-sort (nreverse scored-selections)
                                     (lambda (a b)
                                       (> (getf a :struct-score) (getf b :struct-score)))))
               (sub-count 0))
          (dolist (entry ordered)
            (when (or (eq :aligned-root (getf entry :kind))
                      (< sub-count 8))
              (when (eq :subexpression (getf entry :kind))
                (incf sub-count))
              (price-selection entry))))))
    (setf proposals (nreverse proposals))
    (let* ((best-compression
             (first (stable-sort (copy-list proposals)
                                 (lambda (a b)
                                   (or (< (subexpression-abstraction-bits a)
                                          (subexpression-abstraction-bits b))
                                       (and (= (subexpression-abstraction-bits a)
                                               (subexpression-abstraction-bits b))
                                            (> (subexpression-abstraction-structural-score a)
                                               (subexpression-abstraction-structural-score b))))))))
           (non-trivial-abstractions
             (remove-if (lambda (p)
                          (or (member (subexpression-abstraction-kind p) '(:literal :dictionary))
                              (null (subexpression-abstraction-pattern p))
                              (hole-p (subexpression-abstraction-pattern p))))
                        proposals))
           (best-structural
             (or (first (stable-sort (copy-list non-trivial-abstractions)
                                     (lambda (a b)
                                       (or (> (subexpression-abstraction-structural-score a)
                                              (subexpression-abstraction-structural-score b))
                                           (and (= (subexpression-abstraction-structural-score a)
                                                   (subexpression-abstraction-structural-score b))
                                                (< (subexpression-abstraction-bits a)
                                                   (subexpression-abstraction-bits b)))))))
                 best-compression)))
      (values best-compression best-structural proposals corpus active-trees))))))

;;; Partitioning, Autonomous View Discovery, and Locality (M7 & M8C)

(defstruct partition-view-proposal
  (kind :separate-parts)
  guard
  labels
  partition
  part-models
  model
  conflict
  (bits 0 :type fixnum)
  (run-work 0 :type fixnum))

(defun evaluate-guard-partition (frame guard-expr &key child-bindings ledger (budget 100000))
  "Evaluate Boolean GUARD-EXPR on every row of FRAME in the metered VM, split into
TRUE-FRAME and FALSE-FRAME (projected through CHILD-BINDINGS if supplied), and record
the occurrence-preserving `partition` via `partition-rows`.
Returns (VALUES true-frame false-frame labels partition)."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (rows (frame-rows frame))
         (labels nil)
         (true-rows nil)
         (false-rows nil))
    (assert (eq :bool (expression-type guard-expr inputs)))
    (dolist (row rows)
      (let ((run (evaluate guard-expr inputs (row-known row) :ledger ledger :budget budget)))
        (unless (eq :value (evaluation-status run))
          (return-from evaluate-guard-partition (values nil nil nil nil)))
        (let ((val (not (null (evaluation-value run)))))
          (push val labels)
          (if val
              (push row true-rows)
              (push row false-rows)))))
    (setf labels (nreverse labels)
          true-rows (nreverse true-rows)
          false-rows (nreverse false-rows))
    (when (or (null true-rows) (null false-rows))
      (return-from evaluate-guard-partition (values nil nil labels nil)))
    (let* ((part (partition-rows rows labels ledger))
           (linked-frame (with-frame-linkage frame :partition part :ledger ledger))
           (raw-true (make-frame (copy-schema schema) true-rows))
           (raw-false (make-frame (copy-schema schema) false-rows))
           (true-frame (project-frame-rows raw-true child-bindings ledger))
           (false-frame (project-frame-rows raw-false child-bindings ledger)))
      (values true-frame false-frame labels part linked-frame))))

(defun solve-part-subframe (part-frame language bound work-limit &key propagation ledger)
  "Return all discovered child expressions so parent reconstruction determines cost."
  (if (and propagation (propagation-fallback propagation))
      (let ((search (start-propagation-search propagation language)))
        (resume-propagation-search search bound (remaining-work ledger work-limit))
        (charge ledger :view-child-search (ledger-total (propagation-search-ledger search)))
        (mapcar #'candidate-expression (reverse (propagation-search-results search))))
      (let ((search (start-synthesis (if propagation (propagation-frame propagation) part-frame) language bound)))
        (resume-synthesis search (remaining-work ledger work-limit))
        (charge ledger :view-child-search (ledger-total (synthesis-job-ledger search)))
        (mapcar #'candidate-expression (reverse (synthesis-job-results search))))))

(defun evaluate-model-run-work (model frame &optional ledger)
  "Verify MODEL across all rows of FRAME in the metered VM and return total runtime work W_run."
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target-type (schema-target schema)))
    (loop for row in (frame-rows frame)
          sum (let ((run (evaluate model inputs (row-known row) :ledger ledger)))
                (unless (eq :value (evaluation-status run))
                  (return-from evaluate-model-run-work nil))
                (let ((chk (check-requirement (row-requirement row) (evaluation-value run)
                                              :ledger ledger :type target-type)))
                  (unless (and (eq :value (evaluation-status chk))
                               (eq t (evaluation-value chk)))
                    (return-from evaluate-model-run-work nil)))
                (evaluation-work run)))))

(defun price-view-combinations (frame guard labels partition true-models false-models
                                bindings type ledger &key decoder child-id)
  "One reconstruction/scoring path for separate branches and shared decoders."
  (let ((best nil) (inputs (schema-inputs (frame-schema frame))))
    (dolist (yes true-models)
      (dolist (no false-models)
        (let* ((branch (app (op :if type) guard
                            (if bindings (instantiate yes bindings :var) yes)
                            (if bindings (instantiate no bindings :var) no)))
               (model (if decoder (instantiate decoder (list (cons child-id branch)) :var) branch))
               (bits (description-size model inputs)))
          (charge ledger :construction (syntax-work model))
          (when (or (null best) (<= bits (partition-view-proposal-bits best)))
            (let ((work (evaluate-model-run-work model frame ledger)))
              (when (and work (or (null best) (< bits (partition-view-proposal-bits best))
                                  (< work (partition-view-proposal-run-work best))))
                (setf best (make-partition-view-proposal
                            :kind (if decoder :shared-decoder :separate-parts)
                            :guard guard :labels labels :partition partition :part-models (list yes no)
                            :model model :bits bits :run-work work))))))))
    best))

(defun %synthesize-supplied-partition-view (frame guard-expr child-language
                                          &key child-bindings child-bound (work-limit 1000000)
                                               decoder child-id child-type solver ledger)
  "Both reconstruction alternatives use the same child solver and parent scorer."
  (let* ((schema (frame-schema frame)) (target (schema-target schema)) (proposals nil) (conflicts nil))
    (multiple-value-bind (true-frame false-frame labels partition)
        (evaluate-guard-partition frame guard-expr :child-bindings child-bindings :ledger ledger)
      (unless (and true-frame false-frame)
        (return-from %synthesize-supplied-partition-view (values nil nil)))
      (labels ((solve-parts (yes no language type &optional outer yes-prop no-prop)
                 ;; A tentative narrowing cannot refute its retained original branch.
                 (let ((conflict (or (frame-conflict-p (or (and yes-prop (propagation-fallback yes-prop)) yes) :ledger ledger)
                                     (frame-conflict-p (or (and no-prop (propagation-fallback no-prop)) no) :ledger ledger))))
                   (if conflict
                       (push (make-partition-view-proposal :kind :conflict :guard guard-expr :labels labels
                                                           :partition partition :conflict conflict) conflicts)
                       (let* ((bound (or child-bound (+ (header-size (language-inputs language) type) 48)))
                              (yes-models (solve-part-subframe yes language bound work-limit :propagation yes-prop :ledger ledger))
                              (no-models (when yes-models
                                           (solve-part-subframe no language bound work-limit :propagation no-prop :ledger ledger)))
                              (proposal (price-view-combinations frame guard-expr labels partition yes-models no-models
                                                                 child-bindings type ledger :decoder outer :child-id child-id)))
                         (when proposal (push proposal proposals)))))))
        (solve-parts true-frame false-frame child-language target)
        (when decoder
          (let* ((type (or child-type target))
                 (library (when solver (as-propagator-library solver ledger)))
                 (parents (loop for truth in '(t nil) collect
                            (make-frame (copy-schema schema)
                                        (loop for row in (frame-rows frame) for label in labels
                                              when (eq truth label) collect row))))
                 (pulled (mapcar (lambda (parent)
                                   (pullback-frame parent decoder child-id type child-bindings ledger))
                                 parents))
                 (props (mapcar (lambda (child)
                                  (when library (propagate-requirements child library ledger)))
                                pulled))
                 (children (loop for child in pulled for prop in props collect
                             (if prop (propagation-frame prop) child)))
                 (language (make-language (language-domain child-language)
                                          (schema-inputs (frame-schema (first children)))
                                          :operators (language-operators child-language)
                                          :literals (language-literals child-language)
                                          :constants (language-constants child-language))))
            (solve-parts (first children) (second children) language type decoder (first props) (second props)))))
      (values (nreverse proposals) (first (nreverse conflicts))))))

(defun %discover-partition-views (frame guard-language child-language
                                 &key guard-bound child-bindings child-bound (work-limit 1000000)
                                      decoder child-id child-type solver ledger)
  "Autonomously search GUARD-LANGUAGE for Boolean view selectors on FRAME:
1. Enumerates candidate guards via `start-observation-search` and deduplicates equivalent
   partitions via `observation-bucket` (including complement symmetry G vs (not G)).
2. Prunes inconsistent view splits in O(|Omega|) via `frame-conflict-p` (recording M8C conflicts).
3. Synthesizes `:separate-parts` and `:shared-decoder` models via recursive child search and
   compares them against the unfactored `:lookup` baseline by total description size S.
Returns (VALUES best-proposal proposals conflicts)."
  (let* ((schema (frame-schema frame))
         (parent-inputs (schema-inputs schema))
         (bool-frame (unconstrained-frame frame :bool :domain (language-domain guard-language)))
         (eff-guard-bound (or guard-bound (+ (header-size parent-inputs :bool) 48)))
         (scope (make-observation-scope bool-frame guard-language))
         (obs-job (start-observation-search scope))
         (proposals nil)
         (conflicts nil)
         (seen-partitions (make-hash-table :test #'equal)))
    (resume-observation-search obs-job eff-guard-bound (remaining-work ledger work-limit))
    (charge ledger :view-guard-search (ledger-total (observation-job-ledger obs-job)))
    ;; Include unfactored lookup baseline when available
    (when (schema-lookup-p schema)
      (handler-case
          (let* ((lookup (lookup-model frame ledger))
                 (bits (description-size lookup parent-inputs))
                 (run-work (evaluate-model-run-work lookup frame ledger)))
            (when run-work
              (push (make-partition-view-proposal
                     :kind :lookup
                     :model lookup
                     :bits bits
                     :run-work run-work)
                    proposals)))
        (error () nil)))
    ;; Inspect each distinct Boolean observation bucket (shortest guard representative)
    (dolist (bucket (reverse (observation-job-buckets obs-job)))
      (when (eq :bool (observation-bucket-type bucket))
        (let* ((vals (observation-bucket-values bucket))
               (non-trivial-p (and (member t vals) (member nil vals)))
               ;; Canonicalize complement symmetry so G and (not G) share one partition key
               (canon-vals (if (first vals) vals (mapcar #'not vals))))
          (when (and non-trivial-p (not (gethash canon-vals seen-partitions)))
            (setf (gethash canon-vals seen-partitions) t)
            (let* ((members (observation-bucket-members bucket))
                   (best-rec (first (stable-sort (copy-list members) #'<
                                                 :key (lambda (r)
                                                        (description-size (observed-expression-expression r)
                                                                          parent-inputs)))))
                   (guard-expr (observed-expression-expression best-rec)))
              (multiple-value-bind (guard-proposals conflict-prop)
                  (synthesize-supplied-partition-view
                   frame guard-expr child-language
                   :child-bindings child-bindings :child-bound child-bound :work-limit work-limit
                   :decoder decoder :child-id child-id :child-type child-type
                   :solver solver :ledger ledger)
                (when conflict-prop
                  (push conflict-prop conflicts))
                (dolist (p guard-proposals)
                  (push p proposals))))))))
    (setf proposals (nreverse proposals)
          conflicts (nreverse conflicts))
    (let ((best (first (stable-sort (copy-list proposals)
                                    (lambda (a b)
                                      (or (< (partition-view-proposal-bits a)
                                             (partition-view-proposal-bits b))
                                          (and (= (partition-view-proposal-bits a)
                                                  (partition-view-proposal-bits b))
                                               (< (partition-view-proposal-run-work a)
                                                  (partition-view-proposal-run-work b)))))))))
      (values best proposals conflicts))))

(defun synthesize-supplied-partition-view (frame guard-expr child-language
                                         &key child-bindings child-bound (work-limit 1000000)
                                              decoder child-id child-type solver ledger)
  "A single additional-work budget covers both branches, preparation and replay.
Returns proposals, conflict, and a status message; synchronous cutoffs retain no cursor."
  (let ((ledger (or ledger (make-ledger))))
    (with-work-limit (ledger work-limit
                      (values nil nil (make-message :claim :cutoff :evidence (list :work (ledger-total ledger)))))
      (multiple-value-bind (proposals conflict)
          (%synthesize-supplied-partition-view frame guard-expr child-language
           :child-bindings child-bindings :child-bound child-bound :work-limit work-limit
           :decoder decoder :child-id child-id :child-type child-type :solver solver :ledger ledger)
        (values proposals conflict
                (make-message :claim (if (zerop (remaining-work ledger 1)) :cutoff :proposal-results)
                              :evidence (list :work (ledger-total ledger) :scope :supplied-view)))))))

(defun discover-partition-views (frame guard-language child-language
                                &key guard-bound child-bindings child-bound (work-limit 1000000)
                                     decoder child-id child-type solver ledger)
  "Share one additional-work budget across guard discovery and every child branch."
  (let ((ledger (or ledger (make-ledger))))
    (with-work-limit (ledger work-limit
                      (values nil nil nil (make-message :claim :cutoff :evidence (list :work (ledger-total ledger)))))
      (multiple-value-bind (best proposals conflicts)
          (%discover-partition-views frame guard-language child-language
           :guard-bound guard-bound :child-bindings child-bindings :child-bound child-bound :work-limit work-limit
           :decoder decoder :child-id child-id :child-type child-type :solver solver :ledger ledger)
        (values best proposals conflicts
                (make-message :claim (if (zerop (remaining-work ledger 1)) :cutoff :proposal-results)
                              :evidence (list :work (ledger-total ledger) :scope :view-proposals)))))))


;;; Homoiconic Higher-Order Library Learning via Top-Down Anti-Unification (Phase 4 / R5)

(defstruct library-abstraction
  name
  program-inputs
  inputs
  return-type
  body
  definition
  pattern
  programs
  refactored-bodies
  refactored-definitions
  (original-bits 0 :type fixnum)
  (library-bits 0 :type fixnum)
  (refactored-call-bits 0 :type fixnum)
  (refactored-bits 0 :type fixnum)
  (gain 0 :type fixnum)
  (work 0 :type fixnum))

(defun extract-var-literal-equality (guard)
  "When GUARD is `(= Xi 'c)` or `(= 'c Xi)`, return `(VALUES var-node lit-node)`."
  (when (and (app-p guard) (operator-p (first guard))
             (eq := (operator-name (first guard))))
    (let ((lhs (second guard))
          (rhs (third guard)))
      (cond
        ((and (var-p lhs) (lit-p rhs)) (values lhs rhs))
        ((and (lit-p lhs) (var-p rhs)) (values rhs lhs))
        (t (values nil nil))))))

(defun normalize-guarded-equalities (expr)
  "In `(if (= Xi 'c) then else)` (or `(= 'c Xi)`), canonicalize the guard to `(= Xi 'c)`
and replace occurrences of `Xi` inside `then` with `'c`."
  (if (not (app-p expr))
      expr
      (let* ((op-node (first expr))
             (args (mapcar #'normalize-guarded-equalities (rest expr))))
        (if (and (operator-p op-node) (eq :if (operator-name op-node)))
            (multiple-value-bind (v l) (extract-var-literal-equality (first args))
              (let ((canon-guard (if v (app (first (first args)) v l) (first args)))
                    (then-branch (if v
                                     (replace-subexpression (second args) v l)
                                     (second args))))
                (app op-node canon-guard then-branch (third args))))
            (apply #'app op-node args)))))

(defun infer-self-operator-name (expr inputs return-type &optional declared-name)
  "Determine the recursive self-call operator name in EXPR matching `(inputs -> return-type)`."
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (kdecl (when declared-name (canonical-op-name declared-name)))
         (expected-sig (list :fn (mapcar #'cdr norm-inputs) return-type)))
    (if (and kdecl (term-references-bound-or-self-p expr nil kdecl))
        kdecl
        (labels ((find-self (node)
                   (when (app-p node)
                     (let ((head (first node)))
                       (or (and (operator-p head)
                                (not (member (operator-name head) +operator-names+))
                                (equal (operator-type head) expected-sig)
                                (operator-name head))
                           (some #'find-self (rest node)))))))
          (or (find-self expr) kdecl)))))

(defun anti-unify-for-library (sources inputs &key self-name ledger)
  "Top-down typed anti-unification for higher-order :code library learning.
Preserves shared recursive control spines (:if guards, self-calls, and constructors
wrapping self-calls) while collapsing diverging element/step computations into expression
holes suitable for positional :code abstraction."
  (assert sources)
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (bound-vars (mapcar #'car norm-inputs))
         (eff-self (when self-name (canonical-op-name self-name)))
         (disagreements (make-hash-table :test #'equal))
         (next-id 0))
    (labels ((make-hole-for (terms sort)
               (or (gethash terms disagreements)
                   (setf (gethash terms disagreements)
                         (hole (prog1 next-id (incf next-id)) sort))))
             (generalize (terms)
               (charge ledger :anti-unification (length terms))
               (let ((sorts (mapcar (lambda (term) (term-sort term norm-inputs)) terms)))
                 (assert (every (lambda (sort) (equal sort (first sorts))) sorts))
                 (cond
                   ((every (lambda (term) (equal term (first terms))) terms)
                    (first terms))
                   ((and (every #'app-p terms)
                         (every (lambda (term) (equal (first term) (first (first terms))))
                                (rest terms)))
                    (let* ((op-node (first (first terms)))
                           (op-name (and (operator-p op-node) (operator-name op-node)))
                           (children (loop for i below (length (rest (first terms)))
                                           collect (generalize (mapcar (lambda (term) (nth i (rest term)))
                                                                       terms)))))
                      (if (or (and (eq op-name :if)
                                   (not (hole-p (first children))))
                              (and eff-self (eq op-name eff-self)
                                   (some (lambda (child) (not (hole-p child))) children))
                              (some (lambda (child)
                                      (and (not (hole-p child))
                                           (term-references-bound-or-self-p child nil eff-self)))
                                    children)
                              (and (some (lambda (child) (not (hole-p child))) children)
                                   (not (some (lambda (term)
                                                (term-references-bound-or-self-p term bound-vars eff-self))
                                              terms))))
                          (apply #'app op-node children)
                          (make-hole-for terms (first sorts)))))
                   (t
                    (make-hole-for terms (first sorts)))))))
      (let ((pattern (generalize sources)))
        (values pattern
                (mapcar (lambda (source)
                          (multiple-value-bind (substitution matched)
                              (match-pattern pattern source norm-inputs ledger)
                            (assert matched)
                            substitution))
                        sources))))))

(defun call-with-temporary-function-names (temp-names thunk)
  "Ensure TEMP-NAMES are registered at the front of `*registered-function-names*` during THUNK
(matching `:fa`/`:fb` opcode bit width) and remove any newly added temporary names afterward."
  (let ((added nil))
    (dolist (name (reverse temp-names))
      (let ((kname (canonical-op-name name)))
        (unless (member kname *registered-function-names*)
          (push kname added)
          (push kname *registered-function-names*))))
    (unwind-protect
         (funcall thunk)
      (dolist (kname added)
        (setf *registered-function-names*
              (remove kname *registered-function-names* :test #'eq))
        (evict-operator-symbol-pool kname)))))

(defun finalize-library-abstraction (abs target-name &key register-p)
  "Rename the candidate combinator operator in ABS to TARGET-NAME, optionally
registering it in `*function-definitions*` via `define-function`."
  (let ((ktarget (canonical-op-name target-name))
        (cand-op-name (library-abstraction-name abs)))
    (when (and (null register-p) (eq ktarget cand-op-name))
      (return-from finalize-library-abstraction abs))
    (let* ((prog-inputs (library-abstraction-program-inputs abs))
           (lib-inputs (library-abstraction-inputs abs))
           (return-type (library-abstraction-return-type abs))
           (lib-ctype (code-type lib-inputs return-type))
           (cand-body (library-abstraction-body abs))
           (cand-refs (library-abstraction-refactored-bodies abs)))
      (flet ((update-slots (final-body final-refs def)
               (let* ((lib-bits (body-size final-body lib-inputs))
                      (call-bits (loop for rb in final-refs sum (body-size rb prog-inputs)))
                      (ref-bits (+ lib-bits call-bits)))
                 (setf (library-abstraction-name abs) ktarget
                       (library-abstraction-body abs) final-body
                       (library-abstraction-definition abs) def
                       (library-abstraction-refactored-bodies abs) final-refs
                       (library-abstraction-library-bits abs) lib-bits
                       (library-abstraction-refactored-call-bits abs) call-bits
                       (library-abstraction-refactored-bits abs) ref-bits
                       (library-abstraction-gain abs) (- (library-abstraction-original-bits abs) ref-bits))
                 abs)))
        (if register-p
            (let* ((def (define-function ktarget lib-inputs return-type
                          (lambda (self)
                            (rename-function-calls cand-body cand-op-name self))))
                   (target-op (op ktarget))
                   (final-body (function-definition-body def))
                   (final-refs (mapcar (lambda (rb)
                                         (let ((rewritten (rename-function-calls rb cand-op-name target-op)))
                                           (ensure-ast-meta rewritten)
                                           rewritten))
                                       cand-refs)))
              (update-slots final-body final-refs def))
            (let* ((saved-def (gethash ktarget *function-definitions*))
                   (saved-names *registered-function-names*)
                   (pool-key (list :op ktarget lib-ctype))
                   (had-pool-key-p (nth-value 1 (gethash pool-key *typed-symbol-pool*))))
              (unwind-protect
                   (progn
                     (remhash ktarget *function-definitions*)
                     (unless (member ktarget *registered-function-names*)
                       (setf *registered-function-names*
                             (append *registered-function-names* (list ktarget))))
                     (let* ((target-op (op ktarget lib-ctype))
                            (final-body (rename-function-calls cand-body cand-op-name target-op))
                            (final-refs (mapcar (lambda (rb)
                                                  (rename-function-calls rb cand-op-name target-op))
                                                cand-refs)))
                       (update-slots final-body final-refs nil)))
                (setf *registered-function-names* saved-names)
                (if saved-def
                    (setf (gethash ktarget *function-definitions*) saved-def)
                    (remhash ktarget *function-definitions*))
                (unless had-pool-key-p
                  (remhash pool-key *typed-symbol-pool*)))))))))

(defun abstract-function-bodies (bodies inputs return-type
                                 &key self-names program-names (target-name :fa)
                                      rewrite-library register-p ledger)
  "Anti-unify recursive BODIES of signature `(inputs -> return-type)` after normalizing
self-calls (and optional REWRITE-LIBRARY), factor diverging subexpressions into first-order
value parameters or closed positional `:code` literals via `shared-subterm-cover` +
`abstract-over-subterms`, and return a `library-abstraction` (or NIL when no valid
recursive combinator exists)."
  (let* ((ledger (or ledger (make-ledger)))
         (start-work (ledger-total ledger))
         (norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (bound-vars (mapcar #'car norm-inputs))
         (k (length bodies)))
    (when (< k 2)
      (return-from abstract-function-bodies nil))
    (dolist (b bodies)
      (unless (equal return-type (ignore-errors (expression-type b norm-inputs)))
        (return-from abstract-function-bodies nil)))
    (let* ((inferred-snames
             (loop for b in bodies
                   for i from 0
                   for decl = (cond ((consp self-names) (nth i self-names))
                                    ((symbolp self-names) self-names)
                                    (t nil))
                   collect (infer-self-operator-name b norm-inputs return-type decl)))
           (temp-names (remove-duplicates
                        (append '(:__au_self__ :__lib_cand__)
                                (remove nil inferred-snames))))
           (raw-abs
             (call-with-temporary-function-names
              temp-names
              (lambda ()
                (let* ((active-bodies (if rewrite-library
                                          (normalize-trees-with-library bodies norm-inputs rewrite-library :ledger ledger)
                                          bodies))
                       (canon-self-op (op :__au_self__ (code-type norm-inputs return-type)))
                       (norm-bodies
                         (loop for b in active-bodies
                               for sname in inferred-snames
                               collect (normalize-guarded-equalities
                                        (rename-function-calls b sname canon-self-op)))))
                  ;; Every participating body in a recursive library abstraction must be recursive
                  (unless (every (lambda (nb) (term-references-bound-or-self-p nb nil :__au_self__))
                                 norm-bodies)
                    (return-from abstract-function-bodies nil))
                  (multiple-value-bind (pattern substitutions)
                      (anti-unify-for-library norm-bodies norm-inputs
                                              :self-name :__au_self__
                                              :ledger ledger)
                    (when (or (hole-p pattern) (not (pattern-has-holes-p pattern)))
                      (return-from abstract-function-bodies nil))
                    (let ((holes (pattern-holes pattern))
                          (next-param-id (next-child-id norm-inputs))
                          (new-params nil)
                          (extra-param-vars nil)
                          (hole-replacements nil)
                          (per-param-call-args nil)
                          (has-code-param-p nil))
                      (dolist (h holes)
                        (let* ((hid (car h))
                               (hsort (cdr h))
                               (fillers (mapcar (lambda (subst) (cdr (assoc hid subst))) substitutions)))
                          (when (or (function-sort-p hsort) (some #'null fillers))
                            (return-from abstract-function-bodies nil))
                          (if (some (lambda (f) (term-references-bound-or-self-p f bound-vars :__au_self__))
                                    fillers)
                              ;; Higher-order :code parameter
                              (let ((cover (shared-subterm-cover fillers norm-inputs
                                                                 :bound-vars bound-vars
                                                                 :self-name :__au_self__)))
                                (when (null cover)
                                  (return-from abstract-function-bodies nil))
                                (let ((code-lits nil)
                                      (common-ctype nil))
                                  (dolist (f fillers)
                                    (multiple-value-bind (clit ctype)
                                        (abstract-over-subterms f cover norm-inputs ledger :self-name :__au_self__)
                                      (when (or (null clit)
                                                (and common-ctype (not (equal common-ctype ctype))))
                                        (return-from abstract-function-bodies nil))
                                      (setf common-ctype ctype)
                                      (push clit code-lits)))
                                  (setf code-lits (nreverse code-lits)
                                        has-code-param-p t)
                                  (let* ((pid (prog1 next-param-id (incf next-param-id)))
                                         (pvar (var pid common-ctype))
                                         (eval-expr (apply #'app (op :code-eval common-ctype) pvar cover)))
                                    (push (cons pid common-ctype) new-params)
                                    (push pvar extra-param-vars)
                                    (push (cons hid eval-expr) hole-replacements)
                                    (push code-lits per-param-call-args))))
                              ;; First-order value parameter
                              (let* ((pid (prog1 next-param-id (incf next-param-id)))
                                     (pvar (var pid hsort)))
                                (push (cons pid hsort) new-params)
                                (push pvar extra-param-vars)
                                (push (cons hid pvar) hole-replacements)
                                (push fillers per-param-call-args)))))
                      (unless has-code-param-p
                        (return-from abstract-function-bodies nil))
                      (setf new-params (nreverse new-params)
                            extra-param-vars (nreverse extra-param-vars)
                            hole-replacements (nreverse hole-replacements)
                            per-param-call-args (nreverse per-param-call-args))
                      (let* ((lib-inputs (append (copy-tree norm-inputs) new-params))
                             (lib-ctype (code-type lib-inputs return-type))
                             (cand-op (op :__lib_cand__ lib-ctype))
                             (staged-body (instantiate pattern hole-replacements :hole))
                             (cand-lib-body (rename-function-calls staged-body :__au_self__
                                                                   cand-op extra-param-vars)))
                        (charge ledger :construction (syntax-work cand-lib-body))
                        (unless (and (equal return-type (ignore-errors (expression-type cand-lib-body lib-inputs)))
                                     (term-references-bound-or-self-p cand-lib-body nil :__lib_cand__)
                                     (multiple-value-bind (tot-p cond-params)
                                         (analyze-function-body-totality :__lib_cand__ lib-inputs cand-lib-body)
                                       (or tot-p cond-params)))
                          (return-from abstract-function-bodies nil))
                        (let* ((orig-vars (loop for (id . type) in norm-inputs collect (var id type)))
                               (cand-ref-bodies
                                 (loop for i below k
                                       for prog-args = (mapcar (lambda (pargs) (nth i pargs)) per-param-call-args)
                                       for rb = (apply #'app cand-op (append orig-vars prog-args))
                                       do (charge ledger :construction (syntax-work rb))
                                       collect rb))
                               (original-bits (loop for b in bodies sum (body-size b norm-inputs)))
                               (library-bits (body-size cand-lib-body lib-inputs))
                               (refactored-call-bits (loop for rb in cand-ref-bodies sum (body-size rb norm-inputs)))
                               (refactored-bits (+ library-bits refactored-call-bits))
                               (gain (- original-bits refactored-bits)))
                          (make-library-abstraction
                           :name :__lib_cand__
                           :program-inputs (copy-tree norm-inputs)
                           :inputs lib-inputs
                           :return-type (copy-tree return-type)
                           :body cand-lib-body
                           :pattern pattern
                           :programs (or (copy-list program-names)
                                         (loop for i below k collect i))
                           :refactored-bodies cand-ref-bodies
                           :original-bits original-bits
                           :library-bits library-bits
                           :refactored-call-bits refactored-call-bits
                           :refactored-bits refactored-bits
                           :gain gain
                           :work (- (ledger-total ledger) start-work)))))))))))
      (when raw-abs
        (finalize-library-abstraction raw-abs target-name :register-p register-p)))))

(defun normalize-corpus-definition-entry (entry index)
  "Normalize a `function-definition`, function name symbol, or plist into a canonical
plist `(:index idx :name name :inputs inputs :return-type return-type :body body :self-name sname :def def)`."
  (cond
    ((function-definition-p entry)
     (let ((inputs (copy-tree (function-definition-inputs entry)))
           (ret (copy-tree (function-definition-return-type entry)))
           (body (function-definition-body entry))
           (name (function-definition-name entry)))
       (list :index index
             :name name
             :inputs inputs
             :return-type ret
             :body body
             :self-name (infer-self-operator-name body inputs ret name)
             :def entry)))
    ((and (symbolp entry) (not (null entry)))
     (let ((def (find-function-definition entry)))
       (assert def () "Unknown function definition ~S" entry)
       (normalize-corpus-definition-entry def index)))
    ((consp entry)
     (let* ((name (or (getf entry :name) (de-novo-function-name index)))
            (raw-inputs (getf entry :inputs))
            (inputs (copy-tree (if (schema-p raw-inputs) (schema-inputs raw-inputs) raw-inputs)))
            (body (getf entry :body))
            (ret (copy-tree (or (getf entry :return-type)
                                (expression-type body inputs))))
            (sname (infer-self-operator-name body inputs ret (or (getf entry :self-name) name)))
            (def (%make-function-definition :name (canonical-op-name name)
                                            :inputs inputs
                                            :return-type ret
                                            :body body
                                            :total-p (provably-total-p body))))
       (list :index index
             :name (canonical-op-name name)
             :inputs inputs
             :return-type ret
             :body body
             :self-name sname
             :def def)))
    (t (error "Invalid corpus definition entry: ~S" entry))))

(defun discover-library-abstractions (definitions &key (register-p t) (min-gain 0)
                                                       library-names rewrite-library ledger)
  "Discover higher-order recursive library combinators (:map, :foldr, ...) across DEFINITIONS
using top-down homoiconic anti-unification (`anti-unify-for-library`) and positional `:code`
extraction (`shared-subterm-cover` + `abstract-over-subterms`).
Accepts a candidate combinator only when it strictly improves description length above MIN-GAIN:
  gain = sum_i S(p_i) - (S(L) + sum_i S(p_i | L)) > min-gain.
Returns `(VALUES accepted-abstractions refactored-definitions all-candidates ledger)`."
  (let* ((ledger (or ledger (make-ledger)))
         (entries (loop for d in definitions
                        for idx from 0
                        collect (normalize-corpus-definition-entry d idx)))
         (sig-groups (make-hash-table :test #'equal))
         (group-keys nil)
         (all-candidates nil)
         (raw-accepted nil))
    ;; 1. Optionally normalize corpus bodies once upfront with REWRITE-LIBRARY
    (when rewrite-library
      (let ((temp-snames (remove-duplicates
                          (loop for entry in entries
                                for sname = (getf entry :self-name)
                                when sname collect (canonical-op-name sname)))))
        (call-with-temporary-function-names
         temp-snames
         (lambda ()
           (dolist (entry entries)
             (let ((norm-body (first (normalize-trees-with-library
                                      (list (getf entry :body))
                                      (getf entry :inputs)
                                      rewrite-library
                                      :ledger ledger))))
               (setf (getf entry :body) norm-body)))))))
    ;; 2. Group corpus definitions by (inputs . return-type) preserving corpus order
    (dolist (entry entries)
      (let ((key (cons (getf entry :inputs) (getf entry :return-type))))
        (unless (gethash key sig-groups)
          (push key group-keys))
        (push entry (gethash key sig-groups))))
    (setf group-keys (nreverse group-keys))
    ;; 3. Within each signature group, explore full-group and pair-seeded subsets
    (dolist (key group-keys)
      (let ((remaining (nreverse (gethash key sig-groups)))
            (inputs (car key))
            (ret-type (cdr key)))
        (labels ((eval-subset (subset)
                   (let* ((ordered (sort (copy-list subset) #'< :key (lambda (e) (getf e :index))))
                          (bodies (mapcar (lambda (e) (getf e :body)) ordered))
                          (snames (mapcar (lambda (e) (getf e :self-name)) ordered))
                          (pnames (mapcar (lambda (e) (getf e :name)) ordered)))
                     (abstract-function-bodies bodies inputs ret-type
                                               :self-names snames
                                               :program-names pnames
                                               :target-name :__lib_cand__
                                               :rewrite-library nil
                                               :register-p nil
                                               :ledger ledger)))
                 (better-candidate-p (a b)
                   (or (> (library-abstraction-gain a) (library-abstraction-gain b))
                       (and (= (library-abstraction-gain a) (library-abstraction-gain b))
                            (> (length (library-abstraction-programs a))
                               (length (library-abstraction-programs b))))
                       (and (= (library-abstraction-gain a) (library-abstraction-gain b))
                            (= (length (library-abstraction-programs a))
                               (length (library-abstraction-programs b)))
                            (< (library-abstraction-library-bits a)
                               (library-abstraction-library-bits b))))))
          (loop while (>= (length remaining) 2) do
            (let ((seen-subsets (make-hash-table :test #'equal))
                  (group-candidates nil))
              (flet ((try-subset (subset)
                       (let* ((ordered (sort (copy-list subset) #'< :key (lambda (e) (getf e :index))))
                              (indices (mapcar (lambda (e) (getf e :index)) ordered)))
                         (multiple-value-bind (cached present-p) (gethash indices seen-subsets)
                           (if present-p
                               (unless (eq cached :none) cached)
                               (let ((cand (eval-subset ordered)))
                                 (setf (gethash indices seen-subsets) (or cand :none))
                                 (when cand
                                   (push (cons ordered cand) group-candidates)
                                   (push cand all-candidates))
                                 cand))))))
                ;; 2a. Full remaining signature group
                (try-subset remaining)
                ;; 2b. Pairwise seeds + greedy subset extension
                (loop for tail on remaining
                      for ea = (first tail)
                      do (dolist (eb (rest tail))
                           (let* ((cur-set (list ea eb))
                                  (cur-cand (try-subset cur-set)))
                             (when cur-cand
                               (loop
                                 (let ((best-ext-set nil)
                                       (best-ext-cand nil))
                                   (dolist (ec remaining)
                                     (unless (member ec cur-set :test #'eq)
                                       (let* ((ext-set (cons ec cur-set))
                                              (ext-cand (try-subset ext-set)))
                                         (when (and ext-cand
                                                    (> (library-abstraction-gain ext-cand)
                                                       (library-abstraction-gain cur-cand))
                                                    (or (null best-ext-cand)
                                                        (better-candidate-p ext-cand best-ext-cand)))
                                           (setf best-ext-set ext-set
                                                 best-ext-cand ext-cand)))))
                                   (if best-ext-cand
                                       (setf cur-set best-ext-set
                                             cur-cand best-ext-cand)
                                       (return)))))))))
              (if (null group-candidates)
                  (return)
                  (let* ((best-pair (first (stable-sort (copy-list group-candidates)
                                                        (lambda (a b)
                                                          (better-candidate-p (cdr a) (cdr b))))))
                         (best-subset (car best-pair))
                         (best-cand (cdr best-pair)))
                    (if (> (library-abstraction-gain best-cand) min-gain)
                        (progn
                          (push (cons best-subset best-cand) raw-accepted)
                          (setf remaining (set-difference remaining best-subset :test #'eq)))
                        (return)))))))))
    (setf raw-accepted (nreverse raw-accepted)
          all-candidates (nreverse all-candidates))
    ;; 3. Assign library names (:fa, :fb, ... or LIBRARY-NAMES), register when REGISTER-P,
    ;;    and construct the refactored definitions corpus.
    (let ((refactored-vec (map 'vector
                               (lambda (e)
                                 (let ((orig (getf e :def)))
                                   (%make-function-definition
                                    :name (function-definition-name orig)
                                    :inputs (copy-tree (function-definition-inputs orig))
                                    :return-type (copy-tree (function-definition-return-type orig))
                                    :body (copy-tree (function-definition-body orig))
                                    :oracle-table (copy-tree (function-definition-oracle-table orig))
                                    :total-p (function-definition-total-p orig)
                                    :conditional-code-params
                                    (copy-tree (function-definition-conditional-code-params orig)))))
                               entries))
          (accepted nil))
      (loop for (subset . cand) in raw-accepted
            for lib-idx from 0
            for lib-name = (canonical-op-name (or (nth lib-idx library-names)
                                                  (de-novo-function-name lib-idx)))
            do (finalize-library-abstraction cand lib-name :register-p register-p)
               (let ((ref-defs nil))
                 (loop for entry in subset
                       for rbody in (library-abstraction-refactored-bodies cand)
                       for idx = (getf entry :index)
                       for rdef = (aref refactored-vec idx)
                       do (setf (function-definition-body rdef) rbody
                                (function-definition-oracle-table rdef) nil
                                (function-definition-total-p rdef) (provably-total-p rbody)
                                (function-definition-conditional-code-params rdef) nil)
                          (push rdef ref-defs))
                 (setf (library-abstraction-refactored-definitions cand) (nreverse ref-defs))
                 (push cand accepted)))
      (values (nreverse accepted)
              (coerce refactored-vec 'list)
              all-candidates
              ledger))))

;;; ============================================================
;;; Persistent Knowledge Library: Descriptors, Functions, Relations
;;; ============================================================

(defun function-body-length-preserving-p (name body)
  "True when BODY is a structural list recursion on X0 that maps '() to '() and
constructs one output element via :CONS per (:TAIL X0) step, or delegates directly
to a length-preserving higher-order combinator on X0."
  (and (app-p body)
       (or (and (eq :if (ast-id body))
                (let ((cond-ast (second body))
                      (then-ast (third body))
                      (else-ast (fourth body))
                      (kname (canonical-op-name name)))
                  (and (eql 0 (empty-sequence-guard-var-id cond-ast '(0)))
                       (lit-p then-ast)
                       (null (ast-value then-ast))
                       (app-p else-ast)
                       (eq :cons (ast-id else-ast))
                       (let ((rec-call (third else-ast)))
                         (and (app-p rec-call)
                              (eq kname (ast-id rec-call))
                              (plusp (length (rest rec-call)))
                              (let ((arg0 (second rec-call)))
                                (and (app-p arg0)
                                     (eq :tail (ast-id arg0))
                                     (var-p (second arg0))
                                     (eql 0 (ast-id (second arg0))))))))))
           (and (operator-p (first body))
                (= 2 (length (rest body)))
                (var-p (second body))
                (eql 0 (ast-id (second body)))
                (lit-p (third body))
                (code-type-p (ast-type (third body)))
                (let* ((comb-name (operator-name (first body)))
                       (comb-def (and (not (eq comb-name (canonical-op-name name)))
                                      (find-function-definition comb-name))))
                  (and comb-def
                       (function-definition-body comb-def)
                       (function-body-length-preserving-p comb-name (function-definition-body comb-def))))))))

(defun compute-function-descriptor (fdef)
  "Synthesize a closed VM-executable Boolean descriptor AST over (X0=seq-input, X1=output)
summarizing invariant I/O behavior of FDEF (such as empty-list base behavior and
length preservation)."
  (when (and (function-definition-p fdef)
             (function-definition-body fdef)
             (plusp (length (function-definition-inputs fdef))))
    (let* ((param0-spec (first (function-definition-inputs fdef)))
           (param0-id (car param0-spec))
           (param0-type (cdr param0-spec))
           (ret-type (function-definition-return-type fdef))
           (body (function-definition-body fdef)))
      (when (and (eql 0 param0-id)
                 (consp param0-type)
                 (eq :seq (first param0-type)))
        (let* ((x0 (var 0 param0-type))
               (x1 (var 1 ret-type))
               (empty-seq (lit param0-type nil))
               (len-preserving-p
                 (and (consp ret-type)
                      (eq :seq (first ret-type))
                      (function-body-length-preserving-p (function-definition-name fdef) body)))
               (base-branch
                 (cond
                   ((and (app-p body) (eq :if (ast-id body)))
                    (let ((cond-ast (second body))
                          (then-ast (third body)))
                      (when (and (eql 0 (empty-sequence-guard-var-id cond-ast '(0)))
                                 (lit-p then-ast))
                        then-ast)))
                   (len-preserving-p
                    (lit ret-type nil))))
               (base-check
                 (when base-branch
                   (app (op :if :bool)
                        (app (op := param0-type) x0 empty-seq)
                        (app (op := ret-type) x1 base-branch)
                        (lit :bool t))))
               (len-check
                 (when len-preserving-p
                   (app (op := :int)
                        (app (op :length (second param0-type)) x0)
                        (app (op :length (second ret-type)) x1)))))
          (cond ((and base-check len-check) (bool-and base-check len-check))
                (len-check len-check)
                (base-check base-check)
                (t nil)))))))

(define-knowledge-kind :descriptor
  (:priority 15)
  (:validate (entry library)
    (declare (ignore library))
    (assert (and (knowledge-entry-expression entry)
                 (eq :bool (expression-type (knowledge-entry-expression entry)
                                            (knowledge-entry-inputs entry))))))
  (:install (entry library ledger)
    (declare (ignore ledger))
    (dolist (edge (knowledge-edges-from entry :describes library))
      (dolist (target (rest edge))
        (when (symbolp target)
          (setf (gethash (canonical-op-name target) (knowledge-library-descriptors library))
                (knowledge-entry-expression entry))))))
  (:consume (entry context ledger)
    (let ((expr (knowledge-entry-expression entry))
          (inputs (knowledge-entry-inputs entry)))
      (when (and expr (= (length context) (length inputs)))
        (let ((run (evaluate expr inputs context :ledger ledger)))
          (and (eq :value (evaluation-status run))
               (evaluation-value run)))))))

(defun compose-hybrid-residual-program (inputs target parametric-expr residual-table &key default)
  "Compose a single VM-executable AST from PARAMETRIC-EXPR (or DEFAULT) and RESIDUAL-TABLE.
When RESIDUAL-TABLE is non-empty, guards `:lookup` with `:member` so keys outside the residual
table fall back cleanly to PARAMETRIC-EXPR (or DEFAULT) without raising an unresolved lookup."
  (let* ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (single-input-p (= 1 (length norm-inputs)))
         (key-type (if single-input-p
                       (cdar norm-inputs)
                       (apply #'tuple-type (mapcar #'cdr norm-inputs))))
         (key-expr (if single-input-p
                       (var (caar norm-inputs) (cdar norm-inputs))
                       (apply #'app (op :tuple key-type)
                              (mapcar (lambda (spec) (var (car spec) (cdr spec))) norm-inputs))))
         (fallback-expr (cond (parametric-expr parametric-expr)
                              ((and default (ignore-errors (ensure-ast-meta default))) default)
                              (default (lit target default))
                              (t nil))))
    (cond
      ((null residual-table)
       fallback-expr)
      ((and (eq target :bool)
            (null fallback-expr)
            (every (lambda (item) (not (and (consp item) (= 2 (length item)) (value-p (first item) key-type) (typep (second item) 'boolean))))
                   residual-table))
       (let ((keys (mapcar (lambda (item)
                             (if (and (consp item) (eq (cdr item) t))
                                 (car item)
                                 item))
                           residual-table)))
         (app (op :member key-type)
              key-expr
              (lit (sequence-type key-type) keys))))
      (t
       (let* ((entry-type (tuple-type key-type target))
              (norm-pairs (mapcar (lambda (pair)
                                    (if (and (consp pair) (not (listp (cdr pair))))
                                        (list (car pair) (cdr pair))
                                        (list (first pair) (second pair))))
                                  residual-table))
              (keys (mapcar #'first norm-pairs))
              (lookup-ast (app (op :lookup entry-type)
                               key-expr
                               (lit (sequence-type entry-type) norm-pairs))))
         (if fallback-expr
             (app (op :if target)
                  (app (op :member key-type) key-expr (lit (sequence-type key-type) keys))
                  lookup-ast
                  fallback-expr)
             lookup-ast))))))

(defun register-knowledge-relation (id table &key
                                               (library *knowledge-library*)
                                               domain
                                               inputs
                                               (target :int)
                                               relation-kind
                                               parametric
                                               default
                                               guard
                                               (status :empirical)
                                               edges
                                               metadata
                                               ledger)
  "Register an irreducible table (:LOOKUP map or :MEMBER set, first-order or second-order over :CODE)
or a hybrid (PARAMETRIC + TABLE) residual program as a :RELATION entry in LIBRARY."
  (declare (ignore relation-kind))
  (let* ((norm-id (if (symbolp id) (canonical-op-name id) id))
         (norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs))
         (rel-ast (compose-hybrid-residual-program norm-inputs target parametric table :default default))
         (entry (make-knowledge-entry
                 :id norm-id
                 :kind :relation
                 :domain domain
                 :inputs norm-inputs
                 :target target
                 :expression parametric
                 :guard guard
                 :residual table
                 :auxiliary-code rel-ast
                 :status status
                 :certificate (list :kind :empirical-table :rows (length table))
                 :bits (if rel-ast
                           (or (ignore-errors (body-size rel-ast norm-inputs))
                               (syntax-work rel-ast))
                           0)
                 :edges edges
                 :metadata (append (list :table (copy-tree table) :default default)
                                   (copy-tree metadata))
                 :library library)))
    (register-knowledge-entry entry :library library :ledger ledger)))

(defun consolidate-residual-relations (entries library ledger)
  "Delayed structure discovery across empirical :RELATION entries in LIBRARY.
1. Within a single relation entry whose residual table has >= 2 first-order rows, check if an
   algebraic expression compresses the residual table with positive MDL gain (delta-S > 0).
2. Across multiple relation entries sharing (inputs, target) that are individually too small
   to justify a parametric rule, pool their residual tables and test whether a shared expression
   jointly compresses the pooled residuals with positive total MDL gain."
  (let ((condensed nil)
        (by-sig (make-hash-table :test #'equal)))
    (labels ((first-order-table-p (inputs target table)
               (and (consp table)
                    (every (lambda (spec) (not (code-type-p (cdr spec)))) inputs)
                    (not (code-type-p target))))
             (normalize-table-rows (inputs table)
               (let ((single-p (= 1 (length inputs))))
                 (loop for item in table
                       for idx from 0
                       for raw-key = (if (and (consp item) (not (listp (cdr item))))
                                         (car item)
                                         (first item))
                       for val = (if (and (consp item) (not (listp (cdr item))))
                                     (cdr item)
                                     (second item))
                       for known = (if single-p (list raw-key) raw-key)
                       collect (list idx known val))))
             (find-compressing-expr (inputs target domain rows-data)
               (let* ((eff-domain (or domain :int))
                      (schema (make-schema :domain eff-domain :inputs inputs :target target))
                      (frame (make-frame schema
                                         (loop for (idx known val) in rows-data
                                               collect (make-row :key idx
                                                                 :known known
                                                                 :requirement (singleton-requirement target val)))))
                      (ops (when (or (eq eff-domain :int)
                                     (and (consp eff-domain) (eq :gf (first eff-domain))))
                             (list (op :+ eff-domain) (op :* eff-domain))))
                      (lang (make-language eff-domain inputs :operators ops :literals '(0 1 2 3)))
                      (bound (+ (header-size inputs target) 36))
                      (search (start-search frame lang)))
                 (loop for step from 1 to 20
                       until (search-job-best search)
                       do (resume-search search bound (* step 5000)))
                 (when ledger
                   (charge ledger :child-search (ledger-total (search-job-ledger search))))
                 (and (search-job-best search)
                      (candidate-expression (search-job-best search))))))
      ;; Pass 1: Individual relation entries and grouping by signature
      (dolist (entry entries)
        (let ((inputs (knowledge-entry-inputs entry))
              (target (knowledge-entry-target entry))
              (table (knowledge-entry-residual entry)))
          (when (and (null (knowledge-entry-expression entry))
                     (first-order-table-p inputs target table))
            (push entry (gethash (list (knowledge-entry-domain entry) inputs target) by-sig))
            (when (>= (length table) 4)
              (let* ((rows-data (normalize-table-rows inputs table))
                     (best (find-compressing-expr inputs target (knowledge-entry-domain entry) rows-data)))
                (when best
                  (let* ((old-bits (knowledge-entry-bits entry))
                         (new-bits (body-size best inputs))
                         (gain (- old-bits new-bits)))
                    (when (plusp gain)
                      (setf (knowledge-entry-expression entry) best
                            (knowledge-entry-residual entry) nil
                            (knowledge-entry-auxiliary-code entry) best
                            (knowledge-entry-status entry) :empirical
                            (knowledge-entry-bits entry) new-bits
                            (knowledge-entry-gain entry) gain)
                      (push entry condensed)))))))))
      ;; Pass 2: Joint pooling across multiple relations with the same (domain, inputs, target)
      (maphash
       (lambda (sig group)
         (let ((remaining (remove-if #'knowledge-entry-expression (reverse group))))
           (when (>= (length remaining) 2)
             (destructuring-bind (domain inputs target) sig
               (let* ((pooled-rows
                        (loop for e in remaining
                              for e-idx from 0
                              append (loop for (r-idx known val) in (normalize-table-rows inputs (knowledge-entry-residual e))
                                           collect (list (list e-idx r-idx) known val))))
                      (best (when (>= (length pooled-rows) 4)
                              (find-compressing-expr inputs target domain pooled-rows))))
                 (when best
                   (let* ((old-total-bits (reduce #'+ remaining :key #'knowledge-entry-bits))
                          (expr-bits (body-size best inputs))
                          ;; Shared helper function + call overhead across remaining entries
                          (total-gain (- old-total-bits expr-bits)))
                     (when (plusp total-gain)
                       (dolist (e remaining)
                         (setf (knowledge-entry-expression e) best
                               (knowledge-entry-residual e) nil
                               (knowledge-entry-auxiliary-code e) best
                               (knowledge-entry-status e) :empirical
                               (knowledge-entry-bits e) expr-bits
                               (knowledge-entry-gain e) total-gain)
                         (pushnew e condensed :test #'eq))))))))))
       by-sig)
      (when condensed
        (incf (knowledge-library-version library)))
      (nreverse condensed))))

(define-knowledge-kind :relation
  (:priority 25)
  (:validate (entry library)
    (declare (ignore library))
    (let ((aux (knowledge-entry-auxiliary-code entry))
          (expr (knowledge-entry-expression entry))
          (res (knowledge-entry-residual entry))
          (inputs (knowledge-entry-inputs entry))
          (target (knowledge-entry-target entry)))
      (when (and (null aux) (or expr res))
        (setf aux (compose-hybrid-residual-program inputs target expr res
                                                   :default (getf (knowledge-entry-metadata entry) :default))
              (knowledge-entry-auxiliary-code entry) aux))
      (when aux
        (assert (equal target (expression-type aux inputs))))))
  (:install (entry library ledger)
    (declare (ignore library ledger))
    (when (and (null (knowledge-entry-auxiliary-code entry))
               (or (knowledge-entry-expression entry) (knowledge-entry-residual entry)))
      (setf (knowledge-entry-auxiliary-code entry)
            (compose-hybrid-residual-program (knowledge-entry-inputs entry)
                                             (knowledge-entry-target entry)
                                             (knowledge-entry-expression entry)
                                             (knowledge-entry-residual entry)
                                             :default (getf (knowledge-entry-metadata entry) :default)))))
  (:consume (entry context ledger)
    (let ((prog (or (knowledge-entry-auxiliary-code entry)
                    (knowledge-entry-expression entry)))
          (inputs (knowledge-entry-inputs entry)))
      (when (and prog (= (length context) (length inputs)))
        (evaluate prog inputs context :ledger ledger))))
  (:consolidate (entries library ledger)
    (consolidate-residual-relations entries library ledger)))

(defun knowledge-graph-locality-key (fn-name &optional (library *knowledge-library*))
  "Compute a structural neighborhood signature for FN-NAME in LIBRARY so functions
that share algebraic laws, descriptors, or solver edges cluster together during
higher-order library consolidation."
  (when (knowledge-library-p library)
    (let ((entry (find-knowledge-entry (canonical-op-name fn-name) library)))
      (when entry
        (let ((desc-expr (and (knowledge-entry-trigger entry)
                              (ast->sexp (knowledge-entry-trigger entry))))
              (rel-kinds (sort (loop for edge in (knowledge-edges-from fn-name nil library)
                                     when (consp edge) collect (first edge))
                               #'string< :key #'symbol-name)))
          (list :trigger desc-expr :relations rel-kinds))))))

(defun consolidate-library-functions (library &key
                                                entries
                                                (ledger (make-ledger))
                                                (min-gain 0)
                                                (register-p t)
                                                library-names
                                                rewrite-library)
  "Discover MDL-positive higher-order combinators across :FUNCTION entries in LIBRARY,
recording :REFACTORED-BY and :ABSTRACTS relational edges and refreshing descriptors."
  (let* ((fn-entries (or entries (knowledge-entries-of-kind :function library)))
         (fdefs (loop for e in fn-entries
                      for fdef = (or (gethash (knowledge-entry-id e) (knowledge-library-functions library))
                                     (find-function-definition (knowledge-entry-id e)))
                      when (and fdef
                                (function-definition-body fdef)
                                (null (function-definition-oracle-table fdef))
                                ;; Exclude already-abstracted higher-order combinators and functions already refactored
                                (not (some (lambda (spec) (code-type-p (cdr spec)))
                                           (function-definition-inputs fdef)))
                                (null (knowledge-edges-from e :refactored-by library)))
                        collect fdef)))
    (when (>= (length fdefs) 2)
      (multiple-value-bind (accepted refactored-defs all-candidates updated-ledger)
          (discover-library-abstractions fdefs
                                         :ledger ledger
                                         :min-gain min-gain
                                         :register-p register-p
                                         :library-names library-names
                                         :rewrite-library (or rewrite-library library))
        (declare (ignore all-candidates))
        (when (and register-p accepted)
          (loop for orig-def in fdefs
                for ref-def in refactored-defs
                for fname = (function-definition-name orig-def)
                unless (equal (function-definition-body orig-def)
                              (function-definition-body ref-def))
                  do (define-function fname
                                      (function-definition-inputs ref-def)
                                      (function-definition-return-type ref-def)
                                      (function-definition-body ref-def)))
          (dolist (cand accepted)
            (let* ((lib-name (library-abstraction-name cand))
                   (lib-entry (find-knowledge-entry lib-name library)))
              (when lib-entry
                (setf (knowledge-entry-gain lib-entry) (library-abstraction-gain cand)
                      (knowledge-entry-work lib-entry) (library-abstraction-work cand)))
              (loop for src-name in (library-abstraction-programs cand)
                    for rbody in (library-abstraction-refactored-bodies cand)
                    do (add-knowledge-edge src-name :refactored-by lib-name)
                       (add-knowledge-edge lib-name :abstracts src-name)
                       (let ((src-entry (find-knowledge-entry src-name library)))
                         (when (and src-entry (app-p rbody))
                           (let ((code-args (loop for arg in (rest rbody)
                                                  when (cond
                                                         ((and (lit-p arg) (code-type-p (ast-type arg)))
                                                          (ast-value arg))
                                                         ((and (app-p arg)
                                                               (eq :code-subst (ast-id arg))
                                                               (lit-p (second arg))
                                                               (code-type-p (ast-type (second arg))))
                                                          (ast-value (second arg))))
                                                    collect (if (lit-p arg)
                                                                (ast-value arg)
                                                                (ast-value (second arg))))))
                             (when (= 1 (length code-args))
                               (setf (knowledge-entry-auxiliary-code src-entry) (first code-args))))))))))
        (values accepted refactored-defs updated-ledger)))))

(define-knowledge-kind :function
  (:priority 10)
  (:validate (entry library)
    (declare (ignore library))
    (let ((expr (knowledge-entry-expression entry))
          (inputs (knowledge-entry-inputs entry))
          (target (knowledge-entry-target entry)))
      (when expr
        (let ((kname (knowledge-entry-id entry)))
          (if (or (defined-function-p kname) (member kname *registered-function-names*))
              (assert (equal target (expression-type expr inputs)))
              (let ((*registered-function-names* (append *registered-function-names* (list kname))))
                (assert (equal target (expression-type expr inputs)))))))))
  (:install (entry library ledger)
    (declare (ignore ledger))
    (let* ((kname (knowledge-entry-id entry))
           (inputs (knowledge-entry-inputs entry))
           (target (knowledge-entry-target entry))
           (body (knowledge-entry-expression entry))
           (oracle (getf (knowledge-entry-metadata entry) :oracle-table))
           (def (if *syncing-knowledge-library-p*
                    (or (find-function-definition kname)
                        (define-function kname inputs target body :oracle-table oracle))
                    (let ((*syncing-knowledge-library-p* t))
                      (define-function kname inputs target body :oracle-table oracle)))))
      (setf (gethash kname (knowledge-library-functions library)) def)
      (unless (member kname (knowledge-library-function-names library))
        (setf (knowledge-library-function-names library)
              (append (knowledge-library-function-names library) (list kname))))
      (when (null (knowledge-entry-trigger entry))
        (let ((desc (compute-function-descriptor def)))
          (when desc
            (setf (knowledge-entry-trigger entry) desc)
            (setf (gethash kname (knowledge-library-descriptors library)) desc)
            (let ((desc-id (intern (format nil "~A/DESCRIPTOR" (symbol-name kname)) :keyword)))
              (unless (find-knowledge-entry desc-id library)
                (register-knowledge-entry
                 (make-knowledge-entry
                  :id desc-id
                  :kind :descriptor
                  :domain (knowledge-entry-domain entry)
                  :inputs (list (cons 0 (cdar inputs))
                                (cons 1 target))
                  :target :bool
                  :expression desc
                  :status :validated
                  :certificate '(:kind :structural-descriptor)
                  :edges (list (list :describes kname))
                  :library library)
                 :library library))
              (add-knowledge-edge entry :described-by desc-id)))))
      (when (knowledge-entry-trigger entry)
        (setf (gethash kname (knowledge-library-descriptors library))
              (knowledge-entry-trigger entry)))
      (when (and (app-p body) (operator-p (first body)))
        (let* ((comb-name (operator-name (first body)))
               (comb-entry (and (not (eq comb-name kname))
                                (find-knowledge-entry comb-name library)))
               (code-args (loop for arg in (rest body)
                                when (and (lit-p arg) (code-type-p (ast-type arg)))
                                  collect (ast-value arg))))
          (when (and comb-entry (eq :function (knowledge-entry-kind comb-entry)) code-args)
            (when (and (= 1 (length code-args))
                       (null (knowledge-entry-auxiliary-code entry)))
              (setf (knowledge-entry-auxiliary-code entry) (first code-args)))
            (add-knowledge-edge entry :refactored-by comb-name)
            (add-knowledge-edge comb-entry :abstracts kname))))))
  (:consume (entry context ledger)
    (let ((kname (knowledge-entry-id entry))
          (inputs (knowledge-entry-inputs entry)))
      (when (= (length context) (length inputs))
        (evaluate (apply #'app (op kname)
                         (loop for (id . type) in inputs
                               collect (var id type)))
                  inputs context :ledger ledger))))
  (:consolidate (entries library ledger)
    (consolidate-library-functions library :entries entries :ledger ledger)))

