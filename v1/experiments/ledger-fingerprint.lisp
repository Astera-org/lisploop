;;; Ledger fingerprint of the test suite: for every test, the work that every ledger really
;;; received under each category, and the number of checks the test made. Two kernels that
;;; charge the same work for the same reasons print the same file, however they slice their
;;; charges; so a change that is meant to leave the tariff alone can be checked against it.
;;;
;;;   sbcl --dynamic-space-size 4096 --script experiments/ledger-fingerprint.lisp OUT [ROOT/]
;;;
;;; ROOT defaults to this checkout. To compare with another commit:
;;;   git worktree add /tmp/base 019736f
;;;   sbcl ... --script experiments/ledger-fingerprint.lisp /tmp/base.txt /tmp/base/
;;;   sbcl ... --script experiments/ledger-fingerprint.lisp /tmp/here.txt
;;;   cmp /tmp/base.txt /tmp/here.txt
;;; The modules are the 222 tests of 019736f, so that fingerprints of later kernels compare.
(defvar *output* (second sb-ext:*posix-argv*))
(defvar *repo* (or (third sb-ext:*posix-argv*)
                   (merge-pathnames "../" (make-pathname :name nil :type nil :defaults *load-truename*))))
(defvar *tests-directory* (merge-pathnames "tests/" *repo*))
(load (merge-pathnames "load.lisp" *repo*))
(load (merge-pathnames "tests/support.lisp" *repo*))
(in-package #:lisploop)

(defvar *by-category* (make-hash-table :test #'eq))
(defvar *charging* nil)

;; At a work limit `charge` charges only what is left and throws, calling itself to do so:
;; what a ledger received is the change in its total, not the amount that was asked for.
(sb-int:encapsulate
 'charge 'fingerprint
 (lambda (f ledger category &optional (amount 1))
   (if (or *charging* (null ledger))
       (funcall f ledger category amount)
       (let ((before (ledger-total ledger)) (*charging* t))
         (unwind-protect (funcall f ledger category amount)
           (incf (gethash category *by-category* 0) (- (ledger-total ledger) before)))))))

(defun run-modules (out directory modules)
  (setf *tests* nil)
  (dolist (module modules)
    (load (merge-pathnames (make-pathname :directory directory :name module :type "lisp")
                           cl-user::*tests-directory*)))
  (dolist (test (reverse *tests*))
    (clrhash *by-category*)
    (let ((checks *checks*))
      (funcall test)
      (format out "~A checks=~D~%" test (- *checks* checks))
      (dolist (entry (sort (loop for category being the hash-keys of *by-category* using (hash-value work)
                                 collect (cons category work))
                           #'string< :key (lambda (entry) (symbol-name (car entry)))))
        (format out "  ~A ~D~%" (car entry) (cdr entry))))))

(with-open-file (out cl-user::*output* :direction :output :if-exists :supersede)
  (run-modules out nil '("core" "codec" "observations" "laws" "symbolic" "amortization" "lifting"
                         "abstraction" "refactor" "recursion" "library" "higher-order" "audit"
                         "invariants" "structural" "metrics" "topology" "theories"))
  (load (merge-pathnames "milestones/load.lisp" cl-user::*repo*))
  (load (merge-pathnames "milestones/support.lisp" cl-user::*tests-directory*))
  (run-modules out '(:relative "milestones")
               '("guards" "compression" "algebra" "propagation" "corpus" "views")))
(format t "~A~%" cl-user::*output*)
