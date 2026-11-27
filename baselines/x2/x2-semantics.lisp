;;;; x2-semantics.lisp -- (A) the semantics of the arithmetic primitives in the v1 VM, measured;
;;;; (B) what each discovered guard means, by brute force over all (k, c) in a window.
(load (merge-pathnames "x2-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defun show (form inputs values)
  "Evaluate the term FORM (a `term` template) and print status and value or error."
  (multiple-value-bind (status value error) (x2-eval form inputs values)
    (format nil "~A~@[ ~S~]~@[ ~S~]" status (and (eq status :value) (list value))
            (and error (substitute #\Space #\Newline error)))))

(format t "~&===== A. Primitive semantics, measured in the v1 VM (vm.lisp:209-221) =====~%")
(format t "~%--- A1. :int  (/ a b), compared with host TRUNCATE and FLOOR; (mod a b), compared with host MOD and REM ---~%")
(let* ((inputs (arithmetic-inputs :int)) (a (var 0 :int)) (b (var 1 :int))
       (quotient (term `(/ ,a ,b))) (modulus (term `(mod ,a ,b))))
  (dolist (pair '((7 2) (-7 2) (7 -2) (-7 -2) (6 3) (-6 3) (1 2) (-1 2) (1 -2) (0 5) (0 -5) (5 0) (0 0) (-5 0)))
    (destructuring-bind (x y) pair
      (format t "a=~3D b=~3D   (/ a b) -> ~28A host truncate ~4A floor ~4A |  (mod a b) -> ~28A host mod ~4A rem ~4A~%"
              x y (show quotient inputs pair)
              (if (zerop y) "-" (values (truncate x y))) (if (zerop y) "-" (values (floor x y)))
              (show modulus inputs pair)
              (if (zerop y) "-" (mod x y)) (if (zerop y) "-" (rem x y)))))
  (let ((mismatch-truncate 0) (mismatch-floor 0) (mismatch-mod 0) (errors 0) (n 0))
    (loop for x from -30 to 30 do
      (loop for y from -30 to 30 do
        (incf n)
        (multiple-value-bind (status value) (x2-eval quotient inputs (list x y))
          (multiple-value-bind (mstatus mvalue) (x2-eval modulus inputs (list x y))
            (cond ((zerop y) (when (and (eq status :error) (eq mstatus :error)) (incf errors)))
                  (t (unless (and (eq status :value) (= value (truncate x y))) (incf mismatch-truncate))
                     (unless (and (eq status :value) (= value (floor x y))) (incf mismatch-floor))
                     (unless (and (eq mstatus :value) (= mvalue (mod x y))) (incf mismatch-mod))))))))
    (format t "all ~D pairs in [-30,30]^2: (/ a b) differs from TRUNCATE on ~D pairs, from FLOOR on ~D pairs; (mod a b) differs from host MOD (sign of the divisor) on ~D; both are :error on ~D of the 61 pairs with b = 0~%"
            n mismatch-truncate mismatch-floor mismatch-mod errors))
  (format t "bignums: (/ 2^200 3) -> ~A~%" (show quotient inputs (list (ash 1 200) 3)))
  (format t "         (* 2^200 2^200) = 2^400 ? ~A~%"
          (multiple-value-bind (status value) (x2-eval (term `(* ,a ,b)) inputs (list (ash 1 200) (ash 1 200)))
            (and (eq status :value) (= value (ash 1 400))))))

(format t "~%--- A2. prime fields: values are 0..p-1; + - * reduce mod p; (/ a b) = a * b^-1 mod p; b = 0 is an error ---~%")
(dolist (p '(5 7))
  (let* ((field (gf p)) (inputs (arithmetic-inputs field)) (a (var 0 field)) (b (var 1 field)))
    (format t "GF(~D) division table, rows a = 0..~D, columns b = 0..~D (E = error):~%" p (1- p) (1- p))
    (dotimes (x p)
      (format t "   ~{~A~^ ~}~%"
              (loop for y below p collect
                (multiple-value-bind (status value) (x2-eval (term `(/ ,a ,b)) inputs (list x y))
                  (if (eq status :value) value "E")))))
    (format t "   (/ 3 0) -> ~A~%" (show (term `(/ ,a ,b)) inputs '(3 0)))
    (format t "   (- 1 3) -> ~A      (+ ~D 1) -> ~A      (* ~D ~D) -> ~A~%"
            (show (term `(- ,a ,b)) inputs '(1 3))
            (1- p) (show (term `(+ ,a ,b)) inputs (list (1- p) 1))
            (1- p) (1- p) (show (term `(* ,a ,b)) inputs (list (1- p) (1- p))))
    (let ((bad 0))
      (dotimes (x p) (dotimes (y p)
        (unless (zerop y)
          (multiple-value-bind (status value) (x2-eval (term `(/ ,a ,b)) inputs (list x y))
            (unless (and (eq status :value) (= x (mod (* value y) p))) (incf bad))))))
      (format t "   (/ a b) * b = a for every b /= 0: ~D violations~%" bad))
    (format t "   is -1 a value of GF(~D)? ~S   is ~D? ~S   is ~D? ~S~%" p (value-p -1 field) p (value-p p field)
            (1- p) (value-p (1- p) field))
    (format t "   :mod and :< on a field: ~A~%"
            (handler-case (progn (op :mod field) "accepted")
              (error (c) (format nil "rejected (~A)" (subseq (princ-to-string c) 0 (min 80 (length (princ-to-string c))))))))))

(format t "~%--- A3. errors, laziness, equality ---~%")
(let* ((inputs (arithmetic-inputs :int)) (a (var 0 :int)) (b (var 1 :int)))
  (format t "(if (= b 0) 0 (/ a b)) at (5 0) -> ~A     [`if` evaluates only the chosen branch]~%"
          (show (term `(if (= ,b 0) 0 (/ ,a ,b))) inputs '(5 0)))
  (format t "(= (/ a b) (/ a b)) at (5 0)   -> ~A     [an error in an argument is an error of the application]~%"
          (show (term `(= (/ ,a ,b) (/ ,a ,b))) inputs '(5 0)))
  (format t "(if (= (/ a b) 0) t nil) at (5 0) -> ~A   [an error in the condition is an error of the `if`]~%"
          (show (term `(if (= (/ ,a ,b) 0) t nil)) inputs '(5 0)))
  (format t "(* (/ a b) 0) at (5 0)         -> ~A     [no short cut: 0 * error is an error]~%"
          (show (term `(* (/ ,a ,b) 0)) inputs '(5 0)))
  (format t "(< a b) at (-3 2) -> ~A ; (= a b) at (2 2) -> ~A~%"
          (show (term `(< ,a ,b)) inputs '(-3 2)) (show (term `(= ,a ,b)) inputs '(2 2)))
  (let ((run (evaluate (term `(/ ,a ,b)) inputs '(5 0))))
    (format t "evaluation of (/ 5 0): status ~S, value ~S, error ~S, work ~D~%"
            (evaluation-status run) (evaluation-value run) (evaluation-error run) (evaluation-work run)))
  (let ((run (evaluate (term `(/ ,a ,b)) inputs '(5 2) :budget 1)))
    (format t "evaluation of (/ 5 2) with budget 1: status ~S (not yet finished; resumable)~%" (evaluation-status run))))
(let* ((relation (observe-arithmetic-relation :int :/ '(-1 0 1)))
       (record (first (observation-job-records (arithmetic-relation-observations relation)))))
  (format t "observation of (/ x0 x1) on the grid {-1,0,1}^2: expression status ~S; per-row outcomes ~S~%"
          (observed-expression-status record)
          (mapcar (lambda (o) (if (eq :value (observation-outcome-status o))
                                  (observation-outcome-value o) (observation-outcome-status o)))
                  (observed-expression-outcomes record)))
  (format t "   error text kept per row: ~S~%"
          (observation-outcome-error (find :error (observed-expression-outcomes record) :key #'observation-outcome-status))))

;;; ---- B. what the guards mean -------------------------------------------------------------
(defun host-apply (name domain a b)
  "The VM's arithmetic, restated in host code (checked against the VM in section A). :err on error."
  (if (eq domain :int)
      (ecase name (:+ (+ a b)) (:- (- a b)) (:* (* a b)) (:/ (if (zerop b) :err (values (truncate a b)))))
      (let ((p (second domain)))
        (ecase name
          (:+ (mod (+ a b) p)) (:- (mod (- a b) p)) (:* (mod (* a b) p))
          (:/ (if (zerop b) :err
                  (mod (* a (loop for i below p when (= 1 (mod (* b i) p)) return i)) p)))))))

(defun solutions (name domain position k c candidates)
  (loop for z in candidates
        when (eql c (if (zerop position) (host-apply name domain z k) (host-apply name domain k z)))
          collect z))

(format t "~%===== B. Meaning of each discovered guard, by brute force =====~%")
(format t "For every (k, c) in the window, count the z with op(.., z, ..) = c. Columns: guard true and 0 / 1 / many solutions;~%")
(format t "guard false and 0 / 1 / many solutions; guard error; cases where the guard holds but the answer term is not a solution.~%")
(dolist (domain (list (gf 5) (gf 7) :int))
  (let* ((values (x2-values domain))
         (window (if (eq domain :int) (loop for v from -20 to 20 collect v) values))
         (candidates (if (eq domain :int) (loop for v from -450 to 450 collect v) values))
         (inputs (arithmetic-inputs domain)))
    (format t "~%~A: (k, c) window ~A, z searched in ~A~%" (domain-name domain)
            (if (eq domain :int) "[-20,20]^2 (1681 pairs)" "the whole field")
            (if (eq domain :int) "[-450,450] (complete except where infinitely many z exist)" "the whole field"))
    (format t "~4A ~3A ~18A ~18A ~4A ~5A  ~A~%" "op" "arg" "true: 0/1/many" "false: 0/1/many" "err" "wrong" "guard")
    (dolist (name '(:+ :- :* :/))
      (let ((relation (observe-arithmetic-relation domain name values)))
        (dolist (position '(0 1))
          (let* ((discovery (discover-arithmetic-solver relation position values :literals (x2-literals domain)))
                 (guard (solve-discovery-guard discovery)) (witness (solve-discovery-witness discovery))
                 (tally (make-array '(2 3) :initial-element 0)) (errors 0) (wrong 0)
                 (divisible-mismatch 0))
            (dolist (k window)
              (dolist (c window)
                (let* ((solutions (solutions name domain position k c candidates))
                       (class (cond ((null solutions) 0) ((null (rest solutions)) 1) (t 2))))
                  (multiple-value-bind (status value) (x2-eval guard inputs (list k c))
                    (cond ((not (eq status :value)) (incf errors))
                          (t (incf (aref tally (if value 0 1) class))
                             (when value
                               (multiple-value-bind (wstatus wvalue) (x2-eval witness inputs (list k c))
                                 (unless (and (eq wstatus :value) (member wvalue solutions)) (incf wrong))))
                             (when (and (eq domain :int) (eq name :*))
                               (unless (eq (not (null value)) (and (/= k 0) (zerop (rem c k))))
                                 (incf divisible-mismatch)))))))))
            (format t "~4A ~3D ~18A ~18A ~4D ~5D  ~A~%" (string-downcase name) position
                    (format nil "~D / ~D / ~D" (aref tally 0 0) (aref tally 0 1) (aref tally 0 2))
                    (format nil "~D / ~D / ~D" (aref tally 1 0) (aref tally 1 1) (aref tally 1 2))
                    errors wrong (short guard))
            (when (and (eq domain :int) (eq name :*))
              (format t "         guard differs from (k /= 0 and k divides c) on ~D pairs~%" divisible-mismatch))))))))
