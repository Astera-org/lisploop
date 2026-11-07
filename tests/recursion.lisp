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
