;;;; x2-common.lisp -- shared helpers for the X2 baseline scripts.
;;;; Loads the PRIVATE COPY of the v1 kernel that sits beside this file (./v1/), the milestone
;;;; drivers, and the two test-support files that hold the fixtures the milestone tests use.
;;;; Nothing here changes kernel behaviour: the only instrumentation is a wrapper around CHARGE
;;;; that adds up what is charged to any ledger while *METER* is bound.

(defvar cl-user::*x2-here*
  (make-pathname :name nil :type nil :defaults (or *load-truename* *default-pathname-defaults*)))

(load (merge-pathnames "v1/load.lisp" cl-user::*x2-here*))
(load (merge-pathnames "v1/milestones/load.lisp" cl-user::*x2-here*))
(load (merge-pathnames "v1/tests/support.lisp" cl-user::*x2-here*))
(load (merge-pathnames "v1/tests/milestones/support.lisp" cl-user::*x2-here*))
(in-package #:lisploop)

;;; ---- printing ----------------------------------------------------------------------------
(defun short (ast)
  "A compact rendering of a kernel term: variables as xN, literals by value, (op arg ...)."
  (labels ((p (x)
             (case (ast-kind x)
               (:var (format nil "x~D" (ast-id x)))
               (:lit (let ((v (ast-value x)))
                       (cond ((eq v t) "T") ((null v) "NIL") (t (format nil "~S" v)))))
               (:app (format nil "(~(~A~)~{ ~A~})" (operator-name (first x)) (mapcar #'p (rest x))))
               (t (format nil "~S" x)))))
    (if ast (p ast) "NIL")))

(defun full (ast)
  "The kernel's own portable, self-typed serialisation (ast->sexp), on one line."
  (let ((*print-pretty* nil) (*print-right-margin* 100000))
    (format nil "~S" (ast->sexp ast))))

(defun domain-name (domain)
  (if (eq domain :int) "INT" (format nil "GF(~D)" (second domain))))

;;; ---- metering ----------------------------------------------------------------------------
(defvar *meter* nil
  "When non-nil, a list (total . by-category alist): every unit charged to any ledger is added.")

(defun make-meter () (list 0))

(sb-int:encapsulate
 'charge 'x2-meter
 (lambda (f ledger category &optional (amount 1))
   (if (and *meter* ledger)
       (let ((before (ledger-total ledger)))
         (unwind-protect (funcall f ledger category amount)
           (let ((d (- (ledger-total ledger) before)))
             (incf (car *meter*) d)
             (let ((cell (assoc category (cdr *meter*))))
               (if cell (incf (cdr cell) d) (push (cons category d) (cdr *meter*)))))))
       (funcall f ledger category amount))))

(defun wall-clock ()
  "Monotonic wall clock in seconds (nanosecond resolution; get-internal-real-time is coarse here)."
  (multiple-value-bind (seconds nanoseconds) (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ seconds (* 1d-9 nanoseconds))))

(defun call-metered (thunk)
  "Call THUNK with a fresh meter; return (values result meter wall-seconds)."
  (let* ((meter (make-meter)) (t0 (wall-clock))
         (value (let ((*meter* meter)) (funcall thunk))))
    (values value meter (- (wall-clock) t0))))

(defun meter-total (meter) (car meter))
(defun meter-categories (meter)
  (sort (copy-alist (cdr meter)) #'> :key #'cdr))

;;; ---- the fixture the milestone tests use (tests/milestones/support.lisp:198-208) ------------
(defun x2-values (domain)
  (if (eq domain :int) '(-4 -3 -2 -1 0 1 2 3 4) (loop for i below (second domain) collect i)))
(defun x2-literals (domain) (if (eq domain :int) '(-1 0 1) :all))

(defun x2-eval (expression inputs values)
  "(values status value) of EXPRESSION in the kernel's VM."
  (let ((run (evaluate expression inputs values :budget 100000000)))
    (values (evaluation-status run) (evaluation-value run) (evaluation-error run))))
