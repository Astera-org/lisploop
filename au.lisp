(in-package #:lisploop)

(defun term-sort (term inputs)
  (if (eq (first term) :op) (operator-type term) (expression-type term inputs t)))

(defun match-pattern (pattern source &optional inputs ledger)
  "Typed first-order matching, including symbols in operator position.
Return substitutions and a success flag; NIL substitutions can be a valid match."
  (unless (equal (term-sort pattern inputs) (term-sort source inputs))
    (return-from match-pattern (values nil nil)))
  (let ((substitutions nil))
    (labels ((walk (p s)
               (charge ledger :matching)
               (cond
                 ((and (consp p) (eq (first p) :hole))
                  (and (equal (third p) (term-sort s inputs))
                       (let ((entry (assoc (second p) substitutions)))
                         (if entry (equal (cdr entry) s)
                             (progn (push (cons (second p) s) substitutions) t)))))
                 ((equal p s) t)
                 ((and (consp p) (consp s)
                       (eq (first p) :app) (eq (first s) :app)
                       (= (length (third p)) (length (third s))))
                  (and (walk (second p) (second s))
                       (every #'walk (third p) (third s))))
                 (t nil))))
      (let ((success (walk pattern source)))
        (values (and success (nreverse substitutions)) success)))))

(defun anti-unify (sources &optional inputs ledger)
  "Aligned typed syntactic LGG. Equal disagreement tuples reuse the same hole.
An incompatible operator signature falls back to a whole-expression hole if the
result types agree. Distinct result types have no common typed AST pattern."
  (assert sources)
  (let ((disagreements (make-hash-table :test #'equal)) (next-id 0))
    (labels ((generalize (terms)
               (charge ledger :anti-unification (length terms))
               (let ((sorts (mapcar (lambda (term) (term-sort term inputs)) terms)))
                 (assert (every (lambda (sort) (equal sort (first sorts))) sorts))
                 (cond
                   ((every (lambda (term) (equal term (first terms))) terms) (first terms))
                   ((and (every (lambda (term) (eq (first term) :app)) terms)
                         (let ((signatures (mapcar (lambda (term) (operator-type (second term))) terms)))
                           (every (lambda (signature) (equal signature (first signatures))) signatures)))
                    (list :app (generalize (mapcar #'second terms))
                          (loop for i below (length (third (first terms))) collect
                            (generalize (mapcar (lambda (term) (nth i (third term))) terms)))))
                   (t (or (gethash terms disagreements)
                          (setf (gethash terms disagreements)
                                (hole (prog1 next-id (incf next-id)) (first sorts)))))))))
      (let ((pattern (generalize sources)))
        (values pattern
                (mapcar (lambda (source)
                          (multiple-value-bind (substitution matched)
                              (match-pattern pattern source inputs ledger)
                            (assert matched)
                            substitution)) sources))))))
