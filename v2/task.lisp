(in-package #:lisploop2)

;;; Tasks: a function to be found from rows of inputs and output, and when an answer is accepted.
;;;
;;; Acceptance has three parts (plan sections 7.2 and 8.8).
;;;
;;;   1. Root verification. Every finished program is run on every row by the evaluator, which
;;;      shares only the operators' cell functions with the store that found it.
;;;   2. The size-order rule, inside the search: a conditional is never accepted ahead of a
;;;      smaller term without one.
;;;   3. Held-back rows. The search is repeated with each row left out in turn. If the program
;;;      found without a row does not predict that row, the rows do not determine the answer,
;;;      and the task is reported as underdetermined instead of answered.

;;; A library function that the selection row needs: the elements of S at the positions IDX.
;;; It is TABULATE over AT (plan section 7.1), written here once.
(define-function 'gather '(s idx) (list (seq-of :int) (seq-of :int))
  '(tabulate (length idx) (lambda (i) (at s (at idx i)))))

(defstruct task
  name
  params      ; list of variable terms
  returns     ; the result type
  rows)       ; list of (inputs . output), with inputs a list of values in the order of PARAMS

;;; STATUS is one of:
;;;   :solved           a program was found, verified on every row, and accepted
;;;   :underdetermined  the rows do not determine the answer, for one of two reasons. A
;;;                     parameter has the same value in every row, so its role cannot be seen.
;;;                     Or the search closed the task, or a part every route needs, because so
;;;                     many candidates had been compared that a fit would be expected by
;;;                     chance. A program that fits may still be reported with this status.
;;;   :unsolved         the budget ended, or every route was exhausted, without either
;;;   :unverified       a program was accepted that the evaluator does not confirm: a defect
(defstruct outcome
  status
  program     ; the term found on all rows, or nil
  evidence    ; bits by which the program beat the best description without it
  work        ; ledger units spent, including any searches with a row held back
  search-work ; ledger units spent by the search on all rows
  seconds
  held        ; a conditional that fits and was not accepted under the size-order rule
  rival       ; a program of the same size that fits the rows and differs on made-up rows
  notes)      ; why a task is underdetermined, and anything else worth saying

(defun root-problem (task rows)
  (let ((space (make-space (length rows) :name (task-name task))))
    (make-problem
     :label "root" :space space :type (task-returns task)
     :leaves (loop for v in (task-params task) for k from 0
                   collect (cons v (map 'simple-vector (lambda (row) (nth k (car row))) rows)))
     :target (map 'simple-vector #'cdr rows))))

(defun row-environment (task row)
  (loop for v in (task-params task) for value in (car row) collect (cons (term-head v) value)))

(defun program-value (program task row &key (fuel 1000000))
  (values (run-term program (row-environment task row) :fuel fuel)))

(defun fits-rows-p (program task rows)
  (every (lambda (row) (cell= (cdr row) (program-value program task row))) rows))

(defun solve-rows (task rows ledger budget)
  "Search for a program that gives each row's output from its inputs. Returns the program or nil,
and the root problem. When the budget ends while a term that is not a conditional is held at the
root, that term is returned: it fits, and only the search for a smaller one was cut short."
  (let* ((root (root-problem task rows))
         (program (advance root ledger budget)))
    (when (and (null program) (problem-held root) (not (fit-strict (problem-held root))))
      (push (format nil "root: the budget ended before every smaller term than ~a was ruled out" (held-term root))
            *task-notes*)
      (finalize root)
      (setf program (problem-solution root)))
    (values program root)))

;;; --- rows the kernel makes up, and the rivals that size cannot choose between (section 5.5) ---

(defun observed-range (values)
  (let ((ints (remove-if-not #'integerp values)))
    (if ints (values (reduce #'min ints) (reduce #'max ints)) (values 0 1))))

(defun probe-rows (task count &key (seed 20261126))
  "COUNT made-up rows of inputs for TASK, near the rows it has. An integer parameter is drawn
from the range it takes in the rows. A sequence is up to three elements longer than the longest
in the rows, with elements drawn from two below the smallest to two above the largest seen. A
function is one of those the rows have. Any other parameter takes one of its values in the rows."
  (let ((state (sb-ext:seed-random-state seed)) (rows (task-rows task)))
    (flet ((pick (list) (nth (random (length list) state) list))
           (between (lo hi) (+ lo (random (1+ (- hi lo)) state))))
      (loop repeat count
            collect (loop for v in (task-params task) for k from 0
                          for seen = (mapcar (lambda (row) (nth k (car row))) rows)
                          collect (let ((type (term-type v)))
                                    (cond ((eq type :int)
                                           (multiple-value-bind (lo hi) (observed-range seen)
                                             (between lo hi)))
                                          ((equal type (seq-of :int))
                                           (multiple-value-bind (lo hi)
                                               (observed-range (loop for s in seen append (coerce s 'list)))
                                             (let ((longest (reduce #'max (mapcar #'length seen))))
                                               (coerce (loop repeat (between 0 (+ 3 longest))
                                                             collect (between (- lo 2) (+ hi 2)))
                                                       'simple-vector))))
                                          (t (pick seen)))))))))

(defun single-substitutions (program)
  "Every program got from PROGRAM by replacing one sub-term with one of its alternates."
  (let ((seen '()) (variants '()))
    (labels ((walk (term)
               (unless (member term seen)
                 (push term seen)
                 (dolist (alternate (and *alternates* (gethash term *alternates*)))
                   (pushnew (substitute-term program (list (cons term alternate))) variants))
                 (when (member (term-kind term) '(:app :lam))
                   (mapc #'walk (term-args term))))))
      (walk program))
    (remove program variants)))

(defun find-rival (program task &key (probes 200))
  "A program of PROGRAM's size that fits every row of TASK and gives a different result on some
made-up row. Returns the rival and that row's inputs, or nil."
  (let ((rows (probe-rows task probes)))
    (dolist (variant (single-substitutions program))
      (when (fits-rows-p variant task (task-rows task))
        (dolist (inputs rows)
          (let ((row (cons inputs nil)))
            (unless (cell= (program-value program task row :fuel 200000)
                           (program-value variant task row :fuel 200000))
              (return-from find-rival (values variant inputs)))))))))

(defun solve-task (task &key (budget 50000000) hold-back (check-rivals t))
  "Solve TASK. Returns an OUTCOME. With HOLD-BACK the search is also repeated with each row left
out in turn, and the outcome notes each row that the program found without it fails to predict."
  (let* ((ledger (make-ledger)) (rows (task-rows task)) (t0 (get-internal-real-time))
         (*task-notes* '())
         (*classes-stored* 0)
         (*task-problems* '())
         (*alternates* (make-hash-table :test 'eq))
         (constant (and (rest rows)
                        (loop for v in (task-params task) for k from 0
                              when (every (lambda (row) (cell= (nth k (car row)) (nth k (car (first rows)))))
                                          rows)
                                collect v))))
    (multiple-value-bind (program root) (solve-rows task rows ledger budget)
      (unless program (note-terms-still-held))
      (dolist (v constant)
        (push (format nil "the parameter ~a has the same value in every row, so the rows cannot show how the output depends on it"
                      v)
              *task-notes*))
      (let* ((search-work (ledger-total ledger))
             (verified (and program (fits-rows-p program task rows)))
             (rival (and verified check-rivals
                         (multiple-value-bind (rival inputs) (find-rival program task)
                           (when rival
                             (push (format nil "the rows do not decide between the program and ~a: both fit every row, and they differ on the made-up input ~a"
                                           rival inputs)
                                   *task-notes*)
                             rival))))
             (status (cond ((and program (not verified)) :unverified)
                           ((or constant rival) :underdetermined)
                           (program :solved)
                           ((or (problem-undetermined root)
                                (and (problem-exhausted root) *task-notes*))
                            :underdetermined)
                           (t :unsolved)))
             (notes (reverse *task-notes*)))
        (when (and hold-back (eq status :solved) (>= (length rows) 3))
          (loop for held in rows for k from 0
                do (let* ((*task-notes* '())
                          (other (solve-rows task (remove held rows :test #'eq) ledger
                                             (max 1000000 (* 4 search-work)))))
                     (cond ((null other)
                            (push (format nil "with row ~d held back, no program was found" k) notes))
                           ((not (cell= (cdr held) (program-value other task held)))
                            (push (format nil "with row ~d held back the search returns ~a, which does not predict that row"
                                          k other)
                                  notes))))))
        (make-outcome :status status :program program
                      :evidence (problem-evidence root)
                      :work (ledger-total ledger) :search-work search-work
                      :seconds (/ (- (get-internal-real-time) t0)
                                  (float internal-time-units-per-second))
                      :held (and (not program) (problem-held root) (held-term root))
                      :rival rival
                      :notes notes)))))

;;; --- reading rows written as plain Lisp data ---
;;;
;;; A sequence is written as a list, a tuple as a list, a Boolean as T or NIL, and a function as
;;; (code (x0 x1 ...) body), with body a term over the function's own parameters.

(defun read-type (type)
  "The kernel's type for a type written in v1's notation, where a function is (:code ((0 . T0) ...) T)."
  (cond ((atom type) type)
        ((eq :code (first type))
         (fn-type (mapcar (lambda (input) (read-type (cdr input))) (second type))
                  (read-type (third type))))
        ((eq :seq (first type)) (seq-of (read-type (second type))))
        (t (cons (first type) (mapcar #'read-type (rest type))))))

(defun read-value (datum type)
  (case (type-kind type)
    (:seq (map 'simple-vector (lambda (d) (read-value d (second type))) datum))
    (:tuple (mapcar #'read-value datum (rest type)))
    (:fn (destructuring-bind (params body) (rest datum)
           (let* ((env (mapcar #'cons params (second type)))
                  (term (lam (mapcar #'var params (second type))
                             (parse-term body env (third type)))))
             (make-closure term nil))))
    (t datum)))

(defun read-task (name params returns rows)
  "A task from plain data: PARAMS is a list of (name type), ROWS a list of ((input ...) output)."
  (let* ((types (mapcar (lambda (p) (read-type (second p))) params))
         (returns (read-type returns)))
    (make-task :name name
               :params (mapcar (lambda (p type) (var (first p) type)) params types)
               :returns returns
               :rows (loop for (inputs output) in rows
                           collect (cons (mapcar #'read-value inputs types)
                                         (read-value output returns))))))

(defun define-from-task (task program)
  "Enter PROGRAM in the library as the function named by TASK, so later tasks may call it."
  (let* ((params (mapcar #'term-head (task-params task)))
         (types (mapcar #'term-type (task-params task)))
         (name (task-name task)))
    (define-op name types (term-type program)
      (lambda (bindings) (declare (ignore bindings))
        (lambda (&rest values) (ev program (pairlis params values)))))
    (pushnew name *library*)
    (setf *library* (append (remove name *library*) (list name)))
    name))
