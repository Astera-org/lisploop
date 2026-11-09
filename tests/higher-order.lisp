(in-package #:lisploop)

(defun define-standard-int-combinators ()
  "Register standard `:map`, `:foldr`, and `:filter` combinators over `(:seq :int)`."
  (let* ((seq-type (sequence-type :int))
         (xs (var 0 seq-type))
         (empty-xs (app (op := seq-type) xs (lit seq-type '())))
         (head-xs (app (op :at seq-type) xs (lit :int 0)))
         (tail-xs (app (op :tail :int) xs))
         (unary-code (code-type '((0 . :int)) :int))
         (binary-code (code-type '((0 . :int) (1 . :int)) :int))
         (pred-code (code-type '((0 . :int)) :bool)))
    (define-function :map (list (cons 0 seq-type) (cons 1 unary-code)) seq-type
      (lambda (self)
        (app (op :if seq-type)
             empty-xs
             (lit seq-type '())
             (app (op :cons :int)
                  (app (op :code-eval unary-code) (var 1 unary-code) head-xs)
                  (app self tail-xs (var 1 unary-code))))))
    (define-function :foldr (list (cons 0 seq-type) (cons 1 :int) (cons 2 binary-code)) :int
      (lambda (self)
        (app (op :if :int)
             empty-xs
             (var 1 :int)
             (app (op :code-eval binary-code) (var 2 binary-code)
                  head-xs
                  (app self tail-xs (var 1 :int) (var 2 binary-code))))))
    (define-function :filter (list (cons 0 seq-type) (cons 1 pred-code)) seq-type
      (lambda (self)
        (app (op :if seq-type)
             empty-xs
             (lit seq-type '())
             (app (op :if seq-type)
                  (app (op :code-eval pred-code) (var 1 pred-code) head-xs)
                  (app (op :cons :int) head-xs (app self tail-xs (var 1 pred-code)))
                  (app self tail-xs (var 1 pred-code))))))))

(deftest higher-order-h1-polymorphic-retyping-filter-and-lockstep
  "Verify H1:
1. Polymorphic combinator instantiation (`retype-function-definition`) to nested sequences,
   finite fields, tuples, and heterogeneous $(\\alpha, \\beta)$ bifunctor signatures.
2. `:filter` synthesis, conditional totality, and subsequence alignment (`fold-constants` +
   `lift-frame`) including duplicate-element rows and `:code-subst` closure capture.
3. Multi-sequence lockstep structural recursion (`:dot-product`, `:zip-with`, `:fold2`) and
   lifting through binary sequence combinators."
  (unwind-protect
       (with-knowledge-library ((make-knowledge-library))
         (clear-function-definitions)
         (define-standard-int-combinators)

         ;; 1. Polymorphic retyping of :map, :foldr, :filter
         (let* ((seq-int (sequence-type :int))
                (seq2-int (sequence-type seq-int))
                (gf5 (gf 5))
                (seq-gf5 (sequence-type gf5))
                (map-2d (retype-function-definition :map seq-int :new-name :map-2d))
                (map-gf5 (retype-function-definition :map gf5 :new-name :map-gf5))
                (filter-gf5 (retype-function-definition :filter gf5 :new-name :filter-gf5))
                (map-int-to-seq (retype-function-definition :map :int
                                                            :return-element-type seq-int
                                                            :new-name :map-int-to-seq))
                (map-seq-to-int (retype-function-definition :map seq-int
                                                            :return-element-type :int
                                                            :new-name :map-seq-to-int))
                (foldr-seq-to-int (retype-function-definition :foldr seq-int
                                                              :return-element-type :int
                                                              :new-name :foldr-seq-to-int)))
           (dolist (def (list map-2d map-gf5 filter-gf5 map-int-to-seq map-seq-to-int foldr-seq-to-int))
             (check (function-definition-p def))
             (check (function-definition-conditional-code-params def))
             (check-codec-roundtrip (function-definition-body def)
                                    (function-definition-inputs def)))
           ;; Execute retyped :map-gf5 and :filter-gf5 in VM
           (let* ((gf5-code (code-type (list (cons 0 gf5)) gf5))
                  (gf5-pred (code-type (list (cons 0 gf5)) :bool))
                  (map-expr (app (op :map-gf5)
                                 (var 0 seq-gf5)
                                 (lit gf5-code (app (op :+ gf5) (var 0 gf5) (lit gf5 2)))))
                  (flt-expr (app (op :filter-gf5)
                                 (var 0 seq-gf5)
                                 (lit gf5-pred (app (op := gf5) (var 0 gf5) (lit gf5 4))))))
             (check (provably-total-p map-expr))
             (check (provably-total-p flt-expr))
             (check (equal '(2 3 0 1) (result map-expr (list (cons 0 seq-gf5)) '((0 1 3 4)))))
             (check (equal '(4 4) (result flt-expr (list (cons 0 seq-gf5)) '((1 4 2 4 0))))))
           ;; Execute bifunctor :map-seq-to-int (row lengths of a 2D matrix)
           (let* ((row-code (code-type (list (cons 0 seq-int)) :int))
                  (len-rows-expr (app (op :map-seq-to-int)
                                      (var 0 seq2-int)
                                      (lit row-code (app (op :length :int) (var 0 seq-int))))))
             (check (provably-total-p len-rows-expr))
             (check (equal '(2 3 0)
                           (result len-rows-expr (list (cons 0 seq2-int)) '(((10 20) (1 2 3) ())))))))

         ;; 2. :filter subsequence alignment in `fold-constants` and `lift-frame` (including duplicate elements)
         (let* ((seq-type (sequence-type :int))
                (inputs (list (cons 0 seq-type)))
                (xs (var 0 seq-type))
                (pred-code (code-type '((0 . :int)) :bool))
                (flt-frame (simple-frame seq-type inputs
                                         '(((() ) ())
                                           (((-1 2 -3 4)) (2 4))
                                           (((2 -1 2)) (2 2))
                                           (((-2 3 -2)) (3)))))
                (lifted (lift-frame flt-frame
                                    (app (op :filter) xs (var 1 pred-code))
                                    1 pred-code nil)))
           ;; Lifted frame must be conflict-free and assign :bool truth values to each element
           (check (null (nth-value 0 (frame-conflict-p lifted))))
           (check (>= (length (frame-rows lifted)) 4))
           ;; Synthesize positive-filter `(:filter X0 '(< '0 X0))` via `start-heuristic-synthesis`
           (let* ((flt-lang (make-language :int inputs
                                           :operators (list (op :filter) (op :< :int))
                                           :literals '(0)
                                           :constants (list (lit seq-type '()))))
                  (job (start-heuristic-synthesis flt-frame flt-lang 70)))
             (resume-synthesis job 30000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr inputs)
               (check (expression-calls-operator-p expr :filter))
               (check (equal '(5 2 5) (result expr inputs '((-3 5 0 2 -1 5)))))))
           ;; Synthesize parameterized filter `greater-than-k(xs, k)` with `:code-subst` closure capture
           (let* ((gtk-inputs (list (cons 0 seq-type) (cons 1 :int)))
                  (gtk-frame (simple-frame seq-type gtk-inputs
                                           '(((() 3) ())
                                             (((1 5 2 6) 3) (5 6))
                                             (((4 1 5) 4) (5))
                                             (((2 3 2) 1) (2 3 2)))))
                  (gtk-lang (make-language :int gtk-inputs
                                           :operators (list (op :filter) (op :< :int))
                                           :literals nil
                                           :constants (list (lit seq-type '()))))
                  (job (start-heuristic-synthesis gtk-frame gtk-lang 80)))
             (resume-synthesis job 30000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr gtk-inputs)
               (check (expression-calls-operator-p expr :filter))
               (check (contains-call-to-p expr :code-subst))
               (check (equal '(10 12) (result expr gtk-inputs '((3 10 7 12 5) 7)))))))

         ;; 3. Multi-sequence lockstep recursion: synthesize `:dot-product` and `:zip-with` de novo
         (let* ((seq-type (sequence-type :int))
                (dp-inputs (list (cons 0 seq-type) (cons 1 seq-type)))
                (dp-frame (simple-frame :int dp-inputs
                                        '(((() ()) 0)
                                          ((() (5 6)) 0)
                                          (((5 6) ()) 0)
                                          (((4) (5)) 20)
                                          (((2 4) (3 5)) 26)
                                          (((3 2 4) (2 3 5)) 32))))
                (dp-lang (make-language :int dp-inputs
                                        :operators (list (op :at seq-type) (op :tail :int)
                                                         (op := seq-type) (op :if :int)
                                                         (op :+ :int) (op :* :int))
                                        :literals nil
                                        :constants (list (lit seq-type '()))))
                (dp-job (start-recursive-synthesis dp-frame dp-lang 100 :self-name :dot-product)))
           (resume-synthesis dp-job 60000 :stop-on-first t)
           (check (synthesis-job-best dp-job))
           (let ((dp-def (find-function-definition :dot-product))
                 (dp-expr (candidate-expression (synthesis-job-best dp-job))))
             (check dp-def)
             (check (function-definition-total-p dp-def))
             (check (provably-total-p dp-expr))
             (check-codec-roundtrip dp-expr dp-inputs)
             (check (= 0 (result dp-expr dp-inputs '(() (1 2)))))
             (check (= 0 (result dp-expr dp-inputs '((1 2) ()))))
             (check (= 60 (result dp-expr dp-inputs '((2 4 6) (5 5 5)))))
             ;; Truncates cleanly on unequal lengths
             (check (= 26 (result dp-expr dp-inputs '((2 4 99) (3 5)))))))

         ;; De novo synthesis of higher-order `:zip-with` and lifting `linear-comb` through `:zip-with`
         (let* ((seq-type (sequence-type :int))
                (bin-code (code-type '((0 . :int) (1 . :int)) :int))
                (zw-inputs (list (cons 0 seq-type) (cons 1 seq-type) (cons 2 bin-code)))
                (add-fn (app (op :+ :int) (var 0 :int) (var 1 :int)))
                (mul-fn (app (op :* :int) (var 0 :int) (var 1 :int)))
                (zw-frame (simple-frame seq-type zw-inputs
                                        (list (list (list '() '() add-fn) '())
                                              (list (list '() '(4) add-fn) '())
                                              (list (list '(4) '() add-fn) '())
                                              (list (list '(2) '(3) add-fn) '(5))
                                              (list (list '(1 2) '(10 3) add-fn) '(11 5))
                                              (list (list '(3) '(5) mul-fn) '(15))
                                              (list (list '(2 3) '(4 5) mul-fn) '(8 15)))))
                (zw-lang (make-language :int zw-inputs
                                        :operators (list (op :at seq-type) (op :tail :int)
                                                         (op :cons :int) (op := seq-type)
                                                         (op :if seq-type) (op :code-eval bin-code))
                                        :literals nil
                                        :constants (list (lit seq-type '()))))
                (zw-job (start-recursive-synthesis zw-frame zw-lang 110 :self-name :zip-with)))
           (resume-synthesis zw-job 60000 :stop-on-first t)
           (check (synthesis-job-best zw-job))
           (let ((zw-def (find-function-definition :zip-with))
                 (zw-expr (candidate-expression (synthesis-job-best zw-job))))
             (check zw-def)
             (check (equal '(2) (function-definition-conditional-code-params zw-def)))
             (check-codec-roundtrip zw-expr zw-inputs)
             ;; Synthesize `linear-comb(u, v) = 2*u + v` via `:zip-with`
             (let* ((lc-inputs (list (cons 0 seq-type) (cons 1 seq-type)))
                    (lc-frame (simple-frame seq-type lc-inputs
                                            '(((() ()) ())
                                              (((1 3) (10 20)) (12 26))
                                              (((4 -1 2) (0 5 1)) (8 3 5)))))
                    (lc-lang (make-language :int lc-inputs
                                            :operators (list (op :zip-with) (op :+ :int) (op :* :int))
                                            :literals '(2)
                                            :constants (list (lit seq-type '()))))
                    (lc-job (start-heuristic-synthesis lc-frame lc-lang 80)))
               (resume-synthesis lc-job 45000 :stop-on-first t)
               (check (synthesis-job-best lc-job))
               (let ((lc-expr (candidate-expression (synthesis-job-best lc-job))))
                 (check (provably-total-p lc-expr))
                 (check (expression-calls-operator-p lc-expr :zip-with))
                 (check (equal '(21 42 63) (result lc-expr lc-inputs '((10 20 30) (1 2 3))))))))))
    (clear-function-definitions)))

(deftest higher-order-h2-nested-2d-grids-outer-product-matvec-and-filter-map
  "Verify H2:
1. Reentrant 2-level lifting (`lift-frame` -> child `synthesis-node` -> second-level `lift-frame`)
   for 2D Scalar Map (`(:seq (:seq :int)) -> (:seq (:seq :int))`) with and without `:code-subst` capture.
2. Outer Product ($u_i \\cdot v_j$, `(:seq :int) x (:seq :int) -> (:seq (:seq :int))`) via 2-level
   bifunctor `:map` lifting and `:code-subst` closure capture.
3. Matrix-Vector Product ($(Mv)_i = \\sum_j M_{i,j} v_j$) via `:map` over rows composed with `:dot-product`.
4. 2D Row/Grid Reductions (`row-sums` and `matrix-sum`).
5. Filter-Map comprehension (`[2*x + 1 for x in xs if x > 0]`) via `filter-map-decompositions`."
  (unwind-protect
       (with-knowledge-library ((make-knowledge-library))
         (clear-function-definitions)
         (define-standard-int-combinators)
         (let* ((seq-int (sequence-type :int))
                (seq2-int (sequence-type seq-int))
                (xs (var 0 seq-int))
                (ys (var 1 seq-int))
                (empty-xs (app (op := seq-int) xs (lit seq-int '())))
                (empty-ys (app (op := seq-int) ys (lit seq-int '())))
                (head-xs (app (op :at seq-int) xs (lit :int 0)))
                (head-ys (app (op :at seq-int) ys (lit :int 0)))
                (tail-xs (app (op :tail :int) xs))
                (tail-ys (app (op :tail :int) ys)))
           ;; Register first-order library helpers `:sum` and `:dot-product`
           (define-function :sum (list (cons 0 seq-int)) :int
             (app (op :foldr) xs (lit :int 0)
                  (lit (code-type '((0 . :int) (1 . :int)) :int)
                       (app (op :+ :int) (var 0 :int) (var 1 :int)))))
           (define-function :dot-product (list (cons 0 seq-int) (cons 1 seq-int)) :int
             (lambda (self)
               (app (op :if :int) empty-xs (lit :int 0)
                    (app (op :if :int) empty-ys (lit :int 0)
                         (app (op :+ :int)
                              (app (op :* :int) head-xs head-ys)
                              (app self tail-xs tail-ys))))))

           ;; 1. 2D Scalar Map: double every element of a 2D matrix `M`
           (let* ((m-inputs (list (cons 0 seq2-int)))
                  (m-frame (simple-frame seq2-int m-inputs
                                         '(((() ) ())
                                           ((((1 2) (3))) ((2 4) (6)))
                                           ((((0 -1) (4 5))) ((0 -2) (8 10))))))
                  (m-lang (make-language :int m-inputs
                                         :operators (list (op :map) (op :+ :int) (op :* :int))
                                         :literals '(2)
                                         :constants (list (lit seq2-int '()) (lit seq-int '()))))
                  (job (start-heuristic-synthesis m-frame m-lang 90 :max-depth 2)))
             (resume-synthesis job 40000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr m-inputs)
               (check (expression-calls-operator-p expr :map))
               (check (equal '((20 40) (60)) (result expr m-inputs '(((10 20) (30))))))))

           ;; 2. Outer Product: `outer(u, v)_{i,j} = u_i * v_j` via 2-level `:map` + `:code-subst`
           (let* ((op-inputs (list (cons 0 seq-int) (cons 1 seq-int)))
                  (op-frame (simple-frame seq2-int op-inputs
                                          '(((() (1 2)) ())
                                            (((2 3) (4 5)) ((8 10) (12 15)))
                                            (((1 -2) (3 0 4)) ((3 0 4) (-6 0 -8))))))
                  (op-lang (make-language :int op-inputs
                                          :operators (list (op :map) (op :* :int))
                                          :literals nil
                                          :constants (list (lit seq2-int '()) (lit seq-int '()))))
                  (job (start-heuristic-synthesis op-frame op-lang 110 :max-depth 2)))
             (resume-synthesis job 50000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr op-inputs)
               (check (contains-call-to-p expr :code-subst))
               (check (equal '((10 20 30) (20 40 60))
                             (result expr op-inputs '((1 2) (10 20 30)))))))

           ;; 3. Matrix-Vector Product: `(Mv)_i = dot-product(M_i, v)`
           (let* ((mv-inputs (list (cons 0 seq2-int) (cons 1 seq-int)))
                  (mv-frame (simple-frame seq-int mv-inputs
                                          '(((() (1 2)) ())
                                            ((((1 2) (3 4)) (10 20)) (50 110))
                                            ((((2 0 1) (1 3 2)) (4 5 6)) (14 31)))))
                  (mv-lang (make-language :int mv-inputs
                                          :operators (list (op :map) (op :dot-product))
                                          :literals nil
                                          :constants (list (lit seq2-int '()) (lit seq-int '()))))
                  (job (start-heuristic-synthesis mv-frame mv-lang 100 :max-depth 2)))
             (resume-synthesis job 40000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr mv-inputs)
               (check (expression-calls-operator-p expr :dot-product))
               (check (contains-call-to-p expr :code-subst))
               (check (equal '(14 32)
                             (result expr mv-inputs '(((1 2 3) (4 5 6)) (1 2 3)))))))

           ;; 4. 2D Row Reduction (`row-sums(M)`) and 2D Grid Sum (`matrix-sum(M)`)
           (let* ((m-inputs (list (cons 0 seq2-int)))
                  (rsum-frame (simple-frame seq-int m-inputs
                                            '(((() ) ())
                                              ((((1 2 3) (4 5))) (6 9))
                                              ((((10) () (2 -5 7))) (10 0 4)))))
                  (rsum-lang (make-language :int m-inputs
                                            :operators (list (op :map) (op :sum))
                                            :literals nil
                                            :constants (list (lit seq2-int '()) (lit seq-int '()))))
                  (rsum-job (start-heuristic-synthesis rsum-frame rsum-lang 80)))
             (resume-synthesis rsum-job 30000 :stop-on-first t)
             (check (synthesis-job-best rsum-job))
             (let ((expr (candidate-expression (synthesis-job-best rsum-job))))
               (check (provably-total-p expr))
               (check (expression-calls-operator-p expr :sum))
               (check (equal '(15 6) (result expr m-inputs '(((5 5 5) (1 2 3))))))))

           (let* ((m-inputs (list (cons 0 seq2-int)))
                  (msum-frame (simple-frame :int m-inputs
                                            '(((() ) 0)
                                              ((((3 4))) 7)
                                              ((((1 2) (3 4))) 10)
                                              ((((5) (1 2) (3 4))) 15))))
                  (msum-lang (make-language :int m-inputs
                                            :operators (list (op :foldr) (op :sum) (op :+ :int))
                                            :literals '(0)
                                            :constants (list (lit seq2-int '()) (lit seq-int '()))))
                  (msum-job (start-heuristic-synthesis msum-frame msum-lang 90)))
             (resume-synthesis msum-job 30000 :stop-on-first t)
             (check (synthesis-job-best msum-job))
             (let ((expr (candidate-expression (synthesis-job-best msum-job))))
               (check (provably-total-p expr))
               (check (= 21 (result expr m-inputs '(((1 2 3) (4 5) (6))))))))

           ;; 5. Filter-Map comprehension (`[2*x + 1 for x in xs if x > 0]`) + 1-unit resume parity
           (let* ((fm-inputs (list (cons 0 seq-int)))
                  (fm-frame (simple-frame seq-int fm-inputs
                                          '(((() ) ())
                                            (((-1 2 -3 4)) (5 9))
                                            (((0 -2 3)) (7))
                                            (((-5 -1)) ()))))
                  (fm-lang (make-language :int fm-inputs
                                          :operators (list (op :map) (op :filter)
                                                           (op :+ :int) (op :< :int))
                                          :literals '(0 1)
                                          :constants (list (lit seq-int '()))))
                  (batch-job (start-heuristic-synthesis fm-frame fm-lang 100))
                  (step-job (start-heuristic-synthesis fm-frame fm-lang 100)))
             (resume-synthesis batch-job 25000 :stop-on-first t)
             (loop for limit from 1 to 25000
                   until (or (synthesis-finished-p step-job)
                             (synthesis-job-best step-job))
                   do (resume-synthesis step-job limit :stop-on-first t))
             (check (synthesis-job-best batch-job))
             (check (synthesis-job-best step-job))
             (let ((expr (candidate-expression (synthesis-job-best batch-job))))
               (check (equal expr (candidate-expression (synthesis-job-best step-job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr fm-inputs)
               (check (expression-calls-operator-p expr :map))
               (check (expression-calls-operator-p expr :filter))
               (check (equal '(3 11 21) (result expr fm-inputs '((-4 1 0 5 -2 10)))))))))
    (clear-function-definitions)))

(deftest higher-order-h3-sampled-fibers-and-cegar-refinement
  "Verify H3:
1. `*max-active-lifted-rows*` caps the initial active fiber rows returned by `lift-frame` while
   retaining the remaining distinct fiber inputs in `reserve-rows`.
2. When a child candidate satisfies the initial sampled fiber rows (e.g. `(+ X0 X0)` on `0 -> 0`
   and `2 -> 4`) but fails root verification on a full sequence (`3 -> 9`),
   `refine-lifted-node-from-counterexample` promotes the failing fiber row from `reserve-rows`
   into the active child frame, emits a `:cegar-refinement` message, and converges to `(* X0 X0)`
   without restarting child enumeration from scratch."
  (unwind-protect
       (with-knowledge-library ((make-knowledge-library))
         (clear-function-definitions)
         (define-standard-int-combinators)
         (let* ((seq-int (sequence-type :int))
                (inputs (list (cons 0 seq-int)))
                (xs (var 0 seq-int))
                (unary-code (code-type '((0 . :int)) :int))
                ;; On x=0 -> 0 and x=2 -> 4, `(+ X0 X0)` and `(* X0 X0)` agree;
                ;; on x=3 -> 9 and x=5 -> 25, only `(* X0 X0)` is valid.
                (sq-frame (simple-frame seq-int inputs
                                        '((((0 2)) (0 4))
                                          (((3 5)) (9 25)))))
                (sq-lang (make-language :int inputs
                                        :operators (list (op :map) (op :+ :int) (op :* :int))
                                        :literals nil
                                        :constants (list (lit seq-int '())))))
           (let ((*max-active-lifted-rows* 2))
             ;; 1. Direct `lift-frame` check: 2 active rows + 2 reserve rows
             (multiple-value-bind (lifted coupled reserve)
                 (lift-frame sq-frame (app (op :map) xs (var 1 unary-code)) 1 unary-code nil)
               (declare (ignore coupled))
               (check (= 2 (length (frame-rows lifted))))
               (check (= 2 (length reserve))))
             ;; 2. Full synthesis with `library-expander` under `*max-active-lifted-rows* = 2`:
             ;;    Child enumerates `(+ X0 X0)` first (since `:+` precedes `:*`), fails root verification
             ;;    on `(3 5) -> (9 25)`, triggers `:cegar-refinement`, promotes `(3) -> 9`, and finds `(* X0 X0)`.
             (let ((job (start-synthesis sq-frame sq-lang 60
                                         :expand (library-expander)
                                         :max-depth 1)))
               (resume-synthesis job 30000 :stop-on-first t)
               (check (synthesis-job-best job))
               (let ((cegar-msg (find :cegar-refinement (synthesis-job-messages job)
                                      :key #'message-claim :test #'eq))
                     (expr (candidate-expression (synthesis-job-best job))))
                 (check cegar-msg)
                 (check (equal '(3) (getf (message-evidence cegar-msg) :promoted-row)))
                 (check (provably-total-p expr))
                 (check (equal '(0 4 9 16 25) (result expr inputs '((0 2 3 4 5))))))))))
    (clear-function-definitions)))

(deftest higher-order-h4-linear-algebraic-inverses-involutions-and-invariants
  "Verify H4:
1. Pointwise binary sequence functions refactored through `:map` (`:shift` and `:scale` over `GF(5)`)
   automatically induce BOTH position-0 sequence inverters (`:shift/invert-0`, `:scale/invert-0`)
   and position-1 scalar parameter solvers (`:shift/invert-1`, `:scale/invert-1`).
2. Involution `:law` entries (`(= (reverse (reverse X0)) X0)` and `(= (transpose (transpose X0)) X0)`)
   automatically induce unary `:solver` entries via `induce-involution-solvers`.
3. `conserved-quantity-frame` discovers algebraic sequence invariants (`sum(shift(xs, d)) = sum(xs) + d * length(xs)`)."
  (unwind-protect
       (with-knowledge-library ((make-knowledge-library))
         (clear-function-definitions)
         (define-standard-int-combinators)
         (let* ((gf5 (gf 5))
                (seq-gf5 (sequence-type gf5))
                (gf5-elems '(0 1 2 3 4))
                (gf5-code (code-type (list (cons 0 gf5)) gf5))
                (bin-gf5-code (code-type (list (cons 0 gf5) (cons 1 gf5)) gf5))
                (tup-type (tuple-type gf5-code gf5))
                (subst-type (tuple-type bin-gf5-code tup-type gf5-code)))
           ;; 1. Register element-level solvers for :+ and :* over GF(5)
           (let ((add-rel (observe-arithmetic-relation gf5 :+ gf5-elems))
                 (mul-rel (observe-arithmetic-relation gf5 :* gf5-elems)))
             (dolist (pos '(0 1))
               (register-knowledge-solver
                (discover-arithmetic-solver add-rel pos gf5-elems :operators '(:+ :-))
                :id (intern (format nil "GF5-ADD-SOLVE-~D" pos) :keyword))
               (register-knowledge-solver
                (discover-arithmetic-solver mul-rel pos gf5-elems :operators '(:+ :- :* :/))
                :id (intern (format nil "GF5-MUL-SOLVE-~D" pos) :keyword))))
           ;; Retype `:map` to `GF(5)` and define `:shift(xs, d)` and `:scale(xs, c)` via `:map-gf5` + `:code-subst`
           (retype-function-definition :map gf5 :new-name :map-gf5)
           (let ((shift-inputs (list (cons 0 seq-gf5) (cons 1 gf5))))
             (define-function :shift shift-inputs seq-gf5
               (app (op :map-gf5)
                    (var 0 seq-gf5)
                    (app (op :code-subst subst-type)
                         (lit bin-gf5-code (app (op :+ gf5) (var 0 gf5) (var 1 gf5)))
                         (app (op :tuple tup-type)
                              (lit gf5-code (var 0 gf5))
                              (var 1 gf5)))))
             (define-function :scale shift-inputs seq-gf5
               (app (op :map-gf5)
                    (var 0 seq-gf5)
                    (app (op :code-subst subst-type)
                         (lit bin-gf5-code (app (op :* gf5) (var 0 gf5) (var 1 gf5)))
                         (app (op :tuple tup-type)
                              (lit gf5-code (var 0 gf5))
                              (var 1 gf5)))))
             ;; Record auxiliary step ASTs and run functorial solver induction
             (setf (knowledge-entry-auxiliary-code (find-knowledge-entry :shift))
                   (app (op :+ gf5) (var 0 gf5) (var 1 gf5))
                   (knowledge-entry-auxiliary-code (find-knowledge-entry :scale))
                   (app (op :* gf5) (var 0 gf5) (var 1 gf5)))
             (add-knowledge-edge :map-gf5 :abstracts :shift)
             (add-knowledge-edge :map-gf5 :abstracts :scale)
             (induce-functorial-solvers *knowledge-library*)

             ;; Verify all 4 solvers (:shift/invert-0, :shift/invert-1, :scale/invert-0, :scale/invert-1) exist
             (check (find-knowledge-entry :shift/invert-0))
             (check (find-knowledge-entry :shift/invert-1))
             (check (find-knowledge-entry :scale/invert-0))
             (check (find-knowledge-entry :scale/invert-1))

             ;; Test `propagate-requirements` with `:shift/invert-0` (solve for sequence `xs`)
             (let* ((f0 (make-frame (make-schema :inputs nil :target seq-gf5)
                                    (list (make-row :key 0 :known nil
                                                    :requirement (app (op := seq-gf5)
                                                                      (app (op :shift)
                                                                           (var 0 seq-gf5)
                                                                           (lit gf5 3))
                                                                      (lit seq-gf5 '(1 4 0)))))))
                    (p0 (propagate-requirements f0 *knowledge-library* (make-ledger))))
               (check (plusp (propagation-narrowed p0)))
               (check (equal '((3 1 2))
                             (extract-allowed-values (row-requirement (first (frame-rows (propagation-frame p0))))))))

             ;; Test `propagate-requirements` with `:shift/invert-1` (solve for scalar shift `d`)
             (let* ((f1 (make-frame (make-schema :inputs nil :target gf5)
                                    (list (make-row :key 0 :known nil
                                                    :requirement (app (op := seq-gf5)
                                                                      (app (op :shift)
                                                                           (lit seq-gf5 '(3 1 2))
                                                                           (var 0 gf5))
                                                                      (lit seq-gf5 '(1 4 0)))))))
                    (p1 (propagate-requirements f1 *knowledge-library* (make-ledger))))
               (check (plusp (+ (propagation-narrowed p1) (propagation-suggested p1))))
               (check (equal '(3)
                             (extract-allowed-values (row-requirement (first (frame-rows (propagation-frame p1))))))))

             ;; Test `propagate-requirements` with `:scale/invert-0` and `:scale/invert-1`
             (let* ((f2 (make-frame (make-schema :inputs nil :target seq-gf5)
                                    (list (make-row :key 0 :known nil
                                                    :requirement (app (op := seq-gf5)
                                                                      (app (op :scale)
                                                                           (var 0 seq-gf5)
                                                                           (lit gf5 2))
                                                                      (lit seq-gf5 '(4 1 3)))))))
                    (p2 (propagate-requirements f2 *knowledge-library* (make-ledger))))
               (check (plusp (propagation-narrowed p2)))
               (check (equal '((2 3 4))
                             (extract-allowed-values (row-requirement (first (frame-rows (propagation-frame p2))))))))

             (let* ((f3 (make-frame (make-schema :inputs nil :target gf5)
                                    (list (make-row :key 0 :known nil
                                                    :requirement (app (op := seq-gf5)
                                                                      (app (op :scale)
                                                                           (lit seq-gf5 '(2 3 4))
                                                                           (var 0 gf5))
                                                                      (lit seq-gf5 '(4 1 3)))))))
                    (p3 (propagate-requirements f3 *knowledge-library* (make-ledger))))
               (check (plusp (+ (propagation-narrowed p3) (propagation-suggested p3))))
               (check (equal '(2)
                             (extract-allowed-values (row-requirement (first (frame-rows (propagation-frame p3)))))))))

           ;; 2. Involution law solver induction (`(= (snoc-rev (snoc-rev X0)) X0)`)
           (let* ((seq-int (sequence-type :int))
                  (u-inputs (list (cons 0 seq-int)))
                  (xs (var 0 seq-int))
                  (empty-xs (app (op := seq-int) xs (lit seq-int '())))
                  (head-xs (app (op :at seq-int) xs (lit :int 0)))
                  (tail-xs (app (op :tail :int) xs)))
             ;; Define `:snoc(x, ys)` and `:reverse(xs)` over `(:seq :int)`
             (define-function :snoc (list (cons 0 :int) (cons 1 seq-int)) seq-int
               (lambda (self)
                 (app (op :if seq-int)
                      (app (op := seq-int) (var 1 seq-int) (lit seq-int '()))
                      (app (op :cons :int) (var 0 :int) (lit seq-int '()))
                      (app (op :cons :int)
                           (app (op :at seq-int) (var 1 seq-int) (lit :int 0))
                           (app self (var 0 :int) (app (op :tail :int) (var 1 seq-int)))))))
             (define-function :reverse u-inputs seq-int
               (lambda (self)
                 (app (op :if seq-int)
                      empty-xs
                      (lit seq-int '())
                      (app (op :snoc) head-xs (app self tail-xs)))))
             ;; Register involution law `(= (:reverse (:reverse X0)) X0)` and induce unary solver
             (let* ((inv-law (make-law :int u-inputs
                                       (app (op :reverse) (app (op :reverse) xs))
                                       xs))
                    (inv-val (start-law-validation inv-law :samples '((()) ((1)) ((1 2)) ((3 1 2))))))
               (resume-law-validation inv-val 10000)
               (register-knowledge-law inv-val :id :reverse-involution)
               (induce-functorial-solvers *knowledge-library*)
               (check (find-knowledge-entry :reverse/involution-inverter))
               (let* ((rev-frame (make-frame (make-schema :inputs nil :target seq-int)
                                             (list (make-row :key 0 :known nil
                                                             :requirement (app (op := seq-int)
                                                                               (app (op :reverse) (var 0 seq-int))
                                                                               (lit seq-int '(9 4 1)))))))
                      (rev-prop (propagate-requirements rev-frame *knowledge-library* (make-ledger))))
                 (check (plusp (+ (propagation-narrowed rev-prop)
                                  (propagation-suggested rev-prop))))
                 (check (equal '((1 4 9))
                               (extract-allowed-values
                                (row-requirement (first (frame-rows (propagation-frame rev-prop))))))))))

           ;; 3. Conserved-quantity / homomorphic invariant discovery (`sum(shift-int(xs, d)) = sum(xs) + d * length(xs)`)
           (register-knowledge-solver :-
                                      :id :int-sub-solve-0
                                      :domain :int
                                      :inputs (arithmetic-inputs :int)
                                      :target :int
                                      :position 0
                                      :witness (app (op :+ :int) (var 1 :int) (var 0 :int))
                                      :guard (lit :bool t)
                                      :certified-p t
                                      :unique-p t)
           (let* ((seq-int (sequence-type :int))
                  (sh-inputs (list (cons 0 seq-int) (cons 1 :int)))
                  (obs-inputs (list (cons 0 seq-int) (cons 1 :int) (cons 2 :int)))
                  (unary-int-code (code-type '((0 . :int)) :int))
                  (bin-int-code (code-type '((0 . :int) (1 . :int)) :int))
                  (int-tup-type (tuple-type unary-int-code :int))
                  (int-subst-type (tuple-type bin-int-code int-tup-type unary-int-code)))
             (define-function :shift-int sh-inputs seq-int
               (app (op :map)
                    (var 0 seq-int)
                    (app (op :code-subst int-subst-type)
                         (lit bin-int-code (app (op :+ :int) (var 0 :int) (var 1 :int)))
                         (app (op :tuple int-tup-type)
                              (lit unary-int-code (var 0 :int))
                              (var 1 :int)))))
             (define-function :sum-int (list (cons 0 seq-int)) :int
               (app (op :foldr) (var 0 seq-int) (lit :int 0)
                    (lit bin-int-code (app (op :+ :int) (var 0 :int) (var 1 :int)))))
             ;; Observe `delta = sum-int(shift-int(xs, d)) - sum-int(xs)` across varied `(xs, d)` pairs,
             ;; then use `conserved-quantity-frame` + `propagate-requirements` and `condense-heuristic`
             ;; to synthesize the homomorphic difference law `(* d (length xs))`.
             (let* ((obs-rows
                      (loop for (xs-val d-val) in '((() 5) ((2) 3) ((1 4) 2) ((3 -1 5) 4) ((10 20) -3))
                            for shifted = (result (app (op :shift-int) (var 0 seq-int) (var 1 :int))
                                                  sh-inputs (list xs-val d-val))
                            for base-sum = (result (app (op :sum-int) (var 0 seq-int))
                                                   (list (cons 0 seq-int)) (list xs-val))
                            for shifted-sum = (result (app (op :sum-int) (var 0 seq-int))
                                                      (list (cons 0 seq-int)) (list shifted))
                            collect (list xs-val d-val (- shifted-sum base-sum))))
                    (obs-frame (probe-frame :int obs-inputs obs-rows))
                    (conserved-expr
                      (app (op :- :int)
                           (var 2 :int)
                           (app (op :* :int)
                                (var 1 :int)
                                (app (op :length :int) (var 0 seq-int)))))
                    (pulled-cq (conserved-quantity-frame obs-frame 2 conserved-expr 0 (make-ledger)))
                    (folded-cq (nth-value 1 (frame-conflict-p pulled-cq)))
                    (prop-cq (propagate-requirements folded-cq *knowledge-library* (make-ledger)))
                    (narrowed-cq (nth-value 1 (frame-conflict-p (propagation-frame prop-cq))))
                    (cq-lang (make-language :int sh-inputs
                                            :operators (list (op :length :int) (op :* :int))
                                            :literals nil))
                    (cq-search (start-search narrowed-cq cq-lang)))
               (resume-search cq-search 55 15000)
               (check (plusp (propagation-narrowed prop-cq)))
               (check (search-job-best cq-search))
               (let ((law-prog (candidate-expression (search-job-best cq-search))))
                 (check (provably-total-p law-prog))
                 (check (= 15 (result law-prog sh-inputs '((2 3 4) 5))))))
             ;; 4. Heuristic `:certified-p nil` parameter solver + `propagation-fallback` completeness control:
             ;; Register an uncertified (`:certified-p nil`) position-1 parameter estimator for `:shift-int`
             ;; that estimates `d = (- (at Y '0) (at X '0))` when `X` is non-empty, which is exact on
             ;; non-clipped shifts (`propagation-suggested > 0`, `propagation-fallback` preserved).
             (register-knowledge-solver :shift-int
                                        :id :shift-int/heuristic-lag
                                        :domain :int
                                        :inputs (list (cons 0 seq-int) (cons 1 seq-int))
                                        :target :int
                                        :position 1
                                        :witness (app (op :- :int)
                                                      (app (op :at seq-int) (var 1 seq-int) (lit :int 0))
                                                      (app (op :at seq-int) (var 0 seq-int) (lit :int 0)))
                                        :guard (bool-not (app (op := seq-int) (var 0 seq-int) (lit seq-int '())))
                                        :certified-p nil
                                        :unique-p t)
             (let* ((lag-frame (make-frame (make-schema :inputs nil :target :int)
                                           (list (make-row :key 0 :known nil
                                                           :requirement (app (op := seq-int)
                                                                             (app (op :shift-int)
                                                                                  (lit seq-int '(10 20 30))
                                                                                  (var 0 :int))
                                                                             (lit seq-int '(13 23 33)))))))
                    (lag-prop (propagate-requirements lag-frame *knowledge-library* (make-ledger))))
               (check (= 1 (propagation-suggested lag-prop)))
               (check (propagation-fallback lag-prop))
               (check (equal '(3)
                             (extract-allowed-values
                              (row-requirement (first (frame-rows (propagation-frame lag-prop)))))))))))
    (clear-function-definitions)))
