;;;; bootstrap/recursion-schemas.lisp
;;;; Recursion schemas the battery curriculum is given, not ones the kernel finds.
;;;;
;;;; The kernel's own induction over a sequence is the conditional split on `(= xs ())` whose
;;;; child sees the head and the recursive call on the tail (`lift-inductive-sequence-context`),
;;;; and its lockstep form over several sequences. The decoders below go further: a second
;;;; base case, a state threaded through the recursive call, and an integer counted down or up
;;;; beside the sequence. Each is the shape of one battery function (`:map-adjacent` and
;;;; `:last-or`, `:foldl`, `:scan`, `:shift-seq`, `:best-shift`), written by hand. They are
;;;; curriculum, supplied to a synthesis job through `:expanders`, and no kernel test needs
;;;; them. Retiring one means giving the kernel a general way to propose its recursion (a
;;;; self call whose arguments are synthesized) or storing it as a decoder template.

(in-package #:lisploop)

(defun candidate-inductive-bases (inputs target h-model language)
  "Ordered candidate base-case ASTs over INPUTS for TARGET."
  (let ((cands nil))
    (flet ((add (e) (when (and e (equal target (ignore-errors (expression-type e inputs))))
                      (pushnew e cands :test #'equal))))
      (when h-model
        (add (heuristic-program h-model))
        (dolist (alt (heuristic-alternatives h-model))
          (add (heuristic-program alt))))
      (dolist (s inputs)
        (when (equal (cdr s) target)
          (add (var (car s) (cdr s)))))
      (add (lit target (default-value-for-type target)))
      (when (and (tuple-type-p target)
                 (<= 1 (length (rest target)) 3)
                 (language-operator-p language :tuple))
        (let ((slot-atoms
                (mapcar (lambda (stype)
                          (remove-duplicates
                           (cons (lit stype (default-value-for-type stype))
                                 (loop for (id . type) in inputs
                                       when (equal type stype) collect (var id type)))
                           :test #'equal))
                        (rest target))))
          (dolist (combo (cartesian-product-lists slot-atoms))
            (add (apply #'app (op :tuple target) combo))))))
    (nreverse cands)))

(defun recursion-schema-decompositions (frame language c-lang h-model child-id c-bound
                                            eff-self solver ledger debug-p)
  "Propose lookahead (`(= (tail xs) ())`), state-threading (`foldl`/`scan`), and integer
counter/countdown (`(+ k 1)` / `(< 0 k) -> (- k 1)`) recursive skeletons when EFF-SELF is active."
  (when eff-self
    (let* ((schema (frame-schema frame))
           (inputs (schema-inputs schema))
           (target (schema-target schema))
           (rows (frame-rows frame))
           (seq-specs (remove-if-not #'seq-type-p inputs :key #'cdr))
           (base-cands (candidate-inductive-bases inputs target h-model language))
           (proposals nil))
      (dolist (seq-spec seq-specs (nreverse proposals))
        (let* ((seq-id (car seq-spec))
               (seq-type (cdr seq-spec))
               (seq-pos (position seq-id inputs :key #'car :test #'eql))
               (xs (var seq-id seq-type))
               (has-seq-eq-p (some (lambda (o)
                                     (and (operator-p o) (eq := (operator-name o))
                                          (equal seq-type (operator-operand-type o))))
                                   (language-operators language)))
               (empty-rows (remove-if-not (lambda (r) (empty-sequence-row-p r seq-pos)) rows))
               (non-empty-rows (remove-if-not
                                (lambda (r)
                                  (and (constrained-row-p r)
                                       (consp (nth seq-pos (row-known r)))))
                                rows))
               (base0 (and has-seq-eq-p empty-rows non-empty-rows
                           (find-if (lambda (e)
                                      (and (every (lambda (r) (row-satisfied-p r e inputs :ledger ledger))
                                                  empty-rows)
                                           (notevery (lambda (r) (row-satisfied-p r e inputs :ledger ledger))
                                                     non-empty-rows)))
                                    base-cands))))
          (when base0
            ;; 1. Two-step lookahead induction: `(if (= xs ()) base0 (if (= (tail xs) ()) base1 Z_child))`
            (when (and (= 1 (length seq-specs))
                       (language-operator-p language :at)
                       (language-operator-p language :tail))
              (let* ((singleton-rows (remove-if-not
                                      (lambda (r) (= 1 (length (nth seq-pos (row-known r)))))
                                      non-empty-rows))
                     (long-rows (remove-if-not
                                 (lambda (r) (>= (length (nth seq-pos (row-known r))) 2))
                                 non-empty-rows))
                     (head0 (term `(at ,xs 0)))
                     (sing-cands (remove-duplicates
                                  (append (when (equal (second seq-type) target) (list head0))
                                          base-cands)
                                  :test #'equal))
                     (base1 (and singleton-rows long-rows
                                 (find-if (lambda (e)
                                            (and (every (lambda (r)
                                                          (row-satisfied-p r e inputs :ledger ledger))
                                                        singleton-rows)
                                                 (notevery (lambda (r)
                                                             (row-satisfied-p r e inputs :ledger ledger))
                                                           long-rows)))
                                          sing-cands))))
                (when (and base1
                           (or (not (equal base1 base0))
                               (and (notany (lambda (s) (equal (second seq-type) (cdr s))) inputs)
                                    (some (lambda (o)
                                            (and (operator-p o)
                                                 (eq :code-eval (operator-name o))
                                                 (let ((args (rest (second (operator-type o)))))
                                                   (and (= 2 (length args))
                                                        (every (lambda (at) (equal at (second seq-type)))
                                                               args)))))
                                          (language-operators language)))))
                  (let* ((head1 (term `(at (tail ,xs) 0)))
                         (rec (typed-recursive-call eff-self inputs
                                                    (list (cons seq-id (term `(tail ,xs))))))
                         (other-vars (loop for (id . type) in inputs
                                           unless (eql id seq-id) collect (var id type)))
                         (lifted-bindings
                           (loop for e in (append (list head0 head1) other-vars (when rec (list rec)))
                                 for cid from 0 collect (cons cid e)))
                         (l-lang (inductive-child-language
                                  language (language-operators c-lang)
                                  (remove (lit seq-type '()) (language-constants c-lang) :test #'equal)
                                  lifted-bindings inputs eff-self)))
                    (push (make-decomposition
                           :name (list :lookahead-inductive seq-id base0 base1)
                           :decoder (term `(if (= ,xs ()) ,base0
                                               (if (= (tail ,xs) ()) ,base1 ,(var child-id target))))
                           :child-id child-id :child-type target
                           :bindings lifted-bindings :language l-lang
                           :bound (max c-bound (header-bound (language-inputs l-lang) target 48))
                           :policy-score 4 :solver solver
                           :provenance (when debug-p
                                         (list :origin :lookahead-inductive
                                               :sequence-id seq-id :base0 base0 :base1 base1)))
                          proposals)))))
            ;; 2. State-threading & counter/countdown inductions over non-code parameters
            (when (language-operator-p language :tail)
              (dolist (s-spec inputs)
                (let ((s-id (car s-spec))
                      (s-type (cdr s-spec)))
                  (when (and (not (eql s-id seq-id))
                             (not (seq-type-p s-type))
                             (not (code-type-p s-type)))
                    (let* ((s-var (var s-id s-type))
                           (step-var (var child-id s-type))
                           (rec-state (typed-recursive-call
                                       eff-self inputs
                                       (list (cons seq-id (term `(tail ,xs)))
                                             (cons s-id step-var))))
                           (step-exprs (append (when (language-operator-p language :at)
                                                 (list (term `(at ,xs 0))))
                                               (loop for (id . type) in inputs
                                                     unless (eql id seq-id) collect (var id type))))
                           (step-bindings (loop for e in step-exprs for cid from 0 collect (cons cid e)))
                           (step-lang (inductive-child-language
                                       language (language-operators c-lang)
                                       (remove (lit seq-type '()) (language-constants c-lang) :test #'equal)
                                       step-bindings inputs eff-self)))
                      ;; 2a. Tail-accumulator (`foldl`): `(if (= xs ()) s (<self> (tail xs) Z_next ...))`
                      (when (and (= 1 (length seq-specs))
                                 rec-state
                                 (equal s-type target)
                                 (equal base0 s-var))
                        (push (make-decomposition
                               :name (list :state-fold-inductive seq-id s-id)
                               :decoder (term `(if (= ,xs ()) ,base0 ,rec-state))
                               :child-id child-id :child-type s-type
                               :bindings step-bindings :language step-lang
                               :bound (max c-bound (header-bound (language-inputs step-lang) s-type 44))
                               :policy-score 4 :solver solver
                               :provenance (when debug-p
                                             (list :origin :state-fold-inductive
                                                   :sequence-id seq-id :state-id s-id)))
                              proposals))
                      ;; 2b. Emit-and-thread (`scan`): `(if (= xs ()) () (cons Z_next (<self> (tail xs) Z_next ...)))`
                      (when (and (= 1 (length seq-specs))
                                 rec-state
                                 (seq-type-p target)
                                 (equal s-type (second target))
                                 (some (lambda (sp) (code-type-p (cdr sp))) inputs)
                                 (language-operator-p language :cons))
                        (push (make-decomposition
                               :name (list :state-scan-inductive seq-id s-id)
                               :decoder (term `(if (= ,xs ()) ,(lit target nil) (cons ,step-var ,rec-state)))
                               :child-id child-id :child-type s-type
                               :bindings step-bindings :language step-lang
                               :bound (max c-bound (header-bound (language-inputs step-lang) s-type 44))
                               :policy-score 3 :solver solver
                               :provenance (when debug-p
                                             (list :origin :state-scan-inductive
                                                   :sequence-id seq-id :state-id s-id)))
                              proposals))
                      ;; 2c. Guarded integer countdown: `(if (= xs ()) () (if (< 0 k) Z_child base_le0))`
                      (when (and (eq s-type :int)
                                 (language-operator-p language :<)
                                 (language-operator-p language :-))
                        (let* ((s-pos (position s-id inputs :key #'car :test #'eql))
                               (le0-rows (remove-if-not
                                          (lambda (r)
                                            (let ((kv (nth s-pos (row-known r))))
                                              (and (integerp kv) (<= kv 0))))
                                          non-empty-rows))
                               (gt0-rows (remove-if-not
                                          (lambda (r)
                                            (let ((kv (nth s-pos (row-known r))))
                                              (and (integerp kv) (plusp kv))))
                                          non-empty-rows))
                               (base-le0 (and le0-rows gt0-rows
                                              (find-if (lambda (e)
                                                         (and (every (lambda (r)
                                                                       (row-satisfied-p r e inputs :ledger ledger))
                                                                     le0-rows)
                                                              (notevery (lambda (r)
                                                                          (row-satisfied-p r e inputs :ledger ledger))
                                                                        gt0-rows)))
                                                       base-cands)))
                               (eff-base0 (if (and (seq-type-p target)
                                                   (every (lambda (r)
                                                            (row-satisfied-p r (lit target nil) inputs :ledger ledger))
                                                          empty-rows))
                                              (lit target nil)
                                              base0))
                               (rec-dec (and base-le0
                                             (typed-recursive-call
                                              eff-self inputs
                                              (list (cons seq-id (term `(tail ,xs)))
                                                    (cons s-id (term `(- ,s-var 1))))))))
                          (when rec-dec
                            (let* ((cd-exprs (append (when (language-operator-p language :at)
                                                       (list (term `(at ,xs 0))))
                                                     (loop for (id . type) in inputs
                                                           unless (or (eql id seq-id) (eql id s-id))
                                                             collect (var id type))
                                                     (list rec-dec)))
                                   (cd-bindings (loop for e in cd-exprs for cid from 0 collect (cons cid e)))
                                   (cd-ops (remove-if (lambda (o)
                                                        (and (operator-p o)
                                                             (member (operator-name o) '(:< :-))))
                                                      (language-operators c-lang)))
                                   (cd-lang (inductive-child-language
                                             language cd-ops (language-constants c-lang)
                                             cd-bindings inputs eff-self)))
                              (push (make-decomposition
                                     :name (list :countdown-inductive seq-id s-id eff-base0 base-le0)
                                     :decoder (term `(if (= ,xs ()) ,eff-base0
                                                         (if (< 0 ,s-var) ,(var child-id target) ,base-le0)))
                                     :child-id child-id :child-type target
                                     :bindings cd-bindings :language cd-lang
                                     :bound (max c-bound (header-bound (language-inputs cd-lang) target 64))
                                     :policy-score -4 :solver solver
                                     :provenance (when debug-p
                                                   (list :origin :countdown-inductive
                                                         :sequence-id seq-id :counter-id s-id)))
                                    proposals)))))
                      ;; 2d. Incrementing index recursion: `(if (= xs ()) base0 Z_child)` with `(<self> (tail xs) ... (+ s 1))`
                      (when (and (eq s-type :int)
                                 (language-operator-p language :+))
                        (let ((rec-inc (typed-recursive-call
                                        eff-self inputs
                                        (list (cons seq-id (term `(tail ,xs)))
                                              (cons s-id (term `(+ ,s-var 1)))))))
                          (when rec-inc
                            (let* ((seq-helper-calls
                                     (loop for o in (language-operators language)
                                           when (and (operator-p o)
                                                     (defined-function-p (operator-name o))
                                                     (not (eq eff-self (operator-name o)))
                                                     (every #'seq-type-p (second (operator-type o))))
                                             append (let ((arg-opts
                                                            (mapcar (lambda (at)
                                                                      (loop for (id . it) in inputs
                                                                            when (equal it at)
                                                                              collect (var id it)))
                                                                    (second (operator-type o)))))
                                                      (when (every #'consp arg-opts)
                                                        (loop for args in (cartesian-product-lists arg-opts)
                                                              when (loop for (a b) on args while b
                                                                         always (< (ast-id a) (ast-id b)))
                                                                collect (apply #'app o args))))))
                                   (rec-projs
                                     (when (and (tuple-type-p target)
                                                (<= 1 (length (rest target)) 6))
                                       (loop for stype in (rest target)
                                             for idx from 0
                                             collect (app (op :at (tuple-type target stype))
                                                          rec-inc (lit :int idx)))))
                                   (inc-exprs (append (when (and (null seq-helper-calls)
                                                                 (language-operator-p language :at))
                                                        (list (term `(at ,xs 0))))
                                                      (loop for (id . type) in inputs
                                                            unless (or (eql id seq-id)
                                                                       (and seq-helper-calls (seq-type-p type)))
                                                              collect (var id type))
                                                      seq-helper-calls
                                                      (list rec-inc)
                                                      rec-projs))
                                   (inc-bindings (loop for e in inc-exprs for cid from 0 collect (cons cid e)))
                                   (inc-ops (remove-if
                                             (lambda (o)
                                               (and (operator-p o)
                                                    (or (eq (operator-name o) :tail)
                                                        (eq (operator-name o) eff-self)
                                                        (and seq-helper-calls
                                                             (defined-function-p (operator-name o))
                                                             (every #'seq-type-p (second (operator-type o))))
                                                        (eq (operator-name o) :at)
                                                        (and (eq (operator-name o) :=)
                                                             (equal (operator-operand-type o) seq-type)))))
                                             (language-operators c-lang)))
                                   (inc-lang (derive-language
                                              language
                                              :inputs (loop for (id . e) in inc-bindings
                                                            collect (cons id (expression-type e inputs)))
                                              :operators inc-ops
                                              :constants (remove (lit seq-type '())
                                                                 (language-constants c-lang)
                                                                 :test #'equal))))
                              (push (make-decomposition
                                     :name (list :counter-inductive seq-id s-id base0)
                                     :decoder (term `(if (= ,xs ()) ,base0 ,(var child-id target)))
                                     :child-id child-id :child-type target
                                     :bindings inc-bindings :language inc-lang
                                     :bound (max c-bound (header-bound (language-inputs inc-lang) target 48))
                                     :policy-score -2 :solver solver
                                     :provenance (when debug-p
                                                   (list :origin :counter-inductive
                                                         :sequence-id seq-id :counter-id s-id)))
                                    proposals))))))))))))))))

(defun recursion-schema-expander ()
  "An `:expand` function proposing `recursion-schema-decompositions` for a recursive job, at
each node whose frame has an empty-sequence row and whose Stage A model is not already a
solution: where the kernel proposes its own inductive split."
  (lambda (job node frame language h-model ledger)
    (declare (ignore node))
    (let ((self (synthesis-job-self-name job))
          (operators (remove-if-not #'operator-p (language-operators language))))
      (when (and self h-model
                 (not (and (heuristic-exact-p h-model)
                           (null (heuristic-unresolved-keys h-model))
                           (expression-calls-operator-p (heuristic-program h-model) self)))
                 (frame-has-empty-sequence-row-p frame)
                 (or (language-operator-p language :at)
                     (language-operator-p language :tail)
                     (notany (lambda (o)
                               (or (member (operator-name o) '(:= :<))
                                   (eq :bool (third (operator-type o)))))
                             operators)))
        (recursion-schema-decompositions
         frame language language h-model
         (next-child-id (schema-inputs (frame-schema frame)))
         (synthesis-node-bound (synthesis-job-root job))
         self (synthesis-job-library job) ledger (synthesis-job-debug-p job))))))
