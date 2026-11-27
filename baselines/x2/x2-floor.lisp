;;;; x2-floor.lisp -- a what-if, not a baseline: does it matter that the kernel's integer `/`
;;;; truncates, where the prototype's `div` floors (tg-probe.lisp:205)?
;;;; The kernel copy is not edited. EXECUTE-PRIMITIVE (vm.lisp:209), the one place both the
;;;; interpreter and the closure path compute arithmetic, is wrapped so that integer `/` floors.
;;;; The milestone discovery is then run on the integers exactly as in the baseline.
(load (merge-pathnames "x2-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defvar *floor-division* nil)
(sb-int:encapsulate
 'execute-primitive 'x2-floor
 (lambda (f operator values)
   (if (and *floor-division* (eq :/ (operator-name operator)) (eq :int (operator-operand-type operator)))
       (values (floor (first values) (second values)))
       (funcall f operator values))))

(defun host-div (a b) (if (zerop b) :err (if *floor-division* (values (floor a b)) (values (truncate a b)))))

(defun run (label)
  (format t "~%--- integer solvers with ~A division ---~%" label)
  (format t "(/ -7 2) in the VM now gives ~S~%"
          (nth-value 1 (x2-eval (term `(/ ,(var 0 :int) ,(var 1 :int))) (arithmetic-inputs :int) '(-7 2))))
  (let ((values (x2-values :int)) (inputs (arithmetic-inputs :int))
        (window (loop for v from -20 to 20 collect v)) (candidates (loop for v from -450 to 450 collect v)))
    (dolist (name '(:* :/))
      (let ((relation (observe-arithmetic-relation :int name values)))
        (dolist (position '(0 1))
          (let* ((discovery (discover-arithmetic-solver relation position values :literals '(-1 0 1)))
                 (guard (solve-discovery-guard discovery)) (witness (solve-discovery-witness discovery))
                 (tally (make-array '(2 3) :initial-element 0)) (wrong 0))
            (integer-solver-held-out discovery)
            (dolist (k window)
              (dolist (c window)
                (let* ((solutions
                         (loop for z in candidates
                               when (eql c (if (eq name :*) (* k z)
                                               (if (zerop position) (host-div z k) (host-div k z))))
                                 collect z))
                       (class (cond ((null solutions) 0) ((null (rest solutions)) 1) (t 2))))
                  (multiple-value-bind (status value) (x2-eval guard inputs (list k c))
                    (when (eq status :value)
                      (incf (aref tally (if value 0 1) class))
                      (when value
                        (multiple-value-bind (ws wv) (x2-eval witness inputs (list k c))
                          (unless (and (eq ws :value) (member wv solutions)) (incf wrong)))))))))
            (format t "~A ~D  answer ~A   guard ~A~%      witness law ~S, uniqueness law ~S; on [-20,20]^2 guard true with 0/1/many solutions: ~D / ~D / ~D; guard false: ~D / ~D / ~D; wrong answers under the guard: ~D~%"
                    (string-downcase name) position (short witness) (short guard)
                    (law-validation-status (solve-discovery-validation discovery))
                    (law-validation-status (solve-discovery-uniqueness discovery))
                    (aref tally 0 0) (aref tally 0 1) (aref tally 0 2)
                    (aref tally 1 0) (aref tally 1 1) (aref tally 1 2) wrong)))))))

(format t "~&===== What-if: truncating (the kernel's) against flooring (the prototype's) integer division =====~%")
(let ((*floor-division* nil)) (run "TRUNCATING (the v1 kernel as it is)"))
(let ((*floor-division* t)) (run "FLOORING (what-if)"))
