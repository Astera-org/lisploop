;;; Load the kernel, then the milestone experiment modules, relative to this file.
;;; The kernel never calls into milestones/; those modules are kept under test.
(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (flet ((load-module (name &optional directory)
           (load (merge-pathnames
                  (make-pathname :name name :type "lisp"
                                 :directory (and directory (list :relative directory)))
                  root))))
    (dolist (file '("package" "ast" "knowledge" "codec" "vm" "evidence" "persistence"
                    "requirements" "frame" "enumerate" "unify" "fibers" "laws" "templates"
                    "bootstrap-inverters" "condense" "abstraction" "descriptors" "relations"
                    "synthesize" "nogoods" "decompose" "proposals" "consolidate" "explain"))
      (load-module file))
    (dolist (file '("corpus" "views" "algebra-discovery" "propagation-search" "dependency-search"))
      (load-module file "milestones"))))
