(in-package #:lisploop)

;;; ===========================================================================
;;; Closure evaluation: the same status, value, error and work as the VM
;;; ===========================================================================

(defun evaluation-signature (expression inputs values &optional (budget 1000000))
  "What an evaluation of EXPRESSION on VALUES reports after spending at most BUDGET."
  (let ((run (evaluate expression inputs values :budget budget)))
    (list (evaluation-status run) (evaluation-value run) (evaluation-error run)
          (evaluation-work run))))

(defun check-closure-agrees-with-vm (expression inputs values)
  "The closure and the VM report the same thing on VALUES: run to the end, cut off at any
budget, and paid for one unit at a time. Returns the status both report."
  (let* ((interpreted (let ((*closure-evaluation* nil)) (evaluation-signature expression inputs values)))
         (compiled (evaluation-signature expression inputs values))
         (work (fourth interpreted)))
    (check (equal interpreted compiled))
    (dolist (budget (remove-duplicates (list 0 1 (floor work 2) (max 0 (1- work)) work (1+ work))))
      (check (equal (let ((*closure-evaluation* nil))
                      (evaluation-signature expression inputs values budget))
                    (evaluation-signature expression inputs values budget))))
    (let ((stepped (start-evaluation expression inputs values))
          (ledger (make-ledger)))
      (loop while (eq :unknown (evaluation-status stepped))
            do (advance-evaluation stepped 1 ledger))
      (check (= work (ledger-total ledger)))
      (check (equal interpreted (list (evaluation-status stepped) (evaluation-value stepped)
                                      (evaluation-error stepped) (evaluation-work stepped)))))
    (first interpreted)))

(deftest closures-report-what-the-vm-reports
  "Over arithmetic in the integers and in a field, comparisons, conditionals, sequences,
tuples, tables and literal code, on rows that give values, errors and unresolved inputs, an
evaluation by closure is indistinguishable from an interpreted one."
  (let ((statuses nil))
    (flet ((agree (expression inputs rows)
             (check (expression-closure expression inputs))
             (dolist (values rows)
               (pushnew (check-closure-agrees-with-vm expression inputs values) statuses))))
      ;; 1. Every tree of up to two applications over integer arithmetic and conditionals.
      (let* ((inputs '((0 . :int) (1 . :int)))
             (leaves (list (var 0 :int) (var 1 :int) (lit :int 2) (lit :int 0)))
             (operators (list (op :+ :int) (op :* :int) (op :- :int) (op :/ :int)
                              (op :< :int) (op := :int) (op :if :int))))
        (dolist (expression (reference-typed-trees leaves operators 2 inputs))
          (agree expression inputs '((3 -2) (0 0) (-7 5) (:unresolved 1)))))
      ;; 2. A prime field, whose arithmetic has the unit tariff, and one that does not.
      (dolist (field (list (gf 5) (gf 65537)))
        (let* ((inputs (list (cons 0 field) (cons 1 field)))
               (leaves (list (var 0 field) (var 1 field) (lit field 2)))
               (operators (list (op :+ field) (op :* field) (op :/ field))))
          (dolist (expression (reference-typed-trees leaves operators 2 inputs))
            (agree expression inputs '((3 4) (0 0) (1 0))))))
      ;; 3. Sequences, tuples and tables, with the failures each can have.
      (let* ((ints (sequence-type :int))
             (pair (tuple-type :int :int))
             (entry (tuple-type :int ints))
             (inputs (list (cons 0 :int) (cons 1 ints) (cons 2 pair)))
             (x (var 0 :int)) (xs (var 1 ints)) (p (var 2 pair))
             (rows '((1 (5 6 7) (8 9)) (0 () (0 0)) (4 (2) (1 1)) (-1 (3 3) (2 5))
                     (2 :unresolved (0 1)) (:unresolved (1) (1 2)))))
        (dolist (expression
                 (list (term `(if (= ,xs ()) 0 (+ (at ,xs 0) (length (tail ,xs)))))
                       (term `(at ,xs ,x))
                       (term `(tail ,xs))
                       (term `(cons ,x (tail ,xs)))
                       (term `(gather ,xs (cons 0 (cons ,x ()))) ints)
                       (term `(concat (cons ,xs (cons (cons ,x ()) ()))) ints)
                       (term `(member ,x ,xs))
                       (term `(if (< ,x 2) (member ,x ,xs) (= ,xs (cons ,x ()))))
                       (term `(tuple (at ,p 1) (+ ,x (at ,p 0))) pair)
                       (term `(= ,p (tuple ,x (length ,xs))))
                       (app (op :lookup entry) x (lit (sequence-type entry) '((1 (2 0)) (2 (1 1)))))
                       (term `(at (cons ,x ,xs) (at ,p 0)))))
          (agree expression inputs rows)))
      ;; 4. Literal code applied by `:code-eval`, as `compose-model` writes a shared value:
      ;;    a total binding, a partial one, a failing body, and one let inside another.
      (let* ((inputs '((0 . :int) (1 . :int)))
             (x0 (var 0 :int)) (x1 (var 1 :int)) (z (var 9 :int))
             (big (term `(+ (* ,x0 ,x1) (* (+ ,x0 ,x1) (+ ,x0 ,x1)))))
             (partial (term `(/ ,big (- ,x1 ,x0))))
             (shared (let-call (term `(+ (* ,z ,z) ,z)) (list (cons 9 big))))
             (body-type (code-type inputs :int))
             ;; On (0 0) the shared value is 0 and the body that divides by it fails.
             (rows '((6 3) (2 2) (0 -4) (0 0) (1 :unresolved))))
        (check (app-of-p shared :code-eval))
        (dolist (expression
                 (list shared
                       (let-call (term `(+ ,z (* ,z ,z))) (list (cons 9 partial)))
                       ;; `let-call` does not quote a body that can fail; the VM runs one all the same.
                       (app (op :code-eval body-type) (lit body-type (term `(+ (/ ,x1 ,x0) ,x0))) big x1)
                       (term `(+ ,x1 ,(let-call (term `(* ,z ,z)) (list (cons 9 shared)))))))
          (check (expression-calls-operator-p expression :code-eval))
          (agree expression inputs rows))))
    ;; The rows above exercised every way an evaluation can end.
    (check (same-set-p '(:value :error :unresolved) statuses))))

(deftest closures-decline-what-they-cannot-reproduce
  "An expression that calls a function or a symbolic operator, evaluates code that is not a
literal, or is ill typed has no closure and runs in the VM, as do values that do not fit
their inputs; and a closure is found again whatever scope it was last compiled in."
  (with-clean-kernel-state
    (let* ((inputs '((0 . :int)))
           (x (var 0 :int))
           (code (code-type inputs :int))
           (quoted (lit code (term `(+ ,x 1)))))
      (define-function :twice inputs :int (term `(+ ,x ,x)))
      (dolist (expression (list (term `(+ 1 (twice ,x)))
                                (app (op :code-kind code) quoted)
                                (term `(code-eval ,(var 1 code) ,x))
                                (app (op :+ :int) x (lit :bool t))))
        (check (null (expression-closure expression (list (cons 0 :int) (cons 1 code))))))
      ;; A caller that charges a fixed cost keeps literal code out of its closures.
      (let ((shared (let-call (term `(* ,(var 9 :int) ,(var 9 :int))) (list (cons 9 (term `(+ ,x 1)))))))
        (check (expression-closure shared inputs))
        (check (null (compile-ast-fn shared inputs)))
        (check (compile-ast-fn (term `(+ ,x 1)) inputs)))
      (check (= 9 (result (term `(+ 1 (twice ,x))) inputs '(4))))
      (check (= 5 (result (term `(code-eval ,(var 1 code) ,x)) (list (cons 0 :int) (cons 1 code))
                          (list 4 (term `(+ ,x 1))))))
      ;; Values of the wrong type or number are the VM's to report, with its own work.
      (let ((sum (term `(+ ,x 1))))
        (check (expression-closure sum inputs))
        (dolist (values '((t) (1 2) ()))
          (check (equal (let ((*closure-evaluation* nil)) (evaluation-signature sum inputs values))
                        (evaluation-signature sum inputs values)))
          (check (eq :error (first (evaluation-signature sum inputs values))))))
      ;; One expression in two scopes, alternately, and with room for two closures only.
      (let ((sum (term `(+ ,x ,(var 1 :int))))
            (narrow '((0 . :int) (1 . :int)))
            (wide '((2 . :int) (1 . :int) (0 . :int)))
            (*closure-limit* 2))
        (dotimes (round 3)
          (check (= 7 (result sum narrow '(3 4))))
          (check (= 9 (result sum wide '(0 4 5))))
          (check-closure-agrees-with-vm sum narrow '(3 4))
          (check-closure-agrees-with-vm sum wide '(0 4 5)))))))

(deftest search-is-the-same-job-with-and-without-closures
  "An exact search and an observation search charge the same work to the same categories,
find the same candidates and report the same counterexamples whether rows are evaluated by
closure or interpreted, row budget and one-unit steps included."
  (let* ((field (gf 5))
         (inputs (list (cons 0 field) (cons 1 field)))
         (a (var 0 field)) (b (var 1 field))
         (oracle (term `(+ ,a (* ,b (+ ,b 2)))))
         (frame (simple-frame field inputs
                              (loop for x below 5 append
                                (loop for y below 5
                                      collect (list (list x y) (result oracle inputs (list x y)))))))
         (language (make-language field inputs))
         (bound (description-size oracle inputs))
         (partial (make-language :int '((0 . :int) (1 . :int))
                                 :operators (list (op :+ :int) (op :/ :int)) :literals '(1)))
         (partial-frame (simple-frame :int '((0 . :int) (1 . :int)) '(((4 2) 3) ((6 0) 7) ((9 3) 4)))))
    (flet ((search-view (closures-p frame language bound &rest keys)
             (let* ((*closure-evaluation* closures-p)
                    (job (apply #'start-search frame language keys)))
               (resume-search job bound 100000000)
               (list (canonical-ledger-alist (search-job-ledger job))
                     (mapcar #'candidate-expression (search-job-results job))
                     (mapcar #'candidate-run-work (search-job-results job))
                     (search-job-rejected job)
                     (loop for message in (search-job-messages job)
                           when (eq :counterexample (message-claim message))
                             collect (message-evidence message)))))
           (observation-view (closures-p)
             (let* ((*closure-evaluation* closures-p)
                    (job (start-observation-search (make-observation-scope frame language)
                                                   :retain-outcomes t)))
               (resume-observation-search job (- bound 12) 100000000)
               (list (canonical-ledger-alist (observation-job-ledger job))
                     (loop for record in (observation-job-records job)
                           collect (list (observed-expression-expression record)
                                         (observed-expression-status record)
                                         (observed-expression-values record)
                                         (observed-expression-run-work record)))))))
      (check (equal (search-view nil frame language bound) (search-view t frame language bound)))
      (check (member oracle (second (search-view t frame language bound)) :test #'equal))
      ;; Division makes rows fail, and a small row budget cuts evaluations off.
      (dolist (keys '((:diagnostics t) (:diagnostics t :row-budget 30) (:row-budget 12)))
        (check (equal (apply #'search-view nil partial-frame partial 70 keys)
                      (apply #'search-view t partial-frame partial 70 keys))))
      (check (equal (observation-view nil) (observation-view t)))
      ;; Resumption at every budget is the contract of the job, closures or not.
      (check-search-resumption (lambda () (start-search partial-frame partial :diagnostics t :row-budget 30))
                               60 :exhaustive-p t))))
