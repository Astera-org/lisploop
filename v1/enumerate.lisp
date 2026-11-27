(in-package #:lisploop)

;;; Typed grammar enumeration, exact search over frame rows, and observation search.

(defstruct (language (:constructor %make-language))
  domain inputs operators (literals :all) constants (version 3))

(defun make-language (domain inputs &key (operators (list (op :+ domain) (op :* domain)))
                                        (literals :all) constants)
  "Finite typed productions over the VM's primitives, including quoted syntax.
LITERALS defaults to :ALL, or declares a finite vocabulary without bounding values.
CONSTANTS supplies additional typed literal ASTs. The default operators stay +/*."
  (assert (or (eq domain :int) (gf-type-p domain)))
  (assert (valid-inputs-p inputs))
  (mapc #'operator-type operators)
  (dolist (constant constants)
    (assert (lit-p constant))
    (expression-type constant nil))
  (assert (or (eq literals :all)
              (and (listp literals) (every (lambda (value) (value-p value domain)) literals))))
  (%make-language :domain (copy-tree domain) :inputs (copy-tree inputs)
                  :operators (remove-duplicates (copy-tree operators) :test #'equal)
                  :constants (remove-duplicates (copy-tree constants) :test #'equal)
                  :literals (if (eq literals :all) :all
                                (remove-duplicates (copy-list literals) :from-end t))))

(defun derive-language (language &key (inputs (language-inputs language))
                                      (operators (language-operators language))
                                      (literals (language-literals language))
                                      (constants (language-constants language)))
  "A language over LANGUAGE's domain that differs from it only in the fields supplied."
  (make-language (language-domain language) inputs
                 :operators operators :literals literals :constants constants))

(defun language-operator-p (language name)
  "True when LANGUAGE offers an operator named NAME."
  (some (lambda (operator) (and (operator-p operator) (eq name (operator-name operator))))
        (language-operators language)))

(defun snapshot-language (language)
  (let ((snapshot (copy-language language)))
    (setf (language-domain snapshot) (copy-tree (language-domain language))
          (language-inputs snapshot) (copy-tree (language-inputs language))
          (language-operators snapshot) (copy-tree (language-operators language))
          (language-literals snapshot) (copy-tree (language-literals language))
          (language-constants snapshot) (copy-tree (language-constants language)))
    snapshot))

(defun language-header-size (language &optional (target (language-domain language)))
  (header-size (language-inputs language) target))

(defun language-booleans-p (language)
  (or (find :bool (language-inputs language) :key #'cdr)
      (some (lambda (operator)
              (member :bool (cons (third (operator-type operator))
                                  (second (operator-type operator)))))
            (language-operators language))))

(defstruct (enumerator (:constructor make-enumerator (language)))
  language (size 1) (phase :variables) (cursor 0) (literal-pass 0)
  literal-next literal-end (operator-index 0) sizes indices
  (buckets (make-hash-table :test #'equal)))

(defun syntax-bucket (enumerator type size)
  (gethash (list type size) (enumerator-buckets enumerator)))

(defun index-expression (enumerator expression)
  "File EXPRESSION, which ENUMERATOR has just built, under its type and size, and return
its type. The enumerator builds an application from buckets of its operator's argument
types, so the type and size are read off the cached metadata, not checked by another walk;
a candidate that is evaluated is type-checked then, once."
  (let* ((language (enumerator-language enumerator))
         (inputs (language-inputs language))
         (type (ast-type expression))
         (key (list type (enumerator-size enumerator)))
         (buckets (enumerator-buckets enumerator)))
    (assert (= (enumerator-size enumerator)
               (scoped-bits expression (reference-width inputs expression))))
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
        (enumerator-literal-next enumerator) nil
        (enumerator-operator-index enumerator) 0
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
         (inputs (language-inputs language))
         (domain (language-domain language))
         (literals (language-literals language))
         (size (enumerator-size enumerator)))
    (flet ((atom-step (items build next-phase)
             ;; Visit one of ITEMS per step, offering (BUILD item) when it is an expression of the
             ;; current size. Past the last item the step moves on to NEXT-PHASE.
             (let ((tail (nthcdr (enumerator-cursor enumerator) items)))
               (if (null tail)
                   (setf (enumerator-cursor enumerator) 0
                         (enumerator-phase enumerator) next-phase)
                   (let ((expression (funcall build (first tail))))
                     (incf (enumerator-cursor enumerator))
                     (when (and expression (= size (body-size expression inputs)))
                       (return-from enumeration-step (values expression :candidate))))))))
      (ecase (enumerator-phase enumerator)
        (:variables (atom-step inputs (lambda (input) (var (car input) (cdr input))) :literals))
        (:literals
         (cond ((not (eq literals :all))
                (atom-step literals (lambda (value) (lit domain value)) :booleans))
               ((>= (enumerator-literal-pass enumerator) 2)
                (setf (enumerator-phase enumerator) :booleans))
               (t
                (unless (enumerator-literal-next enumerator)
                  (multiple-value-bind (lo hi)
                      (literal-range domain size (enumerator-literal-pass enumerator))
                    (setf (enumerator-literal-next enumerator) lo
                          (enumerator-literal-end enumerator) hi)))
                (if (> (enumerator-literal-next enumerator) (enumerator-literal-end enumerator))
                    (setf (enumerator-literal-next enumerator) nil
                          (enumerator-literal-pass enumerator) (1+ (enumerator-literal-pass enumerator)))
                    (let ((value (enumerator-literal-next enumerator)))
                      (incf (enumerator-literal-next enumerator))
                      (return-from enumeration-step
                        (values (lit domain (if (= 1 (enumerator-literal-pass enumerator)) (- value) value))
                                :candidate)))))))
        (:booleans
         (atom-step (when (and (= size 3) (language-booleans-p language)) '(nil t))
                    (lambda (value) (lit :bool value))
                    (if (language-constants language) :constants :applications)))
        (:constants
         ;; A constant that the literal or boolean phase already offers is not repeated.
         (atom-step (language-constants language)
                    (lambda (constant)
                      (unless (or (and (equal (ast-type constant) domain)
                                       (or (eq :all literals) (member (ast-value constant) literals)))
                                  (and (eq :bool (ast-type constant)) (language-booleans-p language)))
                        constant))
                    :applications))
        (:applications
         (let ((operator (nth (enumerator-operator-index enumerator) (language-operators language))))
           (if (null operator)
               (setf (enumerator-phase enumerator) :finish)
               (let ((types (second (operator-type operator))))
                 (when (null types)
                   (incf (enumerator-operator-index enumerator))
                   (return-from enumeration-step
                     (if (= size (application-overhead operator)) (values (app operator) :candidate)
                         (values nil :progress))))
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
         (return-from enumeration-step (values nil :bound)))))
    (values nil :progress)))

;;; Search and Matrix Evaluation
(defstruct candidate expression size run-work discovery-work)

(defstruct message call-id claim evidence)

(defvar *noted* :none
  "What host work that is being staged has noted so far, latest first, each (claim . evidence);
:none outside such work. Whoever stages the work sends them as messages when it is published,
so that they become visible when the result they describe does.")

(defun note-event (claim &rest evidence)
  "Note CLAIM with EVIDENCE, a property list, for the staged work that is running, if any is."
  (unless (eq *noted* :none)
    (push (cons claim evidence) *noted*)))

(defstruct row-job
  "State shared by the resumable jobs that draw candidate expressions, pay for their construction
and evaluate each one on the rows of a frame. DEBT is staged host work not yet charged."
  call-id frame language enumerator (mode :enumeration) queue (ledger (make-ledger))
  (phase :enumerate) (debt 0) expression rows evaluation
  (completed-bound 0) (requested-bound 0) (messages nil))

(defstruct (search-job (:include row-job) (:constructor %make-search-job))
  proposals (resolved-rows 0) predicted (run-work 0) (results nil) best (run-weight 0) row-budget
  (rejected 0) diagnostics library rewriting normal-form
  (reused-rejections 0) (rejection-cache (make-hash-table :test #'equal))
  hard-edges ; the frame's :equal and :distinct edges, which every candidate must satisfy
  values)    ; (row-key . value) of the candidate on the rows visited, kept only for those edges

(defvar *next-call-id* 0)

(defun proposal-queue (expressions language)
  "A private copy of EXPRESSIONS without duplicates, each checked to be typed over LANGUAGE's
inputs, in order of description size with ties left as given."
  (let ((inputs (language-inputs language))
        (queue (remove-duplicates (copy-tree expressions) :test #'equal)))
    (dolist (expression queue) (expression-type expression inputs))
    (stable-sort queue #'< :key (lambda (expression) (description-size expression inputs)))))

(defun row-job-target (job)
  (schema-target (frame-schema (row-job-frame job))))

(defun next-row (job)
  "Leave the current row and schedule the one after it."
  (pop (row-job-rows job))
  (setf (row-job-phase job) :row))

(defun row-job-step (job budget admit consume finish)
  "Advance one of the phases every row job shares, using at most BUDGET tariff units: draw a
candidate, pay for its construction, then evaluate it on each frame row in turn. ADMIT takes the
job and the constructed candidate's type and returns the phase to enter. CONSUME takes the job and
a row evaluation that has just advanced. FINISH takes the job once no rows remain."
  (let ((ledger (row-job-ledger job))
        (enumerator (row-job-enumerator job))
        (inputs (language-inputs (row-job-language job))))
    (ecase (row-job-phase job)
      (:enumerate
       (charge ledger :enumeration)
       (multiple-value-bind (expression event)
           (if enumerator (enumeration-step enumerator) (values (pop (row-job-queue job)) :candidate))
         (case event
           (:candidate
            (setf (row-job-expression job) expression
                  (row-job-debt job) (syntax-work expression)
                  (row-job-phase job) :construct))
           (:bound
            (setf (row-job-completed-bound job)
                  (+ (language-header-size (row-job-language job) (row-job-target job))
                     (1- (enumerator-size enumerator))))))))
      (:construct
       (pay-debt (row-job-debt job) budget ledger :construction)
       (when (zerop (row-job-debt job))
         (let ((expression (row-job-expression job)))
           (setf (row-job-rows job) (frame-rows (row-job-frame job))
                 (row-job-phase job)
                 (funcall admit job (if enumerator
                                        (index-expression enumerator expression)
                                        (expression-type expression inputs)))))))
      (:row
       (charge ledger :scheduling)
       (if (row-job-rows job)
           (setf (row-job-evaluation job)
                 (start-evaluation (row-job-expression job) inputs (row-known (first (row-job-rows job))))
                 (row-job-phase job) :evaluate)
           (funcall finish job)))
      (:evaluate
       (let ((state (row-job-evaluation job)))
         (advance-accounted-evaluation state budget ledger :evaluation :validation)
         (funcall consume job state))))))

(defun row-job-bound-complete-p (job bound)
  "True when JOB has settled every candidate of at most BOUND description bits."
  (if (eq :enumeration (row-job-mode job))
      (>= (row-job-completed-bound job) bound)
      (and (eq :enumerate (row-job-phase job))
           (or (null (row-job-queue job))
               (> (description-size (first (row-job-queue job)) (language-inputs (row-job-language job)))
                  bound)))))

(defun resume-row-job (job step description-limit work-limit quantum &rest evidence)
  "Run STEP on JOB until DESCRIPTION-LIMIT packet bits are settled or its ledger reaches the
absolute cumulative WORK-LIMIT. Record and return a message whose evidence ends with EVIDENCE."
  (assert (and (integerp description-limit) (>= description-limit (row-job-requested-bound job))
               (integerp work-limit) (>= work-limit 0)))
  (assert (or (null quantum) (and (integerp quantum) (plusp quantum))))
  (setf (row-job-requested-bound job) description-limit)
  (let ((ledger (row-job-ledger job))
        (replay-p (eq :replay (row-job-mode job))))
    (loop until (or (row-job-bound-complete-p job description-limit)
                    (>= (ledger-total ledger) work-limit))
          do (let ((remaining (- work-limit (ledger-total ledger))))
               (funcall step job (if quantum (min quantum remaining) remaining))))
    (let ((complete-p (row-job-bound-complete-p job description-limit)))
      (when (and replay-p complete-p)
        (setf (row-job-completed-bound job) description-limit))
      (let ((message
              (make-message
               :call-id (row-job-call-id job)
               :claim (cond ((not complete-p) :cutoff) (replay-p :replay-complete) (t :bounded-exhaustion))
               :evidence (list* :description-limit description-limit
                                :completed-bound (row-job-completed-bound job)
                                :work (ledger-total ledger)
                                :phase (row-job-phase job)
                                :syntax-coverage (if replay-p :listed-expressions :grammar)
                                :encoding-version +encoding-version+ :tariff-version +tariff-version+
                                evidence))))
        (push message (row-job-messages job))
        message))))

(defun enter-rule-setup (job)
  "Stage the one-time cost of the job's rewrite library, or begin enumerating when it has none."
  (let ((library (search-job-library job)))
    (if library
        (setf (search-job-phase job) :rule-setup
              (search-job-debt job) (rewrite-library-setup-work library))
        (setf (search-job-phase job) :enumerate))))

(defun start-search (frame language &key (call-id (incf *next-call-id*)) (run-weight 0) row-budget laws diagnostics
                                        (expressions nil supplied-p))
  "Use the canonical enumerator, or check a declared list of complete proposals.
Listed proposals use the same construction, VM, checker and objective."
  (assert (equal (schema-inputs (frame-schema frame)) (language-inputs language)))
  (assert-inputs-available frame)
  (assert (and (realp run-weight) (>= run-weight 0)))
  (assert (or (null row-budget) (and (integerp row-budget) (plusp row-budget))))
  (setf frame (snapshot-frame frame) language (snapshot-language language))
  (let* ((library (when laws (as-rewrite-library laws :domain (language-domain language))))
         (queue (proposal-queue expressions language))
         (job (%make-search-job :call-id call-id :frame frame :language language
                                :mode (if supplied-p :replay :enumeration)
                                :enumerator (unless supplied-p (make-enumerator language))
                                :queue queue :proposals (copy-list queue)
                                :run-weight run-weight :row-budget row-budget
                                :library library :diagnostics diagnostics
                                :hard-edges (hard-edges frame)
                                :completed-bound
                                (language-header-size language (schema-target (frame-schema frame))))))
    (if supplied-p
        (let ((count (length expressions)))
          (setf (search-job-phase job) :proposal-setup
                (search-job-debt job)
                (+ 1 (* count (1+ (integer-length count)))
                   (reduce #'+ expressions :key #'syntax-work :initial-value 0))))
        (enter-rule-setup job))
    job))

(defun candidate-score (candidate run-weight)
  (+ (candidate-size candidate) (* run-weight (candidate-run-work candidate))))

(defun reject-candidate (job &optional witnessed-p)
  (when (search-job-diagnostics job)
    (push (make-message :call-id (search-job-call-id job) :claim :counterexample
                        :evidence (list :row (row-key (first (search-job-rows job)))
                                        :inputs (copy-tree (row-known (first (search-job-rows job))))
                                        :expression (search-job-expression job)
                                        :phase (search-job-phase job)
                                        :status (evaluation-status (search-job-evaluation job))
                                        :value (search-job-predicted job)
                                        :error (evaluation-error (search-job-evaluation job))))
          (search-job-messages job)))
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

(defun admit-search-candidate (job type)
  "Send a candidate of the target type to its row checks, by way of the rewrite filter when the job
has laws, and drop any other."
  (cond ((not (equal type (row-job-target job))) :enumerate)
        (t (setf (search-job-resolved-rows job) 0
                 (search-job-run-work job) 0
                 (search-job-values job) nil)
           (if (search-job-library job) :rewrite-start :row))))

(defun consume-search-outcome (job state)
  "Check a row's value against its requirement, skip a row the candidate leaves unresolved, and
reject the candidate on an error or once it exhausts the row budget."
  (let ((row-limit (search-job-row-budget job)))
    (ecase (evaluation-status state)
      (:error (reject-candidate job))
      (:unresolved
       (incf (search-job-run-work job) (evaluation-work state))
       (next-row job))
      (:value
       (incf (search-job-run-work job) (evaluation-work state))
       (setf (search-job-predicted job) (evaluation-value state)
             (search-job-phase job) :requirement))
      (:unknown
       (when (and row-limit (>= (evaluation-work state) row-limit))
         (reject-candidate job))))))

(defun finish-search-candidate (job)
  "Accept a candidate that resolved enough rows; incident hard edges were already checked row by row."
  (if (< (search-job-resolved-rows job) (frame-min-resolved-rows (search-job-frame job)))
      (reject-candidate job)
      (accept-candidate job)))

(defun violated-edge (job)
  "The first hard edge of the frame that the candidate's row values contradict, or nil. An
edge to a row the candidate left unresolved is not judged."
  (find-if (lambda (edge)
             (destructuring-bind (kind left right) edge
               (let ((a (assoc left (search-job-values job) :test #'equal))
                     (b (assoc right (search-job-values job) :test #'equal)))
                 (and a b (eq (eq kind :distinct) (equal (cdr a) (cdr b)))))))
           (search-job-hard-edges job)))

(defun settle-row-edges (job)
  "Advance past a row's newly settled hard edges, rejecting immediately when one is violated."
  (let ((violated (violated-edge job)))
    (cond ((null violated) (next-row job))
          (t (when (search-job-diagnostics job)
               (push (make-message :call-id (search-job-call-id job) :claim :counterexample
                                   :evidence (list :edge violated
                                                   :expression (search-job-expression job)
                                                   :phase :edges))
                     (search-job-messages job)))
             (incf (search-job-rejected job))
             (setf (search-job-phase job) :enumerate)))))

(defun rewrite-filter-step (job budget)
  "Advance the filter that precedes row checks when the job has rewrite laws: pay for the library
once, normalise each admitted candidate, and reject it unevaluated when a candidate with the same
normal form was already refuted by a row."
  (let ((ledger (search-job-ledger job)))
    (ecase (search-job-phase job)
      (:rule-setup
       (pay-debt (search-job-debt job) budget ledger :rule-setup)
       (when (zerop (search-job-debt job)) (setf (search-job-phase job) :enumerate)))
      (:rewrite-start
       (charge ledger :scheduling)
       (setf (search-job-rewriting job)
             (start-rewriting (search-job-expression job) (language-inputs (search-job-language job))
                              (search-job-library job))
             (search-job-phase job) :rewrite))
      (:rewrite
       (let ((state (advance-rewriting (search-job-rewriting job) budget ledger)))
         (when (eq :complete (rewriting-status state))
           (setf (search-job-normal-form job) (rewriting-value state)
                 (search-job-debt job) (syntax-work (rewriting-value state))
                 (search-job-phase job) :reuse))))
      (:reuse
       (pay-debt (search-job-debt job) budget ledger :equality-cache)
       (when (zerop (search-job-debt job))
         (if (gethash (search-job-normal-form job) (search-job-rejection-cache job))
             (progn (incf (search-job-reused-rejections job)) (reject-candidate job))
             (setf (search-job-phase job) :row)))))))

(defun search-step (job &optional (budget 1))
  "Advance one search phase using at most BUDGET tariff units."
  (assert (and (integerp budget) (plusp budget)))
  (let ((ledger (search-job-ledger job))
        (row (first (search-job-rows job)))
        (row-limit (search-job-row-budget job)))
    (case (search-job-phase job)
      (:proposal-setup
       (pay-debt (search-job-debt job) budget ledger :proposal-setup)
       (when (zerop (search-job-debt job)) (enter-rule-setup job)))
      ((:rule-setup :rewrite-start :rewrite :reuse) (rewrite-filter-step job budget))
      (:edges
       (pay-debt (search-job-debt job) budget ledger :checking)
       (when (zerop (search-job-debt job)) (settle-row-edges job)))
      (:requirement
       (charge ledger :scheduling)
       (setf (search-job-evaluation job)
             (start-evaluation (row-requirement row) (list (cons 0 (row-job-target job)))
                               (list (search-job-predicted job)))
             (search-job-phase job) :check))
      (:check
       (let ((state (advance-accounted-evaluation (search-job-evaluation job) budget ledger
                                                  :checking :validation)))
         (case (evaluation-status state)
           (:error (reject-candidate job))
           (:unresolved (next-row job))
           (:value
            (cond ((eq t (evaluation-value state))
                   (when (constrained-row-p row) (incf (search-job-resolved-rows job)))
                   (if (search-job-hard-edges job)
                       (let* ((key (row-key row))
                              (incident
                                (count-if (lambda (edge)
                                            (or (and (equal key (second edge))
                                                     (assoc (third edge) (search-job-values job)
                                                            :test #'equal))
                                                (and (equal key (third edge))
                                                     (assoc (second edge) (search-job-values job)
                                                            :test #'equal))))
                                          (search-job-hard-edges job))))
                         (push (cons key (search-job-predicted job)) (search-job-values job))
                         (if (plusp incident)
                             (setf (search-job-debt job) incident
                                   (search-job-phase job) :edges)
                             (next-row job)))
                       (next-row job)))
                  (t (reject-candidate job t)))))))
      (t
       ;; A row evaluation stops at its budget, so an overrun is detected at the same work however
       ;; the caller slices its steps.
       (when (and row-limit (eq :evaluate (search-job-phase job)))
         (setf budget (min budget (max 1 (- row-limit (evaluation-work (search-job-evaluation job)))))))
       (row-job-step job budget #'admit-search-candidate #'consume-search-outcome
                     #'finish-search-candidate)))))

(defun search-bound-complete-p (job bound)
  (row-job-bound-complete-p job bound))

(defun resume-search (job description-limit work-limit &key quantum)
  "Absolute cumulative work limit and total packet-bit bound."
  (resume-row-job job #'search-step description-limit work-limit quantum
                  :language-version (language-version (search-job-language job))))

;;; Empirical Observations & Equivalence Buckets
(defstruct (observation-scope (:constructor %make-observation-scope))
  id frame language pairs anchors
  (equality :typed-value) (evidence :replayed-observations) (simulator-version +simulator-version+)
  (encoding-version +encoding-version+) (tariff-version +tariff-version+))

(defun make-observation-scope (frame language &key (id (incf *next-call-id*))
                                                   (pairs (frame-pairs frame))
                                                   (anchors (frame-anchors frame)))
  "Freeze the observed inputs and language. PAIRS and ANCHORS refer to row keys."
  (assert (frame-rows frame) () "An empirical scope needs observations")
  (assert (equal (schema-inputs (frame-schema frame)) (language-inputs language)))
  (assert (or (null anchors) (>= (length anchors) 2)))
  (assert (= (length anchors) (length (remove-duplicates anchors :test #'equal))))
  (let* ((owned (snapshot-frame frame))  ; the scope's private frame, linked by PAIRS and ANCHORS
         (rows (frame-rows owned)))
    (setf (frame-pairs owned) (copy-tree pairs)
          (frame-anchors owned) (copy-tree anchors))
    (labels ((index (key)
               (or (position key rows :key #'row-key :test #'equal)
                   (error "Unknown observation key ~S" key))))
      (dolist (pair pairs)
        (assert (= (length pair) 2))
        (assert (not (equal (first pair) (second pair)))))
      (dolist (key anchors)
        (index key)
        (when pairs
          (assert (some (lambda (pair)
                          (or (equal key (first pair))
                              (equal key (second pair))))
                        pairs))))
      (%make-observation-scope
       :id id :frame owned :language (snapshot-language language)
       :pairs (mapcar (lambda (pair) (mapcar #'index pair)) pairs)
       :anchors (mapcar #'index anchors)))))

(defstruct observation-outcome status value error (work 0))

(defstruct observed-expression scope expression type (status :unknown)
  values outcomes (run-work 0) error failed-key)

(defstruct observation-bucket scope type values members invariant-p informative-p counterexample
  (pair-bits 0) (anchor-bits 0) (residual-bits 0))

(defun relational-linkage-residual (frame outcomes &key row-residuals (type (schema-target (frame-schema frame)))
                                                       decoders ledger)
  "Price relational obligations from (frame-pairs frame) and (frame-anchors frame) in bits
over OUTCOMES (either a list of `observation-outcome` structs or a list of raw values)
after applying any unary ROW-RESIDUALS ((row-key . witness) ...). A pair's drift is priced
by `priced-correction` under the frame's metric, when TYPE is its target type, and the
metric DECODERS, whose programs are charged to LEDGER.
Returns (VALUES entries total-bits pair-bits anchor-bits)."
  (let ((pairs (frame-pairs frame))
        (anchors (frame-anchors frame)))
    (when (and (null pairs) (null anchors))
      (return-from relational-linkage-residual (values nil 0 0 0)))
    (let* ((rows (frame-rows frame))
           (key-table (make-hash-table :test #'equal))
           (charged-keys (make-hash-table :test #'equal))
           (entries nil)
           (pair-bits 0)
           (anchor-bits 0))
      (loop for row in rows
            for item in outcomes
            for row-idx from 0
            for key = (row-key row)
            for override = (assoc key row-residuals :test #'equal)
            do (multiple-value-bind (valid-p val)
                   (cond
                     (override
                      (if (eq :unknown (cdr override))
                          (values nil nil)
                          (values t (cdr override))))
                     ((observation-outcome-p item)
                      (values (eq :value (observation-outcome-status item))
                              (observation-outcome-value item)))
                     (t (values t item)))
                 (setf (gethash key key-table)
                       (list row-idx (not (null override)) valid-p val))))
      ;; 1. Intra-fiber / transition pair corrections
      (loop for pair in pairs
            for pair-idx from 0
            for info-a = (gethash (first pair) key-table)
            for info-b = (gethash (second pair) key-table)
            when (and info-a info-b)
            do (destructuring-bind (idx-a corr-a valid-a val-a) info-a
                 (declare (ignore idx-a corr-a))
                 (destructuring-bind (idx-b corr-b valid-b val-b) info-b
                   (declare (ignore idx-b corr-b))
                   (unless (and valid-a valid-b (equal val-a val-b))
                     (multiple-value-bind (packet step-bits)
                         (cond
                           ((and valid-a valid-b)
                            (priced-correction val-a val-b type
                                               :metric (and (equal type (schema-target (frame-schema frame)))
                                                            (frame-metric frame))
                                               :decoders decoders :ledger ledger))
                           (valid-a (values :error (value-bit-size val-a type)))
                           (valid-b (values :error (value-bit-size val-b type)))
                           (t (values :error (1+ (type-bit-size type)))))
                       (setf (gethash (second pair) charged-keys) t)
                       (unless valid-a
                         (setf (gethash (first pair) charged-keys) t))
                       (push (cons (list :pair (first pair) (second pair)) packet) entries)
                       (incf pair-bits (+ (positive-bit-size (1+ pair-idx)) step-bits)))))))
      ;; 2. Cross-fiber / anchor separation (anti-collapse) corrections
      (when anchors
        (let ((seen-anchor-values nil)
              (min-step (minimum-disambiguation-bit-size type)))
          (dolist (anchor-key anchors)
            (let ((info (gethash anchor-key key-table)))
              (when info
                (destructuring-bind (idx corr-p valid-p val) info
                  (declare (ignore idx corr-p))
                  (if (and valid-p (not (member val seen-anchor-values :test #'equal)))
                      (push val seen-anchor-values)
                      (dolist (member-key (pair-connected-component anchor-key pairs))
                        (let ((m-info (gethash member-key key-table)))
                          (when (and m-info (not (second m-info))
                                     (not (gethash member-key charged-keys)))
                            (setf (gethash member-key charged-keys) t)
                            (push (cons (list :anchor member-key) :disambiguate) entries)
                            (incf anchor-bits (+ (positive-bit-size (1+ (first m-info)))
                                                 min-step))))))))))))
      (values (nreverse entries) (+ pair-bits anchor-bits) pair-bits anchor-bits))))

(defun observed-agreement-p (left right)
  "Agreement only between total evaluations in the exact same observation scope."
  (and left right
       (eq (observed-expression-scope left) (observed-expression-scope right))
       (eq (observed-expression-status left) :complete)
       (eq (observed-expression-status right) :complete)
       (equal (observed-expression-type left) (observed-expression-type right))
       (equal (observed-expression-values left) (observed-expression-values right))))

(defstruct (observation-job (:include row-job) (:constructor %make-observation-job))
  scope current (outputs nil) retain-outcomes-p (outcomes nil) records buckets
  (staged-bucket nil)
  (record-index (make-hash-table :test #'equal))
  (bucket-index (make-hash-table :test #'equal)))

(defun start-observation-search (scope &key (expressions nil supplied-p) retain-outcomes)
  (let* ((language (observation-scope-language scope))
         (frame (observation-scope-frame scope))
         (queue (proposal-queue expressions language))
         ;; Setup work counts the proposals queued from the first one given onward.
         (counted (member (first (remove-duplicates expressions :test #'equal)) queue :test #'equal)))
    (%make-observation-job
     :call-id (observation-scope-id scope) :scope scope :frame frame :language language
     :retain-outcomes-p (not (null retain-outcomes))
     :mode (if supplied-p :replay :enumeration)
     :enumerator (unless supplied-p (make-enumerator language))
     :queue queue
     :completed-bound (if supplied-p 0 (language-header-size language (schema-target (frame-schema frame))))
     :phase :setup
     :debt (+ (length counted) (length (observation-scope-pairs scope))
              (length (observation-scope-anchors scope))
              (loop for row in (frame-rows frame)
                    sum (1+ (loop for value in (row-known row)
                                  for spec in (language-inputs language)
                                  sum (value-work value (cdr spec)))))))))

(defun find-observation (job expression)
  (gethash expression (observation-job-record-index job)))

(defun observation-invariants (job)
  (remove-if-not #'observation-bucket-informative-p (reverse (observation-job-buckets job))))

(defun classify-observation-bucket (bucket &optional ledger)
  (let* ((scope (observation-bucket-scope bucket))
         (values (coerce (observation-bucket-values bucket) 'vector))
         (pairs (observation-scope-pairs scope))
         (anchors (observation-scope-anchors scope))
         (failed (find-if (lambda (pair)
                            (not (equal (aref values (first pair)) (aref values (second pair))))) pairs)))
    (setf (observation-bucket-invariant-p bucket) (and pairs (null failed))
          (observation-bucket-informative-p bucket)
          (and pairs (null failed) anchors
               (not (every (lambda (index) (equal (aref values index) (aref values (first anchors))))
                           (rest anchors)))))
    (when failed
      (let ((rows (frame-rows (observation-scope-frame scope))))
        (setf (observation-bucket-counterexample bucket)
              (list :before-key (row-key (nth (first failed) rows))
                    :after-key (row-key (nth (second failed) rows))
                    :before-value (aref values (first failed))
                    :after-value (aref values (second failed))))))
    (multiple-value-bind (entries total-bits pair-bits anchor-bits)
        (relational-linkage-residual (observation-scope-frame scope)
                                     (observation-bucket-values bucket)
                                     :type (observation-bucket-type bucket)
                                     :decoders (metric-decoders (observation-bucket-type bucket))
                                     :ledger ledger)
      (declare (ignore entries))
      (setf (observation-bucket-pair-bits bucket) pair-bits
            (observation-bucket-anchor-bits bucket) anchor-bits
            (observation-bucket-residual-bits bucket) total-bits)))
  bucket)

(defun finish-observation (job)
  (let* ((record (observation-job-current job))
         (scope (observation-job-scope job))
         (key (list (observed-expression-type record) (observed-expression-values record))))
    (push record (observation-job-records job))
    (setf (gethash (observed-expression-expression record) (observation-job-record-index job)) record)
    (when (eq (observed-expression-status record) :complete)
      (let ((bucket (or (gethash key (observation-job-bucket-index job))
                        (let ((staged (shiftf (observation-job-staged-bucket job) nil)))
                          (when staged
                            (setf (gethash key (observation-job-bucket-index job)) staged)
                            (push staged (observation-job-buckets job)))
                          staged))))
        (when bucket
          (push record (observation-bucket-members bucket))
          (when (observation-bucket-informative-p bucket)
            (push (make-message :call-id (observation-scope-id scope) :claim :observed-invariant
                                :evidence record) (observation-job-messages job))))))
    (setf (observation-job-staged-bucket job) nil
          (observation-job-phase job) :enumerate)))

(defun prepare-observation-index (job)
  (let* ((record (observation-job-current job)) (scope (observation-job-scope job))
         (values (nreverse (observation-job-outputs job)))
         (type (observed-expression-type record))
         (bucket-ledger (make-ledger)))
    (setf (observed-expression-values record) values
          (observed-expression-outcomes record) (nreverse (observation-job-outcomes job))
          (observation-job-outputs job) nil
          (observation-job-outcomes job) nil
          (observation-job-staged-bucket job)
          (when (and (eq (observed-expression-status record) :complete)
                     (null (gethash (list type values) (observation-job-bucket-index job))))
            (classify-observation-bucket
             (make-observation-bucket :scope scope :type type :values values)
             bucket-ledger))
          (observation-job-phase job) :index
          (observation-job-debt job)
          (+ 1 (ledger-total bucket-ledger)
             (loop for value in values sum (value-work value type))
             (* 2 (length (observation-scope-pairs scope)))
             (length (observation-scope-anchors scope))))))

(defun admit-observation (job type)
  "Open a record for the candidate. Replayed expressions are observed whatever their type,
enumerated ones only when they have the target type."
  (setf (observation-job-current job)
        (make-observed-expression :scope (observation-job-scope job)
                                  :expression (observation-job-expression job) :type type))
  (if (or (eq :replay (observation-job-mode job)) (equal type (row-job-target job)))
      :row :enumerate))

(defun note-observation-failure (job state)
  "Keep the status, error and row key of the first row evaluation that yielded no value."
  (let ((record (observation-job-current job)))
    (unless (member (observed-expression-status record) '(:error :unresolved))
      (setf (observed-expression-status record) (evaluation-status state)
            (observed-expression-error record) (evaluation-error state)
            (observed-expression-failed-key record) (row-key (first (observation-job-rows job)))))))

(defun consume-observation-outcome (job state)
  "Once a row evaluation settles, stage its outcome for retention, or else collect its value and
stop observing the candidate at its first failure."
  (let ((record (observation-job-current job))
        (status (evaluation-status state)))
    (unless (eq :unknown status)
      (incf (observed-expression-run-work record) (evaluation-work state))
      (cond ((observation-job-retain-outcomes-p job)
             (setf (observation-job-phase job) :outcome
                   (observation-job-debt job)
                   (+ 1 (if (eq :value status)
                            (value-work (evaluation-value state) (observed-expression-type record))
                            0))))
            ((eq :value status)
             (push (evaluation-value state) (observation-job-outputs job))
             (next-row job))
            (t (note-observation-failure job state)
               (prepare-observation-index job))))))

(defun finish-observation-rows (job)
  (let ((record (observation-job-current job)))
    (unless (eq :error (observed-expression-status record))
      (setf (observed-expression-status record) :complete))
    (prepare-observation-index job)))

(defun observation-step (job budget)
  (assert (and (integerp budget) (plusp budget)))
  (let ((ledger (observation-job-ledger job)))
    (case (observation-job-phase job)
      (:setup
       (pay-debt (observation-job-debt job) budget ledger :setup)
       (when (zerop (observation-job-debt job)) (setf (observation-job-phase job) :enumerate)))
      (:outcome
       (pay-debt (observation-job-debt job) budget ledger :outcomes)
       (when (zerop (observation-job-debt job))
         (let ((state (observation-job-evaluation job)))
           (push (make-observation-outcome :status (evaluation-status state)
                                           :value (evaluation-value state) :error (evaluation-error state)
                                           :work (evaluation-work state))
                 (observation-job-outcomes job))
           (if (eq :value (evaluation-status state))
               (push (evaluation-value state) (observation-job-outputs job))
               (note-observation-failure job state))
           (next-row job))))
      (:index
       (pay-debt (observation-job-debt job) budget ledger :indexing)
       (when (zerop (observation-job-debt job)) (finish-observation job)))
      (t (row-job-step job budget #'admit-observation #'consume-observation-outcome
                       #'finish-observation-rows)))))

(defun observation-bound-complete-p (job bound)
  (row-job-bound-complete-p job bound))

(defun resume-observation-search (job description-limit work-limit &key quantum)
  (resume-row-job job #'observation-step description-limit work-limit quantum
                  :scope (observation-job-scope job)))
