;;;; x3-common.lisp -- shared prelude of the base-x3 scripts.  Loads the v2 kernel FROM THE COPY named by
;;;; the environment variable X3_V2_ROOT (never the repository), borrows two functions of the Stage 0
;;;; harness without running its top level, and defines the plain-data printer used for x3-specs.lisp.
;;;; Environment: X3_V2_ROOT = .../base-x3/kernel/v2/   X3_WORK = .../base-x3/

(defvar *x3-root* (pathname (sb-ext:posix-getenv "X3_V2_ROOT")))
(defvar *x3-work* (pathname (sb-ext:posix-getenv "X3_WORK")))
(assert (search "/kernel/v2" (namestring *x3-root*)) () "refusing to load a kernel outside the work directory")
(load (merge-pathnames "load.lisp" *x3-root*))
(load (merge-pathnames "bootstrap/recursion-schemas.lisp" *x3-root*))
(load (merge-pathnames "tests/support.lisp" *x3-root*))

(in-package #:lisploop)
(setf *print-pretty* nil *print-right-margin* 1000000)

;;; The harness's own spec collection and its one-input held-out cases (stage0-audit.lisp:18-84),
;;; evaluated from the file as it stands, without running the audit at its top level.
(with-open-file (s (merge-pathnames "experiments/stage0-audit.lisp" cl-user::*x3-root*))
  (let ((*package* (find-package :lisploop)))
    (loop for form = (read s nil :eof) until (eq form :eof)
          do (when (and (consp form) (eq 'defun (first form))
                        (member (second form) '(collect-bootstrap-function-specs held-out-test-cases)))
               (eval form)))))

;;; ------------------------------------------------------------------------------------------------
;;; Plain data: symbols interned in a scratch package and printed without a package prefix.
;;; ------------------------------------------------------------------------------------------------
;;; The package uses CL, as a reader of the data files normally will, so that nil and t read as themselves.
(defpackage #:x3p (:use #:cl))
(defun psym (control &rest args) (intern (string-upcase (apply #'format nil control args)) :x3p))

(defun plain-value (v type)
  "Kernel value V of TYPE as plain data.  A code value becomes (code (params) body)."
  (cond ((code-type-p type) (plain-code v type))
        ((seq-type-p type) (mapcar (lambda (e) (plain-value e (second type))) v))
        ((tuple-type-p type) (mapcar #'plain-value v (rest type)))
        (t v)))

(defun plain (expr)
  "A kernel AST as a plain s-expression: variables x0 x1 .., operators by name, integer literals bare,
any other literal as (lit TYPE VALUE)."
  (let ((meta (ensure-ast-meta expr)))
    (ecase (ast-meta-kind meta)
      (:var (psym "X~D" (ast-meta-id meta)))
      (:hole (psym "?~D" (ast-meta-id meta)))
      (:op (psym "~A" (symbol-name (ast-meta-id meta))))
      (:lit (let ((type (ast-meta-type meta)) (val (ast-meta-value meta)))
              (if (eq type :int) val (list (psym "LIT") type (plain-value val type)))))
      (:app (cons (plain (first expr)) (mapcar #'plain (rest expr)))))))

(defun plain-code (ast type)
  (list (psym "CODE") (loop for (id) in (code-inputs type) collect (psym "X~D" id)) (plain ast)))

(defun unplain-form (form scope)
  "Plain FORM back into something `term` accepts: variables become typed variable nodes."
  (cond ((integerp form) form)
        ((symbolp form)
         (let* ((name (symbol-name form)) (id (parse-integer name :start 1)))
           (assert (char= #\X (char name 0)))
           (var id (cdr (assoc id scope)))))
        (t (cons (first form) (mapcar (lambda (f) (unplain-form f scope)) (rest form))))))

(defun unplain-value (v type)
  "Plain data V of TYPE back into a kernel value."
  (cond ((code-type-p type)
         (destructuring-bind (head params body) v
           (assert (and (eq head (psym "CODE")) (= (length params) (length (code-inputs type)))))
           (let ((ast (term (unplain-form body (code-inputs type)) (code-sort type))))
             (assert (value-p ast type))
             ast)))
        ((seq-type-p type) (mapcar (lambda (e) (unplain-value e (second type))) v))
        ((tuple-type-p type) (mapcar #'unplain-value v (rest type)))
        (t v)))

(defun emit (x &optional (out *standard-output*))
  "Print plain data X.  NIL is written () except as the value of a Boolean literal, where it is nil."
  (cond ((null x) (write-string "()" out))
        ((eq x t) (write-string "t" out))
        ((consp x)
         (if (and (eq (first x) (psym "LIT")) (eq (second x) :bool) (null (third x)))
             (write-string "(lit :bool nil)" out)
             (progn (write-char #\( out)
                    (loop for cell on x
                          do (emit (car cell) out)
                             (cond ((null (cdr cell)))
                                   ((consp (cdr cell)) (write-char #\Space out))
                                   (t (write-string " . " out) (emit (cdr cell) out) (return))))
                    (write-char #\) out))))
        ((stringp x) (prin1 x out))
        (t (let ((*package* (find-package :x3p)) (*print-case* :downcase)) (prin1 x out)))))

(defun emit-string (x) (with-output-to-string (s) (emit x s)))

(defun read-plain-file (path)
  "Every form of PATH, read with the scratch package current (so nothing of the kernel is needed)."
  (with-open-file (in path)
    (let ((*package* (find-package :x3p)) (*read-eval* nil))
      (loop for form = (read in nil :eof) until (eq form :eof) collect form))))

(defun read-boot-specs ()
  "The sixteen records dumped by the instrumented bootstrap (boot-specs.sexp), in bootstrap order."
  (with-open-file (in (merge-pathnames "boot-specs.sexp" cl-user::*x3-work*))
    (let ((*package* (find-package :lisploop)) (*read-eval* nil))
      (loop for form = (read in nil :eof) until (eq form :eof) collect form))))

(defparameter *x3-order*
  '(:copy :inc-all :dbl-all :sum-all :len-all :prd-all :foldl :filter :map-adjacent :positions
    :scan :shift-seq :seq-corr :best-shift :argmax-corr :last-or))
