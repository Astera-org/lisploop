;;; Load the kernel, relative to this file.
(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (with-compilation-unit ()
    (dolist (name '("package" "ledger" "values" "ops" "terms" "eval" "store" "codec" "laws" "reorient" "evidence" "synth" "task"))
      (load (merge-pathnames (make-pathname :name name :type "lisp") root)))))
