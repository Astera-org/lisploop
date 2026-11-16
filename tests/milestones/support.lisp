(in-package #:lisploop)

;;; Shared fixtures and helpers for `tests/milestones/*.lisp` (external consumers of `milestones/`).

(defun verify-corpus-abstraction-replay (abstraction expected-trees expected-inputs &optional ledger)
  "Bit-encode, decode, and execute `(subexpression-abstraction-model abstraction)` in the VM,
and verify that `decode-tree-corpus` reconstructs EXPECTED-TREES in exact occurrence order."
  (let* ((model (subexpression-abstraction-model abstraction))
         (decoded-model (decode-model (encode-model model nil)))
         (run (evaluate decoded-model nil nil :ledger ledger :budget 10000000)))
    (check (eq :value (evaluation-status run)))
    (multiple-value-bind (reconstructed-trees schema)
        (decode-tree-corpus (evaluation-value run))
      (check (equal expected-inputs schema))
      (check (equal expected-trees reconstructed-trees))
      (evaluation-work run))))

(defun guard-search-bound (domain inputs)
  "Description-length bound sufficient for a conditional `(if (= x c) nil t)` guard over DOMAIN."
  (let ((sample (app (op :if :bool)
                     (app (op := domain) (var (caar inputs) domain) (lit domain 0))
                     (lit :bool nil)
                     (lit :bool t))))
    (description-size sample inputs)))

(defun discover-guarded-field-laws (p)
  "Joint discovery: enumerate expressions on the FULL field, then synthesize
one exact Boolean membership program per distinct proper agreement support."
  (let* ((domain (gf p)) (inputs (list (cons 0 domain)))
         (frame (make-frame (make-schema :inputs inputs :target domain)
                            (loop for x below p collect
                              (make-row :key x :known (list x)
                                        :requirement (lit :bool t)))))
         (language (make-language domain inputs :operators (mapcar (lambda (name) (op name domain)) '(:- :/ :*))))
         (observations (start-observation-search (make-observation-scope frame language) :retain-outcomes t))
         (bound (+ (header-size inputs domain) 6 (* 2 (body-size (lit domain 0) inputs))))
         (proposal-work (make-ledger))
         (guard-language (make-language domain inputs :operators (list (op := domain) (op :if :bool))))
         (g-bound (guard-search-bound domain inputs))
         (searches nil) (validations nil))
    (check (eq :bounded-exhaustion (message-claim (resume-observation-search observations bound 2000000))))
    (let ((problems (propose-guard-problems observations proposal-work)))
      (dolist (problem problems)
        (let ((search (start-guard-search problem guard-language)))
          (check (eq :bounded-exhaustion (message-claim (resume-search search g-bound 2000000))))
          (push search searches)
          (dolist (law (propose-guarded-laws problem search proposal-work))
            (let ((validation (resume-law-validation (start-law-validation law) 2000000)))
              (check (eq :validated (law-validation-status validation)))
              (push validation validations)))))
      (values (nreverse validations) observations problems (nreverse searches) proposal-work))))

(defun algebra-job-work (job)
  (etypecase job
    (search-job (ledger-total (search-job-ledger job)))
    (propagation-search (ledger-total (propagation-search-ledger job)))
    (observation-job (ledger-total (observation-job-ledger job)))
    (law-validation (ledger-total (law-validation-ledger job)))))

(defun arithmetic-parent-fixture (relation position values ledger)
  "A separate batch hides h(b)=b+1 behind the supplied arithmetic decoder."
  (let* ((domain (arithmetic-relation-domain relation)) (operator (arithmetic-relation-operator relation))
         (hidden (app (op :+ domain) (var 1 domain) (lit domain 1)))
         (oracle (arithmetic-application operator position (var 0 domain) hidden))
         (job (observe-arithmetic-values domain operator values 100000000 oracle))
         (records (arithmetic-forward-records job ledger))
         (parent (orient-observations (list domain domain domain) records '(0 1) '(2) :ledger ledger)))
    (values parent (arithmetic-application operator position (var 0 domain) (var 9 domain))
            (list (cons 3 (var 1 domain))) job)))

(defun replay-arithmetic-parent (model frame ledger)
  (let* ((schema (frame-schema frame))
         (inputs (schema-inputs schema))
         (target-type (schema-target schema)))
    (dolist (row (frame-rows frame))
      (let ((run (run-algebra-program model inputs (row-known row) ledger :parent-replay)))
        (check (eq :value (evaluation-status run)))
        (let ((ok (check-requirement (row-requirement row) (evaluation-value run)
                                     :ledger ledger :type target-type)))
          (check (and (eq (evaluation-status ok) :value) (evaluation-value ok))))))))

(defun algebra-search-results (job)
  (etypecase job (search-job (search-job-results job)) (propagation-search (propagation-search-results job))))

(defun algebra-search-best (job)
  (etypecase job (search-job (search-job-best job)) (propagation-search (propagation-search-best job))))

(defun algebra-first-work (job)
  (etypecase job
    (search-job (when (search-job-results job) (reduce #'min (search-job-results job) :key #'candidate-discovery-work)))
    (propagation-search (propagation-search-first-work job))))

(defun compare-arithmetic-propagation (discovery values &key library)
  (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation))
         (acquisition (make-ledger)) (original-work (make-ledger)) (propagation-work (make-ledger)))
    (multiple-value-bind (parent decoder bindings observations)
        (arithmetic-parent-fixture relation (solve-discovery-position discovery) values acquisition)
      (let* ((original (pullback-frame parent decoder 9 domain bindings original-work))
             (propagation (propagate-requirements (pullback-frame parent decoder 9 domain bindings propagation-work)
                                                  (or library (discovery-propagator-library discovery propagation-work))
                                                  propagation-work))
             (inputs (schema-inputs (frame-schema original)))
             (language (make-language domain inputs :operators (list (op :+ domain) (op :* domain))
                                       :literals (if (eq domain :int) '(-1 0 1) :all)))
             (plain (start-search original language))
             (propagated (if (propagation-fallback propagation) (start-propagation-search propagation language)
                             (start-search (propagation-frame propagation) language)))
             (bound (+ (header-size inputs domain) 16)))
        (check (eq :bounded-exhaustion (message-claim (resume-search plain bound 10000000))))
        (check (eq :bounded-exhaustion (message-claim
                  (etypecase propagated
                    (search-job (resume-search propagated bound 10000000))
                    (propagation-search (resume-propagation-search propagated bound 10000000))))))
        (check (search-job-best plain))
        (check (same-set-p (search-job-results plain) (algebra-search-results propagated)
                           :key #'candidate-expression))
        (let* ((composition (make-ledger))
               (model (compose-model decoder 9 (candidate-expression (algebra-search-best propagated)) bindings composition)))
          (replay-arithmetic-parent (decode-model (encode-model model (schema-inputs (frame-schema parent)))) parent composition)
          (values propagation plain propagated original-work propagation-work
                  (+ (ledger-total acquisition) (algebra-job-work observations)) composition))))))

(defun integer-solver-held-out (discovery)
  "Fresh forward observations and query checks; no universal integer certificate."
  (let* ((relation (solve-discovery-relation discovery)) (operator (arithmetic-relation-operator relation))
         (n (ash 1 64)) (values (list (- n) -17 -1 0 1 17 n))
         (ledger (make-ledger)) (observations (observe-arithmetic-values :int operator values 100000000))
         (record (first (observation-job-records observations)))
         (support (mapcar (lambda (outcome) (eq :value (observation-outcome-status outcome))) (observed-expression-outcomes record)))
         (definedness (search-membership-frame (support-frame (observation-job-scope observations) support ledger) :int
                                               :work-limit 100000000 :expressions (list (arithmetic-relation-guard relation))))
         (fresh (copy-arithmetic-relation relation))
         (position (solve-discovery-position discovery)))
    (setf (arithmetic-relation-records fresh) (arithmetic-forward-records observations ledger))
    (let* ((queries (orient-arithmetic-requirements fresh position values ledger))
           (samples (remove-duplicates (mapcar #'row-known (frame-rows queries)) :test #'equal))
           (unique-samples
             (append (loop for row in (frame-rows (solve-discovery-frame discovery)) append
                       (loop for z from -4 to 4 collect (append (row-known row) (list z))))
                     (loop for record in (arithmetic-relation-records fresh)
                           collect (list (nth (1+ (- 1 position)) record) (fourth record) (nth (1+ position) record))))))
      (validate-arithmetic-solver discovery :samples samples :uniqueness-samples unique-samples)
      (check (eq :conjecture (law-validation-status (solve-discovery-validation discovery))))
      (check (not (certified-solve-discovery-p discovery)))
      (+ (ledger-total ledger) (algebra-job-work observations) (algebra-job-work definedness)))))

(defun addition-oracle-control (discovery)
  "An explicitly supplied control, called only AFTER unseeded bootstrap discovery."
  (let* ((domain (arithmetic-relation-domain (solve-discovery-relation discovery)))
         (inputs (arithmetic-inputs domain))
         (oracle (app (op :+ domain) (var 1 domain)
                      (app (op :* domain) (lit domain (if (eq domain :int) -1 (1- (second domain)))) (var 0 domain))))
         (job (start-search (solve-discovery-frame discovery) (make-language domain inputs :operators nil :literals nil)
                            :expressions (list oracle))))
    (check (eq :replay-complete (message-claim (resume-search job (description-size oracle inputs) 100000000))))
    (check (search-job-best job))
    job))

(defun integer-propagation-cost-control (discoveries)
  "Supplied expensive context a*a; hidden child b*b+1. Same candidate grammar,
bound and rows on both paths; all inverse and verification work is charged."
  (let* ((inputs (arithmetic-inputs :int)) (a (var 0 :int)) (b (var 1 :int))
         (known (app (op :* :int) a a)) (decoder (app (op :+ :int) known (var 9 :int)))
         (hidden (app (op :+ :int) (app (op :* :int) b b) (lit :int 1)))
         (oracle (instantiate decoder (list (cons 9 hidden)) :var))
         (acquisition (make-ledger)) (plain-work (make-ledger)) (guided-work (make-ledger))
         (probe (make-frame (make-schema :inputs inputs :target :int)
                            (loop for b from -3 to 3 for key from 0 collect
                              (make-row :key key :known (list (+ (ash 1 128) key) b)
                                        :requirement (lit :bool t)))))
         (observations (start-observation-search
                        (make-observation-scope probe (make-language :int inputs :operators nil :literals nil))
                        :expressions (list oracle) :retain-outcomes t)))
    (finish-observations observations (description-size oracle inputs) 10000000)
    (let* ((parent (orient-observations '(:int :int :int) (arithmetic-forward-records observations acquisition) '(0 1) '(2)
                                         :ledger acquisition))
           (bindings (list (cons 3 b))) (original (pullback-frame parent decoder 9 :int bindings plain-work))
           (library (prepare-propagator-library discoveries guided-work))
           (propagation (propagate-requirements (pullback-frame parent decoder 9 :int bindings guided-work)
                                                library guided-work))
           (child-inputs (schema-inputs (frame-schema original)))
           (language (make-language :int child-inputs :operators (list (op :+ :int) (op :* :int)) :literals '(-1 0 1)))
           (bound (+ (header-size child-inputs :int) 22))
           (plain (start-search original language)) (guided (start-propagation-search propagation language)))
      (check (= 7 (propagation-suggested propagation)))
      (check (eq :bounded-exhaustion (message-claim (resume-search plain bound 100000000))))
      (check (eq :candidate (message-claim (resume-propagation-search guided bound 100000000 :stop-on-first t))))
      (let* ((replay (make-ledger)) (model (compose-model decoder 9 (candidate-expression (propagation-search-best guided)) bindings replay)))
        (replay-arithmetic-parent (decode-model (encode-model model inputs)) parent replay)
        (check (eq :bounded-exhaustion (message-claim (resume-propagation-search guided bound 100000000))))
        (check (same-set-p (search-job-results plain) (propagation-search-results guided)
                           :key #'candidate-expression))
        (values plain guided plain-work guided-work
                (+ (ledger-total acquisition) (algebra-job-work observations)) replay)))))

(defvar *arithmetic-controls* (make-hash-table :test #'equal))

(defun arithmetic-controls (domain)
  (or (gethash domain *arithmetic-controls*)
      (setf (gethash domain *arithmetic-controls*)
            (loop with values = (if (eq domain :int) '(-4 -3 -2 -1 0 1 2 3 4)
                                    (loop for i below (second domain) collect i))
                  for name in '(:+ :- :* :/)
                  for relation = (observe-arithmetic-relation domain name values) append
                    (loop for position below 2
                          for discovery = (discover-arithmetic-solver relation position values :literals (if (eq domain :int) '(-1 0 1) :all))
                          do (if (eq domain :int) (integer-solver-held-out discovery) (validate-arithmetic-solver discovery))
                          collect discovery)))))

(defun arithmetic-control (domain name position)
  (find-if (lambda (d) (and (eq name (operator-name (arithmetic-relation-operator (solve-discovery-relation d))))
                            (= position (solve-discovery-position d))))
           (arithmetic-controls domain)))
