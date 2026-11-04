;;; Load the kernel, conservative simplifier, and synthesis controller relative to this file.
(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (dolist (file '("package" "ast" "codec" "vm" "requirements" "frame" "enumerate" "factor" "laws" "synthesize"))
    (load (merge-pathnames (make-pathname :name file :type "lisp") root))))
