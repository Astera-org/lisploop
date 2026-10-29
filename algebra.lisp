(in-package #:lisploop)

;;; Adapters around ordinary observation, Boolean synthesis, law validation and
;;; pullback jobs. Candidate programs are enumerated ONLY by the core grammar.
(defstruct arithmetic-relation domain operator observations records guard guard-search ledger exhaustive-p)
(defstruct solve-discovery relation position frame observations recovery proposals search
  witness guard guard-searches ledger validation uniqueness)

(defun arithmetic-inputs (domain &optional (count 2))
  (loop for id below count collect (cons id domain)))

(defun arithmetic-application (operator position known unknown)
  (assert (member position '(0 1)))
  (if (zerop position) (app operator unknown known) (app operator known unknown)))

(defun literal-conditional (condition yes no)
  "Only fold literal Boolean conditions; no algebraic identity is supplied."
  (if (eq :lit (first condition)) (if (third condition) yes no)
      (app (op :if :bool) condition yes no)))

(defun finish-observations (job bound work-limit)
  (let ((message (resume-observation-search job bound work-limit)))
    (assert (member (message-claim message) '(:bounded-exhaustion :replay-complete)) ()
            "Observation cutoff; resume the ordinary observation job before using its outcomes")
    job))

(defun search-membership-frame (frame domain &key (body-bound 35) (work-limit 10000000) expressions)
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (language (make-language domain inputs :operators (list (op := domain) (op :if :bool)) :literals '(0)))
         (job (if expressions (start-search frame language :expressions expressions) (start-search frame language)))
         (bound (if expressions (reduce #'max expressions :key (lambda (e) (description-size e inputs)))
                    (+ (header-size inputs :bool) body-bound))))
    (resume-search job bound work-limit)
    (assert (search-job-best job) () "Membership search unresolved at the supplied bounds")
    job))

(defun observe-arithmetic-values (domain operator values work-limit &optional expression)
  (let* ((inputs (arithmetic-inputs domain))
         (forward (or expression (app operator (var 0 domain) (var 1 domain))))
         (frame (make-frame (make-schema :inputs inputs :target domain)
                            (loop for a in values for block from 0 append
                              (loop for b in values for key from (* block (length values)) collect
                                (make-row :key key :known (list a b) :allowed (predicate-allowed domain (lit :bool t)))))))
         (job (start-observation-search (make-observation-scope frame (make-language domain inputs :operators nil :literals nil))
                                        :expressions (list forward) :retain-outcomes t)))
    (finish-observations job (description-size forward inputs) work-limit)
    job))

(defun arithmetic-forward-records (observations ledger)
  (loop for row in (frame-rows (observation-scope-frame (observation-job-scope observations)))
        for outcome in (observed-expression-outcomes (first (observation-job-records observations)))
        do (charge ledger :forward-records)
        when (eq :value (observation-outcome-status outcome)) collect
          (cons (row-key row) (append (row-known row) (list (observation-outcome-value outcome))))))

(defun observe-arithmetic-relation (domain name values &key (work-limit 10000000))
  "Acquire forward executions, including errors, and learn their definedness guard.
No inverse values or solve programs are supplied. Exhaustiveness is finite only."
  (let* ((operator (op name domain)) (ledger (make-ledger))
         (job (observe-arithmetic-values domain operator values work-limit))
         (forward (app operator (var 0 domain) (var 1 domain))))
    (let* ((record (find-observation job forward))
           (support (mapcar (lambda (outcome) (eq :value (observation-outcome-status outcome)))
                            (observed-expression-outcomes record)))
           (guard-job (search-membership-frame (support-frame (observation-job-scope job) support ledger) domain :work-limit work-limit))
           (records (arithmetic-forward-records job ledger)))
      (make-arithmetic-relation
       :domain domain :operator operator :observations job :records records :ledger ledger
       :guard (copy-tree (candidate-expression (search-job-best guard-job))) :guard-search guard-job
       :exhaustive-p (and (consp domain) (eq :gf (first domain))
                          (= (second domain) (length (remove-duplicates values)))
                          (every (lambda (value) (value-p value domain)) values))))))

(defun arithmetic-definedness (relation position known unknown)
  (let ((args (if (zerop position) (list unknown known) (list known unknown))))
    (instantiate (arithmetic-relation-guard relation) (list (cons 0 (first args)) (cons 1 (second args))) :var)))

(defun arithmetic-requirement (relation position)
  "R(k,c,z): a Boolean predicate describing the complete defined forward fiber."
  (let* ((domain (arithmetic-relation-domain relation))
         (k (var 0 domain)) (c (var 1 domain)) (z (var 2 domain)))
    (literal-conditional
     (arithmetic-definedness relation position k z)
     (app (op := domain) (arithmetic-application (arithmetic-relation-operator relation) position k z) c)
     (lit :bool nil))))

(defun orient-arithmetic-requirements (relation position query-values ledger)
  "Retain witnessed occurrences and add declared queries, without solving fibers.
The recorded unknown operand is never installed as a singleton requirement."
  (let* ((domain (arithmetic-relation-domain relation)) (inputs (arithmetic-inputs domain))
         (oriented (orient-observations (list domain domain domain) (arithmetic-relation-records relation)
                                       (list (- 1 position) 2) (list position) :ledger ledger))
         (predicate (arithmetic-requirement relation position))
         (queries (append (loop for row in (frame-rows oriented) collect
                            (cons (list :forward (row-key row)) (row-known row)))
                          (loop for k in query-values for block from 0 append
                            (loop for c in query-values for i from (* block (length query-values))
                                  collect (list (list :query i) k c))))))
    (make-frame (make-schema :inputs inputs :target domain)
                (loop for (key k c) in queries collect
                  (let ((requirement (instantiate predicate (list (cons 0 (lit domain k)) (cons 1 (lit domain c))
                                                                 (cons 2 (var 0 domain))) :var)))
                    (charge ledger :relational-frame (syntax-work requirement))
                    (make-row :key key :known (list k c) :allowed (predicate-allowed domain requirement)))))))

(defun covered-frame (frame support)
  (make-frame (frame-schema frame)
              (loop for row in (frame-rows frame) for keep in support when keep collect row)))

(defun discover-arithmetic-solver (relation position query-values &key
                                   (operators '(:+ :- :* :/)) (literals :all)
                                   (body-bound 16) (work-limit 100000000))
  "Observe a bounded program vocabulary, select maximum observed coverage, and
learn guards through Boolean frames. The core search checks/selects witnesses.
Coverage is a declared proposal prior, not a claim about unseen input rows."
  (let* ((domain (arithmetic-relation-domain relation)) (inputs (arithmetic-inputs domain))
         (ledger (make-ledger)) (frame (orient-arithmetic-requirements relation position query-values ledger))
         (language (make-language domain inputs :operators (mapcar (lambda (name) (op name domain)) operators) :literals literals))
         (observations (start-observation-search (make-observation-scope frame language) :retain-outcomes t))
         (requirement (arithmetic-requirement relation position)))
    (finish-observations observations (+ (header-size inputs domain) body-bound) work-limit)
    (let* ((records (remove-if-not (lambda (record) (equal domain (observed-expression-type record)))
                                   (reverse (observation-job-records observations))))
           (checks (mapcar (lambda (record)
                             (let ((model (instantiate requirement (list (cons 2 (observed-expression-expression record))) :var)))
                               (charge ledger :solve-proposal (syntax-work model)) model)) records))
           (recovery (start-observation-search (make-observation-scope frame language)
                                               :expressions (cons (lit :bool t) checks) :retain-outcomes t)))
      (finish-observations recovery (reduce #'max (cons (lit :bool t) checks) :key (lambda (e) (description-size e inputs))) work-limit)
      (let* ((truth (find-observation recovery (lit :bool t)))
             (proposals (loop for record in records for check in checks collect
                          (let ((mask (observed-support (find-observation recovery check) truth ledger))
                                (model (observed-expression-expression record)))
                            (charge ledger :solve-ranking (+ (length (frame-rows frame)) (syntax-work model)))
                            (list record mask (count t mask) (description-size model inputs)))))
             (ranked (stable-sort (copy-list proposals)
                                  (lambda (a b)
                                    (charge ledger :solve-ranking)
                                    (let ((ca (third a)) (cb (third b)))
                                      (if (/= ca cb) (> ca cb)
                                          (< (fourth a) (fourth b)))))))
             (support (second (first ranked))))
        (assert (some #'identity support) () "No acceptable witness at the declared bounds")
        (let* ((models (loop for (record mask) in proposals do (charge ledger :solve-selection (length mask))
                            when (equal mask support) collect (observed-expression-expression record)))
               (search (start-search (covered-frame frame support) language :expressions models)))
          (assert (eq :replay-complete (message-claim (resume-search search
                       (reduce #'max models :key (lambda (e) (description-size e inputs))) work-limit))))
          (let* ((witness (candidate-expression (search-job-best search)))
                 (record (find-observation observations witness))
                 (discovery (make-solve-discovery :relation relation :position position :frame frame :observations observations
                                                  :recovery recovery :proposals proposals :search search :witness witness :ledger ledger)))
            (learn-solver-guard discovery record support work-limit)
            discovery))))))

(defun learn-solver-guard (discovery record support work-limit)
  "Learn definedness first; reorient computed forward results as guard features.
Both searches are ordinary Boolean synthesis. Compose and recheck the full mask."
  (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation))
         (inputs (arithmetic-inputs domain)) (ledger (solve-discovery-ledger discovery))
         (scope (observation-job-scope (solve-discovery-observations discovery)))
         (frame (solve-discovery-frame discovery))
         (defined (mapcar (lambda (outcome) (eq :value (observation-outcome-status outcome))) (observed-expression-outcomes record)))
         (domain-search (search-membership-frame (support-frame scope defined ledger) domain :work-limit work-limit))
         (witness (solve-discovery-witness discovery))
         (forward (arithmetic-application (arithmetic-relation-operator relation) (solve-discovery-position discovery) (var 0 domain) witness))
         (forward-job (start-observation-search (make-observation-scope frame (make-language domain inputs :operators nil :literals nil))
                                                :expressions (list forward) :retain-outcomes t)))
    (finish-observations forward-job (description-size forward inputs) work-limit)
    (let* ((outcomes (observed-expression-outcomes (find-observation forward-job forward)))
           (records (loop for row in (frame-rows frame) for outcome in outcomes
                          when (eq :value (observation-outcome-status outcome)) collect
                            (append (list (row-key row)) (row-known row)
                                    (list (observation-outcome-value outcome)
                                          (equal (second (row-known row)) (observation-outcome-value outcome))))))
           (features (orient-observations (list domain domain domain :bool) records '(0 1 2) '(3) :ledger ledger))
           (equality-search (search-membership-frame features domain :work-limit work-limit))
           (equality (compose-model (var 9 :bool) 9 (candidate-expression (search-job-best equality-search))
                                    (list (cons 0 (var 0 domain)) (cons 1 (var 1 domain)) (cons 2 forward)) ledger))
           (guard (literal-conditional (candidate-expression (search-job-best domain-search))
                                      (literal-conditional (arithmetic-definedness relation (solve-discovery-position discovery) (var 0 domain) witness)
                                                           equality (lit :bool nil)) (lit :bool nil)))
           (recheck (search-membership-frame (support-frame scope support ledger) domain :work-limit work-limit :expressions (list guard))))
      (setf (solve-discovery-guard discovery) guard
            (solve-discovery-guard-searches discovery) (list domain-search equality-search recheck forward-job)))))

(defun solve-witness-law (discovery)
  (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation)))
    (make-law domain (arithmetic-inputs domain)
              (instantiate (arithmetic-requirement relation (solve-discovery-position discovery))
                           (list (cons 2 (solve-discovery-witness discovery))) :var)
              (lit :bool t) :guard (solve-discovery-guard discovery))))

(defun solve-uniqueness-law (discovery)
  "Under G(k,c), R(k,c,z) iff z=q(k,c): validates the WHOLE fiber, not just a witness."
  (let* ((relation (solve-discovery-relation discovery)) (domain (arithmetic-relation-domain relation)))
    (make-law domain (arithmetic-inputs domain 3)
              (arithmetic-requirement relation (solve-discovery-position discovery))
              (app (op := domain) (var 2 domain) (solve-discovery-witness discovery))
              :guard (solve-discovery-guard discovery))))

(defun validate-arithmetic-solver (discovery &key (samples nil samples-p)
                                               (uniqueness-samples nil uniqueness-samples-p)
                                               (work-limit 100000000))
  "Reuse the existing validator. Integer samples never grant universal evidence."
  (let ((witness (solve-witness-law discovery)) (unique (solve-uniqueness-law discovery)))
    (setf (solve-discovery-validation discovery)
          (resume-law-validation (if samples-p (start-law-validation witness :samples samples) (start-law-validation witness)) work-limit)
          (solve-discovery-uniqueness discovery)
          (resume-law-validation (if uniqueness-samples-p (start-law-validation unique :samples uniqueness-samples) (start-law-validation unique)) work-limit))
    discovery))

(defun certified-solve-discovery-p (discovery)
  (and (arithmetic-relation-exhaustive-p (solve-discovery-relation discovery))
       (loop for state in (list (solve-discovery-validation discovery) (solve-discovery-uniqueness discovery))
             for expected in (list (solve-witness-law discovery) (solve-uniqueness-law discovery))
             always (and state (eq :validated (law-validation-status state))
                         (law-validation-certificate state)
                         (equalp (law-certificate-snapshot (law-validation-certificate state)) (law-snapshot expected))))))

(defun run-algebra-program (model inputs values ledger category)
  (let ((state (start-evaluation model inputs values)))
    (advance-accounted-evaluation state 100000000 ledger category category)
    (assert (not (eq :unknown (evaluation-status state))) () "Algebra evaluation cutoff")
    state))
