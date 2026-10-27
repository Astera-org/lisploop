(in-package #:lisploop)

(defstruct (language (:constructor %make-language)) domain inputs operators (version 1))

(defun make-language (domain inputs &key (operators (list (op :+ domain) (op :* domain))))
  "The baseline grammar: declared variables, every domain literal, binary primitives.
No observational deduplication, algebraic rewrites, lookup proposals, or sketches."
  (assert (or (eq domain :int) (and (consp domain) (eq (first domain) :gf))))
  (dolist (operator operators)
    (assert (= 2 (length (second (operator-type operator))))))
  (%make-language :domain (copy-tree domain) :inputs (copy-tree inputs)
                  :operators (remove-duplicates (copy-tree operators) :test #'equal)))

(defstruct (enumerator (:constructor make-enumerator (language)))
  language (size 1) (phase :variables) (cursor 0) (literal-pass 0)
  literal-next literal-end (operator-index 0) (split 1) (left-index 0) (right-index 0)
  (buckets (make-hash-table :test #'equal)))

(defun syntax-bucket (enumerator type size)
  (gethash (list type size) (enumerator-buckets enumerator)))

(defun index-expression (enumerator expression)
  (let* ((language (enumerator-language enumerator))
         (type (expression-type expression (language-inputs language)))
         (key (list type (enumerator-size enumerator)))
         (buckets (enumerator-buckets enumerator)))
    (assert (= (enumerator-size enumerator) (description-size expression)))
    (unless (gethash key buckets)
      (setf (gethash key buckets) (make-array 0 :adjustable t :fill-pointer 0)))
    (vector-push-extend expression (gethash key buckets))
    type))

(defun literal-range (domain size pass)
  "An exact-size interval, generated lazily even for the unbounded integer domain."
  (let* ((digits (- size (1- (description-size (lit domain 0)))))
         (negative-p (= pass 1))
         (magnitude-digits (- digits (if negative-p 1 0))))
    (if (or (< magnitude-digits 1) (and negative-p (not (eq domain :int))))
        (values 1 0)
        (let ((lo (if (= magnitude-digits 1) (if negative-p 1 0)
                      (expt 10 (1- magnitude-digits))))
              (hi (1- (expt 10 magnitude-digits))))
          (values lo (if (eq domain :int) hi (min hi (1- (second domain)))))))))

(defun reset-enumerator-bound (enumerator)
  (incf (enumerator-size enumerator))
  (setf (enumerator-phase enumerator) :variables
        (enumerator-cursor enumerator) 0
        (enumerator-literal-pass enumerator) 0
        (enumerator-literal-next enumerator) nil
        (enumerator-operator-index enumerator) 0
        (enumerator-split enumerator) 1
        (enumerator-left-index enumerator) 0
        (enumerator-right-index enumerator) 0))

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
                 (when (= size (description-size expression))
                   (return-from enumeration-step (values expression :candidate)))))
             (setf (enumerator-phase enumerator) :literals))))
      (:literals
       (if (>= (enumerator-literal-pass enumerator) 2)
           (setf (enumerator-phase enumerator) :applications)
           (progn
             (unless (enumerator-literal-next enumerator)
               (multiple-value-bind (lo hi)
                   (literal-range (language-domain language) size
                                  (enumerator-literal-pass enumerator))
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
      (:applications
       (let ((operator (nth (enumerator-operator-index enumerator) (language-operators language))))
         (if (null operator)
             (setf (enumerator-phase enumerator) :finish)
             (let* ((types (second (operator-type operator)))
                    (overhead (1+ (description-size (app operator))))
                    (left-size (enumerator-split enumerator))
                    (right-size (- size overhead left-size)))
               (if (< right-size 1)
                   (setf (enumerator-operator-index enumerator)
                         (1+ (enumerator-operator-index enumerator))
                         (enumerator-split enumerator) 1
                         (enumerator-left-index enumerator) 0
                         (enumerator-right-index enumerator) 0)
                   (let ((left (syntax-bucket enumerator (first types) left-size))
                         (right (syntax-bucket enumerator (second types) right-size)))
                     (if (or (null left) (null right))
                         (incf (enumerator-split enumerator))
                         (let ((expression
                                 (app operator
                                      (aref left (enumerator-left-index enumerator))
                                      (aref right (enumerator-right-index enumerator)))))
                           (incf (enumerator-right-index enumerator))
                           (when (= (enumerator-right-index enumerator) (length right))
                             (setf (enumerator-right-index enumerator) 0)
                             (incf (enumerator-left-index enumerator))
                             (when (= (enumerator-left-index enumerator) (length left))
                               (setf (enumerator-left-index enumerator) 0)
                               (incf (enumerator-split enumerator))))
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
  (rejected 0) (messages nil))
(defvar *next-call-id* 0)

(defun start-search (frame language &key (call-id (incf *next-call-id*)) (run-weight 0))
  (assert (equal (schema-inputs (frame-schema frame)) (language-inputs language)))
  (assert (and (realp run-weight) (>= run-weight 0)))
  (%make-search-job :call-id call-id :frame frame :language language
                    :enumerator (make-enumerator language) :run-weight run-weight))

(defun candidate-score (candidate run-weight)
  (+ (candidate-size candidate) (* run-weight (candidate-run-work candidate))))

(defun reject-candidate (job)
  (incf (search-job-rejected job))
  (setf (search-job-phase job) :enumerate))

(defun accept-candidate (job)
  (let ((candidate (make-candidate :expression (search-job-expression job)
                                   :size (description-size (search-job-expression job))
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

(defun search-step (job)
  "One metered quantum. A partial evaluator/checker survives the quantum unchanged."
  (let ((ledger (search-job-ledger job))
        (schema (frame-schema (search-job-frame job))))
    (ecase (search-job-phase job)
      (:enumerate
       (charge ledger :enumeration)
       (multiple-value-bind (expression event) (enumeration-step (search-job-enumerator job))
         (case event
           (:candidate
            (setf (search-job-expression job) expression
                  (search-job-construction-debt job) (description-size expression)
                  (search-job-phase job) :construct))
           (:bound
            (setf (search-job-completed-bound job)
                  (1- (enumerator-size (search-job-enumerator job))))))))
      (:construct
       (charge ledger :construction)
       (when (zerop (decf (search-job-construction-debt job)))
         (let ((type (index-expression (search-job-enumerator job) (search-job-expression job))))
           (if (equal type (schema-target schema))
               (setf (search-job-rows job) (frame-rows (search-job-frame job))
                     (search-job-run-work job) 0
                     (search-job-phase job) :row)
               (setf (search-job-phase job) :enumerate)))))
      (:row
       (charge ledger :scheduling)
       (if (null (search-job-rows job))
           (accept-candidate job)
           (setf (search-job-evaluation job)
                 (start-evaluation (search-job-expression job) (schema-inputs schema)
                                   (row-known (first (search-job-rows job))))
                 (search-job-phase job) :evaluate)))
      (:evaluate
       (let* ((state (search-job-evaluation job)) (before (ledger-total ledger)))
         (advance-evaluation state 1 ledger :evaluation)
         (when (= before (ledger-total ledger)) (charge ledger :validation))
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
       (let* ((state (search-job-evaluation job)) (before (ledger-total ledger)))
         (advance-evaluation state 1 ledger :checking)
         (when (= before (ledger-total ledger)) (charge ledger :validation))
         (case (evaluation-status state)
           (:error (reject-candidate job))
           (:value
            (if (eq t (evaluation-value state))
                (progn (pop (search-job-rows job)) (setf (search-job-phase job) :row))
                (reject-candidate job)))))))))

(defun resume-search (job description-limit work-limit)
  "Absolute cumulative work limit, finite canonical-byte limit. Return a scoped
cutoff or completed bounded exhaustion; neither claims the goal is impossible.
All successful programs remain available, including after an incumbent is found."
  (assert (and (integerp description-limit) (>= description-limit 0)
               (integerp work-limit) (>= work-limit 0)))
  (loop while (and (< (search-job-completed-bound job) description-limit)
                   (< (ledger-total (search-job-ledger job)) work-limit))
        do (search-step job))
  (let ((message
          (make-message
           :call-id (search-job-call-id job)
           :claim (if (>= (search-job-completed-bound job) description-limit)
                      :bounded-exhaustion :cutoff)
           :evidence (list :description-limit description-limit
                           :completed-bound (search-job-completed-bound job)
                           :work (ledger-total (search-job-ledger job))
                           :phase (search-job-phase job)
                           :language-version (language-version (search-job-language job))))))
    (push message (search-job-messages job))
    message))
