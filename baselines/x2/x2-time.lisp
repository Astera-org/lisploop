;;;; x2-time.lisp -- wall time of the 24 discoveries with NO instrumentation.
;;;; Loads the private copy directly (not x2-common.lisp, so CHARGE is not wrapped) and calls the
;;;; test fixture ARITHMETIC-CONTROLS (observe + discover + validate for 4 operators x 2 positions)
;;;; five times per domain, clearing its cache each time.
(defvar cl-user::*here* (make-pathname :name nil :type nil :defaults *load-truename*))
(load (merge-pathnames "v1/load.lisp" cl-user::*here*))
(load (merge-pathnames "v1/milestones/load.lisp" cl-user::*here*))
(load (merge-pathnames "v1/tests/support.lisp" cl-user::*here*))
(load (merge-pathnames "v1/tests/milestones/support.lisp" cl-user::*here*))
(in-package #:lisploop)

(defun wall-clock ()
  (multiple-value-bind (seconds nanoseconds) (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ seconds (* 1d-9 nanoseconds))))

(format t "~&X2 timing, uninstrumented. Each line: 8 solvers on one domain (observe, discover, validate).~%")
(let ((totals nil))
  (dotimes (repetition 5)
    (let ((sum 0d0))
      (dolist (domain (list (gf 5) (gf 7) :int))
        (clrhash *arithmetic-controls*)
        (let* ((t0 (wall-clock))
               (discoveries (arithmetic-controls domain))
               (dt (- (wall-clock) t0)))
          (incf sum dt)
          (format t "run ~D  ~8A  ~D solvers  ~,4F s~%" (1+ repetition)
                  (if (eq domain :int) "INT" (format nil "GF(~D)" (second domain)))
                  (length discoveries) dt)))
      (format t "run ~D  all three domains (24 solvers)  ~,4F s~%" (1+ repetition) sum)
      (push sum totals)))
  (let ((sorted (sort (copy-list totals) #'<)))
    (format t "24 solvers: min ~,4F s, median ~,4F s, max ~,4F s over 5 runs in one process~%"
            (first sorted) (third sorted) (fifth sorted))))
