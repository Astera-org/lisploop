(in-package #:lisploop2)

;;; Laws from collisions.
;;;
;;; A law is two terms in one class. Nothing here is a mechanism of its own: when enumeration
;;; builds a term whose column is already in the bank, that collision is an equation between the
;;; new term and the class's smallest term (plan sections 5.3 and 8.3).
;;;
;;; What a law is worth depends on the space it was observed on. On a space that holds every
;;; assignment of a finite domain the equation is certified: it has been checked exhaustively.
;;; On a sample of rows it is observed on that sample, and it becomes tested when it also holds
;;; on fresh rows (plan section 5.5).

;;; --- spaces that hold every assignment ---

(defun type-values (type)
  "Every value of the finite TYPE, in a fixed order."
  (ecase (type-kind type)
    (:gf (loop for v below (second type) collect v))
    (:bool (list nil t))
    (:tuple (if (null (rest type))
                (list '())
                (loop for v in (type-values (second type))
                      append (loop for rest in (type-values (cons :tuple (cddr type)))
                                   collect (cons v rest)))))))

(defun exhaustive-space (variables)
  "The space with one row for each assignment of the VARIABLES, which must have finite types.
Returns the space and an alist from variable name to column. The first variable varies slowest."
  (let* ((domains (mapcar (lambda (v) (type-values (term-type v))) variables))
         (rows (reduce (lambda (domain rows)
                         (loop for v in domain append (mapcar (lambda (row) (cons v row)) rows)))
                       domains :from-end t :initial-value (list '())))
         (space (make-space (length rows) :name :exhaustive)))
    (values space
            (loop for v in variables for k from 0
                  collect (cons (term-head v)
                                (map 'simple-vector (lambda (row) (nth k row)) rows))))))

(defun certify-equation (lhs rhs)
  "Check the equation LHS = RHS on every assignment of its variables, which must have finite
types. Returns :CERTIFIED, or :REFUTED with a counterexample as an alist from variable name to
value. This is the one proof rule: exhaustion of a finite domain (v1/laws.lisp, finite-field
certification)."
  (let ((variables (union (term-variables lhs) (term-variables rhs))))
    (multiple-value-bind (space leaves) (exhaustive-space variables)
      (let* ((memo (make-hash-table :test 'eq))
             (a (term-column lhs space leaves memo))
             (b (term-column rhs space leaves memo)))
        (dotimes (r (space-n space) :certified)
          (unless (cell= (svref a r) (svref b r))
            (return (values :refuted
                            (loop for (name . column) in leaves
                                  collect (cons name (svref column r)))))))))))

;;; --- an order on terms, and rewriting by laws ---

(defun term< (a b)
  "A total order on terms: fewer nodes first, then leaves before applications, then by the
identity of the head, then by the arguments in order. A law rewrites its later side to its
earlier side, so rewriting by laws always ends."
  (cond ((eq a b) nil)
        ((/= (term-size a) (term-size b)) (< (term-size a) (term-size b)))
        (t (let ((ka (position (term-kind a) '(:var :const :hole :app :lam)))
                 (kb (position (term-kind b) '(:var :const :hole :app :lam))))
             (cond ((/= ka kb) (< ka kb))
                   ((not (member (term-kind a) '(:app :lam))) (< (term-id a) (term-id b)))
                   ((and (eq :app (term-kind a)) (not (eq (term-head a) (term-head b))))
                    (< (op-id (term-head a)) (op-id (term-head b))))
                   (t (loop for p in (term-args a) for q in (term-args b)
                            do (cond ((term< p q) (return t)) ((term< q p) (return nil)))
                            finally (return (< (term-id a) (term-id b))))))))))

(defun match-pattern (pattern term bindings)
  "One-way matching. A variable of PATTERN matches any term of its type, the same term at each
of its occurrences. Constants and operators match themselves. Returns the bindings, an alist
from variable to term, or :FAIL."
  (cond ((eq bindings :fail) :fail)
        ((eq :var (term-kind pattern))
         (let ((bound (assoc pattern bindings)))
           (cond (bound (if (eq (cdr bound) term) bindings :fail))
                 ((equal (term-type pattern) (term-type term)) (acons pattern term bindings))
                 (t :fail))))
        ;; a pattern that is not an application has no variables in it: it matches itself only.
        ;; An application is matched argument by argument even when it is the very term in hand,
        ;; because the variables inside it must still be bound.
        ((not (eq :app (term-kind pattern))) (if (eq pattern term) bindings :fail))
        ((not (and (eq :app (term-kind term)) (eq (term-head pattern) (term-head term))))
         :fail)
        (t (loop for p in (term-args pattern) for q in (term-args term)
                 do (setf bindings (match-pattern p q bindings))
                    (when (eq bindings :fail) (return :fail))
                 finally (return bindings)))))

(defstruct (law (:constructor make-law (lhs rhs &optional (grade :observed))))
  "The equation LHS = RHS, with RHS the earlier side under TERM<."
  lhs rhs grade
  certificate)   ; set by CERTIFY-LAW (evidence.lisp)

(defmethod print-object ((law law) stream)
  (format stream "~a = ~a" (law-lhs law) (law-rhs law)))

(defun law-rules (law)
  "The directions in which LAW may rewrite: from a side to the other when the other side has no
variable that the first lacks."
  (let ((l (law-lhs law)) (r (law-rhs law)))
    (append (when (subsetp (term-variables r) (term-variables l)) (list (cons l r)))
            (when (and (eq :app (term-kind r)) (subsetp (term-variables l) (term-variables r)))
              (list (cons r l))))))

(defun rewrite-at-root (term rules)
  "A term earlier than TERM that one instance of a rule gives at the root, or nil."
  (loop for (from . to) in rules
        do (let ((b (match-pattern from term nil)))
             (unless (eq b :fail)
               (let ((new (substitute-term to b)))
                 (when (term< new term) (return new)))))))

(defun rewrite-step (term rules)
  "A term earlier than TERM reached by one instance of a rule, at the root or inside, or nil."
  (or (rewrite-at-root term rules)
      (and (eq :app (term-kind term))
           (loop for arg in (term-args term) for k from 0
                 do (let ((new (rewrite-step arg rules)))
                      (when new
                        (return (app-op-retyped
                                 (term-head term)
                                 (append (subseq (term-args term) 0 k) (list new)
                                         (nthcdr (1+ k) (term-args term)))))))))))

(defun normalize-by-rules (term rules)
  (loop for new = (rewrite-step term rules) while new do (setf term new) finally (return term)))

;;; --- collecting laws during enumeration ---

(defstruct (law-book (:constructor %make-law-book))
  "The laws that enumeration of a bank has found. Every collision is counted. A collision is
kept as a law unless a law already kept rewrites its later side: such a collision is an
instance of what is known."
  bank grade
  (laws (make-array 64 :adjustable t :fill-pointer 0))
  (rules '())
  table                         ; when every collision is kept: the colliding term -> the class's term
  (collisions 0) (instances 0))

(defun collect-laws (bank &key (grade :observed) every)
  "Record the laws that further enumeration of BANK finds. Returns the law book. With EVERY, each
collision is also kept in a table from the colliding term to the smallest term of its class."
  (let ((book (%make-law-book :bank bank :grade grade
                              :table (and every (make-hash-table :test 'eq)))))
    (setf (bank-on-collision bank)
          (lambda (class op args)
            (incf (law-book-collisions book))
            (let* ((new (app-op op (mapcar #'cls-term args)))
                   (rep (cls-term class))
                   (later (if (term< rep new) new rep))
                   (earlier (if (eq later new) rep new)))
              (when every (setf (gethash new (law-book-table book)) rep))
              (if (rewrite-step later (law-book-rules book))
                  (incf (law-book-instances book))
                  (let ((law (make-law later earlier grade)))
                    (vector-push-extend law (law-book-laws book))
                    (setf (law-book-rules book)
                          (append (law-book-rules book) (law-rules law))))))
            nil))
    book))

(defun normal-form (term table)
  "TERM rewritten bottom-up by the collisions kept in TABLE, using nothing else. Each argument is
first replaced by its normal form; the resulting term is then either the smallest term of a class,
or a term that enumeration built and found to collide, and the table gives the class's term.
Every collision is one equation, so two terms with one normal form are equal by those equations
and the rule that equals may be replaced inside a term. No column is evaluated."
  (if (eq :app (term-kind term))
      (let ((rebuilt (app-op-retyped (term-head term)
                                     (mapcar (lambda (a) (normal-form a table)) (term-args term)))))
        (or (gethash rebuilt table) rebuilt))
      term))

(defun derivable-p (lhs rhs rules)
  "True when the kept laws rewrite LHS and RHS to one term."
  (eq (normalize-by-rules lhs rules) (normalize-by-rules rhs rules)))

;;; --- what the store itself knows ---

(defun term-class (bank term &optional (memo (make-hash-table :test 'eq)))
  "The class of BANK that TERM falls in, found by evaluating TERM on the bank's space. Nil when
the bank has not reached that column. This is what the store knows without any list of laws:
two terms are equal on the space exactly when they fall in one class."
  (lookup bank (term-column term (bank-space bank) (bank-leaves bank) memo)))
