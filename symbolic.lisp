(in-package #:lisploop)

;;; Structural operations on quoted data. None executes the quoted expression.
;;; Matching/substitution reuse the same implementation as AU and frame composition.

(defun expression-code-p (type)
  (and (code-type-p type) (not (function-sort-p (code-sort type)))))

(defun same-code-scope-p (left right)
  (and (code-type-p left) (code-type-p right) (equal (code-inputs left) (code-inputs right))))

(defun symbolic-operator-type (name type)
  (flet ((signature (inputs output) (list :fn inputs output)))
    (case name
      (:code-kind (assert (code-type-p type)) (signature (list type) :int))
      (:code-total (assert (expression-code-p type)) (signature (list type) :bool))
      (:code-less (assert (expression-code-p type)) (signature (list type type) :bool))
      ((:code-operator :code-apply)
       (assert (and (code-type-p type) (function-sort-p (code-sort type))))
       (let* ((sort (code-sort type)) (scope (code-inputs type))
              (result (code-type scope (third sort))))
         (if (eq name :code-operator) (signature (list result) type)
             (signature (list type (apply #'tuple-type
                                         (mapcar (lambda (arg) (code-type scope arg)) (second sort)))) result))))
      (otherwise
       (assert (and (eq :tuple (first type)) (member (length type) '(3 4))))
       (let ((a (second type)) (b (third type)) (c (fourth type)))
         (assert (expression-code-p a))
         (ecase name
           (:code-child
            (assert (and (null c) (expression-code-p b) (same-code-scope-p a b)))
            (signature (list a :int) b))
           (:code-match
            (assert (and (null c) (expression-code-p b) (equal (code-sort a) (code-sort b))))
            (signature (list a b) :bool))
           (:code-bind
            (assert (and (expression-code-p b) (expression-code-p c) (same-code-scope-p b c)
                         (equal (code-sort a) (code-sort b))))
            (signature (list a b :int) c))
           (:code-subst
            (assert (and (eq :tuple (first b)) (expression-code-p c) (equal (code-sort a) (code-sort c))
                         (= (length (rest b)) (length (code-inputs a)))
                         (every (lambda (binding input)
                                  (and (same-code-scope-p binding c) (equal (code-sort binding) (cdr input))))
                                (rest b) (code-inputs a))))
            (signature (list a b) c))))))))

(defun expression-variables (expression)
  (case (first expression)
    (:var (list (second expression)))
    (:app (remove-duplicates (mapcan #'expression-variables (third expression))))))

(defun expression-pattern (expression)
  (case (first expression)
    (:var (hole (second expression) (third expression)))
    (:app (apply #'app (second expression) (mapcar #'expression-pattern (third expression))))
    (otherwise expression)))

(defun provably-total-p (expression)
  "Conservative structural definedness, without executing the quoted program."
  (case (first expression)
    ((:var :lit) t)
    (:app
     (let ((name (second (second expression))) (args (third expression)))
       (case name
         (:/ (and (every #'provably-total-p args) (eq :lit (first (second args)))
                  (not (zerop (third (second args))))))
         ((:lookup :gather :code-child :code-operator :code-bind) nil)
         (:if (and (provably-total-p (first args))
                   (if (eq :lit (first (first args)))
                       (provably-total-p (if (third (first args)) (second args) (third args)))
                       (every #'provably-total-p (rest args)))))
         (otherwise (every #'provably-total-p args)))))))

(defun expression-less-p (left right inputs)
  "Well-founded order: packet bits, then lexicographic bits at equal length."
  (let ((a (encode-model left inputs)) (b (encode-model right inputs)))
    (or (< (length a) (length b))
        (and (= (length a) (length b))
             (loop for x across a for y across b when (/= x y) return (< x y))))))

(defun match-code (pattern source source-type)
  (match-pattern (expression-pattern pattern) source (code-inputs source-type)))

(defun execute-symbolic-primitive (name type values)
  (case name
    (:code-kind (ecase (first (first values)) (:var 0) (:lit 1) (:app 2) (:op 3)))
    (:code-total (not (null (provably-total-p (first values)))))
    (:code-less (not (null (expression-less-p (first values) (second values) (code-inputs type)))))
    (:code-operator
     (let ((source (first values)))
       (assert (and (eq :app (first source)) (equal (operator-type (second source)) (code-sort type))))
       (copy-tree (second source))))
    (:code-apply (apply #'app (copy-tree (first values)) (copy-tree (second values))))
    (:code-child
     (let ((source (first values)) (index (second values)))
       (assert (eq :app (first source)))
       (checked-position index (length (third source)))
       (let ((child (nth index (third source))))
         (assert (value-p child (third type)))
         (copy-tree child))))
    (:code-match (nth-value 1 (match-code (first values) (second values) (third type))))
    (:code-bind
     (multiple-value-bind (bindings matched) (match-code (first values) (second values) (third type))
       (let ((entry (assoc (third values) bindings)))
         (assert (and matched entry (value-p (cdr entry) (fourth type))))
         (copy-tree (cdr entry)))))
    (:code-subst
     (instantiate (first values)
                  (mapcar (lambda (input value) (cons (car input) value))
                          (code-inputs (second type)) (second values)) :var))))

(defun symbolic-primitive-cost (name type values)
  "Prepay traversal/copying, including nested substitutions and failed matches."
  (let* ((weights (mapcar #'value-work values (second (symbolic-operator-type name type))))
         (base (1+ (reduce #'+ weights))))
    (case name
      ((:code-match :code-bind :code-subst) (+ base (* (first weights) (second weights))))
      (:code-less (* 4 (+ base (type-work type))))
      (otherwise base))))

(defun compile-au-constructor (pattern scope &optional ledger)
  "A DSL program maps quoted hole fillings to the instantiated quoted expression.
Operator holes are quoted operator values, not callable host functions."
  (let ((inputs nil))
    (labels ((walk (term)
               (charge ledger :au-lowering (syntax-work term))
               (let ((type (code-type scope (term-sort term scope))))
                 (cond
                   ((eq :hole (first term))
                    (let ((previous (assoc (second term) inputs)))
                      (when previous (assert (equal (cdr previous) type)))
                      (unless previous (push (cons (second term) type) inputs)))
                    (var (second term) type))
                   ((not (pattern-has-holes-p term)) (lit type term))
                   (t
                    (let* ((operator-sort (term-sort (second term) scope))
                           (operator-code (code-type scope operator-sort))
                           (arguments (apply #'tuple-type
                                             (mapcar (lambda (sort) (code-type scope sort)) (second operator-sort)))))
                      (app (op :code-apply operator-code) (walk (second term))
                           (apply #'app (op :tuple arguments) (mapcar #'walk (third term))))))))))
      (let ((model (walk pattern)))
        (charge ledger :construction (syntax-work model))
        (values model (nreverse inputs))))))
