(load (merge-pathnames "../load.lisp" *load-truename*))
(load (merge-pathnames "../fixtures.lisp" *load-truename*))
(load (merge-pathnames "../law-experiments.lisp" *load-truename*))
(load (merge-pathnames "../algebra-experiments.lisp" *load-truename*))
(load (merge-pathnames "../lifting-experiments.lisp" *load-truename*))
(load (merge-pathnames "../abstraction-experiments.lisp" *load-truename*))
(load (merge-pathnames "../view-experiments.lisp" *load-truename*))
(in-package #:lisploop)

(dolist (module '("support" "core" "observations" "codec" "laws" "guards" "compression" "symbolic" "amortization" "algebra" "propagation" "lifting" "abstraction" "views"))
  (load (merge-pathnames (make-pathname :name module :type "lisp") *load-truename*)))

(let ((start (get-internal-real-time)))
  (dolist (test (reverse *tests*))
    (format t "~&~A ... " test)
    (finish-output)
    (funcall test)
    (format t "ok~%"))
  (format t "~&~D tests, ~D checks passed in ~,3F s.~%"
          (length *tests*) *checks*
          (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
