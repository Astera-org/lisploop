;;; Run the kernel's tests: sbcl --script tests/run.lisp
;;; The exit code is 0 when every check passes.
(setf *compile-verbose* nil *load-verbose* nil)
(let* ((here (make-pathname :name nil :type nil :defaults *load-truename*))
       (root (merge-pathnames (make-pathname :directory '(:relative :up)) here)))
  (handler-bind ((warning (lambda (w) (format t "WARNING: ~a~%" w) (muffle-warning w))))
    (load (merge-pathnames "load.lisp" root))
    (with-compilation-unit ()
      (dolist (name '("support" "core" "codec" "algebra" "synth"))
        (load (merge-pathnames (make-pathname :name name :type "lisp") here))))))
(sb-ext:exit :code (if (lisploop2::run-tests) 0 1))
