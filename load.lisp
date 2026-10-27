;;; Load relative to this file, independently of the caller's working directory.
(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (dolist (file '("package" "syntax" "sim" "frames" "search" "observations" "au"))
    (load (merge-pathnames (make-pathname :name file :type "lisp") root))))
