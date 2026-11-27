(in-package #:lisploop2)

;;; Exact accounting of work. Carried over from v1/vm.lisp:10-54 (plan section 9, "Ledger and work
;;; limit, as code"). A ledger is a running total with a count per category. Work is charged before
;;; its result is published, so a result never exists that has not been paid for.
;;;
;;; The unit of work in this kernel is one cell: one operator applied on one row (plan section 7.1).

(defstruct ledger (total 0) (counts nil))

(defvar *work-limit-ledger* nil)
(defvar *work-limit* nil)
(defvar *work-limit-tag* nil)

(defun remaining-work (ledger limit)
  (max 0 (min limit (if (and (eq ledger *work-limit-ledger*) *work-limit*)
                        (- *work-limit* (ledger-total ledger)) limit))))

(defmacro with-work-limit ((ledger limit cutoff) &body body)
  "Bound synchronous orchestration, including nested preparation and checking.
LIMIT is additional work for this invocation; nested calls cannot renew it.
CUTOFF is returned on interruption. Resumable controllers use explicit state instead."
  (let ((l (gensym)) (end (gensym)) (tag (gensym)) (answer (gensym)))
    `(let* ((,l ,ledger)
            (,end (+ (ledger-total ,l) (remaining-work ,l ,limit)))
            (,tag (gensym))
            (,answer
              (let ((*work-limit-ledger* ,l) (*work-limit* ,end) (*work-limit-tag* ,tag))
                (catch ,tag (cons :complete (multiple-value-list (progn ,@body)))))))
       (if (eq :complete (car ,answer)) (values-list (cdr ,answer)) ,cutoff))))

(defun charge (ledger category &optional (amount 1))
  (assert (and (integerp amount) (>= amount 0)))
  (when (and ledger (eq ledger *work-limit-ledger*) *work-limit*
             (> (+ (ledger-total ledger) amount) *work-limit*))
    (let ((remaining (- *work-limit* (ledger-total ledger))))
      (when (plusp remaining) (charge ledger category remaining)))
    (throw *work-limit-tag* '(:cutoff)))
  (when ledger
    (incf (ledger-total ledger) amount)
    (let ((entry (assoc category (ledger-counts ledger))))
      (if entry (incf (cdr entry) amount)
          (push (cons category amount) (ledger-counts ledger)))))
  amount)

(defmacro pay-debt (place budget ledger category)
  "Charge up to BUDGET units of the staged work held in PLACE to LEDGER under CATEGORY,
reduce PLACE by that amount, and return it. A result is published once PLACE is zero."
  (let ((spent (gensym "SPENT")))
    `(let ((,spent (min ,budget ,place)))
       (charge ,ledger ,category ,spent)
       (decf ,place ,spent)
       ,spent)))

(defun ledger-count (ledger category)
  (or (cdr (assoc category (ledger-counts ledger))) 0))
