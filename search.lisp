(in-package #:lisploop)

(defstruct (language (:constructor %make-language))
  domain inputs operators (literals :all) (version 2))

(defun make-language (domain inputs &key (operators (list (op :+ domain) (op :* domain)))
                                        (literals :all))
  "Typed grammar with arithmetic, equality and lazy conditional primitives.
LITERALS defaults to :ALL, or declares a finite vocabulary without bounding values.
The default vocabulary stays +/*. Optional checked laws belong to the search job."
  (assert (or (eq domain :int) (and (consp domain) (eq (first domain) :gf))))
  (assert (every (lambda (input) (member (cdr input) (list domain :bool) :test #'equal)) inputs))
  (assert (every (lambda (operator)
                   (and (member (second operator) '(:+ :* :- :/ := :if))
                        (every (lambda (type) (member type (list domain :bool) :test #'equal))
                               (cons (third (operator-type operator))
                                     (second (operator-type operator)))))) operators))
  (assert (or (eq literals :all)
              (and (listp literals) (every (lambda (value) (value-p value domain)) literals))))
  (%make-language :domain (copy-tree domain) :inputs (copy-tree inputs)
                  :operators (remove-duplicates (copy-tree operators) :test #'equal)
                  :literals (if (eq literals :all) :all
                                (remove-duplicates (copy-list literals) :from-end t))))

(defun language-header-size (language &optional (target (language-domain language)))
  (header-size (language-inputs language) target))

(defun language-booleans-p (language)
  (or (find :bool (language-inputs language) :key #'cdr)
      (some (lambda (operator)
              (member :bool (cons (third (operator-type operator))
                                 (second (operator-type operator)))))
            (language-operators language))))

(defstruct (enumerator (:constructor make-enumerator (language)))
  language (size 1) (phase :variables) (cursor 0) (literal-pass 0) (literal-index 0)
  literal-next literal-end (boolean-index 0) (operator-index 0) sizes indices
  (buckets (make-hash-table :test #'equal)))

(defun syntax-bucket (enumerator type size)
  (gethash (list type size) (enumerator-buckets enumerator)))

(defun index-expression (enumerator expression)
  (let* ((language (enumerator-language enumerator))
         (type (expression-type expression (language-inputs language)))
         (key (list type (enumerator-size enumerator)))
         (buckets (enumerator-buckets enumerator)))
    (assert (= (enumerator-size enumerator) (body-size expression (language-inputs language))))
    (unless (gethash key buckets)
      (setf (gethash key buckets) (make-array 0 :adjustable t :fill-pointer 0)))
    (vector-push-extend expression (gethash key buckets))
    type))

(defun literal-range (domain size pass)
  "Exact body-bit intervals, without visiting integers outside the current bound."
  (let ((payload (- size 2)))
    (if (eq domain :int)
        (let ((width (loop for width from 1 to payload
                          when (= payload (+ width (* 2 (1- (integer-length width))))) return width)))
          (if (null width) (values 1 0)
              (let ((lo (ash 1 (1- width))) (hi (1- (ash 1 width))))
                (if (= pass 0)
                    (values (ceiling (1- lo) 2) (floor (1- hi) 2))
                    (values (max 1 (ceiling lo 2)) (floor hi 2))))))
        (if (and (= pass 0) (= payload (integer-length (1- (second domain)))))
            (values 0 (1- (second domain))) (values 1 0)))))

(defun reset-enumerator-bound (enumerator)
  (incf (enumerator-size enumerator))
  (setf (enumerator-phase enumerator) :variables
        (enumerator-cursor enumerator) 0
        (enumerator-literal-pass enumerator) 0
        (enumerator-literal-index enumerator) 0
        (enumerator-literal-next enumerator) nil
        (enumerator-operator-index enumerator) 0
        (enumerator-boolean-index enumerator) 0
        (enumerator-sizes enumerator) nil
        (enumerator-indices enumerator) nil))

(defun first-composition (total arity)
  (when (>= total arity)
    (append (make-list (1- arity) :initial-element 1) (list (- total (1- arity))))))

(defun next-composition (sizes)
  "Next positive composition of the same total, in lexicographic order."
  (loop for i downfrom (- (length sizes) 2) to 0
        for tail = (nthcdr (1+ i) sizes)
        for total = (reduce #'+ tail)
        when (> total (length tail)) do
          (return (append (subseq sizes 0 i) (list (1+ (nth i sizes)))
                          (make-list (1- (length tail)) :initial-element 1)
                          (list (- total (length tail)))))))

(defun advance-application-cursor (enumerator buckets)
  (let ((indices (enumerator-indices enumerator)))
    (loop for i downfrom (1- (length indices)) to 0 do
      (incf (nth i indices))
      (when (< (nth i indices) (length (nth i buckets))) (return-from advance-application-cursor))
      (setf (nth i indices) 0)))
  (setf (enumerator-sizes enumerator) (next-composition (enumerator-sizes enumerator)))
  (unless (enumerator-sizes enumerator) (incf (enumerator-operator-index enumerator))))

(defun enumeration-step (enumerator)
  "One cursor operation; return (candidate, event). No eager Cartesian products."
  (let* ((language (enumerator-language enumerator))
         (size (enumerator-size enumerator)))
    (ecase (enumerator-phase enumerator)
      (:variables
       (let ((input (nth (enumerator-cursor enumerator) (language-inputs language))))
         (if input
             (progn
               (incf (enumerator-cursor enumerator))
               (let ((expression (var (car input) (cdr input))))
                 (when (= size (body-size expression (language-inputs language)))
                   (return-from enumeration-step (values expression :candidate)))))
             (setf (enumerator-phase enumerator) :literals))))
      (:literals
       (unless (eq (language-literals language) :all)
         (let ((tail (nthcdr (enumerator-literal-index enumerator) (language-literals language))))
           (if tail
               (let ((expression (lit (language-domain language) (first tail))))
                 (incf (enumerator-literal-index enumerator))
                 (when (= size (body-size expression (language-inputs language)))
                   (return-from enumeration-step (values expression :candidate))))
               (setf (enumerator-phase enumerator) :booleans)))
         (return-from enumeration-step (values nil :progress)))
       (if (>= (enumerator-literal-pass enumerator) 2)
           (setf (enumerator-phase enumerator) :booleans)
           (progn
             (unless (enumerator-literal-next enumerator)
               (multiple-value-bind (lo hi)
                   (literal-range (language-domain language) size (enumerator-literal-pass enumerator))
                 (setf (enumerator-literal-next enumerator) lo
                       (enumerator-literal-end enumerator) hi)))
             (if (> (enumerator-literal-next enumerator) (enumerator-literal-end enumerator))
                 (setf (enumerator-literal-next enumerator) nil
                       (enumerator-literal-pass enumerator) (1+ (enumerator-literal-pass enumerator)))
                 (let ((value (enumerator-literal-next enumerator)))
                   (incf (enumerator-literal-next enumerator))
                   (return-from enumeration-step
                     (values (lit (language-domain language)
                                  (if (= 1 (enumerator-literal-pass enumerator)) (- value) value))
                             :candidate)))))))
      (:booleans
       (if (and (= size 3) (language-booleans-p language)
                (< (enumerator-boolean-index enumerator) 2))
           (return-from enumeration-step
             (values (lit :bool (= 1 (prog1 (enumerator-boolean-index enumerator)
                                      (incf (enumerator-boolean-index enumerator))))) :candidate))
           (setf (enumerator-phase enumerator) :applications)))
      (:applications
       (let ((operator (nth (enumerator-operator-index enumerator) (language-operators language))))
         (if (null operator)
             (setf (enumerator-phase enumerator) :finish)
             (let ((types (second (operator-type operator))))
               (unless (enumerator-sizes enumerator)
                 (setf (enumerator-sizes enumerator)
                       (first-composition (- size (application-overhead operator)) (length types))
                       (enumerator-indices enumerator) (make-list (length types) :initial-element 0)))
               (if (null (enumerator-sizes enumerator))
                   (incf (enumerator-operator-index enumerator))
                   (let ((buckets (mapcar (lambda (type bits) (syntax-bucket enumerator type bits))
                                          types (enumerator-sizes enumerator))))
                     (if (some #'null buckets)
                         (progn
                           (setf (enumerator-sizes enumerator)
                                 (next-composition (enumerator-sizes enumerator)))
                           (unless (enumerator-sizes enumerator)
                             (incf (enumerator-operator-index enumerator))))
                         (let ((expression (apply #'app operator
                                                  (mapcar #'aref buckets (enumerator-indices enumerator)))))
                           (advance-application-cursor enumerator buckets)
                           (return-from enumeration-step (values expression :candidate))))))))))
      (:finish
       (reset-enumerator-bound enumerator)
       (return-from enumeration-step (values nil :bound))))
    (values nil :progress)))

(defstruct candidate expression size run-work discovery-work)
(defstruct message call-id claim evidence)
(defstruct (search-job (:constructor %make-search-job))
  call-id frame language enumerator (ledger (make-ledger))
  (phase :enumerate) expression (construction-debt 0) rows evaluation predicted
  (run-work 0) (completed-bound 0) (results nil) best (run-weight 0)
  (rejected 0) (messages nil) library rewriting normal-form
  (reused-rejections 0) (rejection-cache (make-hash-table :test #'equal)))
(defvar *next-call-id* 0)

(defun start-search (frame language &key (call-id (incf *next-call-id*)) (run-weight 0) laws)
  (assert (equal (schema-inputs (frame-schema frame)) (language-inputs language)))
  (assert (and (realp run-weight) (>= run-weight 0)))
  (let* ((library (when laws (prepare-rewrite-library laws (language-domain language))))
         (job (%make-search-job :call-id call-id :frame frame :language language
                                :enumerator (make-enumerator language) :run-weight run-weight :library library
                                :completed-bound (language-header-size language (schema-target (frame-schema frame))))))
    (when library
      (setf (search-job-phase job) :rule-setup
            (search-job-construction-debt job) (rewrite-library-setup-work library)))
    job))

(defun candidate-score (candidate run-weight)
  (+ (candidate-size candidate) (* run-weight (candidate-run-work candidate))))

(defun reject-candidate (job &optional witnessed-p)
  ;; Only a successful prediction rejected by its requirement is reusable.
  ;; Errors are not equality evidence. The cache belongs to this exact frame/job.
  (when (and witnessed-p (search-job-library job))
    (setf (gethash (search-job-normal-form job) (search-job-rejection-cache job))
          (list :row (row-key (first (search-job-rows job))) :value (search-job-predicted job))))
  (incf (search-job-rejected job))
  (setf (search-job-phase job) :enumerate))

(defun accept-candidate (job)
  (let ((candidate (make-candidate :expression (search-job-expression job)
                                   :size (description-size (search-job-expression job)
                                                           (language-inputs (search-job-language job)))
                                   :run-work (search-job-run-work job)
                                   :discovery-work (ledger-total (search-job-ledger job)))))
    (push candidate (search-job-results job))
    (when (or (null (search-job-best job))
              (< (candidate-score candidate (search-job-run-weight job))
                 (candidate-score (search-job-best job) (search-job-run-weight job))))
      (setf (search-job-best job) candidate))
    (push (make-message :call-id (search-job-call-id job) :claim :candidate
                        :evidence candidate) (search-job-messages job))
    (setf (search-job-phase job) :enumerate)))

(defun advance-search-evaluation (job budget category)
  "Batch VM work and preserve the single-unit charge for an unpaid validation error."
  (let* ((ledger (search-job-ledger job)) (before (ledger-total ledger)))
    (multiple-value-bind (state unpaid-error-p)
        (advance-evaluation (search-job-evaluation job) budget ledger category)
      (when (or unpaid-error-p (= before (ledger-total ledger)))
        (charge ledger :validation))
      state)))

(defun search-step (job &optional (budget 1))
  "Advance one search phase using at most BUDGET tariff units.
Construction debt and VM instructions are paid in batches; single-unit stepping
remains available for diagnostics. Any unpaid work stays in the continuation."
  (assert (and (integerp budget) (plusp budget)))
  (let ((ledger (search-job-ledger job))
        (schema (frame-schema (search-job-frame job))))
    (ecase (search-job-phase job)
      (:rule-setup
       (let ((spent (min budget (search-job-construction-debt job))))
         (charge ledger :rule-setup spent) (decf (search-job-construction-debt job) spent))
       (when (zerop (search-job-construction-debt job)) (setf (search-job-phase job) :enumerate)))
      (:enumerate
       (charge ledger :enumeration)
       (multiple-value-bind (expression event) (enumeration-step (search-job-enumerator job))
         (case event
           (:candidate
            (setf (search-job-expression job) expression
                  (search-job-construction-debt job) (syntax-work expression)
                  (search-job-phase job) :construct))
           (:bound
            (setf (search-job-completed-bound job)
                  (+ (language-header-size (search-job-language job) (schema-target schema))
                     (1- (enumerator-size (search-job-enumerator job)))))))))
      (:construct
       (let ((spent (min budget (search-job-construction-debt job))))
         (charge ledger :construction spent)
         (decf (search-job-construction-debt job) spent))
       (when (zerop (search-job-construction-debt job))
         (let ((type (index-expression (search-job-enumerator job) (search-job-expression job))))
           (if (equal type (schema-target schema))
               (setf (search-job-rows job) (frame-rows (search-job-frame job))
                     (search-job-run-work job) 0
                     (search-job-phase job) (if (search-job-library job) :rewrite-start :row))
               (setf (search-job-phase job) :enumerate)))))
      (:rewrite-start
       (charge ledger :scheduling)
       (setf (search-job-rewriting job)
             (start-rewriting (search-job-expression job) (schema-inputs schema) (search-job-library job))
             (search-job-phase job) :rewrite))
      (:rewrite
       (let ((state (advance-rewriting (search-job-rewriting job) budget ledger)))
         (when (eq :complete (rewriting-status state))
           (setf (search-job-normal-form job) (rewriting-value state)
                 (search-job-construction-debt job) (syntax-work (rewriting-value state))
                 (search-job-phase job) :reuse))))
      (:reuse
       (let ((spent (min budget (search-job-construction-debt job))))
         (charge ledger :equality-cache spent) (decf (search-job-construction-debt job) spent))
       (when (zerop (search-job-construction-debt job))
         (if (gethash (search-job-normal-form job) (search-job-rejection-cache job))
             (progn (incf (search-job-reused-rejections job)) (reject-candidate job))
             (setf (search-job-phase job) :row))))
      (:row
       (charge ledger :scheduling)
       (if (null (search-job-rows job))
           (accept-candidate job)
           (setf (search-job-evaluation job)
                 (start-evaluation (search-job-expression job) (schema-inputs schema)
                                   (row-known (first (search-job-rows job))))
                 (search-job-phase job) :evaluate)))
      (:evaluate
       (let ((state (advance-search-evaluation job budget :evaluation)))
         (case (evaluation-status state)
           (:error (reject-candidate job))
           (:value
            (incf (search-job-run-work job) (evaluation-work state))
            (setf (search-job-predicted job) (evaluation-value state)
                  (search-job-phase job) :requirement)))))
      (:requirement
       (charge ledger :scheduling)
       (setf (search-job-evaluation job)
             (start-evaluation (allowed-expression (row-allowed (first (search-job-rows job))))
                               (list (cons 0 (schema-target schema)))
                               (list (search-job-predicted job)))
             (search-job-phase job) :check))
      (:check
       (let ((state (advance-search-evaluation job budget :checking)))
         (case (evaluation-status state)
           (:error (reject-candidate job))
           (:value
            (if (eq t (evaluation-value state))
                (progn (pop (search-job-rows job)) (setf (search-job-phase job) :row))
                (reject-candidate job t)))))))))

(defun resume-search (job description-limit work-limit &key quantum)
  "Absolute cumulative work limit and total packet-bit bound. Return a scoped
cutoff or completed bounded exhaustion; neither claims the goal is impossible.
All successful programs remain available, including after an incumbent is found.
Batch up to the remaining budget within each phase. Optional QUANTUM caps the
batch size; QUANTUM=1 reproduces single-unit stepping without changing the tariff."
  (assert (and (integerp description-limit) (>= description-limit 0)
               (integerp work-limit) (>= work-limit 0)))
  (assert (or (null quantum) (and (integerp quantum) (plusp quantum))))
  (loop while (and (< (search-job-completed-bound job) description-limit)
                   (< (ledger-total (search-job-ledger job)) work-limit))
        do (let ((remaining (- work-limit (ledger-total (search-job-ledger job)))))
             (search-step job (if quantum (min quantum remaining) remaining))))
  (let ((message
          (make-message
           :call-id (search-job-call-id job)
           :claim (if (>= (search-job-completed-bound job) description-limit)
                      :bounded-exhaustion :cutoff)
           :evidence (list :description-limit description-limit
                           :completed-bound (search-job-completed-bound job)
                           :work (ledger-total (search-job-ledger job))
                           :phase (search-job-phase job)
                           :encoding-version +encoding-version+ :tariff-version +tariff-version+
                           :language-version (language-version (search-job-language job))))))
    (push message (search-job-messages job))
    message))
