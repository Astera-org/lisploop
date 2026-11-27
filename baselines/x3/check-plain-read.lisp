;;;; check-plain-read.lisp -- run WITHOUT the kernel.  Reads x3-specs.lisp and x3-heldout.lisp with READ in
;;;; an ordinary package, then evaluates every :definition-readable with a forty-line interpreter written
;;;; from the report's table of primitives, and checks that it reproduces every spec row and every
;;;; held-out row.  This shows that the two data files and the stated semantics are enough on their own.
(defpackage #:x3check (:use #:cl))
(in-package #:x3check)

(defparameter *dir* (make-pathname :name nil :type nil :defaults *load-truename*))
(defun read-forms (name)
  (with-open-file (in (merge-pathnames name *dir*))
    (let ((*package* (find-package :x3check)) (*read-eval* nil))
      (loop for form = (read in nil :eof) until (eq form :eof) collect form))))

(defparameter *specs* (read-forms "x3-specs.lisp"))
(defparameter *heldout* (read-forms "x3-heldout.lisp"))
(defparameter *defs* (make-hash-table :test 'eq))   ; name -> (params body)

(defun ev (e env)
  (cond ((integerp e) e)
        ((symbolp e) (let ((b (assoc e env))) (unless b (error "unbound ~a" e)) (cdr b)))
        ((eq (first e) 'lit) (third e))                       ; (lit TYPE VALUE); a code value stays (code (params) body)
        ((eq (first e) 'if) (if (ev (second e) env) (ev (third e) env) (ev (fourth e) env)))   ; lazy
        (t (call (first e) (mapcar (lambda (a) (ev a env)) (rest e))))))                       ; strict

(defun call (op args)
  (destructuring-bind (&optional a b &rest more) args
    (declare (ignorable more))
    (case op
      (+ (+ a b)) (- (- a b)) (* (* a b))
      (/ (if (zerop b) (error "division by zero") (values (truncate a b))))
      (mod (if (zerop b) (error "division by zero") (mod a b)))
      (< (< a b))
      (= (equal a b))
      (cons (cons a b))
      (tail (if (null a) (error "tail of the empty sequence") (rest a)))
      (length (length a))
      (concat (apply #'append a))
      (at (if (and (<= 0 b) (< b (length a))) (nth b a) (error "index ~a out of bounds" b)))
      (tuple args)
      (code-eval (destructuring-bind (head params body) a
                   (assert (eq head 'code))
                   (ev body (pairlis params (rest args)))))    ; the code sees its own parameters only
      (t (let ((def (gethash op *defs*)))
           (unless def (error "unknown operator ~a" op))
           (ev (second def) (pairlis (first def) args)))))))

(dolist (s *specs*)
  (setf (gethash (getf s :name) *defs*)
        (list (mapcar #'first (getf s :params)) (getf s :definition-readable))))

(let ((total-spec 0) (total-held 0) (bad 0))
  (format t "~&files read: ~d specs, ~d held-out sets~%" (length *specs*) (length *heldout*))
  (assert (equal (mapcar (lambda (s) (getf s :name)) *specs*) (mapcar (lambda (h) (getf h :name)) *heldout*)))
  (loop for s in *specs* for h in *heldout*
        for name = (getf s :name)
        do (let ((bad-spec 0) (bad-held 0))
             (dolist (row (getf s :rows))
               (incf total-spec)
               (unless (equal (second row) (handler-case (call name (first row)) (error (c) (list :error (princ-to-string c)))))
                 (incf bad-spec)))
             (dolist (row (getf h :rows))
               (incf total-held)
               (unless (equal (second row) (handler-case (call name (first row)) (error (c) (list :error (princ-to-string c)))))
                 (incf bad-held)))
             (incf bad (+ bad-spec bad-held))
             (format t "  ~14a spec rows ~2d (mismatches ~d)   held-out rows ~3d (mismatches ~d)~%"
                     (string-downcase name) (length (getf s :rows)) bad-spec (length (getf h :rows)) bad-held)))
  (format t "total: ~d spec rows, ~d held-out rows, ~d mismatches~%" total-spec total-held bad))

;;; A census of the held-out rows: how often each function or predicate argument occurs, how many rows
;;; have an empty first sequence, and how many held-out inputs also occur among the spec's own rows.
(format t "~&held-out census~%")
(loop for s in *specs* for h in *heldout*
      do (let ((codes nil) (empty 0) (seen 0) (lens nil))
           (dolist (row (getf h :rows))
             (when (null (first (first row))) (incf empty))
             (push (length (first (first row))) lens)
             (when (member (first row) (getf s :rows) :key #'first :test #'equal) (incf seen))
             (dolist (a (first row))
               (when (and (consp a) (eq (first a) 'code))
                 (let ((cell (assoc a codes :test #'equal)))
                   (if cell (incf (cdr cell)) (push (cons a 1) codes))))))
           (format t "  ~14a first sequence empty in ~3d rows, longest ~2d; inputs that are also spec rows: ~d~@[; arguments: ~{~a~^, ~}~]~%"
                   (string-downcase (getf s :name)) empty (reduce #'max lens) seen
                   (loop for (c . n) in (sort codes #'> :key #'cdr)
                         collect (format nil "~(~a~) x~d" (third c) n)))))
