;;; Load the kernel, conservative simplifier, and synthesis controller relative to this file.
(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (dolist (file '("package" "ast" "knowledge" "codec" "vm" "evidence" "persistence" "requirements" "frame" "enumerate" "factor" "laws" "templates" "bootstrap-inverters" "synthesize" "proposals"))
    (load (merge-pathnames (make-pathname :name file :type "lisp") root))))
