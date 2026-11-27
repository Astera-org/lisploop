(in-package #:lisploop2)

;;; The evaluator: the value of one term in one environment.
;;;
;;; This is the reference semantics of the object language, and it is how a finished program is
;;; run on a row: for the verification of every finished program at the root, and for held-out
;;; rows. The store evaluates by column instead (store.lisp). The two share only the cell
;;; functions of the operators, and a test contract requires that they agree.
;;;
;;; Metering. Every application costs one unit, counted in *SPENT* before the operator runs. An
;;; evaluation that would pass *FUEL* yields the out-of-fuel cell instead of a value. A status
;;; propagates through every strict operator, so a fault or a cut-off anywhere inside a term is
;;; the value of the whole term, unless a TRY or an IF branch that is not taken hides it.

(defun make-closure (term env)
  "The function value of the lambda TERM in ENV."
  (let ((params (mapcar #'term-head (term-head term))) (body (term-body term)))
    (make-fnval (list term env) (length params)
                (lambda (&rest values) (ev body (pairlis params values env))))))

(defun ev (term env)
  "The value of TERM, or a status. ENV is an alist from variable names to values."
  (ecase (term-kind term)
    (:const (term-head term))
    (:var (let ((bound (assoc (term-head term) env)))
            (if bound (cdr bound) (error "Unbound variable ~a" (term-head term)))))
    (:lam (make-closure term env))
    (:hole (error "A term with a hole has no value: ~a" term))
    (:app
     (if (> (incf *spent*) *fuel*)
         *fuel-out*
         (let* ((op (term-head term)) (args (term-args term)))
           (case (op-name op)
             ;; the two lazy forms do not evaluate what they do not use
             (if (let ((g (ev (first args) env)))
                   (cond ((status-p g) g)
                         (g (ev (second args) env))
                         (t (ev (third args) env)))))
             (try (let ((v (ev (first args) env)))
                    (if (fault-p v) (ev (second args) env) v)))
             ;; a strict operator: the arguments in order, and the first status among them wins
             (t (let ((values '()))
                  (dolist (arg args (apply (op-fn op) (nreverse values)))
                    (let ((v (ev arg env)))
                      (when (status-p v) (return v))
                      (push v values)))))))))))

(defun run-term (term env &key (fuel 1000000))
  "Evaluate TERM in ENV with a fuel limit. Returns the value or status, and the work spent."
  (let ((*spent* 0) (*fuel* fuel))
    (let ((value (ev term env)))
      (values value *spent*))))

;;; --- library functions: operators defined by a term ---

(defun define-function (name params types body-sexp)
  "Define the operator NAME as the function of PARAMS, of the given TYPES, whose value is the
term written BODY-SEXP. Applying it costs what evaluating its body costs."
  (let* ((env (mapcar #'cons params types))
         (body (parse-term body-sexp env)))
    (define-op name types (term-type body)
      (lambda (bindings) (declare (ignore bindings))
        (lambda (&rest values) (ev body (pairlis params values)))))
    body))

(defun primitive-fnval (name &rest arg-types)
  "The function value that applies the operator NAME at ARG-TYPES: how a library function or a
primitive is passed as an argument."
  (let ((op (find-op name arg-types)))
    (make-fnval name (op-arity op)
                (lambda (&rest values)
                  (let ((bad (find-if #'status-p values)))
                    (or bad (apply (op-fn op) values)))))))
