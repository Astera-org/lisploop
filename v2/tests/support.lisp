(in-package #:lisploop2)

;;; A small test harness. A test is a named body of CHECK forms. A check that fails is recorded
;;; with its form and does not stop the test, so one run reports every failure.

(defvar *tests* '() "names of the defined tests, most recent first")
(defvar *failures* '())
(defvar *checks* 0)
(defvar *current-test* nil)

(defmacro deftest (name &body body)
  `(progn (defun ,name () (let ((*current-test* ',name)) ,@body))
          (pushnew ',name *tests*)
          ',name))

(defmacro check (form &optional note)
  `(progn (incf *checks*)
          (unless (handler-case ,form
                    (error (e) (push (list *current-test* ',form (format nil "error: ~a" e)) *failures*) t))
            (push (list *current-test* ',form ,note) *failures*))))

(defmacro check-equal (expected form &optional note)
  (let ((e (gensym)) (v (gensym)))
    `(let ((,e ,expected) (,v (handler-case ,form (error (c) (list :error (format nil "~a" c))))))
       (incf *checks*)
       (unless (equalp ,e ,v)
         (push (list *current-test* ',form
                     (format nil "expected ~s, got ~s~@[ (~a)~]" ,e ,v ,note))
               *failures*)))))

(defun run-tests (&optional (names (reverse *tests*)))
  (setf *failures* '() *checks* 0)
  (dolist (name names)
    (let ((before (length *failures*)) (t0 (get-internal-real-time)))
      (handler-case (funcall name)
        (error (e) (push (list name :whole-test (format nil "error: ~a" e)) *failures*)))
      (format t "~:[FAIL~;ok  ~] ~a (~,2f s)~%" (= before (length *failures*)) name
              (/ (- (get-internal-real-time) t0) (float internal-time-units-per-second)))))
  (let ((*print-case* :downcase))
    (dolist (f (reverse *failures*))
      (format t "~%FAILED in ~a:~%  ~s~@[~%  ~a~]~%" (first f) (second f) (third f))))
  (format t "~%~d tests, ~d checks, ~d failures~%" (length names) *checks* (length *failures*))
  (null *failures*))

(defun xyz-rows (n seed &key (lo -9) (hi 9))
  "N rows of three integers; the first three rows are made of 0, 1 and -1."
  (let ((rs (sb-ext:seed-random-state seed)))
    (append '((0 1 -1) (1 -1 0) (-1 0 1))
            (loop repeat (- n 3)
                  collect (loop repeat 3 collect (+ lo (random (1+ (- hi lo)) rs)))))))

(defun rows-bank (rows names op-names &key (type :int) constants)
  "A bank on one row per element of ROWS, with one leaf per name in NAMES and the CONSTANTS."
  (let* ((space (make-space (length rows))) (bank (make-bank space op-names)))
    (loop for name in names for k from 0
          do (add-leaf bank (var name type) (map 'simple-vector (lambda (r) (nth k r)) rows)))
    (dolist (c constants) (add-constant bank c type))
    bank))
