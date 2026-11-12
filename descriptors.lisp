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

(defparameter *descriptor-table*
  (flet ((lists (test)
           (lambda (in out) (and (listp in) (listp out) (funcall test in out))))
         (same-length-p (in out) (= (length in) (length out)))
         (long-input-p (in out) (declare (ignore out)) (>= (length in) 2)))
    (list
     (list :DESC/HO-SEQ->SEQ :type 1 2 1 :necessary '(:higher-order :seq-in :seq-out)
           :frame '(:seq-in :seq-out) :mismatch :violated)
     (list :DESC/HO-SEQ->SCALAR :type 1 2 1 :necessary '(:higher-order :seq-in :scalar-out)
           :frame '(:seq-in :scalar-out) :mismatch :violated)
     (list :DESC/SEQ->SEQ :type 1 2 1 :necessary '(:first-order :seq-in :seq-out)
           :frame '(:seq-in :seq-out) :mismatch :violated)
     (list :DESC/SEQ->SCALAR :type 1 2 1 :necessary '(:first-order :seq-in :scalar-out)
           :frame '(:seq-in :scalar-out) :mismatch :violated)
     (list :DESC/SCALAR->SCALAR :type 1 1 1 :necessary '(:scalar-in)
           :frame '(:scalar-in :scalar-out))
     (list :DESC/LEN-EQ :shape-delta 1 6 2 :structural '(:preserving)
           :frame '(:seq-out) :over :all :holds (lists #'same-length-p)
           :witness (lambda (in out) (declare (ignore out)) in))
     (list :DESC/LEN-DEC-1 :shape-delta 1 6 2 :structural '(:decrementing)
           :frame '(:seq-out) :over :all :witness #'long-input-p
           :holds (lists (lambda (in out) (= (length out) (max 0 (1- (length in)))))))
     (list :DESC/LEN-LE :shape-delta 1 5 2 :structural '(:contracting)
           :frame '(:seq-out) :over :all
           :holds (lists (lambda (in out) (<= (length out) (length in))))
           :witness (lambda (in out) (< (length out) (length in))))
     (list :DESC/OUTER-SHAPE-2D :shape-delta 1 4 2 :empirical '(:body :seq-2d-out)
           :frame '(:seq-2d-out) :over :non-empty)
     (list :DESC/EMPTY->EMPTY :boundary 1 4 2 :structural '(:empty->empty)
           :over :empty :holds (lambda (in out) (declare (ignore in)) (null out)))
     (list :DESC/EMPTY->ZERO :boundary 1 4 2 :structural '(:empty->zero)
           :over :empty :holds (lambda (in out) (declare (ignore in)) (eql 0 out)))
     (list :DESC/SUBSET-ELEMENTS :sampled-content 2 6 8 :empirical '(:subset)
           :frame '(:seq-out) :over :non-empty
           :holds (lists (lambda (in out) (subsetp out in :test #'equal))))
     (list :DESC/POINTWISE-MAP :sampled-content 2 5 6 :empirical '(:higher-order :preserving)
           :frame '(:seq-out) :over :non-empty :holds (lists #'same-length-p))
     (list :DESC/SCALAR-REDUCTION :sampled-content 2 5 6 :empirical
           '(:body :higher-order :seq-in :scalar-out)
           :frame '(:seq-in :scalar-out) :over :non-empty)
     (list :DESC/CONSTANT-STEP-DELTA :sampled-content 2 4 8 :empirical '(:sampled-constant-step)
           :frame '(:int-seq-out) :over :non-empty :failure :neutral :witness #'long-input-p
           :holds (lists (lambda (in out)
                           (and (same-length-p in out)
                                (or (< (length in) 2)
                                    (= (- (first out) (first in)) (- (second out) (second in))))))))
     (list :DESC/SUBSET-ELEMENTS :sampled-content 2 4 8 :empirical '(:sampled-subset))
     (list :DESC/ABSTRACTS-FAMILY :algebraic 3 4 4 :empirical '(:abstracts) :over :all)
     (list :DESC/ALGEBRAIC-LAW :algebraic 3 4 8 :empirical '(:laws) :over :all)))
  "One row per behavioural descriptor: id, facet, tier, weight in bits, work cost, status, and
the entry facts that prove it (see `entry-descriptor-facts`), then how it is checked on a
frame (see `evaluate-descriptor-clause-on-frame`). A :structural status is :necessary for a
function whose only input besides code is the sequence and :empirical otherwise. A second
row with an id seen before is weaker evidence for the same descriptor and shares its check.")

(defun entry-descriptor-facts (entry library ledger)
  "The facts about ENTRY that rows of `*descriptor-table*` are proved by: its type signature,
the structure of a function or decoder-template body, one sampled run of a first-order
integer list function (charged to LEDGER), and its edges in LIBRARY."
  (let* ((kind (knowledge-entry-kind entry))
         (inputs (knowledge-entry-inputs entry))
         (target (knowledge-entry-target entry))
         (body (and (member kind '(:function :decoder-template)) (knowledge-entry-expression entry)))
         (ho-p (find-if #'code-type-p inputs :key #'cdr)))
    (destructuring-bind (&key seq-spec pure-p shape base subset-p)
        (function-shape-facts (knowledge-entry-id entry) inputs target body)
      (append
       (signature-facts seq-spec target)
       (list (if ho-p :higher-order :first-order))
       (when body
         (list :body shape
               (and pure-p :pure)
               (and subset-p :subset)
               (cond ((null base) nil)
                     ((and (seq-type-p target) (null (ast-value base))) :empty->empty)
                     ((and (eq target :int) (eql 0 (ast-value base))) :empty->zero))
               (when (and (eq kind :function) (not ho-p) (not subset-p) (= 1 (length inputs))
                          (equal (cdr seq-spec) '(:seq :int)) (equal target '(:seq :int)))
                 (let* ((run (evaluate body inputs (list '(1 2 3)) :budget 200 :ledger ledger))
                        (out (evaluation-value run)))
                   (when (and (eq :value (evaluation-status run)) (listp out))
                     (cond ((and (= (length out) 3) (every #'integerp out)
                                 (= (- (first out) 1) (- (second out) 2) (- (third out) 3)))
                            :sampled-constant-step)
                           ((and (<= (length out) 3) (subsetp out '(1 2 3) :test #'equal))
                            :sampled-subset)))))))
       (when library
         (list (and (knowledge-edges-from entry :abstracts library) :abstracts)
               (and (or (knowledge-edges-from entry :functor-laws library)
                        (knowledge-edges-from entry :laws library))
                    :laws)))))))

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
           ;; The id of the first clause of the first of FACETS that has any.
           (let ((clause (some (lambda (facet) (find facet clauses :key #'descriptor-clause-facet))
                               facets)))
             (if clause (strip-descriptor-prefix (descriptor-clause-id clause)) "ANY"))))
    (keyword-id "~A/~A/~A/~A/~A" (or (knowledge-entry-kind entry) :entry)
                (token :type) (token :shape-delta) (token :boundary)
                (token :sampled-content :algebraic))))

(defun compute-entry-descriptor-profile (entry &optional (library *knowledge-library*) ledger)
  "Compute the `descriptor-clause` profile of ENTRY, one clause per row of `*descriptor-table*`
that the entry's facts prove, install it with the entry's secondary `compositional-name`,
and index it in LIBRARY."
  (when (knowledge-entry-p entry)
    (let* ((facts (entry-descriptor-facts entry library ledger))
           (clauses (loop for (id facet tier weight cost status proof) in *descriptor-table*
                          when (subsetp proof facts)
                            collect (make-descriptor-clause
                                     :id id :facet facet :tier tier
                                     :status (if (or (eq status :necessary)
                                                     (and (eq status :structural) (member :pure facts)))
                                                 :necessary
                                                 :empirical)
                                     :weight-bits weight :work-cost cost))))
      (setf (knowledge-entry-descriptor-profile entry) clauses
            (knowledge-entry-compositional-name entry) (derive-compositional-name entry clauses))
      (when library
        (index-knowledge-entry-compositional-address entry library))
      clauses)))

(define-knowledge-kind :descriptor
  (:priority 15)
  (:validate (entry library)
    (declare (ignore library))
    (assert (eq :bool (knowledge-entry-target entry)))
    (assert-entry-expression-type entry))
  (:install (entry library ledger)
    (declare (ignore ledger))
    (dolist (edge (knowledge-edges-from entry :describes library))
      (dolist (target (rest edge))
        (when (symbolp target)
          (setf (gethash (canonical-op-name target) (knowledge-library-descriptors library))
                (knowledge-entry-expression entry)))))))

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

(defun library-function-descriptor-compatible-p (frame seq-input-id fn-name ledger)
  "Only current necessary-condition evidence authorizes descriptor pruning.
Uncertified descriptors are hints; no function shape implies a hard rejection."
  (let* ((descriptors
           (remove-if-not
            (lambda (entry)
              (and (knowledge-evidence-current-p entry :necessary)
                   (some (lambda (edge) (member fn-name (rest edge)))
                         (knowledge-edges-from entry :describes *knowledge-library*))))
            (knowledge-entries-of-kind :descriptor *knowledge-library*)))
         (pairs (and descriptors (frame-concrete-pairs frame seq-input-id))))
    (every
     (lambda (descriptor)
       (let* ((guard (knowledge-entry-guard descriptor))
              (expression (knowledge-entry-expression descriptor))
              (predicate (if (equal guard (lit :bool t))
                             expression
                             (term `(if ,guard ,expression t)))))
         (every (lambda (pair)
                  (let ((run (evaluate predicate (knowledge-entry-inputs descriptor)
                                       (list (car pair) (cdr pair)) :ledger ledger)))
                    (or (not (eq :value (evaluation-status run))) (evaluation-value run))))
                pairs)))
     descriptors)))

(defun evaluate-descriptor-clause-on-frame (clause frame-facts pairs)
  "Check CLAUSE on a frame with type facts FRAME-FACTS and concrete (input . output) PAIRS,
as its row of `*descriptor-table*` says. FRAME-FACTS must include the row's :frame facts,
or the result is its :mismatch. A row without :over is then satisfied by the types alone.
Otherwise every pair that :over selects must pass :holds, or the result is the row's
:failure, and one of them must pass :witness. Returns :satisfied, :violated or :neutral."
  (let ((row (assoc (descriptor-clause-id clause) *descriptor-table*)))
    (if (null row)
        :neutral
        (destructuring-bind (&key frame (mismatch :neutral) over (holds (constantly t))
                                  (failure :violated) (witness (constantly t)))
            (nthcdr 7 row)
          (let ((selected (ecase over
                            ((nil :all) pairs)
                            (:non-empty (remove-if #'null pairs :key #'car))
                            (:empty (remove-if-not #'null pairs :key #'car)))))
            (cond ((not (subsetp frame frame-facts)) mismatch)
                  ((null over) :satisfied)
                  ((null selected) :neutral)
                  ((notevery (lambda (pair) (funcall holds (car pair) (cdr pair))) selected) failure)
                  ((some (lambda (pair) (funcall witness (car pair) (cdr pair))) selected) :satisfied)
                  (t :neutral)))))))

(defun score-entry-by-descriptors (entry-or-id frame seq-input-id
                                   &key (library *knowledge-library*) ledger extra-fo-specs)
  "Score the `descriptor-clause` profile of ENTRY-OR-ID on FRAME.
Returns `(VALUES compatible-p policy-delta-bits matched-clause-ids)`; lower delta is better.
A satisfied clause subtracts its weight and a violated one adds half of it, whatever its
status: a clause is a hint. Only the certified `:descriptor` entries that
`library-function-descriptor-compatible-p` consults can reject a function, giving NIL."
  (let* ((fn-name (if (knowledge-entry-p entry-or-id)
                      (knowledge-entry-id entry-or-id)
                      (canonical-op-name entry-or-id)))
         (entry (if (knowledge-entry-p entry-or-id)
                    entry-or-id
                    (and library (find-knowledge-entry fn-name library)))))
    (if (and fn-name (null extra-fo-specs)
             (or (null entry) (eq :function (knowledge-entry-kind entry)))
             (not (library-function-descriptor-compatible-p frame seq-input-id fn-name ledger)))
        (values nil most-positive-fixnum nil)
        (let* ((clauses (and entry
                             (or (knowledge-entry-descriptor-profile entry)
                                 (compute-entry-descriptor-profile entry library ledger))))
               (schema (frame-schema frame))
               (seq-type (cdr (assoc seq-input-id (schema-inputs schema))))
               (frame-facts (signature-facts (seq-type-p seq-type) (schema-target schema)))
               (pairs (frame-concrete-pairs frame seq-input-id))
               (delta 0)
               (matched nil))
          (dolist (clause clauses)
            (charge ledger :orientation (descriptor-clause-work-cost clause))
            (case (evaluate-descriptor-clause-on-frame clause frame-facts pairs)
              (:satisfied
               (decf delta (descriptor-clause-weight-bits clause))
               (push (descriptor-clause-id clause) matched))
              (:violated
               (incf delta (ceiling (descriptor-clause-weight-bits clause) 2)))))
          (values t delta (nreverse matched))))))
