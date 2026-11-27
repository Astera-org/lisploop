;;;; x2-composite.lisp -- the two composite cases of risk 2: a*x + b = c and x + x = c.
;;;; Asks the v1 kernel's one mechanism that composes inverses, SOLVE-EQUALITY-SYMBOLICALLY
;;;; (laws.lisp:809-887), with two rule sets: (1) the bootstrap library's arithmetic solvers
;;;; (tests/support.lisp:525 KERNEL-PROPAGATOR-LIBRARY), (2) the rules the milestone code discovers.
;;;; Every returned closed form is then checked by brute force.
(load (merge-pathnames "x2-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defun host-op (name domain a b)
  (if (eq domain :int)
      (ecase name (:+ (+ a b)) (:* (* a b)))
      (mod (ecase name (:+ (+ a b)) (:* (* a b))) (second domain))))

(defun check-closed-form (domain inputs unknown-id solution guards forward window)
  "FORWARD is a host function of the full assignment (alist id -> value) giving (values lhs rhs).
Over every assignment of the known inputs in WINDOW, compare the closed form with brute force."
  (let* ((known (remove unknown-id inputs :key #'car))
         (candidates (if (eq domain :int) (loop for v from -60 to 60 collect v) window))
         (active 0) (right 0) (wrong 0) (errors 0) (missed-unique 0) (missed-any 0) (total 0))
    (labels ((walk (remaining assignment)
               (if remaining
                   (dolist (v window) (walk (rest remaining) (acons (car (first remaining)) v assignment)))
                   (let* ((values (loop for (id . nil) in inputs
                                        collect (if (eql id unknown-id) (first window)
                                                    (cdr (assoc id assignment)))))
                          (solutions (loop for z in candidates
                                           when (multiple-value-bind (lhs rhs)
                                                    (funcall forward (acons unknown-id z assignment))
                                                  (eql lhs rhs))
                                             collect z))
                          (guard-values (loop for g in guards
                                              collect (multiple-value-list (x2-eval g inputs values))))
                          (holds (every (lambda (r) (and (eq :value (first r)) (second r))) guard-values)))
                     (incf total)
                     (cond (holds
                            (incf active)
                            (multiple-value-bind (status value) (x2-eval solution inputs values)
                              (cond ((not (eq status :value)) (incf errors))
                                    ((member value solutions) (incf right))
                                    (t (incf wrong)))))
                           ((and solutions (null (rest solutions))) (incf missed-unique) (incf missed-any))
                           (solutions (incf missed-any)))))))
      (walk known nil))
    (format t "      brute force over ~D assignments of the knowns: guards hold on ~D; closed form right on ~D, wrong on ~D, error on ~D;~%      guards fail although a solution exists on ~D (of which exactly one solution: ~D)~%"
            total active right wrong errors missed-any missed-unique)))

(defun ask (label domain library inputs unknown-id lhs rhs forward window)
  (format t "~%   ~A   [~A]~%" label (domain-name domain))
  (multiple-value-bind (solution guards certified-p)
      (handler-case (solve-equality-symbolically lhs rhs unknown-id :library library)
        (error (c) (values :error (princ-to-string c))))
    (cond ((eq solution :error) (format t "      ERROR: ~A~%" guards))
          ((null solution) (format t "      -> NIL (not solved)~%"))
          (t (format t "      -> x = ~A~%      guards: ~:[none~;~:*~{~A~^  AND  ~}~]~%      certified-p: ~S~%"
                     (short solution) (mapcar #'short guards) certified-p)
             (check-closed-form domain inputs unknown-id solution guards forward window)))))

(defun run-cases (title domain library)
  (format t "~%--- ~A ---~%" title)
  (let* ((window (if (eq domain :int) '(-4 -3 -2 -1 0 1 2 3 4) (loop for i below (second domain) collect i)))
         (inputs (arithmetic-inputs domain 4))
         (a (var 0 domain)) (b (var 1 domain)) (c (var 2 domain)) (x (var 3 domain))
         (two-inputs (list (cons 2 domain) (cons 3 domain))))
    (flet ((val (id assignment) (cdr (assoc id assignment))))
      (ask "a*x + b = c, solved for x (inputs a b c)" domain library inputs 3
           (term `(+ (* ,a ,x) ,b)) c
           (lambda (s) (values (host-op :+ domain (host-op :* domain (val 0 s) (val 3 s)) (val 1 s)) (val 2 s)))
           window)
      (ask "b + x*a = c, solved for x (the same equation, arguments swapped)" domain library inputs 3
           (term `(+ ,b (* ,x ,a))) c
           (lambda (s) (values (host-op :+ domain (val 1 s) (host-op :* domain (val 3 s) (val 0 s))) (val 2 s)))
           window)
      (ask "x + x = c, solved for x (input c)" domain library two-inputs 3
           (term `(+ ,x ,x)) c
           (lambda (s) (values (host-op :+ domain (val 3 s) (val 3 s)) (val 2 s)))
           window)
      (ask "x * x = c, solved for x (input c)" domain library two-inputs 3
           (term `(* ,x ,x)) c
           (lambda (s) (values (host-op :* domain (val 3 s) (val 3 s)) (val 2 s)))
           window)
      (ask "a*x + x = c, solved for x (the unknown twice, under two operators)" domain library inputs 3
           (term `(+ (* ,a ,x) ,x)) c
           (lambda (s) (values (host-op :+ domain (host-op :* domain (val 0 s) (val 3 s)) (val 3 s)) (val 2 s)))
           window))))

(format t "~&===== Composite cases, asked of SOLVE-EQUALITY-SYMBOLICALLY =====~%")
(format t "~%##### Rule set 1: the bootstrap library's eight arithmetic solvers (library/arithmetic.sexp) #####~%")
(dolist (domain (list (gf 5) (gf 7) :int))
  (with-clean-kernel-state
    (let ((library (kernel-propagator-library domain)))
      (format t "~%rules for ~A: ~D; evidence per rule (operator position witness-current uniqueness-current uniqueness-tested):~%"
              (domain-name domain) (length (propagator-library-rules library)))
      (dolist (rule (propagator-library-rules library))
        (format t "   ~A ~D  ~12A guard ~30A ~S ~S ~S~%"
                (string-downcase (operator-name (arithmetic-propagator-operator rule)))
                (arithmetic-propagator-position rule)
                (short (arithmetic-propagator-witness rule)) (short (arithmetic-propagator-guard rule))
                (propagator-certified-current-p rule :witness)
                (propagator-certified-current-p rule :uniqueness)
                (propagator-tested-p rule :uniqueness)))
      (run-cases (format nil "bootstrap library rules, ~A" (domain-name domain)) domain library))))

(format t "~%##### Rule set 2: the rules the milestone code discovers (discovery-propagator-library) #####~%")
(dolist (domain (list (gf 5) (gf 7) :int))
  (with-clean-kernel-state
    (let* ((discoveries (arithmetic-controls domain))
           (library (discovery-propagator-library discoveries (make-ledger))))
      (format t "~%rules for ~A: ~D of 8 discoveries become rules~%" (domain-name domain)
              (length (propagator-library-rules library)))
      (dolist (rule (propagator-library-rules library))
        (format t "   ~A ~D  ~12A ~S ~S ~S~%"
                (string-downcase (operator-name (arithmetic-propagator-operator rule)))
                (arithmetic-propagator-position rule)
                (short (arithmetic-propagator-witness rule))
                (propagator-certified-current-p rule :witness)
                (propagator-certified-current-p rule :uniqueness)
                (propagator-tested-p rule :uniqueness)))
      (run-cases (format nil "milestone-discovered rules, ~A" (domain-name domain)) domain library))))
