(in-package #:lisploop2)

;;; Evidence: three grades, and certificates that lapse.
;;;
;;; A class, a law or a solver has one of three grades (plan section 5.5).
;;;
;;;   :observed   the same column on one space. Exact for any question about that space, so two
;;;               terms in one class are interchangeable there. This is where pruning comes from.
;;;   :tested     the same on several fresh spaces as well. It may be used wherever a mistake
;;;               costs only time or a missed answer: to order a search or to propose a step.
;;;   :certified  exhaustive on a finite domain, derived from certified statements, or a declared
;;;               axiom. Only this may eliminate an alternative for all inputs.
;;;
;;; A certificate binds a grade to a statement and to the definitions the statement was checked
;;; under. It is v1's rule (v1/evidence.lisp): evidence binds to semantics, not to a status flag,
;;; so a certificate lapses by itself when anything it depends on is defined again.

(defstruct certificate
  grade         ; :observed, :tested or :certified
  method        ; how it was established, for example :exhaustive
  statement     ; the terms the certificate is about
  dependencies) ; alist from operator name to the version of its definition that was checked

(defun term-operators (term)
  "The names of the operators that TERM applies, each once."
  (let ((names '()))
    (labels ((walk (term)
               (case (term-kind term)
                 (:app (pushnew (op-name (term-head term)) names) (mapc #'walk (term-args term)))
                 (:lam (walk (term-body term))))))
      (walk term))
    names))

(defun attest (grade method &rest terms)
  "A certificate of GRADE for the statement made of TERMS, under the definitions now in force."
  (make-certificate
   :grade grade :method method :statement terms
   :dependencies (loop for name in (remove-duplicates (mapcan #'term-operators (copy-list terms)))
                       collect (cons name (definition-version name)))))

(defun certificate-current-p (certificate)
  "True while every operator the statement uses still has the definition it was checked under."
  (and certificate
       (loop for (name . version) in (certificate-dependencies certificate)
             always (eql version (definition-version name)))))

(defun licenses-elimination-p (certificate)
  "True when the certificate may be used to rule an alternative out for all inputs: it is
certified, and it has not lapsed. A tested or observed statement never licenses that."
  (and (certificate-current-p certificate)
       (eq :certified (certificate-grade certificate))))

(defun certify-law (law)
  "Check LAW on every assignment of its variables, and attach a certificate when it holds.
Returns the verdict of CERTIFY-EQUATION, and its counterexample when the law is refuted."
  (multiple-value-bind (verdict counterexample) (certify-equation (law-lhs law) (law-rhs law))
    (cond ((eq verdict :certified)
           (setf (law-grade law) :certified
                 (law-certificate law) (attest :certified :exhaustive (law-lhs law) (law-rhs law))))
          (t (setf (law-grade law) :refuted (law-certificate law) nil)))
    (values verdict counterexample)))
