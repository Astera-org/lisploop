(in-package #:lisploop)

(deftest recursion-r1-sequence-and-ordering-primitives
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 :int) (cons 1 seq-type)))
              (x (var 0 :int))
              (xs (var 1 seq-type))
              (cons-expr (app (op :cons :int) x xs))
              (tail-expr (app (op :tail :int) xs))
              (len-expr (app (op :length :int) xs))
              (lt-expr (app (op :< :int) x (app (op :length :int) xs))))
         ;; Codec roundtrips and exact types
         (dolist (expr (list cons-expr tail-expr len-expr lt-expr))
           (check-codec-roundtrip expr inputs))
         ;; Runtime semantics
         (check (equal '(7 1 2 3) (result cons-expr inputs '(7 (1 2 3)))))
         (check (equal '(7) (result cons-expr inputs '(7 ()))))
         (check (equal '(2 3) (result tail-expr inputs '(0 (1 2 3)))))
         (check (equal '() (result tail-expr inputs '(0 (1)))))
         (check (eq :error (evaluation-status (evaluate tail-expr inputs '(0 ())))))
         (check (= 3 (result len-expr inputs '(0 (10 20 30)))))
         (check (= 0 (result len-expr inputs '(0 ()))))
         (check (eq t (result lt-expr inputs '(2 (10 20 30)))))
         (check (null (result lt-expr inputs '(3 (10 20 30)))))
         (check (null (result lt-expr inputs '(5 (10 20 30)))))
         ;; Static totality checks
         (check (provably-total-p cons-expr))
         (check (provably-total-p len-expr))
         (check (provably-total-p lt-expr))
         (check (not (provably-total-p tail-expr)))
         (check (provably-total-p (app (op :tail :int) (lit seq-type '(1 2)))))
         (check (not (provably-total-p (app (op :tail :int) (lit seq-type '())))))
         (check (provably-total-p (app (op :tail :int) cons-expr)))
         (check (provably-total-p (app (op :at seq-type) cons-expr (lit :int 0))))
         (check (not (provably-total-p (app (op :at seq-type) cons-expr (lit :int 1)))))
         ;; < is restricted to :int, not (:gf p)
         (raises (op :< (gf 5)))
         (raises (op :< :bool)))
    (clear-function-definitions)))

(deftest recursion-r1-code-eval-and-homoiconic-capture
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (unary-code (code-type '((0 . :int)) :int))
              (binary-code (code-type '((0 . :int) (1 . :int)) :int))
              (inc-ast (app (op :+ :int) (var 0 :int) (lit :int 1)))
              (add-ast (app (op :+ :int) (var 0 :int) (var 1 :int)))
              (div-zero-ast (app (op :/ :int) (var 0 :int) (lit :int 0)))
              (inputs (list (cons 0 :int) (cons 1 unary-code)))
              (direct-eval (app (op :code-eval unary-code) (lit unary-code inc-ast) (var 0 :int)))
              (var-eval (app (op :code-eval unary-code) (var 1 unary-code) (var 0 :int)))
              (binary-eval (app (op :code-eval binary-code)
                                (lit binary-code add-ast)
                                (var 0 :int)
                                (lit :int 10))))
         (check-codec-roundtrip direct-eval inputs)
         (check-codec-roundtrip var-eval inputs)
         (check-codec-roundtrip binary-eval inputs)
         (check (= 8 (result direct-eval inputs (list 7 inc-ast))))
         (check (= 17 (result binary-eval inputs (list 7 inc-ast))))
         (check (= 8 (result var-eval inputs (list 7 inc-ast))))
         (check (eq :error (evaluation-status (evaluate var-eval inputs (list 7 div-zero-ast)))))
         ;; Totality of :code-eval on literal vs variable vs partial code
         (check (provably-total-p direct-eval))
         (check (not (provably-total-p var-eval)))
         (check (not (provably-total-p
                      (app (op :code-eval unary-code) (lit unary-code div-zero-ast) (var 0 :int)))))
         ;; Homoiconic capture via :code-subst + :code-eval (both code-in-scope and runtime value lifting)
         (let* ((outer-scope '((0 . :int) (1 . :int)))
                (elem-code (code-type '((0 . :int)) :int))
                (subst-op (op :code-subst (tuple-type binary-code (tuple-type elem-code :int) unary-code)))
                (specialized (app subst-op
                                  (lit binary-code add-ast)
                                  (app (op :tuple (tuple-type elem-code :int))
                                       (lit elem-code (var 0 :int))
                                       (var 1 :int))))
                (eval-specialized (app (op :code-eval unary-code) specialized (var 0 :int))))
           (check (provably-total-p eval-specialized))
           (check-codec-roundtrip eval-specialized outer-scope)
           (check (= 12 (result eval-specialized outer-scope '(7 5))))
           ;; 1-unit vs batch resume parity on :code-subst + :code-eval
           (let* ((whole (evaluate eval-specialized outer-scope '(7 5) :budget 100000))
                  (total (evaluation-work whole))
                  (unit (start-evaluation eval-specialized outer-scope '(7 5)))
                  (batch (start-evaluation eval-specialized outer-scope '(7 5))))
             (check (eq :value (evaluation-status whole)))
             (dolist (limit (list 0 1 5 (floor total 2) (1- total) total))
               (loop while (< (evaluation-work unit) limit) do (advance-evaluation unit 1))
               (advance-evaluation batch (- limit (evaluation-work batch)))
               (check (equalp unit batch))
               (check (= limit (evaluation-work batch)))))))
    (clear-function-definitions)))

(deftest recursion-r1-named-functions-resume-parity-and-cutoffs
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (unary-code (code-type '((0 . :int)) :int))
              (binary-code (code-type '((0 . :int) (1 . :int)) :int))
              (xs (var 0 seq-type))
              (f-var (var 1 unary-code))
              (init-var (var 1 :int))
              (fold-f-var (var 2 binary-code)))
         ;; 1. De novo function naming (:FA, :FB, ..., :FZ, :FAA)
         (check (eq :fa (de-novo-function-name 0)))
         (check (eq :fb (de-novo-function-name 1)))
         (check (eq :fz (de-novo-function-name 25)))
         (check (eq :faa (de-novo-function-name 26)))
         (let ((n1 (next-function-name))
               (n2 (next-function-name)))
           (check (eq :fa n1))
           (check (eq :fb n2)))
         ;; 2. Define recursive :fa (copy), :fb (map), :fc (fold), :fd (insert), :fe (sort)
         (define-function :fa (list (cons 0 seq-type)) seq-type
           (lambda (self)
             (app (op :if seq-type)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit seq-type '())
                  (app (op :cons :int)
                       (app (op :at seq-type) xs (lit :int 0))
                       (app self (app (op :tail :int) xs))))))
         (check (function-definition-total-p (find-function-definition :fa)))
         (check (provably-total-p (app (op :fa) xs)))

         (define-function :fb (list (cons 0 seq-type) (cons 1 unary-code)) seq-type
           (lambda (self)
             (app (op :if seq-type)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit seq-type '())
                  (app (op :cons :int)
                       (app (op :code-eval unary-code) f-var (app (op :at seq-type) xs (lit :int 0)))
                       (app self (app (op :tail :int) xs) f-var)))))
         (check (not (function-definition-total-p (find-function-definition :fb))))
         (check (equal '(1) (function-definition-conditional-code-params (find-function-definition :fb))))
         (let ((inc-lit (lit unary-code (app (op :+ :int) (var 0 :int) (lit :int 1))))
               (bad-lit (lit unary-code (app (op :/ :int) (var 0 :int) (lit :int 0)))))
           (check (provably-total-p (app (op :fb) xs inc-lit)))
           (check (not (provably-total-p (app (op :fb) xs bad-lit))))
           (check (not (provably-total-p (app (op :fb) xs f-var)))))

         (define-function :fc (list (cons 0 seq-type) (cons 1 :int) (cons 2 binary-code)) :int
           (lambda (self)
             (app (op :if :int)
                  (app (op := seq-type) xs (lit seq-type '()))
                  init-var
                  (app (op :code-eval binary-code)
                       fold-f-var
                       (app (op :at seq-type) xs (lit :int 0))
                       (app self (app (op :tail :int) xs) init-var fold-f-var)))))
         (check (equal '(2) (function-definition-conditional-code-params (find-function-definition :fc))))

         ;; :fd = insert(x, sorted)
         (let ((elem (var 0 :int))
               (sorted (var 1 seq-type)))
           (define-function :fd (list (cons 0 :int) (cons 1 seq-type)) seq-type
             (lambda (self)
               (app (op :if seq-type)
                    (app (op := seq-type) sorted (lit seq-type '()))
                    (app (op :cons :int) elem (lit seq-type '()))
                    (app (op :if seq-type)
                         (app (op :< :int) elem (app (op :at seq-type) sorted (lit :int 0)))
                         (app (op :cons :int) elem sorted)
                         (app (op :cons :int)
                              (app (op :at seq-type) sorted (lit :int 0))
                              (app self elem (app (op :tail :int) sorted))))))))
         (check (function-definition-total-p (find-function-definition :fd)))

         ;; :fe = sort(xs) calling :fd
         (define-function :fe (list (cons 0 seq-type)) seq-type
           (lambda (self)
             (app (op :if seq-type)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit seq-type '())
                  (app (op :fd)
                       (app (op :at seq-type) xs (lit :int 0))
                       (app self (app (op :tail :int) xs))))))
         (check (function-definition-total-p (find-function-definition :fe)))
         (check (provably-total-p (app (op :fe) xs)))

         ;; Codec roundtrips and execution for :fa, :fb, :fc, :fe
         (let* ((inputs (list (cons 0 seq-type)))
                (copy-call (app (op :fa) xs))
                (map-call (app (op :fb) xs (lit unary-code (app (op :* :int) (var 0 :int) (lit :int 2)))))
                (fold-call (app (op :fc) xs (lit :int 0)
                                (lit binary-code (app (op :+ :int) (var 0 :int) (var 1 :int)))))
                (sort-call (app (op :fe) xs)))
           (dolist (call (list copy-call map-call fold-call sort-call))
             (check-codec-roundtrip call inputs))
           (check (equal '(3 1 4 1 5) (result copy-call inputs '((3 1 4 1 5)))))
           (check (equal '(6 2 8 2 10) (result map-call inputs '((3 1 4 1 5)))))
           (check (= 14 (result fold-call inputs '((3 1 4 1 5)))))
           (check (equal '(1 1 3 4 5) (result sort-call inputs '((3 1 4 1 5)))))
           ;; 1-unit vs batch VM resume parity across recursive sort
           (let* ((whole (evaluate sort-call inputs '((3 1 2)) :budget 1000000))
                  (total (evaluation-work whole))
                  (unit (start-evaluation sort-call inputs '((3 1 2))))
                  (batch (start-evaluation sort-call inputs '((3 1 2)))))
             (check (eq :value (evaluation-status whole)))
             (check (equal '(1 2 3) (evaluation-value whole)))
             (dolist (limit (list 0 1 10 (floor total 3) (floor (* 2 total) 3) (1- total) total))
               (loop while (< (evaluation-work unit) limit) do (advance-evaluation unit 1))
               (advance-evaluation batch (- limit (evaluation-work batch)))
               (check (equalp unit batch))
               (check (= limit (evaluation-work batch)))
               (check (eq (if (< limit total) :unknown :value) (evaluation-status batch)))))
           ;; Prepared program validation & library version invalidation
           (let* ((val-state (advance-evaluation (start-program-validation sort-call inputs) 1000000))
                  (program (progn (check (eq :value (evaluation-status val-state)))
                                  (evaluation-value val-state)))
                  (run (advance-evaluation (start-validated-evaluation program '((4 2 3 1))) 100000)))
             (check (eq :value (evaluation-status run)))
             (check (equal '(1 2 3 4) (evaluation-value run)))
             ;; Defining a new function bumps library version and invalidates stale validated-program
             (define-function :ff (list (cons 0 seq-type)) seq-type (lambda (self) (app self xs)))
             (raises (start-validated-evaluation program '((4 2 3 1))))
             ;; Non-terminating recursion :ff has total-p = nil and hits :unknown (cutoff), not :error
             (check (not (function-definition-total-p (find-function-definition :ff))))
             (check (not (provably-total-p (app (op :ff) xs))))
             (let ((inf-run (evaluate (app (op :ff) xs) inputs '((1 2)) :budget 500)))
               (check (eq :unknown (evaluation-status inf-run)))
               (check (= 500 (evaluation-work inf-run))))
             ;; Clearing definitions also invalidates validated programs from that library snapshot
             (clear-function-definitions)
             (raises (start-validated-evaluation program '((4 2 3 1)))))))
    (clear-function-definitions)))

(deftest recursion-r1-oracle-unresolved-and-search-filtering
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (xs (var 0 seq-type)))
         ;; Define an incomplete oracle for sum(xs): knows () -> 0 and (2) -> 2, but NOT (1 2)
         (define-function :fa inputs :int nil
           :oracle-table '(((()) . 0)
                           (((2)) . 2)))
         ;; Compact call-site overhead (2 app tag bits + 12 opcode bits = 14 bits, no redundant :code type emission)
         (check (= (+ 2 (operator-name-bit-size :fa)) (application-overhead (op :fa))))
         (let* ((step-expr (app (op :if :int)
                                (app (op := seq-type) xs (lit seq-type '()))
                                (lit :int 0)
                                (app (op :+ :int)
                                     (app (op :at seq-type) xs (lit :int 0))
                                     (app (op :fa) (app (op :tail :int) xs)))))
                (wrong-expr (app (op :if :int)
                                 (app (op := seq-type) xs (lit seq-type '()))
                                 (lit :int 99)
                                 (app (op :fa) (app (op :tail :int) xs))))
                (self-call (app (op :fa) xs))
                (only-unresolved (app (op :fa) (lit seq-type '(9 9)))))
           (check (not (provably-total-p self-call)))
           ;; On (2): tail is () which is in oracle -> evaluates to 2
           (let ((r1 (evaluate step-expr inputs '((2)))))
             (check (eq :value (evaluation-status r1)))
             (check (= 2 (evaluation-value r1))))
           ;; On (3 2): tail is (2) which is in oracle -> evaluates to 5
           (let ((r2 (evaluate step-expr inputs '((3 2)))))
             (check (eq :value (evaluation-status r2)))
             (check (= 5 (evaluation-value r2))))
           ;; On (1 3 2): tail is (3 2) which is NOT in oracle -> :unresolved (not :error!)
           (let ((r3 (evaluate step-expr inputs '((1 3 2)))))
             (check (eq :unresolved (evaluation-status r3))))
           ;; Search over frame containing (2)->2, (3 2)->5, and trace-incomplete (1 3 2)->6:
           ;; step-expr resolves & passes on (2) and (3 2) and is :unresolved on (1 3 2) -> accepted!
           ;; wrong-expr fails on resolved rows -> rejected!
           ;; self-call only resolves on 1 row ((2)->2) out of 3 -> rejected by >= 2 resolved-rows rule!
           ;; only-unresolved is :unresolved on all rows -> rejected!
           (let* ((frame (simple-frame :int inputs
                                       '((((2)) 2)
                                         (((3 2)) 5)
                                         (((1 3 2)) 6))))
                  (language (make-language :int inputs :operators (list (op :+ :int))))
                  (job (start-search frame language
                                     :expressions (list step-expr wrong-expr self-call only-unresolved)))
                  (bound (max (description-size step-expr inputs)
                              (description-size wrong-expr inputs)
                              (description-size self-call inputs)
                              (description-size only-unresolved inputs))))
             (check (eq :replay-complete (message-claim (resume-search job bound 1000000))))
             (check (= 1 (length (search-job-results job))))
             (check (equal step-expr (candidate-expression (search-job-best job))))
             ;; Heuristic search also skips :unresolved without charging a false residual
             (let ((h-job (%make-heuristic-search
                           :observation (start-observation-search (make-observation-scope frame language)
                                                                  :expressions (list step-expr only-unresolved)
                                                                  :retain-outcomes t)
                           :debt 1 :bound bound)))
               (resume-heuristic-search h-job 100000)
               (check (heuristic-search-best h-job))
               (check (heuristic-exact-p (heuristic-search-best h-job)))
               (check (heuristic-total-p (heuristic-search-best h-job)))
               (check (equal step-expr (heuristic-program (heuristic-search-best h-job))))))
           ;; Upgrading :fa from an oracle to a total recursive definition invalidates cached ast-meta on self-call
           (define-function :fa inputs :int step-expr)
           (check (provably-total-p self-call))))
    (clear-function-definitions)))

(deftest recursion-r2-sequence-equality-splitting-and-projections
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (x0 (var 0 :int))
              (x1 (var 1 :int))
              (xs (var 2 seq-type))
              (inputs (list (cons 0 :int) (cons 1 :int) (cons 2 seq-type)))
              (two-cons (app (op :cons :int) x0 (app (op :cons :int) x1 (lit seq-type '()))))
              (open-cons (app (op :cons :int) x0 (app (op :cons :int) x1 xs))))
         ;; 1. (= (cons X0 (cons X1 '())) '(3 5)) -> (bool-and (= X0 '3) (= X1 '5))
         (let ((eq-two (app (op := seq-type) two-cons (lit seq-type '(3 5))))
               (expected (bool-and (app (op := :int) x0 (lit :int 3))
                                   (app (op := :int) x1 (lit :int 5)))))
           (check (equal expected (fold-constants eq-two))))
         ;; 2. (= (cons X0 xs) '()) -> 'nil, and length-mismatch (= (cons X0 (cons X1 '())) '(3)) -> 'nil
         (check (equal (lit :bool nil)
                       (fold-constants (app (op := seq-type) (app (op :cons :int) x0 xs) (lit seq-type '())))))
         (check (equal (lit :bool nil)
                       (fold-constants (app (op := seq-type) two-cons (lit seq-type '(3))))))
         ;; 3. (at (cons X0 xs) '0) -> X0 and (at (cons X0 (cons X1 xs)) '1) -> X1
         (check (equal x0 (fold-constants (app (op :at seq-type) open-cons (lit :int 0)))))
         (check (equal x1 (fold-constants (app (op :at seq-type) open-cons (lit :int 1)))))
         (check (equal (app (op :at seq-type) xs (lit :int 0))
                       (fold-constants (app (op :at seq-type) open-cons (lit :int 2)))))
         ;; 4. (tail (cons X0 xs)) -> xs and (length (cons X0 '(10 20))) -> '3
         (check (equal (app (op :cons :int) x1 xs)
                       (fold-constants (app (op :tail :int) open-cons))))
         (check (equal (lit :int 3)
                       (fold-constants (app (op :length :int)
                                            (app (op :cons :int) x0 (lit seq-type '(10 20)))))))
         ;; 5. Definedness preservation: partial child (/ '1 X0) is never dropped
         (let* ((bad-div (app (op :/ :int) (lit :int 1) x0))
                (bad-cons (app (op :cons :int) bad-div (lit seq-type '())))
                (eq-empty (app (op := seq-type) bad-cons (lit seq-type '())))
                (tail-bad (app (op :tail :int) bad-cons))
                (at0-bad-tail (app (op :at seq-type)
                                   (app (op :cons :int) x1 (app (op :cons :int) bad-div (lit seq-type '())))
                                   (lit :int 0))))
           (dolist (expr (list eq-empty tail-bad at0-bad-tail))
             (let ((folded (fold-constants expr)))
               (dolist (v0 '(-1 0 1 2))
                 (let ((r-orig (evaluate expr inputs (list v0 9 '(4))))
                       (r-fold (evaluate folded inputs (list v0 9 '(4)))))
                   (check (eq (evaluation-status r-orig) (evaluation-status r-fold)))
                   (when (eq :value (evaluation-status r-orig))
                     (check (equal (evaluation-value r-orig) (evaluation-value r-fold))))))))))
    (clear-function-definitions)))

(deftest recursion-r2-guarded-unfold-definedness-and-cutoffs
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (xs (var 0 seq-type))
              (x0 (var 0 :int))
              (ys (var 1 seq-type)))
         ;; :fa = copy(xs)
         (define-function :fa (list (cons 0 seq-type)) seq-type
           (lambda (self)
             (app (op :if seq-type)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit seq-type '())
                  (app (op :cons :int)
                       (app (op :at seq-type) xs (lit :int 0))
                       (app self (app (op :tail :int) xs))))))
         ;; :fb = first-or-default(xs, fallback) = (if (= xs '()) '0 fallback)
         (define-function :fb (list (cons 0 seq-type) (cons 1 :int)) :int
           (lambda (self)
             (declare (ignore self))
             (app (op :if :int)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit :int 0)
                  (var 1 :int))))
         ;; 1. Unfolding (:fa (cons X0 '(2 3))) folds completely to (cons X0 '(2 3))
         (let* ((call-closed-tail (app (op :fa) (app (op :cons :int) x0 (lit seq-type '(2 3)))))
                (folded (fold-constants call-closed-tail)))
           (check (equal (app (op :cons :int) x0 (lit seq-type '(2 3))) folded)))
         ;; 2. Unfolding (:fa (cons X0 ys)) unfolds one step to (cons X0 (:fa ys)) and stops cleanly
         (let* ((call-open-tail (app (op :fa) (app (op :cons :int) x0 ys)))
                (folded (fold-constants call-open-tail)))
           (check (equal (app (op :cons :int) x0 (app (op :fa) ys)) folded)))
         ;; 3. Call-by-value definedness preservation under lazy :if:
         ;; (:fb '() (+ X0 '1)) unfolds to '0, whereas (:fb '() (/ '1 X0)) stays intact so X0=0 still errors!
         (let* ((safe-call (app (op :fb) (lit seq-type '()) (app (op :+ :int) x0 (lit :int 1))))
                (partial-call (app (op :fb) (lit seq-type '()) (app (op :/ :int) (lit :int 1) x0)))
                (folded-safe (fold-constants safe-call))
                (folded-partial (fold-constants partial-call)))
           (check (equal (lit :int 0) folded-safe))
           (check (equal partial-call folded-partial))
           (dolist (v '(-1 0 1))
             (let ((r1 (evaluate partial-call '((0 . :int)) (list v)))
                   (r2 (evaluate folded-partial '((0 . :int)) (list v))))
               (check (eq (evaluation-status r1) (evaluation-status r2)))
               (when (eq :value (evaluation-status r1))
                 (check (equal (evaluation-value r1) (evaluation-value r2)))))))
         ;; 4. Budget cutoff leaves unreduced expression intact and semantically equivalent
         (let* ((call (app (op :fa) (app (op :cons :int) x0 (lit seq-type '(2 3 4)))))
                (ledger (make-ledger)))
           (check (equal call (fold-constants call nil :ledger ledger :budget 0)))
           (check (zerop (ledger-total ledger)))
           (dolist (b '(1 2 4 8 100))
             (let ((cut (fold-constants call nil :budget b)))
               (dolist (v '(5 9))
                 (check (equal (result call '((0 . :int)) (list v))
                               (result cut '((0 . :int)) (list v)))))))))
    (clear-function-definitions)))

(deftest recursion-r2-pullback-through-recursive-decoders
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (unary-code (code-type '((0 . :int)) :int))
              (binary-code (code-type '((0 . :int) (1 . :int)) :int))
              (xs (var 0 seq-type))
              (f-var (var 1 unary-code))
              (acc-var (var 1 :int))
              (fold-f-var (var 2 binary-code)))
         ;; :fa = sum(xs)
         (define-function :fa (list (cons 0 seq-type)) :int
           (lambda (self)
             (app (op :if :int)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit :int 0)
                  (app (op :+ :int)
                       (app (op :at seq-type) xs (lit :int 0))
                       (app self (app (op :tail :int) xs))))))
         ;; :fb = map(xs, f)
         (define-function :fb (list (cons 0 seq-type) (cons 1 unary-code)) seq-type
           (lambda (self)
             (app (op :if seq-type)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit seq-type '())
                  (app (op :cons :int)
                       (app (op :code-eval unary-code) f-var (app (op :at seq-type) xs (lit :int 0)))
                       (app self (app (op :tail :int) xs) f-var)))))
         ;; :fc = foldl(xs, acc, f)
         (define-function :fc (list (cons 0 seq-type) (cons 1 :int) (cons 2 binary-code)) :int
           (lambda (self)
             (app (op :if :int)
                  (app (op := seq-type) xs (lit seq-type '()))
                  acc-var
                  (app self
                       (app (op :tail :int) xs)
                       (app (op :code-eval binary-code)
                            fold-f-var
                            acc-var
                            (app (op :at seq-type) xs (lit :int 0)))
                       fold-f-var))))

         ;; 1. First-order recursive decoder: d(X0, Z) = (:fa (cons Z X0))
         ;; Parent observations: X0=(2 3)->6 (so Z=1), X0=(10 20)->35 (so Z=5); true Z = (+ (* '2 X1) '1)
         (let* ((parent-inputs (list (cons 0 seq-type) (cons 1 :int)))
                (parent (simple-frame :int parent-inputs
                                      '((((2 3) 0) 6)
                                        (((10 20) 2) 35)
                                        (((1 1) 4) 11))))
                (decoder (app (op :fa) (app (op :cons :int) (var 9 :int) (var 0 seq-type))))
                (bindings (list (cons 0 (var 1 :int))))
                (raw-child (pullback-frame parent decoder 9 :int bindings)))
           (multiple-value-bind (conflict child-frame) (frame-conflict-p raw-child)
             (check (null conflict))
             ;; First row requirement folded from (= (:fa (cons Z '(2 3))) '6) to (= (+ Z '5) '6)
             (check (equal (app (op := :int)
                                (app (op :+ :int) (var 0 :int) (lit :int 5))
                                (lit :int 6))
                           (row-requirement (first (frame-rows child-frame)))))
             ;; Propagate + search on the pulled-back child frame finds (+ (* 2 X0) 1)
             (let* ((work (make-ledger))
                    (library (prepare-propagator-library (arithmetic-controls :int) work))
                    (prop (propagate-requirements child-frame library work))
                    (narrowed-frame (propagation-frame prop))
                    (child-lang (make-language :int '((0 . :int))
                                               :operators (list (op :+ :int) (op :* :int))
                                               :literals '(1 2)))
                    (job (start-search narrowed-frame child-lang)))
               (check (equal (app (op := :int) (var 0 :int) (lit :int 1))
                             (row-requirement (first (frame-rows narrowed-frame)))))
               (resume-search job 40 100000)
               (check (search-job-best job))
               (let ((composed (compose-model decoder 9 (candidate-expression (search-job-best job)) bindings)))
                 (dolist (row (frame-rows parent))
                   (check (= (first (extract-allowed-values (row-requirement row)))
                             (result composed parent-inputs (row-known row)))))))))

         ;; 2. Higher-order recursive map decoder: d(X0, Z) = (:fb X0 Z) where Z : (:code ((0 . :int)) :int)
         (let* ((parent-inputs (list (cons 0 seq-type)))
                (parent (simple-frame seq-type parent-inputs
                                      '((((3 5)) (7 11))
                                        (((1 4)) (3 9)))))
                (z-var (var 9 unary-code))
                (decoder (app (op :fb) xs z-var))
                (raw-child (pullback-frame parent decoder 9 unary-code nil)))
           (multiple-value-bind (conflict child-frame) (frame-conflict-p raw-child)
             (check (null conflict))
             ;; First row requirement folded from (= (:fb '(3 5) Z) '(7 11))
             ;; into (bool-and (= (:code-eval Z '3) '7) (= (:code-eval Z '5) '11))
             (let ((z0 (var 0 unary-code)))
               (check (equal (bool-and (app (op := :int)
                                            (app (op :code-eval unary-code) z0 (lit :int 3))
                                            (lit :int 7))
                                       (app (op := :int)
                                            (app (op :code-eval unary-code) z0 (lit :int 5))
                                            (lit :int 11)))
                             (row-requirement (first (frame-rows child-frame))))))
             ;; Search over candidate code expressions in child-frame recovers '(+ (* X0 2) 1)
             (let* ((target-code (lit unary-code
                                      (app (op :+ :int)
                                           (app (op :* :int) (var 0 :int) (lit :int 2))
                                           (lit :int 1))))
                    (wrong-code (lit unary-code
                                     (app (op :+ :int) (var 0 :int) (lit :int 4))))
                    (child-lang (make-language :int nil
                                               :operators nil
                                               :literals nil
                                               :constants (list target-code wrong-code)))
                    (job (start-search child-frame child-lang
                                       :expressions (list wrong-code target-code)))
                    (bound (max (description-size wrong-code nil)
                                (description-size target-code nil))))
               (resume-search job bound 100000)
               (check (= 1 (length (search-job-results job))))
               (check (equal target-code (candidate-expression (search-job-best job))))
               (let ((composed (compose-model decoder 9 (candidate-expression (search-job-best job)) nil)))
                 (check (equal '(7 11) (result composed parent-inputs '((3 5)))))
                 (check (equal '(3 9) (result composed parent-inputs '((1 4)))))))))

         ;; 3. Higher-order recursive foldl decoder: d(X0, Z) = (:fc X0 '0 Z)
         ;; Unfolds (:fc '(3 5) '0 Z) into (:code-eval Z (:code-eval Z '0 '3) '5)
         (let* ((z0 (var 0 binary-code))
                (fold-expr (app (op :fc) (lit seq-type '(3 5)) (lit :int 0) z0))
                (folded (fold-constants fold-expr))
                (expected (app (op :code-eval binary-code)
                               z0
                               (app (op :code-eval binary-code) z0 (lit :int 0) (lit :int 3))
                               (lit :int 5))))
           (check (equal expected folded)))

         ;; 4. Higher-order map with runtime value capture via :code-subst:
         ;; d(X0, Z) = (:fb X0 (:code-subst '(* X0 X1) (tuple 'X0 Z))) where Z : :int
         ;; Unfolds on '(3 5) -> '(6 10) into (and (= (* '3 Z) '6) (= (* '5 Z) '10)), propagating to (= Z '2)!
         (let* ((parent-inputs (list (cons 0 seq-type) (cons 1 :int)))
                (parent (simple-frame seq-type parent-inputs
                                      '((((3 5) 1) (6 10))
                                        (((2 4) 3) (8 16)))))
                (mul-template (lit binary-code (app (op :* :int) (var 0 :int) (var 1 :int))))
                (subst-op (op :code-subst (tuple-type binary-code (tuple-type unary-code :int) unary-code)))
                (captured-fn (app subst-op mul-template
                                  (app (op :tuple (tuple-type unary-code :int))
                                       (lit unary-code (var 0 :int))
                                       (var 9 :int))))
                (decoder (app (op :fb) xs captured-fn))
                (bindings (list (cons 0 (var 1 :int))))
                (raw-child (pullback-frame parent decoder 9 :int bindings)))
           (multiple-value-bind (conflict child-frame) (frame-conflict-p raw-child)
             (check (null conflict))
             (let* ((work (make-ledger))
                    (library (prepare-propagator-library (arithmetic-controls :int) work))
                    (prop (propagate-requirements child-frame library work))
                    (narrowed (propagation-frame prop)))
               (check (equal (app (op := :int) (var 0 :int) (lit :int 2))
                             (fold-constants (row-requirement (first (frame-rows narrowed))))))
               (check (equal (app (op := :int) (var 0 :int) (lit :int 4))
                             (fold-constants (row-requirement (second (frame-rows narrowed))))))))))
    (clear-function-definitions)))

(deftest recursion-r3-conserved-quantity-observation-and-inversion
  (unwind-protect
       (let* ((work (make-ledger))
              (library (prepare-propagator-library (arithmetic-controls :int) work))
              (inputs-3 '((0 . :int) (1 . :int) (2 . :int)))
              (inputs-2 '((0 . :int) (1 . :int)))
              (u-lang-2 (make-language :int inputs-2
                                       :operators (list (op :+ :int) (op :- :int))
                                       :literals '(0 1))))
         ;; 1. Copy index conservation: records (j, n-1, I) from '(10 20 30) and '(40 50)
         (let* ((raw-copy (probe-frame :int inputs-3
                                       '((0 2 0)
                                         (1 2 1)
                                         (2 2 2)
                                         (0 1 0)
                                         (1 1 1))))
                (obs-copy (with-frame-linkage raw-copy :labels '(0 0 0 0 0)))
                (obs-lang (make-language :int inputs-3 :operators (list (op :- :int))))
                (scope (make-observation-scope obs-copy obs-lang :pairs (frame-pairs obs-copy)))
                (obs-job (start-observation-search scope))
                (conserved-expr (app (op :- :int) (var 2 :int) (var 0 :int))))
           (resume-observation-search obs-job (description-size conserved-expr inputs-3) 100000)
           (let ((rec (find-observation obs-job conserved-expr)))
             (check rec)
             (check (equal '(0 0 0 0 0) (observed-expression-values rec))))
           (multiple-value-bind (pulled const-frame)
               (conserved-quantity-frame obs-copy 2 conserved-expr 0)
             (let* ((prop (propagate-requirements pulled library (make-ledger)))
                    (narrowed (nth-value 1 (frame-conflict-p (propagation-frame prop)))))
               (check (= 5 (propagation-suggested prop)))
               (dolist (row (frame-rows narrowed))
                 (check (equal (list (first (row-known row)))
                               (extract-allowed-values (row-requirement row)))))
               (let* ((decomp (make-decomposition :name :invert-copy-index
                                                  :decoder conserved-expr
                                                  :child-id 2
                                                  :child-type :int
                                                  :bindings (list (cons 0 (var 0 :int)) (cons 1 (var 1 :int)))
                                                  :language u-lang-2
                                                  :bound 28
                                                  :solver library))
                      (synth (start-synthesis const-frame u-lang-2 28 :decompositions (list decomp))))
                 (resume-synthesis synth 100000 :stop-on-first t)
                 (check (synthesis-job-best synth))
                 (dolist (row (frame-rows obs-copy))
                   (check (= 0 (result (candidate-expression (synthesis-job-best synth))
                                       inputs-2 (subseq (row-known row) 0 2)))))))))

         ;; 2. Reverse index conservation: records (j, n-1, I) from '(10 20 30)->'(30 20 10) and '(40 50)->'(50 40)
         ;; Conserved quantity: (- (+ I j) (n-1)) = 0 => algebraically inverts to I = (n-1) - j
         (let* ((raw-rev (probe-frame :int inputs-3
                                      '((0 2 2)
                                        (1 2 1)
                                        (2 2 0)
                                        (0 1 1)
                                        (1 1 0))))
                (obs-rev (with-frame-linkage raw-rev :labels '(0 0 0 0 0)))
                (conserved-expr (app (op :- :int)
                                     (app (op :+ :int) (var 2 :int) (var 0 :int))
                                     (var 1 :int)))
                (obs-lang (make-language :int inputs-3 :operators (list (op :+ :int) (op :- :int))))
                (scope (make-observation-scope obs-rev obs-lang :pairs (frame-pairs obs-rev)))
                (obs-job (start-observation-search scope :expressions (list conserved-expr))))
           (resume-observation-search obs-job (description-size conserved-expr inputs-3) 100000)
           (let ((rec (find-observation obs-job conserved-expr)))
             (check rec)
             (check (equal '(0 0 0 0 0) (observed-expression-values rec))))
           (multiple-value-bind (pulled const-frame)
               (conserved-quantity-frame obs-rev 2 conserved-expr 0)
             (let* ((prop (propagate-requirements pulled library (make-ledger)))
                    (narrowed (nth-value 1 (frame-conflict-p (propagation-frame prop)))))
               (check (= 5 (propagation-suggested prop)))
               (dolist (row (frame-rows narrowed))
                 (destructuring-bind (j n-1) (row-known row)
                   (check (equal (list (- n-1 j))
                                 (extract-allowed-values (row-requirement row))))))
               (let* ((s-job (start-search narrowed u-lang-2)))
                 (resume-search s-job 36 100000)
                 (check (search-job-best s-job))
                 (check (equal (app (op :- :int) (var 1 :int) (var 0 :int))
                               (candidate-expression (search-job-best s-job)))))
               (let* ((root-lang (make-language :int inputs-2 :operators nil :literals nil))
                      (decomp (make-decomposition :name :invert-reverse-index
                                                  :decoder conserved-expr
                                                  :child-id 2
                                                  :child-type :int
                                                  :bindings (list (cons 0 (var 0 :int)) (cons 1 (var 1 :int)))
                                                  :language u-lang-2
                                                  :bound 36
                                                  :solver library))
                      (synth (start-synthesis const-frame root-lang 48 :decompositions (list decomp))))
                 (resume-synthesis synth 200000 :stop-on-first t)
                 (check (synthesis-job-best synth))))))

         ;; 3. Value conservation on map_inc ((- Y_j X_j) = 1 => Y_j = X_j + 1)
         ;;    and step conservation on fold_sum ((- (- Y Z) H) = 0 => Y = H + Z)
         (let* ((obs-map (probe-frame :int inputs-2
                                      '((3 4) (5 6) (10 11))))
                (map-conserved (app (op :- :int) (var 1 :int) (var 0 :int)))
                (pulled-map (conserved-quantity-frame obs-map 1 map-conserved 1))
                (prop-map (propagate-requirements pulled-map library (make-ledger)))
                (narrowed-map (nth-value 1 (frame-conflict-p (propagation-frame prop-map))))
                (u-lang-1 (make-language :int '((0 . :int))
                                         :operators (list (op :+ :int))
                                         :literals '(1)))
                (map-search (start-search narrowed-map u-lang-1)))
           (resume-search map-search 36 100000)
           (check (search-job-best map-search))
           (check (equal (app (op :+ :int) (var 0 :int) (lit :int 1))
                         (candidate-expression (search-job-best map-search)))))

         (let* ((obs-fold (probe-frame :int inputs-3
                                       '((3 2 5) (2 0 2) (4 5 9))))
                (fold-conserved (app (op :- :int)
                                     (app (op :- :int) (var 2 :int) (var 1 :int))
                                     (var 0 :int)))
                (pulled-fold (conserved-quantity-frame obs-fold 2 fold-conserved 0))
                (prop-fold (propagate-requirements pulled-fold library (make-ledger)))
                (narrowed-fold (nth-value 1 (frame-conflict-p (propagation-frame prop-fold))))
                (fold-search (start-search narrowed-fold u-lang-2)))
           (resume-search fold-search 36 100000)
           (check (search-job-best fold-search))
           (dolist (row (frame-rows obs-fold))
             (destructuring-bind (h z y) (row-known row)
               (check (= y (result (candidate-expression (search-job-best fold-search))
                                   inputs-2 (list h z))))))))
    (clear-function-definitions)))

(deftest recursion-r3-lift-frame-map-and-symmetry-conflict
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (unary-code (code-type '((0 . :int)) :int))
              (idx-code (code-type (list (cons 0 :int) (cons 1 :int) (cons 2 seq-type)) :int))
              (xs (var 0 seq-type))
              (f-var (var 1 unary-code)))
         ;; :fb = map(xs, f)
         (define-function :fb (list (cons 0 seq-type) (cons 1 unary-code)) seq-type
           (lambda (self)
             (app (op :if seq-type)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit seq-type '())
                  (app (op :cons :int)
                       (app (op :code-eval unary-code) f-var (app (op :at seq-type) xs (lit :int 0)))
                       (app self (app (op :tail :int) xs) f-var)))))
         ;; :fc = map-indexed(xs, idx, full-xs, f)
         (define-function :fc (list (cons 0 seq-type) (cons 1 :int) (cons 2 seq-type) (cons 3 idx-code)) seq-type
           (lambda (self)
             (app (op :if seq-type)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit seq-type '())
                  (app (op :cons :int)
                       (app (op :code-eval idx-code)
                            (var 3 idx-code)
                            (app (op :at seq-type) xs (lit :int 0))
                            (var 1 :int)
                            (var 2 seq-type))
                       (app self
                            (app (op :tail :int) xs)
                            (app (op :+ :int) (var 1 :int) (lit :int 1))
                            (var 2 seq-type)
                            (var 3 idx-code))))))

         ;; 1. 1-to-many lift-frame on map (E1) + end-to-end start-synthesis with :lift-p t
         (let* ((parent-inputs (list (cons 0 seq-type)))
                (parent (simple-frame seq-type parent-inputs
                                      '((((3 5)) (7 11))
                                        (((1 4)) (3 9)))))
                (decoder (app (op :fb) xs (var 9 unary-code))))
           (multiple-value-bind (lifted coupled) (lift-frame parent decoder 9 unary-code)
             (check (null coupled))
             (check (equal '((0 . :int)) (schema-inputs (frame-schema lifted))))
             (check (eq :int (schema-target (frame-schema lifted))))
             (check (= 4 (length (frame-rows lifted))))
             (check (equal '((3) (5) (1) (4)) (mapcar #'row-known (frame-rows lifted)))))
           (let* ((root-lang (make-language :int parent-inputs :operators nil :literals nil))
                  (target-child (app (op :+ :int) (app (op :* :int) (var 0 :int) (lit :int 2)) (lit :int 1)))
                  (child-lang (make-language :int '((0 . :int))
                                             :operators (list (op :+ :int) (op :* :int))
                                             :literals '(1 2)))
                  (decomp (make-decomposition :name :map-lift
                                              :decoder decoder
                                              :child-id 9
                                              :child-type unary-code
                                              :language child-lang
                                              :bound (description-size target-child '((0 . :int)))
                                              :lift-p t))
                  (job (start-synthesis parent root-lang 80 :decompositions (list decomp))))
             (resume-synthesis job 500000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((best-expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p best-expr))
               (check-codec-roundtrip best-expr parent-inputs)
               (check (equal '(7 11) (result best-expr parent-inputs '((3 5)))))
               (check (equal '(3 9) (result best-expr parent-inputs '((1 4)))))
               (check (equal '(1 5 13) (result best-expr parent-inputs '((0 2 6))))))))

         ;; 2. 1-to-many lift-frame with runtime context capture (bindings) + :code-subst reconstruction
         (let* ((parent-inputs (list (cons 0 seq-type) (cons 1 :int)))
                (parent (simple-frame seq-type parent-inputs
                                      '((((3 5) 2) (6 10))
                                        (((1 4) 3) (3 12)))))
                (decoder (app (op :fb) xs (var 9 unary-code)))
                (bindings (list (cons 1 (var 1 :int))))
                (root-lang (make-language :int parent-inputs :operators nil :literals nil))
                (child-lang (make-language :int '((0 . :int) (1 . :int))
                                           :operators (list (op :* :int))
                                           :literals nil))
                (target-child (app (op :* :int) (var 0 :int) (var 1 :int)))
                (decomp (make-decomposition :name :map-capture-lift
                                            :decoder decoder
                                            :child-id 9
                                            :child-type unary-code
                                            :bindings bindings
                                            :language child-lang
                                            :bound (description-size target-child '((0 . :int) (1 . :int)))
                                            :lift-p t))
                (job (start-synthesis parent root-lang 80 :decompositions (list decomp))))
           (resume-synthesis job 500000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((best-expr (candidate-expression (synthesis-job-best job))))
             (check (provably-total-p best-expr))
             (check-codec-roundtrip best-expr parent-inputs)
             (check (equal '(6 10) (result best-expr parent-inputs '((3 5) 2))))
             (check (equal '(3 12) (result best-expr parent-inputs '((1 4) 3))))
             (check (equal '(20 30) (result best-expr parent-inputs '((4 6) 5))))))

         ;; 3. Symmetry conflict refutation on reverse (E1c):
         ;;    Element-only map lift is immediately refuted by frame-conflict-p (:incompatible-rows),
         ;;    while indexed/sequence-aware map-lift resolves the conflict!
         (let* ((parent-inputs (list (cons 0 seq-type)))
                (rev-parent (simple-frame seq-type parent-inputs
                                          '((((1 2)) (2 1))
                                            (((1 3)) (3 1)))))
                (elem-decoder (app (op :fb) xs (var 9 unary-code)))
                (idx-decoder (app (op :fc) xs (lit :int 0) xs (var 9 idx-code)))
                (elem-lifted (lift-frame rev-parent elem-decoder 9 unary-code))
                (idx-lifted (lift-frame rev-parent idx-decoder 9 idx-code)))
           (multiple-value-bind (conflict folded) (frame-conflict-p elem-lifted)
             (declare (ignore folded))
             (check conflict)
             (check (eq :incompatible-rows (frame-conflict-kind conflict)))
             (check (equal '(1) (frame-conflict-known conflict)))
             (check (equal '((0 0) (1 0)) (frame-conflict-keys conflict))))
           (multiple-value-bind (conflict folded) (frame-conflict-p idx-lifted)
             (check (null conflict))
             (check (= 4 (length (frame-rows folded))))
             (let* ((rev-elem-expr (app (op :at seq-type)
                                        (var 2 seq-type)
                                        (app (op :- :int)
                                             (app (op :- :int)
                                                  (app (op :length :int) (var 2 seq-type))
                                                  (lit :int 1))
                                             (var 1 :int))))
                    (root-lang (make-language :int parent-inputs :operators nil :literals nil))
                    (elem-lang (make-language :int '((0 . :int)) :operators (list (op :+ :int)) :literals '(1)))
                    (idx-lang (make-language :int (code-inputs idx-code)
                                             :operators (list (op :at seq-type) (op :- :int) (op :length :int))
                                             :literals '(1)))
                    (bad-decomp (make-decomposition :name :bad-elem-map
                                                    :decoder elem-decoder
                                                    :child-id 9
                                                    :child-type unary-code
                                                    :language elem-lang
                                                    :bound 24
                                                    :lift-p t))
                    (good-decomp (make-decomposition :name :good-idx-map
                                                     :decoder idx-decoder
                                                     :child-id 9
                                                     :child-type idx-code
                                                     :language idx-lang
                                                     :bound (description-size rev-elem-expr (code-inputs idx-code))
                                                     :lift-p t))
                    (composed-rev (compose-lifted-model idx-decoder 9 idx-code rev-elem-expr))
                    (job (start-synthesis rev-parent root-lang 60
                                          :decompositions (list bad-decomp good-decomp))))
               (resume-synthesis job 5000 :stop-on-first t)
               ;; Verify that :bad-elem-map emitted a :conflict message during node preparation
               (check (find-if (lambda (m)
                                 (and (eq :conflict (message-claim m))
                                      (eq :bad-elem-map (getf (message-evidence m) :proposal))))
                               (synthesis-job-messages job)))
               ;; And composed-rev reverses arbitrary sequences
               (check (equal '(2 1) (result composed-rev parent-inputs '((1 2)))))
               (check (equal '(3 1) (result composed-rev parent-inputs '((1 3)))))
               (check (equal '(40 30 20 10) (result composed-rev parent-inputs '((10 20 30 40)))))))))
    (clear-function-definitions)))

(deftest recursion-r3-congruence-closure-and-prefix-closed-fold
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (binary-code (code-type '((0 . :int) (1 . :int)) :int))
              (xs (var 0 seq-type))
              (acc-var (var 1 :int))
              (fold-f-var (var 2 binary-code))
              (parent-inputs (list (cons 0 seq-type)))
              (root-lang (make-language :int parent-inputs :operators nil :literals nil)))
         ;; :fc = foldl(xs, acc, f)
         (define-function :fc (list (cons 0 seq-type) (cons 1 :int) (cons 2 binary-code)) :int
           (lambda (self)
             (app (op :if :int)
                  (app (op := seq-type) xs (lit seq-type '()))
                  acc-var
                  (app self
                       (app (op :tail :int) xs)
                       (app (op :code-eval binary-code)
                            fold-f-var
                            acc-var
                            (app (op :at seq-type) xs (lit :int 0)))
                       fold-f-var))))

         ;; 1. sumsq via foldl + cross-row congruence closure: (+ acc (* x x))
         (let* ((parent (simple-frame :int parent-inputs
                                      '(((() ) 0)
                                        (((3)) 9)
                                        (((3 4)) 25)
                                        (((2)) 4)
                                        (((2 5)) 29)
                                        (((3 4 1)) 26))))
                (decoder (app (op :fc) xs (lit :int 0) (var 9 binary-code))))
           (multiple-value-bind (lifted coupled) (lift-frame parent decoder 9 binary-code)
             (check (null coupled))
             (check (= 5 (length (frame-rows lifted))))
             (check (equal '((0 3) (9 4) (0 2) (4 5) (25 1))
                           (mapcar #'row-known (frame-rows lifted)))))
           (let* ((child-inputs '((0 . :int) (1 . :int)))
                  (target-child (app (op :+ :int) (var 0 :int) (app (op :* :int) (var 1 :int) (var 1 :int))))
                  (child-lang (make-language :int child-inputs
                                             :operators (list (op :+ :int) (op :* :int))
                                             :literals nil))
                  (decomp (make-decomposition :name :fold-sumsq
                                              :decoder decoder
                                              :child-id 9
                                              :child-type binary-code
                                              :language child-lang
                                              :bound (description-size target-child child-inputs)
                                              :lift-p t))
                  (job (start-synthesis parent root-lang 80 :decompositions (list decomp))))
             (resume-synthesis job 500000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((best-expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p best-expr))
               (check-codec-roundtrip best-expr parent-inputs)
               (check (= 30 (result best-expr parent-inputs '((1 2 3 4))))))))

         ;; 2. horner10 via foldl + cross-row congruence closure: (+ (* acc 10) x)
         (let* ((parent (simple-frame :int parent-inputs
                                      '(((() ) 0)
                                        (((3)) 3)
                                        (((3 4)) 34)
                                        (((3 4 5)) 345)
                                        (((1)) 1)
                                        (((1 2)) 12))))
                (decoder (app (op :fc) xs (lit :int 0) (var 9 binary-code)))
                (child-inputs '((0 . :int) (1 . :int)))
                (target-child (app (op :+ :int) (app (op :* :int) (var 0 :int) (lit :int 10)) (var 1 :int)))
                (child-lang (make-language :int child-inputs
                                           :operators (list (op :+ :int) (op :* :int))
                                           :literals '(10)))
                (decomp (make-decomposition :name :fold-horner10
                                            :decoder decoder
                                            :child-id 9
                                            :child-type binary-code
                                            :language child-lang
                                            :bound (description-size target-child child-inputs)
                                            :lift-p t))
                (job (start-synthesis parent root-lang 80 :decompositions (list decomp))))
           (resume-synthesis job 500000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((best-expr (candidate-expression (synthesis-job-best job))))
             (check (provably-total-p best-expr))
             (check-codec-roundtrip best-expr parent-inputs)
             (check (= 789 (result best-expr parent-inputs '((7 8 9)))))))

         ;; 3. (+ acc (* acc x)) via foldl (init = 1) + cross-row congruence closure
         (let* ((parent (simple-frame :int parent-inputs
                                      '(((() ) 1)
                                        (((2)) 3)
                                        (((2 3)) 12)
                                        (((4)) 5)
                                        (((4 1)) 10))))
                (decoder (app (op :fc) xs (lit :int 1) (var 9 binary-code)))
                (child-inputs '((0 . :int) (1 . :int)))
                (target-child (app (op :+ :int) (var 0 :int) (app (op :* :int) (var 0 :int) (var 1 :int))))
                (child-lang (make-language :int child-inputs
                                           :operators (list (op :+ :int) (op :* :int))
                                           :literals nil))
                (decomp (make-decomposition :name :fold-acc-prod
                                            :decoder decoder
                                            :child-id 9
                                            :child-type binary-code
                                            :language child-lang
                                            :bound (description-size target-child child-inputs)
                                            :lift-p t))
                (job (start-synthesis parent root-lang 80 :decompositions (list decomp))))
           (resume-synthesis job 500000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((best-expr (candidate-expression (synthesis-job-best job))))
             (check (provably-total-p best-expr))
             (check-codec-roundtrip best-expr parent-inputs)
             (check (= 24 (result best-expr parent-inputs '((2 3 1))))))))
    (clear-function-definitions)))

(deftest recursion-r4-de-novo-unary-functions
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (seq-ops (list (op :cons :int) (op :at seq-type) (op :tail :int)
                             (op := seq-type) (op :if seq-type)
                             (op :+ :int) (op :* :int)))
              (int-ops (list (op :at seq-type) (op :tail :int)
                             (op := seq-type) (op :if :int)
                             (op :+ :int) (op :* :int))))
         ;; 1. copy: (:seq :int) -> (:seq :int)
         (clear-function-definitions)
         (let* ((frame (simple-frame seq-type inputs
                                     '(((() ) ())
                                       (((3)) (3))
                                       (((1 3)) (1 3))
                                       (((4 1 3)) (4 1 3)))))
                (lang (make-language :int inputs
                                     :operators seq-ops
                                     :literals nil
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis frame lang 80 :self-name :fa)))
           (resume-synthesis job 50000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((expr (candidate-expression (synthesis-job-best job))))
             (check (function-definition-total-p (find-function-definition :fa)))
             (check (provably-total-p expr))
             (check-codec-roundtrip expr inputs)
             (check (equal '(9 8 7 6) (result expr inputs '((9 8 7 6)))))))

         ;; 2. inc-all: (:seq :int) -> (:seq :int)
         (clear-function-definitions)
         (let* ((frame (simple-frame seq-type inputs
                                     '(((() ) ())
                                       (((2)) (3))
                                       (((5 2)) (6 3))
                                       (((0 5 2)) (1 6 3)))))
                (lang (make-language :int inputs
                                     :operators seq-ops
                                     :literals '(1)
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis frame lang 90 :self-name :fa)))
           (resume-synthesis job 50000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((expr (candidate-expression (synthesis-job-best job))))
             (check (function-definition-total-p (find-function-definition :fa)))
             (check (provably-total-p expr))
             (check-codec-roundtrip expr inputs)
             (check (equal '(11 21 31) (result expr inputs '((10 20 30)))))))

         ;; 3. double-all: (:seq :int) -> (:seq :int)
         (clear-function-definitions)
         (let* ((frame (simple-frame seq-type inputs
                                     '(((() ) ())
                                       (((3)) (6))
                                       (((4 3)) (8 6))
                                       (((1 4 3)) (2 8 6)))))
                (lang (make-language :int inputs
                                     :operators seq-ops
                                     :literals '(2)
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis frame lang 90 :self-name :fa)))
           (resume-synthesis job 50000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((expr (candidate-expression (synthesis-job-best job))))
             (check (function-definition-total-p (find-function-definition :fa)))
             (check (provably-total-p expr))
             (check-codec-roundtrip expr inputs)
             (check (equal '(10 -4 14) (result expr inputs '((5 -2 7)))))))

         ;; 4. sum: (:seq :int) -> :int
         (clear-function-definitions)
         (let* ((frame (simple-frame :int inputs
                                     '(((() ) 0)
                                       (((4)) 4)
                                       (((3 4)) 7)
                                       (((2 3 4)) 9))))
                (lang (make-language :int inputs
                                     :operators int-ops
                                     :literals nil
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis frame lang 80 :self-name :fa)))
           (resume-synthesis job 50000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((expr (candidate-expression (synthesis-job-best job))))
             (check (function-definition-total-p (find-function-definition :fa)))
             (check (provably-total-p expr))
             (check-codec-roundtrip expr inputs)
             (check (= 100 (result expr inputs '((10 20 30 40)))))))

         ;; 5. length: (:seq :int) -> :int
         (clear-function-definitions)
         (let* ((frame (simple-frame :int inputs
                                     '(((() ) 0)
                                       (((7)) 1)
                                       (((5 7)) 2)
                                       (((9 5 7)) 3))))
                (lang (make-language :int inputs
                                     :operators (list (op :at seq-type) (op :tail :int)
                                                      (op := seq-type) (op :if :int)
                                                      (op :+ :int))
                                     :literals '(1)
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis frame lang 80 :self-name :fa)))
           (resume-synthesis job 50000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((expr (candidate-expression (synthesis-job-best job))))
             (check (function-definition-total-p (find-function-definition :fa)))
             (check (provably-total-p expr))
             (check-codec-roundtrip expr inputs)
             (check (= 6 (result expr inputs '((1 2 3 4 5 6)))))))

         ;; 6. product: (:seq :int) -> :int
         (clear-function-definitions)
         (let* ((frame (simple-frame :int inputs
                                     '(((() ) 1)
                                       (((3)) 3)
                                       (((2 3)) 6)
                                       (((4 2 3)) 24))))
                (lang (make-language :int inputs
                                     :operators int-ops
                                     :literals nil
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis frame lang 80 :self-name :fa)))
           (resume-synthesis job 50000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((expr (candidate-expression (synthesis-job-best job))))
             (check (function-definition-total-p (find-function-definition :fa)))
             (check (provably-total-p expr))
             (check-codec-roundtrip expr inputs)
             (check (= 70 (result expr inputs '((2 5 7))))))))
    (clear-function-definitions)))

(deftest recursion-r4-insert-and-sort-synthesis
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (insert-inputs (list (cons 0 :int) (cons 1 seq-type)))
              (sort-inputs (list (cons 0 seq-type))))
         ;; 1. Synthesize insert(x, sorted) de novo (2-level conditional split: (= X1 '()) then (< X0 (at X1 '0)))
         ;; Note that (2 (3 5)) -> (2 3 5) does not have (2 (5)) in the training set, exercising lazy :unresolved.
         (let* ((insert-frame (simple-frame seq-type insert-inputs
                                            '(((2 ()) (2))
                                              ((1 (3)) (1 3))
                                              ((2 (3 5)) (2 3 5))
                                              ((4 (5)) (4 5))
                                              ((4 (2 5)) (2 4 5))
                                              ((3 (4)) (3 4))
                                              ((3 (1 4)) (1 3 4)))))
                (insert-lang (make-language :int insert-inputs
                                            :operators (list (op :cons :int) (op :at seq-type)
                                                             (op :tail :int) (op :< :int)
                                                             (op := seq-type) (op :if seq-type))
                                            :literals nil
                                            :constants (list (lit seq-type '()))))
                (insert-job (start-recursive-synthesis insert-frame insert-lang 110 :self-name :fa)))
           (resume-synthesis insert-job 100000 :stop-on-first t)
           (check (synthesis-job-best insert-job))
           (let ((insert-expr (candidate-expression (synthesis-job-best insert-job))))
             (check (function-definition-total-p (find-function-definition :fa)))
             (check (provably-total-p insert-expr))
             (check-codec-roundtrip insert-expr insert-inputs)
             (check (equal '(0 1 2 3) (result insert-expr insert-inputs '(0 (1 2 3)))))
             (check (equal '(1 2 3 4 5) (result insert-expr insert-inputs '(3 (1 2 4 5)))))
             (check (equal '(1 2 4 5 9) (result insert-expr insert-inputs '(9 (1 2 4 5)))))))

         ;; 2. Synthesize sort(xs) de novo using the synthesized :fa (insert)
         (let* ((sort-frame (simple-frame seq-type sort-inputs
                                          '(((() ) ())
                                            (((2)) (2))
                                            (((3 2)) (2 3))
                                            (((1 3 2)) (1 2 3))
                                            (((4 1 3 2)) (1 2 3 4)))))
                (sort-lang (make-language :int sort-inputs
                                          :operators (list (op :fa) (op :at seq-type)
                                                           (op :tail :int) (op := seq-type)
                                                           (op :if seq-type))
                                          :literals nil
                                          :constants (list (lit seq-type '()))))
                (sort-job (start-recursive-synthesis sort-frame sort-lang 90 :self-name :fb)))
           (resume-synthesis sort-job 50000 :stop-on-first t)
           (check (synthesis-job-best sort-job))
           (let ((sort-expr (candidate-expression (synthesis-job-best sort-job))))
             (check (function-definition-total-p (find-function-definition :fb)))
             (check (provably-total-p sort-expr))
             (check-codec-roundtrip sort-expr sort-inputs)
             (check (equal '(1 2 3 4 5) (result sort-expr sort-inputs '((5 3 1 4 2)))))
             (check (equal '(-1 0 2 4 4 9) (result sort-expr sort-inputs '((9 -1 4 0 4 2))))))))
    (clear-function-definitions)))

(deftest recursion-r4-oracle-controls-and-resume-parity
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (xs (var 0 seq-type))
              (int-ops (list (op :at seq-type) (op :tail :int)
                             (op := seq-type) (op :if :int) (op :+ :int))))
         ;; 1. Positive control: trace-incomplete dataset where (1 4 2) -> 7 has no (4 2) row in the oracle.
         ;; Child search returns (+ H R) with R=:unresolved on (1 4 2), and root VM verification executes
         ;; the full recursion (1 4 2) -> (4 2) -> (2) -> () to confirm 7.
         (clear-function-definitions)
         (let* ((frame (simple-frame :int inputs
                                     '(((() ) 0)
                                       (((2)) 2)
                                       (((3 2)) 5)
                                       (((1 4 2)) 7))))
                (lang (make-language :int inputs
                                     :operators int-ops
                                     :literals nil
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis frame lang 80 :self-name :fa)))
           (resume-synthesis job 50000 :stop-on-first t)
           (check (synthesis-job-best job))
           (let ((expr (candidate-expression (synthesis-job-best job))))
             (check (provably-total-p expr))
             (check (= 7 (result expr inputs '((1 4 2)))))
             (check (= 15 (result expr inputs '((1 2 3 4 5)))))))

         ;; 2. Negative control A: corrupted target on the trace-incomplete row ((1 4 2) -> 99).
         ;; Child search still proposes (+ H R), but root VM verification executes the concrete
         ;; recursive body on (1 4 2), computes 7 /= 99, and rejects it!
         (clear-function-definitions)
         (let* ((bad-frame (simple-frame :int inputs
                                         '(((() ) 0)
                                           (((2)) 2)
                                           (((3 2)) 5)
                                           (((1 4 2)) 99))))
                (lang (make-language :int inputs
                                     :operators int-ops
                                     :literals nil
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis bad-frame lang 60 :self-name :fa)))
           (resume-synthesis job 30000 :stop-on-first t)
           (check (null (synthesis-job-best job)))
           (check (find-if (lambda (m)
                             (and (eq :rejected (message-claim m))
                                  (eq :original-root (getf (message-evidence m) :scope))))
                           (synthesis-job-messages job))))

         ;; 3. Negative control B: circular oracle-only fits (:fa X0) and (if (= X0 '()) '0 (:fa X0))
         ;; match the oracle table directly, but root verification binds :fa to the candidate body,
         ;; hits the per-row evaluation cutoff in the VM, and rejects them cleanly.
         (clear-function-definitions)
         (let* ((frame (simple-frame :int inputs
                                     '(((() ) 0)
                                       (((2)) 2)
                                       (((3 2)) 5))))
                (oracle (frame-oracle-table frame))
                ( dummy (define-function :fa inputs :int nil :oracle-table oracle))
                (circular-direct (app (op :fa) xs))
                (circular-guarded (app (op :if :int)
                                       (app (op := seq-type) xs (lit seq-type '()))
                                       (lit :int 0)
                                       (app (op :fa) xs)))
                (root-lang (make-language :int inputs
                                          :operators (cons (op :fa) int-ops)
                                          :literals '(0)
                                          :constants (list (lit seq-type '()))))
                (decomp (make-decomposition :name :bogus-circular
                                            :decoder circular-guarded
                                            :child-id 1
                                            :child-type :int
                                            :bindings nil
                                            :language (make-language :int nil :literals '(0))
                                            :bound 40))
                (job (start-synthesis frame root-lang 70
                                      :decompositions (list decomp)
                                      :self-name :fa
                                      :oracle-table oracle
                                      :verification-row-budget 300)))
           (declare (ignore dummy))
           ;; Under the oracle alone, both circular expressions evaluate to :value on all rows of frame:
           (check (= 2 (result circular-direct inputs '((2)))))
           (check (= 5 (result circular-guarded inputs '((3 2)))))
           ;; Enqueue circular-direct directly to root verification as well:
           (enqueue-node-candidate job (synthesis-job-root job) circular-direct nil)
           (resume-synthesis job 10000)
           (check (null (synthesis-job-best job)))
           (check (find-if (lambda (m)
                             (and (eq :rejected (message-claim m))
                                  (eq :original-root (getf (message-evidence m) :scope))))
                           (synthesis-job-messages job))))

         ;; 4. 1-unit vs. batch resume-synthesis parity on recursive synthesis
         (clear-function-definitions)
         (let* ((frame (simple-frame :int inputs
                                     '(((() ) 0)
                                       (((4)) 4)
                                       (((3 4)) 7)
                                       (((2 3 4)) 9))))
                (lang (make-language :int inputs
                                     :operators int-ops
                                     :literals nil
                                     :constants (list (lit seq-type '()))))
                (probe (start-recursive-synthesis frame lang 80 :self-name :fa))
                (probe-msg (resume-synthesis probe 50000 :stop-on-first t))
                (total (ledger-total (synthesis-job-ledger probe))))
           (declare (ignore probe-msg))
           (check (synthesis-job-best probe))
           (clear-function-definitions)
           (let ((unit (start-recursive-synthesis frame lang 80 :self-name :fa))
                 (batch (start-recursive-synthesis frame lang 80 :self-name :fa)))
             (dolist (limit (list 0 1 5 (floor total 3) (floor (* 2 total) 3) (1- total) total))
               (loop while (< (ledger-total (synthesis-job-ledger unit)) limit)
                     do (resume-synthesis unit (1+ (ledger-total (synthesis-job-ledger unit)))
                                          :stop-on-first t))
               (resume-synthesis batch limit :stop-on-first t)
               (check (= limit (ledger-total (synthesis-job-ledger unit))))
               (check (= limit (ledger-total (synthesis-job-ledger batch))))
               (check (equalp (synthesis-job-ledger unit) (synthesis-job-ledger batch)))
               (check (equalp (synthesis-job-best unit) (synthesis-job-best batch)))))))
    (clear-function-definitions)))

(deftest recursion-r4-audit-edge-cases-debug-and-pre-r5-r6
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (xs (var 0 seq-type)))
         ;; 1. Constrained-only resolved-rows: dead `'t` rows from base cases must not inflate resolved-rows
         (clear-function-definitions)
         (let* ((bin-inputs (list (cons 0 :int) (cons 1 seq-type)))
                (parent (simple-frame seq-type bin-inputs
                                      '(((2 ()) (2))
                                        ((4 ()) (4))
                                        ((2 (1 3)) (1 2 3))
                                        ((4 (1 5)) (1 4 5)))))
                (oracle (frame-oracle-table parent))
                (dummy (define-function :fa bin-inputs seq-type nil :oracle-table oracle))
                (guard (app (op := seq-type) (var 1 seq-type) (lit seq-type '())))
                (base (app (op :cons :int) (var 0 :int) (lit seq-type '())))
                (decoder (app (op :if seq-type) guard base (var 9 seq-type)))
                (bindings (list (cons 0 (var 0 :int))
                                (cons 1 (app (op :at seq-type) (var 1 seq-type) (lit :int 0)))
                                (cons 2 (app (op :fa) (var 0 :int) (app (op :tail :int) (var 1 seq-type))))))
                (pulled (pullback-frame parent decoder 9 seq-type bindings)))
           (declare (ignore dummy))
           (multiple-value-bind (conflict folded) (frame-conflict-p pulled)
             (check (null conflict))
             ;; 2 base rows folded to `'t`, 2 non-empty rows remain constrained (and both have :unresolved in X2)
             (check (= 4 (length (frame-rows folded))))
             (check (= 2 (frame-constrained-row-count folded)))
             (check (= 2 (frame-min-resolved-rows folded)))
             ;; Dead rows (rows 0 and 1) substituted default values instead of :unresolved
             (check (not (member :unresolved (row-known (first (frame-rows folded))))))
             (check (not (member :unresolved (row-known (second (frame-rows folded))))))
             ;; Constrained rows (rows 2 and 3) have :unresolved in slot 2
             (check (eq :unresolved (third (row-known (third (frame-rows folded))))))
             (check (eq :unresolved (third (row-known (fourth (frame-rows folded))))))
             ;; Candidate `(var 2 seq-type)` evaluates to :value on the 2 dead rows, and :unresolved on both
             ;; constrained rows -> must be REJECTED because 0 < 2 constrained rows resolved!
             (let* ((child-inputs (schema-inputs (frame-schema folded)))
                    (child-lang (make-language :int child-inputs :operators nil :literals nil))
                    (sjob (start-search folded child-lang :expressions (list (var 2 seq-type)))))
               (resume-search sjob 100 5000)
               (check (null (search-job-best sjob)))
               (check (null (search-job-results sjob))))
             ;; And `infer-fibers` / `tighten-same-input-requirements` does not conjoin rows sharing :unresolved
             (multiple-value-bind (classes msg refined) (infer-fibers folded)
               (declare (ignore classes msg))
               (check (frame-p refined)))))

         ;; 2. Transitive totality recomputation when an underlying dependency is redefined
         (clear-function-definitions)
         (define-function :fa inputs :int
           (lambda (self)
             (app (op :if :int)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit :int 0)
                  (app (op :+ :int)
                       (app (op :at seq-type) xs (lit :int 0))
                       (app self (app (op :tail :int) xs))))))
         (define-function :fb inputs :int
           (lambda (self)
             (declare (ignore self))
             (app (op :+ :int) (app (op :fa) xs) (lit :int 1))))
         (let ((call-fb (app (op :fb) xs)))
           (check (function-definition-total-p (find-function-definition :fa)))
           (check (function-definition-total-p (find-function-definition :fb)))
           (check (provably-total-p call-fb))
           ;; Redefining :fa as an oracle invalidates :fb's totality transitively
           (define-function :fa inputs :int nil :oracle-table '((((2)) . 2)))
           (check (not (function-definition-total-p (find-function-definition :fa))))
           (check (not (function-definition-total-p (find-function-definition :fb))))
           (check (not (provably-total-p call-fb)))
           ;; Redefining :fa with a total body restores :fb's totality transitively
           (define-function :fa inputs :int
             (lambda (self)
               (app (op :if :int)
                    (app (op := seq-type) xs (lit seq-type '()))
                    (lit :int 0)
                    (app (op :+ :int)
                         (app (op :/ :int) (app (op :at seq-type) xs (lit :int 0)) (lit :int 2))
                         (app self (app (op :tail :int) xs))))))
           (check (function-definition-total-p (find-function-definition :fa)))
           (check (function-definition-total-p (find-function-definition :fb)))
           (check (provably-total-p call-fb)))

         ;; 3. Oracle state restoration when recursive synthesis fails or stops without a verified candidate
         (clear-function-definitions)
         (let* ((bad-frame (simple-frame :int inputs
                                         '(((() ) 0)
                                           (((2)) 2)
                                           (((3 2)) 5)
                                           (((1 4 2)) 99))))
                (lang (make-language :int inputs
                                     :operators (list (op :at seq-type) (op :tail :int)
                                                      (op := seq-type) (op :if :int) (op :+ :int))
                                     :literals nil
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis bad-frame lang 60 :self-name :fa)))
           (resume-synthesis job 30000 :stop-on-first t)
           (check (null (synthesis-job-best job)))
           ;; :fa must be restored to its oracle table, not left bound to the rejected (+ H R) body!
           (let ((def (find-function-definition :fa)))
             (check def)
             (check (null (function-definition-body def)))
             (check (function-definition-oracle-table def))))

         ;; 4. Coupled non-prefix-closed fold in `lift-frame` does not pass constants on a vacuous row
         (clear-function-definitions)
         (let* ((binary-code (code-type '((0 . :int) (1 . :int)) :int))
                (acc-var (var 1 :int))
                (fold-f-var (var 2 binary-code)))
           (define-function :fc (list (cons 0 seq-type) (cons 1 :int) (cons 2 binary-code)) :int
             (lambda (self)
               (app (op :if :int)
                    (app (op := seq-type) xs (lit seq-type '()))
                    acc-var
                    (app self
                         (app (op :tail :int) xs)
                         (app (op :code-eval binary-code)
                              fold-f-var acc-var (app (op :at seq-type) xs (lit :int 0)))
                         fold-f-var))))
           (let* ((coupled-parent (simple-frame :int inputs
                                                '((((3 4)) 25)
                                                  (((2 5)) 29))))
                  (decoder (app (op :fc) xs (lit :int 0) (var 9 binary-code))))
             (multiple-value-bind (lifted coupled) (lift-frame coupled-parent decoder 9 binary-code)
               (check (= 2 (length coupled)))
               (check (= 2 (frame-constrained-row-count lifted)))
               ;; Constant '0 is rejected on the coupled lifted frame
               (let* ((child-lang (make-language :int '((0 . :int) (1 . :int)) :operators nil :literals '(0)))
                      (sjob (start-search lifted child-lang :expressions (list (lit :int 0)))))
                 (resume-search sjob 50 5000)
                 (check (null (search-job-best sjob)))))))

         ;; 5. Explicit Debug Mode (`:debug-p t`, `explain-synthesis-node`, `explain-synthesis-job`)
         ;;    and homoiconic S-expression `nogood-clause`
         (clear-function-definitions)
         (let* ((frame (simple-frame :int inputs
                                     '(((() ) 0)
                                       (((4)) 4)
                                       (((3 4)) 7)
                                       (((2 3 4)) 9))))
                (lang (make-language :int inputs
                                     :operators (list (op :at seq-type) (op :tail :int)
                                                      (op := seq-type) (op :if :int) (op :+ :int))
                                     :literals nil
                                     :constants (list (lit seq-type '()))))
                (job (start-recursive-synthesis frame lang 80 :self-name :fa :debug-p t)))
           (resume-synthesis job 50000 :stop-on-first t)
           (check (synthesis-job-best job))
           (check (synthesis-job-debug-p job))
           (let* ((out (make-string-output-stream))
                  (summary (explain-synthesis-job job :stream out))
                  (text (get-output-stream-string out)))
             (check (getf summary :best))
             (check (plusp (length text)))
             (check (some (lambda (n-rep)
                            (and (getf n-rep :proposal-provenance)
                                 (eq :inductive-sequence-lift
                                     (getf (getf n-rep :proposal-provenance) :origin))))
                          (getf summary :nodes)))))

         ;; 6. Pre-R5 helpers: `rename-function-calls`, `shared-subterm-cover`, `abstract-over-subterms`
         (clear-function-definitions)
         (define-function :fa inputs :int nil :oracle-table '(((() ) . 0)))
         (define-function :fb inputs :int nil :oracle-table '(((() ) . 0)))
         (let* ((head-x0 (app (op :at seq-type) xs (lit :int 0)))
                (tail-x0 (app (op :tail :int) xs))
                (rec-fa (app (op :fa) tail-x0))
                (rec-fb (app (op :fb) tail-x0))
                (sum-step (app (op :+ :int) head-x0 rec-fa))
                (len-step-raw (app (op :+ :int) (lit :int 1) rec-fb))
                (len-step (rename-function-calls len-step-raw :fb :fa))
                (cover (shared-subterm-cover (list sum-step len-step) inputs :self-name :fa)))
           (check (equal (list head-x0 rec-fa) cover))
           (multiple-value-bind (sum-code sum-code-type sum-body)
               (abstract-over-subterms sum-step cover inputs)
             (multiple-value-bind (len-code len-code-type len-body)
                 (abstract-over-subterms len-step cover inputs)
               (check (equal sum-code-type len-code-type))
               (check (equal (code-type '((0 . :int) (1 . :int)) :int) sum-code-type))
               (check (equal (app (op :+ :int) (var 0 :int) (var 1 :int)) sum-body))
               (check (equal (app (op :+ :int) (lit :int 1) (var 1 :int)) len-body))
               (check (lit-p sum-code))
               (check (lit-p len-code))))
           (let* ((inc-step (app (op :+ :int) head-x0 (lit :int 1)))
                  (dbl-step (app (op :* :int) head-x0 (lit :int 2)))
                  (map-cover (shared-subterm-cover (list inc-step dbl-step) inputs)))
             (check (equal (list head-x0) map-cover))
             (multiple-value-bind (inc-code inc-type inc-body)
                 (abstract-over-subterms inc-step map-cover inputs)
               (declare (ignore inc-code))
               (check (equal (code-type '((0 . :int)) :int) inc-type))
               (check (equal (app (op :+ :int) (var 0 :int) (lit :int 1)) inc-body)))))

         ;; 7. Pre-R6 / Phase 5.2 homoiconic S-expression `nogood-clause` on 1-to-many lift conflict
         (clear-function-definitions)
         (let* ((unary-code (code-type '((0 . :int)) :int))
                (f-var (var 1 unary-code)))
           (define-function :fb (list (cons 0 seq-type) (cons 1 unary-code)) seq-type
             (lambda (self)
               (app (op :if seq-type)
                    (app (op := seq-type) xs (lit seq-type '()))
                    (lit seq-type '())
                    (app (op :cons :int)
                         (app (op :code-eval unary-code) f-var (app (op :at seq-type) xs (lit :int 0)))
                         (app self (app (op :tail :int) xs) f-var)))))
           (let* ((rev-parent (simple-frame seq-type inputs
                                            '((((1 2)) (2 1))
                                              (((1 3)) (3 1)))))
                  (elem-decoder (app (op :fb) xs (var 9 unary-code)))
                  (elem-lang (make-language :int '((0 . :int)) :operators (list (op :+ :int)) :literals '(1)))
                  (bad-decomp (make-decomposition :name :bad-elem-map
                                                  :decoder elem-decoder
                                                  :child-id 9
                                                  :child-type unary-code
                                                  :language elem-lang
                                                  :bound 24
                                                  :lift-p t))
                  (root-lang (make-language :int inputs :operators nil :literals nil))
                  (job (start-synthesis rev-parent root-lang 40
                                        :decompositions (list bad-decomp)
                                        :debug-p t)))
             (resume-synthesis job 2000)
             (check (= 1 (length (synthesis-job-nogoods job))))
             (let ((ng (first (synthesis-job-nogoods job))))
               (check (nogood-clause-p ng))
               (check (eq :lift-incompatible-rows (nogood-clause-kind ng)))
               (check (equal '((0 0) (1 0)) (nogood-clause-keys ng)))
               (check (equal '(1) (nogood-clause-known ng)))
               (check (equal (app (op := :int) (var 0 :int) (lit :int 1))
                             (nogood-clause-clause-expr ng)))))))
    (clear-function-definitions)))


;;; ===========================================================================
;;; Milestone R5: Phase 4 (Homoiconic Higher-Order AU & Library Learning)
;;; ===========================================================================

(deftest recursion-r5-higher-order-au-and-library-discovery
  "Synthesize the R4 unary recursive corpus (`copy`, `inc-all`, `double-all`, `sum`, `length`, `product`)
de novo, then run `discover-library-abstractions` to automatically discover and register
`:fa` (`:map`) and `:fb` (`:foldr`), refactor the corpus, and verify DL compression and VM equivalence."
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (xs (var 0 seq-type))
              (unary-code (code-type '((0 . :int)) :int))
              (binary-code (code-type '((0 . :int) (1 . :int)) :int))
              (seq-ops (list (op :cons :int) (op :at seq-type) (op :tail :int)
                             (op := seq-type) (op :if seq-type)
                             (op :+ :int) (op :* :int)))
              (int-ops (list (op :at seq-type) (op :tail :int)
                             (op := seq-type) (op :if :int)
                             (op :+ :int) (op :* :int)))
              (corpus nil))
         (flet ((synth (name target ops lits rows)
                  (clear-function-definitions)
                  (let* ((frame (simple-frame target inputs rows))
                         (lang (make-language :int inputs
                                              :operators ops
                                              :literals lits
                                              :constants (list (lit seq-type '()))))
                         (job (start-recursive-synthesis frame lang 90 :self-name :fa)))
                    (resume-synthesis job 50000 :stop-on-first t)
                    (check (synthesis-job-best job))
                    (let ((expr (candidate-expression (synthesis-job-best job))))
                      (push (list :name name
                                  :inputs inputs
                                  :return-type target
                                  :body expr
                                  :self-name :fa)
                            corpus)))))
           (synth :copy seq-type seq-ops nil
                  '(((() ) ()) (((3)) (3)) (((1 3)) (1 3)) (((4 1 3)) (4 1 3))))
           (synth :inc-all seq-type seq-ops '(1)
                  '(((() ) ()) (((2)) (3)) (((5 2)) (6 3)) (((0 5 2)) (1 6 3))))
           (synth :double-all seq-type seq-ops '(2)
                  '(((() ) ()) (((3)) (6)) (((4 3)) (8 6)) (((1 4 3)) (2 8 6))))
           (synth :sum :int int-ops nil
                  '(((() ) 0) (((4)) 4) (((3 4)) 7) (((2 3 4)) 9)))
           (synth :length :int (list (op :at seq-type) (op :tail :int)
                                     (op := seq-type) (op :if :int) (op :+ :int))
                  '(1)
                  '(((() ) 0) (((7)) 1) (((5 7)) 2) (((9 5 7)) 3)))
           (synth :product :int int-ops nil
                  '(((() ) 1) (((3)) 3) (((2 3)) 6) (((4 2 3)) 24))))
         (setf corpus (nreverse corpus))
         (clear-function-definitions)
         (let ((ledger (make-ledger)))
           (multiple-value-bind (accepted refactored all-candidates out-ledger)
               (discover-library-abstractions corpus :register-p t :ledger ledger)
             (check (eq ledger out-ledger))
             (check (plusp (ledger-total ledger)))
             (check (= 2 (length accepted)))
             (check (= 6 (length refactored)))
             (check (>= (length all-candidates) 2))

             ;; 1. Verify discovered :FA is :MAP
             (let ((map-abs (first accepted))
                   (map-def (find-function-definition :fa))
                   (f-var (var 1 unary-code)))
               (check (library-abstraction-p map-abs))
               (check (eq :fa (library-abstraction-name map-abs)))
               (check (eq map-def (library-abstraction-definition map-abs)))
               (check (equal (list (cons 0 seq-type) (cons 1 unary-code))
                             (library-abstraction-inputs map-abs)))
               (check (equal seq-type (library-abstraction-return-type map-abs)))
               (check (equal '(:copy :inc-all :double-all)
                             (library-abstraction-programs map-abs)))
               (check (equal '(1) (function-definition-conditional-code-params map-def)))
               (check (equal (app (op :if seq-type)
                                  (app (op := seq-type) xs (lit seq-type '()))
                                  (lit seq-type '())
                                  (app (op :cons :int)
                                       (app (op :code-eval unary-code) f-var
                                            (app (op :at seq-type) xs (lit :int 0)))
                                       (app (op :fa) (app (op :tail :int) xs) f-var)))
                             (library-abstraction-body map-abs)))
               (check-codec-roundtrip (library-abstraction-body map-abs)
                                      (library-abstraction-inputs map-abs))
               (check (< (library-abstraction-refactored-bits map-abs)
                         (library-abstraction-original-bits map-abs)))
               (check (= 98 (library-abstraction-gain map-abs)))
               (check (plusp (library-abstraction-work map-abs))))

             ;; 2. Verify discovered :FB is :FOLDR
             (let ((fold-abs (second accepted))
                   (fold-def (find-function-definition :fb))
                   (init-var (var 1 :int))
                   (step-var (var 2 binary-code)))
               (check (library-abstraction-p fold-abs))
               (check (eq :fb (library-abstraction-name fold-abs)))
               (check (eq fold-def (library-abstraction-definition fold-abs)))
               (check (equal (list (cons 0 seq-type) (cons 1 :int) (cons 2 binary-code))
                             (library-abstraction-inputs fold-abs)))
               (check (eq :int (library-abstraction-return-type fold-abs)))
               (check (equal '(:sum :length :product)
                             (library-abstraction-programs fold-abs)))
               (check (equal '(2) (function-definition-conditional-code-params fold-def)))
               (check (equal (app (op :if :int)
                                  (app (op := seq-type) xs (lit seq-type '()))
                                  init-var
                                  (app (op :code-eval binary-code) step-var
                                       (app (op :at seq-type) xs (lit :int 0))
                                       (app (op :fb) (app (op :tail :int) xs) init-var step-var)))
                             (library-abstraction-body fold-abs)))
               (check-codec-roundtrip (library-abstraction-body fold-abs)
                                      (library-abstraction-inputs fold-abs))
               (check (< (library-abstraction-refactored-bits fold-abs)
                         (library-abstraction-original-bits fold-abs)))
               (check (= 1 (library-abstraction-gain fold-abs)))
               (check (plusp (library-abstraction-work fold-abs))))

             ;; 3. Verify all 6 refactored definitions: totality, codec roundtrip, and VM execution
             (destructuring-bind (copy-def inc-def dbl-def sum-def len-def prd-def) refactored
               (dolist (rdef refactored)
                 (check (function-definition-total-p rdef))
                 (check (provably-total-p (function-definition-body rdef)))
                 (check-codec-roundtrip (function-definition-body rdef)
                                        (function-definition-inputs rdef)))
               ;; Exact refactored AST bodies
               (check (equal (app (op :fa) xs (lit unary-code (var 0 :int)))
                             (function-definition-body copy-def)))
               (check (equal (app (op :fa) xs
                                  (lit unary-code (app (op :+ :int) (var 0 :int) (lit :int 1))))
                             (function-definition-body inc-def)))
               (check (equal (app (op :fa) xs
                                  (lit unary-code (app (op :+ :int) (var 0 :int) (var 0 :int))))
                             (function-definition-body dbl-def)))
               (check (equal (app (op :fb) xs (lit :int 0)
                                  (lit binary-code (app (op :+ :int) (var 0 :int) (var 1 :int))))
                             (function-definition-body sum-def)))
               (check (equal (app (op :fb) xs (lit :int 0)
                                  (lit binary-code (app (op :+ :int) (var 1 :int) (lit :int 1))))
                             (function-definition-body len-def)))
               (check (equal (app (op :fb) xs (lit :int 1)
                                  (lit binary-code (app (op :* :int) (var 0 :int) (var 1 :int))))
                             (function-definition-body prd-def)))
               ;; Held-out VM evaluation
               (check (equal '() (result (function-definition-body copy-def) inputs '(()))))
               (check (equal '(9 -3 4 12) (result (function-definition-body copy-def) inputs '((9 -3 4 12)))))
               (check (equal '(10 -2 5 13) (result (function-definition-body inc-def) inputs '((9 -3 4 12)))))
               (check (equal '(18 -6 8 24) (result (function-definition-body dbl-def) inputs '((9 -3 4 12)))))
               (check (= 0 (result (function-definition-body sum-def) inputs '(()))))
               (check (= 22 (result (function-definition-body sum-def) inputs '((9 -3 4 12)))))
               (check (= 0 (result (function-definition-body len-def) inputs '(()))))
               (check (= 4 (result (function-definition-body len-def) inputs '((9 -3 4 12)))))
               (check (= 1 (result (function-definition-body prd-def) inputs '(()))))
               (check (= -1296 (result (function-definition-body prd-def) inputs '((9 -3 4 12)))))))))
    (clear-function-definitions)))

(deftest recursion-r5-controls-outliers-and-ledger-accounting
  "Verify negative DL gain rejection, resilience to unrelated outlier definitions in the same
signature group, multi-function fold extension (`sum-squares`), order-independence of subterm
covers, and `:register-p nil` dry-run isolation."
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (xs (var 0 seq-type))
              (unary-code (code-type '((0 . :int)) :int))
              (binary-code (code-type '((0 . :int) (1 . :int)) :int))
              (head-x0 (app (op :at seq-type) xs (lit :int 0)))
              (tail-x0 (app (op :tail :int) xs)))
         ;; Register distinct recursive functions :fa..:fg
         (let ((copy-def
                 (define-function :fa inputs seq-type
                   (lambda (self)
                     (app (op :if seq-type)
                          (app (op := seq-type) xs (lit seq-type '()))
                          (lit seq-type '())
                          (app (op :cons :int) head-x0 (app self tail-x0))))))
               (inc-def
                 (define-function :fb inputs seq-type
                   (lambda (self)
                     (app (op :if seq-type)
                          (app (op := seq-type) xs (lit seq-type '()))
                          xs
                          (app (op :cons :int)
                               (app (op :+ :int) head-x0 (lit :int 1))
                               (app self tail-x0))))))
               (dbl-def
                 (define-function :fc inputs seq-type
                   (lambda (self)
                     (app (op :if seq-type)
                          (app (op := seq-type) xs (lit seq-type '()))
                          xs
                          (app (op :cons :int)
                               (app (op :+ :int) head-x0 head-x0)
                               (app self tail-x0))))))
               (sum-def
                 (define-function :fd inputs :int
                   (lambda (self)
                     (app (op :if :int)
                          (app (op := seq-type) xs (lit seq-type '()))
                          (lit :int 0)
                          (app (op :+ :int) head-x0 (app self tail-x0))))))
               (len-def
                 (define-function :fe inputs :int
                   (lambda (self)
                     (app (op :if :int)
                          (app (op := seq-type) xs (lit seq-type '()))
                          (lit :int 0)
                          (app (op :+ :int) (app self tail-x0) (lit :int 1))))))
               (prd-def
                 (define-function :ff inputs :int
                   (lambda (self)
                     (app (op :if :int)
                          (app (op := seq-type) xs (lit seq-type '()))
                          (lit :int 1)
                          (app (op :* :int) head-x0 (app self tail-x0))))))
               (sumsq-def
                 (define-function :fg inputs :int
                   (lambda (self)
                     (app (op :if :int)
                          (app (op := seq-type) xs (lit seq-type '()))
                          (lit :int 0)
                          (app (op :+ :int)
                               (app (op :* :int) head-x0 head-x0)
                               (app self tail-x0))))))
               ;; Non-recursive outlier of the same signature ((0 . (:seq :int))) -> (:seq :int)
               (tail-outlier
                 (list :name :tail-or-empty
                       :inputs inputs
                       :return-type seq-type
                       :body (app (op :if seq-type)
                                  (app (op := seq-type) xs (lit seq-type '()))
                                  (lit seq-type '())
                                  tail-x0))))

           ;; 1. Negative control: a single definition cannot form a library abstraction
           (multiple-value-bind (accepted refactored all-cands ledger)
               (discover-library-abstractions (list sum-def) :register-p nil)
             (declare (ignore ledger))
             (check (null accepted))
             (check (null all-cands))
             (check (= 1 (length refactored))))

           ;; 2. Negative control: 2 small fold functions (`sum` + `product`) have negative net gain (-30 bits)
           ;;    so `discover-library-abstractions` rejects the candidate under `:min-gain 0`.
           (let ((ledger (make-ledger)))
             (multiple-value-bind (accepted refactored all-cands)
                 (discover-library-abstractions (list sum-def prd-def)
                                                :register-p nil
                                                :min-gain 0
                                                :ledger ledger)
               (check (null accepted))
               (check (= 1 (length all-cands)))
               (check (< (library-abstraction-gain (first all-cands)) 0))
               (check (= -30 (library-abstraction-gain (first all-cands))))
               (check (equal (function-definition-body sum-def)
                             (function-definition-body (first refactored))))
               (check (plusp (cdr (assoc :anti-unification (ledger-counts ledger)))))
               (check (plusp (cdr (assoc :matching (ledger-counts ledger)))))
               (check (plusp (cdr (assoc :construction (ledger-counts ledger)))))))

           ;; 3. Order-independence: placing `len-def` (which omits `(at X0 '0)`) before `sum-def`
           ;;    still orders `(at X0 '0)` as X0 and `(:self (tail X0))` as X1 in the `:code` parameter.
           (let ((reordered-abs
                   (abstract-function-bodies
                    (list (function-definition-body len-def)
                          (function-definition-body sum-def)
                          (function-definition-body prd-def))
                    inputs :int
                    :self-names '(:fe :fd :ff)
                    :program-names '(:len :sum :prd)
                    :target-name :fb
                    :register-p nil)))
             (check (library-abstraction-p reordered-abs))
             (check (plusp (library-abstraction-gain reordered-abs)))
             (check (equal (list (lit binary-code (app (op :+ :int) (var 1 :int) (lit :int 1)))
                                 (lit binary-code (app (op :+ :int) (var 0 :int) (var 1 :int)))
                                 (lit binary-code (app (op :* :int) (var 0 :int) (var 1 :int))))
                           (mapcar #'fourth (library-abstraction-refactored-bodies reordered-abs))))
             ;; `:register-p nil` must not clobber the existing `:fb` (`inc-def`) in `*function-definitions*`
             (check (eq inc-def (find-function-definition :fb))))

           ;; 4. Outlier resilience & 4-function fold corpus (`sum`, `len`, `prd`, `sumsq`)
           (clear-function-definitions)
           (multiple-value-bind (accepted refactored all-cands ledger)
               (discover-library-abstractions
                (list copy-def tail-outlier inc-def dbl-def sum-def len-def prd-def sumsq-def)
                :register-p t)
             (declare (ignore all-cands))
             (check (plusp (ledger-total ledger)))
             (check (= 2 (length accepted)))
             (let ((map-abs (first accepted))
                   (fold-abs (second accepted)))
               ;; `tail-outlier` is excluded from `:map`, leaving (:fa :fb :fc)
               (check (equal '(:fa :fb :fc) (library-abstraction-programs map-abs)))
               (check (= 98 (library-abstraction-gain map-abs)))
               ;; `tail-outlier` (index 1 in refactored) retains its original unfactored body
               (check (equal (getf tail-outlier :body)
                             (function-definition-body (nth 1 refactored))))
               ;; All 4 fold functions (:fd :fe :ff :fg) are factored into `:fb` (`:foldr`) with positive gain
               (check (equal '(:fd :fe :ff :fg) (library-abstraction-programs fold-abs)))
               (check (> (library-abstraction-gain fold-abs) 50))
               (let ((ref-sumsq (function-definition-body (nth 7 refactored))))
                 (check (provably-total-p ref-sumsq))
                 (check-codec-roundtrip ref-sumsq inputs)
                 (check (equal (app (op :fb) xs (lit :int 0)
                                    (lit binary-code
                                         (app (op :+ :int)
                                              (app (op :* :int) (var 0 :int) (var 0 :int))
                                              (var 1 :int))))
                               ref-sumsq))
                 (check (= 30 (result ref-sumsq inputs '((1 2 3 4))))))))

           ;; 5. `:rewrite-library` normalization before anti-unification (over finite field GF(5))
           (clear-function-definitions)
           (call-with-temporary-function-names
            '(:fa)
            (lambda ()
              (let* ((gf5 (gf 5))
                     (gf5-seq (sequence-type gf5))
                     (gf5-inputs (list (cons 0 gf5-seq)))
                     (gf5-xs (var 0 gf5-seq))
                     (gf5-head (app (op :at gf5) gf5-xs (lit :int 0)))
                     (gf5-tail (app (op :tail gf5) gf5-xs))
                     (gf5-self (op :fa (code-type gf5-inputs gf5-seq)))
                     (v-add-zero (start-law-validation
                                  (make-law gf5 (list (cons 0 gf5))
                                            (app (op :+ gf5) (var 0 gf5) (lit gf5 0))
                                            (var 0 gf5))))
                     (_ (resume-law-validation v-add-zero 100000))
                     (rw-lib (prepare-rewrite-library (list v-add-zero) gf5))
                     (gf5-copy
                       (list :name :gf5-copy :inputs gf5-inputs :return-type gf5-seq :self-name :fa
                             :body (app (op :if gf5-seq)
                                        (app (op := gf5-seq) gf5-xs (lit gf5-seq '()))
                                        (lit gf5-seq '())
                                        (app (op :cons gf5) gf5-head (app gf5-self gf5-tail)))))
                     (gf5-inc-unsimplified
                       (list :name :gf5-inc :inputs gf5-inputs :return-type gf5-seq :self-name :fa
                             :body (app (op :if gf5-seq)
                                        (app (op := gf5-seq) gf5-xs (lit gf5-seq '()))
                                        gf5-xs
                                        (app (op :cons gf5)
                                             (app (op :+ gf5) gf5-head
                                                  (app (op :+ gf5) (lit gf5 1) (lit gf5 0)))
                                             (app gf5-self gf5-tail)))))
                     (gf5-dbl
                       (list :name :gf5-dbl :inputs gf5-inputs :return-type gf5-seq :self-name :fa
                             :body (app (op :if gf5-seq)
                                        (app (op := gf5-seq) gf5-xs (lit gf5-seq '()))
                                        gf5-xs
                                        (app (op :cons gf5)
                                             (app (op :+ gf5) gf5-head gf5-head)
                                             (app gf5-self gf5-tail)))))
                     (ledger (make-ledger)))
                (declare (ignore _))
                (check (eq :validated (law-validation-status v-add-zero)))
                (multiple-value-bind (accepted refactored)
                    (discover-library-abstractions (list gf5-copy gf5-inc-unsimplified gf5-dbl)
                                                   :rewrite-library rw-lib
                                                   :register-p t
                                                   :ledger ledger)
                  (check (= 1 (length accepted)))
                  (check (plusp (cdr (assoc :rewriting (ledger-counts ledger)))))
                  ;; `(+ '1 '0)` in `gf5-inc-unsimplified` was rewritten to `'1`, so its refactored
                  ;; `:code` argument is `'(+ X0 '1)` instead of `'(+ X0 (+ '1 '0))`
                  (check (equal (app (op :fa) gf5-xs
                                     (lit (code-type (list (cons 0 gf5)) gf5)
                                          (app (op :+ gf5) (var 0 gf5) (lit gf5 1))))
                                (function-definition-body (second refactored)))))))))

           ;; 6. Tail-recursive `foldl` higher-order library discovery (`sum-acc`, `prod-acc`, `diff-acc`)
           ;;    plus inverted guard orientation `(= '() X0)` and `:register-p nil` state hygiene
           (clear-function-definitions)
           (let* ((acc-inputs (list (cons 0 seq-type) (cons 1 :int)))
                  (acc-var (var 1 :int))
                  (sum-acc (define-function :fa acc-inputs :int
                             (lambda (self)
                               (app (op :if :int)
                                    (app (op := seq-type) xs (lit seq-type '()))
                                    acc-var
                                    (app self tail-x0 (app (op :+ :int) acc-var head-x0))))))
                  (prod-acc (define-function :fb acc-inputs :int
                              (lambda (self)
                                ;; Inverted guard `(= '() X0)` canonicalizes to `(= X0 '())`
                                (app (op :if :int)
                                     (app (op := seq-type) (lit seq-type '()) xs)
                                     acc-var
                                     (app self tail-x0 (app (op :* :int) acc-var head-x0))))))
                  (diff-acc (define-function :fc acc-inputs :int
                              (lambda (self)
                                (app (op :if :int)
                                     (app (op := seq-type) xs (lit seq-type '()))
                                     acc-var
                                     (app self tail-x0 (app (op :- :int) acc-var head-x0)))))))
             (clear-function-definitions)
             ;; `:register-p nil` must not leak `:fa` into `*registered-function-names*`
             (multiple-value-bind (dry-accepted)
                 (discover-library-abstractions (list sum-acc prod-acc diff-acc) :register-p nil)
               (check (= 1 (length dry-accepted)))
               (check (null *registered-function-names*))
               (check (null (find-function-definition :fa))))
             ;; `:register-p t` registers `:fa` as tail-recursive `:foldl`
             (multiple-value-bind (accepted refactored)
                 (discover-library-abstractions (list sum-acc prod-acc diff-acc) :register-p t)
               (check (= 1 (length accepted)))
               (let ((foldl-abs (first accepted))
                     (foldl-def (find-function-definition :fa))
                     (f-var (var 2 binary-code)))
                 (check (eq :fa (library-abstraction-name foldl-abs)))
                 (check (plusp (library-abstraction-gain foldl-abs)))
                 (check (equal '(2) (function-definition-conditional-code-params foldl-def)))
                 (check (equal (app (op :if :int)
                                    (app (op := seq-type) xs (lit seq-type '()))
                                    acc-var
                                    (app (op :fa) tail-x0
                                         (app (op :code-eval binary-code) f-var acc-var head-x0)
                                         f-var))
                               (library-abstraction-body foldl-abs)))
                 ;; Verify left-fold semantics on non-commutative subtraction:
                 ;; (((10 - 1) - 2) - 3) = 4
                 (let ((ref-diff (function-definition-body (third refactored))))
                   (check (provably-total-p ref-diff))
                   (check-codec-roundtrip ref-diff acc-inputs)
                   (check (= 4 (result ref-diff acc-inputs '((1 2 3) 10))))))))

           ;; 7. Compound shared subterm cover & recursive `:code` totality soundness
           (clear-function-definitions)
           (define-function :fa inputs :int nil :oracle-table '(((() ) . 0)))
           (let* ((inc-head (app (op :+ :int) head-x0 (lit :int 1)))
                  (rec-fa (app (op :fa) tail-x0))
                  (t1 (app (op :+ :int) inc-head rec-fa))
                  (t2 (app (op :* :int) inc-head rec-fa))
                  (cover (shared-subterm-cover (list t1 t2) inputs :self-name :fa)))
             ;; `(+ (at X0 '0) '1)` is kept as a single shared cover unit alongside `(:fa (tail X0))`
             (check (equal (list inc-head rec-fa) cover)))
           ;; A recursive function that substitutes a non-total `:code` literal in its recursive step
           ;; must NOT be marked conditionally total
           (clear-function-definitions)
           (let* ((f-var (var 1 unary-code))
                  (bad-code (lit unary-code (app (op :/ :int) (var 0 :int) (lit :int 0))))
                  (bad-def (define-function :fa (list (cons 0 seq-type) (cons 1 unary-code)) :int
                             (lambda (self)
                               (app (op :if :int)
                                    (app (op := seq-type) xs (lit seq-type '()))
                                    (lit :int 0)
                                    (app (op :+ :int)
                                         (app (op :code-eval unary-code) f-var head-x0)
                                         (app self tail-x0 bad-code)))))))
             (check (null (function-definition-total-p bad-def)))
             (check (null (function-definition-conditional-code-params bad-def))))

           ;; 8. Multi-step `:code-subst` unfolding in `fold-constants` with a `:code` variable binding
           (clear-function-definitions)
           (let* ((f-var (var 2 binary-code))
                  (acc-var (var 1 :int)))
             (define-function :fb (list (cons 0 seq-type) (cons 1 :int) (cons 2 binary-code)) :int
               (lambda (self)
                 (app (op :if :int)
                      (app (op := seq-type) xs (lit seq-type '()))
                      acc-var
                      (app (op :code-eval binary-code) f-var
                           head-x0
                           (app self tail-x0 acc-var f-var)))))
             ;; Adapt 2-arg `:fb` (`foldr`) to a 1-arg `:code` variable `X9` via `:code-subst`:
             ;; `(:code-subst '(+ X0 X1) (tuple X9 'X1))` where `X9 : (:code ((0 . :int) (1 . :int)) :int)`
             (let* ((x9 (var 9 binary-code))
                    (x1-code (lit binary-code (var 1 :int)))
                    (subst-tup-type (tuple-type binary-code binary-code))
                    (adapter (app (op :code-subst (tuple-type binary-code subst-tup-type binary-code))
                                  (lit binary-code (app (op :+ :int) (var 0 :int) (var 1 :int)))
                                  (app (op :tuple subst-tup-type) x9 x1-code)))
                    (call-expr (app (op :fb) (lit seq-type '(2 3)) (lit :int 0) adapter))
                    (checker-schema (make-schema :inputs (list (cons 9 binary-code)) :target :int))
                    (unfolded (fold-constants call-expr checker-schema)))
               ;; Unfolds across both elements '(2 3), exposing (:code-eval X9 ...) on each step
               (check (not (contains-call-to-p unfolded :fb)))
               (check (contains-call-to-p unfolded :code-eval)))))
    (clear-function-definitions)))

(deftest recursion-r6-library-expander-and-curriculum-sort
  "End-to-end R6 curriculum: discover `:fa` (`:map`) and `:fb` (`:foldr`) from the R4/R5 corpus,
use `library-decompositions` / `library-expander` / `combine-expanders` / `start-heuristic-synthesis`
to solve held-out `:map` (including `:code-subst` outer-variable capture) and `:foldr` tasks,
synthesize `insert` and `sort` de novo, abstract sequence-returning `:foldr`, and synthesize
`sort` through the learned library expander while `:map` is automatically refuted by a leaf nogood."
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (xs (var 0 seq-type))
              (seq-fold-code (code-type (list (cons 0 :int) (cons 1 seq-type)) seq-type))
              (head-x0 (app (op :at seq-type) xs (lit :int 0)))
              (tail-x0 (app (op :tail :int) xs)))
         (clear-function-definitions)
         ;; 1. Discover :fa (:map) and :fb (:foldr) from the 6-program R4/R5 corpus
         (let* ((copy-body (call-with-temporary-function-names
                            '(:fa)
                            (lambda ()
                              (app (op :if seq-type)
                                   (app (op := seq-type) xs (lit seq-type '()))
                                   (lit seq-type '())
                                   (app (op :cons :int) head-x0 (app (op :fa (code-type inputs seq-type)) tail-x0))))))
                (inc-body (call-with-temporary-function-names
                           '(:fa)
                           (lambda ()
                             (app (op :if seq-type)
                                  (app (op := seq-type) xs (lit seq-type '()))
                                  xs
                                  (app (op :cons :int)
                                       (app (op :+ :int) head-x0 (lit :int 1))
                                       (app (op :fa (code-type inputs seq-type)) tail-x0))))))
                (dbl-body (call-with-temporary-function-names
                           '(:fa)
                           (lambda ()
                             (app (op :if seq-type)
                                  (app (op := seq-type) xs (lit seq-type '()))
                                  xs
                                  (app (op :cons :int)
                                       (app (op :+ :int) head-x0 head-x0)
                                       (app (op :fa (code-type inputs seq-type)) tail-x0))))))
                (sum-body (call-with-temporary-function-names
                           '(:fa)
                           (lambda ()
                             (app (op :if :int)
                                  (app (op := seq-type) xs (lit seq-type '()))
                                  (lit :int 0)
                                  (app (op :+ :int) head-x0 (app (op :fa (code-type inputs :int)) tail-x0))))))
                (len-body (call-with-temporary-function-names
                           '(:fa)
                           (lambda ()
                             (app (op :if :int)
                                  (app (op := seq-type) xs (lit seq-type '()))
                                  (lit :int 0)
                                  (app (op :+ :int) (app (op :fa (code-type inputs :int)) tail-x0) (lit :int 1))))))
                (prd-body (call-with-temporary-function-names
                           '(:fa)
                           (lambda ()
                             (app (op :if :int)
                                  (app (op := seq-type) xs (lit seq-type '()))
                                  (lit :int 1)
                                  (app (op :* :int) head-x0 (app (op :fa (code-type inputs :int)) tail-x0))))))
                (corpus (list (list :name :copy :inputs inputs :return-type seq-type :body copy-body :self-name :fa)
                              (list :name :inc-all :inputs inputs :return-type seq-type :body inc-body :self-name :fa)
                              (list :name :double-all :inputs inputs :return-type seq-type :body dbl-body :self-name :fa)
                              (list :name :sum :inputs inputs :return-type :int :body sum-body :self-name :fa)
                              (list :name :length :inputs inputs :return-type :int :body len-body :self-name :fa)
                              (list :name :product :inputs inputs :return-type :int :body prd-body :self-name :fa))))
           (multiple-value-bind (accepted refactored)
               (discover-library-abstractions corpus :register-p t)
             (declare (ignore refactored))
             (check (= 2 (length accepted)))
             (check (find-function-definition :fa))
             (check (find-function-definition :fb)))

           ;; 2a. Held-out :map task: triple-all(xs) synthesized via start-heuristic-synthesis + library-expander
           (let* ((triple-frame (simple-frame seq-type inputs
                                              '(((() ) ())
                                                (((2)) (6))
                                                (((4 2)) (12 6))
                                                (((-1 3 5)) (-3 9 15)))))
                  (triple-lang (make-language :int inputs
                                              :operators (list (op :fa) (op :* :int) (op :+ :int))
                                              :literals '(3)
                                              :constants (list (lit seq-type '()))))
                  (job (start-heuristic-synthesis triple-frame triple-lang 60)))
             (resume-synthesis job 30000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr inputs)
               (check (expression-calls-operator-p expr :fa))
               (check (equal '() (result expr inputs '(()))))
               (check (equal '(30 0 -15 9) (result expr inputs '((10 0 -5 3)))))))

           ;; 2b. Held-out :map task with outer-variable capture: add-k(xs, k) -> (:fa X0 (:code-subst '(+ X0 X1) (tuple 'X0 X1)))
           (let* ((addk-inputs (list (cons 0 seq-type) (cons 1 :int)))
                  (addk-frame (simple-frame seq-type addk-inputs
                                            '(((() 5) ())
                                              (((3 5) 2) (5 7))
                                              (((1 4) 10) (11 14)))))
                  (addk-lang (make-language :int addk-inputs
                                            :operators (list (op :fa) (op :+ :int))
                                            :literals nil
                                            :constants (list (lit seq-type '()))))
                  (job (start-heuristic-synthesis addk-frame addk-lang 80)))
             (resume-synthesis job 30000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr addk-inputs)
               (check (expression-calls-operator-p expr :fa))
               (check (contains-call-to-p expr :code-subst))
               (check (equal '(17 27 37) (result expr addk-inputs '((10 20 30) 7))))))

           ;; 3. Held-out :foldr task: sum-squares(xs) -> (:fb X0 '0 '(+ X1 (* X0 X0)))
           (let* ((sumsq-frame (simple-frame :int inputs
                                             '(((() ) 0)
                                               (((3)) 9)
                                               (((2 3)) 13)
                                               (((4 2 3)) 29))))
                  (sumsq-lang (make-language :int inputs
                                             :operators (list (op :fb) (op :+ :int) (op :* :int))
                                             :literals nil))
                  (combined-exp (combine-expanders (library-expander)
                                                   (heuristic-expander :library-proposals-p nil)))
                  (job (start-synthesis sumsq-frame sumsq-lang 80
                                        :policy :heuristic
                                        :heuristic-budget 4000
                                        :expand combined-exp
                                        :max-depth 1)))
             (resume-synthesis job 50000 :stop-on-first t)
             (check (synthesis-job-best job))
             (let ((expr (candidate-expression (synthesis-job-best job))))
               (check (provably-total-p expr))
               (check-codec-roundtrip expr inputs)
               (check (expression-calls-operator-p expr :fb))
               (check (= 0 (result expr inputs '(()))))
               (check (= 54 (result expr inputs '((5 -2 4 3)))))))

           ;; 4. Curriculum synthesis of `sort`:
           ;;    4a. Synthesize `:fc` (`insert`) de novo, then synthesize `:fd` (`sort`) de novo using `:fc`.
           ;;    4b. Run `discover-library-abstractions` on `(copy, inc-all, sort)` to discover sequence-`:foldr` (`:fe`).
           ;;    4c. Synthesize `sort` from I/O examples via `start-heuristic-synthesis` where BOTH `:fa` (`:map`)
           ;;        and `:fe` (sequence-`:foldr`) are proposed by `library-decompositions`: `:fa` is refuted by
           ;;        a `:lift-incompatible-rows` nogood clause, while `:fe` cascades via congruence closure and
           ;;        condenses `(:fe X0 '(:fc X0 X1))`.
           (let* ((insert-inputs (list (cons 0 :int) (cons 1 seq-type)))
                  (insert-frame (simple-frame seq-type insert-inputs
                                              '(((2 ()) (2))
                                                ((1 (3)) (1 3))
                                                ((2 (3 5)) (2 3 5))
                                                ((4 (5)) (4 5))
                                                ((4 (2 5)) (2 4 5))
                                                ((3 (4)) (3 4))
                                                ((3 (1 4)) (1 3 4)))))
                  (insert-lang (make-language :int insert-inputs
                                              :operators (list (op :cons :int) (op :at seq-type)
                                                               (op :tail :int) (op :< :int)
                                                               (op := seq-type) (op :if seq-type))
                                              :literals nil
                                              :constants (list (lit seq-type '()))))
                  (insert-job (start-recursive-synthesis insert-frame insert-lang 110 :self-name :fc)))
             (resume-synthesis insert-job 100000 :stop-on-first t)
             (check (synthesis-job-best insert-job))
             (check (function-definition-total-p (find-function-definition :fc)))
             (let* ((sort-frame (simple-frame seq-type inputs
                                              '(((() ) ())
                                                (((2)) (2))
                                                (((3 2)) (2 3))
                                                (((1 3 2)) (1 2 3))
                                                (((4 1 3 2)) (1 2 3 4)))))
                    (de-novo-sort-lang (make-language :int inputs
                                                      :operators (list (op :fc) (op :at seq-type)
                                                                       (op :tail :int) (op := seq-type)
                                                                       (op :if seq-type))
                                                      :literals nil
                                                      :constants (list (lit seq-type '()))))
                    (de-novo-sort-job (start-recursive-synthesis sort-frame de-novo-sort-lang 90 :self-name :fd)))
               (resume-synthesis de-novo-sort-job 50000 :stop-on-first t)
               (check (synthesis-job-best de-novo-sort-job))
               (let ((de-novo-sort-expr (candidate-expression (synthesis-job-best de-novo-sort-job))))
                 (check (provably-total-p de-novo-sort-expr))
                 ;; Discover sequence-returning foldr `:fe` across `(copy, inc-all, sort)`
                 (let ((seq-fold-abs
                         (abstract-function-bodies
                          (list copy-body inc-body de-novo-sort-expr)
                          inputs seq-type
                          :self-names '(:fa :fa :fd)
                          :program-names '(:copy :inc-all :sort)
                          :target-name :fe
                          :register-p t)))
                   (check (library-abstraction-p seq-fold-abs))
                   (check (plusp (library-abstraction-gain seq-fold-abs)))
                   (check (find-function-definition :fe))
                   (check (equal (list (cons 0 seq-type) (cons 1 seq-fold-code))
                                 (library-abstraction-inputs seq-fold-abs)))
                   ;; Now synthesize `sort` directly from `sort-frame` with BOTH `:fa` (`:map`) and `:fe` (`:foldr`)
                   ;; in the language and no de novo self-recursion:
                   (let* ((lib-sort-lang (make-language :int inputs
                                                        :operators (list (op :fa) (op :fe) (op :fc)
                                                                         (op :+ :int))
                                                        :literals '(1)
                                                        :constants (list (lit seq-type '()))))
                          (lib-sort-job (start-heuristic-synthesis sort-frame lib-sort-lang 70 :debug-p t)))
                     (resume-synthesis lib-sort-job 30000 :stop-on-first t)
                     (check (synthesis-job-best lib-sort-job))
                     ;; Verify `:fa` (`:map`) was proposed and refuted with a `:lift-incompatible-rows` nogood clause
                     (check (find-if (lambda (ng)
                                       (and (nogood-clause-p ng)
                                            (eq :lift-incompatible-rows (nogood-clause-kind ng))))
                                     (synthesis-job-nogoods lib-sort-job)))
                     (let ((lib-sort-expr (candidate-expression (synthesis-job-best lib-sort-job))))
                       (check (provably-total-p lib-sort-expr))
                       (check-codec-roundtrip lib-sort-expr inputs)
                       (check (equal (app (op :fe) xs
                                          (lit seq-fold-code
                                               (app (op :fc) (var 0 :int) (var 1 seq-type))))
                                     lib-sort-expr))
                       (check (equal '() (result lib-sort-expr inputs '(()))))
                       (check (equal '(1 2 3 4 5) (result lib-sort-expr inputs '((5 3 1 4 2)))))
                       (check (equal '(-4 -1 0 2 2 8) (result lib-sort-expr inputs '((2 -1 8 -4 2 0)))))))))))))
    (clear-function-definitions)))

(deftest recursion-r6-deductive-nogoods-uip-dip-and-search-trace-condensation
  "Verify Section 5.2 deductive leaf messages:
1. S-expression conflict nogood clauses (`nogood-clause`, `check-parent-nogoods`) and search-work
   reduction with `:deductive-nogoods-p t` vs `:deductive-nogoods-p nil`.
2. UIP anti-unification of conflict S-expressions (`collect-frame-nogood-clauses`,
   `anti-unify-nogood-clauses`, `clause-expr-matches-known-p`).
3. DIP intermediate context variable introduction (`propose-dip-context-bindings`,
   `dip-repaired-decompositions`) solving `add-len(xs)` via `:code-subst`.
4. Lossy branch condensation (`make-search-trace-frame`, `condense-search-heuristic`) inducing an
   S-expression priority predictor `\\hat{\\pi}` deployed via `:priority-predictor`."
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (xs (var 0 seq-type))
              (unary-code (code-type '((0 . :int)) :int))
              (binary-code (code-type '((0 . :int) (1 . :int)) :int))
              (head-x0 (app (op :at seq-type) xs (lit :int 0)))
              (tail-x0 (app (op :tail :int) xs)))
         (clear-function-definitions)
         ;; Register :fa = :map and :fb = :foldr
         (define-function :fa (list (cons 0 seq-type) (cons 1 unary-code)) seq-type
           (lambda (self)
             (app (op :if seq-type)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (lit seq-type '())
                  (app (op :cons :int)
                       (app (op :code-eval unary-code) (var 1 unary-code) head-x0)
                       (app self tail-x0 (var 1 unary-code))))))
         (define-function :fb (list (cons 0 seq-type) (cons 1 :int) (cons 2 binary-code)) :int
           (lambda (self)
             (app (op :if :int)
                  (app (op := seq-type) xs (lit seq-type '()))
                  (var 1 :int)
                  (app (op :code-eval binary-code) (var 2 binary-code)
                       head-x0
                       (app self tail-x0 (var 1 :int) (var 2 binary-code))))))

         ;; 1. Search-work comparison: `:deductive-nogoods-p t` vs `:deductive-nogoods-p nil`
         ;;    On a frame with 3 inputs (X0:seq, X1:int, X2:int) where X1 is constant across colliding
         ;;    rows ((1 2) 0 10) -> (2 1) and ((1 3) 0 20) -> (3 1), while the target is (+ (length X0) X2):
         ;;    Several lifted `:map` proposals (with bindings nil, (X1), (+ X1 X1)) share the colliding
         ;;    lifted decoder or uninformative bindings. With `:deductive-nogoods-p t`, the first `:map`
         ;;    conflict records a `:lift-incompatible-rows` nogood and prunes all subsequent sibling `:map`
         ;;    branches during preparation without running `lift-frame` or `fold-constants`!
         (let* ((p-inputs (list (cons 0 seq-type) (cons 1 :int) (cons 2 :int)))
                (p-frame (simple-frame seq-type p-inputs
                                       '((((1 2) 0 10) (11 12))
                                         (((1 3) 0 20) (21 23))
                                         (((4) 0 30) (34)))))
                (p-lang (make-language :int p-inputs
                                       :operators (list (op :fa) (op :+ :int))
                                       :literals nil))
                (c-lang-0 (make-language :int '((0 . :int)) :operators (list (op :+ :int)) :literals '(1 2)))
                (c-lang-1 (make-language :int '((0 . :int) (1 . :int)) :operators (list (op :+ :int)) :literals '(1 2)))
                (map-dec (app (op :fa) xs (var 9 unary-code)))
                (d-map-0 (make-decomposition :name :map-no-bind
                                             :decoder map-dec :child-id 9 :child-type unary-code
                                             :bindings nil :language c-lang-0 :bound 40 :lift-p t))
                (d-map-x1 (make-decomposition :name :map-bind-x1
                                              :decoder map-dec :child-id 9 :child-type unary-code
                                              :bindings (list (cons 1 (var 1 :int)))
                                              :language c-lang-1 :bound 40 :lift-p t))
                (d-map-x1b (make-decomposition :name :map-bind-x1-plus-x1
                                               :decoder map-dec :child-id 9 :child-type unary-code
                                               :bindings (list (cons 1 (app (op :+ :int) (var 1 :int) (var 1 :int))))
                                               :language c-lang-1 :bound 40 :lift-p t))
                (d-map-x2 (make-decomposition :name :map-bind-x2
                                              :decoder map-dec :child-id 9 :child-type unary-code
                                              :bindings (list (cons 1 (var 2 :int)))
                                              :language c-lang-1 :bound 40 :lift-p t))
                (job-with (start-synthesis p-frame p-lang 80
                                           :decompositions (list d-map-0 d-map-x1 d-map-x1b d-map-x2)
                                           :deductive-nogoods-p t))
                (job-without (start-synthesis p-frame p-lang 80
                                              :decompositions (list d-map-0 d-map-x1 d-map-x1b d-map-x2)
                                              :deductive-nogoods-p nil)))
           (resume-synthesis job-with 50000 :stop-on-first t)
           (resume-synthesis job-without 50000 :stop-on-first t)
           (check (synthesis-job-best job-with))
           (check (synthesis-job-best job-without))
           (check (equal (candidate-expression (synthesis-job-best job-with))
                         (candidate-expression (synthesis-job-best job-without))))
           ;; Deductive leaf nogoods prune `:map-bind-x1` and `:map-bind-x1-plus-x1` before `lift-frame`,
           ;; strictly reducing total ledger work while still allowing `:map-bind-x2` (which separates
           ;; the conflicting rows via X2=10 vs X2=20) to succeed!
           (check (< (ledger-total (synthesis-job-ledger job-with))
                     (ledger-total (synthesis-job-ledger job-without))))
           (check (= 2 (count-if (lambda (m)
                                   (and (eq :conflict (message-claim m))
                                        (getf (message-evidence m) :reused-nogood)))
                                 (synthesis-job-messages job-with))))
           (check (zerop (count-if (lambda (m)
                                     (and (eq :conflict (message-claim m))
                                          (getf (message-evidence m) :reused-nogood)))
                                   (synthesis-job-messages job-without)))))

         ;; 2. UIP Anti-Unification of Conflict Clauses (`collect-frame-nogood-clauses` & `anti-unify-nogood-clauses`)
         ;;    On `reverse` with two colliding element pairs ((1 2)->(2 1), (1 3)->(3 1), (4 5)->(5 4), (4 6)->(6 4)),
         ;;    `collect-frame-nogood-clauses` extracts both `(= X0 '1)` and `(= X0 '4)` nogoods, and
         ;;    `anti-unify-nogood-clauses` generalizes them into the UIP pattern `(= X0 ?0)`.
         (let* ((rev-frame (simple-frame seq-type inputs
                                         '((((1 2)) (2 1))
                                           (((1 3)) (3 1))
                                           (((4 5)) (5 4))
                                           (((4 6)) (6 4)))))
                (rev-lang (make-language :int inputs :operators (list (op :fa) (op :+ :int)) :literals '(1)))
                (elem-lang (make-language :int '((0 . :int)) :operators (list (op :+ :int)) :literals '(1)))
                (bad-map (make-decomposition :name :bad-map
                                             :decoder (app (op :fa) xs (var 9 unary-code))
                                             :child-id 9 :child-type unary-code
                                             :language elem-lang :bound 30 :lift-p t))
                (job (start-synthesis rev-frame rev-lang 60 :decompositions (list bad-map))))
           (resume-synthesis job 5000)
           (let* ((nogoods (synthesis-job-nogoods job))
                  (lift-ngs (remove-if-not (lambda (ng) (eq :lift-incompatible-rows (nogood-clause-kind ng)))
                                           nogoods))
                  (uip-ng (find-if (lambda (ng) (eq :uip-clause (nogood-clause-kind ng))) nogoods)))
             (check (= 2 (length lift-ngs)))
             (check (nogood-clause-p uip-ng))
             (check (equal (app (op := :int) (var 0 :int) (hole 0 :int))
                           (nogood-clause-clause-expr uip-ng)))
             (check (clause-expr-matches-known-p (nogood-clause-clause-expr uip-ng)
                                                 '((0 . :int)) '(99) nil)))
           ;; Also verify UIP anti-unification on multi-conjunct projection nogoods:
           ;; `(and (= X0 '0) (= X1 '2))` and `(and (= X0 '0) (= X1 '5))` -> `(and (= X0 '0) (= X1 ?0))`
           (let* ((two-in '((0 . :int) (1 . :int)))
                  (c1 (bool-and (app (op := :int) (var 0 :int) (lit :int 0))
                                (app (op := :int) (var 1 :int) (lit :int 2))))
                  (c2 (bool-and (app (op := :int) (var 0 :int) (lit :int 0))
                                (app (op := :int) (var 1 :int) (lit :int 5))))
                  (ng1 (make-nogood-clause :parent-id 0 :kind :incompatible-rows
                                           :keys '(0 1) :known '(0 2) :child-type :int
                                           :parent-incompatible-p t :clause-expr c1 :parent-clause-expr c1))
                  (ng2 (make-nogood-clause :parent-id 0 :kind :incompatible-rows
                                           :keys '(2 3) :known '(0 5) :child-type :int
                                           :parent-incompatible-p t :clause-expr c2 :parent-clause-expr c2))
                  (ledger (make-ledger)))
             (multiple-value-bind (uip pattern substs)
                 (anti-unify-nogood-clauses (list ng1 ng2) ledger)
               (check (nogood-clause-p uip))
               (check (plusp (ledger-total ledger)))
               (check (= 2 (length substs)))
               (check (equal (bool-and (app (op := :int) (var 0 :int) (lit :int 0))
                                       (app (op := :int) (var 1 :int) (hole 0 :int)))
                             pattern))
               (check (clause-expr-matches-known-p pattern two-in '(0 99) nil))
               (check (not (clause-expr-matches-known-p pattern two-in '(1 99) nil))))))

         ;; 3. DIP Context Variable Introduction (`propose-dip-context-bindings` & `dip-repaired-decompositions`)
         ;;    On `add-len(xs)` (`((10)) -> (11)`, `((10 20)) -> (12 22)`, `((5 10 20)) -> (8 13 23)`),
         ;;    unary `:map` (`:fa`) conflicts on `10 -> 11` vs `10 -> 12` (and `20 -> 22` vs `20 -> 23`).
         ;;    DIP automatically discovers that `(length X0)` separates all conflicting parent row pairs,
         ;;    introduces `(1 . (length X0))` into `bindings`, and synthesizes:
         ;;    `(:fa X0 (:code-subst '(+ X0 X1) (tuple 'X0 (length X0))))`!
         (let* ((addlen-frame (simple-frame seq-type inputs
                                            '(((() ) ())
                                              (((10)) (11))
                                              (((10 20)) (12 22))
                                              (((5 10 20)) (8 13 23)))))
                (addlen-lang (make-language :int inputs
                                            :operators (list (op :fa) (op :length :int) (op :+ :int))
                                            :literals nil
                                            :constants (list (lit seq-type '()))))
                (job (start-heuristic-synthesis addlen-frame addlen-lang 80 :debug-p t)))
           (resume-synthesis job 40000 :stop-on-first t)
           (check (synthesis-job-best job))
           ;; Verify that a `:dip-repair` node introducing `(length X0)` was spawned and solved the task
           (let ((dip-node (find-if (lambda (n)
                                      (and (synthesis-node-proposal n)
                                           (consp (decomposition-name (synthesis-node-proposal n)))
                                           (eq :dip-repair (first (decomposition-name (synthesis-node-proposal n))))))
                                    (synthesis-job-nodes job))))
             (check dip-node)
             (check (equal (list (cons 1 (app (op :length :int) xs)))
                           (decomposition-bindings (synthesis-node-proposal dip-node)))))
           (let ((expr (candidate-expression (synthesis-job-best job))))
             (check (provably-total-p expr))
             (check-codec-roundtrip expr inputs)
             (check (expression-calls-operator-p expr :fa))
             (check (contains-call-to-p expr :code-subst))
             (check (contains-call-to-p expr :length))
             (check (equal '() (result expr inputs '(()))))
             (check (equal '(5 6 7 8) (result expr inputs '((1 2 3 4)))))))

         ;; 4. Lossy Branch Condensations (`make-search-trace-frame` & `condense-search-heuristic`)
         ;;    Package quantitative branch outcomes from explored synthesis jobs into a `trace-frame`,
         ;;    induce an S-expression priority predictor `\\hat{\\pi}` + residual `\\varepsilon` via
         ;;    `condense-search-heuristic`, and deploy both `predictor-fn` and `trace-h-model` (discarding
         ;;    `\\varepsilon`) via `:priority-predictor` on a held-out synthesis task.
         (let* ((t1-frame (simple-frame seq-type inputs
                                        '(((() ) ()) (((1 2)) (2 3)) (((4 5 6)) (5 6 7)))))
                (t2-frame (simple-frame :int inputs
                                        '(((() ) 0) (((2)) 4) (((3 2)) 13) (((1 3 2)) 14))))
                (t-lang (make-language :int inputs
                                       :operators (list (op :fa) (op :fb) (op :+ :int) (op :* :int))
                                       :literals '(0 1)
                                       :constants (list (lit seq-type '()))))
                (j1 (start-heuristic-synthesis t1-frame t-lang 70))
                (j2 (start-heuristic-synthesis t2-frame t-lang 70)))
           (resume-synthesis j1 25000 :stop-on-first t)
           (resume-synthesis j2 25000 :stop-on-first t)
           (let* ((trace-ledger (make-ledger))
                  (trace-frame (make-search-trace-frame (list j1 j2) :ledger trace-ledger)))
             (check (>= (length (frame-rows trace-frame)) 3))
             (check (plusp (ledger-total trace-ledger)))
             (multiple-value-bind (predictor-fn trace-h-model)
                 (condense-search-heuristic trace-frame :ledger trace-ledger)
               (check (functionp predictor-fn))
               (check (heuristic-model-p trace-h-model))
               (check (provably-total-p (heuristic-program trace-h-model)))
               ;; Deploy the condensed predictor function AND the `heuristic-model` directly
               ;; via `:priority-predictor` on a held-out synthesis problem:
               (let* ((held-frame (simple-frame seq-type inputs
                                                '(((() ) ()) (((3 4)) (5 6)) (((10 20)) (12 22)))))
                      (held-lang (make-language :int inputs
                                                :operators (list (op :fa) (op :+ :int))
                                                :literals '(2)
                                                :constants (list (lit seq-type '()))))
                      (job-fn (start-heuristic-synthesis held-frame held-lang 70
                                                         :priority-predictor predictor-fn))
                      (job-ast (start-heuristic-synthesis held-frame held-lang 70
                                                          :priority-predictor trace-h-model)))
                 (resume-synthesis job-fn 25000 :stop-on-first t)
                 (resume-synthesis job-ast 25000 :stop-on-first t)
                 (check (synthesis-job-best job-fn))
                 (check (synthesis-job-best job-ast))
                 (check (equal '(12 22 32)
                               (result (candidate-expression (synthesis-job-best job-fn))
                                       inputs '((10 20 30)))))
                 (check (equal '(12 22 32)
                               (result (candidate-expression (synthesis-job-best job-ast))
                                       inputs '((10 20 30))))))))))
    (clear-function-definitions)))

(deftest recursion-r6-all-elements-in-concert
  "Exercise all novel elements of recursive synthesis, higher-order library discovery,
1-to-many lifting (with step-pair linkage), algebraic requirement propagation, deductive
leaf messaging (nogoods, UIP, DIP), search-trace heuristic condensation, and debug
provenance working together in concert."
  (unwind-protect
       (let* ((seq-type (sequence-type :int))
              (inputs (list (cons 0 seq-type)))
              (xs (var 0 seq-type))
              (unary-code (code-type '((0 . :int)) :int))
              (head-x0 (app (op :at seq-type) xs (lit :int 0)))
              (tail-x0 (app (op :tail :int) xs)))
         (clear-function-definitions)

         ;; 1. Hygiene & retyping checks:
         ;;    - `rename-function-calls` with an unregistered target symbol does not pollute `*registered-function-names*`.
         ;;    - `retype-expr` retypes higher-order `:code` literals across domains (:int -> (:gf 5)).
         (call-with-temporary-function-names
          '(:fa)
          (lambda ()
            (let* ((ctype (code-type inputs seq-type))
                   (expr (app (op :fa ctype) tail-x0))
                   (renamed (rename-function-calls expr :fa :__temp_unregistered__)))
              (check (app-p renamed))
              (check (eq :__temp_unregistered__ (operator-name (first renamed))))
              (check (equal '(:fa) *registered-function-names*)))))
         (check (null *registered-function-names*))
         (let* ((code-lit (lit unary-code (app (op :+ :int) (var 0 :int) (lit :int 7))))
                (gf5 (gf 5))
                (retyped (retype-expr code-lit :int gf5))
                (gf5-code (code-type (list (cons 0 gf5)) gf5)))
           (check (lit-p retyped))
           (check (equal gf5-code (ast-type retyped)))
           (check (equal (app (op :+ gf5) (var 0 gf5) (lit gf5 2))
                         (ast-value retyped))))

         ;; 2. Stage 1: Synthesize recursive base corpus de novo (`copy`, `inc-all`, `double-all`, `sum`, `length`, `product`)
         ;;    and discover/register `:fa` (`:map`) and `:fb` (`:foldr`) via `discover-library-abstractions`.
         (let ((seq-ops (list (op :cons :int) (op :at seq-type) (op :tail :int)
                              (op := seq-type) (op :if seq-type) (op :+ :int)))
               (int-ops (list (op :at seq-type) (op :tail :int)
                              (op := seq-type) (op :if :int) (op :+ :int) (op :* :int)))
               (corpus nil))
           (flet ((synth (name target ops lits rows)
                    (clear-function-definitions)
                    (let* ((frame (simple-frame target inputs rows))
                           (lang (make-language :int inputs
                                                :operators ops
                                                :literals lits
                                                :constants (list (lit seq-type '()))))
                           (job (start-recursive-synthesis frame lang 90 :self-name :fa)))
                      (resume-synthesis job 50000 :stop-on-first t)
                      (check (synthesis-job-best job))
                      (push (list :name name
                                  :inputs inputs
                                  :return-type target
                                  :body (candidate-expression (synthesis-job-best job))
                                  :self-name :fa)
                            corpus))))
             (synth :copy seq-type seq-ops nil
                    '(((() ) ()) (((3)) (3)) (((1 3)) (1 3)) (((4 1 3)) (4 1 3))))
             (synth :inc-all seq-type seq-ops '(1)
                    '(((() ) ()) (((2)) (3)) (((5 2)) (6 3)) (((0 5 2)) (1 6 3))))
             (synth :double-all seq-type seq-ops nil
                    '(((() ) ()) (((3)) (6)) (((4 3)) (8 6)) (((1 4 3)) (2 8 6))))
             (synth :sum :int int-ops nil
                    '(((() ) 0) (((4)) 4) (((3 4)) 7) (((2 3 4)) 9)))
             (synth :length :int (list (op :at seq-type) (op :tail :int)
                                       (op := seq-type) (op :if :int) (op :+ :int))
                    '(1)
                    '(((() ) 0) (((7)) 1) (((5 7)) 2) (((9 5 7)) 3)))
             (synth :product :int int-ops nil
                    '(((() ) 1) (((3)) 3) (((2 3)) 6) (((4 2 3)) 24))))
           (setf corpus (nreverse corpus))
           (clear-function-definitions)
           (multiple-value-bind (accepted refactored)
               (discover-library-abstractions corpus :register-p t)
             (check (= 2 (length accepted)))
             (check (= 6 (length refactored)))
             (check (find-function-definition :fa))
             (check (find-function-definition :fb)))

           ;; Verify 1-to-many `lift-frame` call-site coordinates in `(row-key row)` along unrolled `:fa` call paths
           (let* ((p-frame (simple-frame seq-type inputs
                                         '((((3 5 8)) (4 6 9))
                                           (((5 10)) (6 11)))))
                  (decoder (app (op :fa) xs (var 9 unary-code)))
                  (lifted (lift-frame p-frame decoder 9 unary-code)))
             (check (= 4 (length (frame-rows lifted))))
             ;; Row 0 unrolls ((0 0), (0 1), (0 2)); Row 1 deduplicates x=5 and emits (1 1) for x=10
             (check (equal '((0 0) (0 1) (0 2) (1 1))
                           (mapcar #'row-key (frame-rows lifted)))))

           ;; 3. Stage 2: Build an algebraic propagator library for integer addition/subtraction
           ;;    so Stage B additive residual pullbacks propagate exact child requirements.
           (let* ((prop-lib (prepare-propagator-library (arithmetic-controls :int) (make-ledger)))
                  ;; 4. Stage 3: Run concerted synthesis jobs combining:
                  ;;    - `library-expander` + `heuristic-expander`
                  ;;    - `prop-lib` requirement propagation
                  ;;    - Deductive leaf nogoods, UIP anti-unification, and DIP context repair
                  ;;    Job A: `add-len(xs)` where unary `:fa` (`:map`) hits multiple incompatible-row
                  ;;           conflicts (`10->11` vs `10->12` and `20->22` vs `20->23`), emits nogood
                  ;;           clauses + a UIP generalized clause `(= X0 ?0)`, and triggers DIP to
                  ;;           introduce `(length X0)` and synthesize `(:fa X0 (:code-subst '(+ X0 X1) (tuple 'X0 (length X0))))`.
                  (addlen-frame (simple-frame seq-type inputs
                                              '(((() ) ())
                                                (((10)) (11))
                                                (((10 20)) (12 22))
                                                (((5 10 20)) (8 13 23)))))
                  (addlen-lang (make-language :int inputs
                                              :operators (list (op :fa) (op :length :int) (op :+ :int))
                                              :literals nil
                                              :constants (list (lit seq-type '()))))
                  (job-a (start-heuristic-synthesis addlen-frame addlen-lang 80
                                                    :library prop-lib
                                                    :deductive-nogoods-p t
                                                    :debug-p t))
                  ;;    Job B: `sum-plus-one(xs) = 1 + sum(xs)` where Stage A condenses constant `'1`,
                  ;;           Stage B pulls back through `(+ '1 Z)` using `prop-lib` to propagate exact
                  ;;           singleton requirements `(0, 4, 7, 9)` to the child frame, and the child
                  ;;           lifts through learned `:fb` (`:foldr`) to synthesize `(+ '1 (:fb X0 '0 '(+ X0 X1)))`!
                  (sump1-frame (simple-frame :int inputs
                                             '(((() ) 1)
                                               (((4)) 5)
                                               (((3 4)) 8)
                                               (((2 3 4)) 10))))
                  (sump1-lang (make-language :int inputs
                                             :operators (list (op :fb) (op :+ :int) (op :- :int))
                                             :literals '(0 1)
                                             :constants (list (lit seq-type '()))))
                  (job-b (start-heuristic-synthesis sump1-frame sump1-lang 85
                                                    :library prop-lib
                                                    :deductive-nogoods-p t
                                                    :debug-p t)))
             (resume-synthesis job-a 45000 :stop-on-first t)
             (resume-synthesis job-b 45000 :stop-on-first t)
             (check (synthesis-job-best job-a))
             (check (synthesis-job-best job-b))
             ;; Verify Job A produced leaf nogoods, UIP clause, and DIP repair node
             (check (find-if (lambda (ng) (eq :lift-incompatible-rows (nogood-clause-kind ng)))
                             (synthesis-job-nogoods job-a)))
             (check (find-if (lambda (ng) (eq :uip-clause (nogood-clause-kind ng)))
                             (synthesis-job-nogoods job-a)))
             (check (find-if (lambda (n)
                               (and (synthesis-node-proposal n)
                                    (consp (decomposition-name (synthesis-node-proposal n)))
                                    (eq :dip-repair (first (decomposition-name (synthesis-node-proposal n))))))
                             (synthesis-job-nodes job-a)))
             ;; Verify Job B combined Stage B additive residual with learned `:fb` (`:foldr`)
             (let ((expr-a (candidate-expression (synthesis-job-best job-a)))
                   (expr-b (candidate-expression (synthesis-job-best job-b))))
               (check (provably-total-p expr-a))
               (check (provably-total-p expr-b))
               (check-codec-roundtrip expr-a inputs)
               (check-codec-roundtrip expr-b inputs)
               (check (expression-calls-operator-p expr-a :fa))
               (check (contains-call-to-p expr-a :code-subst))
               (check (expression-calls-operator-p expr-b :fb))
               (check (equal '(14 24 34 44) (result expr-a inputs '((10 20 30 40)))))
               (check (= 101 (result expr-b inputs '((10 20 30 40))))))

             ;; 5. Stage 4: Condense a search-trace heuristic predictor `\hat{\pi}` across `(job-a, job-b)`
             ;;    and deploy it via `:priority-predictor` on a held-out concerted synthesis task,
             ;;    verifying `explain-synthesis-job` debug introspection.
             (let* ((trace-ledger (make-ledger))
                    (trace-frame (make-search-trace-frame (list job-a job-b) :ledger trace-ledger)))
               (multiple-value-bind (predictor-fn trace-h-model)
                   (condense-search-heuristic trace-frame :ledger trace-ledger)
                 (check (functionp predictor-fn))
                 (check (heuristic-model-p trace-h-model))
                 (let* ((held-frame (simple-frame seq-type inputs
                                                  '(((() ) ())
                                                    (((2)) (3))
                                                    (((2 5)) (4 7))
                                                    (((1 2 5)) (4 5 8)))))
                        (held-job (start-heuristic-synthesis held-frame addlen-lang 80
                                                             :library prop-lib
                                                             :priority-predictor trace-h-model
                                                             :deductive-nogoods-p t
                                                             :debug-p t)))
                   (resume-synthesis held-job 45000 :stop-on-first t)
                   (check (synthesis-job-best held-job))
                   (let ((held-expr (candidate-expression (synthesis-job-best held-job)))
                         (report (with-output-to-string (s)
                                   (explain-synthesis-job held-job :stream s))))
                     (check (provably-total-p held-expr))
                     (check-codec-roundtrip held-expr inputs)
                     (check (equal '(8 9 10) (result held-expr inputs '((5 6 7)))))
                     (check (search "Synthesis Job" report))
                     (check (search "DIP-REPAIR" report)))))))))
    (clear-function-definitions)))
