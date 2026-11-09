(load (merge-pathnames "../load.lisp" *load-truename*))
(load (merge-pathnames "support.lisp" *load-truename*))
(in-package #:lisploop)

(defparameter *all-test-modules*
  '("core" "observations" "codec" "laws" "guards" "compression" "symbolic"
    "amortization" "algebra" "propagation" "lifting" "abstraction" "views" "refactor"
    "recursion" "library" "higher-order"))

(defparameter *milestone-test-modules*
  '(("m1" . ("core"))
    ("m2" . ("observations" "codec"))
    ("m3" . ("laws" "guards" "compression" "symbolic" "amortization"))
    ("m4" . ("algebra" "propagation"))
    ("m5" . ("lifting"))
    ("m6" . ("abstraction"))
    ("m7" . ("views"))
    ("m8" . ("views" "refactor" "recursion"))
    ("m9" . ("abstraction" "recursion" "library" "higher-order"))
    ("r1" . ("recursion"))
    ("r2" . ("recursion"))
    ("r3" . ("recursion"))
    ("r4" . ("recursion"))
    ("r5" . ("recursion"))
    ("r6" . ("recursion"))
    ("l1" . ("library"))
    ("l2" . ("library"))
    ("l3" . ("library"))
    ("l4" . ("library"))
    ("h1" . ("higher-order"))
    ("h2" . ("higher-order"))
    ("h3" . ("higher-order"))
    ("h4" . ("higher-order"))))

(defun resolve-test-modules (args)
  (if (or (null args) (member "all" args :test #'string-equal))
      *all-test-modules*
      (let ((selected nil))
        (dolist (arg args (nreverse selected))
          (let ((group (cdr (assoc arg *milestone-test-modules* :test #'string-equal))))
            (cond (group
                   (dolist (module group)
                     (pushnew module selected :test #'string=)))
                  ((member arg *all-test-modules* :test #'string-equal)
                   (pushnew (string-downcase arg) selected :test #'string=))
                  (t
                   (error "Unknown test module or milestone ~S; expected one of ~S or ~S."
                          arg *all-test-modules* (mapcar #'car *milestone-test-modules*)))))))))

(dolist (module (resolve-test-modules (cdr sb-ext:*posix-argv*)))
  (load (merge-pathnames (make-pathname :name module :type "lisp") *load-truename*)))

(let ((start (get-internal-real-time)))
  (dolist (test (reverse *tests*))
    (format t "~&~A ... " test)
    (finish-output)
    (funcall test)
    (format t "ok~%"))
  (format t "~&~D tests, ~D checks passed in ~,3F s.~%"
          (length *tests*) *checks*
          (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
