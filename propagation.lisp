(in-package #:lisploop)

(defstruct propagation frame original fallback (narrowed 0) (suggested 0) (retained 0) (rejected 0))
(defstruct arithmetic-propagator domain operator position witness guard certified-p)
(defstruct propagator-library rules (versions (vm-versions)) (matchers (make-hash-table :test #'equal)))

(defun current-witness-conjecture-p (discovery)
  (let ((validation (solve-discovery-validation discovery)))
    (and validation (eq :conjecture (law-validation-status validation))
         (equalp (law-validation-snapshot validation) (law-snapshot (solve-witness-law discovery))))))

(defun prepare-propagator-library (discoveries ledger)
  "Freeze certified field rules and current integer witness conjectures.
Certificates remain scaffold evidence; the guard, witness and matcher are DSL."
  (let ((rules nil))
    (dolist (discovery discoveries)
      (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation))
             (certified (certified-solve-discovery-p discovery)))
        (charge ledger :propagator-library (+ (syntax-work (law-statement (solve-witness-law discovery)))
                                             (syntax-work (law-statement (solve-uniqueness-law discovery)))))
        (when (or certified (and (eq domain :int) (current-witness-conjecture-p discovery)))
          (push (make-arithmetic-propagator
                 :domain (copy-tree domain) :operator (copy-tree (arithmetic-relation-operator relation))
                 :position (solve-discovery-position discovery)
                 :witness (copy-tree (solve-discovery-witness discovery)) :guard (copy-tree (solve-discovery-guard discovery))
                 :certified-p certified) rules))))
    (make-propagator-library :rules (nreverse rules))))

(defun compile-propagator-matcher (rule inputs child-id)
  "Quoted decoder -> (matched, quoted known operand). Match the actual child
variable exactly; all other pattern variables are typed matching parameters."
  (let* ((domain (arithmetic-propagator-domain rule))
         (scope (acons child-id domain inputs)) (source-type (code-type scope domain))
         (parameters (arithmetic-inputs domain)) (pattern-type (code-type parameters domain))
         (pattern (lit pattern-type (arithmetic-application (arithmetic-propagator-operator rule)
                                   (arithmetic-propagator-position rule) (var 0 domain) (var 1 domain))))
         (source (var 0 source-type)) (result-type (tuple-type :bool source-type))
         (no (app (op :tuple result-type) (lit :bool nil) (lit source-type (lit domain 0)))))
    (flet ((binding (id)
             (app (op :code-bind (tuple-type pattern-type source-type source-type)) pattern source (lit :int id))))
      (values
       (app (op :if result-type)
            (app (op :code-match (tuple-type pattern-type source-type)) pattern source)
            (app (op :if result-type)
                 (app (op := source-type) (binding 1) (lit source-type (var child-id domain)))
                 (app (op :tuple result-type) (lit :bool t) (binding 0)) no)
            no)
       (list (cons 0 source-type))))))

(defun prepare-propagation-program (model inputs ledger category)
  (let ((state (start-program-validation model inputs)))
    (advance-accounted-evaluation state 100000000 ledger category category)
    (assert (eq :value (evaluation-status state)) () "Propagation preparation unresolved")
    (evaluation-value state)))

(defun evaluate-propagation-program (program values ledger category)
  (let ((state (start-validated-evaluation program values)))
    (advance-accounted-evaluation state 100000000 ledger category category)
    (assert (not (eq :unknown (evaluation-status state))) () "Propagation evaluation unresolved")
    state))

(defun match-arithmetic-propagator (library decoder inputs child-id domain ledger)
  "Meter a typed operator scan, then run DSL matchers on the shortlisted rules.
Known operands may be arbitrary parent expressions but cannot depend on the child.
Select the first applicable rule in the declared library order."
  (assert (equal (propagator-library-versions library) (vm-versions)) () "Stale propagator library")
  (charge ledger :propagator-dispatch (syntax-work decoder))
  (dolist (rule (propagator-library-rules library))
    (charge ledger :propagator-dispatch (+ 1 (syntax-work (arithmetic-propagator-operator rule))))
    (when (and (eq :app (first decoder)) (equal domain (arithmetic-propagator-domain rule))
               (equal (second decoder) (arithmetic-propagator-operator rule)))
      (let* ((key (list rule (copy-tree inputs) child-id))
             (cache (propagator-library-matchers library)))
        (charge ledger :propagator-cache (+ 1 (integer-width child-id)
                                           (loop for (id . type) in inputs sum (+ (integer-width id) (type-work type)))))
        (let ((program (or (gethash key cache)
                           (multiple-value-bind (model schema) (compile-propagator-matcher rule inputs child-id)
                             (charge ledger :propagator-compilation (syntax-work model))
                             (setf (gethash key cache) (prepare-propagation-program model schema ledger :propagator-preparation))))))
          (let ((run (evaluate-propagation-program program (list decoder) ledger :propagator-matching)))
            (when (and (eq :value (evaluation-status run)) (first (evaluation-value run)))
              (let ((known (second (evaluation-value run))))
                (charge ledger :propagator-binding (syntax-work known))
                ;; This explicit interface check also rejects a repeated child, z*z.
                (when (handler-case (equal domain (expression-type known inputs)) (error () nil))
                  (return-from match-arithmetic-propagator (values rule known))))))))))
  (values nil nil))

(defun propagate-arithmetic-child (parent decoder child-id bindings source ledger)
  "Certified rules replace requirements exactly. Integer witnesses are forward
checked against the ORIGINAL pullback and supply a separate tentative frame.
Its unchanged fallback frame must remain available to the child search."
  (let* ((inputs (schema-inputs (frame-schema parent))) (domain (schema-target (frame-schema parent)))
         (original (pullback-frame parent decoder child-id domain bindings ledger))
         (library (etypecase source
                    (solve-discovery (prepare-propagator-library (list source) ledger))
                    (propagator-library source)))
         (result (make-propagation :frame original :original original :retained (length (frame-rows original)))))
    (multiple-value-bind (rule known) (match-arithmetic-propagator library decoder inputs child-id domain ledger)
      (unless rule (return-from propagate-arithmetic-child result))
      (let* ((schema (arithmetic-inputs domain))
             (guard-program (prepare-propagation-program (arithmetic-propagator-guard rule) schema ledger :propagation-preparation))
             (witness-program (prepare-propagation-program (arithmetic-propagator-witness rule) schema ledger :propagation-preparation))
             (certified (arithmetic-propagator-certified-p rule))
             (rows
               (loop for parent-row in (frame-rows parent) for row in (frame-rows original) collect
                 (block propose
                   (let ((targets (allowed-values (row-allowed parent-row))))
                     (unless (and (listp targets) (= 1 (length targets))) (return-from propose row))
                     (let ((context (run-algebra-program known inputs (row-known parent-row) ledger :propagation-context)))
                       (unless (eq :value (evaluation-status context)) (return-from propose row))
                       (let* ((values (list (evaluation-value context) (first targets)))
                              (guard (evaluate-propagation-program guard-program values ledger :propagation-guard)))
                         (unless (and (eq :value (evaluation-status guard)) (evaluation-value guard)) (return-from propose row))
                         (let ((witness (evaluate-propagation-program witness-program values ledger :propagation-witness)))
                           (unless (eq :value (evaluation-status witness)) (return-from propose row))
                           (unless certified
                             ;; Never trust learned definedness/guards as the verification oracle.
                             (let ((check (run-algebra-program (allowed-expression (row-allowed row))
                                          (list (cons 0 domain)) (list (evaluation-value witness)) ledger :propagation-verification)))
                               (unless (and (eq :value (evaluation-status check)) (evaluation-value check))
                                 (incf (propagation-rejected result)) (return-from propose row))))
                           (if certified (incf (propagation-narrowed result)) (incf (propagation-suggested result)))
                           (let ((allowed (finite-allowed domain (list (evaluation-value witness)))))
                             (charge ledger :propagation-frame (syntax-work (allowed-expression allowed)))
                             (make-row :key (row-key row) :known (row-known row) :allowed allowed))))))))))
        (setf (propagation-frame result) (make-frame (frame-schema original) rows)
              (propagation-retained result) (- (length rows) (propagation-narrowed result) (propagation-suggested result)))
        (when (plusp (propagation-suggested result)) (setf (propagation-fallback result) original))))
    result))
