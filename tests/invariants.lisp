(in-package #:lisploop)

;;; ===========================================================================
;;; Cross-Module Algebraic, Semantic, Metamorphic & Warm-Library Invariants
;;; ===========================================================================

(deftest invariant-partial-evaluation-equivalent-and-necessary-soundness
  "Verify that `fold-constants` under `:contract :equivalent` preserves exact `outcome-signature`
(including `:error` definedness) across types, control flow, homoiconic code evaluation, recursive
calls, and arbitrary budgets, and that `:contract :necessary` with `:max-fibers` never introduces
false negatives on valid assignments."
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:map))
    (let* ((seq-type (sequence-type :int))
           (gf5 (gf 5))
           (unary-code (code-type '((0 . :int)) :int))
           (binary-code (code-type '((0 . :int) (1 . :int)) :int))
           (xs (var 0 seq-type)))
      (define-function :sum-rec (list (cons 0 seq-type)) :int
        (lambda (self)
          (app (op :if :int)
               (app (op := seq-type) xs (lit seq-type '()))
               (lit :int 0)
               (app (op :+ :int)
                    (app (op :at seq-type) xs (lit :int 0))
                    (app self (app (op :tail :int) xs))))))
      (define-function :const-zero (list (cons 0 seq-type) (cons 1 :int)) :int
        (lambda (self)
          (declare (ignore self))
          (app (op :if :int)
               (app (op := seq-type) xs (lit seq-type '()))
               (lit :int 0)
               (var 1 :int))))

      ;; 1. Exact `:equivalent` preservation across types, partiality, and budgets
      (let* ((int-seq-scope (list (cons 0 :int) (cons 1 seq-type)))
             (x0 (var 0 :int))
             (s1 (var 1 seq-type))
             (int-seq-valuations '((-2 ()) (0 ()) (0 (4 5)) (2 (7)) (3 (8 9 10))))
             (int-seq-exprs
               (list
                ;; Structural sequence projections & equalities with partial subterms
                (app (op :at seq-type)
                     (app (op :cons :int) x0 (app (op :cons :int) (app (op :/ :int) (lit :int 6) x0) s1))
                     (lit :int 0))
                (app (op :tail :int)
                     (app (op :cons :int) (app (op :/ :int) (lit :int 6) x0) s1))
                (app (op := seq-type)
                     (app (op :cons :int) (app (op :/ :int) (lit :int 6) x0) s1)
                     (lit seq-type '()))
                ;; Guarded conditional with branch-local equality propagation & partial dead branch
                (app (op :if :int)
                     (app (op := :int) x0 (lit :int 0))
                     (app (op :+ :int) x0 (app (op :length :int) s1))
                     (app (op :/ :int) (lit :int 12) x0))
                ;; Strict call-by-value definedness when unfolding a function whose body ignores arg 1
                (app (op :const-zero) (lit seq-type '()) (app (op :/ :int) (lit :int 10) x0))
                ;; Recursive unfolding along closed and open `:cons` spines
                (app (op :sum-rec) (app (op :cons :int) x0 (lit seq-type '(3 4))))
                (app (op :sum-rec) (app (op :cons :int) x0 s1))
                ;; Homoiconic `:code-subst` + `:code-eval`
                (let ((subst-op (op :code-subst
                                    (tuple-type binary-code (tuple-type unary-code :int) unary-code))))
                  (app (op :code-eval unary-code)
                       (app subst-op
                            (lit binary-code (app (op :+ :int) (var 0 :int) (var 1 :int)))
                            (app (op :tuple (tuple-type unary-code :int))
                                 (lit unary-code (var 0 :int))
                                 (app (op :length :int) s1)))
                       x0))))
             (gf5-scope (list (cons 0 gf5) (cons 1 gf5)))
             (gf5-valuations '((0 0) (0 3) (2 0) (4 2)))
             (gf5-exprs
               (list
                (app (op :if gf5)
                     (app (op := gf5) (var 1 gf5) (lit gf5 0))
                     (var 0 gf5)
                     (app (op :/ gf5) (var 0 gf5) (var 1 gf5)))
                (bool-and (bool-not (app (op := gf5) (var 1 gf5) (lit gf5 0)))
                          (app (op := gf5)
                               (app (op :* gf5) (var 0 gf5) (lit gf5 3))
                               (lit gf5 1))))))
        (dolist (budget '(0 1 2 8 10000))
          (dolist (expr int-seq-exprs)
            (let ((folded (fold-constants expr :contract :equivalent :budget budget)))
              (dolist (vals int-seq-valuations)
                (check (equal (outcome-signature expr int-seq-scope vals)
                              (outcome-signature folded int-seq-scope vals))))))
          (dolist (expr gf5-exprs)
            (let ((folded (fold-constants expr :contract :equivalent :budget budget)))
              (dolist (vals gf5-valuations)
                (check (equal (outcome-signature expr gf5-scope vals)
                              (outcome-signature folded gf5-scope vals))))))))

      ;; 2. `:necessary` contract with `:max-fibers`: weakening may drop tail conjuncts past `max-fibers`,
      ;;    but must NEVER reject an assignment that satisfies the original Boolean requirement.
      (let* ((code-scope (list (cons 0 unary-code)))
             (z (var 0 unary-code))
             (map-req (app (op := seq-type)
                           (app (op :map) (lit seq-type '(1 2 3 4 5)) z)
                           (lit seq-type '(2 3 4 5 6))))
             (good-code (lit unary-code (app (op :+ :int) (var 0 :int) (lit :int 1))))
             (prefix-only-code (lit unary-code
                                    (app (op :if :int)
                                         (app (op :< :int) (var 0 :int) (lit :int 3))
                                         (app (op :+ :int) (var 0 :int) (lit :int 1))
                                         (lit :int 99))))
             (bad-first-code (lit unary-code (app (op :+ :int) (var 0 :int) (lit :int 9)))))
        (dolist (k '(1 2 4))
          (dolist (budget '(2 12 10000))
            (let ((nec (fold-constants map-req :contract :necessary :max-fibers k :budget budget)))
              (dolist (candidate (list good-code prefix-only-code bad-first-code))
                (let ((orig-out (evaluate map-req code-scope (list candidate)))
                      (nec-out (evaluate nec code-scope (list candidate))))
                  (when (and (eq :value (evaluation-status orig-out))
                             (eq t (evaluation-value orig-out)))
                    (check (eq :value (evaluation-status nec-out)))
                    (check (eq t (evaluation-value nec-out)))))))))))))

(deftest invariant-pullback-and-lift-galois-soundness
  "Verify the Galois soundness invariant of `pullback-frame` / `compose-model` and `lift-frame` /
`compose-lifted-model` across scalar, guarded, `:map`, `:filter`, and `:foldr` decoders:
every child expression whose composed parent model satisfies the parent frame is accepted by the
pulled-back / lifted child frame (zero false pruning), and exact equivalence holds when uncoupled."
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:map :foldr :filter))
    (flet ((satisfies-frame-p (expr frame)
             (let ((inputs (schema-inputs (frame-schema frame))))
               (every (lambda (row)
                        (or (equal (lit :bool t) (row-requirement row))
                            (let ((run (evaluate expr inputs (row-known row))))
                              (and (eq :value (evaluation-status run))
                                   (accepts (row-requirement row) (evaluation-value run))))))
                      (frame-rows frame)))))
      ;; 1. Finite-field GF(5) scalar decoder + certified propagation: exact two-way Galois equivalence
      (let* ((gf5 (gf 5))
             (p-inputs (list (cons 0 gf5) (cons 1 gf5)))
             (parent (simple-frame gf5 p-inputs
                                   '(((1 2) 0)
                                     ((3 1) 0)
                                     ((2 4) 0))))
             ;; True model: (+ X0 (* 2 Z)) where Z = X1 (since 1+2*2=5=0, 3+2*1=5=0, 2+2*4=10=0 mod 5)
             (decoder (app (op :+ gf5) (var 0 gf5) (app (op :* gf5) (lit gf5 2) (var 9 gf5))))
             (bindings (list (cons 0 (var 1 gf5))))
             (pulled (nth-value 1 (frame-conflict-p (pullback-frame parent decoder 9 gf5 bindings))))
             (prop-lib (kernel-propagator-library gf5))
             (narrowed (propagation-frame (propagate-requirements pulled prop-lib (make-ledger))))
             (c-inputs (list (cons 0 gf5)))
             (c-candidates (reference-typed-trees
                            (list (var 0 gf5) (lit gf5 0) (lit gf5 1) (lit gf5 2))
                            (list (op :+ gf5) (op :* gf5))
                            1 c-inputs)))
        (dolist (child-expr c-candidates)
          (let* ((composed (compose-model decoder 9 child-expr bindings))
                 (parent-ok (satisfies-frame-p composed parent))
                 (pulled-ok (satisfies-frame-p child-expr pulled))
                 (narrowed-ok (satisfies-frame-p child-expr narrowed)))
            (check (eq parent-ok pulled-ok))
            (check (eq parent-ok narrowed-ok)))))

      ;; 2. Guarded conditional `:int` decoder: `(if (= X0 '0) '0 (+ Z X1))`
      (let* ((p-inputs '((0 . :int) (1 . :int)))
             (parent (simple-frame :int p-inputs
                                   '(((0 99) 0)
                                     ((1 10) 13)
                                     ((2 20) 26))))
             (decoder (app (op :if :int)
                           (app (op := :int) (var 0 :int) (lit :int 0))
                           (lit :int 0)
                           (app (op :+ :int) (var 9 :int) (var 1 :int))))
             (bindings (list (cons 0 (var 0 :int))))
             (pulled (nth-value 1 (frame-conflict-p (pullback-frame parent decoder 9 :int bindings))))
             (c-candidates (list (app (op :* :int) (var 0 :int) (lit :int 3))
                                 (app (op :+ :int) (var 0 :int) (lit :int 2))
                                 (app (op :/ :int) (lit :int 3) (var 0 :int))
                                 (lit :int 3))))
        (dolist (child-expr c-candidates)
          (let* ((composed (compose-model decoder 9 child-expr bindings))
                 (parent-ok (satisfies-frame-p composed parent))
                 (child-ok (satisfies-frame-p child-expr pulled)))
            ;; Every parent-valid child expression (including partial `(/ '3 X0)` when X0=0 is guarded!)
            ;; MUST be accepted by `pulled` (zero false pruning).
            (when parent-ok
              (check child-ok)))))

      ;; 3. 1-to-many `lift-frame` across `:map`, `:filter`, and prefix-closed `:foldr`
      (let* ((seq-type (sequence-type :int))
             (p-inputs (list (cons 0 seq-type)))
             (xs (var 0 seq-type))
             (unary-code (code-type '((0 . :int)) :int))
             (pred-code (code-type '((0 . :int)) :bool))
             (binary-code (code-type '((0 . :int) (1 . :int)) :int)))
        ;; 3a. `:map` uncoupled lift: exact two-way equivalence
        (let* ((map-parent (simple-frame seq-type p-inputs
                                         '(((() ) ())
                                           (((2 5)) (5 11))
                                           (((-1 0)) (-1 1)))))
               (map-dec (app (op :map) xs (var 9 unary-code)))
               (lifted (lift-frame map-parent map-dec 9 unary-code))
               (candidates (list (app (op :+ :int) (app (op :* :int) (var 0 :int) (lit :int 2)) (lit :int 1))
                                 (app (op :+ :int) (var 0 :int) (lit :int 3))
                                 (var 0 :int))))
          (dolist (c candidates)
            (check (eq (satisfies-frame-p (compose-lifted-model map-dec 9 unary-code c) map-parent)
                       (satisfies-frame-p c lifted)))))

        ;; 3b. `:filter` lift: soundness (every parent-valid predicate is accepted by `lift-frame`)
        (let* ((flt-parent (simple-frame seq-type p-inputs
                                         '(((() ) ())
                                           (((-2 3 -1 5)) (3 5))
                                           (((0 4)) (4)))))
               (flt-dec (app (op :filter) xs (var 9 pred-code)))
               (lifted (lift-frame flt-parent flt-dec 9 pred-code))
               (candidates (list (app (op :< :int) (lit :int 0) (var 0 :int))
                                 (app (op :< :int) (var 0 :int) (lit :int 0))
                                 (lit :bool t)
                                 (lit :bool nil))))
          (dolist (c candidates)
            (when (satisfies-frame-p (compose-lifted-model flt-dec 9 pred-code c) flt-parent)
              (check (satisfies-frame-p c lifted)))))

        ;; 3c. `:foldr` prefix-closed lift: exact two-way equivalence on total candidates
        (let* ((fld-parent (simple-frame :int p-inputs
                                         '(((() ) 0)
                                           (((3)) 9)
                                           (((2 3)) 13)
                                           (((4 2 3)) 29))))
               (fld-dec (app (op :foldr) xs (lit :int 0) (var 9 binary-code)))
               (lifted (lift-frame fld-parent fld-dec 9 binary-code))
               (candidates (list (app (op :+ :int) (app (op :* :int) (var 0 :int) (var 0 :int)) (var 1 :int))
                                 (app (op :+ :int) (var 0 :int) (var 1 :int))
                                 (var 1 :int))))
          (dolist (c candidates)
            (check (eq (satisfies-frame-p (compose-lifted-model fld-dec 9 binary-code c) fld-parent)
                       (satisfies-frame-p c lifted)))))))))

(deftest invariant-metamorphic-row-order-and-schema-alpha-renaming
  "Verify metamorphic invariances of the synthesis kernel:
1. Permuting `frame-rows` preserves `frame-conflict-p`, optimal MDL `candidate-size` under
   exhaustive search, and active-set CEGAR convergence under `*max-active-lifted-rows*`.
2. Alpha-renaming and permuting `schema-inputs` variable IDs preserves descriptor scoring,
   `library-decompositions`, DIP context-variable repair, and synthesized semantics."
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:map :foldr))
    (let* ((seq-type (sequence-type :int))
           (gf5 (gf 5)))
      ;; 1a. Row-order invariance of `frame-conflict-p` on compatible and conflicting frames
      (let* ((inputs '((0 . :int)))
             (compat-rows (frame-rows (simple-frame :int inputs '(((1) 2) ((2) 4) ((3) 6) ((4) 8)))))
             (conflict-rows (frame-rows (simple-frame :int inputs '(((1) 2) ((2) 4) ((1) 9) ((3) 6)))))
             (schema (make-schema :inputs inputs :target :int)))
        (dolist (perm (list '(0 1 2 3) '(3 2 1 0) '(2 0 3 1) '(1 3 0 2)))
          (let ((f-ok (make-frame schema (mapcar (lambda (i) (nth i compat-rows)) perm)))
                (f-bad (make-frame schema (mapcar (lambda (i) (nth i conflict-rows)) perm))))
            (check (null (frame-conflict-p f-ok)))
            (check (frame-conflict-p f-bad)))))

      ;; 1b. Row-order invariance of optimal MDL `candidate-size` under `:bounded-exhaustion`
      (let* ((inputs (list (cons 0 gf5) (cons 1 gf5)))
             (target-expr (app (op :+ gf5) (var 0 gf5) (app (op :* gf5) (lit gf5 2) (var 1 gf5))))
             (bound (description-size target-expr inputs))
             (base-frame (simple-frame gf5 inputs
                                       '(((0 1) 2) ((1 0) 1) ((2 2) 1) ((3 4) 1) ((4 1) 1))))
             (rows (frame-rows base-frame))
             (lang (make-language gf5 inputs
                                  :operators (list (op :+ gf5) (op :* gf5))
                                  :literals '(0 1 2)))
             (sizes nil))
        (dolist (perm (list '(0 1 2 3 4) '(4 3 2 1 0) '(2 4 0 3 1) '(1 3 4 0 2)))
          (let* ((p-frame (make-frame (frame-schema base-frame)
                                      (mapcar (lambda (i) (nth i rows)) perm)))
                 (job (start-search p-frame lang))
                 (msg (resume-search job bound 200000)))
            (check (eq :bounded-exhaustion (message-claim msg)))
            (check (search-job-best job))
            (push (candidate-size (search-job-best job)) sizes)))
        (check (= 1 (length (remove-duplicates sizes)))))

      ;; 1c. Row-order invariance of CEGAR convergence under `*max-active-lifted-rows* = 2`
      (let* ((inputs (list (cons 0 seq-type)))
             (base-frame (simple-frame seq-type inputs
                                       '((((0)) (1))
                                         (((1)) (3))
                                         (((2)) (5))
                                         (((3 4)) (7 9)))))
             (rows (frame-rows base-frame))
             (lang (make-language :int inputs
                                  :operators (list (op :map) (op :+ :int) (op :* :int))
                                  :literals '(1 2)
                                  :constants (list (lit seq-type '())))))
        (let ((*max-active-lifted-rows* 2))
          (dolist (perm (list '(0 1 2 3) '(3 2 1 0) '(2 0 3 1)))
            (let ((p-frame (make-frame (frame-schema base-frame)
                                       (mapcar (lambda (i) (nth i rows)) perm))))
              (check-synthesis-task p-frame lang 75
                                    :budget 60000
                                    :held-out '((((10 20)) (21 41))))))))

      ;; 2. Input schema alpha-renaming and permutation invariance:
      ;;    Compare canonical `((0 . (:seq :int)) (1 . :int))` against permuted/renamed
      ;;    `((9 . :int) (4 . (:seq :int)))` on `add-len-plus-k(xs, k)` (exercising descriptor
      ;;    scoring, `library-decompositions`, `:code-subst` capture, and DIP context repair).
      (let* ((inputs-a (list (cons 0 seq-type) (cons 1 :int)))
             (inputs-b (list (cons 9 :int) (cons 4 seq-type)))
             (frame-a (simple-frame seq-type inputs-a
                                    '(((() 5) ())
                                      (((10) 1) (12))
                                      (((10 20) 1) (13 23))
                                      (((5 10 20) 2) (10 15 25)))))
             (frame-b (simple-frame seq-type inputs-b
                                    '(((5 ()) ())
                                      ((1 (10)) (12))
                                      ((1 (10 20)) (13 23))
                                      ((2 (5 10 20)) (10 15 25)))))
             (lang-a (make-language :int inputs-a
                                    :operators (list (op :map) (op :foldr) (op :length :int) (op :+ :int))
                                    :literals nil
                                    :constants (list (lit seq-type '()))))
             (lang-b (make-language :int inputs-b
                                    :operators (list (op :map) (op :foldr) (op :length :int) (op :+ :int))
                                    :literals nil
                                    :constants (list (lit seq-type '())))))
        (multiple-value-bind (ok-a delta-a) (score-entry-by-descriptors :map frame-a 0)
          (multiple-value-bind (ok-b delta-b) (score-entry-by-descriptors :map frame-b 4)
            (check (eq ok-a ok-b))
            (check (= delta-a delta-b))))
        (check (= (length (library-decompositions frame-a lang-a :child-bound 60))
                  (length (library-decompositions frame-b lang-b :child-bound 60))))
        (let ((expr-a (check-synthesis-task frame-a lang-a 95
                                            :budget 60000
                                            :held-out '((((1 2 3) 10) (14 15 16)))))
              (expr-b (check-synthesis-task frame-b lang-b 95
                                            :budget 60000
                                            :held-out '(((10 (1 2 3)) (14 15 16))))))
          (dolist (pair '((() 7) ((1 2 3) 10) ((-2 0 4 8) -3)))
            (destructuring-bind (seq-val k-val) pair
              (let ((run-a (evaluate expr-a inputs-a (list seq-val k-val)))
                    (run-b (evaluate expr-b inputs-b (list k-val seq-val))))
                (check (eq :value (evaluation-status run-a)))
                (check (eq :value (evaluation-status run-b)))
                (check (equal (evaluation-value run-a) (evaluation-value run-b)))))))))))

(deftest invariant-warm-library-distractor-resilience-and-consolidation-idempotence
  "Verify that a warm `knowledge-library` populated with 12+ distractor functions, uncertified
solvers, validated laws, decoder templates, and misleading empirical descriptors never causes
unsound pruning, and that repeated `consolidate-knowledge-library` + serialization round-trips
are idempotent."
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:map :foldr :filter))
    (let* ((seq-type (sequence-type :int))
           (gf5 (gf 5))
           (xs (var 0 seq-type)))
      ;; 1. Populate 12 distractor functions across scalar, finite-field, and sequence signatures
      (dotimes (k 4)
        (let ((scalar-name (intern (format nil "DISTRACT-INT-~D" k) :keyword))
              (gf-name (intern (format nil "DISTRACT-GF5-~D" k) :keyword))
              (seq-name (intern (format nil "DISTRACT-SEQ-~D" k) :keyword)))
          (define-function scalar-name '((0 . :int)) :int
            (app (op :+ :int) (var 0 :int) (lit :int (+ 10 k))))
          (define-function gf-name (list (cons 0 gf5)) gf5
            (app (op :+ gf5) (var 0 gf5) (lit gf5 (mod (1+ k) 5))))
          (define-function seq-name (list (cons 0 seq-type)) seq-type
            (lambda (self)
              (app (op :if seq-type)
                   (app (op := seq-type) xs (lit seq-type '()))
                   (lit seq-type '())
                   (app (op :cons :int)
                        (app (op :+ :int) (app (op :at seq-type) xs (lit :int 0)) (lit :int (+ 50 k)))
                        (app self (app (op :tail :int) xs))))))))

      ;; 2. Register tentative `:int` solvers, certified `GF(5)` laws, and an uncertified misleading
      ;;    empirical descriptor attached to `:map` (must act ONLY as a soft hint, never pruning `:map`!).
      (dolist (op-name '(:+ :- :* :/))
        (register-kernel-arithmetic-solver :int op-name 0)
        (register-kernel-arithmetic-solver :int op-name 1))
      (let ((law-val (checked-law (make-law gf5 (list (cons 0 gf5))
                                            (app (op :+ gf5) (var 0 gf5) (lit gf5 0))
                                            (var 0 gf5)))))
        (register-knowledge-law law-val))
      (register-knowledge-entry
       (make-knowledge-entry
        :id :misleading-empirical-map-hint
        :kind :descriptor
        :domain :int
        :inputs (list (cons 0 seq-type) (cons 1 seq-type))
        :target :bool
        :expression (app (op := seq-type) (var 1 seq-type) (lit seq-type '(999)))
        :guard (lit :bool t)
        :status :empirical
        :edges '((:describes :map))
        :metadata '(:facet :sampled-content :tier 2 :weight-bits 4 :work-cost 2 :failure :violated)))
      (add-knowledge-edge :map :described-by :misleading-empirical-map-hint)
      (check (library-function-descriptor-compatible-p
              (simple-frame seq-type (list (cons 0 seq-type)) '((((1 2)) (3 6))))
              0 :map (make-ledger)))

      ;; 3. Target synthesis in the warm distractor-filled library still succeeds cleanly
      (let* ((inputs (list (cons 0 seq-type)))
             (target-frame (simple-frame seq-type inputs
                                         '(((() ) ())
                                           (((2)) (7))
                                           (((4 2)) (13 7))
                                           (((-1 3)) (-2 10)))))
             (distractor-ops (loop for k below 4
                                   collect (op (intern (format nil "DISTRACT-SEQ-~D" k) :keyword))))
             (lang (make-language :int inputs
                                  :operators (append (list (op :map) (op :foldr) (op :filter)
                                                           (op :+ :int) (op :* :int))
                                                     distractor-ops)
                                  :literals '(1 3)
                                  :constants (list (lit seq-type '()))))
             (prop-lib (as-propagator-library *knowledge-library* (make-ledger))))
        (multiple-value-bind (expr job)
            (check-synthesis-task target-frame lang 75
                                  :budget 60000
                                  :library prop-lib
                                  :must-call-ops '(:map)
                                  :held-out '((((0 5 -3)) (1 16 -8))))
          (declare (ignore expr))
          ;; 4. Consolidation + persistence idempotence:
          ;;    First consolidation ingests `job` and runs all consolidation hooks;
          ;;    subsequent consolidations + serialize/deserialize round-trips on unchanged state
          ;;    must reach a strict fixed point without duplicating descriptors or functors.
          (consolidate-knowledge-library *knowledge-library*
                                         :synthesis-jobs (list job)
                                         :retype-domains (list (gf 7)))
          ;; Stabilize hooks once more, then check fixed-point idempotence across round-trip + re-consolidation
          (consolidate-knowledge-library *knowledge-library*)
          (let* ((snap-1 (serialize-knowledge-library *knowledge-library*))
                 (restored-1 (deserialize-knowledge-library snap-1))
                 (count-1 (length (knowledge-library-entries restored-1)))
                 (desc-1 (length (knowledge-entries-of-kind :descriptor restored-1)))
                 (func-1 (length (knowledge-entries-of-kind :functor restored-1))))
            (consolidate-knowledge-library restored-1)
            (let* ((snap-2 (serialize-knowledge-library restored-1))
                   (restored-2 (deserialize-knowledge-library snap-2))
                   (count-2 (length (knowledge-library-entries restored-2)))
                   (desc-2 (length (knowledge-entries-of-kind :descriptor restored-2)))
                   (func-2 (length (knowledge-entries-of-kind :functor restored-2))))
              (check (= count-1 count-2))
              (check (= desc-1 desc-2))
              (check (= func-1 func-2))
              ;; Verify the restored library remains immediately functional for synthesis
              (with-knowledge-library (restored-2)
                (check-synthesis-task target-frame lang 75
                                      :budget 60000
                                      :must-call-ops '(:map)
                                      :held-out '((((10)) (31))))))))))))
