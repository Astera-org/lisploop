(in-package #:lisploop)

;;; Behavioural descriptors of library entries: structural proofs, profiles, and frame scoring.

(defvar *descriptor-proof-stack* nil
  "Names of the functions whose recursion shape is being classified; cuts delegation cycles.")

(defun tail-of-var-p (term seq-id)
  "True when TERM is `(:tail X_SEQ-ID)`."
  (and (app-of-p term :tail) (var-p (second term)) (eql seq-id (ast-id (second term)))))

(defun recursive-tail-call-on-var-p (expr kname seq-id &optional seq-pos)
  "True when EXPR is a recursive call `(kname ...)` whose argument at SEQ-POS (or, without a
usable SEQ-POS, any argument) is `(:tail X_SEQ-ID)`."
  (and (app-of-p expr kname)
       (let ((args (rest expr)))
         (if (and seq-pos (< seq-pos (length args)))
             (tail-of-var-p (nth seq-pos args) seq-id)
             (some (lambda (arg) (tail-of-var-p arg seq-id)) args)))))

(defun empty-sequence-base (body seq-id)
  "When BODY is `(if (= X_SEQ-ID '()) base step)` with a literal BASE, return BASE and STEP."
  (when (and (app-of-p body :if)
             (eql seq-id (empty-sequence-guard-var-id (second body) (list seq-id)))
             (lit-p (third body)))
    (values (third body) (fourth body))))

(defun list-recursion-shape (name body &optional (seq-id 0) seq-pos)
  "Classify BODY as a structural recursion on the list X_SEQ-ID that maps '() to '().
:preserving emits one :cons per (:tail X_SEQ-ID) step; :contracting either emits one or
skips the step, as a filter does; :decrementing also maps singletons to '() and otherwise
emits one per step, as an adjacent-pair stencil does. A body that hands X_SEQ-ID to another
function takes that function's shape, except that a decrementing shape is not inherited and
a preserving one needs every other argument to be a code literal. Anything else is nil."
  (unless (member name *descriptor-proof-stack*)
    (let ((*descriptor-proof-stack* (cons name *descriptor-proof-stack*))
          (kname (canonical-op-name name)))
      (flet ((self-tail-p (expr) (recursive-tail-call-on-var-p expr kname seq-id seq-pos))
             (seq-var-p (term) (and (var-p term) (eql seq-id (ast-id term)))))
        (multiple-value-bind (base step) (empty-sequence-base body seq-id)
          (cond
            ((and base (null (ast-value base)))
             (flet ((emit-p (branch) (and (app-of-p branch :cons) (self-tail-p (third branch)))))
               (cond
                 ((emit-p step) :preserving)
                 ((app-of-p step :if)
                  (destructuring-bind (guard then else) (rest step)
                    (cond ((or (and (emit-p then) (self-tail-p else))
                               (and (emit-p else) (self-tail-p then)))
                           :contracting)
                          ((and (lit-p then) (null (ast-value then))
                                (app-of-p guard :=)
                                (some (lambda (side) (tail-of-var-p side seq-id)) (rest guard))
                                (emit-p else))
                           :decrementing)))))))
            ((and (app-p body) (operator-p (first body)) (>= (length (rest body)) 2))
             (let* ((args (rest body))
                    (var-pos (position-if #'seq-var-p args))
                    (comb-name (operator-name (first body)))
                    (comb-def (and var-pos (not (eq comb-name kname))
                                   (find-function-definition comb-name)))
                    (comb-seq-spec (and comb-def (nth var-pos (function-definition-inputs comb-def)))))
               (when (and comb-seq-spec (function-definition-body comb-def))
                 (case (list-recursion-shape comb-name (function-definition-body comb-def)
                                             (car comb-seq-spec) var-pos)
                   (:preserving
                    (and (every (lambda (arg)
                                  (or (seq-var-p arg) (and (lit-p arg) (code-type-p (ast-type arg)))))
                                args)
                         :preserving))
                   (:contracting :contracting)))))))))))

(defun function-body-length-preserving-p (name body &optional (seq-id 0) seq-pos)
  "True when BODY is a length-preserving list recursion on X_SEQ-ID, directly or by handing
X_SEQ-ID to a length-preserving combinator; see `list-recursion-shape`."
  (eq :preserving (list-recursion-shape name body seq-id seq-pos)))

(defun function-body-pointwise-map-p (name inputs body seq-id code-id)
  "True when BODY, the definition of NAME over INPUTS, maps the code X_CODE-ID over the list
X_SEQ-ID element by element: '() on the empty list, and otherwise that code applied to the
head alone, consed onto NAME applied to the tail and the same code. The i-th output of such
a function is the code's value on the i-th input and depends on nothing else. A body that
merely preserves length (`function-body-length-preserving-p`) promises less: its step may
read the rest of the list, or the list in another order."
  (let ((kname (canonical-op-name name))
        (seq-pos (position seq-id inputs :key #'car))
        (code-pos (position code-id inputs :key #'car)))
    (flet ((code-var-p (term) (and (var-p term) (eql code-id (ast-id term))))
           (head-p (term)
             (and (app-of-p term :at) (var-p (second term)) (eql seq-id (ast-id (second term)))
                  (lit-p (third term)) (eql 0 (ast-value (third term))))))
      (multiple-value-bind (base step) (empty-sequence-base body seq-id)
        (and seq-pos code-pos base (null (ast-value base))
             (app-of-p step :cons)
             (destructuring-bind (emitted onward) (rest step)
               (and (app-of-p emitted :code-eval)
                    (= 2 (length (rest emitted)))
                    (code-var-p (second emitted))
                    (head-p (third emitted))
                    (app-of-p onward kname)
                    (= (length inputs) (length (rest onward)))
                    (tail-of-var-p (nth seq-pos (rest onward)) seq-id)
                    (code-var-p (nth code-pos (rest onward))))))))))

(defun function-shape-facts (name inputs target body)
  "Structural facts about the function NAME : INPUTS -> TARGET with BODY, as a plist.
:seq-spec is the first sequence input; :pure-p holds when every other input is code; :shape
is the `list-recursion-shape` of BODY on that input when TARGET is a sequence; :base is the
literal BODY returns on the empty sequence, if that is known; :subset-p holds when a
contracting BODY emits only the head `(:at seq 0)` of its input."
  (let* ((seq-spec (find-if #'seq-type-p inputs :key #'cdr))
         (seq-id (car seq-spec))
         (shape (and seq-spec body (seq-type-p target)
                     (list-recursion-shape name body seq-id (position seq-spec inputs :test #'eq)))))
    (flet ((head-p (term)
             (and (app-of-p term :at) (var-p (second term)) (eql seq-id (ast-id (second term)))
                  (lit-p (third term)) (eql 0 (ast-value (third term))))))
      (list :seq-spec seq-spec
            :pure-p (and seq-spec
                         (every (lambda (spec) (or (eq spec seq-spec) (code-type-p (cdr spec))))
                                inputs))
            :shape shape
            :base (and seq-spec body
                       (or (empty-sequence-base body seq-id) (and shape (lit target nil))))
            :subset-p (and (eq shape :contracting) (app-of-p body :if)
                           (some (lambda (branch)
                                   (and (app-of-p branch :cons) (head-p (second branch))))
                                 (cddr (fourth body))))))))

(defun compute-function-descriptor (fdef)
  "Synthesize a closed VM-executable Boolean descriptor AST over (X0=seq-input, X1=output)
summarizing invariant I/O behavior of FDEF (such as empty-list base behavior and
length preservation or contraction)."
  (when (and (function-definition-p fdef) (function-definition-body fdef))
    (let ((ret-type (function-definition-return-type fdef)))
      (destructuring-bind (&key seq-spec pure-p shape base &allow-other-keys)
          (function-shape-facts (function-definition-name fdef) (function-definition-inputs fdef)
                                ret-type (function-definition-body fdef))
        (when pure-p
          (let* ((x0 (var 0 (cdr seq-spec)))
                 (x1 (var 1 ret-type))
                 (base-check (and base (term `(if (= ,x0 ()) (= ,x1 ,base) t))))
                 (len-check (case shape
                              (:preserving (term `(= (length ,x0) (length ,x1))))
                              (:contracting (bool-not (term `(< (length ,x0) (length ,x1))))))))
            (if (and base-check len-check)
                (bool-and base-check len-check)
                (or len-check base-check))))))))

(defun signature-facts (seq-in-p target)
  "The type facts of an entry or a frame: whether a sequence goes in and what comes out."
  (list (if seq-in-p :seq-in :scalar-in)
        (if (seq-type-p target) :seq-out :scalar-out)
        (and (seq-type-p target) (seq-type-p (second target)) :seq-2d-out)
        (and (equal target '(:seq :int)) :int-seq-out)))

(defun strip-descriptor-prefix (sym)
  "Strip leading `DESC/` from SYM's name when building a compositional address."
  (let ((name (symbol-name sym)))
    (if (and (>= (length name) 5) (string= "DESC/" name :end2 5))
        (subseq name 5)
        name)))

(defun derive-compositional-name (entry &optional (clauses (knowledge-entry-descriptor-profile entry)))
  "Derive a canonical compositional secondary address symbol for ENTRY from its descriptor
clause profile across `:type`, `:shape-delta`, `:boundary`, `:sampled-content`, and `:algebraic` facets."
  (flet ((token (&rest facets)
           (let ((clause (some (lambda (facet) (find facet clauses :key #'descriptor-clause-facet))
                               facets)))
             (if clause (strip-descriptor-prefix (descriptor-clause-id clause)) "ANY"))))
    (keyword-id "~A/~A/~A/~A/~A" (or (knowledge-entry-kind entry) :entry)
                (token :type) (token :shape-delta) (token :boundary)
                (token :sampled-content :algebraic))))

(define-knowledge-kind :descriptor
  (:priority 15)
  ;; A descriptor probes the functions it names; it is not a use of them.
  (:passive t)
  (:validate (entry library)
    (declare (ignore library))
    (assert (eq :bool (knowledge-entry-target entry)))
    (assert-entry-expression-type entry))
  (:install (entry library ledger)
    (declare (ignore entry library ledger))
    nil))

(defun frame-concrete-pairs (frame input-id)
  "The (input . output) value pairs of the rows of FRAME that fix both the value of input
INPUT-ID and a single allowed output."
  (let ((pos (position input-id (schema-inputs (frame-schema frame)) :key #'car)))
    (when pos
      (loop for row in (frame-rows frame)
            for allowed = (extract-allowed-values (row-requirement row))
            when (and (consp allowed) (= 1 (length allowed))
                      (not (member :unresolved (row-known row))))
              collect (cons (nth pos (row-known row)) (first allowed))))))

(defvar *polymorphic-descriptor-executables* (make-hash-table :test #'eq :weakness :key)
  "Transient weak cache of polymorphically instantiated `:descriptor` entries per `(seq-type, target)`.")

(defun resolve-descriptor-for-types (descriptor seq-type target)
  "Return DESCRIPTOR when its `inputs` already match `(seq-type, target)`, or a cached
polymorphically instantiated `:descriptor` entry when its template unifies with `(seq-type, target)`."
  (let ((inputs (knowledge-entry-inputs descriptor)))
    (cond
      ((and (= 2 (length inputs))
            (equal seq-type (cdr (first inputs)))
            (equal target (cdr (second inputs))))
       descriptor)
      ((and (= 2 (length inputs)) seq-type target)
       (let* ((key (list seq-type target
                         (knowledge-entry-expression descriptor)
                         (knowledge-entry-guard descriptor)
                         (knowledge-entry-auxiliary-code descriptor)))
              (bucket (gethash descriptor *polymorphic-descriptor-executables*))
              (cached (assoc key bucket :test #'equal)))
         (if cached
             (and (knowledge-entry-p (cdr cached)) (cdr cached))
             (let ((inst (ignore-errors
                          (instantiate-entry-template descriptor
                                                      :input-types (list seq-type target)
                                                      :target :bool
                                                      :certify-p nil
                                                      :register-p nil))))
               (when inst (sync-entry-executable inst))
               (setf (gethash descriptor *polymorphic-descriptor-executables*)
                     (acons key (or inst :incompatible) bucket))
               inst)))))))

(defun evaluate-descriptor-entry-on-frame (descriptor frame-facts seq-type target pairs ledger)
  "Evaluate a (possibly polymorphic) `:descriptor` knowledge-entry on PAIRS via its
synchronized `entry-executable`. Returns `:satisfied`, `:violated`, or `:neutral`."
  (let* ((meta (knowledge-entry-metadata descriptor))
         (req-facts (getf meta :frame-facts))
         (active (and (subsetp req-facts frame-facts)
                      (resolve-descriptor-for-types descriptor seq-type target))))
    (cond
      ((not (subsetp req-facts frame-facts)) (or (getf meta :mismatch) :neutral))
      ((null active)
       (when ledger (charge ledger :orientation 1))
       :neutral)
      ((null pairs)
       (when ledger (charge ledger :orientation 1))
       :neutral)
      (t
       (let* ((guard (knowledge-entry-guard active))
              (aux (knowledge-entry-auxiliary-code active))
              (trivial-guard-p (equal guard (lit :bool t)))
              (selected (if trivial-guard-p
                            pairs
                            (remove-if-not
                             (lambda (pair)
                               (multiple-value-bind (val status)
                                   (eval-entry-slot active :guard (list (car pair) (cdr pair))
                                                    :ledger ledger :category :orientation
                                                    :check-types-p nil)
                                 (and (eq status :value) val)))
                             pairs))))
         (if (null selected)
             :neutral
             (let ((incomplete-p nil))
               (dolist (pair selected
                        (cond
                          (incomplete-p :neutral)
                          ((or (null aux)
                               (some (lambda (pair)
                                       (multiple-value-bind (val status)
                                           (eval-entry-slot active :aux (list (car pair) (cdr pair))
                                                            :ledger ledger :category :orientation
                                                            :check-types-p nil)
                                         (and (eq status :value) val)))
                                     selected))
                           :satisfied)
                          (t :neutral)))
                 (multiple-value-bind (val status)
                     (eval-entry-slot active :expr (list (car pair) (cdr pair))
                                      :ledger ledger :category :orientation
                                      :check-types-p nil)
                   (cond
                     ((not (eq status :value))
                      (setf incomplete-p t))
                     ((null val)
                      (return (or (getf meta :failure) :violated)))))))))))))

(defun canonical-probe-codes (c-inputs c-sort)
  "Small closed probe ASTs for a `:code` parameter `(c-inputs -> c-sort)` used to sample a
higher-order function across non-degenerate behaviors."
  (unless (function-sort-p c-sort)
    (cond
      ((or (eq c-sort :int) (gf-type-p c-sort))
       (let ((one (if (eq c-sort :int) 1 (mod 1 (second c-sort))))
             (matching (remove-if-not (lambda (s) (equal (cdr s) c-sort)) c-inputs)))
         (cond
           ((>= (length matching) 2)
            (let ((v0 (var (caar matching) c-sort))
                  (v1 (var (caadr matching) c-sort)))
              (list (term `(- ,v0 ,v1)) (term `(+ ,v0 ,v1)))))
           ((= (length matching) 1)
            (let ((v0 (var (caar matching) c-sort)))
              (list (term `(+ ,v0 ,(lit c-sort one))) (term `(+ ,v0 ,v0)))))
           (t (list (lit c-sort 0) (lit c-sort one))))))
      ((eq c-sort :bool)
       (let ((first-spec (first c-inputs)))
         (cond
           ((and first-spec (eq :int (cdr first-spec)))
            (list (term `(< 0 ,(var (car first-spec) :int))) (lit :bool nil)))
           (first-spec
            (let ((pt (cdr first-spec)))
              (list (term `(= ,(var (car first-spec) pt) ,(lit pt (default-value-for-type pt))))
                    (lit :bool nil))))
           (t (list (lit :bool t) (lit :bool nil))))))
      (t
       (let ((same (find c-sort c-inputs :key #'cdr :test #'equal))
             (def (lit c-sort (default-value-for-type c-sort))))
         (if same (list (var (car same) c-sort) def) (list def)))))))

(defun probe-values-for-type (type)
  (cond
    ((eq type :int) '(0 1))
    ((eq type :bool) '(nil t))
    ((gf-type-p type) (list 0 (mod 1 (second type))))
    ((code-type-p type) (canonical-probe-codes (code-inputs type) (code-sort type)))))

(defun probe-sequences-for-type (seq-type)
  (let ((elem (second seq-type)))
    (cond
      ((eq elem :int) '(() (2) (-1 2 5) (10 13 19)))
      ((gf-type-p elem)
       (let ((m (second elem)))
         (list '() (list (mod 1 m)) (list 0 (mod 1 m) (mod 2 m)))))
      ((eq elem :bool) '(() (t) (nil t nil)))
      ((seq-type-p elem)
       (unless (code-type-p (second elem))
         (let ((d (default-value-for-type (second elem))))
           (list '() (list (list d)) (list '() (list d d))))))
      ((not (code-type-p elem))
       (let ((d (default-value-for-type elem)))
         (list '() (list d) (list d d)))))))

(defun sample-entry-io-pairs (entry seq-spec ledger)
  "Run a `:function` ENTRY on canonical probe sequences and return observed `(in . out)` pairs."
  (when (and (eq :function (knowledge-entry-kind entry))
             seq-spec
             (knowledge-entry-expression entry))
    (let* ((inputs (knowledge-entry-inputs entry))
           (body (knowledge-entry-expression entry))
           (extra-specs (remove seq-spec inputs :test #'eq))
           (extra-options (mapcar (lambda (s) (probe-values-for-type (cdr s))) extra-specs))
           (seqs (and (notany #'null extra-options)
                      (probe-sequences-for-type (cdr seq-spec)))))
      (when seqs
        (let ((tuples (subseq (cartesian-product-lists extra-options)
                              0 (min 4 (length (cartesian-product-lists extra-options)))))
              (pairs nil))
          (dolist (tuple tuples)
            (let ((extra-alist (mapcar #'cons (mapcar #'car extra-specs) tuple)))
              (dolist (seq seqs)
                (let* ((args (loop for spec in inputs
                                   collect (if (eq spec seq-spec)
                                               seq
                                               (cdr (assoc (car spec) extra-alist :test #'eql)))))
                       (run (evaluate body inputs args :budget 2000 :ledger ledger)))
                  (when (eq :value (evaluation-status run))
                    (pushnew (cons seq (evaluation-value run)) pairs :test #'equal))))))
          (let ((ordered (nreverse pairs)))
            (when (some #'car ordered)
              ordered)))))))

(defun observe-io-search (pairs inputs target &key operators literals constants body-bound domain pair-keys ledger)
  "Run bounded enumerative observation search over `(in . out)` PAIRS and return the `observation-job`."
  (let* ((rows (loop for p in pairs for i from 0
                     collect (make-row :key i :known (list (car p) (cdr p)) :requirement (lit :bool t))))
         (schema (make-schema :domain domain :inputs inputs :target target))
         (frame (make-frame schema rows))
         (lang (make-language (schema-domain schema) inputs
                              :operators operators :literals literals :constants constants))
         (bound (+ 1 (language-header-size lang target) body-bound))
         (scope (make-observation-scope frame lang :pairs pair-keys))
         (obs (start-observation-search scope)))
    (resume-observation-search obs bound 200000)
    (when ledger
      (charge ledger :discovery (min 32 (ledger-total (observation-job-ledger obs)))))
    obs))

(defun obs-expr (obs expr)
  (let ((rec (find-observation obs expr)))
    (and rec (observed-expression-expression rec))))

(defun obs-agrees-p (obs left right)
  (observed-agreement-p (find-observation obs left) (find-observation obs right)))

(defun synthesize-io-descriptor-specs (entry shape-facts pairs ho-p ledger)
  "Discover behavioral `:descriptor` AST specifications for ENTRY by running enumerative
observation search over its sampled I/O PAIRS and certifying specs backed by structural `shape-facts`."
  (let ((seq-spec (getf shape-facts :seq-spec)))
    (when seq-spec
      (let* ((seq-type (cdr seq-spec))
             (target (knowledge-entry-target entry))
             (body (and (member (knowledge-entry-kind entry) '(:function :decoder-template))
                        (knowledge-entry-expression entry)))
             (pure-p (getf shape-facts :pure-p))
             (shape (getf shape-facts :shape))
             (base (getf shape-facts :base))
             (subset-p (getf shape-facts :subset-p))
             (rel-inputs (list (cons 0 seq-type) (cons 1 target)))
             (x0 (var 0 seq-type))
             (x1 (var 1 target))
             (empty-guard (term `(= ,x0 ())))
             (nonempty-guard (bool-not empty-guard))
             (empty-pairs (remove-if-not #'null pairs :key #'car))
             (nonempty-pairs (remove-if #'null pairs :key #'car))
             (specs nil)
             (shape-choice nil))
        (flet ((emit (id facet tier weight cost frame-facts guard holds witness
                      &key (failure :violated) necessary-p)
                 (push (list :id id :facet facet :tier tier :weight-bits weight :work-cost cost
                             :frame-facts frame-facts :guard guard :holds holds :witness witness
                             :failure failure :necessary-p (not (null necessary-p)))
                       specs)))
          ;; 1. Shape-delta facet: the shape the samples show, or without samples the one the
          ;;    body's recursion has. It is necessary when the two are the same.
          (when (seq-type-p target)
            (let* ((len0 (term `(length ,x0)))
                   (len1 (term `(length ,x1)))
                   (dec1 (term `(- ,len0 1)))
                   (longer (term `(< ,len0 ,len1)))
                   (shorter (term `(< ,len1 ,len0)))
                   (true (lit :bool t))
                   (false (lit :bool nil))
                   (lengths (remove-duplicates (list (op :length (second seq-type))
                                                     (op :length (second target)))))
                   (observed
                     (cond
                       ((null pairs) shape)
                       (nonempty-pairs
                        (let ((obs (observe-io-search nonempty-pairs rel-inputs :int
                                                      :operators (append lengths (list (op :- :int)))
                                                      :literals '(1)
                                                      :body-bound (body-size dec1 rel-inputs)
                                                      :ledger ledger))
                              (empty-ok-p (every (lambda (p) (null (cdr p))) empty-pairs)))
                          (cond
                            ((and empty-ok-p (obs-agrees-p obs len1 len0)) :preserving)
                            ((and empty-ok-p
                                  (some (lambda (p) (>= (length (car p)) 2)) nonempty-pairs)
                                  (obs-agrees-p obs len1 dec1))
                             :decrementing)
                            (t
                             (let* ((obs (observe-io-search pairs rel-inputs :bool
                                                            :operators (append lengths (list (op :< :int)))
                                                            :constants (list false)
                                                            :body-bound (body-size longer rel-inputs)
                                                            :ledger ledger))
                                    (under (find-observation obs shorter)))
                               (and (obs-agrees-p obs longer false)
                                    under
                                    (eq :complete (observed-expression-status under))
                                    (some #'identity (observed-expression-values under))
                                    :contracting)))))))))
              (destructuring-bind (&optional id weight guard holds witness)
                  (ecase observed
                    ((nil) nil)
                    (:preserving (list :DESC/LEN-EQ 6 true (term `(= ,len0 ,len1)) nonempty-guard))
                    (:decrementing (list :DESC/LEN-DEC-1 6 nonempty-guard (term `(= ,dec1 ,len1))
                                         (term `(< 1 ,len0))))
                    (:contracting (list :DESC/LEN-LE 5 true (bool-not longer) shorter)))
                (when id
                  (setf shape-choice id)
                  (emit id :shape-delta 1 weight 2 '(:seq-out) guard holds witness
                        :necessary-p (and pure-p (eq shape observed))))))
            (when (and body (seq-type-p (second target)) (or (null pairs) nonempty-pairs))
              (emit :DESC/OUTER-SHAPE-2D :shape-delta 1 4 2 '(:seq-2d-out)
                    nonempty-guard (lit :bool t) nil)))
          ;; 2. Boundary facet: what the empty sequence maps to, sampled or read off the body.
          (when (or (seq-type-p target) (eq target :int))
            (let* ((base-lit (if (seq-type-p target) (lit target nil) (lit :int 0)))
                   (base-p (and base (equal (ast-value base) (ast-value base-lit)))))
              (when (cond (empty-pairs
                           (obs-agrees-p (observe-io-search
                                          empty-pairs rel-inputs target
                                          :literals (when (eq target :int) '(0))
                                          :constants (when (seq-type-p target) (list base-lit))
                                          :body-bound (max (body-size x1 rel-inputs)
                                                           (body-size base-lit rel-inputs))
                                          :ledger ledger)
                                         x1 base-lit))
                          ((null pairs) base-p))
                (emit (if (seq-type-p target) :DESC/EMPTY->EMPTY :DESC/EMPTY->ZERO) :boundary 1 4 2 nil
                      empty-guard (term `(= ,x1 ,base-lit)) nil
                      :necessary-p (and pure-p base-p)))))
          ;; 3. Sampled-content facet
          (when (and ho-p (eq shape-choice :DESC/LEN-EQ))
            (emit :DESC/POINTWISE-MAP :sampled-content 2 5 6 '(:seq-out)
                  nonempty-guard (term `(= (length ,x0) (length ,x1))) nil))
          (when (and body ho-p (not (seq-type-p target)) (or (null pairs) nonempty-pairs))
            (emit :DESC/SCALAR-REDUCTION :sampled-content 2 5 6 '(:seq-in :scalar-out)
                  nonempty-guard (lit :bool t) nil))
          (let ((step-delta-p nil))
            (when (and (equal seq-type '(:seq :int)) (equal target '(:seq :int))
                       (eq shape-choice :DESC/LEN-EQ) nonempty-pairs)
              (let ((elem-pairs nil)
                    (pair-keys nil)
                    (idx 0))
                (dolist (p nonempty-pairs)
                  (when (and (>= (length (car p)) 2) (= (length (car p)) (length (cdr p))))
                    (let ((start idx))
                      (loop for a in (car p) for b in (cdr p) do
                        (push (cons a b) elem-pairs)
                        (incf idx))
                      (loop for k from start below (1- idx) do
                        (push (list k (1+ k)) pair-keys)))))
                (when pair-keys
                  (let* ((elem-inputs '((0 . :int) (1 . :int)))
                         (diff-proto (term `(- ,(var 1 :int) ,(var 0 :int))))
                         (s-obs (observe-io-search (nreverse elem-pairs) elem-inputs :int
                                                   :operators (list (op :- :int))
                                                   :body-bound (body-size diff-proto elem-inputs)
                                                   :pair-keys (nreverse pair-keys)
                                                   :ledger ledger))
                         (inv (loop for bucket in (reverse (observation-job-buckets s-obs))
                                    thereis (and (observation-bucket-invariant-p bucket)
                                                 (loop for m in (reverse (observation-bucket-members bucket))
                                                       for expr = (observed-expression-expression m)
                                                       when (and (member 0 (free-vars expr))
                                                                 (member 1 (free-vars expr)))
                                                         return expr)))))
                    (when inv
                      (let ((d0 (instantiate inv (list (cons 0 (term `(at ,x0 0)))
                                                       (cons 1 (term `(at ,x1 0)))) :var))
                            (d1 (instantiate inv (list (cons 0 (term `(at ,x0 1)))
                                                       (cons 1 (term `(at ,x1 1)))) :var)))
                        (setf step-delta-p t)
                        (emit :DESC/CONSTANT-STEP-DELTA :sampled-content 2 4 8 '(:int-seq-out)
                              nonempty-guard
                              (bool-and (term `(= (length ,x0) (length ,x1)))
                                        (term `(if (< (length ,x0) 2) t (= ,d0 ,d1))))
                              (term `(< 1 (length ,x0)))
                              :failure :neutral)))))))
            (when (and (seq-type-p target) (equal (second seq-type) (second target)) (not step-delta-p))
              (let* ((elem (second seq-type))
                     (m0-proto (term `(member (at ,x1 0) ,x0)))
                     (m1-proto (term `(member (at ,x1 1) ,x0)))
                     (ne-out1 (remove-if (lambda (p) (null (cdr p))) nonempty-pairs))
                     (ne-out2 (remove-if (lambda (p) (< (length (cdr p)) 2)) nonempty-pairs)))
                (flet ((build-subset-ast (m0-expr m1-expr)
                         (term `(if (= ,x1 ())
                                    t
                                    ,(bool-and m0-expr
                                               (bool-and (term `(member (at ,x1 (- (length ,x1) 1)) ,x0))
                                                         (term `(if (< 1 (length ,x1)) ,m1-expr t))))))))
                  (cond
                    (ne-out1
                     (let* ((sample (or ne-out2 ne-out1))
                            (proto (if ne-out2 m1-proto m0-proto))
                            (m-obs (observe-io-search
                                    sample rel-inputs :bool
                                    :operators (list (op :member elem) (op :at target))
                                    :literals (if ne-out2 '(0 1) '(0))
                                    :constants (list (lit :bool t))
                                    :body-bound (body-size proto rel-inputs)
                                    :ledger ledger))
                            (m0-ast (and (obs-agrees-p m-obs m0-proto (lit :bool t))
                                         (obs-expr m-obs m0-proto)))
                            (m1-ast (if ne-out2
                                        (and (obs-agrees-p m-obs m1-proto (lit :bool t))
                                             (obs-expr m-obs m1-proto))
                                        m1-proto)))
                       (when (and m0-ast m1-ast)
                         (let* ((holds-ast (build-subset-ast m0-ast m1-ast))
                                (probe-desc (make-knowledge-entry
                                             :kind :descriptor :inputs rel-inputs :target :bool
                                             :guard nonempty-guard :expression holds-ast)))
                           (when (eq :satisfied
                                     (evaluate-descriptor-entry-on-frame
                                      probe-desc '(:seq-out) seq-type target nonempty-pairs ledger))
                             (emit :DESC/SUBSET-ELEMENTS :sampled-content 2 (if subset-p 6 4) 8
                                   '(:seq-out) nonempty-guard holds-ast nil))))))
                    ((and (null pairs) subset-p)
                     (emit :DESC/SUBSET-ELEMENTS :sampled-content 2 6 8 '(:seq-out)
                           nonempty-guard (build-subset-ast m0-proto m1-proto) nil)))))))
          (nreverse specs))))))

(defun type-facet-clause (ho-p seq-in-p target)
  "The `:type` `descriptor-clause` for an entry's signature."
  (if (not seq-in-p)
      (make-descriptor-clause :id :DESC/SCALAR->SCALAR :facet :type :tier 1
                              :status :necessary :weight-bits 1 :work-cost 1)
      (make-descriptor-clause
       :id (cond ((and ho-p (seq-type-p target)) :DESC/HO-SEQ->SEQ)
                 (ho-p :DESC/HO-SEQ->SCALAR)
                 ((seq-type-p target) :DESC/SEQ->SEQ)
                 (t :DESC/SEQ->SCALAR))
       :facet :type :tier 1 :status :necessary :weight-bits 2 :work-cost 1)))

(defun evaluate-structural-clause-on-frame (clause frame-facts pairs)
  "Evaluate a `:type` or `:algebraic` metadata clause against FRAME-FACTS and PAIRS."
  (ecase (descriptor-clause-facet clause)
    (:type
     (ecase (descriptor-clause-id clause)
       (:DESC/SCALAR->SCALAR
        (if (subsetp '(:scalar-in :scalar-out) frame-facts) :satisfied :neutral))
       ((:DESC/HO-SEQ->SEQ :DESC/SEQ->SEQ)
        (if (subsetp '(:seq-in :seq-out) frame-facts) :satisfied :violated))
       ((:DESC/HO-SEQ->SCALAR :DESC/SEQ->SCALAR)
        (if (subsetp '(:seq-in :scalar-out) frame-facts) :satisfied :violated))))
    (:algebraic
     (if pairs :satisfied :neutral))))

(defun generalize-descriptor-ast (ast new-inputs)
  "Rebuild descriptor AST over shallower representative NEW-INPUTS when type-safe."
  (when ast
    (ignore-errors
     (let ((rebuilt
             (map-ast
              (lambda (node meta)
                (case (ast-meta-kind meta)
                  (:var (let ((spec (assoc (ast-meta-id meta) new-inputs)))
                          (and spec (var (car spec) (cdr spec)))))
                  (:lit (when (and (seq-type-p (ast-meta-type meta))
                                   (null (ast-meta-value meta)))
                          (lit '(:seq :int) nil)))
                  (:app (let* ((name (operator-name (first node)))
                               (args (rest node))
                               (arg-types (mapcar (lambda (a) (expression-type a new-inputs)) args)))
                          (case name
                            ((:+ :- :* :/ :< :=)
                             (apply #'app (op name (first arg-types)) args))
                            (:if (apply #'app (op :if (second arg-types)) args))
                            (:length (app (op :length (second (first arg-types))) (first args)))
                            (:at (apply #'app (op :at (first arg-types)) args))
                            (:member (apply #'app (op :member (first arg-types)) args))
                            (otherwise nil))))
                  (otherwise nil)))
              ast)))
       (and rebuilt (expression-type rebuilt new-inputs) rebuilt)))))

(defun canonicalize-auto-descriptor (raw)
  "Normalize auto-descriptor RAW to shallow `(:seq :int)` / `:int` representative inputs
whenever instantiating that shallow template back at RAW's concrete inputs reproduces RAW
bit-identically (so 2D and 1D batteries share the same polymorphic `:DESC/*` entry)."
  (let* ((orig-inputs (knowledge-entry-inputs raw))
         (in0 (cdr (first orig-inputs)))
         (in1 (cdr (second orig-inputs)))
         (base-inputs (list (cons 0 (if (seq-type-p in0) '(:seq :int) :int))
                            (cons 1 (cond ((seq-type-p in1) '(:seq :int))
                                          ((eq in1 :bool) :bool)
                                          (t :int))))))
    (if (equal orig-inputs base-inputs)
        raw
        (let* ((g-expr (generalize-descriptor-ast (knowledge-entry-expression raw) base-inputs))
               (g-guard (generalize-descriptor-ast (knowledge-entry-guard raw) base-inputs))
               (orig-aux (knowledge-entry-auxiliary-code raw))
               (g-aux (and orig-aux (generalize-descriptor-ast orig-aux base-inputs))))
          (if (and g-expr g-guard (or (null orig-aux) g-aux))
              (let* ((cand (let ((c (copy-knowledge-entry raw)))
                             (setf (knowledge-entry-domain c) :int
                                   (knowledge-entry-inputs c) base-inputs
                                   (knowledge-entry-expression c) g-expr
                                   (knowledge-entry-guard c) g-guard
                                   (knowledge-entry-auxiliary-code c) g-aux)
                             c))
                     (roundtrip (ignore-errors
                                 (instantiate-entry-template cand
                                                             :input-types (list in0 in1)
                                                             :target :bool
                                                             :certify-p nil
                                                             :register-p nil))))
                (if (and roundtrip
                         (equal (knowledge-entry-expression roundtrip)
                                (knowledge-entry-expression raw))
                         (equal (knowledge-entry-guard roundtrip)
                                (knowledge-entry-guard raw))
                         (equal (knowledge-entry-auxiliary-code roundtrip)
                                (knowledge-entry-auxiliary-code raw)))
                    cand
                    raw))
              raw)))))

(defun descriptor-templates-compatible-p (left right)
  "True when `:descriptor` LEFT instantiates cleanly to RIGHT's inputs/ASTs and shares
identical metadata semantics (`:frame-facts`, `:mismatch`, `:failure`)."
  (let ((m1 (knowledge-entry-metadata left))
        (m2 (knowledge-entry-metadata right)))
    (and (equal (getf m1 :frame-facts) (getf m2 :frame-facts))
         (eq (getf m1 :mismatch) (getf m2 :mismatch))
         (eq (getf m1 :failure) (getf m2 :failure))
         (let ((inst (ignore-errors
                      (instantiate-entry-template
                       left
                       :input-types (mapcar #'cdr (knowledge-entry-inputs right))
                       :target (knowledge-entry-target right)
                       :certify-p nil
                       :register-p nil))))
           (and inst
                (equal (knowledge-entry-expression inst) (knowledge-entry-expression right))
                (equal (knowledge-entry-guard inst) (knowledge-entry-guard right))
                (equal (knowledge-entry-auxiliary-code inst)
                       (knowledge-entry-auxiliary-code right)))))))

(defun attach-descriptor-target (descriptor target-id library)
  "Ensure TARGET-ID is listed in DESCRIPTOR's `:describes` edge and indexed in LIBRARY."
  (let* ((ktarget (canonical-op-name target-id))
         (existing-edge (first (knowledge-edges-from descriptor :describes library))))
    (cond
      ((null existing-edge)
       (add-knowledge-edge descriptor :describes ktarget))
      ((not (member ktarget (rest existing-edge) :test #'eq))
       (unindex-knowledge-entry descriptor library)
       (setf (knowledge-entry-edges descriptor)
             (substitute (append existing-edge (list ktarget))
                         existing-edge
                         (knowledge-entry-edges descriptor)
                         :test #'eq))
       (index-knowledge-entry descriptor library)
       (invalidate-knowledge-caches library)))
    descriptor))

(defun prune-auto-descriptors-for-entry (entry library)
  "Detach ENTRY from shared `:auto-descriptor` entries before re-installing its profile."
  (let* ((kname (knowledge-entry-id entry))
         (auto-ids (loop for edge in (knowledge-edges-to kname :describes library)
                         for d = (find-knowledge-entry (second edge) library)
                         when (and d (eq :descriptor (knowledge-entry-kind d))
                                   (getf (knowledge-entry-metadata d) :auto-descriptor))
                           collect (knowledge-entry-id d))))
    (when auto-ids
      (detach-entry-from-auto-descriptors kname library)
      (setf (knowledge-entry-edges entry)
            (remove-if (lambda (edge)
                         (and (eq :described-by (first edge))
                              (null (cddr edge))
                              (member (second edge) auto-ids :test #'eq)))
                       (knowledge-entry-edges entry))))))

(defun register-entry-io-descriptors (entry io-specs seq-type library)
  "Install or reuse shared polymorphic `:descriptor` entries in LIBRARY for ENTRY's IO-SPECS.
Returns an alist `((spec-id . descriptor-entry) ...)`."
  (let* ((kname (knowledge-entry-id entry))
         (target (knowledge-entry-target entry))
         (rel-inputs (list (cons 0 seq-type) (cons 1 target)))
         (installed nil))
    (prune-auto-descriptors-for-entry entry library)
    (dolist (spec io-specs (nreverse installed))
      (destructuring-bind (&key id facet tier weight-bits work-cost frame-facts
                                guard holds witness failure necessary-p)
          spec
        (declare (ignore necessary-p))
        (let* ((raw (canonicalize-auto-descriptor
                     (make-knowledge-entry
                      :id id
                      :kind :descriptor
                      :domain (knowledge-entry-domain entry)
                      :inputs rel-inputs
                      :target :bool
                      :expression holds
                      :guard (or guard (lit :bool t))
                      :auxiliary-code witness
                      :status :empirical
                      :edges (list (list :describes kname))
                      :metadata (list :auto-descriptor t :concept id :facet facet :tier tier
                                      :weight-bits weight-bits :work-cost work-cost
                                      :frame-facts frame-facts :failure failure)
                      :library library)))
               (existing (find-knowledge-entry id library))
               (chosen
                 (cond
                   ((and existing
                         (eq :descriptor (knowledge-entry-kind existing))
                         (descriptor-templates-compatible-p existing raw))
                    (attach-descriptor-target existing kname library))
                   (existing
                    (let ((qualified (keyword-id "~A/~A" kname id)))
                      (setf (knowledge-entry-id raw) qualified)
                      (register-knowledge-entry raw :library library)))
                   (t
                    (register-knowledge-entry raw :library library)))))
          (add-knowledge-edge entry :described-by (knowledge-entry-id chosen))
          (push (cons id chosen) installed))))))

(defun descriptor-predicate-snapshot (descriptor)
  "Intrinsic semantic snapshot of a `:descriptor` entry's predicate, independent of which
entries currently share its `:describes` edge."
  (let ((exprs (list (knowledge-entry-expression descriptor)
                     (knowledge-entry-guard descriptor)
                     (knowledge-entry-trigger descriptor)
                     (knowledge-entry-auxiliary-code descriptor)))
        (meta (knowledge-entry-metadata descriptor)))
    (list :semantics (list +simulator-version+ +encoding-version+)
          :kind (knowledge-entry-kind descriptor)
          :domain (copy-tree (knowledge-entry-domain descriptor))
          :inputs (copy-tree (knowledge-entry-inputs descriptor))
          :target (copy-tree (knowledge-entry-target descriptor))
          :code (mapcar #'ast->sexp exprs)
          :meta (list (copy-tree (getf meta :frame-facts))
                      (getf meta :mismatch)
                      (getf meta :failure))
          :dependencies (expression-dependencies exprs))))

(defun entry-descriptor-pair-snapshot (entry descriptor)
  (let ((fn-deps (and (eq :function (knowledge-entry-kind entry))
                      (defined-function-p (knowledge-entry-id entry))
                      (expression-dependencies (list (op (knowledge-entry-id entry)))))))
    (list (knowledge-statement-snapshot entry)
          fn-deps
          (descriptor-predicate-snapshot descriptor))))

(defun entry-descriptor-necessary-p (entry-or-id desc-or-id &optional (library *knowledge-library*))
  "True when DESCRIPTOR is a current necessary condition of ENTRY-OR-ID: either DESCRIPTOR
carries its own current `:necessary` certificate, or ENTRY-OR-ID's `:descriptor-profile`
attests `:status :necessary` with a current `(entry, descriptor)` statement snapshot."
  (let ((entry (if (knowledge-entry-p entry-or-id)
                   entry-or-id
                   (and entry-or-id library (find-knowledge-entry entry-or-id library))))
        (desc (if (knowledge-entry-p desc-or-id)
                  desc-or-id
                  (and desc-or-id library (find-knowledge-entry desc-or-id library)))))
    (and desc
         (or (knowledge-evidence-current-p desc :necessary)
             (and entry
                  (let* ((did (knowledge-entry-id desc))
                         (concept (getf (knowledge-entry-metadata desc) :concept))
                         (clause (find-if (lambda (c)
                                            (or (eq (descriptor-clause-id c) did)
                                                (and concept (eq (descriptor-clause-id c) concept))))
                                          (knowledge-entry-descriptor-profile entry))))
                    (and clause
                         (eq :necessary (descriptor-clause-status clause))
                         (getf clause :snapshot)
                         (equalp (getf clause :snapshot)
                                 (entry-descriptor-pair-snapshot entry desc)))))))))

(defun entry-trigger-compatible-p (entry frame seq-input-id &optional ledger)
  "Fast-gate conditional ENTRY via its `knowledge-entry-trigger` AST over `(seq-in, out)`.
Returns NIL only when concrete `(in . out)` pairs exist and some pair evaluates cleanly to `NIL`."
  (let ((trigger (and (knowledge-entry-p entry) (knowledge-entry-trigger entry))))
    (if (null trigger)
        t
        (let* ((schema (frame-schema frame))
               (seq-type (cdr (assoc seq-input-id (schema-inputs schema))))
               (target (schema-target schema))
               (pairs (and seq-type (frame-concrete-pairs frame seq-input-id))))
          (if (null pairs)
              t
              (let* ((src-seq (cdr (find-if #'seq-type-p (knowledge-entry-inputs entry) :key #'cdr)))
                     (src-targ (knowledge-entry-target entry))
                     (probe (and src-seq src-targ
                                 (resolve-descriptor-for-types
                                  (make-knowledge-entry :kind :descriptor
                                                        :inputs (list (cons 0 src-seq) (cons 1 src-targ))
                                                        :target :bool
                                                        :expression trigger)
                                  seq-type target))))
                (or (null probe)
                    (every (lambda (pair)
                             (multiple-value-bind (val status)
                                 (eval-entry-slot probe :expr (list (car pair) (cdr pair))
                                                  :ledger ledger :category :orientation
                                                  :check-types-p nil)
                               (or (not (eq status :value)) val)))
                           pairs))))))))

(defun compute-entry-descriptor-profile (entry &optional (library *knowledge-library*) ledger)
  "Synthesize and register shared polymorphic `:descriptor` entries for ENTRY, assemble its
portable `:descriptor-profile` plist list and `compositional-name`, and index them in LIBRARY."
  (when (knowledge-entry-p entry)
    (let* ((kname (knowledge-entry-id entry))
           (kind (knowledge-entry-kind entry))
           (inputs (knowledge-entry-inputs entry))
           (target (knowledge-entry-target entry))
           (body (and (member kind '(:function :decoder-template))
                      (knowledge-entry-expression entry)))
           (ho-p (not (null (find-if #'code-type-p inputs :key #'cdr))))
           (shape-facts (function-shape-facts kname inputs target body))
           (seq-spec (getf shape-facts :seq-spec)))
      (when (and (eq kind :function) (null (knowledge-entry-trigger entry)))
        (let ((fdef (find-function-definition kname)))
          (when fdef
            (setf (knowledge-entry-trigger entry) (compute-function-descriptor fdef)))))
      (let* ((pairs (sample-entry-io-pairs entry seq-spec ledger))
             (io-specs (synthesize-io-descriptor-specs entry shape-facts pairs ho-p ledger))
             (installed (when (and library seq-spec (eq entry (find-knowledge-entry kname library)))
                          (register-entry-io-descriptors entry io-specs (cdr seq-spec) library)))
             (io-clauses
               (loop for spec in io-specs
                     for desc = (cdr (assoc (getf spec :id) installed))
                     for nec-p = (getf spec :necessary-p)
                     collect (make-descriptor-clause
                              :id (if desc (knowledge-entry-id desc) (getf spec :id))
                              :facet (getf spec :facet)
                              :tier (getf spec :tier)
                              :status (if nec-p :necessary :empirical)
                              :weight-bits (getf spec :weight-bits)
                              :work-cost (getf spec :work-cost)
                              :snapshot (when (and nec-p desc)
                                          (entry-descriptor-pair-snapshot entry desc)))))
             (alg-clauses
               (when library
                 (append
                  (when (knowledge-edges-from entry :abstracts library)
                    (list (make-descriptor-clause :id :DESC/ABSTRACTS-FAMILY :facet :algebraic :tier 3
                                                  :status :empirical :weight-bits 4 :work-cost 4)))
                  (when (or (knowledge-edges-from entry :functor-laws library)
                            (knowledge-edges-from entry :laws library))
                    (list (make-descriptor-clause :id :DESC/ALGEBRAIC-LAW :facet :algebraic :tier 3
                                                  :status :empirical :weight-bits 4 :work-cost 8))))))
             (clauses (append (list (type-facet-clause ho-p (not (null seq-spec)) target))
                              io-clauses
                              alg-clauses)))
        (setf (knowledge-entry-descriptor-profile entry) clauses
              (knowledge-entry-compositional-name entry) (derive-compositional-name entry clauses))
        (when library
          (index-knowledge-entry-compositional-address entry library))
        clauses))))

(defun evaluate-frame-descriptors (frame seq-input-id &key (library *knowledge-library*) ledger
                                                           describing (max-tier 2))
  "The verdict of the `:descriptor` entries of LIBRARY on FRAME, read through its input
SEQ-INPUT-ID, as an alist `(descriptor-id . verdict)` with verdicts `:satisfied`, `:violated`,
and `:neutral`. Shared polymorphic descriptors are stored once in LIBRARY and evaluated once."
  (let* ((schema (frame-schema frame))
         (seq-type (cdr (assoc seq-input-id (schema-inputs schema))))
         (target (schema-target schema))
         (facts (signature-facts (seq-type-p seq-type) target))
         (pairs (frame-concrete-pairs frame seq-input-id))
         (stated (make-hash-table :test #'equal)))
    (loop for descriptor in (knowledge-entries-of-kind :descriptor library)
          for meta = (knowledge-entry-metadata descriptor)
          when (and (<= (or (getf meta :tier) 1) max-tier)
                    (or (null describing)
                        (some (lambda (edge) (intersection (rest edge) describing))
                              (knowledge-edges-from descriptor :describes library))))
            collect (cons (knowledge-entry-id descriptor)
                          (let ((statement (list (knowledge-entry-expression descriptor)
                                                 (knowledge-entry-guard descriptor)
                                                 (knowledge-entry-auxiliary-code descriptor)
                                                 (getf meta :frame-facts)
                                                 (getf meta :mismatch) (getf meta :failure))))
                            (multiple-value-bind (verdict found-p) (gethash statement stated)
                              (if found-p
                                  verdict
                                  (setf (gethash statement stated)
                                        (evaluate-descriptor-entry-on-frame
                                         descriptor facts seq-type target pairs ledger)))))))))

(defun frame-addressed-entries (frame seq-input-id &key (library *knowledge-library*) ledger
                                                         (verdicts (evaluate-frame-descriptors
                                                                    frame seq-input-id
                                                                    :library library :ledger ledger)))
  "The entries of LIBRARY that FRAME addresses: those indexed under a concept that one of
their descriptors shows FRAME to satisfy (`find-knowledge-entries-by-address`), each with the
number of such concepts, most first, as `((entry . count) ...)`."
  (let ((counts nil))
    (loop for (descriptor-id . verdict) in verdicts
          for descriptor = (find-knowledge-entry descriptor-id library)
          for concept = (and descriptor (or (getf (knowledge-entry-metadata descriptor) :concept)
                                            descriptor-id))
          when (and concept (eq :satisfied verdict))
            do (dolist (entry (find-knowledge-entries-by-address concept library))
                 (when (member (knowledge-entry-id entry)
                               (loop for edge in (knowledge-edges-from descriptor :describes library)
                                     append (rest edge)))
                   (incf (cdr (or (assoc entry counts)
                                  (first (push (cons entry 0) counts))))))))
    (stable-sort (nreverse counts) #'> :key #'cdr)))

(defun score-entry-by-descriptors (entry-or-id frame seq-input-id
                                   &key (library *knowledge-library*) ledger extra-fo-specs necessary-only-p
                                        verdicts)
  "Evaluate the `:descriptor` entries and structural/algebraic profile clauses of ENTRY-OR-ID on FRAME.
Returns `(VALUES compatible-p policy-delta-bits matched-clause-ids)`; lower delta is better.
Only current `:necessary` descriptors on a unary-FO `:function` can reject an entry with
`compatible-p = NIL`; uncertified descriptors act purely as soft policy hints."
  (let* ((fn-name (if (knowledge-entry-p entry-or-id)
                      (knowledge-entry-id entry-or-id)
                      (canonical-op-name entry-or-id)))
         (entry (if (knowledge-entry-p entry-or-id)
                    entry-or-id
                    (and library (find-knowledge-entry fn-name library))))
         (clauses (and entry
                       (or (knowledge-entry-descriptor-profile entry)
                           (compute-entry-descriptor-profile entry library ledger))))
         (schema (frame-schema frame))
         (seq-type (cdr (assoc seq-input-id (schema-inputs schema))))
         (target (schema-target schema))
         (frame-facts (signature-facts (seq-type-p seq-type) target))
         (pairs (frame-concrete-pairs frame seq-input-id))
         (can-prune-p (and fn-name (null extra-fo-specs)
                           (or (null entry) (eq :function (knowledge-entry-kind entry)))))
         (descriptors
           (when (and fn-name library)
             (let ((seen nil) (out nil))
               (dolist (edge (reverse (knowledge-edges-to fn-name :describes library)) (nreverse out))
                 (let ((did (second edge)))
                   (unless (member did seen :test #'eq)
                     (push did seen)
                     (let ((d (find-knowledge-entry did library)))
                       (when (and d (eq :descriptor (knowledge-entry-kind d)))
                         (push d out)))))))))
         (delta 0)
         (matched nil))
    (unless necessary-only-p
      (dolist (clause clauses)
        (when (member (descriptor-clause-facet clause) '(:type :algebraic))
          (charge ledger :orientation (descriptor-clause-work-cost clause))
          (case (evaluate-structural-clause-on-frame clause frame-facts pairs)
            (:satisfied
             (decf delta (descriptor-clause-weight-bits clause))
             (push (descriptor-clause-id clause) matched))
            (:violated
             (incf delta (ceiling (descriptor-clause-weight-bits clause) 2)))))))
    (dolist (desc descriptors)
      (let ((certified-p (entry-descriptor-necessary-p entry desc library)))
        (unless (and necessary-only-p (not certified-p))
          (let ((verdict (let ((known (assoc (knowledge-entry-id desc) verdicts)))
                           (if known
                               (cdr known)
                               (evaluate-descriptor-entry-on-frame desc frame-facts seq-type target
                                                                   pairs ledger)))))
            (when (and can-prune-p certified-p (eq verdict :violated))
              (return-from score-entry-by-descriptors (values nil most-positive-fixnum nil)))
            (unless necessary-only-p
              (let* ((meta (knowledge-entry-metadata desc))
                     (did (knowledge-entry-id desc))
                     (cid (or (getf meta :concept) did))
                     (clause (find-if (lambda (c)
                                        (or (eq (descriptor-clause-id c) did)
                                            (eq (descriptor-clause-id c) cid)))
                                      clauses))
                     (weight (if clause
                                 (descriptor-clause-weight-bits clause)
                                 (or (getf meta :weight-bits) 0))))
                (when (plusp weight)
                  (case verdict
                    (:satisfied
                     (decf delta weight)
                     (when cid (push cid matched)))
                    (:violated
                     (incf delta (ceiling weight 2)))))))))))
    (values t delta (nreverse matched))))

(defun library-function-descriptor-compatible-p (frame seq-input-id fn-name ledger)
  "Only current necessary-condition evidence authorizes descriptor pruning.
Uncertified descriptors are hints; no function shape implies a hard rejection."
  (nth-value 0 (score-entry-by-descriptors fn-name frame seq-input-id
                                           :ledger ledger :necessary-only-p t)))
