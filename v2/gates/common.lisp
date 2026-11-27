;;; Shared by the gate runners: load the kernel, and read the recorded baselines.
(setf *compile-verbose* nil *load-verbose* nil)
(defvar cl-user::*gates-directory* (make-pathname :name nil :type nil :defaults *load-truename*))
(handler-bind ((warning #'muffle-warning))
  (load (merge-pathnames "../load.lisp" cl-user::*gates-directory*)))
(in-package #:lisploop2)
(setf *print-pretty* nil *print-case* :downcase)

(defun baseline-path (name)
  (merge-pathnames (concatenate 'string "../../baselines/" name) cl-user::*gates-directory*))

(defun read-forms (path)
  "Every form of the file at PATH, read with this kernel's symbols."
  (with-open-file (s path)
    (let ((*package* (find-package '#:lisploop2)))
      (loop for form = (read s nil :eof) until (eq form :eof) collect form))))

(defun seconds-since (start)
  (/ (- (get-internal-real-time) start) (float internal-time-units-per-second)))

(defun integer-solvers (&key (reach 6) (pad 6))
  "The solvers of + - * / on the integers, found from each operator's own table (gate X2): the
unknown in -REACH..REACH, uniqueness judged on a range wider by PAD on each side."
  (let ((inner (loop for v from (- reach) to reach collect v))
        (wide (loop for v from (- (+ reach pad)) to (+ reach pad) collect v)))
    (loop for name in '(+ - * /)
          append (loop for position below 2
                       for solver = (reorient name '(:int :int) position
                                              :ranges (if (= position 0) (list wide inner) (list inner wide))
                                              :inner inner :op-names '(+ - * / mod < = if)
                                              :constants '((:int 0 1)) :max-size 7 :budget 20000000)
                       when (solver-answer solver) collect solver))))
