;;; Load relative to this file, independently of the caller's working directory.
(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (dolist (file '("package" "syntax" "codec" "sim" "frames" "au" "symbolic" "laws" "grammar" "search" "observations" "guards" "law-compression" "algebra" "propagation" "propagation-search"))
    (load (merge-pathnames (make-pathname :name file :type "lisp") root))))
