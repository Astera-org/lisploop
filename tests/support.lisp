(in-package #:lisploop)

;;; 1. Test Harness & Core Assertions

(defvar *tests* nil)
(defvar *checks* 0)

(defmacro check (form)
  `(progn (incf *checks*) (unless ,form (error "Check failed: ~S" ',form))))

(defmacro raises (form)
  `(check (handler-case (progn ,form nil) (error () t))))

(defmacro deftest (name &body body)
  `(progn (defun ,name () ,@body) (push ',name *tests*)))

(defun result (expression &optional inputs values)
  (let ((state (evaluate expression inputs values)))
    (check (eq (evaluation-status state) :value))
    (evaluation-value state)))

(defun accepts (requirement value)
  (let ((state (check-requirement requirement value)))
    (check (eq (evaluation-status state) :value))
    (evaluation-value state)))

(defun simple-frame (type inputs examples &key lookup-p)
  (make-frame (make-schema :inputs inputs :target type :lookup-p lookup-p)
              (loop for (known target) in examples for key from 0 collect
                (make-row :key key :known known :requirement (set-requirement type (list target))))))

(defun probe-frame (type inputs known-values)
  (make-frame (make-schema :inputs inputs :target type)
              (loop for known in known-values for key from 0 collect
                (make-row :key key :known (copy-tree known)
                          :requirement (lit :bool t)))))

(defun check-codec-roundtrip (expression inputs)
  (let ((bits (encode-model expression inputs)))
    (check (= (length bits) (description-size expression inputs)))
    (multiple-value-bind (decoded schema) (decode-model bits)
      (check (equal expression decoded)) (check (equal inputs schema)))
    (raises (decode-model (subseq bits 0 (1- (length bits)))))
    (raises (decode-model (concatenate 'bit-vector bits #*0)))))

(defun replay-model (expression frame &optional ledger)
  "Decode a fresh model, pass declared values only, and separately check each output."
  (multiple-value-bind (model inputs)
      (decode-model (encode-model expression (schema-inputs (frame-schema frame))))
    (check (equal inputs (schema-inputs (frame-schema frame))))
    (let ((target-type (schema-target (frame-schema frame))))
      (loop for row in (frame-rows frame) sum
        (let ((run (evaluate model inputs (row-known row) :ledger ledger)))
          (check (eq (evaluation-status run) :value))
          (let ((ok (check-requirement (row-requirement row) (evaluation-value run)
                                       :ledger ledger :type target-type)))
            (check (and (eq (evaluation-status ok) :value) (evaluation-value ok))))
          (evaluation-work run))))))

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

;;; 2. Shared Reference Enumerators & Evaluators

(defun reference-node-trees (leaves operators applications)
  "Enumerate by application count, independently of the size-indexed search."
  (if (zerop applications) leaves
      (loop for left-count below applications append
        (loop for left in (reference-node-trees leaves operators left-count) append
          (loop for right in (reference-node-trees leaves operators (- applications 1 left-count)) append
            (loop for operator in operators collect (app operator left right)))))))

(defun reference-one-application (domain inputs operators bound)
  "Independent exhaustive reference: this bound permits leaves and ONE binary app."
  (let* ((leaves (append (mapcar (lambda (spec) (var (car spec) (cdr spec))) inputs)
                          (loop for i below (second domain) collect (lit domain i))))
         (candidates (copy-list leaves)))
    (dolist (operator operators)
      (dolist (left leaves)
        (dolist (right leaves) (push (app operator left right) candidates))))
    (check (< bound (+ (header-size inputs domain)
                       (* 3 (reduce #'min leaves :key (lambda (e) (body-size e inputs)))) 10)))
    (remove-if (lambda (expression) (> (description-size expression inputs) bound)) candidates)))

(defun reference-value (expression inputs prime)
  (case (ast-kind expression)
    (:lit (ast-value expression))
    (:var (cdr (assoc (ast-id expression) inputs)))
    (:app
     (let ((a (reference-value (first (rest expression)) inputs prime))
           (b (reference-value (second (rest expression)) inputs prime)))
       (ecase (operator-name (first expression))
         (:+ (mod (+ a b) prime)) (:* (mod (* a b) prime)))))))

(defun integer-reference-value (expression inputs)
  "Independent arithmetic oracle for the tiny integer grammar; no simulator calls."
  (ecase (ast-kind expression)
    (:lit (ast-value expression))
    (:var (cdr (assoc (ast-id expression) inputs)))
    (:app
     (let ((values (mapcar (lambda (e) (integer-reference-value e inputs)) (rest expression))))
       (ecase (operator-name (first expression))
         (:+ (+ (first values) (second values)))
         (:* (* (first values) (second values))))))))

;;; 3. Shared Observation & Lifting Fixtures

(defun gf5-fixture (&optional ledger)
  "The oracle generates observations only; neither its syntax nor sketch enters search."
  (let* ((field (gf 5))
         (inputs (list (cons 0 field) (cons 1 field)))
         (oracle (app (op :+ field) (var 0 field)
                      (app (op :* field) (lit field 2) (var 1 field))))
         (records
           (loop for a below 5 append
             (loop for b below 5 for key from (* a 5) collect
               (let ((run (evaluate oracle inputs (list a b) :ledger ledger)))
                 (check (eq (evaluation-status run) :value))
                 (list key a b (evaluation-value run)))))))
    (values (orient-observations (list field field field) records '(0 1) '(2)
                                  :lookup-p t :ledger ledger)
            oracle records)))

(defun additive-transition-fixture (domain starts steps shift-b key-prefix ledger)
  "Record forward transitions T(a,b)=(a+1,b+SHIFT-B). Return the frame and start keys.
The transition is supplied fixture machinery; no invariant sketch enters search."
  (check (and (integerp steps) (plusp steps)))
  (let* ((field domain) (state-type (tuple-type field field))
         (inputs (list (cons 0 field) (cons 1 field)))
         (transition (app (op :tuple state-type)
                          (app (op :+ field) (var 0 field) (lit field 1))
                          (app (op :+ field) (var 1 field) (lit field shift-b))))
         (rows nil) (anchors nil))
    (loop for start in starts for orbit from 0 do
      (let ((state start))
        (dotimes (step steps)
          (let* ((key (list key-prefix orbit step))
                 (run (evaluate transition inputs state :ledger ledger)))
            (check (eq (evaluation-status run) :value))
            (when (zerop step) (push (list key :before) anchors))
            (push (make-row :key key :known state
                            :requirement (set-requirement state-type (list (evaluation-value run)))) rows)
            (setf state (evaluation-value run))))))
    (values (make-frame (make-schema :inputs inputs :target state-type) (nreverse rows))
            (nreverse anchors))))

(defun gf5-transition-fixture (&key (starts '((0 0) (0 1))) (steps 5)
                                  (shift-b 4) (key-prefix :training) ledger)
  (additive-transition-fixture (gf 5) starts steps shift-b key-prefix ledger))

(defun integer-transition-fixture (&key (starts '((-3 1) (0 0) (2 3))) (steps 3)
                                       (shift-b -1) (key-prefix :integer-training) ledger)
  (additive-transition-fixture :int starts steps shift-b key-prefix ledger))

(defun integer-held-out-starts ()
  "Exact cancellation, adjacent large integers, and positive/negative large outputs."
  (let ((n (ash 1 256)))
    (list (list n (- n)) (list (1+ n) (- n))
          (list (- n) n) (list (- (1+ n)) n)
          (list n n) (list (- n) (- n)))))

(defun gf7-iota-conversion (t-expr &key (steps 7) ledger)
  "Declared, metered conversion \\iota(t) from :int index T-EXPR into GF(7)."
  (check (and (integerp steps) (plusp steps)))
  (let* ((field (gf 7))
         (key-type (tuple-type :int))
         (entry-type (tuple-type key-type field))
         (entries (loop for step below steps
                        collect (list (list step) (mod step 7))))
         (expr (app (op :lookup entry-type)
                    (app (op :tuple key-type) t-expr)
                    (lit (sequence-type entry-type) entries))))
    (charge ledger :construction (syntax-work expr))
    expr))

(defun gf7-lifting-fixture (&key (offsets '(1 3)) (steps 7) (repetitions 1) schedule ledger)
  "Generate indexed GF(7) sequences y_{j,t} = a_j + \\iota(t) with explicit occurrence
coordinate r (:int) and index t (:int). Returns:
  (values frame decoder r-to-j-map row-labels records)"
  (check (and (integerp steps) (plusp steps)))
  (check (and (integerp repetitions) (plusp repetitions)))
  (let* ((field (gf 7))
         (seq-tags (or schedule
                       (loop repeat repetitions
                             append (loop for idx below (length offsets) collect idx))))
         (iota-t (gf7-iota-conversion (var 1 :int) :steps steps :ledger ledger))
         (decoder (app (op :+ field) iota-t (var 9 field)))
         (oracle-inputs (list (cons 0 field) (cons 1 :int)))
         (oracle (app (op :+ field) (var 0 field)
                      (gf7-iota-conversion (var 1 :int) :steps steps :ledger ledger)))
         (records nil)
         (row-labels nil))
    (charge ledger :construction (syntax-work decoder))
    (loop for tag in seq-tags
          for r from 0
          for offset = (nth tag offsets)
          do (dotimes (step steps)
               (let* ((key (list :seq r step))
                      (run (evaluate oracle oracle-inputs (list offset step) :ledger ledger)))
                 (check (eq :value (evaluation-status run)))
                 (push tag row-labels)
                 (push (list key r step (evaluation-value run)) records))))
    (setf records (nreverse records)
          row-labels (nreverse row-labels))
    (let* ((frame (orient-observations (list :int :int field) records '(0 1) '(2)
                                       :lookup-p t :ledger ledger))
           (label-frame (context-label-frame frame row-labels
                                             :bindings (list (cons 0 (var 0 :int)))
                                             :label-type field
                                             :ledger ledger))
           (r-to-j (lookup-model label-frame ledger)))
      (values frame decoder r-to-j row-labels records))))

(defun integer-lifting-fixture (&key (offsets '(1 3)) (steps 7) (repetitions 1) schedule ledger)
  "Generate indexed integer sequences y_{j,t} = a_j + t with explicit occurrence
coordinate r (:int) and index t (:int). Returns:
  (values frame decoder r-to-j-map row-labels records)"
  (check (and (integerp steps) (plusp steps)))
  (check (and (integerp repetitions) (plusp repetitions)))
  (let* ((domain :int)
         (seq-tags (or schedule
                       (loop repeat repetitions
                             append (loop for idx below (length offsets) collect idx))))
         (decoder (app (op :+ domain) (var 1 domain) (var 9 domain)))
         (oracle-inputs (list (cons 0 domain) (cons 1 domain)))
         (oracle (app (op :+ domain) (var 0 domain) (var 1 domain)))
         (records nil)
         (row-labels nil))
    (charge ledger :construction (syntax-work decoder))
    (loop for tag in seq-tags
          for r from 0
          for offset = (nth tag offsets)
          do (dotimes (step steps)
               (let* ((key (list :seq r step))
                      (run (evaluate oracle oracle-inputs (list offset step) :ledger ledger)))
                 (check (eq :value (evaluation-status run)))
                 (push tag row-labels)
                 (push (list key r step (evaluation-value run)) records))))
    (setf records (nreverse records)
          row-labels (nreverse row-labels))
    (let* ((frame (orient-observations (list domain domain domain) records '(0 1) '(2)
                                       :lookup-p t :ledger ledger))
           (label-frame (context-label-frame frame row-labels
                                             :bindings (list (cons 0 (var 0 domain)))
                                             :label-type domain
                                             :ledger ledger))
           (r-to-j (lookup-model label-frame ledger)))
      (values frame decoder r-to-j row-labels records))))

;;; 4. Shared Law, Guard, and Algebra Helpers

(defun checked-law (law)
  (let ((validation (resume-law-validation (start-law-validation law) 1000000)))
    (check (eq :validated (law-validation-status validation)))
    validation))

(defun normalize-for-test (expression inputs validations domain)
  (let ((state (start-rewriting expression inputs (prepare-rewrite-library validations domain))))
    (advance-rewriting state 10000000)
    (check (eq :complete (rewriting-status state)))
    (rewriting-value state)))

(defun validation-for-equation (validations left right)
  (or (find-if (lambda (state)
                 (let ((sides (rest (law-equation (law-validation-law state)))))
                   (or (equal sides (list left right)) (equal sides (list right left))))) validations)
      (error "Required identity was not discovered")))

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
         (searches nil) (validations nil))
    (check (eq :bounded-exhaustion (message-claim (resume-observation-search observations bound 2000000))))
    (let ((problems (propose-guard-problems observations proposal-work)))
      (dolist (problem problems)
        (let ((search (start-guard-search problem guard-language)))
          (check (eq :bounded-exhaustion (message-claim (resume-search search 54 2000000))))
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
          (check (and (eq :value (evaluation-status ok)) (evaluation-value ok))))))))

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
                                                  (or library discovery) propagation-work))
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
        (check (null (set-exclusive-or (search-job-results plain) (algebra-search-results propagated)
                                       :key #'candidate-expression :test #'equal)))
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
        (check (null (set-exclusive-or (search-job-results plain) (propagation-search-results guided)
                                       :key #'candidate-expression :test #'equal)))
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
                            (= position (solve-discovery-position d)))) (arithmetic-controls domain)))
