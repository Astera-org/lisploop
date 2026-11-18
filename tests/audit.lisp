(in-package #:lisploop)

(deftest audit-folding-retains-partial-code-conditions
  ;; Branch-local assumptions are valid only after the condition has run.
  (let* ((ctype (code-type nil :bool))
         (inputs (list (cons 0 ctype)))
         (condition (app (op :code-eval ctype) (var 0 ctype)))
         (bad-code (app (op := :int)
                        (app (op :/ :int) (lit :int 1) (lit :int 0))
                        (lit :int 0))))
    (dolist (branches (list (list (lit :int 7) (lit :int 7))
                           (list (lit :bool nil) (lit :bool nil))))
      (let* ((expr (app (op :if (ast-type (first branches))) condition
                        (first branches) (second branches)))
             (folded (fold-constants expr)))
        (check (eq :error (evaluation-status (evaluate expr inputs (list bad-code)))))
        (check (eq :error (evaluation-status (evaluate folded inputs (list bad-code)))))
        (dolist (value '(nil t))
          (check (equal (result expr inputs (list (lit :bool value)))
                        (result folded inputs (list (lit :bool value))))))))))

(deftest audit-certified-nonunique-propagation-keeps-fallback
  (with-knowledge-library ((make-knowledge-library))
    (let* ((domain (gf 5))
           (req (app (op := domain)
                     (app (op :* domain) (lit domain 0) (var 0 domain))
                     (lit domain 0)))
           (frame (make-frame (make-schema :inputs nil :target domain)
                              (list (make-row :key 0 :known nil :requirement req)))))
      ;; Zero is a sound witness for 0*z=0, but all field values solve it.
      (register-knowledge-solver :* :domain domain :position 1
                                :witness (lit domain 0)
                                :guard (bool-and
                                        (app (op := domain) (var 0 domain) (lit domain 0))
                                        (app (op := domain) (var 1 domain) (lit domain 0)))
                                :certified-p t :unique-p nil)
      (let ((prop (propagate-requirements frame *knowledge-library* (make-ledger))))
        (check (= 1 (propagation-ambiguous prop)))
        (check (eq frame (propagation-fallback prop)))
        (dolist (value '(0 1 2 3 4))
          (check (accepts (row-requirement (first (frame-rows (propagation-fallback prop))))
                          value)))))))

(deftest audit-map-inversion-does-not-promote-scalar-evidence
  (with-knowledge-library ((make-knowledge-library))
    (let* ((domain (gf 5))
           (seq-type (sequence-type domain))
           (ctype (code-type (list (cons 0 domain)) domain))
           (xs (var 0 seq-type))
           (code (var 1 ctype)))
      (define-function :audit-map (list (cons 0 seq-type) (cons 1 ctype)) seq-type
        (lambda (self)
          (app (op :if seq-type)
               (app (op := seq-type) xs (lit seq-type nil)) (lit seq-type nil)
               (app (op :cons domain)
                    (app (op :code-eval ctype) code
                         (app (op :at seq-type) xs (lit :int 0)))
                    (app self (app (op :tail domain) xs) code)))))
      ;; Correct, unique inverse of k+z=c ONLY on the declared domain c=0.
      (register-knowledge-solver :+ :domain domain :position 1
                                :witness (app (op :- domain) (lit domain 0) (var 0 domain))
                                :guard (app (op := domain) (var 1 domain) (lit domain 0))
                                :certified-p t :unique-p t)
      (induce-functorial-solvers *knowledge-library*)
      (let ((entry (find-knowledge-entry :audit-map/invert-+-1)))
        (check entry)
        (check (not (getf (knowledge-entry-metadata entry) :certified-p))))
      (dolist (target '(0 2))
        (let* ((req (app (op := seq-type)
                         (app (op :audit-map) (var 0 seq-type)
                              (lit ctype (app (op :+ domain) (lit domain 1) (var 0 domain))))
                         (lit seq-type (list target))))
               (frame (make-frame (make-schema :inputs nil :target seq-type)
                                  (list (make-row :key 0 :known nil :requirement req))))
               (prop (propagate-requirements frame *knowledge-library* (make-ledger))))
          (check (zerop (propagation-narrowed prop)))
          (if (zerop target)
              (progn
                (check (= 1 (propagation-suggested prop)))
                (check (eq frame (propagation-fallback prop)))
                (check (accepts (row-requirement (first (frame-rows (propagation-frame prop)))) '(4))))
              (progn
                (check (= 1 (propagation-rejected prop)))
                (check (equal req (row-requirement (first (frame-rows (propagation-frame prop))))))
                (check (accepts req '(1))))))))))

(deftest audit-projections-and-strict-argument-demand
  (let* ((ct (code-type nil :int)) (scope (list (cons 0 ct)))
         (bad (app (op :/ :int) (lit :int 1) (lit :int 0)))
         (call (app (op :code-eval ct) (var 0 ct)))
         (expr (app (op :tail :int) (app (op :cons :int) call (lit (sequence-type :int) nil)))))
    (check (eq :error (evaluation-status (evaluate (fold-constants expr) scope (list bad)))))
    (with-knowledge-library ((make-knowledge-library))
      (define-function :audit-ignore '((0 . :int)) :int
        (app (op :if :int) (lit :bool nil) (var 0 :int) (lit :int 7)))
      (let ((expr (app (op :audit-ignore) call)))
        (check (eq :error (evaluation-status (evaluate expr scope (list bad)))))
        (check (eq :error (evaluation-status (evaluate (fold-constants expr) scope (list bad)))))))))

(deftest audit-evidence-tracks-function-bodies-and-persistence
  (with-knowledge-library ((make-knowledge-library))
    (let* ((d (gf 3)) (scope (list (cons 0 d))) (x (var 0 d)))
      (define-function :audit-id scope d x)
      (let* ((law (make-law d scope (app (op :audit-id) x) x))
             (validation (resume-law-validation (start-law-validation law) 100000))
             (entry (register-knowledge-law validation)))
        (check (knowledge-evidence-current-p entry :equivalence))
        (check (as-rewrite-library *knowledge-library* :domain d))
        (let ((packet (serialize-knowledge-library)))
          (with-knowledge-library ((deserialize-knowledge-library packet))
            (check (knowledge-evidence-current-p (find-knowledge-entry (knowledge-entry-id entry)) :equivalence))))
        (define-function :audit-id scope d (lit d 0))
        (check (not (knowledge-evidence-current-p entry :equivalence)))
        (check (null (as-rewrite-library *knowledge-library* :domain d)))
        ;; A legacy status/certificate must not regain authority on reload.
        (setf (knowledge-entry-status entry) :validated
              (knowledge-entry-certificate entry) '(:kind :exhaustive))
        (let ((packet (serialize-knowledge-library)))
          (with-knowledge-library ((deserialize-knowledge-library packet))
            (check (null (as-rewrite-library *knowledge-library* :domain d)))))))))

(deftest audit-replacement-updates-all-indexes
  (with-knowledge-library ((make-knowledge-library))
    (register-knowledge-entry
     (make-knowledge-entry :id :audit-entry :kind :relation :inputs nil :target :int
                           :expression (lit :int 1) :edges '((:derived-from :old))))
    (register-knowledge-entry
     (make-knowledge-entry :id :audit-entry :kind :heuristic :inputs nil :target :int
                           :expression (lit :int 2) :edges '((:derived-from :new))))
    (check (null (knowledge-edges-to :old)))
    (check (null (knowledge-entries-of-kind :relation)))
    (check (equal '((:derived-from :audit-entry)) (knowledge-edges-to :new)))
    (define-function :audit-f nil :int (lit :int 1))
    (register-knowledge-entry
     (make-knowledge-entry :id :audit-f :kind :function :inputs nil :target :int :expression (lit :int 2)))
    (check (= 2 (result (app (op :audit-f)))))
    (remove-knowledge-entry :audit-f)
    (check (null (find-function-definition :audit-f)))))

(deftest audit-guarded-involution-retains-other-preimages
  (with-knowledge-library ((make-knowledge-library))
    (let* ((d (gf 3)) (scope (list (cons 0 d))) (x (var 0 d)))
      (define-function :audit-collapse scope d (lit d 0))
      (register-knowledge-law
       (resume-law-validation
        (start-law-validation
         (make-law d scope (app (op :audit-collapse) (app (op :audit-collapse) x)) x
                   :guard (app (op := d) x (lit d 0)))) 100000))
      (induce-involution-solvers *knowledge-library*)
      (let* ((req (app (op := d) (app (op :audit-collapse) x) (lit d 0)))
             (frame (make-frame (make-schema :inputs nil :target d)
                                (list (make-row :key 0 :known nil :requirement req))))
             (prop (propagate-requirements frame *knowledge-library* (make-ledger))))
        (check (= 1 (propagation-ambiguous prop)))
        (check (eq frame (propagation-fallback prop)))
        (dolist (value '(0 1 2))
          (check (accepts (row-requirement (first (frame-rows (propagation-fallback prop)))) value)))))))

(deftest audit-inversion-handles-ternary-and-joint-unknowns
  (with-knowledge-library ((make-knowledge-library))
    (let* ((d (gf 3)) (scope (loop for i below 3 collect (cons i d)))
           (pair (tuple-type d d)))
      (define-function :audit-add3 scope d
        (app (op :+ d) (var 0 d) (app (op :+ d) (var 1 d) (var 2 d))))
      (register-knowledge-solver :audit-add3 :domain d :position 2
        :witness (app (op :- d) (var 2 d) (app (op :+ d) (var 0 d) (var 1 d)))
        :certified-p t)
      (let* ((req (app (op := d) (app (op :audit-add3) (lit d 1) (lit d 2) (var 0 d)) (lit d 2)))
             (frame (make-frame (make-schema :inputs nil :target d)
                                (list (make-row :key 0 :known nil :requirement req))))
             (prop (propagate-requirements frame *knowledge-library* (make-ledger))))
        (check (= 1 (propagation-narrowed prop)))
        (check (equal '(2) (extract-allowed-values (row-requirement (first (frame-rows (propagation-frame prop))))))))
      (define-function :audit-pair scope pair
        (app (op :tuple pair) (var 0 d) (app (op :+ d) (var 1 d) (var 2 d))))
      (let ((entry (register-knowledge-solver :audit-pair :domain d :position '(0 2)
                    :witness (app (op :tuple pair)
                                  (app (op :at pair) (var 1 pair) (lit :int 0))
                                  (app (op :- d) (app (op :at pair) (var 1 pair) (lit :int 1)) (var 0 d)))
                    :certified-p t)))
        (check (knowledge-evidence-current-p entry :witness))
        (check (knowledge-evidence-current-p entry :uniqueness))))))

(deftest audit-type-roles-are-independent-of-parameter-order
  (with-knowledge-library ((make-knowledge-library))
    (let* ((st (sequence-type :int)) (ct (code-type '((0 . :int)) :int)))
      (define-function :audit-indexed (list (cons 8 ct) (cons 2 :int) (cons 6 st)) :int
        (app (op :code-eval ct) (var 8 ct) (app (op :at st) (var 6 st) (var 2 :int))))
      (let* ((d (gf 5)) (new (retype-function-definition :audit-indexed d :new-name :audit-indexed-gf))
             (scope (function-definition-inputs new)))
        (check (eq :int (cdr (assoc 2 scope))))
        (check (equal (sequence-type d) (cdr (assoc 6 scope))))
        (check (= 3 (result (app (op :audit-indexed-gf) (var 8 (cdr (assoc 8 scope)))
                                 (var 2 :int) (var 6 (sequence-type d)))
                            scope (list (var 0 d) 1 '(2 3 4))))))
      (let ((dry (retype-function-definition :audit-indexed (gf 3) :new-name :audit-dry :register-p nil)))
        (check dry)
        (check (null (find-function-definition :audit-dry)))))))

(deftest audit-multiple-code-parameters-use-generic-partial-applications
  (with-knowledge-library ((make-knowledge-library))
    (let* ((ct (code-type '((0 . :int)) :int))
           (scope '((7 . :int)))
           (increment (lit ct (app (op :+ :int) (var 0 :int) (lit :int 1))))
           (double (app (op :+ :int) (var 0 :int) (var 0 :int)))
           (frame (simple-frame :int scope '(((2) 5) ((4) 9))))
           (*library-code-argument-work* 0))
      (define-function :audit-compose (list (cons 9 ct) (cons 4 :int) (cons 1 ct)) :int
        (app (op :code-eval ct) (var 1 ct)
             (app (op :code-eval ct) (var 9 ct) (var 4 :int))))
      (let* ((language (make-language :int scope :operators (list (op :audit-compose) (op :+ :int))
                                     :literals '(1) :constants (list increment)))
             (proposals (library-decompositions frame language))
             (wanted (app (op :audit-compose) (var 8 ct) (var 7 :int) increment))
             (proposal (find wanted proposals :key #'decomposition-decoder :test #'equal)))
        (check (= 1 (length (candidate-library-definitions language))))
        (check proposal)
        (let ((model (compose-lifted-model (decomposition-decoder proposal) (decomposition-child-id proposal)
                                           ct double (decomposition-bindings proposal))))
          (check (= 15 (result model scope '(7)))))
        (multiple-value-bind (child coupled reserve)
            (lift-frame frame wanted 8 ct (decomposition-bindings proposal))
          (declare (ignore coupled reserve))
          (dolist (row (frame-rows child))
            (check (row-satisfied-p row double (schema-inputs (frame-schema child))))))))))

(deftest audit-learned-syntax-transformer-is-portable-library-code
  (with-knowledge-library ((make-knowledge-library))
    (let* ((ct (code-type '((0 . :int)) :int))
           (scope (list (cons 0 ct)))
           (x (var 0 :int))
           (frame (simple-frame ct scope
                    (list (list (list (app (op :+ :int) x (lit :int 1))) x)
                          (list (list (app (op :* :int) (lit :int 3) x)) (lit :int 3)))))
           (language (make-language :int scope
                        :operators (list (op :code-child (tuple-type ct ct))) :literals '(0 1)))
           (expected (app (op :code-child (tuple-type ct ct)) (var 0 ct) (lit :int 0))))
      (multiple-value-bind (entry job)
          (learn-knowledge-transformer frame language (description-size expected scope) 20000 :id :audit-transform)
        (check entry)
        (check (plusp (ledger-total (search-job-ledger job))))
        (check (eq :empirical (knowledge-entry-status entry)))
        (check (not (knowledge-evidence-current-p entry :equivalence)))
        (let* ((held-out (app (op :- :int) (app (op :+ :int) x x) (lit :int 42)))
               (packet (serialize-knowledge-library)))
          (with-knowledge-library ((deserialize-knowledge-library packet))
            (let ((run (consume-knowledge-entry :audit-transform (list held-out))))
              (check (eq :value (evaluation-status run)))
              (check (equal (second held-out) (evaluation-value run))))))))))

(deftest audit-refinement-publishes-immutable-scopes-after-payment
  (let* ((inputs '((0 . :int)))
         (frame (simple-frame :int inputs '(((0) 0))))
         (reserve (make-row :key :reserve :known '(3) :requirement (singleton-requirement :int 9)))
         (language (make-language :int inputs))
         (job (start-synthesis frame language 60))
         (node (synthesis-job-root job))
         (before (synthesis-node-frame node))
         (candidate (app (op :+ :int) (var 0 :int) (var 0 :int))))
    (setf (synthesis-node-reserve-rows node) (list reserve))
    (check (eq :unknown (row-satisfaction reserve candidate inputs :budget 0)))
    (check (refine-lifted-node-from-counterexample job node candidate))
    (check (eq before (synthesis-node-frame node)))
    (check (= 1 (length (frame-rows before))))
    ;; Stepping 1 work unit leaves the refinement unpublished while debt remains,
    ;; and stepping until publication obeys every intermediate limit without mutating `before`.
    (resume-synthesis job 1)
    (check (= 1 (ledger-total (synthesis-job-ledger job))))
    (check (eq before (synthesis-node-frame node)))
    (loop for limit from 2 to 500
          until (not (eq before (synthesis-node-frame node)))
          do (resume-synthesis job limit)
             (check (<= (ledger-total (synthesis-job-ledger job)) limit)))
    (check (not (eq before (synthesis-node-frame node))))
    (check (= 1 (length (frame-rows before))))
    (check (= 2 (length (frame-rows (synthesis-node-frame node)))))
    (check (= 1 (synthesis-node-revision node)))
    (check (null (synthesis-node-reserve-rows node)))
    (check (not (equal (child-scope-signature frame language)
                       (child-scope-signature frame language (list reserve)))))
    (let ((renamed (snapshot-frame frame)))
      (setf (row-key (first (frame-rows renamed))) :different-origin)
      (check (equal (child-scope-signature frame language (list reserve))
                    (child-scope-signature renamed language (list reserve)))))))

(deftest audit-decoder-template-retrieval-renames-and-reorders-parameters
  (with-knowledge-library ((make-knowledge-library))
    (let* ((inputs '((7 . :int) (11 . :bool)))
           (decoder (app (op :if :int) (var 11 :bool)
                          (app (op :+ :int) (var 12 :int) (var 7 :int)) (var 7 :int)))
           (proposal (make-decomposition :decoder decoder :child-id 12 :child-type :int
                       :bindings (list (cons 0 (var 7 :int)) (cons 1 (var 11 :bool))))))
      (remember-decoder-template proposal inputs)
      (with-knowledge-library ((deserialize-knowledge-library (serialize-knowledge-library)))
        (let* ((new-inputs '((9 . :bool) (2 . :int)))
               (frame (simple-frame :int new-inputs '(((t 3) 9) ((nil 4) 4))))
               (language (make-language :int new-inputs))
               (retrieved (learned-decoder-decompositions frame language 60 nil (make-ledger))))
          (check (= 1 (length retrieved)))
          (let* ((p (first retrieved))
                 (child (app (op :+ :int) (var 0 :int) (var 0 :int)))
                 (model (compose-model (decomposition-decoder p) (decomposition-child-id p)
                                       child (decomposition-bindings p))))
            (check (= 21 (result model new-inputs '(t 7))))
            (check (= 7 (result model new-inputs '(nil 7))))))))))

(deftest audit-restore-forward-function-dependencies
  (with-knowledge-library ((make-knowledge-library))
    (define-function :audit-callee '((0 . :int)) :int (app (op :+ :int) (var 0 :int) (lit :int 1)))
    (define-function :audit-caller '((0 . :int)) :int (app (op :audit-callee) (var 0 :int)))
    (let* ((packet (serialize-knowledge-library))
           (plist (rest packet)))
      (setf (getf plist :entries) (reverse (getf plist :entries)))
      (with-knowledge-library ((deserialize-knowledge-library packet))
        (check (= 8 (result (app (op :audit-caller) (lit :int 7)))))))))

(deftest audit-template-inference-preserves-quote-scopes-and-captures
  (with-knowledge-library ((make-knowledge-library))
    (let* ((inner (code-type '((0 . :int)) :int))
           (full (code-type '((0 . :int) (1 . :int)) :int))
           (tuple (tuple-type inner :int))
           (closed (app (op :code-subst (tuple-type full tuple inner))
                         (lit full (app (op :+ :int) (var 0 :int) (var 1 :int)))
                         (app (op :tuple tuple) (lit inner (var 0 :int)) (var 8 :int)))))
      (define-function :audit-capture '((8 . :int)) inner closed)
      (let* ((d (gf 5)) (target (code-type (list (cons 0 d)) d))
             (instance (instantiate-function-template :audit-capture (list d) target :name :audit-capture-gf))
             (expr (app (op :code-eval target) (app (op :audit-capture-gf) (lit d 4)) (lit d 3))))
        (check instance)
        (check (= 2 (result expr)))
        (check-codec-roundtrip expr nil))
      (let ((scopes nil))
        (walk-typed-ast closed '((8 . :int))
          (lambda (node scope) (when (var-p node) (push (list (ast-id node) scope) scopes))))
        (check (member '(8 ((8 . :int))) scopes :test #'equal))
        (check (member '(0 ((0 . :int) (1 . :int))) scopes :test #'equal))
        (check (member '(0 ((0 . :int))) scopes :test #'equal))))))

(deftest audit-uncertified-descriptors-cannot-prune-constant-functions
  (with-knowledge-library ((make-knowledge-library))
    (let* ((st (sequence-type :int)) (ct (code-type '((0 . :int)) :bool))
           (frame (simple-frame st (list (cons 0 st)) '((((1)) (9))))))
      (define-function :audit-constant (list (cons 0 st) (cons 1 ct)) st (lit st '(9)))
      (check (library-function-descriptor-compatible-p frame 0 :audit-constant (make-ledger)))
      (register-knowledge-entry
       (make-knowledge-entry :kind :descriptor :inputs (list (cons 0 st) (cons 1 st)) :target :bool
                             :expression (lit :bool nil) :status :validated :edges '((:describes :audit-constant))))
      ;; The implication FALSE => FALSE is valid, but its conclusion alone is not.
      (register-knowledge-entry
       (attest-knowledge-entry
        (make-knowledge-entry :kind :descriptor :inputs (list (cons 0 st) (cons 1 st)) :target :bool
                              :expression (lit :bool nil) :guard (lit :bool nil)
                              :edges '((:describes :audit-constant))) :trusted-axiom '(:necessary)))
      (check (library-function-descriptor-compatible-p frame 0 :audit-constant (make-ledger))))))

(deftest audit-solver-certificate-revocation-invalidates-cache
  (with-knowledge-library ((make-knowledge-library))
    (let* ((d (gf 3))
           (entry (register-knowledge-solver :+ :domain d :position 1
                     :witness (app (op :- d) (var 1 d) (var 0 d)) :certified-p t))
           (prepared (as-propagator-library *knowledge-library*)))
      (check (propagator-certified-current-p (first (propagator-library-rules prepared))))
      (setf (knowledge-entry-certificate entry) nil)
      (let ((replacement (as-propagator-library *knowledge-library*)))
        (check (not (eq prepared replacement)))
        (check (not (propagator-certified-current-p (first (propagator-library-rules prepared)))))
        (check (not (propagator-certified-current-p (first (propagator-library-rules replacement)))))))))

(deftest audit-pooled-residuals-charge-every-executable-copy
  (with-knowledge-library ((make-knowledge-library))
    (let* ((a (register-knowledge-relation :audit-a '((10 21) (20 41)) :inputs '((0 . :int))))
           (b (register-knowledge-relation :audit-b '((30 61) (40 81)) :inputs '((0 . :int))))
           (old (+ (knowledge-entry-bits a) (knowledge-entry-bits b))))
      (consolidate-residual-relations (list a b) *knowledge-library* (make-ledger))
      (check (knowledge-entry-expression a))
      (check (knowledge-entry-expression b))
      (check (= (+ (knowledge-entry-gain a) (knowledge-entry-gain b))
                (- old (knowledge-entry-bits a) (knowledge-entry-bits b))))
      (let ((packet (serialize-knowledge-library)) (bits (knowledge-library-storage-bits)))
        (check (> bits (+ (knowledge-entry-bits a) (knowledge-entry-bits b))))
        (with-knowledge-library ((deserialize-knowledge-library packet))
          (check (= bits (knowledge-library-storage-bits))))))))

(deftest audit-revision-detaches-followers-of-retired-descendants
  (let* ((frame (simple-frame :int '((0 . :int)) '(((1) 2))))
         (language (make-language :int '((0 . :int))))
         (job (start-synthesis frame language 40))
         (root (synthesis-job-root job))
         (descendant (make-synthesis-node :id 1 :parent root :frame (snapshot-frame frame) :language language))
         (follower (make-synthesis-node :id 2 :frame (snapshot-frame frame) :language language :reused-from descendant)))
    (setf (synthesis-node-followers descendant) (list follower)
          (synthesis-job-nodes job) (list root descendant follower))
    (restart-revised-node job root (snapshot-frame frame))
    (check (eq :done (synthesis-node-phase descendant)))
    (check (null (synthesis-node-reused-from follower)))
    (check (eq :search (synthesis-node-phase follower)))
    (check (= 1 (synthesis-node-revision follower)))
    (check (null (synthesis-node-followers descendant)))))


(deftest audit-cegar-refinement-obeys-unit-step-budgets
  ;; Active row x0=2 -> 4 admits constant '4 first; root verification refutes (:map xs '4)
  ;; on reserve row ((3)) -> (6), triggering budgeted CEGAR refinement before finding (+ x0 x0).
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:map))
    (let* ((*max-active-lifted-rows* 1)
           (seq-type (sequence-type :int))
           (inputs (list (cons 0 seq-type)))
           (frame (simple-frame seq-type inputs '((((2)) (4)) (((3)) (6)))))
           (language (make-language :int inputs
                                    :operators (list (op :map) (op :+ :int))
                                    :literals '(4)))
           (batch (check-synthesis-resumption
                   (lambda ()
                     (start-heuristic-synthesis frame language 80
                                                :child-bound 45
                                                :library-proposals-p t
                                                :additive-p nil
                                                :conditional-p nil))
                   :budget 200000
                   :stop-on-first t
                   :exhaustive-p t)))
      (check (synthesis-job-best batch))
      (check (some (lambda (n) (plusp (synthesis-node-revision n)))
                   (synthesis-job-nodes batch)))
      (check-synthesized-model (candidate-expression (synthesis-job-best batch)) frame
                               :must-call-ops '(:map)
                               :held-out '((((5 -2)) (10 -4)))))))

;;; Defects found by the audit of Plan 9 (`plan9-audit.md` §9, `plan9.md` §1.2).

(deftest audit-totality-is-a-least-fixed-point
  ;; A function is total through callees that are total already. A cycle of calls cannot
  ;; vouch for itself, whatever its members were certified as before a redefinition.
  (with-knowledge-library ((make-knowledge-library))
    (let ((n (var 0 :int)) (scope '((0 . :int))))
      (flet ((total-p (name) (function-definition-total-p (find-function-definition name)))
             (call (name) (app (op name) (lit :int 3)))
             (successor () (app (op :+ :int) n (lit :int 1))))
        (define-function :audit-g scope :int (successor))
        (define-function :audit-f scope :int (app (op :audit-g) n))
        (check (and (total-p :audit-f) (total-p :audit-g)))
        (check (= 4 (result (call :audit-f))))
        ;; The callee now calls back: neither returns, and neither may be read as total.
        (define-function :audit-g scope :int (app (op :audit-f) n))
        (dolist (name '(:audit-f :audit-g))
          (check (not (total-p name)))
          (check (not (provably-total-p (call name))))
          (check (not (eq :value (evaluation-status (evaluate (call name) nil nil :budget 2000))))))
        ;; Breaking the cycle certifies both again.
        (define-function :audit-g scope :int (successor))
        (check (and (total-p :audit-f) (total-p :audit-g)))
        ;; A caller listed before its callee is certified by a later pass from the bottom.
        (define-function :audit-early scope :int n)
        (define-function :audit-late scope :int (successor))
        (define-function :audit-early scope :int (app (op :audit-late) n))
        (check (< (position :audit-early *registered-function-names*)
                  (position :audit-late *registered-function-names*)))
        (check (total-p :audit-early))
        (check (provably-total-p (call :audit-early)))))
    ;; A combinator that is total given total code stays so across an unrelated definition.
    (define-standard-int-combinators :which '(:map))
    (define-function :audit-other '((0 . :int)) :int (var 0 :int))
    (let ((map (find-function-definition :map)))
      (check (not (function-definition-total-p map)))
      (check (equal '(1) (function-definition-conditional-code-params map))))))

(deftest audit-calls-of-undefined-names-are-not-total
  (with-knowledge-library ((make-knowledge-library))
    (let ((n (var 0 :int)) (scope '((0 . :int))))
      ;; A name that is registered and nothing more has no body to judge.
      (let ((*registered-function-names* (append *registered-function-names* (list :audit-ghost))))
        (check (not (provably-total-p (app (op :audit-ghost (code-type scope :int)) (lit :int 3))))))
      ;; A primitive needs no definition.
      (check (provably-total-p (app (op :+ :int) (lit :int 1) (lit :int 2))))
      ;; A caller stops being total when its callee leaves the library.
      (define-function :audit-callee scope :int (app (op :+ :int) n (lit :int 1)))
      (define-function :audit-caller scope :int (app (op :audit-callee) n))
      (check (function-definition-total-p (find-function-definition :audit-caller)))
      (remove-knowledge-entry :audit-callee)
      (check (not (defined-function-p :audit-callee)))
      (let ((caller (find-function-definition :audit-caller)))
        (check (not (function-definition-total-p caller)))
        (check (not (provably-total-p (function-definition-body caller))))))))

(deftest audit-persisted-nogood-schemas-zip-only-pointwise-maps
  ;; A persisted schema pairs the i-th input element of a row with its i-th output element
  ;; and calls one input with two outputs a conflict. A pointwise map reads its rows that
  ;; way and no other decoder does, so a lift that holds through another is not refuted.
  (with-clean-kernel-state
    (define-standard-int-combinators :which '(:map))
    (let* ((seq (sequence-type :int))
           (unary (code-type '((0 . :int)) :int))
           (xs (var 0 seq))
           (code (var 1 unary))
           (inputs (list (cons 0 seq)))
           (signature (list (cons 0 seq) (cons 1 unary)))
           (identity (lit unary (var 0 :int)))
           (successor (lit unary (term `(+ ,(var 0 :int) 1)))))
      ;; Preserves length, but its i-th output is the code's value on the length left.
      (define-function :audit-map-length signature seq
        (lambda (self)
          (term `(if (= ,xs ()) ()
                     (cons (code-eval ,code (length ,xs)) (,self (tail ,xs) ,code)))
                seq)))
      ;; Its i-th output is the code's value on the i-th input from the end.
      (define-function :audit-map-reversed signature seq
        (lambda (self)
          (term `(if (= ,xs ()) ()
                     (concat (cons (,self (tail ,xs) ,code)
                                   (cons (cons (code-eval ,code (at ,xs 0)) ()) ()))))
                seq)))
      (flet ((body (name) (function-definition-body (find-function-definition name)))
             (refuted-p (name rows)
               (let* ((parent (make-synthesis-node :id 0 :frame (simple-frame seq inputs rows)
                                                   :language (make-language :int inputs)))
                      (decoder (app (op name) xs code))
                      (proposal (make-decomposition :decoder decoder :child-id 1 :child-type unary
                                                    :lift-p t)))
                 (unless (find decoder (knowledge-entries-of-kind :nogood-schema)
                               :key #'knowledge-entry-auxiliary-code :test #'equal)
                   (register-knowledge-nogood-schema (lit :bool t) :inputs (code-inputs unary)
                                                                  :decoder decoder :child-id 1
                                                                  :child-type unary))
                 (and (check-library-nogood-schemas *knowledge-library* parent proposal (make-ledger))
                      t))))
        ;; Preserving length is not being pointwise.
        (check (function-body-pointwise-map-p :map signature (body :map) 0 1))
        (check (function-body-length-preserving-p :audit-map-length (body :audit-map-length)))
        (check (not (function-body-pointwise-map-p :audit-map-length signature
                                                   (body :audit-map-length) 0 1)))
        (check (not (function-body-pointwise-map-p :audit-map-reversed signature
                                                   (body :audit-map-reversed) 0 1)))
        ;; A map is still refuted by rows that no code satisfies, and only by those.
        (check (refuted-p :map '((((5)) (6)) (((5 7)) (9 8)))))
        (check (not (refuted-p :map '((((5)) (6)) (((5 7)) (6 8))))))
        ;; The rows below hold of the code named, and repeat an input with another output.
        (check (equal '(2 1) (result (app (op :audit-map-length) (lit seq '(5 7)) identity))))
        (check (not (refuted-p :audit-map-length '((((5)) (1)) (((5 7)) (2 1))))))
        (check (equal '(6 8) (result (app (op :audit-map-reversed) (lit seq '(7 5)) successor))))
        (check (not (refuted-p :audit-map-reversed '((((5)) (6)) (((7 5)) (6 8))))))))))

(deftest audit-relation-consolidation-fits-only-standalone-lookup-tables
  (let ((affine '((0 1) (1 4) (2 7) (3 10) (4 13) (5 16)))
        (inputs '((0 . :int))))
    (flet ((value (entry key) (evaluation-value (consume-knowledge-entry entry (list key)))))
      ;; Two sets of keys with one signature: nothing to fit them against, and no error.
      (with-knowledge-library ((make-knowledge-library))
        (let ((evens (register-knowledge-relation :audit-evens '(0 2 4 6 8) :inputs inputs :target :bool))
              (odds (register-knowledge-relation :audit-odds '(1 3 5 7 9) :inputs inputs :target :bool))
              (ledger (make-ledger)))
          (check (null (consolidate-residual-relations (list evens odds) *knowledge-library* ledger)))
          (check (zerop (ledger-total ledger)))
          (check (eq t (value evens 4)))
          (check (null (value evens 3)))
          (check (getf (consolidate-knowledge-library *knowledge-library*) :fixed-point-p))))
      ;; A default answers off the table, and a law fitted to the rows would overwrite it.
      (with-knowledge-library ((make-knowledge-library))
        (let ((entry (register-knowledge-relation :audit-default affine :inputs inputs :default -1))
              (ledger (make-ledger)))
          (check (null (consolidate-residual-relations (list entry) *knowledge-library* ledger)))
          (check (zerop (ledger-total ledger)))
          (check (= 10 (value entry 3)))
          (check (= -1 (value entry 9)))))
      ;; The same rows standing alone are condensed to the law that generates them.
      (with-knowledge-library ((make-knowledge-library))
        (let ((entry (register-knowledge-relation :audit-bare affine :inputs inputs)))
          (check (equal (list entry)
                        (consolidate-residual-relations (list entry) *knowledge-library* (make-ledger))))
          (check (plusp (knowledge-entry-gain entry)))
          (check (= 10 (value entry 3)))
          (check (= 28 (value entry 9))))))))

(deftest audit-failed-relation-fits-are-searched-once
  (let ((inputs '((0 . :int))))
    (flet ((work (&rest keys)
             (let ((ledger (make-ledger)))
               (apply #'consolidate-residual-relations (knowledge-entries-of-kind :relation)
                      *knowledge-library* ledger keys)
               (ledger-total ledger))))
      ;; One table that no small expression generates.
      (with-knowledge-library ((make-knowledge-library))
        (let ((noise '((0 17) (1 3) (2 40) (3 8) (4 29) (5 1))))
          (register-knowledge-relation :audit-noise noise :inputs inputs)
          (check (plusp (work)))
          (check (null (knowledge-entry-expression (find-knowledge-entry :audit-noise))))
          (check (zerop (work)))
          ;; The record of the search is part of the entry and survives persistence.
          (with-knowledge-library ((deserialize-knowledge-library (serialize-knowledge-library)))
            (check (zerop (work))))
          ;; The whole consolidation is then free, and a fixed point.
          (let ((report (consolidate-knowledge-library *knowledge-library*)))
            (check (zerop (getf report :work)))
            (check (getf report :fixed-point-p)))
          ;; A search with more work is another search, and so is a search of another table:
          ;; a record carried over to a table it was not made for is not believed.
          (check (plusp (work :work-limit 120000)))
          (check (zerop (work :work-limit 120000)))
          (let ((record (getf (knowledge-entry-metadata (find-knowledge-entry :audit-noise))
                              :fit-attempted)))
            (check record)
            (register-knowledge-relation :audit-noise (append noise '((6 23))) :inputs inputs
                                         :metadata (list :fit-attempted record))
            (check (plusp (work :work-limit 120000))))))
      ;; Two tables too small to fit alone, pooled.
      (with-knowledge-library ((make-knowledge-library))
        (register-knowledge-relation :audit-pool-a '((0 17) (1 3) (2 40)) :inputs inputs)
        (register-knowledge-relation :audit-pool-b '((3 8) (4 29) (5 1)) :inputs inputs)
        (check (plusp (work)))
        (check (zerop (work)))
        ;; A third table changes what is pooled.
        (register-knowledge-relation :audit-pool-c '((6 23) (7 2)) :inputs inputs)
        (check (plusp (work)))
        (check (zerop (work)))))))

(deftest audit-one-consolidation-call-reaches-a-fixed-point
  (flet ((unchanged-by-another-call-p (&rest arguments)
           (let ((version (knowledge-library-version *knowledge-library*))
                 (count (length (knowledge-library-entries *knowledge-library*)))
                 (report (apply #'consolidate-knowledge-library *knowledge-library* arguments)))
             (and (getf report :fixed-point-p)
                  (= 1 (getf report :passes))
                  (null (getf report :consolidated))
                  (= version (knowledge-library-version *knowledge-library*))
                  (= count (length (knowledge-library-entries *knowledge-library*)))))))
    ;; 1. The lift to :int runs after the :functor hook that maps its solvers through :map.
    (with-clean-kernel-state
      (define-standard-int-combinators :which '(:map))
      (dolist (prime '(5 7))
        (dolist (position '(0 1))
          (register-kernel-arithmetic-solver (gf prime) :+ position)))
      ;; Cut short after one pass, the call says that it did not reach the fixed point.
      (let* ((*consolidation-pass-limit* 1)
             (report (consolidate-knowledge-library *knowledge-library*)))
        (check (= 1 (getf report :passes)))
        (check (not (getf report :fixed-point-p)))
        (check (= 2 (length (cdr (assoc :lifted-solvers (getf report :consolidated))))))
        (check (null (find-knowledge-entry :map/functor))))
      (let ((report (consolidate-knowledge-library *knowledge-library*)))
        (check (getf report :fixed-point-p))
        (check (<= (getf report :passes) *consolidation-pass-limit*))
        (dolist (id '(:map/functor :map/invert-+-0 :map/invert-+-1))
          (check (find-knowledge-entry id))))
      (check (unchanged-by-another-call-p)))
    ;; 2. The same library in one call.
    (with-clean-kernel-state
      (define-standard-int-combinators :which '(:map))
      (dolist (prime '(5 7))
        (dolist (position '(0 1))
          (register-kernel-arithmetic-solver (gf prime) :+ position)))
      (let ((report (consolidate-knowledge-library *knowledge-library*)))
        (check (getf report :fixed-point-p))
        (dolist (id '(:map/functor :map/invert-+-0 :map/invert-+-1))
          (check (find-knowledge-entry id))))
      (check (unchanged-by-another-call-p)))
    ;; 3. The :motif hook induces laws that are then retyped, and reads the retyped ones.
    (with-clean-kernel-state
      (define-standard-int-combinators :which '(:foldr :foldl))
      (let* ((seq (sequence-type :int))
             (a (var 0 :int)) (b (var 1 :int)) (c (var 2 :int))
             (step-type (code-type '((0 . :int) (1 . :int)) :int))
             (samples '((0 0 0) (1 2 3) (-2 5 7) (4 -1 2))))
        (flet ((sampled-law (inputs left right)
                 (register-knowledge-law
                  (resume-law-validation
                   (start-law-validation (make-law :int inputs left right)
                                         :samples (mapcar (lambda (sample) (subseq sample 0 (length inputs)))
                                                          samples))
                   100000))))
          (loop for (name operator identity) in (list (list :sum (op :+ :int) 0)
                                                      (list :product (op :* :int) 1))
                do (define-function name (list (cons 0 seq)) :int
                     (app (op :foldr) (var 0 seq) (lit :int identity)
                          (lit step-type (app operator a b))))
                   (add-knowledge-edge name :refactored-by :foldr)
                   (add-knowledge-edge :foldr :abstracts name)
                   (sampled-law (arithmetic-inputs :int 3)
                                (app operator (app operator a b) c) (app operator a (app operator b c)))
                   (sampled-law (arithmetic-inputs :int 1) (app operator a (lit :int identity)) a)))
        (let ((report (consolidate-knowledge-library *knowledge-library*
                                                     :retype-domains (list (gf 5)))))
          (check (getf report :fixed-point-p))
          (check (find-knowledge-entry :foldr=foldl/monoid))
          (check (assoc :retyped-laws (getf report :consolidated))))
        (check (unchanged-by-another-call-p :retype-domains (list (gf 5))))))))

(deftest audit-descriptor-errors-never-satisfy
  ;; A descriptor whose expression errors or fails to evaluate on any guard-selected row
  ;; must return :neutral rather than :satisfied, while a clean nil still returns :violated.
  (with-clean-kernel-state
    (let* ((seq (sequence-type :int))
           (xs (var 0 seq))
           (y (var 1 :int))
           (facts (signature-facts seq :int))
           (desc (register-knowledge-entry
                  (make-knowledge-entry
                   :id :audit-head1-eq-target
                   :kind :descriptor
                   :domain :int
                   :inputs (list (cons 0 seq) (cons 1 :int))
                   :target :bool
                   :expression (app (op := :int) (app (op :at seq) xs (lit :int 1)) y)
                   :guard (lit :bool t)
                   :status :empirical
                   :metadata '(:concept :audit-second)))))
      ;; Error on pairs 0 & 1 (length-1 lists), true on pair 2 -> must NOT return :satisfied.
      (check (eq :neutral
                 (evaluate-descriptor-entry-on-frame
                  desc facts seq :int '(((10) . 99) ((20) . 88) ((30 40) . 40)) (make-ledger))))
      ;; Unresolved input on pair 0, true on pair 1 -> must NOT return :satisfied.
      (check (eq :neutral
                 (evaluate-descriptor-entry-on-frame
                  desc facts seq :int '((:unresolved . 0) ((30 40) . 40)) (make-ledger))))
      ;; Error on pair 0, clean nil on pair 1 -> sound refutation still yields :violated.
      (check (eq :violated
                 (evaluate-descriptor-entry-on-frame
                  desc facts seq :int '(((10) . 99) ((30 40) . 99)) (make-ledger))))
      ;; All rows evaluate cleanly to t -> :satisfied.
      (check (eq :satisfied
                 (evaluate-descriptor-entry-on-frame
                  desc facts seq :int '(((10 20) . 20) ((30 40) . 40)) (make-ledger))))
      ;; Non-nil :aux must also never force :satisfied when :expr errored on a row.
      (let ((desc-aux (register-knowledge-entry
                       (make-knowledge-entry
                        :id :audit-head1-eq-target-aux
                        :kind :descriptor
                        :domain :int
                        :inputs (list (cons 0 seq) (cons 1 :int))
                        :target :bool
                        :expression (app (op := :int) (app (op :at seq) xs (lit :int 1)) y)
                        :guard (lit :bool t)
                        :auxiliary-code (lit :bool t)
                        :status :empirical
                        :metadata '(:concept :audit-second-aux)))))
        (check (eq :neutral
                   (evaluate-descriptor-entry-on-frame
                    desc-aux facts seq :int '(((10) . 99) ((30 40) . 40)) (make-ledger))))))))

(deftest audit-dip-repairs-collect-all-pure-projection-collisions
  ;; Both collect-frame-nogood-clauses and node-dip-repairs handle pure projections with
  ;; multiple colliding input buckets, collecting every bucket without extra folds per bucket.
  (with-clean-kernel-state
    (let* ((inputs '((0 . :int) (1 . :int) (2 . :int)))
           (parent-frame (simple-frame :int inputs
                                       '(((0 10 100) 1)
                                         ((0 10 200) 2)
                                         ((0 10 300) 3)
                                         ((1 20 100) 4)
                                         ((1 30 100) 5))))
           (parent-node (make-synthesis-node :id 0 :frame parent-frame
                                             :language (make-language :int inputs)))
           (child-lang (make-language :int '((0 . :int))))
           (prop (make-decomposition :name '(:project 0) :decoder (var 9 :int)
                                     :child-id 9 :child-type :int
                                     :bindings (list (cons 0 (var 0 :int)))
                                     :language child-lang :bound 12)))
      (multiple-value-bind (child-frame) (pullback-frame parent-frame (var 9 :int) 9 :int (list (cons 0 (var 0 :int))))
        (multiple-value-bind (conflict) (frame-conflict-p child-frame)
          (check conflict)
          (let ((clauses (collect-frame-nogood-clauses parent-node prop child-frame conflict)))
            (check (= 2 (length clauses)))
            (check (equal '((0) (1)) (mapcar #'nogood-clause-known clauses)))
            (check (= 2 (length (conflict-distinct-parent-row-pairs parent-frame clauses))))
            ;; With only 0-step variables allowed, neither X1 nor X2 separates BOTH buckets;
            ;; with :+ allowed, DIP finds (+ X1 X2) separating both buckets simultaneously.
            (check (null (propose-dip-context-bindings parent-frame (make-language :int inputs :operators nil) clauses)))
            (check (propose-dip-context-bindings parent-frame
                                                 (make-language :int inputs :operators (list (op :+ :int)))
                                                 clauses)))))
      ;; End-to-end: node-dip-repairs launches :dip-repair directly from a colliding pure projection
      ;; and solves the frame via the repaired child even when the root's own bound (1) cannot.
      (let* ((inputs2 '((0 . :int) (1 . :int)))
             (frame2 (simple-frame :int inputs2 '(((0 1) 1) ((0 2) 2) ((1 1) 1) ((1 2) 2))))
             (lang2 (make-language :int inputs2))
             (proj2 (make-decomposition :name '(:project 0) :decoder (var 9 :int)
                                        :child-id 9 :child-type :int
                                        :bindings (list (cons 0 (var 0 :int)))
                                        :language (make-language :int '((0 . :int))) :bound 64))
             (job (start-synthesis frame2 lang2 1 :decompositions (list proj2)
                                                  :policy :heuristic :heuristic-budget nil)))
        (resume-synthesis job 50000 :stop-on-first t)
        (check (synthesis-job-best job))
        (check (some (lambda (n)
                       (let ((p (synthesis-node-proposal n)))
                         (and p (consp (decomposition-name p))
                              (eq :dip-repair (first (decomposition-name p)))
                              (synthesis-node-search n)
                              (search-job-best (synthesis-node-search n)))))
                     (synthesis-job-nodes job)))))))

(deftest audit-priority-predictor-adds-clamped-residual-to-mdl
  ;; Priority predictors add a clamped [-24, 48] signed residual to analytical MDL rather than
  ;; overwriting it, reuse precomputed program bits, and trace frames emit 6-feature signed residuals.
  (with-clean-kernel-state
    (let* ((inputs '((0 . :int)))
           (frame (simple-frame :int inputs '(((1) 1) ((2) 2) ((3) 3))))
           (lang (make-language :int inputs :operators (list (op :+ :int)) :literals '(0 1)))
           (h-model (make-heuristic-model :program (var 0 :int)
                                          :residual '((0 . 1))
                                          :exact-p nil
                                          :program-bits 10
                                          :residual-bits 15
                                          :run-work 2))
           (proposal (make-decomposition :name :p :decoder (var 9 :int) :child-id 9 :child-type :int
                                         :bindings (list (cons 0 (var 0 :int)))
                                         :language lang :bound 20 :policy-score 4)))
      (flet ((mk-job (pred)
               (let* ((job (start-synthesis frame lang 20 :policy :heuristic
                                                        :heuristic-budget nil
                                                        :priority-predictor pred))
                      (node (add-synthesis-node job (synthesis-job-root job) proposal)))
                 (setf (synthesis-node-frame node) frame
                       (synthesis-node-language node) lang
                       (synthesis-node-heuristic node) h-model
                       (synthesis-node-coupled-requirements node) '(:c1 :c2))
                 (values job node))))
        (multiple-value-bind (job0 node0) (mk-job nil)
          (let* ((l0 (make-ledger))
                 (mdl (node-priority job0 node0 frame lang h-model l0)))
            (check (= mdl (node-analytical-mdl job0 node0 h-model)))
            ;; Extreme positive & negative predictors clamp to [+48, -24] added onto MDL.
            (multiple-value-bind (j-hi n-hi) (mk-job (lit :int 500))
              (check (= (+ mdl 48) (node-priority j-hi n-hi frame lang h-model (make-ledger)))))
            (multiple-value-bind (j-lo n-lo) (mk-job (lit :int -500))
              (check (= (+ mdl -24) (node-priority j-lo n-lo frame lang h-model (make-ledger)))))
            ;; Features 4 (policy-score=4) and 5 (coupled-count=2) are passed cleanly without
            ;; recomputing full-path-program-bits / double-charging :composition.
            (multiple-value-bind (j-f6 n-f6)
                (mk-job (app (op :+ :int) (var 4 :int) (var 5 :int)))
              (let ((l6 (make-ledger)))
                (check (= (+ mdl 6) (node-priority j-f6 n-f6 frame lang h-model l6)))
                (check (equal (assoc :composition (ledger-counts l0))
                              (assoc :composition (ledger-counts l6))))))))
        ;; Trace frame uses 6-feature schema and computes subtree-grounded signed residuals (j_real - b_mdl)
        ;; clamped to [-24, 48] (negative when a verified descendant beats analytical B_MDL).
        (multiple-value-bind (job win-node) (mk-job nil)
          (let* ((root (synthesis-job-root job))
                 (cand (make-candidate :expression (var 0 :int) :size 4 :run-work 0)))
            (setf (synthesis-node-heuristic root) (make-heuristic-model :program (var 0 :int)
                                                                        :program-bits 10 :residual-bits 60))
            (synthesis-message job win-node :candidate (list :candidate cand :scope :original-root))
            (let* ((tframe (make-search-trace-frame job :ledger (make-ledger)))
                   (trows (frame-rows tframe)))
              (check (= 6 (length (schema-inputs (frame-schema tframe)))))
              (check (= 2 (length trows)))
              (check (every (lambda (r)
                              (let ((v (row-singleton-value r)))
                                (and (integerp v) (<= -24 v 48))))
                            trows))
              ;; Both root and win-node inherit win-node's 4-bit candidate, strictly below B_MDL.
              (check (some (lambda (r) (< (row-singleton-value r) 0)) trows)))))))))

(deftest audit-metric-delta-reuses-closures-and-heuristic-packets
  ;; 1. Zero-allocation replay in metric-delta never grows *closures* after the first call per template.
  ;; 2. Stage A stores winning metric packets in heuristic-packets, and Stage B reuses them at zero VM work.
  (with-clean-kernel-state
    (let* ((k (var 0 :int)) (c (var 1 :int))
           (solver (register-knowledge-solver
                    (op :- :int) :id :audit-sub-1 :domain :int :position 1
                    :witness (term `(- ,k ,c)) :certified-p nil :unique-p t)))
      (register-metric-decoder solver :tag-bits 0)
      (let* ((dec (first (metric-decoders :int)))
             (*closure-evaluation* t))
        (check (= 5 (metric-delta dec 10 5 :int (make-ledger))))
        (let ((count-after-first (hash-table-count *closures*)))
          (loop for p from 100 below 120
                for target = (- p (mod p 7))
                do (check (= (mod p 7) (metric-delta dec p target :int (make-ledger)))))
          (check (= count-after-first (hash-table-count *closures*))))))
    (let* ((seq (sequence-type :int))
           (inputs (list (cons 0 seq)))
           (xs (var 0 seq))
           (k-seq (var 0 seq))
           (c-seq (var 1 seq))
           (empty-seq (lit seq nil)))
      (define-function :audit-prepend (list (cons 0 seq) (cons 1 :int)) seq
        (app (op :cons :int) (var 1 :int) xs))
      (let ((prep-solver (register-knowledge-solver
                          (op :audit-prepend) :id :audit-prepend-1 :domain :int :position 1
                          :witness (term `(if (= ,c-seq ,empty-seq) 0 (at ,c-seq 0)))
                          :guard (term `(if (= ,c-seq ,empty-seq) ,(lit :bool nil) ,(lit :bool t)))
                          :unique-p nil)))
        (register-metric-decoder prep-solver :tag-bits 1)
        (let* ((frame (simple-frame seq inputs
                                    '((((10 20 30)) (7 10 20 30))
                                      (((40 50 60)) (9 40 50 60)))))
               (language (make-language :int inputs :operators (list (op :audit-prepend)) :literals '(0 1 7)))
               (model (condense-heuristic frame language :work-limit 40000)))
          (check (equal xs (heuristic-program model)))
          (check (= 2 (length (heuristic-residual model))))
          (check (every (lambda (pair) (not (eq :metric-decoder (and (consp (cdr pair)) (first (cdr pair))))))
                        (heuristic-residual model)))
          (check (= 2 (length (heuristic-packets model))))
          (check (every (lambda (pair)
                          (and (consp (cdr pair)) (eq :metric-decoder (second pair))))
                        (heuristic-packets model)))
          (let* ((l-cached (make-ledger))
                 (l-uncached (make-ledger))
                 (p-cached (metric-residual-decompositions
                            frame xs (heuristic-residual model) language 120 nil l-cached nil
                            :packets (heuristic-packets model)))
                 (p-uncached (metric-residual-decompositions
                              frame xs (heuristic-residual model) language 120 nil l-uncached nil)))
            (check (= 1 (length p-cached)))
            (check (= 1 (length p-uncached)))
            (check (zerop (ledger-total l-cached)))
            (check (plusp (ledger-total l-uncached)))))))))

(deftest audit-symbolic-unwinding-keeps-unsimplified-fallback
  ;; When simplify-symbolic-expr rewrites a solvable 1-occurrence form into a 2-occurrence form,
  ;; solve-equality-symbolically falls back to the unsimplified form; when simplification folds
  ;; 2 occurrences into 1, it uses the simplified form.
  (with-clean-kernel-state
    (let* ((field (gf 5))
           (k (var 0 field)) (c (var 1 field))
           (y (var 0 field)) (a (var 1 field)) (b (var 2 field)))
      (dolist (pos '(0 1))
        (register-knowledge-solver (op :+ field) :domain field :position pos
                                  :witness (term `(- ,c ,k) field) :certified-p t :unique-p t)
        (register-knowledge-solver (op :* field) :domain field :position pos
                                  :witness (term `(/ ,c ,k) field)
                                  :guard (term `(if (= ,k ,(lit field 0)) ,(lit :bool nil) ,(lit :bool t)))
                                  :certified-p t :unique-p t))
      ;; Law 1 (1 occ -> 2 occs, smaller code): y * (a+a+a+a + 1) = y + y * (4 * a)
      (let* ((lhs1 (term `(* ,y (+ (+ ,a (+ ,a (+ ,a ,a))) ,(lit field 1))) field))
             (rhs1 (term `(+ ,y (* ,y (* ,(lit field 4) ,a))) field))
             (law1 (resume-law-validation
                    (start-law-validation (make-law field (list (cons 0 field) (cons 1 field)) lhs1 rhs1))
                    100000)))
        (register-knowledge-law law1)
        ;; Law 2 (2 occs -> 1 occ, smaller code): (y * a) + (y * b) = y * (a + b)
        (let* ((lhs2 (term `(+ (* ,y ,a) (* ,y ,b)) field))
               (rhs2 (term `(* ,y (+ ,a ,b)) field))
               (law2 (resume-law-validation
                      (start-law-validation
                       (make-law field (list (cons 0 field) (cons 1 field) (cons 2 field)) lhs2 rhs2))
                      100000)))
          (register-knowledge-law law2)
          ;; Case A: simplify rewrites lhs1 -> rhs1 (2 occurrences of y); fallback unwinds lhs1 cleanly!
          (let ((simp1 (simplify-symbolic-expr lhs1 :library *knowledge-library*)))
            (check (= 2 (count 0 (let ((vars nil))
                                    (map-ast (lambda (n m) (declare (ignore n))
                                               (when (eq :var (ast-meta-kind m))
                                                 (push (ast-meta-id m) vars))
                                               nil)
                                             simp1)
                                    vars))))
            (multiple-value-bind (sol guards certified-p)
                (solve-equality-symbolically lhs1 (lit field 3) 0 :library *knowledge-library*)
              (check sol)
              (check certified-p)
              (check (= 1 (length guards)))
              (let ((scope (list (cons 0 field) (cons 1 field))))
                (dolist (a-val '(0 2 3 4))
                  (let ((y-val (result sol scope (list 0 a-val))))
                    (check (= 3 (mod (* y-val (+ (* 4 a-val) 1)) 5))))))))
          ;; Case B: simplify rewrites lhs2 (2 occurrences of y) -> rhs2 (1 occurrence), which unwinds!
          (multiple-value-bind (sol2 guards2 certified2)
              (solve-equality-symbolically lhs2 (lit field 3) 0 :library *knowledge-library*)
            (check sol2)
            (check certified2)
            (check (= 1 (length guards2)))
            (let ((scope (list (cons 0 field) (cons 1 field) (cons 2 field))))
              (check (= 4 (result sol2 scope '(0 1 1))))
              (check (= 3 (mod (+ (* 4 1) (* 4 1)) 5))))))))))

(deftest audit-candidate-library-definitions-retypes-sequence-state
  ;; State-returning combinators (like foldr) retain the full (:seq ...) target type when
  ;; instantiated for sequence-typed frames, rather than stripping :seq off target.
  (with-clean-kernel-state
    (let* ((seq (sequence-type :int))
           (step-type (code-type '((0 . :int) (1 . :int)) :int))
           (xs (var 0 seq))
           (acc (var 1 :int))
           (step (var 2 step-type))
           (lang (make-language :int (list (cons 0 seq)) :constants (list (lit seq nil))))
           (frame (simple-frame seq (list (cons 0 seq)) '(((() ) ()) (((1 2)) (2 1)))))
           (seq-state-code (code-type (list (cons 0 :int) (cons 1 seq)) seq)))
      (define-function :audit-fold (list (cons 0 seq) (cons 1 :int) (cons 2 step-type)) :int
        (lambda (self)
          (app (op :if :int) (app (op := seq) xs (lit seq nil)) acc
               (app (op :code-eval step-type) step
                    (app (op :at seq) xs (lit :int 0))
                    (app self (app (op :tail :int) xs) acc step)))))
      (let* ((defs (candidate-library-definitions lang :frame frame))
             (inst (find seq defs :key #'function-definition-return-type :test #'equal)))
        (check inst)
        (check (find seq (function-definition-inputs inst) :key #'cdr :test #'equal))
        (check (find seq-state-code (function-definition-inputs inst) :key #'cdr :test #'equal))
        (let* ((props (library-decompositions frame lang))
               (fold-prop (find (function-definition-name inst) props
                                :key (lambda (p) (operator-name (first (decomposition-decoder p)))))))
          (check fold-prop)
          (check (equal seq-state-code (decomposition-child-type fold-prop))))))))
