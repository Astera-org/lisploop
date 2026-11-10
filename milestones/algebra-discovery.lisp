(in-package #:lisploop)

;;; Milestones 3A and 4: guard problems from observed support, and arithmetic solver discovery.

;;; Guard Discovery & Support Frames
(defstruct (guard-problem (:constructor %make-guard-problem)) scope support frame equations)

(defun complete-outcomes-p (record)
  (and (member (observed-expression-status record) '(:complete :error))
       (= (length (observed-expression-outcomes record))
          (length (frame-rows (observation-scope-frame (observed-expression-scope record)))))
       (every (lambda (outcome) (member (observation-outcome-status outcome) '(:value :error)))
              (observed-expression-outcomes record))))

(defun observed-support (left right &optional ledger)
  "Exact row membership where both expressions return equal, same-typed values."
  (assert (eq (observed-expression-scope left) (observed-expression-scope right)))
  (assert (equal (observed-expression-type left) (observed-expression-type right)))
  (assert (and (complete-outcomes-p left) (complete-outcomes-p right)) ()
          "Support requires completed per-row outcomes; resume observation first")
  (loop with type = (observed-expression-type left)
        for a in (observed-expression-outcomes left)
        for b in (observed-expression-outcomes right) collect
          (progn
            (charge ledger :support-comparison
                    (+ 2 (if (eq :value (observation-outcome-status a))
                             (value-work (observation-outcome-value a) type) 0)
                         (if (eq :value (observation-outcome-status b))
                             (value-work (observation-outcome-value b) type) 0)))
            (and (eq :value (observation-outcome-status a))
                 (eq :value (observation-outcome-status b))
                 (equal (observation-outcome-value a) (observation-outcome-value b))))))

(defun propose-guard-problems (job &optional ledger)
  "Compare all pairs of finished expressions and group proper nonempty supports."
  (assert (observation-job-retain-outcomes-p job))
  (assert (and (eq :enumerate (observation-job-phase job))
               (observation-bound-complete-p job (observation-job-requested-bound job))) ()
          "Finish the requested observation bound before constructing guard problems")
  (let* ((scope (observation-job-scope job))
         (domain (language-domain (observation-scope-language scope)))
         (records (reverse (observation-job-records job)))
         (groups (make-hash-table :test #'equal)) (problems nil))
    (assert (every #'complete-outcomes-p records))
    (loop for tail on records for left = (first tail) do
      (dolist (right (rest tail))
        (charge ledger :support-pairs)
        (when (and (equal (observed-expression-type left) (observed-expression-type right))
                   (law-type-p (observed-expression-type left) domain))
          (let ((support (observed-support left right ledger)))
            (charge ledger :support-index (1+ (length support)))
            (when (and (some #'identity support) (not (every #'identity support)))
              (let ((problem (gethash support groups))
                    (a (observed-expression-expression left))
                    (b (observed-expression-expression right)))
                (unless problem
                  (setf problem (%make-guard-problem :scope scope :support support
                                                     :frame (support-frame scope support ledger))
                        (gethash support groups) problem)
                  (push problem problems))
                (charge ledger :guard-equations (+ (syntax-work a) (syntax-work b)))
                (push (list (copy-tree a) (copy-tree b)) (guard-problem-equations problem))))))))
    (dolist (problem problems)
      (setf (guard-problem-equations problem) (nreverse (guard-problem-equations problem))))
    (nreverse problems)))

(defun start-guard-search (problem language &key (call-id (incf *next-call-id*)) (run-weight 0))
  "Synthesize the complete observed support, including its false rows."
  (let ((source (observation-scope-language (guard-problem-scope problem))))
    (assert (equal (language-domain source) (language-domain language)))
    (assert (equal (language-inputs source) (language-inputs language)))
    (start-search (guard-problem-frame problem)
                  (snapshot-language language)
                  :call-id call-id :run-weight run-weight)))

(defun propose-guarded-laws (problem search &optional ledger)
  "Attach the best successful guard so far to each equation, as conjectures only."
  (assert (equalp (search-job-frame search) (guard-problem-frame problem)))
  (let* ((scope (guard-problem-scope problem)) (language (observation-scope-language scope))
         (best (search-job-best search)) (guard (and best (candidate-expression best))))
    (when best
      (loop for (left right) in (guard-problem-equations problem) collect
        (progn
          (charge ledger :law-proposal (+ (syntax-work left) (syntax-work right) (syntax-work guard)
                                          (length (guard-problem-support problem))))
          (make-law (language-domain language) (language-inputs language) left right :guard guard
                    :origin (list :observed-scope (observation-scope-id scope)
                                  :support (copy-list (guard-problem-support problem))
                                  :evidence :replayed-observations)))))))

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
                    (header-bound inputs :bool body-bound))))
    (resume-search job bound work-limit)
    (assert (search-job-best job) () "Membership search unresolved at the supplied bounds")
    job))

(defun observe-arithmetic-values (domain operator values work-limit &optional expression)
  (let* ((inputs (arithmetic-inputs domain))
         (forward (or expression (app operator (var 0 domain) (var 1 domain))))
         (frame (make-frame (make-schema :inputs inputs :target domain)
                            (loop for a in values for block from 0 append
                              (loop for b in values for key from (* block (length values)) collect
                                (make-row :key key :known (list a b) :requirement (lit :bool t))))))
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
  "Acquire forward executions, including errors, and learn their definedness guard."
  (let* ((operator (op name domain)) (ledger (make-ledger))
         (job (observe-arithmetic-values domain operator values work-limit))
         (forward (app operator (var 0 domain) (var 1 domain))))
    (let* ((record (find-observation job forward))
           (support (mapcar (lambda (outcome) (eq :value (observation-outcome-status outcome)))
                            (observed-expression-outcomes record)))
           (guard-job (search-membership-frame (support-frame (observation-job-scope job) support ledger) domain :work-limit work-limit))
           (records (arithmetic-forward-records job ledger)))
      (make-arithmetic-relation
       :domain domain :operator operator :observations job :records records
       :guard (copy-tree (candidate-expression (search-job-best guard-job)))
       :exhaustive-p (and (gf-type-p domain)
                          (= (second domain) (length (remove-duplicates values)))
                          (every (lambda (value) (value-p value domain)) values))))))

(defun orient-arithmetic-requirements (relation position query-values ledger)
  "Retain witnessed occurrences and add declared queries, without solving fibers."
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
                    (make-row :key key :known (list k c) :requirement requirement))))))

(defun covered-frame (frame support)
  (make-frame (frame-schema frame)
              (loop for row in (frame-rows frame) for keep in support when keep collect row)))

(defun discover-arithmetic-solver (relation position query-values &key
                                   (operators '(:+ :- :* :/)) (literals :all)
                                   (body-bound 16) (work-limit +completion-work+))
  "Observe a bounded program vocabulary, select maximum observed coverage, and
learn guards through Boolean frames."
  (let* ((domain (arithmetic-relation-domain relation)) (inputs (arithmetic-inputs domain))
         (ledger (make-ledger)) (frame (orient-arithmetic-requirements relation position query-values ledger))
         (language (make-language domain inputs :operators (mapcar (lambda (name) (op name domain)) operators) :literals literals))
         (observations (start-observation-search (make-observation-scope frame language) :retain-outcomes t))
         (requirement (arithmetic-requirement relation position)))
    (finish-observations observations (header-bound inputs domain body-bound) work-limit)
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
                 (discovery (make-solve-discovery :relation relation :position position :frame frame
                                                  :observations observations :witness witness :ledger ledger)))
            (learn-solver-guard discovery record support work-limit)
            discovery))))))

(defun learn-solver-guard (discovery record support work-limit)
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
                                                            equality (lit :bool nil)) (lit :bool nil))))
      ;; The composed guard must itself satisfy the selected support.
      (search-membership-frame (support-frame scope support ledger) domain
                               :work-limit work-limit :expressions (list guard))
      (setf (solve-discovery-guard discovery) guard))))
