;;; Load the 7-module homoiconic kernel relative to this file.
(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (dolist (file '("package" "ast" "codec" "vm" "frame" "enumerate" "factor" "laws"))
    (load (merge-pathnames (make-pathname :name file :type "lisp") root))))
