;;;; tabulate.lisp -- run WITHOUT the kernel.  Reads results/*.sexp (one plist per spec attempt, written by
;;;; x3-harness.lisp) and prints the tables used in REPORT.md.
(defpackage #:x3tab (:use #:cl))
(in-package #:x3tab)

(defparameter *dir* (make-pathname :name nil :type nil :defaults *load-truename*))
(defun read-results (name)
  (let ((path (merge-pathnames (format nil "results/~a.sexp" name) *dir*)))
    (when (probe-file path)
      (with-open-file (in path)
        (let ((*package* (find-package :x3tab)) (*read-eval* nil))
          (loop for form = (read in nil :eof) until (eq form :eof) collect form))))))

(defparameter *regimes* '(:whitelist+schemas :whitelist-no-schemas :active-grammar+schemas :active-grammar-no-schemas))
(defparameter *gate* :active-grammar-no-schemas)

(defun h200 (r) (getf r :held-out-200))
(defun sound-1 (r) (and (getf r :solved) (getf r :held-out-1)))
(defun sound-200 (r) (and (getf r :solved) (h200 r) (= (getf (h200 r) :ok) (getf (h200 r) :n))))
(defun sound-both (r) (and (sound-1 r) (sound-200 r)))
(defun of-regime (rs regime) (remove regime rs :key (lambda (r) (getf r :regime)) :test-not #'eq))

(format t "~&TABLE 1. Totals of 16: solved / sound by the harness's one input / sound on the 200 inputs / sound on both~%")
(format t "~28a ~{~22a~}~%" "run" (mapcar #'string-downcase *regimes*))
(dolist (name '("as-written-x1" "repaired-x1" "clean-x1" "curriculum-x1"
                "as-written-x10" "clean-x10" "curriculum-x10"
                "as-written-x100-active-grammar-no-schemas" "clean-x100-active-grammar-no-schemas"
                "curriculum-x100-active-grammar-no-schemas"
                "as-written-x1000-active-grammar-no-schemas"))
  (let ((rs (read-results name)))
    (when rs
      (format t "~28a ~{~22a~}~%"
              (subseq name 0 (min 28 (length name)))
              (loop for regime in *regimes*
                    for sub = (of-regime rs regime)
                    collect (if sub
                                (format nil "~d / ~d / ~d / ~d"
                                        (count-if (lambda (r) (getf r :solved)) sub)
                                        (count-if #'sound-1 sub) (count-if #'sound-200 sub)
                                        (count-if #'sound-both sub))
                                "not run"))))))

(defun outcome (r)
  (cond ((null r) "not run")
        ((not (getf r :solved))
         (if (search "Failed to synthesize" (or (getf r :error) ""))
             "no (budget spent)"
             (format nil "no (~a)" (getf r :error))))
        ((sound-both r) "sound")
        ((sound-200 r) "IMPOSTOR (passes the 200, fails the one input)")
        ((sound-1 r) (format nil "IMPOSTOR (~d/200; passes the one input)" (getf (h200 r) :ok)))
        (t (format nil "IMPOSTOR (~d/200; fails the one input)" (getf (h200 r) :ok)))))

(format t "~&~%TABLE 2. The gate's regime (active grammar, no schemas), per spec~%")
(dolist (name '("as-written-x1" "clean-x1" "curriculum-x1" "as-written-x10" "clean-x10" "curriculum-x10"
                "as-written-x100-active-grammar-no-schemas" "clean-x100-active-grammar-no-schemas"
                "curriculum-x100-active-grammar-no-schemas"
                "as-written-x1000-active-grammar-no-schemas"))
  (let ((rs (of-regime (read-results name) *gate*)))
    (when rs
      (format t "~%-- ~a --~%" name)
      (dolist (r rs)
        (format t "  ~13a ~48a work ~11:d  cpu ~5,2f s  bits ~a~%" (string-downcase (getf r :id)) (outcome r)
                (getf r :work) (getf r :cpu-seconds) (or (getf r :bits) "-"))
        (when (getf r :program) (format t "       ~a~%" (getf r :program)))))))

(format t "~&~%TABLE 3. The gate's regime: what each spec's search is offered~%")
(dolist (name '("as-written-x1" "clean-x1" "curriculum-x1"))
  (let ((rs (of-regime (read-results name) *gate*)))
    (format t "~%-- ~a --~%" name)
    (dolist (r rs)
      (let ((g (getf r :grammar)))
        (format t "  ~13a bound ~3d; ~2d operators; literals ~a; constants ~(~s~)~%" (string-downcase (getf r :id))
                (getf r :bound) (length (getf g :operators)) (sort (copy-list (getf g :literals)) #'<)
                (mapcar #'third (getf g :constants)))
        (format t "       library functions in the grammar: ~(~{~a~^ ~}~)~%"
                (or (loop for o in (getf g :operators)
                          when (and (consp (third o)) (eq :code (first (third o)))
                                    (not (member (second o) '(:code-eval := :if))))
                            collect (second o))
                    '("(none)")))
        (when (getf g :oracle-stubs)
          (format t "       oracle stubs left defined by earlier failures: ~(~{~a~^ ~}~)~%" (getf g :oracle-stubs)))
        (when (getf g :reference-missing)
          (format t "       the library's definition uses, and the grammar lacks: ~(~{~a~^; ~}~)~%"
                  (mapcar (lambda (m) (cond ((integerp m) (format nil "literal ~d" m))
                                            ((eq :op (first m))
                                             (if (and (consp (third m)) (eq :code (first (third m)))
                                                      (not (eq :code-eval (second m))))
                                                 (format nil "function ~a" (second m))
                                                 (format nil "~a at ~s" (second m) (third m))))
                                            (t "a quoted code literal")))
                          (getf g :reference-missing))))))))

(format t "~&~%TABLE 4. Primitive operators of the active grammar per spec (curriculum-x1, gate's regime)~%")
(dolist (r (of-regime (read-results "curriculum-x1") *gate*))
  (format t "  ~13a ~(~{~a~^ ~}~)~%" (string-downcase (getf r :id))
          (loop for o in (getf (getf r :grammar) :operators)
                unless (and (consp (third o)) (eq :code (first (third o)))
                            (not (member (second o) '(:code-eval := :if))))
                  collect (format nil "~a@~a" (second o)
                                  (let ((ty (third o)))
                                    (cond ((eq ty :int) "int") ((eq ty :bool) "bool")
                                          ((equal ty '(:seq :int)) "seq")
                                          ((equal ty '(:tuple :int :int)) "tup")
                                          ((equal ty '(:tuple (:tuple :int :int) :int)) "tup")
                                          ((and (consp ty) (eq :code (first ty))) "code")
                                          (t ty)))))))
