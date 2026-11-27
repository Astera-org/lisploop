(in-package #:lisploop2)

;;; Terms.
;;;
;;; A term is an operator applied to terms, or a leaf. Terms are stored once each (hash-consed),
;;; so a term is a node in a shared graph, and two terms are the same term exactly when they are
;;; EQ. A term has no rows. Evaluated over a space, it denotes a column (plan section 5.2).
;;;
;;; Kinds:
;;;   :var    a named variable; HEAD is its name. A leaf that names a column of a space.
;;;   :const  a constant; HEAD is its value
;;;   :app    an operator applied to arguments; HEAD is the OP, ARGS the argument terms
;;;   :lam    a function; HEAD is the list of its parameters (terms of kind :var), ARGS its one body
;;;   :hole   an unknown to be filled; HEAD is its name. Requirements are terms with holes (5.6).

(defstruct (term (:constructor %make-term))
  (id 0 :type fixnum)
  kind head args type
  (size 1 :type fixnum))

(defvar *terms* (make-hash-table :test 'equalp) "the key of a term -> the term")
(defvar *term-count* 0)

(defun intern-term (key kind head args type size)
  (or (gethash key *terms*)
      (setf (gethash key *terms*)
            (%make-term :id (incf *term-count*) :kind kind :head head :args args
                        :type type :size size))))

(defun var (name type) (intern-term (list :var name type) :var name nil type 1))
(defun const (value type) (intern-term (list :const value type) :const value nil type 1))
(defun hole (name type) (intern-term (list :hole name type) :hole name nil type 1))

(defun app-op (op args)
  "The term that applies the operator OP to the terms ARGS, whose types must be OP's."
  (intern-term (list* :app (op-id op) (mapcar #'term-id args)) :app op args (op-res op)
               (1+ (loop for a in args sum (term-size a)))))

(defun app (name &rest args)
  "The term that applies the operator named NAME to ARGS, at their types."
  (app-op (find-op name (mapcar #'term-type args)) args))

(defun lam (params body)
  "The function of the variables PARAMS whose value is BODY. The binder adds no size of its own."
  (intern-term (list* :lam (term-id body) (mapcar #'term-id params)) :lam params (list body)
               (fn-type (mapcar #'term-type params) (term-type body)) (term-size body)))

(defun true () (const t :bool))
(defun false () (const nil :bool))

(defun term-body (term) (first (term-args term)))

(defun term-variables (term)
  "The free variables of TERM, each once, in order of first appearance."
  (let ((seen '()))
    (labels ((walk (term bound)
               (ecase (term-kind term)
                 (:var (unless (or (member term bound) (member term seen)) (push term seen)))
                 ((:const :hole))
                 (:app (dolist (a (term-args term)) (walk a bound)))
                 (:lam (walk (term-body term) (append (term-head term) bound))))))
      (walk term nil))
    (nreverse seen)))

(defun term-holes (term)
  (let ((seen '()))
    (labels ((walk (term)
               (case (term-kind term)
                 (:hole (pushnew term seen))
                 ((:app :lam) (mapc #'walk (term-args term))))))
      (walk term))
    (nreverse seen)))

(defun app-op-retyped (op args)
  "Apply the operator named as OP is to ARGS. The types of ARGS may differ from OP's after a
substitution, so the operator is looked up again."
  (if (every (lambda (a type) (equal (term-type a) type)) args (op-args op))
      (app-op op args)
      (apply #'app (op-name op) args)))

(defun substitute-term (term replacements)
  "TERM with each leaf that appears as a key of the alist REPLACEMENTS replaced by its value."
  (labels ((walk (term)
             (let ((hit (assoc term replacements)))
               (cond (hit (cdr hit))
                     ((eq :app (term-kind term))
                      (app-op-retyped (term-head term) (mapcar #'walk (term-args term))))
                     ((eq :lam (term-kind term))
                      (lam (term-head term) (walk (term-body term))))
                     (t term)))))
    (walk term)))

;;; --- terms as s-expressions ---
;;;
;;; Written form: an integer for a numeric constant, TRUE and FALSE, (seq v1 v2 ...) for a
;;; constant sequence, a symbol for a variable, ?name for a hole, (lambda (p1 p2) body), and
;;; (operator arg ...).

(defun value->sexp (value type)
  (case (type-kind type)
    (:bool (if value 'true 'false))
    (:seq (cons 'seq (map 'list (lambda (v) (value->sexp v (second type))) value)))
    (:tuple (cons 'tuple (mapcar #'value->sexp value (rest type))))
    (:fn (fnval-name value))
    (t value)))

(defun term->sexp (term)
  (ecase (term-kind term)
    (:var (term-head term))
    (:hole (term-head term))
    (:const (value->sexp (term-head term) (term-type term)))
    (:lam `(lambda ,(mapcar #'term-head (term-head term)) ,(term->sexp (term-body term))))
    (:app (cons (op-name (term-head term)) (mapcar #'term->sexp (term-args term))))))

(defmethod print-object ((term term) stream)
  (let ((*print-case* :downcase) (*package* (find-package '#:lisploop2)))
    (format stream "~s" (term->sexp term))))

(defun deferred-argument-p (sexp)
  "True for a written argument whose type cannot be read off it alone: a numeric literal, which
may belong to the integers or to a field, and a lambda, whose parameters have no written types."
  (or (integerp sexp) (and (consp sexp) (eq 'lambda (first sexp)))))

(defun ground-type-p (pattern)
  (cond ((type-variable-p pattern) nil)
        ((atom pattern) t)
        (t (every #'ground-type-p pattern))))

(defun partial-substitute (pattern bindings)
  "PATTERN with the type variables that BINDINGS knows replaced, and the others left in place."
  (cond ((type-variable-p pattern)
         (let ((bound (assoc pattern bindings))) (if bound (cdr bound) pattern)))
        ((atom pattern) pattern)
        (t (mapcar (lambda (p) (partial-substitute p bindings)) pattern))))

(defun parse-term (sexp env &optional expected)
  "The term written as SEXP. ENV is an alist from variable names to types. EXPECTED, when given,
is the type the term should have, possibly with type variables left in it; it decides the type
of a numeric literal and the parameter types of a lambda."
  (cond ((integerp sexp)
         (const sexp (if (and expected (ground-type-p expected) (numeric-type-p expected))
                         expected :int)))
        ((eq sexp 'true) (true))
        ((eq sexp 'false) (false))
        ((symbolp sexp)
         (let ((bound (assoc sexp env)))
           (cond (bound (var sexp (cdr bound)))
                 ((type-variable-p sexp)
                  (hole sexp (if (and expected (ground-type-p expected)) expected
                                 (error "A hole needs a known type: ~a" sexp))))
                 (t (error "Unbound variable ~a" sexp)))))
        ((eq 'seq (first sexp))
         (let ((element (if (and expected (seq-type-p expected) (ground-type-p expected))
                            (second expected) :int)))
           (const (coerce (rest sexp) 'simple-vector) (seq-of element))))
        ((eq 'lambda (first sexp))
         (destructuring-bind (params body) (rest sexp)
           (unless (and expected (fn-type-p expected) (ground-type-p (second expected))
                        (= (length params) (length (second expected))))
             (error "The parameter types of ~s are not determined by its context" sexp))
           (let ((vars (mapcar #'var params (second expected))))
             (lam vars (parse-term body (append (mapcar #'cons params (second expected)) env)
                                   (third expected))))))
        (t (parse-application sexp env expected))))

(defun parse-application (sexp env expected)
  (let* ((name (first sexp)) (written (rest sexp)) (n (length written)) (failures '()))
    (dolist (def (or (gethash name *opdefs*) (error "Unknown operator ~a in ~s" name sexp)))
      (when (= n (length (opdef-args def)))
        (handler-case
            (let ((bindings (if expected
                                (let ((b (match-partial (opdef-res def) expected nil)))
                                  (if (eq b :fail) (error "result type mismatch") b))
                                nil))
                  (args (make-list n)))
              ;; arguments whose type can be read off them first, then the deferred ones
              (dolist (deferred '(nil t))
                (loop for w in written for pattern in (opdef-args def) for k from 0
                      when (eq deferred (and (deferred-argument-p w) t))
                        do (let ((arg (parse-term w env (partial-substitute pattern bindings))))
                             (setf bindings (match-type pattern (term-type arg) bindings))
                             (when (eq bindings :fail) (error "argument type mismatch"))
                             (setf (nth k args) arg))))
              (return-from parse-application
                (app-op (find-op name (mapcar #'term-type args)) args)))
          (error (e) (push e failures)))))
    (error "Cannot type ~s~@[: ~a~]" sexp (first failures))))

(defun match-partial (pattern type bindings)
  "Like MATCH-TYPE, but TYPE may itself contain type variables, which match anything."
  (cond ((eq bindings :fail) :fail)
        ((type-variable-p type) bindings)
        ((type-variable-p pattern)
         (if (ground-type-p type) (match-type pattern type bindings) bindings))
        ((atom pattern) (if (eq pattern type) bindings :fail))
        ((atom type) :fail)
        ((/= (length pattern) (length type)) :fail)
        (t (loop for p in pattern for q in type
                 do (setf bindings (match-partial p q bindings))
                    (when (eq bindings :fail) (return :fail))
                 finally (return bindings)))))
