;;; Load the self-contained synthesis kernel relative to this file.
;;; External milestone experiment drivers live in milestones/load.lisp;
;;; the kernel never calls into milestones/.
(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (dolist (name '("package" "ast" "knowledge" "codec" "vm" "evidence" "persistence"
                  "requirements" "frame" "enumerate" "unify" "fibers" "laws" "templates"
                  "bootstrap-inverters" "condense" "abstraction" "descriptors" "relations"
                  "synthesize" "nogoods" "decompose" "proposals" "consolidate" "messages" "explain"
                  "batteries"))
    (load (merge-pathnames (make-pathname :name name :type "lisp") root))))
