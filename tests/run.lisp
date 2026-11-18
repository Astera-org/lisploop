(defvar *tests-directory*
  (make-pathname :name nil :type nil :defaults (or *load-truename* *compile-file-truename*)))

(load (merge-pathnames "../load.lisp" *tests-directory*))
(load (merge-pathnames "support.lisp" *tests-directory*))
(in-package #:lisploop)

(defparameter *kernel-test-modules*
  '("core" "codec" "observations" "laws" "symbolic" "amortization"
    "lifting" "abstraction" "refactor" "recursion" "library"
    "higher-order" "audit" "invariants" "structural" "metrics" "topology" "theories" "closures"
    "batteries" "trace"))

(defparameter *milestone-only-test-modules*
  '("guards" "compression" "algebra" "propagation" "corpus" "views"))

(defparameter *all-test-modules*
  (append *kernel-test-modules* *milestone-only-test-modules*))

(defparameter *milestone-test-modules*
  `(("kernel" . ,*kernel-test-modules*)
    ("milestones" . ,*milestone-only-test-modules*)
    ("m1" . ("core"))
    ("m2" . ("observations" "codec"))
    ("m3" . ("laws" "guards" "compression" "symbolic" "amortization"))
    ("m4" . ("algebra" "propagation"))
    ("m5" . ("lifting"))
    ("m6" . ("abstraction" "corpus"))
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
                   (error "Unknown test module or group ~S; expected one of ~S or ~S."
                          arg *all-test-modules* (mapcar #'car *milestone-test-modules*)))))))))

(defun assert-pure-kernel-environment ()
  "Verify that no `milestones/` symbols have been bound before running pure-kernel suites."
  (dolist (sym-name '("DISCOVER-ARITHMETIC-SOLVER"
                      "START-GUARD-SEARCH"
                      "SYNTHESIZE-PARTITION-VIEW"
                      "SYNTHESIZE-CORPUS-ABSTRACTION"
                      "SEARCH-DEPENDENCIES"))
    (let ((sym (find-symbol sym-name '#:lisploop)))
      (assert (not (and sym (fboundp sym))) ()
              "Pure-kernel test isolation violated: milestone symbol ~A is bound."
              sym-name))))

(defun run-registered-tests ()
  (let ((tests (reverse *tests*)))
    (dolist (test tests (length tests))
      (format t "~&~A ... " test)
      (finish-output)
      (funcall test)
      (format t "ok~%"))))

(let* ((selected (resolve-test-modules (cdr sb-ext:*posix-argv*)))
       (kernel-modules (remove-if-not (lambda (m) (member m *kernel-test-modules* :test #'string=))
                                      selected))
       (milestone-modules (remove-if-not (lambda (m) (member m *milestone-only-test-modules* :test #'string=))
                                         selected))
       (start (get-internal-real-time))
       (total-tests 0))
  (when kernel-modules
    (assert-pure-kernel-environment)
    (setf *tests* nil)
    (dolist (module kernel-modules)
      (load (merge-pathnames (make-pathname :name module :type "lisp") cl-user::*tests-directory*)))
    (incf total-tests (run-registered-tests)))
  (when milestone-modules
    (load (merge-pathnames "../milestones/load.lisp" cl-user::*tests-directory*))
    (load (merge-pathnames "milestones/support.lisp" cl-user::*tests-directory*))
    (setf *tests* nil)
    (dolist (module milestone-modules)
      (load (merge-pathnames (make-pathname :directory '(:relative "milestones")
                                            :name module :type "lisp")
                             cl-user::*tests-directory*)))
    (incf total-tests (run-registered-tests)))
  (format t "~&~D tests, ~D checks passed in ~,3F s.~%"
          total-tests *checks*
          (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
