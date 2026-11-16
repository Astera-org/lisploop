(in-package #:lisploop)

;;; ===========================================================================
;;; Plan 8: Geometric & Topological Unification (SMOCE) & Product Completeness
;;; ===========================================================================

(defun satisfiability-frame-p (expr frame)
  "True when EXPR satisfies every constrained row of FRAME."
  (let ((inputs (schema-inputs (frame-schema frame))))
    (every (lambda (row)
             (or (equal (lit :bool t) (row-requirement row))
                 (let ((run (evaluate expr inputs (row-known row))))
                   (and (eq :value (evaluation-status run))
                        (accepts (row-requirement row) (evaluation-value run))))))
           (frame-rows frame))))

;;; ---------------------------------------------------------------------------
;;; Phase P8.1: Product Completeness, Safe `:code-eval` Let-Sharing,
;;; Bucket-Pair Exception Guards, and Constructor-AU / Template AU
;;; ---------------------------------------------------------------------------

(deftest plan8-p1-safe-code-eval-let-sharing
  "Verify definedness-safe homoiconic `:code-eval` let-sharing in `compose-model` and
`compose-product-model`: compresses total/demanded multi-use compound bindings strictly
without introducing eager evaluation errors on partial dead branches."
  (with-clean-kernel-state
    (let* ((tup (tuple-type :int :int))
           (inputs (list (cons 0 tup) (cons 1 :int)))
           (x0 (var 0 tup))
           (x1 (var 1 :int))
           (v9 (var 9 :int))
           (sum-head (term `(+ (at ,x0 0) ,x1)))
           (s1 (term `(at ,x0 1)))
           ;; Multi-use total binding inside conditional tuple (mirrors Probe 5 step body)
           (step-inline (term `(tuple ,sum-head (if (= ,sum-head ,s1) (+ ,s1 ,x1) ,s1))))
           (step-dec (term `(tuple ,v9 (if (= ,v9 ,s1) (+ ,s1 ,x1) ,s1))))
           (led (make-ledger))
           (shared (compose-model step-dec 9 sum-head (identity-bindings inputs) led :inputs inputs)))
      (check (provably-total-p shared))
      (check (expression-calls-operator-p shared :code-eval))
      (check (< (description-size shared inputs) (description-size step-inline inputs)))
      (check-codec-roundtrip shared inputs)
      (dolist (vals '(((2 3) 1) ((1 4) 2) ((0 0) 5) ((-3 4) 7)))
        (check (equal (outcome-signature step-inline inputs vals)
                      (outcome-signature shared inputs vals))))

      ;; Definedness-safety invariant: partial expression `(/ 10 X0)` used multiple times inside
      ;; a lazy `:if` else-branch MUST NOT be eagerly hoisted to `:code-eval` arguments.
      (let* ((int-in '((0 . :int)))
             (z (var 0 :int))
             (partial-div (term `(/ 10 ,z)))
             (zero-tup (lit tup '(0 0)))
             (guarded-inline (term `(if (= ,z 0) ,zero-tup
                                        (tuple (+ ,partial-div 1) (+ ,partial-div ,partial-div)))))
             (guarded-dec (term `(if (= ,z 0) ,zero-tup
                                     (tuple (+ ,v9 1) (+ ,v9 ,v9)))))
             (guarded-shared (compose-model guarded-dec 9 partial-div (identity-bindings int-in)
                                            nil :inputs int-in)))
        (dolist (vals '((0) (1) (2) (-5)))
          (check (equal (outcome-signature guarded-inline int-in vals)
                        (outcome-signature guarded-shared int-in vals))))
        (check (equal '(:value (0 0)) (outcome-signature guarded-shared int-in '(0))))

        ;; Strictly demanded partial subexpression MAY be shared safely because inline already fails.
        (let* ((demanded-dec (term `(+ ,v9 (* ,v9 ,z))))
               (demanded-shared (compose-model demanded-dec 9 partial-div (identity-bindings int-in)
                                               nil :inputs int-in)))
          (dolist (vals '((0) (2) (-5)))
            (check (equal (outcome-signature (instantiate demanded-dec (list (cons 9 partial-div)) :var)
                                             int-in vals)
                          (outcome-signature demanded-shared int-in vals))))
          (check (equal '(:error nil) (outcome-signature demanded-shared int-in '(0))))))

      ;; Negative control: single-use binding stays inline rather than inflating size with `:code-eval`.
      (let* ((single-in '((0 . :int) (1 . :int)))
             (single-dec (term `(+ ,v9 ,(var 1 :int))))
             (single-res (compose-model single-dec 9 (term `(+ ,(var 0 :int) 1))
                                        (identity-bindings single-in) nil :inputs single-in)))
        (check (not (expression-calls-operator-p single-res :code-eval)))))))

(deftest plan8-p1-bucket-pair-exception-guards
  "Verify Stage A `heuristic-buckets` pairing discovers >20-bit relational `=` and `<`
exception guards with zero extra observational search, and rejects non-separating buckets."
  (with-clean-kernel-state
    ;; 1. Equality relational guard: (= (+ X0 X2) X1) — 27 body bits
    (let* ((proj-in '((0 . :int) (1 . :int) (2 . :int)))
           (rows (loop for (s0 s1 a) in '((0 2 1) (1 2 1) (2 3 1) (3 4 -1) (2 4 -1) (5 2 -1) (3 2 -1))
                       for i from 0
                       collect (make-row :key i :known (list s0 s1 a)
                                         :requirement (singleton-requirement :int (if (= (+ s0 a) s1) (+ s1 a) s1)))))
           (frame (make-frame (make-schema :inputs proj-in :target :int) rows))
           (stage-a-lang (make-language :int proj-in
                                        :operators (list (op :+ :int) (op :- :int))
                                        :literals '(0 1)))
           (guard-lang (default-guard-language
                        frame
                        (make-language :int proj-in
                                       :operators (list (op :+ :int) (op :- :int) (op := :int) (op :< :int) (op :if :int))
                                       :literals '(0 1))))
           (led (make-ledger))
           (hm (condense-heuristic frame stage-a-lang :work-limit 30000 :ledger led))
           (mask (heuristic-hit-mask frame hm))
           (buckets (heuristic-buckets hm)))
      (check buckets)
      (multiple-value-bind (guard invert-p)
          (find-sound-exception-guard frame mask guard-lang 20 0 led :buckets buckets)
        (check guard)
        (check (<= 21 (body-size guard proj-in) 32))
        (dolist (row rows)
          (let ((gv (result guard proj-in (row-known row)))
                (hit-p (nth (row-key row) mask)))
            (check (eq (if invert-p (not hit-p) hit-p) gv))))
        (dolist (ho '((4 6 2 nil) (4 6 1 t) (-2 3 5 nil) (0 0 1 t)))
          (destructuring-bind (s0 s1 a expected-hit-p) ho
            (let ((gv (result guard proj-in (list s0 s1 a))))
              (check (eq expected-hit-p (if invert-p (not gv) gv))))))))

    ;; 2. Inequality relational guard: (< (+ X0 X2) X1)
    (let* ((proj-in '((0 . :int) (1 . :int) (2 . :int)))
           (rows (loop for (s0 s1 a) in '((0 3 1) (1 4 2) (3 3 1) (4 2 -1) (5 2 0) (1 1 -2) (2 5 0))
                       for i from 0
                       collect (make-row :key i :known (list s0 s1 a)
                                         :requirement (singleton-requirement :int (if (< (+ s0 a) s1) (+ s1 a) s1)))))
           (frame (make-frame (make-schema :inputs proj-in :target :int) rows))
           (stage-a-lang (make-language :int proj-in
                                        :operators (list (op :+ :int) (op :- :int))
                                        :literals '(0 1)))
           (guard-lang (default-guard-language
                        frame
                        (make-language :int proj-in
                                       :operators (list (op :+ :int) (op :- :int) (op := :int) (op :< :int) (op :if :int))
                                       :literals '(0 1))))
           (led (make-ledger))
           (hm (condense-heuristic frame stage-a-lang :work-limit 30000 :ledger led))
           (mask (heuristic-hit-mask frame hm)))
      (multiple-value-bind (guard invert-p)
          (find-sound-exception-guard frame mask guard-lang 20 0 led :buckets (heuristic-buckets hm))
        (check guard)
        (dolist (row rows)
          (let ((gv (result guard proj-in (row-known row)))
                (hit-p (nth (row-key row) mask)))
            (check (eq (if invert-p (not hit-p) hit-p) gv))))))

    ;; 3. Negative control: hits and misses both span all three relations (`<`, `=`, `>`),
    ;;    so no pairwise `=` or `<` on the buckets can separate them.
    (let* ((inputs '((0 . :int) (1 . :int)))
           (frame (simple-frame :int inputs '(((1 1) 10) ((2 3) 10) ((3 2) 10)
                                              ((1 2) 20) ((2 1) 20) ((3 3) 20))))
           (stage-a-lang (make-language :int inputs :operators nil :literals nil))
           (guard-lang (default-guard-language frame stage-a-lang))
           (led (make-ledger))
           (buckets (list (cons (var 0 :int) '(1 2 3 1 2 3))
                          (cons (var 1 :int) '(1 3 2 2 1 3))))
           (guard (find-sound-exception-guard frame '(t t t nil nil nil) guard-lang 16 0 led :buckets buckets)))
      (check (null guard)))))

(deftest plan8-p1-parallel-product-and-probe5-resumption
  "Verify parallel `product-slots`, alpha-invariant `:tuple-projection`, Probe 5 conditional
`:scan-tup` solving with held-out rollout & unit-step anytime resumption parity, plus negative
controls rejecting coupled tuple requirements while preserving Galois soundness."
  (with-clean-kernel-state
    (let* ((tup (tuple-type :int :int))
           (seq-int (sequence-type :int))
           (seq-tup (sequence-type tup))
           (step-tup (code-type (list (cons 0 tup) (cons 1 :int)) tup)))
      (define-function :scan-tup (list (cons 0 seq-int) (cons 1 tup) (cons 2 step-tup)) seq-tup
        (lambda (self)
          (let* ((actions (var 0 seq-int)) (state (var 1 tup)) (step (var 2 step-tup))
                 (next (term `(code-eval ,step ,state (at ,actions 0)))))
            (term `(if (= ,actions ()) () (cons ,next (,self (tail ,actions) ,next ,step))) seq-tup))))

      ;; 1. Probe 5 conditional tuple scan + held-out generalization + unit-step anytime parity
      (let* ((in-tup (list (cons 0 seq-int) (cons 1 tup)))
             (f-cond (make-frame (make-schema :inputs in-tup :target seq-tup)
                                 (list (make-row :key 0 :known '((1 1) (0 2))
                                                 :requirement (singleton-requirement seq-tup '((1 2) (2 3))))
                                       (make-row :key 1 :known '((1 1) (0 3))
                                                 :requirement (singleton-requirement seq-tup '((1 3) (2 3))))
                                       (make-row :key 2 :known '((-1 -1) (4 2))
                                                 :requirement (singleton-requirement seq-tup '((3 2) (2 1)))))))
             (lang-cond (make-language :int in-tup
                                       :operators (list (op :+ :int) (op :- :int) (op := :int) (op :if :int)
                                                        (op :tuple tup) (op :at tup) (op :scan-tup))
                                       :literals '(0 1))))
        (multiple-value-bind (expr job cand)
            (check-synthesis-task f-cond lang-cond 260
                                  :budget 800000
                                  :must-call-ops '(:scan-tup)
                                  :held-out '((((1 1 2) (0 2)) ((1 2) (2 3) (4 3)))
                                              (((1 -1 1 -1) (2 3)) ((3 4) (2 4) (3 4) (2 4)))))
          (declare (ignore job))
          (check (<= (candidate-size cand) 260))
          (check (expression-calls-operator-p expr :code-eval)))
        (check-synthesis-resumption
         (lambda ()
           (start-heuristic-synthesis f-cond lang-cond 260 :library-proposals-p t :library-functions '(:scan-tup)))
         :budget 800000
         :stop-on-first t
         :limits '(0 1 2 5 13 1000 50000 200000 500000 800000)))

      ;; 2. Structural constant computational-depth: tuple product + tuple projection works at max-depth = 1
      (let* ((in-proj (list (cons 7 tup)))
             (f-tuple (make-frame (make-schema :inputs in-proj :target tup)
                                  (list (make-row :key 0 :known '((2 5)) :requirement (singleton-requirement tup '(3 10)))
                                        (make-row :key 1 :known '((4 7)) :requirement (singleton-requirement tup '(5 14))))))
             (lang-proj (make-language :int in-proj
                                       :operators (list (op :+ :int) (op :tuple tup) (op :at tup))
                                       :literals '(1))))
        (check-synthesis-task f-tuple lang-proj 120
                              :budget 50000
                              :max-depth 1
                              :held-out '((((10 -3)) (11 -6)))))

      ;; 3. Alpha-renaming & permutation invariance of `:tuple-projection`
      (let* ((in-a (list (cons 0 tup) (cons 1 :int)))
             (in-b (list (cons 9 :int) (cons 4 tup)))
             (f-a (simple-frame :int in-a '((((2 3) 5) 10) (((1 4) 2) 7))))
             (f-b (simple-frame :int in-b '(((5 (2 3)) 10) ((2 (1 4)) 7))))
             (l-a (make-language :int in-a :operators (list (op :+ :int) (op :at tup)) :literals nil))
             (l-b (make-language :int in-b :operators (list (op :+ :int) (op :at tup)) :literals nil))
             (p-a (first (tuple-projection-decompositions f-a l-a 60)))
             (p-b (first (tuple-projection-decompositions f-b l-b 60))))
        (check p-a)
        (check p-b)
        (check (= 3 (length (decomposition-bindings p-a))))
        (check (= 3 (length (decomposition-bindings p-b))))
        (let ((ea (check-synthesis-task f-a l-a 90 :budget 40000 :held-out '((((4 5) 6) 15))))
              (eb (check-synthesis-task f-b l-b 90 :budget 40000 :held-out '(((6 (4 5)) 15)))))
          (check (= (result ea in-a '((10 20) 30))
                    (result eb in-b '(30 (10 20)))))))

      ;; 4. Galois soundness & negative control: Cartesian multi-valued tuple requirements factor cleanly,
      ;;    while coupled / non-Cartesian tuple requirements (`(0,1) or (1,0)`, `at 0 = at 1`) MUST be rejected!
      (let* ((z (var 0 tup))
             (slots (list (list 9 :int :int nil (lit :int 0))
                          (list 10 :int :int nil (lit :int 0))))
             (dummy-prop (make-decomposition :name '(:tuple-product 2)
                                             :decoder (app (op :tuple tup) (var 9 :int) (var 10 :int))
                                             :child-id 9 :child-type tup
                                             :bindings (list (cons 0 (var 0 :int)))
                                             :product-slots slots))
             (cartesian-req (set-requirement tup '((0 2) (0 3) (1 2) (1 3))))
             (non-cart-req (set-requirement tup '((0 1) (1 0))))
             (sym-coupled-req (app (op := :int) (term `(at ,z 0)) (term `(at ,z 1))))
             (f-cart (make-frame (make-schema :inputs '((0 . :int)) :target tup)
                                 (list (make-row :key 0 :known '(1) :requirement cartesian-req))))
             (f-noncart (make-frame (make-schema :inputs '((0 . :int)) :target tup)
                                    (list (make-row :key 0 :known '(1) :requirement non-cart-req))))
             (f-sym (make-frame (make-schema :inputs '((0 . :int)) :target tup)
                                (list (make-row :key 0 :known '(1) :requirement sym-coupled-req)))))
        (multiple-value-bind (sf-cart cf-cart) (pullback-product-frames dummy-prop f-cart)
          (check (null cf-cart))
          (check (= 2 (length sf-cart)))
          (dolist (e0 (list (lit :int 0) (lit :int 1) (lit :int 2)))
            (dolist (e1 (list (lit :int 2) (lit :int 3) (lit :int 9)))
              (let ((parent-e (app (op :tuple tup) e0 e1)))
                (check (eq (satisfiability-frame-p parent-e f-cart)
                           (and (satisfiability-frame-p e0 (first sf-cart))
                                (satisfiability-frame-p e1 (second sf-cart)))))))))
        (multiple-value-bind (sf-noncart cf-noncart) (pullback-product-frames dummy-prop f-noncart)
          (check (null sf-noncart))
          (check cf-noncart))
        (multiple-value-bind (sf-sym cf-sym) (pullback-product-frames dummy-prop f-sym)
          (check (null sf-sym))
          (check cf-sym))))))

(deftest plan8-p1-constructor-au-and-decoder-template-au
  "Verify aligned Constructor-AU (`FO` all-lit dynamic holes and `:fn` operator holes), pure
`au-substitutions-frame`, `:decoder-template` single-hole AU generalization + persistence + solving,
and negative controls."
  (with-clean-kernel-state
    (let* ((inner (list (cons 0 :int)))
           (code-t (code-type inner :int))
           (outer-in (list (cons 0 :int)))
           (x0 (var 0 :int))
           (fo-cases (list (list (list 1) (app (op :+ :int) (app (op :* :int) x0 (lit :int 2)) (lit :int 1)))
                           (list (list 3) (app (op :+ :int) (app (op :* :int) x0 (lit :int 2)) (lit :int 3)))))
           (f-fo (simple-frame code-t outer-in fo-cases))
           (bin-fn (operator-type (op :+ :int)))
           (bin-code (code-type nil bin-fn))
           (lang-fo (make-language :int outer-in
                                   :operators (list (op :+ :int) (op :* :int) (op :if :int) (op := :int))
                                   :literals '(0 1 2)
                                   :constants (list (lit code-t x0)
                                                    (lit bin-code (op :+ :int))
                                                    (lit bin-code (op :* :int))))))
      ;; 1. FO all-lit Constructor-AU (`(+ (* X0 '2) ?0)` -> fills `?0` dynamically from outer X0)
      (multiple-value-bind (pattern subs)
          (anti-unify (mapcar #'second fo-cases) inner nil :operator-holes-p t)
        (let ((au-frame (au-substitutions-frame pattern subs :inputs inner)))
          (check (= 2 (length (frame-rows au-frame))))
          (check (tuple-type-p (schema-target (frame-schema au-frame))))))
      (let ((expr-fo (check-synthesis-task f-fo lang-fo 220
                                           :budget 200000
                                           :held-out (list (list '(7) (app (op :+ :int) (app (op :* :int) x0 (lit :int 2)) (lit :int 7)))))))
        (check (equal (app (op :+ :int) (app (op :* :int) x0 (lit :int 2)) (lit :int -4))
                      (result expr-fo outer-in '(-4)))))

      ;; 2. `:fn` operator-hole Constructor-AU (`(?0 X0 '1)` switching between `+` and `*`)
      (let* ((fn-cases (list (list '(0) (app (op :+ :int) x0 (lit :int 1)))
                             (list '(1) (app (op :* :int) x0 (lit :int 1)))))
             (f-fn (simple-frame code-t outer-in fn-cases))
             (expr-fn (check-synthesis-task f-fn lang-fo 240
                                            :budget 300000
                                            :held-out (list (list '(0) (app (op :+ :int) x0 (lit :int 1)))
                                                            (list '(5) (app (op :* :int) x0 (lit :int 1)))))))
        (check (expression-calls-operator-p expr-fn :code-apply)))

      ;; 3. Negative control: identical target across rows has no disagreement holes -> no Constructor-AU
      (let* ((f-same (simple-frame code-t outer-in
                                   (list (list '(0) (app (op :+ :int) x0 (lit :int 1)))
                                         (list '(1) (app (op :+ :int) x0 (lit :int 1)))))))
        (check (null (product-decompositions f-same lang-fo 200)))))

    ;; 4. `:decoder-template` single-hole AU + persistence + fresh task solving & negative control
    (let* ((inputs '((0 . :int) (1 . :int)))
           (p1 (make-decomposition
                :decoder (app (op :* :int) (app (op :+ :int) (var 1 :int) (var 9 :int)) (lit :int 3))
                :child-id 9 :child-type :int :bindings (identity-bindings inputs)))
           (p2 (make-decomposition
                :decoder (app (op :* :int) (app (op :- :int) (var 1 :int) (var 9 :int)) (lit :int 3))
                :child-id 9 :child-type :int :bindings (identity-bindings inputs)))
           ;; Incompatible decoder (creates >1 holes with p1/p2) must NOT produce bogus single-hole AU
           (p3 (make-decomposition
                :decoder (app (op :+ :int) (var 9 :int) (lit :int 7))
                :child-id 9 :child-type :int :bindings (identity-bindings inputs))))
      (remember-decoder-template p1 inputs)
      (remember-decoder-template p2 inputs)
      (with-knowledge-library ((deserialize-knowledge-library (serialize-knowledge-library)))
        (let* ((fresh-in '((4 . :int) (8 . :int)))
               ;; Target: (* (+ X4 X8) 3) -> `:learned-template-au` offers `(* Z 3)` so child solves `(+ X4 X8)`
               (fresh-frame (simple-frame :int fresh-in '(((1 2) 9) ((3 4) 21) ((0 5) 15))))
               (fresh-lang (make-language :int fresh-in :operators (list (op :+ :int)) :literals nil))
               (props (learned-decoder-decompositions fresh-frame fresh-lang 60 nil (make-ledger)))
               (au-props (remove-if-not (lambda (d)
                                          (and (consp (decomposition-name d))
                                               (eq :learned-template-au (first (decomposition-name d)))))
                                        props)))
          (check (= 1 (length au-props)))
          ;; Even with `:*` withheld from fresh-lang operators, `:learned-template-au` solves the task!
          (let ((expr (check-synthesis-task fresh-frame fresh-lang 60
                                            :budget 40000
                                            :library *knowledge-library*
                                            :held-out '(((10 -4) 18) ((-2 -3) -15)))))
            (check (expression-calls-operator-p expr :*)))))
      ;; Adding unrelated template `p3` breaks single-hole AU across all 3 templates cleanly
      (with-clean-kernel-state
        (remember-decoder-template p1 inputs)
        (remember-decoder-template p3 inputs)
        (let* ((f-neg (simple-frame :int inputs '(((1 2) 9) ((3 4) 21))))
               (l-neg (make-language :int inputs :operators (list (op :+ :int)) :literals nil))
               (au-neg (remove-if-not (lambda (d)
                                        (and (consp (decomposition-name d))
                                             (eq :learned-template-au (first (decomposition-name d)))))
                                      (learned-decoder-decompositions f-neg l-neg 60 nil (make-ledger)))))
          (check (null au-neg)))))))

;;; ---------------------------------------------------------------------------
;;; Phase P8.2: Co-Induced DSL Metrics, Heuristic Solvers, & Arity-Scaled M9
;;; ---------------------------------------------------------------------------

(deftest plan8-p2-explicit-metric-and-resumption
  "Verify explicit `:metric` AST hooks on `frame`, `condense-heuristic`, `start-heuristic-search`,
`start-synthesis`, `propagate-requirements` preservation, metered ledger accounting, negative
controls on invalid/non-matching metrics, and `check-heuristic-search-resumption`."
  (with-clean-kernel-state
    ;; Explicit :metric AST on :int: cost = (if (= X0 X1) 0 (if (< X0 0) 20 1))
    ;; Makes negative baseline lose badly while making X0 look near X1.
    (let* ((inputs '((0 . :int)))
           (metric (term `(if (= ,(var 0 :int) ,(var 1 :int)) 0 (if (< ,(var 0 :int) 0) 20 1)) :int))
           (frame (make-frame (make-schema :inputs inputs :target :int)
                              (list (make-row :key 0 :known '(1) :requirement (singleton-requirement :int 100))
                                    (make-row :key 1 :known '(2) :requirement (singleton-requirement :int 200))
                                    (make-row :key 2 :known '(3) :requirement (singleton-requirement :int 300)))
                              :metric metric))
           (lang (make-language :int inputs :operators nil :literals '(-1)))
           (led (make-ledger)))
      (check (equal metric (frame-metric frame)))
      ;; `propagate-requirements` via `derive-frame` preserves `frame-metric`.
      (let ((prop (propagate-requirements frame *knowledge-library* (make-ledger))))
        (check (equal metric (frame-metric (propagation-frame prop)))))
      ;; `correction` meters `:metric-evaluation` on ledger and keeps a valid reconstruction packet.
      (multiple-value-bind (pkt bits info)
          (correction 1 100 :int t metric *knowledge-library* led)
        (check (eq :explicit-metric info))
        (check (= 1 bits))
        (check (equal 100 (apply-correction-packet 1 pkt :int t metric *knowledge-library* led)))
        (check (plusp (or (cdr (assoc :simulation (ledger-counts led))) 0))))
      ;; `select-closest-witness` meters relational/witness metric evaluation cleanly.
      (let ((wled (make-ledger)))
        (multiple-value-bind (w bits)
            (select-closest-witness -5 '(2 -3) :int t metric *knowledge-library* wled)
          (check (member w '(2 -3)))
          (check (plusp bits))
          (check (plusp (ledger-total wled)))))
      ;; `condense-heuristic` uses explicit `:metric`: `X0` (metric 1/row) beats `'-1` (metric 20/row).
      (let ((hm (condense-heuristic frame lang :work-limit 50000 :metric metric)))
        (check hm)
        (check (equal (var 0 :int) (heuristic-program hm))))
      ;; Negative control 1: non-total metric AST is rejected upfront by `normalize-frame-metric`.
      (let ((bad-nontotal (term `(/ 1 (- ,(var 0 :int) ,(var 0 :int))))))
        (check (nth-value 1 (ignore-errors (normalize-frame-metric bad-nontotal :int)))))
      ;; Negative control 2: negative/invalid metric score falls back safely without crashing Stage A.
      (let* ((bad-neg-metric (lit :int -5))
             (hm-bad (condense-heuristic (derive-frame frame :metric nil) lang
                                         :work-limit 50000 :metric bad-neg-metric)))
        (check hm-bad)
        (check (typep (heuristic-score hm-bad) 'integer)))
      ;; Resumption parity with explicit :metric on `start-heuristic-search` & `start-synthesis`.
      (check-heuristic-search-resumption
       (lambda () (start-heuristic-search frame lang :metric metric))
       :budget 50000 :limits '(0 1 5 25 200 2000 50000))
      (let* ((s-lang (make-language :int inputs :operators (list (op :* :int)) :literals '(100)))
             (job (start-synthesis frame s-lang 40 :policy :heuristic :metric metric)))
        (check (equal metric (frame-metric (synthesis-node-frame (synthesis-job-root job)))))
        (resume-synthesis job 80000 :stop-on-first t)
        (check (synthesis-job-best job))))))

(deftest plan8-p2-shift-seq-mul-and-code-metrics
  "Verify totality of standard metric helpers, `(:shift-seq <-> :argmax-corr)`, `(:* <-> :/)`,
and `(:code-subst <-> :anti-unify)` packet round-trips, Stage B pullback synthesis + anytime
resumption, non-divisibility soundness, and exact two-way Galois soundness of
`unfold-constructor-equality`."
  (with-clean-kernel-state
    (define-standard-metric-decoders :library *knowledge-library* :domain :int)
    ;; 1. Every installed standard sequence/corr helper is provably total.
    (dolist (fn '(:snoc :seq-init-rest :seq-last :rot-right-1 :rot-left-1
                  :shift-right-fuel :shift-left-fuel :shift-seq :seq-eq-count
                  :argmax-step-pair :argmax-corr-loop :argmax-corr :seq-sum))
      (let ((def (find-function-definition fn)))
        (check def)
        (check (function-definition-total-p def))))

    ;; 2. `(:shift-seq <-> :argmax-corr)` packet roundtrip + Stage B synthesis WITHOUT `:shift-seq` in lang.
    (let* ((seq-int (sequence-type :int))
           (pled (make-ledger)))
      (multiple-value-bind (pkt bits info)
          (correction '(1 2 3 4) '(3 4 1 2) seq-int t nil *knowledge-library* pled)
        (check (consp info))
        (check (eq :SHIFT-SEQ/ARGMAX-CORR-METRIC-DECODER (second info)))
        (check (< bits (value-bit-size '(3 4 1 2) seq-int)))
        (check (equal '(3 4 1 2) (apply-correction-packet '(1 2 3 4) pkt seq-int t nil *knowledge-library* pled)))
        (check (plusp (ledger-total pled))))
      (let* ((inputs (list (cons 0 seq-int) (cons 1 :int)))
             (f-dyn (make-frame (make-schema :inputs inputs :target seq-int)
                                (list (make-row :key 0 :known '((1 2 3 4) 1)
                                                :requirement (singleton-requirement seq-int '(3 4 1 2)))
                                      (make-row :key 1 :known '((5 6 7 8 9) -3)
                                                :requirement (singleton-requirement seq-int '(7 8 9 5 6)))
                                      (make-row :key 2 :known '((10 20 30) 0)
                                                :requirement (singleton-requirement seq-int '(30 10 20))))))
             ;; Note `:shift-seq` is withheld from `lang-dyn` operators: only co-induced Stage B can supply it!
             (lang-dyn (make-language :int inputs
                                      :operators (list (op :+ :int) (op :tail :int))
                                      :literals '(0 1)
                                      :constants (list (lit seq-int '())))))
        (check-synthesis-task f-dyn lang-dyn 120
                              :budget 200000
                              :library *knowledge-library*
                              :must-call-ops '(:shift-seq)
                              :held-out '((((10 20 30 40) 2) (20 30 40 10))
                                          (((1 2 3) -2) (2 3 1))))
        (check-synthesis-resumption
         (lambda () (start-heuristic-synthesis f-dyn lang-dyn 120 :library *knowledge-library*))
         :budget 150000 :stop-on-first t :limits '(0 1 10 2000 30000 100000 150000))))

    ;; 3. `(:* <-> :/)` scaling metric: packet round-trip, non-divisibility negative control, & synthesis.
    (multiple-value-bind (pkt bits info)
        (correction 100 300 :int t nil *knowledge-library* (make-ledger))
      (check (consp info))
      (check (eq :MUL/DIV-METRIC-DECODER (second info)))
      (check (< bits (value-bit-size 200 :int)))
      (check (equal 300 (apply-correction-packet 100 pkt :int t nil *knowledge-library*))))
    ;; Negative control: 2 does not divide 5 -> truncating division MUST NOT forge a `:MUL/DIV` packet!
    (multiple-value-bind (pkt-bad bits-bad info-bad)
        (correction 2 5 :int t nil *knowledge-library* (make-ledger))
      (declare (ignore pkt-bad bits-bad))
      (check (null info-bad)))
    (let* ((inputs '((0 . :int) (1 . :int)))
           (f-mul (simple-frame :int inputs '(((1 2) 300) ((2 3) 500) ((4 1) 500))))
           ;; Withhold `:*` from `lang-mul`: Stage B `:MUL/DIV-METRIC-DECODER` injects `(* X Z)`!
           (lang-mul (make-language :int inputs :operators (list (op :+ :int)) :literals '(100))))
      (check-synthesis-task f-mul lang-mul 120
                            :budget 200000
                            :library *knowledge-library*
                            :must-call-ops '(:*)
                            :held-out '(((10 5) 1500) ((-2 3) 100))))

    ;; 4. `(:code-subst <-> :anti-unify)` packet round-trip, Stage B synthesis, & constructor equality soundness.
    (let* ((inner '((0 . :int) (1 . :int)))
           (ct (code-type inner :int))
           (x0 (var 0 :int)) (x1 (var 1 :int))
           (c-pred (app (op :+ :int) x0 x1))
           (c-targ1 (app (op :+ :int) x0 (app (op :* :int) x1 (lit :int 10))))
           (c-targ2 (app (op :+ :int) (lit :int 5) x1)))
      ;; 1-hole AST subtree edit round-trip
      (multiple-value-bind (pkt bits info)
          (correction c-pred c-targ1 ct t nil *knowledge-library* (make-ledger))
        (check (consp info))
        (check (eq :CODE-SUBST/ANTI-UNIFY-METRIC-DECODER (second info)))
        (check (< bits (value-bit-size c-targ1 ct)))
        (check (equal c-targ1 (apply-correction-packet c-pred pkt ct t nil *knowledge-library*))))
      ;; Variable substitution `:code-subst` round-trip
      (multiple-value-bind (pkt2 bits2 info2)
          (correction c-pred c-targ2 ct t nil *knowledge-library* (make-ledger))
        (check (consp info2))
        (check (< bits2 (value-bit-size c-targ2 ct)))
        (check (equal c-targ2 (apply-correction-packet c-pred pkt2 ct t nil *knowledge-library*))))
      ;; Stage B synthesis on `:code` with metric decoder (with base `(+ X0 100)` or `(+ X0 X1)`)
      (let* ((ct1 (code-type '((0 . :int)) :int))
             (c-base (app (op :+ :int) x0 (lit :int 100)))
             (f-code (make-frame (make-schema :inputs '((0 . :int)) :target ct1)
                                 (list (make-row :key 0 :known '(1)
                                                 :requirement (singleton-requirement ct1 (app (op :+ :int) x0 (lit :int 100))))
                                       (make-row :key 1 :known '(2)
                                                 :requirement (singleton-requirement ct1 (app (op :+ :int) x0 (lit :int 200))))
                                       (make-row :key 2 :known '(5)
                                                 :requirement (singleton-requirement ct1 (app (op :+ :int) x0 (lit :int 500)))))))
             (l-code (make-language :int '((0 . :int))
                                    :operators (list (op :* :int) (op :+ :int))
                                    :literals '(100)
                                    :constants (list (lit ct1 c-base)))))
        (check-synthesis-task f-code l-code 300
                              :budget 200000
                              :library *knowledge-library*
                              :held-out (list (list '(7) (app (op :+ :int) x0 (lit :int 700))))))
      ;; Exact two-way Galois soundness of `unfold-constructor-equality` across :tuple, :code-apply,
      ;; and cross-scope `:code-subst` (substituted AST reads outer `out-inputs` var not in `tmpl-inputs`).
      (let* ((ct1 (code-type '((0 . :int)) :int))
             (ct-in '((0 . :int) (1 . :int)))
             (tup2 (tuple-type (code-type '((0 . :int)) :int) (code-type '((0 . :int)) :int)))
             (fn-sort (list :fn '(:int :int) :int))
             (fn-ctype (code-type ct-in fn-sort))
             (ct2 (code-type ct-in :int))
             (z-int (var 0 :int))
             (tup-eq (app (op := (tuple-type :int :int))
                          (app (op :tuple (tuple-type :int :int)) z-int (lit :int 5))
                          (lit (tuple-type :int :int) '(7 5))))
             (ca-eq (app (op := ct2)
                         (app (op :code-apply fn-ctype)
                              (var 0 fn-ctype)
                              (lit (tuple-type ct2 ct2) (list x0 x1)))
                         (lit ct2 (app (op :+ :int) x0 x1))))
             ;; Template mentions only var 100; target AST substitutes var 0 + var 1 from `out-inputs`!
             (tmpl-ct (code-type '((100 . :int)) :int))
             (cs-eq (app (op := ct2)
                         (app (op :code-subst (tuple-type tmpl-ct (tuple-type ct2) ct2))
                              (lit tmpl-ct (app (op :+ :int) (var 100 :int) (lit :int 1)))
                              (app (op :tuple (tuple-type ct2)) (var 0 ct2)))
                         (lit ct2 (app (op :+ :int) (app (op :* :int) x0 x1) (lit :int 1)))))
             (cs-bad (app (op := ct2)
                          (app (op :code-subst (tuple-type tmpl-ct (tuple-type ct2) ct2))
                               (lit tmpl-ct (app (op :+ :int) (var 100 :int) (lit :int 1)))
                               (app (op :tuple (tuple-type ct2)) (var 0 ct2)))
                          (lit ct2 (app (op :- :int) x0 x1)))))
        (let ((u-tup (unfold-constructor-equality tup-eq (make-ledger))))
          (check u-tup)
          (dolist (v '(5 7 9))
            (check (eq (result tup-eq '((0 . :int)) (list v))
                       (result u-tup '((0 . :int)) (list v))))))
        (let ((u-ca (unfold-constructor-equality ca-eq (make-ledger))))
          (check u-ca)
          (dolist (opval (list (op :+ :int) (op :- :int) (op :* :int)))
            (check (eq (result ca-eq (list (cons 0 fn-ctype)) (list opval))
                       (result u-ca (list (cons 0 fn-ctype)) (list opval))))))
        (let ((u-cs (unfold-constructor-equality cs-eq (make-ledger))))
          (check u-cs)
          (dolist (cand (list (app (op :* :int) x0 x1) (app (op :+ :int) x0 x1) (lit :int 1)))
            (check (eq (result cs-eq (list (cons 0 ct2)) (list cand))
                       (result u-cs (list (cons 0 ct2)) (list cand))))))
        ;; Cross-scope unsatisfiable mismatch collapses to `'nil`
        (let ((u-bad (unfold-constructor-equality cs-bad (make-ledger))))
          (check (equal (lit :bool nil) u-bad)))
        ;; Keep `tup2` & `ct1` bindings used cleanly
        (check (tuple-type-p tup2))
        (check (code-type-p ct1))))))

(deftest plan8-p2-moment-solvers-and-3-to-1-fallback
  "Verify `induce-moment-solvers` (conserved first-moment propagation & solving), 3:1
`propagation-fallback` completeness under ambiguous correlation witnesses, and rejection of
dishonest uncertified solvers via `witness-replays-p`."
  (with-clean-kernel-state
    (define-standard-metric-decoders :library *knowledge-library* :domain :int)
    (let* ((seq-int (sequence-type :int))
           (empty (lit seq-int '())))
      ;; Helper: append at back (`:snoc` already exists!) to define `:rev-add(xs, k)` which
      ;; BOTH reverses element order AND adds `k` to every element (breaking pointwise maps!).
      (define-function :rev-add (list (cons 0 seq-int) (cons 1 :int)) seq-int
        (lambda (self)
          (let ((xs (var 0 seq-int)) (k (var 1 :int)))
            (app (op :if seq-int) (app (op := seq-int) xs empty)
                 empty
                 (app (op :snoc)
                      (app self (app (op :tail :int) xs) k)
                      (app (op :+ :int) (app (op :at seq-int) xs (lit :int 0)) k))))))
      (check (function-definition-total-p (find-function-definition :rev-add)))
      ;; 1. Moment solver induction discovers `:REV-ADD/MOMENT-ADD-SOLVER-1`
      (let* ((induced (induce-moment-solvers *knowledge-library*))
             (solver-entry (find :REV-ADD/MOMENT-ADD-SOLVER-1 induced :key #'knowledge-entry-id)))
        (check solver-entry)
        (check (null (getf (knowledge-entry-metadata solver-entry) :certified-p)))
        ;; Solve pulled-back/propagated requirement `(= (rev-add X0 Z) Y)` where `Z = (+ X1 2)`
        (let* ((inputs (list (cons 0 seq-int) (cons 1 :int)))
               (z (var 0 :int))
               (f-mom (make-frame (make-schema :inputs inputs :target :int)
                                  (list (make-row :key 0 :known '((1 2 3) 1)
                                                  :requirement (app (op := seq-int)
                                                                    (app (op :rev-add) (lit seq-int '(1 2 3)) z)
                                                                    (lit seq-int '(6 5 4))))
                                        (make-row :key 1 :known '((10 0 -4) 5)
                                                  :requirement (app (op := seq-int)
                                                                    (app (op :rev-add) (lit seq-int '(10 0 -4)) z)
                                                                    (lit seq-int '(3 7 17)))))))
               (prop (propagate-requirements f-mom *knowledge-library* (make-ledger))))
          (check (= 2 (propagation-suggested prop)))
          (check (= 3 (car (extract-allowed-values (row-requirement (first (frame-rows (propagation-frame prop))))))))
          (check (= 7 (car (extract-allowed-values (row-requirement (second (frame-rows (propagation-frame prop))))))))
          (let ((lang-z (make-language :int inputs :operators (list (op :+ :int)) :literals '(1 2))))
            (check-synthesis-task (propagation-frame prop) lang-z 40
                                  :budget 50000
                                  :held-out '((((1 1) 10) 12))))))

      ;; 2. 3:1 `propagation-fallback` completeness under ambiguous `:argmax-corr` correlation:
      ;;    Row 0 `(1 2 1 2) -> (2 1 2 1)` fits BOTH +1 and -1 (`:argmax-corr` returns +1),
      ;;    while Rows 1 & 2 require `-1`: un-narrowed fallback preserves completeness -> `(shift-seq X0 '-1)`!
      (let* ((inputs (list (cons 0 seq-int)))
             (f-amb (make-frame (make-schema :inputs inputs :target seq-int)
                                (list (make-row :key 0 :known '((1 2 1 2))
                                                :requirement (singleton-requirement seq-int '(2 1 2 1)))
                                      (make-row :key 1 :known '((10 20 30 40))
                                                :requirement (singleton-requirement seq-int '(20 30 40 10)))
                                      (make-row :key 2 :known '((7 8 9))
                                                :requirement (singleton-requirement seq-int '(8 9 7))))))
             (lang-amb (make-language :int inputs :operators (list (op :- :int))
                                      :literals '(-1 0 1) :constants (list (lit seq-int '())))))
        (check-synthesis-task f-amb lang-amb 100
                              :budget 300000
                              :library *knowledge-library*
                              :must-call-ops '(:shift-seq)
                              :held-out '((((4 5 6 7)) (5 6 7 4)))))

      ;; 3. Negative control: uncertified lying solver fails `witness-replays-p` & is rejected!
      (let* ((bad-lib (make-knowledge-library))
             (inputs '((0 . :int))))
        (register-knowledge-solver
         :rev-add :id :BAD-LYING-SOLVER :library bad-lib :domain :int
         :inputs (list (cons 0 seq-int) (cons 1 seq-int))
         :target :int :position 1
         :witness (lit :int 99) ; bogus constant witness that fails forward replay
         :certified-p nil :unique-p nil)
        (let* ((z (var 0 :int))
               (f-bad (make-frame (make-schema :inputs inputs :target :int)
                                  (list (make-row :key 0 :known '(1)
                                                  :requirement (app (op := seq-int)
                                                                    (app (op :rev-add) (lit seq-int '(1 2)) z)
                                                                    (lit seq-int '(3 2)))))))
               (prop-bad (propagate-requirements f-bad bad-lib (make-ledger))))
          (check (plusp (propagation-rejected prop-bad)))
          (check (zerop (propagation-narrowed prop-bad)))
          (check (zerop (propagation-suggested prop-bad))))))))

(deftest plan8-p2-arity-scaling-descriptors-and-eager-cap
  "Verify arity-scaled Probe 2 (< 80,000 work at bounds 90 & 110, both with and without
metric decoders), `*max-eager-proposals-per-node*` deferral/promotion ahead of fallbacks,
and `evaluate-frame-descriptors` address retrieval + persistence + zero false pruning."
  (with-clean-kernel-state
    ;; 1. Probe 2 irrelevant-input `:scan` at bounds 90 and 110 (clean & warm metric library)
    (let* ((seq-int (sequence-type :int))
           (step-int (code-type '((0 . :int) (1 . :int)) :int))
           (in-3 (list (cons 0 seq-int) (cons 1 :int) (cons 2 :int)))
           (empty (lit seq-int '())))
      (define-function :scan (list (cons 0 seq-int) (cons 1 :int) (cons 2 step-int)) seq-int
        (lambda (self)
          (let* ((actions (var 0 seq-int)) (state (var 1 :int)) (step (var 2 step-int))
                 (next (app (op :code-eval step-int) step state (app (op :at seq-int) actions (lit :int 0)))))
            (app (op :if seq-int) (app (op := seq-int) actions empty) empty
                 (app (op :cons :int) next (app self (app (op :tail :int) actions) next step))))))
      (let* ((f-irr (make-frame (make-schema :inputs in-3 :target seq-int)
                                (list (make-row :key 0 :known '((1 1) 0 7) :requirement (singleton-requirement seq-int '(1 2)))
                                      (make-row :key 1 :known '((2 -1 3) 1 9) :requirement (singleton-requirement seq-int '(3 2 5)))
                                      (make-row :key 2 :known '((-2 4) 5 3) :requirement (singleton-requirement seq-int '(3 7))))))
             (lang-3 (make-language :int in-3 :operators (list (op :+ :int) (op :- :int) (op := :int) (op :scan)) :literals '(0 1))))
        (dolist (with-metrics-p '(nil t))
          (when with-metrics-p
            (define-standard-metric-decoders :library *knowledge-library* :domain :int))
          (dolist (bnd '(90 110))
            (let ((job (start-heuristic-synthesis f-irr lang-3 bnd
                                                  :library-proposals-p t :library-functions '(:scan))))
              (resume-synthesis job 120000 :stop-on-first t)
              (check (synthesis-job-best job))
              (check (< (ledger-total (synthesis-job-ledger job)) 80000))
              (check-synthesized-model (candidate-expression (synthesis-job-best job)) f-irr
                                       :held-out '((((10 20 30) 5 -99) (15 35 65))))))))

      ;; 2. `*max-eager-proposals-per-node*` defers excess primaries ahead of fallbacks
      (let* ((*max-eager-proposals-per-node* 2)
             (inputs '((0 . :int)))
             (frame (simple-frame :int inputs '(((1) 2) ((2) 3))))
             (lang (make-language :int inputs :operators (list (op :+ :int)) :literals '(1)))
             (job (start-synthesis frame lang 30 :policy :round-robin))
             (root (synthesis-job-root job))
             (p1 (make-decomposition :name :p1 :decoder (var 9 :int) :child-id 9 :child-type :int
                                     :bindings (identity-bindings inputs) :policy-score 1))
             (p2 (make-decomposition :name :p2 :decoder (var 9 :int) :child-id 9 :child-type :int
                                     :bindings (identity-bindings inputs) :policy-score 2))
             (p3 (make-decomposition :name :p3 :decoder (var 9 :int) :child-id 9 :child-type :int
                                     :bindings (identity-bindings inputs) :policy-score 3))
             (fb (make-decomposition :name :fb :decoder (var 9 :int) :child-id 9 :child-type :int
                                     :bindings (identity-bindings inputs) :fallback-p t :policy-score -100)))
        (publish-node-expansion job root (list fb p3 p1 p2))
        ;; Only 2 primaries materialized immediately (`:p1`, `:p2`); `:p3` stays queued ahead of `:fb`!
        (let ((children (remove root (synthesis-job-nodes job))))
          (check (= 2 (length children)))
          (check (equal '(:p1 :p2) (mapcar (lambda (n) (decomposition-name (synthesis-node-proposal n))) children)))
          (check (equal '(:p3 :fb) (mapcar #'decomposition-name (synthesis-node-deferred-proposals root)))))
        ;; Promoting a deferred proposal materializes `:p3` before `:fb`
        (let ((prom (promote-next-deferred-proposal job)))
          (check prom)
          (check (eq :p3 (decomposition-name (synthesis-node-proposal prom))))
          (check (equal '(:fb) (mapcar #'decomposition-name (synthesis-node-deferred-proposals root))))))

      ;; 3. `evaluate-frame-descriptors`: address-clause retrieval + serialization round-trip + no false pruning
      (clear-knowledge-library)
      (define-function :map-inc (list (cons 0 seq-int)) seq-int
        (lambda (self)
          (let ((xs (var 0 seq-int)))
            (app (op :if seq-int) (app (op := seq-int) xs empty) empty
                 (app (op :cons :int) (app (op :+ :int) (app (op :at seq-int) xs (lit :int 0)) (lit :int 1))
                      (app self (app (op :tail :int) xs)))))))
      ;; Constant function returns '(1 2): uncertified descriptor MUST NOT falsely prune it!
      (define-function :const-pair (list (cons 0 seq-int)) seq-int
        (lambda (self)
          (declare (ignore self))
          (lit seq-int '(1 2))))
      (dolist (fn '(:map-inc :const-pair))
        (compute-entry-descriptor-profile (find-knowledge-entry fn *knowledge-library*) *knowledge-library*))
      (with-knowledge-library ((deserialize-knowledge-library (serialize-knowledge-library)))
        (let* ((f-len-eq (make-frame (make-schema :inputs (list (cons 0 seq-int)) :target seq-int)
                                     (list (make-row :key 0 :known '(()) :requirement (singleton-requirement seq-int '()))
                                           (make-row :key 1 :known '((3 4)) :requirement (singleton-requirement seq-int '(4 5)))
                                           (make-row :key 2 :known '((1 2 3)) :requirement (singleton-requirement seq-int '(2 3 4))))))
               (clauses (frame-descriptor-address-clauses f-len-eq 0)))
          (check (member :DESC/LEN-EQ clauses))
          (check (find-knowledge-entries-by-address :DESC/LEN-EQ *knowledge-library*))
          (multiple-value-bind (ranked pruned used-clauses)
              (evaluate-frame-descriptors f-len-eq :library *knowledge-library* :kind :function
                                          :candidates '(:map-inc :const-pair))
            (check (member :DESC/LEN-EQ used-clauses))
            ;; `:const-pair` violates `empty -> empty` as an empirical/necessary property? Check `:const-pair`:
            ;; `:map-inc` is compatible and ranks first; and uncertified empirical shapes never prune without necessary evidence!
            (check ranked)
            (check (eq :map-inc (getf (first ranked) :id)))
            ;; On an frame with empty->(1 2), `:const-pair` IS compatible while `:map-inc` (`empty->empty` necessary?)
            ;; Wait: specifically test an uncertified hint never prunes via `library-function-descriptor-compatible-p`:
            (check (library-function-descriptor-compatible-p f-len-eq 0 :map-inc (make-ledger)))
            ;; Explicitly attach an UNCERTIFIED false descriptor to `:const-pair`: must NEVER prune!
            (let* ((xs-var (var 0 seq-int))
                   (y-var (var 1 seq-int))
                   (false-desc (make-knowledge-entry
                                :id :CONST-PAIR/UNCERTIFIED-EMPTY
                                :kind :descriptor :domain :int
                                :inputs (list (cons 0 seq-int) (cons 1 seq-int))
                                :target :bool
                                :expression (app (op :if :bool)
                                                 (app (op := seq-int) xs-var empty)
                                                 (app (op := seq-int) y-var empty)
                                                 (lit :bool t))
                                :status :empirical :edges (list (list :describes :const-pair))
                                :library *knowledge-library*)))
              (register-knowledge-entry false-desc :library *knowledge-library*)
              (add-knowledge-edge (find-knowledge-entry :const-pair *knowledge-library*)
                                  :described-by :CONST-PAIR/UNCERTIFIED-EMPTY)
              (check (library-function-descriptor-compatible-p f-len-eq 0 :const-pair (make-ledger))))
            (let ((f-const (make-frame (make-schema :inputs (list (cons 0 seq-int)) :target seq-int)
                                       (list (make-row :key 0 :known '((9 8 7)) :requirement (singleton-requirement seq-int '(1 2)))))))
              (check (library-function-descriptor-compatible-p f-const 0 :const-pair (make-ledger))))
            (check (listp pruned))))))))

;;; ---------------------------------------------------------------------------
;;; Phase P8.3: Row-Keyed `frame-edges`, Canonical `sort-by(k(X))` Topology &
;;; `:locality-key`, Availability Preorder `\tau`, & Symbolic Unwinding
;;; ---------------------------------------------------------------------------

(deftest plan8-p3-row-keyed-edges-and-invariance
  "Verify unified row-keyed `frame-edges` (hard `:equal`/`:distinct` pruning during exact search
and `node-satisfies-frame-p`, soft `:persistence`/`:recurrence` pricing, unit-step resumption
parity, `child-scope-signature` + `nogood-identity` shuffle invariance)."
  (with-clean-kernel-state
    (let* ((inputs '((0 . :int) (1 . :int)))
           (x0 (var 0 :int))
           (x1 (var 1 :int))
           (schema (make-schema :inputs inputs :target :int))
           (rows (list (make-row :key :r0 :known '(1 5) :requirement (set-requirement :int '(1 5)))
                       (make-row :key :r1 :known '(1 9) :requirement (set-requirement :int '(1 9)))
                       (make-row :key :r2 :known '(3 5) :requirement (set-requirement :int '(3 5)))))
           ;; Hard edge requires :r0 == :r1 and :r1 /= :r2:
           ;; `x1` fails `:r0 == :r1` (`5 /= 9`), while `x0` satisfies both `:r0 == :r1` (`1 == 1`) and `:r1 /= :r2` (`1 /= 3`)!
           (hard-edges '((:equal :r0 :r1) (:distinct :r1 :r2)))
           (f-hard (make-frame schema rows :edges hard-edges))
           (f-soft (make-frame schema rows :pairs '((:r0 :r1)) :anchors '(:r1 :r2)))
           (lang (make-language :int inputs :operators (list (op :+ :int)) :literals '(0))))
      (check (equal hard-edges (frame-hard-edges f-hard)))
      (check (null (frame-soft-edges f-hard)))
      (check (null (frame-hard-edges f-soft)))
      (check (= 2 (length (frame-soft-edges f-soft))))
      (check (not (node-satisfies-frame-p f-hard x1)))
      (check (node-satisfies-frame-p f-hard x0))
      (check (node-satisfies-frame-p f-soft x1))

      ;; Unit-step resumption parity & exact hard-edge pruning vs soft-edge pricing
      (let* ((bound (+ (header-size inputs :int) 8))
             (job-unit (check-search-resumption
                        (lambda () (start-search f-hard lang))
                        bound :budget 20000 :exhaustive-p t))
             (job-soft (start-search f-soft lang)))
        (resume-search job-soft bound 20000)
        (check (search-job-best job-unit))
        (check (equal x0 (candidate-expression (search-job-best job-unit))))
        ;; `x1` passes soft-edge search (since soft edges don't prune) but is pruned in `f-hard`
        (check (find x1 (search-job-results job-soft) :key #'candidate-expression :test #'equal))
        (check (not (find x1 (search-job-results job-unit) :key #'candidate-expression :test #'equal))))

      ;; Soft edges price mismatching outcomes smoothly via `relational-linkage-residual` without pruning
      (let ((outcomes-x1 '(5 9 5))
            (outcomes-x0 '(1 1 3)))
        (multiple-value-bind (e1 total1 p1 a1) (relational-linkage-residual f-soft outcomes-x1)
          (multiple-value-bind (e0 total0 p0 a0) (relational-linkage-residual f-soft outcomes-x0)
            (declare (ignore e1 e0 a1))
            (check (zerop total0))
            (check (plusp p1))
            (check (plusp total1))
            (check (= 0 p0 a0)))))

      ;; Shuffle-frame-rows permutation invariance of `child-scope-signature`, `nogood-identity`, and optimal `candidate-size`
      (let ((sigs nil)
            (ng-ids nil)
            (sizes nil)
            (uip-expr (bool-and (term `(= ,x1 '9)) (term `(= ,x0 '1)))))
        (dolist (perm '((0 1 2) (2 0 1) (1 2 0)))
          (let* ((p-rows (mapcar (lambda (i) (nth i rows)) perm))
                 (p-frame (make-frame schema p-rows :edges hard-edges))
                 (job (start-search p-frame lang))
                 (ng (make-nogood-clause :parent-id 1 :kind :incompatible-rows
                                         :keys (reverse (mapcar #'row-key p-rows))))
                 (uip (make-nogood-clause :parent-id 1 :kind :uip-clause
                                          :keys (mapcar #'row-key p-rows)
                                          :clause-expr (if (eq perm (first '((0 1 2) (2 0 1) (1 2 0))))
                                                           uip-expr
                                                           (bool-and (term `(= ,x0 '1)) (term `(= ,x1 '9)))))))
            (resume-search job (description-size x0 inputs) 20000)
            (check (search-job-best job))
            (push (candidate-size (search-job-best job)) sizes)
            (push (child-scope-signature p-frame lang) sigs)
            (push (list (nogood-identity ng) (nogood-identity uip)) ng-ids)))
        (check (= 1 (length (remove-duplicates sigs :test #'equal))))
        (check (= 1 (length (remove-duplicates ng-ids :test #'equal))))
        (check (= 1 (length (remove-duplicates sizes))))))))

(deftest plan8-p3-sort-by-topology-and-locality-key
  "Verify canonical order-invariant `sort-by(k(X))` topology induction & `:locality-key`
registration: recovers latent `k(X) = X0 + X1` identically across row permutations, emits
`:persistence` + extremal `:distinct` edges, supplies `compute-tree-locality-positions`-style
`:locality-key` entries idempotently, handles `:seq`/projected frames, and induces zero edges on noise."
  (with-clean-kernel-state
    ;; 1. Planted permuted 2-input table with latent trajectory ordering k(X) = X0 + X1
    ;;    Points grouped into 4 regime plateaus by t = x0 + x1:
    ;;    t<=2 -> 0; t in [3,4] -> 100000; t in [5,6] -> 200000; t>=7 -> 300000
    ;;    Individual coordinates x0, x1 alone scramble output transitions!
    (let* ((inputs '((0 . :int) (1 . :int)))
           (x0 (var 0 :int))
           (x1 (var 1 :int))
           (latent-k (term `(+ ,x0 ,x1)))
           (pts '((0 1 0) (1 0 0) (1 1 0)
                  (2 1 100000) (1 2 100000) (4 0 100000)
                  (2 3 200000) (3 2 200000) (0 6 200000)
                  (4 3 300000) (2 6 300000) (8 0 300000)))
           (rows (loop for (a b y) in pts for idx from 0
                       collect (make-row :key idx :known (list a b)
                                         :requirement (singleton-requirement :int y))))
           (schema (make-schema :inputs inputs :target :int))
           (lang (make-language :int inputs :operators (list (op :+ :int) (op :- :int)) :literals '(0 1)))
           (perms '((0 4 8 1 5 9 2 6 10 3 7 11)
                    (11 10 9 8 7 6 5 4 3 2 1 0)
                    (3 7 0 10 1 5 11 4 8 2 6 9)))
           (induced-keys nil)
           (canonical-edge-sigs nil))
      (dolist (perm perms)
        (clear-knowledge-library)
        (let* ((p-rows (mapcar (lambda (i) (nth i rows)) perm))
               (p-frame (make-frame schema p-rows))
               (hm (condense-heuristic p-frame lang :work-limit 15000))
               (led (make-ledger)))
          (multiple-value-bind (enriched key-expr lk-entry)
              (induce-sort-by-topology p-frame :h-model hm :library *knowledge-library* :ledger led)
            (check key-expr)
            (check lk-entry)
            (check (eq :locality-key (knowledge-entry-kind lk-entry)))
            (check (equal key-expr (knowledge-entry-expression lk-entry)))
            (check (member :persistence (frame-edges enriched) :key #'first))
            (check (member :distinct (frame-edges enriched) :key #'first))
            ;; Sorted key values are monotonically non-decreasing along induced `:persistence` chain
            (let ((row-by-key (loop with h = (make-hash-table :test #'equal)
                                    for r in (frame-rows enriched) do (setf (gethash (row-key r) h) r)
                                    finally (return h)))
                  (prev-k nil))
              (dolist (e (frame-edges enriched))
                (when (eq :persistence (first e))
                  (let* ((ka (result key-expr inputs (row-known (gethash (second e) row-by-key))))
                         (kb (result key-expr inputs (row-known (gethash (third e) row-by-key)))))
                    (check (<= ka kb))
                    (when prev-k (check (= ka prev-k)))
                    (setf prev-k kb)))))
            ;; Idempotent re-registration & serialization roundtrip
            (let ((lk2 (register-knowledge-locality-key key-expr inputs :library *knowledge-library*)))
              (check (eq lk-entry lk2))
              (check (= 1 (length (knowledge-entries-of-kind :locality-key *knowledge-library*)))))
            (let* ((restored (deserialize-knowledge-library (serialize-knowledge-library *knowledge-library*)))
                   (restored-lk (first (knowledge-entries-of-kind :locality-key restored))))
              (check restored-lk)
              (check (equal key-expr (knowledge-entry-expression restored-lk))))
            (push key-expr induced-keys)
            (push (canonical-frame-edges enriched inputs) canonical-edge-sigs))))
      (check (member latent-k induced-keys :test #'equal))
      (check (= 1 (length (remove-duplicates induced-keys :test #'equal))))
      (check (= 1 (length (remove-duplicates canonical-edge-sigs :test #'equal)))))

    ;; 2. Negative control: uncompressible random-noise values induce ZERO edges and ZERO `:locality-key`
    (clear-knowledge-library)
    (let* ((inputs '((0 . :int) (1 . :int)))
           (noise-pts '((0 1 9000) (1 0 -7000) (0 2 15000) (2 0 -13000)
                        (0 3 21000) (3 0 -29000) (1 3 31000) (3 1 -41000)))
           (noise-rows (loop for (a b y) in noise-pts for idx from 0
                             collect (make-row :key idx :known (list a b)
                                               :requirement (singleton-requirement :int y))))
           (noise-frame (make-frame (make-schema :inputs inputs :target :int) noise-rows))
           (lang (make-language :int inputs :operators (list (op :+ :int)) :literals '(0 1)))
           (hm (condense-heuristic noise-frame lang :work-limit 10000)))
      (multiple-value-bind (enriched key-expr lk-entry)
          (induce-sort-by-topology noise-frame :h-model hm :library *knowledge-library*)
        (check (null key-expr))
        (check (null lk-entry))
        (check (null (frame-edges enriched)))
        (check (null (knowledge-entries-of-kind :locality-key *knowledge-library*)))))

    ;; 3. Non-`:int` target (`(:seq :int)` with `(:tuple :int :int)` input) falls back to 1-step `:int` accessor
    (clear-knowledge-library)
    (let* ((pair (tuple-type :int :int))
           (seq-int (sequence-type :int))
           (in-tup (list (cons 0 pair) (cons 1 :int)))
           (tup-pts '(((8 0) 99 (10000000 10000000))
                      ((3 0) 11 (100000 100000))
                      ((0 0) 44 (0 0))
                      ((6 0) 88 (10000000 10000000))
                      ((1 0) 77 (0 0))
                      ((4 0) 55 (100000 100000))
                      ((2 0) 33 (0 0))
                      ((7 0) 22 (10000000 10000000))
                      ((5 0) 66 (100000 100000))))
           (tup-rows (loop for (p j y) in tup-pts for idx from 0
                           collect (make-row :key idx :known (list p j)
                                             :requirement (singleton-requirement seq-int y))))
           (tup-frame (make-frame (make-schema :inputs in-tup :target seq-int) tup-rows)))
      (multiple-value-bind (enriched key-expr lk-entry)
          (induce-sort-by-topology tup-frame :library *knowledge-library*)
        (check key-expr)
        (check lk-entry)
        (check (equal (term `(at ,(var 0 pair) 0)) key-expr))
        (check (member :persistence (frame-edges enriched) :key #'first))))))

(deftest plan8-p3-availability-preorder-and-symbolic-unwinding
  "Verify ID-keyed availability preorder `\\tau` (numeric & non-numeric partial order) enforces
causal access in exact search, Stage A, `proposals`, and `observation-scope`, preserves
alpha-renaming invariance, projects in `conserved-quantity-frame :target-id :auto`, and
derives closed-form inverses via `solve-equality-symbolically` with target-sensitivity check."
  (with-clean-kernel-state
    ;; 1. General partial order `:le`: `:past < :present`, `:future` and `:incomparable` blocked for `:present`
    (let* ((inputs '((0 . :int) (1 . :int) (2 . :int) (3 . :int)))
           (avail '(:target :present
                    :le ((:past . :present))
                    :ranks ((0 . :past) (1 . :present) (2 . :future) (3 . :incomparable))))
           (schema (make-schema :inputs inputs :target :int :availability avail))
           ;; Shorter expressions `X1`, `X2`, `X3` match the rows (`(+ X0 1)` also matches but is larger!).
           ;; Availability MUST block `X1`, `X2`, `X3` and force exact/Stage-A search to pick `(+ X0 1)`.
           (rows (loop for x0 from 0 to 3
                       collect (make-row :key x0
                                         :known (list x0 (1+ x0) (1+ x0) (1+ x0))
                                         :requirement (singleton-requirement :int (1+ x0)))))
           (frame (make-frame schema rows))
           (lang (make-language :int inputs :operators (list (op :+ :int)) :literals '(1))))
      (check (equal '((0 . :int)) (schema-available-inputs schema)))
      (check (expression-respects-availability-p (var 0 :int) schema))
      (check (not (expression-respects-availability-p (var 1 :int) schema)))
      (check (not (expression-respects-availability-p (var 2 :int) schema)))
      (check (not (expression-respects-availability-p (var 3 :int) schema)))
      (check (eq 2 (schema-maximal-availability-id
                    (make-schema :inputs '((0 . :int) (1 . :int) (2 . :int))
                                 :target :int
                                 :availability '((0 . 0) (1 . 5) (2 . 10))))))

      ;; Exact search with unit-step resumption cannot return blocked `X1`/`X2`/`X3`
      (let ((job (check-search-resumption
                  (lambda () (start-search frame lang))
                  (header-bound inputs :int 16) :budget 20000 :exhaustive-p nil)))
        (check (search-job-best job))
        (let ((expr (candidate-expression (search-job-best job))))
          (check (expression-respects-availability-p expr schema))
          (check (equal '(0) (free-vars expr)))))

      ;; Stage A `start-heuristic-search` also respects availability preorder
      (let ((hs (start-heuristic-search frame lang
                                        :description-limit (header-bound inputs :int 16))))
        (resume-heuristic-search hs 20000)
        (check (heuristic-search-best hs))
        (let ((hprog (heuristic-program (heuristic-search-best hs))))
          (check (expression-respects-availability-p hprog schema))
          (check (equal '(0) (free-vars hprog)))))

      ;; Proposals respect availability while unrestricted observation scope sees all inputs for invariant discovery
      (let ((deps (dependency-proposals frame lang 40 :include-empty-p nil)))
        (check (= 1 (length deps)))
        (check (expression-respects-availability-p (cdar (decomposition-bindings (first deps))) schema)))
      (let* ((obs-unrestricted (start-observation-search (make-observation-scope frame lang)))
             (obs-restricted (start-observation-search (make-observation-scope frame lang :respect-availability-p t))))
        (resume-observation-search obs-unrestricted (header-bound inputs :int 6) 10000)
        (resume-observation-search obs-restricted (header-bound inputs :int 6) 10000)
        ;; `X1` is observed only in unrestricted scope, not in restricted scope
        (check (find-observation obs-unrestricted (var 1 :int)))
        (check (null (find-observation obs-restricted (var 1 :int))))))

    ;; 2. Symbolic inverse unwinding for `reverse` index conservation: `I + j - (n - 1) = 0 => I = (n - 1) - j`
    (let* ((inputs '((0 . :int) (1 . :int) (2 . :int))) ; 0: j, 1: n, 2: I
           (avail '(:target 10 :ranks ((0 . 1) (1 . 1) (2 . 10))))
           (j (var 0 :int))
           (n (var 1 :int))
           (big-i (var 2 :int))
           (conserved (term `(- (+ ,big-i ,j) (- ,n 1))))
           (bad-zero (term `(- ,big-i ,big-i)))
           (bad-zero2 (term `(* 0 ,big-i)))
           (obs-rows (loop for (jv nv iv) in '((0 4 3) (1 4 2) (2 5 2) (3 5 1) (0 1 0))
                           for k from 0
                           collect (make-row :key k :known (list jv nv iv) :requirement (lit :bool t))))
           (obs-frame (make-frame (make-schema :inputs inputs :target :bool :availability avail) obs-rows))
           (plib (kernel-propagator-library :int :operators '(:+ :-) :positions '(0 1))))
      ;; Sensitivity filter rejects trivial algebraic zeros and accepts true dependence on column `2`
      (check (not (conserved-expression-sensitive-p bad-zero 2 obs-frame)))
      (check (not (conserved-expression-sensitive-p bad-zero2 2 obs-frame)))
      (check (conserved-expression-sensitive-p conserved 2 obs-frame))

      ;; `conserved-quantity-frame :target-id :auto :symbolic-p t :check-sensitivity-p t` picks `2` and unwinds `(- (- n 1) j)`
      (multiple-value-bind (pulled const-frame solved target-id)
          (conserved-quantity-frame obs-frame :auto conserved 0 nil
                                    :symbolic-p t :library plib
                                    :allow-tentative-p t :check-sensitivity-p t)
        (check (= 2 target-id))
        (check pulled)
        (check const-frame)
        (check solved)
        (check (expression-respects-availability-p solved (frame-schema pulled)))
        (check (every (lambda (id) (member id '(0 1))) (free-vars solved)))
        (dolist (pair '((0 5 4) (2 5 2) (4 5 0) (1 10 8)))
          (check (= (third pair) (result solved '((0 . :int) (1 . :int)) (list (first pair) (second pair)))))))

      ;; Negative control: sensitive check on cancelled expression returns NIL cleanly
      (check (null (conserved-quantity-frame obs-frame :auto bad-zero 0 nil
                                             :symbolic-p t :library plib :check-sensitivity-p t)))

      ;; Negative control: tentative `:int` multiplication solver refuses unverified / zero-divisor unwinding!
      (let* ((plib-mul (kernel-propagator-library :int :operators '(:+ :- :* :/) :positions '(0 1)))
             (zero-samples '((0 0) (2 6)))
             (nz-samples '((2 6) (3 9))))
        (check (null (solve-equality-symbolically (term `(= (* ,(var 0 :int) ,(var 1 :int)) '6))
                                                  1 :int plib-mul :inputs '((0 . :int) (1 . :int))
                                                  :sample-knowns zero-samples :allow-tentative-p t)))
        ;; Without `allow-tentative-p`, tentative `:int` solver does NOT claim a certified unwinding
        (check (null (solve-equality-symbolically (term `(= (* ,(var 0 :int) ,(var 1 :int)) '6))
                                                  1 :int plib-mul :inputs '((0 . :int) (1 . :int))
                                                  :sample-knowns nz-samples :allow-tentative-p nil)))
        ;; With certified finite-field `GF(5)` solver and nonzero samples, DOES return `certified-p = t`!
        (let* ((gf5 (gf 5))
               (gf-plib (kernel-propagator-library gf5 :operators '(:+ :- :*) :positions '(0 1)))
               (gf-in (list (cons 0 gf5) (cons 1 gf5))))
          (multiple-value-bind (gf-sol cert-p)
              (solve-equality-symbolically (term `(= (* ,(var 0 gf5) ,(var 1 gf5)) ,(lit gf5 1)))
                                           1 gf5 gf-plib :inputs gf-in
                                           :sample-knowns '((2 3) (4 4)) :allow-tentative-p nil)
            (check gf-sol)
            (check cert-p)
            (check (= 2 (result gf-sol (list (cons 0 gf5)) '(3))))
            (check (= 4 (result gf-sol (list (cons 0 gf5)) '(4))))))))

    ;; 3. Alpha-renaming invariance of schema availability preorder (`0,1,2 -> 10,20,30`)
    (let* ((s1 (make-schema :inputs '((0 . :int) (1 . :int) (2 . :int)) :target :int
                            :availability '(:target 5 :ranks ((0 . 1) (1 . 5) (2 . 9)))))
           (s2 (make-schema :inputs '((10 . :int) (20 . :int) (30 . :int)) :target :int
                            :availability '(:target 5 :ranks ((10 . 1) (20 . 5) (30 . 9))))))
      (check (equal (canonicalize-schema-availability s1)
                    (canonicalize-schema-availability s2)))
      (check (eql 2 (schema-maximal-availability-id s1)))
      (check (eql 30 (schema-maximal-availability-id s2))))))

;;; ---------------------------------------------------------------------------
;;; Phase P8.4: Monoid Fold Theories, Cross-Prime Solver AU, & Cold Archival
;;; ---------------------------------------------------------------------------

(defun install-p8-fold-monoid-fixtures (&key (include-foldl t) (include-append t))
  "Install `:foldr`, optional `:foldl`, optional `:append`, plus `:sum-r` and `:prod-r` in active library."
  (let* ((seq-int (sequence-type :int))
         (step-t (code-type '((0 . :int) (1 . :int)) :int))
         (xs (var 0 seq-int))
         (acc (var 1 :int))
         (fn (var 2 step-t))
         (hd (term `(at ,xs 0)))
         (tl (term `(tail ,xs))))
    (define-function :foldr (list (cons 0 seq-int) (cons 1 :int) (cons 2 step-t)) :int
      (lambda (self)
        (app (op :if :int) (app (op := seq-int) xs (lit seq-int '()))
             acc
             (app (op :code-eval step-t) fn hd (app self tl acc fn)))))
    (when include-foldl
      (define-function :foldl (list (cons 0 seq-int) (cons 1 :int) (cons 2 step-t)) :int
        (lambda (self)
          (app (op :if :int) (app (op := seq-int) xs (lit seq-int '()))
               acc
               (app self tl (app (op :code-eval step-t) fn acc hd) fn)))))
    (when include-append
      (let ((ys (var 1 seq-int)))
        (define-function :append (list (cons 0 seq-int) (cons 1 seq-int)) seq-int
          (lambda (self)
            (app (op :if seq-int) (app (op := seq-int) xs (lit seq-int '()))
                 ys
                 (app (op :cons :int) hd (app self tl ys)))))))
    (define-function :sum-r (list (cons 0 seq-int)) :int
      (app (op :foldr) xs (lit :int 0)
           (lit step-t (app (op :+ :int) (var 0 :int) (var 1 :int)))))
    (define-function :prod-r (list (cons 0 seq-int)) :int
      (app (op :foldr) xs (lit :int 1)
           (lit step-t (app (op :* :int) (var 0 :int) (var 1 :int)))))))

(defun register-certified-int-law (id inputs lhs rhs)
  "Register an unconditional `:int` law with trusted `:equivalence` certificate."
  (let ((entry (register-knowledge-law (make-law :int inputs lhs rhs)
                                       :id id :status :validated)))
    (attest-knowledge-entry entry :trusted-axiom '(:equivalence))
    (invalidate-knowledge-caches *knowledge-library*)
    entry))

(deftest plan8-p4-monoid-fold-theories
  "Verify Monoid / Fold-Homomorphism `:functor` star quotienting, `:foldr <-> :foldl` transfer
+ split homomorphism `:law` induction, checked rewriting equivalence, idempotence, and strict
negative controls (missing associativity, uncertified/refuted laws, one-sided identities)."
  ;; 1. Positive control: full monoids for `+` (id 0) and `*` (id 1) + non-commutative associative test
  (with-clean-kernel-state
    (install-p8-fold-monoid-fixtures)
    (let* ((a (var 0 :int)) (b (var 1 :int)) (c (var 2 :int))
           (in2 '((0 . :int) (1 . :int)))
           (in3 '((0 . :int) (1 . :int) (2 . :int)))
           (in1 '((0 . :int)))
           (seq-int (sequence-type :int)))
      (declare (ignore in2))
      (register-certified-int-law :assoc-add in3
                                  (app (op :+ :int) (app (op :+ :int) a b) c)
                                  (app (op :+ :int) a (app (op :+ :int) b c)))
      (register-certified-int-law :lid-add in1 (app (op :+ :int) (lit :int 0) a) a)
      (register-certified-int-law :rid-add in1 (app (op :+ :int) a (lit :int 0)) a)
      (register-certified-int-law :assoc-mul in3
                                  (app (op :* :int) (app (op :* :int) a b) c)
                                  (app (op :* :int) a (app (op :* :int) b c)))
      (register-certified-int-law :lid-mul in1 (app (op :* :int) (lit :int 1) a) a)
      (register-certified-int-law :rid-mul in1 (app (op :* :int) a (lit :int 1)) a)
      (consolidate-knowledge-library *knowledge-library*
                                     :law-validations (list (resume-law-validation
                                                             (start-law-validation
                                                              (make-law (gf 5)
                                                                        (list (cons 0 (gf 5)))
                                                                        (app (op :+ (gf 5)) (var 0 (gf 5)) (lit (gf 5) 0))
                                                                        (var 0 (gf 5))))
                                                             10000)))
      (let* ((functor (find-knowledge-entry :MONOID-FOLD/FUNCTOR))
             (derived-laws (remove-if-not
                            (lambda (e)
                              (eq :monoid-fold (getf (knowledge-entry-metadata e) :theory)))
                            (active-knowledge-entries-of-kind :law)))
             (transfer-laws (remove-if-not
                             (lambda (e) (eql 0 (search "MONOID-TRANSFER/" (symbol-name (knowledge-entry-id e)))))
                             derived-laws))
             (split-laws (remove-if-not
                          (lambda (e) (eql 0 (search "MONOID-SPLIT/" (symbol-name (knowledge-entry-id e)))))
                          derived-laws)))
        (check functor)
        (check (eq :functor (knowledge-entry-kind functor)))
        (check (member :sum-r (cdr (assoc :abstracts (knowledge-entry-edges functor)))))
        (check (member :prod-r (cdr (assoc :abstracts (knowledge-entry-edges functor)))))
        (check (>= (length transfer-laws) 2))
        (check (>= (length split-laws) 2))
        (dolist (dl derived-laws)
          (check (knowledge-evidence-current-p dl :equivalence)))
        ;; Checked rewriting preserves semantic equality on split and transfer terms
        (let* ((rlib (as-rewrite-library *knowledge-library* :domain :int))
               (xs (var 0 seq-int)) (ys (var 1 seq-int))
               (split-lhs (app (op :sum-r) (app (op :append) xs ys)))
               (split-rhs (app (op :+ :int) (app (op :sum-r) xs) (app (op :sum-r) ys)))
               (st-lhs (start-rewriting split-lhs (list (cons 0 seq-int) (cons 1 seq-int)) rlib))
               (st-rhs (start-rewriting split-rhs (list (cons 0 seq-int) (cons 1 seq-int)) rlib)))
          (advance-rewriting st-lhs 100000)
          (advance-rewriting st-rhs 100000)
          (check (eq :complete (rewriting-status st-lhs)))
          (check (eq :complete (rewriting-status st-rhs)))
          (check (equal (rewriting-value st-lhs) (rewriting-value st-rhs)))
          (dolist (pair '((() ()) ((1 2) (3 4 5)) ((-4) (10 -2))))
            (check (= (result (rewriting-value st-lhs) (list (cons 0 seq-int) (cons 1 seq-int)) pair)
                      (reduce #'+ (append (first pair) (second pair))))))))
      ;; Zero-workload idempotence creates zero extra monoid laws or functors
      (let ((law-count (length (knowledge-entries-of-kind :law)))
            (fn-count (length (knowledge-entries-of-kind :functor))))
        (consolidate-knowledge-library *knowledge-library*)
        (check (null (induce-monoid-fold-theories *knowledge-library*)))
        (check (= law-count (length (knowledge-entries-of-kind :law))))
        (check (= fn-count (length (knowledge-entries-of-kind :functor)))))))

  ;; 2. Negative control A & B: missing associativity / conjecture associativity / refuted law
  (with-clean-kernel-state
    (install-p8-fold-monoid-fixtures)
    (let ((a (var 0 :int)) (b (var 1 :int)) (c (var 2 :int)))
      ;; Identity laws certified, but associativity is only a `:conjecture`!
      (register-certified-int-law :lid-add '((0 . :int)) (app (op :+ :int) (lit :int 0) a) a)
      (register-certified-int-law :rid-add '((0 . :int)) (app (op :+ :int) a (lit :int 0)) a)
      (register-knowledge-law
       (make-law :int '((0 . :int) (1 . :int) (2 . :int))
                 (app (op :+ :int) (app (op :+ :int) a b) c)
                 (app (op :+ :int) a (app (op :+ :int) b c)))
       :id :unvalidated-assoc :status :conjecture)
      (check (null (induce-monoid-fold-theories *knowledge-library*)))
      (check (null (find-knowledge-entry :MONOID-FOLD/FUNCTOR)))))

  ;; 3. Negative control C: one-sided identity (right identity only, NO commutativity law)
  (with-clean-kernel-state
    (install-p8-fold-monoid-fixtures)
    (let ((a (var 0 :int)) (b (var 1 :int)) (c (var 2 :int)))
      (register-certified-int-law :assoc-add '((0 . :int) (1 . :int) (2 . :int))
                                  (app (op :+ :int) (app (op :+ :int) a b) c)
                                  (app (op :+ :int) a (app (op :+ :int) b c)))
      (register-certified-int-law :rid-only '((0 . :int)) (app (op :+ :int) a (lit :int 0)) a)
      (check (null (induce-monoid-fold-theories *knowledge-library*)))
      ;; Asymmetric non-monoid operator `:-` with right identity `(- a 0) = a` also rejected
      (define-function :sub-fold (list (cons 0 (sequence-type :int))) :int
        (app (op :foldr) (var 0 (sequence-type :int)) (lit :int 0)
             (lit (code-type '((0 . :int) (1 . :int)) :int)
                  (app (op :- :int) (var 0 :int) (var 1 :int)))))
      (register-certified-int-law :sub-rid '((0 . :int)) (app (op :- :int) a (lit :int 0)) a)
      (check (null (induce-monoid-fold-theories *knowledge-library*)))
      ;; Adding certified commutativity for `:+` licenses the missing side and induces `:sum-r` ONLY!
      (register-certified-int-law :comm-add '((0 . :int) (1 . :int))
                                  (app (op :+ :int) a b) (app (op :+ :int) b a))
      (let ((induced (induce-monoid-fold-theories *knowledge-library*)))
        (check induced)
        (let ((functor (find-knowledge-entry :MONOID-FOLD/FUNCTOR)))
          (check functor)
          (check (member :sum-r (cdr (assoc :abstracts (knowledge-entry-edges functor)))))
          (check (not (member :sub-fold (cdr (assoc :abstracts (knowledge-entry-edges functor)))))))))))

(deftest plan8-p4-cross-prime-solver-au
  "Verify cross-prime `(:gf p)` solver AU lifts shared polynomial witnesses (`:+`) into
parametric `:int` `:solver` conjectures integrated with `propagate-requirements`, while rejecting
modular-only witnesses (`:*` integer truncating division) and single-prime inputs."
  ;; 1. Negative control: single prime GF(5) alone produces zero cross-prime lifted solvers
  (with-clean-kernel-state
    (register-kernel-arithmetic-solver (gf 5) :+ 0)
    (register-kernel-arithmetic-solver (gf 5) :* 0)
    (check (null (induce-cross-prime-solvers *knowledge-library*))))

  ;; 2. Positive (`:+`) + Negative (`:*`) across GF(5) and GF(7) through `consolidate-knowledge-library`
  (with-clean-kernel-state
    (let* ((gf5 (gf 5))
           (gf7 (gf 7))
           (s5+ (register-kernel-arithmetic-solver gf5 :+ 0))
           (s7+ (register-kernel-arithmetic-solver gf7 :+ 0)))
      (register-kernel-arithmetic-solver gf5 :* 0)
      (register-kernel-arithmetic-solver gf7 :* 0)
      (consolidate-knowledge-library *knowledge-library*
                                     :law-validations (list (resume-law-validation
                                                             (start-law-validation
                                                              (make-law gf5 (list (cons 0 gf5))
                                                                        (app (op :+ gf5) (var 0 gf5) (lit gf5 0))
                                                                        (var 0 gf5)))
                                                             10000)))
      ;; `:+` solver lifts cleanly to `:int` `:conjecture` with `:retyped-from` edges!
      (let ((lifted-add (find-knowledge-entry :CROSS-PRIME/+-0))
            (rejected-mul (find-knowledge-entry :CROSS-PRIME/*-0)))
        (check lifted-add)
        (check (null rejected-mul))
        (check (eq :solver (knowledge-entry-kind lifted-add)))
        (check (eq :int (knowledge-entry-domain lifted-add)))
        (check (eq :conjecture (knowledge-entry-status lifted-add)))
        (check (null (getf (knowledge-entry-metadata lifted-add) :certified-p)))
        (check (member (knowledge-entry-id s5+)
                       (cdr (assoc :retyped-from (knowledge-entry-edges lifted-add)))))
        (check (member (knowledge-entry-id s7+)
                       (cdr (assoc :retyped-from (knowledge-entry-edges lifted-add)))))
        (check (equal '(5 7) (getf (knowledge-entry-metadata lifted-add) :source-primes)))
        ;; Lifted `:int` solver narrows `(= (+ Z 5) 12)` via `propagate-requirements`!
        (let* ((frame (make-frame (make-schema :domain :int :inputs '((0 . :int)) :target :int)
                                  (list (make-row :key 0 :known '(5)
                                                  :requirement (app (op := :int)
                                                                    (app (op :+ :int) (var 0 :int) (lit :int 5))
                                                                    (lit :int 12))))))
               (prop (propagate-requirements frame *knowledge-library* (make-ledger))))
          (check (= 1 (propagation-suggested prop)))
          (check (plusp (propagation-ambiguous prop)))
          (check (equal (list 7)
                        (extract-allowed-values (row-requirement (first (frame-rows (propagation-frame prop)))))))))
      ;; Idempotency: second consolidation creates zero duplicate `:solver` entries
      (let ((solver-count (length (knowledge-entries-of-kind :solver))))
        (check (null (induce-cross-prime-solvers *knowledge-library*)))
        (consolidate-knowledge-library *knowledge-library*)
        (check (= solver-count (length (knowledge-entries-of-kind :solver))))))))

(deftest plan8-p4-net-utility-cold-archive-and-idempotence
  "Verify workload-gated epoch advancement, NetUtility usage accounting, cold-archive demotion
to `:active-p nil` after grace epochs, live `:depends-on`/AST caller protection + cascade, active-only
filtering vs preserved archival inspection, serialization round-trip, and strict zero-workload
fixed-point idempotence."
  (with-clean-kernel-state
    (let* ((seq-int (sequence-type :int))
           (xs (var 0 seq-int))
           (x0 (var 0 :int)))
      ;; 1. Seed useful entry, helper-with-live-caller, and decoy entries across kinds at epoch 0
      (define-function :live-helper '((0 . :int)) :int (app (op :+ :int) x0 (lit :int 2)))
      (define-function :caller-fn '((0 . :int)) :int (app (op :live-helper) x0))
      (add-knowledge-edge :caller-fn :depends-on :live-helper)
      (define-function :decoy-seq-fn (list (cons 0 seq-int)) seq-int
        (lambda (self)
          (app (op :if seq-int) (app (op := seq-int) xs (lit seq-int '()))
               (lit seq-int '())
               (app (op :cons :int) (app (op :* :int) (app (op :at seq-int) xs (lit :int 0)) (lit :int 9))
                    (app self (app (op :tail :int) xs))))))
      (define-function :decoy-comb (list (cons 0 seq-int) (cons 1 (code-type '((0 . :int)) :int))) seq-int
        (lambda (self) (declare (ignore self)) xs))
      (register-kernel-arithmetic-solver (gf 5) :+ 0)
      (register-knowledge-solver :+ :id :decoy-int-solver :domain :int :position 1
                                 :witness (app (op :- :int) (var 1 :int) (var 0 :int))
                                 :status :conjecture)
      (register-knowledge-solver :- :id :useful-sub-solver :domain :int :position 0
                                 :witness (app (op :+ :int) (var 1 :int) (var 0 :int))
                                 :status :conjecture)
      (register-knowledge-dip-feature (app (op :< :int) (lit :int 0) x0)
                                      :id :decoy-dip :domain :int :inputs '((0 . :int)) :target :bool)
      ;; Give `:caller-fn` initial positive saved bits + a decoy manual descriptor
      (register-knowledge-entry
       (make-knowledge-entry :id :decoy-descriptor :kind :descriptor :domain :int
                             :inputs '((0 . :int)) :target :bool :expression (lit :bool t)
                             :metadata (list :compositional-name :FUNCTION/DECOY-ADDR))
       :library *knowledge-library*)
      (setf (knowledge-entry-compositional-name (find-knowledge-entry :decoy-descriptor))
            :FUNCTION/DECOY-ADDR)
      (index-knowledge-entry-compositional-address (find-knowledge-entry :decoy-descriptor) *knowledge-library*)

      ;; Zero-workload consolidation MUST NOT advance epoch or demote anything
      (let ((rep0 (consolidate-knowledge-library *knowledge-library*)))
        (check (= 0 (getf rep0 :before-epoch)))
        (check (= 0 (getf rep0 :after-epoch)))
        (check (null (getf rep0 :demoted)))
        (check (active-knowledge-entry-p (find-knowledge-entry :decoy-seq-fn))))

      ;; 2. Epoch 1: run one real synthesis job + credit `:caller-fn` & `:useful-sub-solver` -> no demotions yet (`age 1 < 3`)
      (let* ((f1 (simple-frame :int '((0 . :int)) '(((1) 2) ((4) 5))))
             (l1 (make-language :int '((0 . :int)) :operators (list (op :+ :int)) :literals '(1)))
             (j1 (start-heuristic-synthesis f1 l1 40)))
        (resume-synthesis j1 20000 :stop-on-first t)
        (check (synthesis-job-best j1))
        (let ((rep1 (consolidate-knowledge-library
                     *knowledge-library*
                     :synthesis-jobs (list j1)
                     :usage-events '((:id :caller-fn :saved-bits 50 :dispatch-work 100 :used-p t)
                                     (:id :useful-sub-solver :saved-bits 20 :used-p t)
                                     (:id :decoy-int-solver :failed-lift-work 500)))))
          (check (= 0 (getf rep1 :before-epoch)))
          (check (= 1 (getf rep1 :after-epoch)))
          (check (= 1 (knowledge-library-epoch *knowledge-library*)))
          (check (null (getf rep1 :demoted)))
          (check (plusp (knowledge-entry-net-utility (find-knowledge-entry :caller-fn))))
          (check (minusp (knowledge-entry-net-utility (find-knowledge-entry :decoy-int-solver))))))

      ;; 3. Epochs 2 and 3: age decoys to 3 while keeping `:caller-fn` & `:useful-sub-solver` fresh;
      ;;    `:live-helper` is NEVER used directly (utility = 0) yet MUST survive because `:caller-fn` calls/depends on it!
      (dolist (step '(2 3))
        (consolidate-knowledge-library
         *knowledge-library*
         :usage-events `((:id :caller-fn :saved-bits 10 :dispatch-work 100 :used-p t)
                         (:id :useful-sub-solver :used-p t)
                         (:id :decoy-seq-fn :failed-lift-work 400))))
      (check (= 3 (knowledge-library-epoch *knowledge-library*)))
      ;; Active survivors vs cold-archived decoys
      (check (active-knowledge-entry-p (find-knowledge-entry :caller-fn)))
      (check (active-knowledge-entry-p (find-knowledge-entry :live-helper)))
      (check (active-knowledge-entry-p (find-knowledge-entry :useful-sub-solver)))
      (dolist (dead-id '(:decoy-seq-fn :decoy-comb :decoy-int-solver :decoy-dip :decoy-descriptor))
        (let ((e (find-knowledge-entry dead-id)))
          (check e)
          (check (not (knowledge-entry-active-p e)))
          (check (not (active-knowledge-entry-p e)))))
      ;; Auto-descriptor of `:decoy-seq-fn` cascaded to inactive too
      (dolist (edge (knowledge-edges-to :decoy-seq-fn :describes))
        (let ((d (find-knowledge-entry (second edge))))
          (when (and d (getf (knowledge-entry-metadata d) :auto-descriptor))
            (check (not (active-knowledge-entry-p d))))))

      ;; 4. Active consumer filtering vs intact archival inspection
      (check (not (member :decoy-seq-fn (active-knowledge-entries-of-kind :function) :key #'knowledge-entry-id)))
      (check (member :decoy-seq-fn (knowledge-entries-of-kind :function) :key #'knowledge-entry-id))
      (check (null (find-knowledge-entries-by-address :FUNCTION/DECOY-ADDR *knowledge-library*)))
      (check (find-knowledge-entries-by-address :FUNCTION/DECOY-ADDR *knowledge-library* t))
      (let* ((f-decoy (make-frame (make-schema :domain :int :inputs '((0 . :int)) :target :int)
                                  (list (make-row :key 0 :known '(10)
                                                  :requirement (app (op := :int)
                                                                    (app (op :+ :int) (var 0 :int) (lit :int 10))
                                                                    (lit :int 15))))))
             (f-live (make-frame (make-schema :domain :int :inputs '((0 . :int)) :target :int)
                                 (list (make-row :key 0 :known '(3)
                                                 :requirement (app (op := :int)
                                                                   (app (op :- :int) (var 0 :int) (lit :int 3))
                                                                   (lit :int 7))))))
             (prop-decoy (propagate-requirements f-decoy *knowledge-library* (make-ledger)))
             (prop-live (propagate-requirements f-live *knowledge-library* (make-ledger)))
             (lang-comb (make-language :int (list (cons 0 seq-int)) :operators nil :literals nil))
             (cdefs (candidate-library-definitions lang-comb))
             (explain (explain-knowledge-library)))
        ;; Decoy `:int` solver excluded from propagation, while live `:-` solver narrows!
        (check (zerop (propagation-suggested prop-decoy)))
        (check (= 1 (propagation-suggested prop-live)))
        (check (not (find :decoy-comb cdefs :key #'function-definition-name)))
        (check (= (length (knowledge-library-entries *knowledge-library*))
                  (getf explain :total-entries)))
        (check (< (getf explain :active-entries) (getf explain :total-entries)))
        (check (= 3 (getf explain :epoch))))

      ;; 5. Persistence round-trip preserves `:epoch`, `:active-p nil`, `:last-used-epoch`, and strict
      ;;    zero-workload fixed-point idempotence!
      (let* ((snap1 (serialize-knowledge-library *knowledge-library*))
             (restored1 (deserialize-knowledge-library snap1))
             (total1 (length (knowledge-library-entries restored1)))
             (active1 (length (remove-if-not #'active-knowledge-entry-p
                                             (knowledge-library-entries restored1)))))
        (check (= 3 (knowledge-library-epoch restored1)))
        (check (not (active-knowledge-entry-p (find-knowledge-entry :decoy-seq-fn restored1))))
        (check (active-knowledge-entry-p (find-knowledge-entry :live-helper restored1)))
        (let ((rep-noop (consolidate-knowledge-library restored1)))
          (check (= 3 (getf rep-noop :before-epoch)))
          (check (= 3 (getf rep-noop :after-epoch)))
          (check (null (getf rep-noop :demoted)))
          (let* ((snap2 (serialize-knowledge-library restored1))
                 (restored2 (deserialize-knowledge-library snap2)))
            (check (= total1 (length (knowledge-library-entries restored2))))
            (check (= active1 (length (remove-if-not #'active-knowledge-entry-p
                                                     (knowledge-library-entries restored2))))))))

      ;; 6. Cascade: once `:caller-fn` itself loses all utility & ages out, `:live-helper` demotes too!
      (consolidate-knowledge-library
       *knowledge-library*
       :usage-events '((:id :caller-fn :failed-lift-work 10000))) ; net-utility becomes < 0, still epoch 4 - 3 = 1 < 3
      (check (active-knowledge-entry-p (find-knowledge-entry :caller-fn)))
      (dotimes (i 3)
        (consolidate-knowledge-library *knowledge-library* :usage-events '((:id :nonexistent))))
      (check (not (active-knowledge-entry-p (find-knowledge-entry :caller-fn))))
      (check (not (active-knowledge-entry-p (find-knowledge-entry :live-helper)))))))
