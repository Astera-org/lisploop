;;; Read-only experiment 4: time each battery build of bootstrap/build-batteries.lisp with the
;;; output directory redirected to the scratchpad (nothing is written under the repository).
(load "/home/tlh24/lisploop/load.lisp")
(load "/home/tlh24/lisploop/bootstrap/recursion-schemas.lisp")
(in-package #:lisploop)

(defparameter *scratch-out*
  #P"/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/laws-library/library-out/")

;; Evaluate every top-level form of build-batteries.lisp except its loader (first form), its
;; output-directory parameter, and its final run-everything form.
(with-open-file (in "/home/tlh24/lisploop/bootstrap/build-batteries.lisp")
  (let ((*package* (find-package '#:lisploop)) (forms nil))
    (loop for form = (read in nil :eof) until (eq form :eof) do (push form forms))
    (setf forms (nreverse forms))
    (dolist (form (butlast (rest forms)))
      (cond ((and (consp form) (eq 'in-package (first form))))
            ((and (consp form) (eq 'defparameter (first form))
                  (eq '*bootstrap-output-directory* (second form)))
             (defparameter *bootstrap-output-directory* *scratch-out*))
            (t (eval form))))))

(format t "~&output dir = ~A~%" *bootstrap-output-directory*)
(let ((total0 (get-internal-real-time)))
  (dolist (build '(build-algebra-battery build-arithmetic-battery build-constructors-battery
                   build-functors-battery build-sequences-and-descriptors-batteries
                   build-scans-battery build-sequence-shift-battery))
    (let ((t0 (get-internal-real-time)))
      (handler-case (funcall build)
        (error (e) (format t "~&!! ~A failed: ~A~%" build e)))
      (format t "~&## ~A wall=~,2Fs~%" build
              (/ (float (- (get-internal-real-time) t0) 1d0) internal-time-units-per-second))
      (finish-output)))
  (format t "~&## TOTAL wall=~,2Fs~%"
          (/ (float (- (get-internal-real-time) total0) 1d0) internal-time-units-per-second)))
