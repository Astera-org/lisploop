(in-package #:lisploop2)

;;; Contracts of the synthesizer (Stage B): each row of the refinement table finds what it should
;;; from plain rows, every program returned is confirmed by the evaluator, a conditional is
;;; accepted only in size order, and a task whose rows do not determine an answer is reported
;;; as such and not answered.

(defmacro with-fresh-library (&body body)
  `(let ((*library* '()) (*solvers* '())) ,@body))

(defun solved-program (name params returns rows &rest keys)
  "Solve the task and return its program, having checked that the evaluator confirms it."
  (let* ((task (read-task name params returns rows))
         (outcome (apply #'solve-task task keys)))
    (values (and (eq :solved (outcome-status outcome))
                 (fits-rows-p (outcome-program outcome) task (task-rows task))
                 (outcome-program outcome))
            outcome task)))

(defun run-on (program task &rest inputs)
  (values (run-term program (loop for v in (task-params task) for value in inputs
                                  collect (cons (term-head v) value)))))

(deftest test-leaf-and-tabulate
  (with-fresh-library
    ;; a leaf of the context is found without any search
    (check-equal 'x0 (term->sexp (solved-program 'same '((x0 (:seq :int))) '(:seq :int)
                                                 '(((()) ()) (((3)) (3)) (((1 3)) (1 3))))))
    ;; a position-wise function is a tabulate: the length on the rows, the element on positions
    (multiple-value-bind (program outcome task)
        (solved-program 'add-k '((x0 (:seq :int)) (x1 :int)) '(:seq :int)
                        '(((() 2) ()) (((3) 1) (4)) (((1 3) 5) (6 8)) (((4 1 3) 0) (4 1 3)) (((2 2) 7) (9 9))))
      (check program)
      (check (plusp (outcome-evidence outcome)))
      (check-equal (vector 15 6 9) (run-on program task (vector 10 1 4) 5)))))

(deftest test-select-and-where
  (with-fresh-library
    ;; elements kept by a test: no alignment of output to input is computed
    (multiple-value-bind (program outcome task)
        (solved-program 'above '((x0 (:seq :int)) (x1 :int)) '(:seq :int)
                        '(((() 1) ()) (((3) 1) (3)) (((-2 3) 0) (3)) (((4 -2 3) 3) (4)) (((5 1 7 2) 2) (5 7))
                          (((1 2 3) 0) (1 2 3)) (((6 6) 6) ())))
      (declare (ignorable outcome))
      (check program)
      (check (search "where" (format nil "~a" program)))
      (check-equal (vector 9 8) (run-on program task (vector 9 0 8 -1) 3)))
    ;; a list of positions
    (multiple-value-bind (program outcome task)
        (solved-program 'places '((x0 (:seq :int)) (x1 :int)) '(:seq :int)
                        '(((() 1) ()) (((3) 3) (0)) (((2 3) 3) (1)) (((3 2 3) 3) (0 2)) (((1 1 1) 1) (0 1 2))
                          (((5 4) 9) ()) (((7 5 7 7) 7) (0 2 3))))
      (declare (ignorable outcome))
      (check program)
      (check-equal (vector 1 3) (run-on program task (vector 0 4 0 4) 4)))))

(deftest test-fold-and-aggregate
  (with-fresh-library
    ;; the accumulator is not observed: step functions are run through the fold and compared
    (multiple-value-bind (program outcome task)
        (solved-program 'total '((x0 (:seq :int))) :int
                        '(((()) 0) (((3)) 3) (((2 3)) 5) (((4 2 3)) 9)))
      (declare (ignorable outcome))
      (check-equal '(fold 0 (lambda (v0 v1) (+ v0 v1)) x0) (and program (term->sexp program)))
      (check-equal 21 (run-on program task (vector 1 2 3 4 5 6)))
      ;; once in the library, the function serves as an aggregate over a space of positions
      (define-from-task task program)
      (multiple-value-bind (program2 outcome2 task2)
          (solved-program 'sum-squares '((x0 (:seq :int))) :int
                          '(((()) 0) (((3)) 9) (((2 3)) 13) (((4 2 3)) 29) (((1 1 5)) 27)))
        (declare (ignorable outcome2))
        (check program2)
        (check-equal 14 (and program2 (run-on program2 task2 (vector 1 2 3))))))))

(defparameter *abs-rows*
  '(((3) 3) ((-2) 2) ((0) 0) ((7) 7) ((-5) 5) ((1) 1) ((-1) 1) ((-9) 9) ((4) 4) ((-6) 6)))

(deftest test-size-order-rule
  (with-fresh-library
    (let ((*grammar* '(+ - * < =)))
      ;; the answer needs a conditional; it is accepted, and only in size order
      (multiple-value-bind (program outcome task) (solved-program 'magnitude '((x0 :int)) :int *abs-rows*)
        (check program)
        (check (search "(if " (format nil "~a" program)))
        (check-equal 12 (run-on program task -12))
        (check-equal 12 (run-on program task 12))
        ;; the look-ahead changes the cost and not the answer
        (let ((*use-lookahead* nil))
          (multiple-value-bind (program2 outcome2) (solved-program 'magnitude '((x0 :int)) :int *abs-rows*)
            (check (eq program program2))
            (check (<= (outcome-work outcome) (outcome-work outcome2))
                   "the look-ahead does not add work"))))
      ;; with too small a budget to rule out the smaller terms, the conditional is held, not returned
      (let ((outcome (solve-task (read-task 'magnitude '((x0 :int)) :int *abs-rows*) :budget 300)))
        (check (null (outcome-program outcome)))
        (check-equal :unsolved (outcome-status outcome))))))

(deftest test-rows-that-do-not-determine-an-answer
  (with-fresh-library
    ;; three small outputs: any fit would be expected by chance, so the search stops and says so
    (let ((outcome (solve-task (read-task 'riddle '((x0 (:seq :int)) (x1 (:seq :int))) :int
                                          '((((3 4 1) (4 1)) 1) (((5 2) (5 0)) 0) (((3 1 4 1 5) (4 1 5 0 0)) 2))))))
      (check-equal :underdetermined (outcome-status outcome))
      (check (null (outcome-program outcome)))
      (check (outcome-notes outcome)))
    ;; a parameter with one value on every row: its role cannot be seen
    (let ((outcome (solve-task (read-task 'offset '((x0 :int) (x1 :int)) :int
                                          '(((1 5) 6) ((2 5) 7) ((9 5) 14) ((-3 5) 2) ((0 5) 5))))))
      (check-equal :underdetermined (outcome-status outcome))
      (check (search "same value in every row" (format nil "~{~a~}" (outcome-notes outcome)))))
    ;; two programs of one size fit and differ on made-up rows: x0 + x0, x0 + x1 and x1 + x1
    (let ((outcome (solve-task (read-task 'twice '((x0 :int) (x1 :int)) :int
                                          '(((1 1) 2) ((2 2) 4) ((3 3) 6) ((7 7) 14) ((-4 -4) -8))))))
      (check-equal :underdetermined (outcome-status outcome))
      (check (outcome-rival outcome)))))

(deftest test-reorientation-of-a-requirement
  (with-fresh-library
    ;; a distractor in the library that reads the elements
    (let ((product (read-task 'product '((x0 (:seq :int))) :int
                              '(((()) 1) (((3)) 3) (((2 3)) 6) (((4 2 3)) 24)))))
      (define-from-task product (parse-term '(fold 1 (lambda (v0 v1) (* v0 v1)) x0) '((x0 . (:seq :int))))))
    ;; the output depends on the length alone, and every length is seen twice, so the problem is
    ;; solved on the lengths and its answer cannot read the elements
    (multiple-value-bind (program outcome task)
        (solved-program 'pairs '((x0 (:seq :int))) :int
                        '(((()) 0) (((9)) 0) (((4 9)) 1) (((1 4 9)) 2) (((5)) 0) (((2 5)) 1) (((1 2 5)) 2) ((()) 0)))
      (declare (ignorable outcome))
      (check program)
      (check (not (search "product" (string-downcase (format nil "~a" program)))))
      (check-equal 4 (run-on program task (vector 1 1 1 1 1)))
      (check-equal 0 (run-on program task (vector 0))))))

(deftest test-synthesis-is-resumable
  (with-fresh-library
    (let* ((task (read-task 'add-k '((x0 (:seq :int)) (x1 :int)) '(:seq :int)
                            '(((() 2) ()) (((3) 1) (4)) (((1 3) 5) (6 8)) (((4 1 3) 0) (4 1 3)) (((2 2) 7) (9 9)))))
           (whole (solve-rows task (task-rows task) (make-ledger) 10000000)))
      ;; the same search cut into small slices of budget gives the same program
      (let ((root (root-problem task (task-rows task))) (ledger (make-ledger)) (calls 0))
        (loop until (or (closed-p root) (> calls 100000))
              do (advance root ledger 500) (incf calls))
        (check (> calls 3))
        (check (eq whole (problem-solution root)))))))
