(in-package #:lisploop)

;;; Static totality (ast.lisp): facts established by conditions, per-parameter termination
;;; measures, bindings read through, and totality under a guard.

(defun totality-of (name)
  "The verdict on the defined function NAME, as (total-p conditional-code-params)."
  (let ((definition (find-function-definition name)))
    (list (function-definition-total-p definition)
          (function-definition-conditional-code-params definition))))

(defun certified-p (name)
  (let ((verdict (totality-of name)))
    (or (first verdict) (second verdict))))

(deftest totality-follows-how-much-of-a-sequence-is-known
  "A guard on `(tail^k xs)` proves one element more, so a body may step two at a time and
read as far as it has tested, and no further."
  (with-clean-kernel-state
    (let* ((seq (sequence-type :int))
           (xs (var 0 seq))
           (binary (code-type '((0 . :int) (1 . :int)) :int))
           (f (var 1 binary))
           (one (list (cons 0 seq))))
      ;; Every other element: the second guard licenses the double step.
      (define-function :evens one seq
        (lambda (self)
          (term `(if (= ,xs ()) ()
                     (cons (at ,xs 0)
                           (if (= (tail ,xs) ()) () (,self (tail (tail ,xs))))))
                seq)))
      (check (equal '(t nil) (totality-of :evens)))
      (check (equal '(1 3 5) (result (app (op :evens) (lit seq '(1 2 3 4 5))))))
      ;; Disjoint pairs: reads the second element and steps past both.
      (define-function :pairwise (list (cons 0 seq) (cons 1 binary)) seq
        (lambda (self)
          (term `(if (= ,xs ()) ()
                     (if (= (tail ,xs) ()) ()
                         (cons (code-eval ,f (at ,xs 0) (at (tail ,xs) 0))
                               (,self (tail (tail ,xs)) ,f))))
                seq)))
      (check (equal '(nil (1)) (totality-of :pairwise)))
      (check (equal '(3 7) (result (app (op :pairwise) (lit seq '(1 2 3 4 5))
                                        (lit binary (term `(+ ,(var 0 :int) ,(var 1 :int))))))))
      ;; A length test proves as much as it says.
      (define-function :third-or-zero one :int
        (term `(if (< 2 (length ,xs)) (at ,xs 2) 0) :int))
      (check (equal '(t nil) (totality-of :third-or-zero)))
      (check (= 7 (result (app (op :third-or-zero) (lit seq '(5 6 7 8))))))
      (check (= 0 (result (app (op :third-or-zero) (lit seq '(5 6))))))
      ;; A length compared with a literal the other way round, or for equality, proves as much.
      (define-function :second-unless-short one :int
        (term `(if (< (length ,xs) 2) 0 (at ,xs 1)) :int))
      (check (equal '(t nil) (totality-of :second-unless-short)))
      (define-function :head-unless-empty one :int
        (term `(if (= (length ,xs) 0) 0 (at ,xs 0)) :int))
      (check (equal '(t nil) (totality-of :head-unless-empty)))
      (define-function :sum-of-a-pair one :int
        (term `(if (= (length ,xs) 2) (+ (at ,xs 0) (at ,xs 1)) 0) :int))
      (check (equal '(t nil) (totality-of :sum-of-a-pair)))
      (check (= 9 (result (app (op :sum-of-a-pair) (lit seq '(4 5))))))
      ;; One guard does not license two steps, nor a read of the second element.
      (define-function :skips-unguarded one seq
        (lambda (self)
          (term `(if (= ,xs ()) () (,self (tail (tail ,xs)))) seq)))
      (check (not (certified-p :skips-unguarded)))
      (define-function :reads-unguarded one :int
        (term `(if (= ,xs ()) 0 (at ,xs 1)) :int))
      (check (not (certified-p :reads-unguarded)))
      (define-function :reads-past-length-test one :int
        (term `(if (< 2 (length ,xs)) (at ,xs 3) 0) :int))
      (check (not (certified-p :reads-past-length-test)))
      ;; The facts hold on the branch they were established on, not on the other.
      (define-function :reads-on-the-empty-branch one :int
        (term `(if (= ,xs ()) (at ,xs 0) 0) :int))
      (check (not (certified-p :reads-on-the-empty-branch))))))

(deftest termination-is-measured-parameter-by-parameter
  "Each parameter is compared with the argument in its own place. A measure that some call
lowers and none raises accounts for the calls that lower it; the rest must descend by
another."
  (with-clean-kernel-state
    (let* ((seq (sequence-type :int))
           (xs (var 0 seq))
           (ys (var 1 seq))
           (two (list (cons 0 seq) (cons 1 seq))))
      ;; Merging shrinks one sequence on one branch and the other on the other.
      (define-function :merge two seq
        (lambda (self)
          (term `(if (= ,xs ()) ,ys
                     (if (= ,ys ()) ,xs
                         (if (< (at ,xs 0) (at ,ys 0))
                             (cons (at ,xs 0) (,self (tail ,xs) ,ys))
                             (cons (at ,ys 0) (,self ,xs (tail ,ys))))))
                seq)))
      (check (equal '(t nil) (totality-of :merge)))
      (check (equal '(1 2 3 4 5 9) (result (app (op :merge) (lit seq '(1 4 9)) (lit seq '(2 3 5))))))
      ;; The order is lexicographic: a call that shortens the first sequence may do anything
      ;; to the second, here refill it, as long as every other call shortens the second.
      (define-function :refills two seq
        (lambda (self)
          (term `(if (= ,xs ()) ,ys
                     (if (= ,ys ()) (,self (tail ,xs) (cons 0 ,xs)) (,self ,xs (tail ,ys))))
                seq)))
      (check (equal '(t nil) (totality-of :refills)))
      (check (equal '(0 2) (result (app (op :refills) (lit seq '(1 2)) (lit seq '(7))))))
      ;; The tail of another parameter says nothing of this one: this never returns.
      (define-function :chases-the-other two seq
        (lambda (self)
          (term `(if (= ,ys ()) () (,self (tail ,ys) ,ys)) seq)))
      (check (not (certified-p :chases-the-other)))
      (check (not (eq :value (evaluation-status
                              (evaluate (app (op :chases-the-other) (lit seq '()) (lit seq '(1)))
                                        nil nil :budget 2000)))))
      ;; A parameter that one call shortens and another replaces is no measure.
      (define-function :shortens-then-regrows two seq
        (lambda (self)
          (term `(if (= ,xs ()) ()
                     (if (= ,ys ()) (,self (cons 0 ,xs) (cons 0 ,ys)) (,self (tail ,xs) (tail ,ys))))
                seq)))
      (check (not (certified-p :shortens-then-regrows))))))

(deftest integers-descend-and-ascend-within-a-literal-bound
  (with-clean-kernel-state
    (let* ((seq (sequence-type :int))
           (n (var 0 :int))
           (one '((0 . :int))))
      (flet ((define (name body)
               (define-function name one seq (lambda (self) (term (funcall body self) seq)))
               (certified-p name))
             (run (name value)
               (result (app (op name) (lit :int value)))))
        ;; Down to a lower bound by subtraction, and by halving when the bound is not negative.
        (check (define :count-down (lambda (self) `(if (< 0 ,n) (cons ,n (,self (- ,n 1))) ()))))
        (check (equal '(3 2 1) (run :count-down 3)))
        (check (define :halvings (lambda (self) `(if (< 0 ,n) (cons ,n (,self (/ ,n 2))) ()))))
        (check (equal '(9 4 2 1) (run :halvings 9)))
        ;; Up to an upper bound, as a negative count rising to zero does.
        (check (define :count-up (lambda (self) `(if (< ,n 0) (cons ,n (,self (+ ,n 1))) ()))))
        (check (equal '(-3 -2 -1) (run :count-up -3)))
        ;; The false branch of a bound is a bound too.
        (check (define :count-down-else (lambda (self) `(if (< ,n 1) () (cons ,n (,self (- ,n 1)))))))
        (check (equal '(2 1) (run :count-down-else 2)))
        ;; Not being zero is not a bound: from -1 this descends for ever.
        (check (not (define :from-nonzero (lambda (self) `(if (= ,n 0) () (cons ,n (,self (- ,n 1))))))))
        (check (not (eq :value (evaluation-status
                                (evaluate (app (op :from-nonzero) (lit :int -1)) nil nil :budget 2000)))))
        ;; Truncating division sticks at zero above a negative bound.
        (check (not (define :halves-below-zero (lambda (self) `(if (< -5 ,n) (cons ,n (,self (/ ,n 2))) ())))))
        (check (not (eq :value (evaluation-status
                                (evaluate (app (op :halves-below-zero) (lit :int 4)) nil nil :budget 2000)))))
        ;; Rising with no upper bound, and a parameter that one call lowers and another raises.
        (check (not (define :rises-unbounded (lambda (self) `(if (< 0 ,n) (,self (+ ,n 1)) ())))))
        (check (not (define :down-and-up
                      (lambda (self) `(if (< 0 ,n) (if (< ,n 10) (,self (+ ,n 1)) (,self (- ,n 1))) ())))))
        (check (not (eq :value (evaluation-status
                                (evaluate (app (op :down-and-up) (lit :int 9)) nil nil :budget 2000)))))))))

(deftest a-binding-is-read-through-to-the-self-call-inside-it
  "`code-eval` of literal code is a binding. Where that code is not total by itself the
analysis reads its body with the arguments in place of its parameters, so the self-call
inside is judged where it runs: under the guard that made the fuel non-empty."
  (with-clean-kernel-state
    (let* ((seq (sequence-type :int))
           (step-type (code-type '((0 . :int)) :int))
           (fuel (var 0 seq)) (init (var 1 :int)) (step (var 2 step-type))
           (inputs (list (cons 0 seq) (cons 1 :int) (cons 2 step-type)))
           ;; (let ((next (step init))) (if (= next init) init (fix-seq (tail fuel) next step)))
           (binding (code-type (list (cons 0 :int) (cons 1 :int) (cons 2 seq) (cons 3 step-type)) :int))
           (settle (lit step-type (term `(if (< 3 ,(var 0 :int)) (- ,(var 0 :int) 3) ,(var 0 :int))
                                        :int))))
      (define-function :fix-seq inputs :int
        (lambda (self)
          (term `(if (= ,fuel ()) ,init
                     (code-eval ,(lit binding
                                      (term `(if (= ,(var 0 :int) ,(var 1 :int)) ,(var 1 :int)
                                                 (,self (tail ,(var 2 seq)) ,(var 0 :int)
                                                        ,(var 3 step-type)))
                                            :int))
                                (code-eval ,step ,init) ,init ,fuel ,step))
                :int)))
      ;; Total given total code for its step, which it runs once a round.
      (check (equal '(nil (2)) (totality-of :fix-seq)))
      (check (provably-total-p (app (op :fix-seq) (lit seq '(0 0 0)) (lit :int 10) settle)))
      ;; 10 -> 7 -> 4 -> 1 -> 1: stops at the fixed point, or when the fuel runs out.
      (check (= 1 (result (app (op :fix-seq) (lit seq '(0 0 0 0 0 0)) (lit :int 10) settle))))
      (check (= 4 (result (app (op :fix-seq) (lit seq '(0 0)) (lit :int 10) settle))))
      ;; The same binding around a call that does not shorten the fuel is refused.
      (define-function :spins inputs :int
        (lambda (self)
          (term `(if (= ,fuel ()) ,init
                     (code-eval ,(lit binding
                                      (term `(,self ,(var 2 seq) ,(var 0 :int) ,(var 3 step-type)) :int))
                                (code-eval ,step ,init) ,init ,fuel ,step))
                :int)))
      (check (not (certified-p :spins))))))

(deftest modulus-keeps-an-index-in-range
  "`mod` takes the sign of its divisor, so a count taken modulo a positive length is a
position. Like division it is defined where its divisor is not zero, and total where that
is known."
  (let ((a (var 0 :int)) (n (var 1 :int)))
    (check (= 1 (result (term `(mod 7 3)))))
    (check (= 2 (result (term `(mod -1 3)))))
    (check (= 0 (result (term `(mod 6 3)))))
    (check (eq :error (evaluation-status (evaluate (term `(mod 5 0)) nil nil))))
    (check (provably-total-p (term `(mod ,a 3))))
    (check (not (provably-total-p (term `(mod ,a ,n)))))
    (check (provably-total-p (term `(if (< 0 ,n) (mod ,a ,n) 0) :int)))
    (check (not (provably-total-p (term `(if (< ,n 1) (mod ,a ,n) 0) :int))))))

(deftest a-guard-makes-what-it-guards-total
  "Division is total where the divisor is known not to be zero, whether a condition around
it says so or the guard of the solver whose witness it is."
  (let* ((y (var 0 :int)) (p (var 1 :int))
         (quotient (term `(/ ,y ,p)))
         (guard (bool-not (term `(= ,p 0)))))
    (check (not (provably-total-p quotient)))
    (check (provably-total-p (term `(if (= ,p 0) 0 ,quotient) :int)))
    (check (provably-total-p (term `(if (< 0 ,p) ,quotient 0) :int)))
    (check (not (provably-total-p (term `(if (= ,p 0) ,quotient 0) :int))))
    (check (not (provably-total-p (term `(if (< ,p 1) ,quotient 0) :int))))
    (check (provably-total-given-p quotient guard))
    (check (provably-total-given-p quotient (bool-and (term `(< 0 ,y)) guard)))
    (check (not (provably-total-given-p quotient (lit :bool t))))
    (check (not (provably-total-given-p quotient (bool-not (term `(= ,y 0))))))
    ;; A guard that may itself fail establishes nothing, though it says the divisor is not zero.
    (check (not (provably-total-given-p quotient (bool-and guard (term `(= (/ ,y ,y) 1))))))
    ;; The same over a field.
    (let* ((field (gf 5)) (a (var 0 field)) (b (var 1 field)))
      (check (provably-total-given-p (term `(/ ,a ,b)) (bool-not (term `(= ,b 0)))))))
  ;; So a decoder whose solver divides can price a miss: the solver runs where its guard holds.
  (with-clean-kernel-state
    (let* ((p (var 0 :int)) (y (var 1 :int))
           (solver (register-knowledge-solver :* :domain :int :position 1
                                              :witness (term `(/ ,y ,p))
                                              :guard (bool-not (term `(= ,p 0)))
                                              :unique-p nil)))
      (register-metric-decoder solver)
      (let ((decoder (first (metric-decoders :int))))
        (check (eq :* (operator-name (first decoder))))
        ;; 12 is 3 scaled by 4; 13 is no multiple of 3, and nothing scales 0 to 5.
        (check (eql 4 (metric-delta decoder 3 12 :int (make-ledger))))
        (check (null (metric-delta decoder 3 13 :int (make-ledger))))
        (check (null (metric-delta decoder 0 5 :int (make-ledger))))))
    ;; Without the guard the witness may divide by zero, and the registration is refused.
    (raises (register-metric-decoder
             (register-knowledge-solver :* :domain :int :position 1 :id :unguarded
                                        :witness (term `(/ ,(var 1 :int) ,(var 0 :int)))
                                        :unique-p nil)))))
