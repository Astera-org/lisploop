;;; The yield gate of plan9.md section 4.2, scored against recorded searches.
;;;
;;; plan9-audit.md Appendix C made its table by redefining `condense-heuristic` to run in
;;; quanta and log. Here the searches run untouched. The table is read off their trace
;;; relations (trace.lisp); a gate is an object-language expression that the VM evaluates on
;;; the rows; the kernel's conflict check says whether what a gate reads can tell a needed
;;; search from a spent one; and observation search proposes the gates that these rows allow.
;;; A gate that stops a needed search on a recorded row is refuted without being run. One that
;;; passes is a suggestion: the rows of two searches are sampled evidence, and they say
;;; nothing of a gate that would run longer than the recorded searches did.
;;;
;;;   sbcl --dynamic-space-size 4096 --script experiments/yield-gate.lisp [QUANTUM]
(load (merge-pathnames "../load.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)
(clear-knowledge-library)

(defparameter *quantum* (let ((arg (second sb-ext:*posix-argv*)))
                          (if arg (parse-integer arg) 2000)))
(defparameter *tup* (tuple-type :int :int))
(defparameter *seq-int* (sequence-type :int))
(defparameter *seq-tup* (sequence-type *tup*))
(defparameter *step-tup* (code-type (list (cons 0 *tup*) (cons 1 :int)) *tup*))

(define-function :scan-tup (list (cons 0 *seq-int*) (cons 1 *tup*) (cons 2 *step-tup*)) *seq-tup*
  (lambda (self)
    (let* ((actions (var 0 *seq-int*)) (state (var 1 *tup*)) (step (var 2 *step-tup*))
           (next (term `(code-eval ,step ,state (at ,actions 0)))))
      (term `(if (= ,actions ()) () (cons ,next (,self (tail ,actions) ,next ,step))) *seq-tup*))))

(defun tuple-scan-job (rows bound operators)
  "The tuple scan probes of plan8.md Appendix A (2 and 3), run as experiments/probes.lisp runs them."
  (let* ((inputs (list (cons 0 *seq-int*) (cons 1 *tup*)))
         (frame (make-frame (make-schema :inputs inputs :target *seq-tup*)
                            (loop for (known wanted) in rows for key from 0
                                  collect (make-row :key key :known known
                                                    :requirement (singleton-requirement *seq-tup* wanted)))))
         (language (make-language :int inputs :operators operators :literals '(0 1)))
         (job (start-heuristic-synthesis frame language bound
                                         :library-proposals-p t :library-functions '(:scan-tup))))
    (resume-synthesis job 800000 :stop-on-first t)
    job))

(defparameter *jobs*
  (list (tuple-scan-job '((((1 2) (0 10)) ((1 11) (3 13))) (((-1 3) (5 2)) ((4 1) (7 4))))
                        160
                        (list (op :+ :int) (op :- :int) (op :tuple *tup*) (op :at *tup*) (op :scan-tup)))
        (tuple-scan-job '((((1 1) (0 2)) ((1 2) (2 3))) (((1 1) (0 3)) ((1 3) (2 3)))
                          (((-1 -1) (4 2)) ((3 2) (2 1))))
                        260
                        (list (op :+ :int) (op :- :int) (op := :int) (op :if :int)
                              (op :tuple *tup*) (op :at *tup*) (op :scan-tup)))))
(defparameter *job-names* '("Symmetric tuple scan" "Conditional tuple scan"))

;;; Queries over the trace relations.

(defun select (relation &rest column-values)
  "The rows of RELATION in *jobs* whose named columns have the given values."
  (let ((names (mapcar #'car (trace-columns relation))))
    (remove-if-not (lambda (row)
                     (loop for (name value) on column-values by #'cddr
                           always (equal value (nth (position name names) row))))
                   (trace-rows relation *jobs*))))

(defun field (relation row name)
  (nth (position name (mapcar #'car (trace-columns relation))) row))

(defun winning-path (job)
  "The nodes from the one whose candidate was verified first up to the root."
  (let ((verified (first (select :verified :job job))))
    (when verified
      (loop for node = (field :verified verified :node)
              then (field :node (first (select :node :job job :node node)) :parent)
            until (minusp node) collect node))))

(defun quantum-series (job node at spent)
  "For each quantum of the Stage A search of NODE published at AT: (best-score buckets exact-p)
at its end, with a best score of nil while there is no model."
  (let ((run-weight (synthesis-job-run-weight (nth job *jobs*)))
        (buckets (mapcar (lambda (row) (field :stage-a-bucket row :work))
                         (select :stage-a-bucket :job job :node node :at at)))
        (models (select :stage-a-model :job job :node node :at at)))
    (flet ((score (row) (+ (field :stage-a-model row :program-bits)
                           (field :stage-a-model row :residual-bits)
                           (* run-weight (field :stage-a-model row :run-work))))
           (bits (row) (field :stage-a-model row :program-bits)))
      (loop for q from 1 to (max 1 (ceiling spent *quantum*))
            for end = (* q *quantum*)
            collect (let ((best (best-by (remove-if (lambda (row) (> (field :stage-a-model row :work) end))
                                                    models)
                                         #'score #'bits)))
                      (list (and best (score best))
                            (count-if (lambda (work) (<= work end)) buckets)
                            (and best (field :stage-a-model best :exact-p))))))))

;;; One row for each quantum of each Stage A search: what a gate may read at the end of the
;;; quantum, and whether the search was still needed then. NEEDED-P is true when the node is
;;; on the winning path and its final model had not been found yet, which understates the
;;; need: it leaves out what later buckets gave to guards and to the children's proposals.

(defparameter *quantum-columns*
  '((:job . :int) (:node . :int) (:at . :int) (:quantum . :int) (:inputs . :int) (:depth . :int)
    (:has-model-p . :bool) (:improved-p . :bool) (:added-p . :bool) (:buckets . :int)
    (:needed-p . :bool)))

(defun final-model-quantum (series)
  "The quantum in which SERIES reaches its last best score, or nil when it has no model."
  (let ((final (first (first (last series)))))
    (and final (1+ (position final series :key #'first)))))

(defun quantum-rows ()
  (loop for stage-a in (trace-rows :stage-a *jobs*)
        append (destructuring-bind (job node at limit spent) stage-a
                 (declare (ignore limit))
                 (let* ((series (quantum-series job node at spent))
                        (final (final-model-quantum series))
                        (on-path-p (member node (winning-path job)))
                        (node-row (first (select :node :job job :node node))))
                   (loop for (score buckets) in series
                         for (before-score before-buckets) in (cons '(nil 0) series)
                         for q from 1
                         collect (list job node at q
                                       (field :node node-row :inputs) (field :node node-row :depth)
                                       (not (null score))
                                       (not (equal score before-score))
                                       (> buckets before-buckets)
                                       buckets
                                       (and on-path-p final (< q final) t)))))))

(defun stop-quantum (rule rows inputs)
  "The first quantum of ROWS, the quantum rows of one search, at which RULE, an expression
over INPUTS that is true where the search should go on, is false; nil when it never is."
  (let ((names (mapcar #'car *quantum-columns*)))
    (loop for row in rows
          for known = (loop for name in inputs collect (nth (position name names) row))
          unless (eval-expr-value rule (loop for name in inputs for id from 0
                                             collect (cons id (cdr (assoc name *quantum-columns*))))
                                  known)
            return (nth (position :quantum names) row))))

;;; The table of Appendix C.

(defun proposal-label (job node)
  (let* ((message (find-if (lambda (m) (and (eq :prepared (message-claim m)) (eql node (message-call-id m))))
                           (synthesis-job-messages (nth job *jobs*))))
         (name (getf (message-evidence message) :proposal)))
    (cond ((null name) "root")
          ((consp name) (string-downcase (symbol-name (first name))))
          (t (string-downcase (princ-to-string name))))))

(defparameter *gate* (term `(if ,(var 0 :bool) t ,(var 1 :bool)) :bool)
  "The gate of plan9.md section 4.2 over (:improved-p :added-p): go on while a quantum
improves the best score or adds a bucket.")
(defparameter *score-gate* (var 0 :bool)
  "The same gate without the bucket condition, over (:improved-p).")

(defparameter *rows* (quantum-rows))

(defun search-rows (job node at)
  (remove-if-not (lambda (row) (equal (list job node at) (subseq row 0 3))) *rows*))

(format t "Stage A searches in quanta of ~D, read from the trace relations.~%" *quantum*)
(loop for job from 0 for name in *job-names*
      do (format t "~%~A (~:D work; winning path nodes ~{~D~^, ~})~%"
                 name (ledger-total (synthesis-job-ledger (nth job *jobs*))) (winning-path job))
         (format t "~4A ~5A ~22A ~6A ~4A ~7A ~11A ~9A ~10A ~A~%"
                 "Node" "At/k" "Proposal" "Inputs" "Path" "Limit" "Final model" "Gate" "Score-only" "Buckets per quantum")
         (dolist (stage-a (select :stage-a :job job))
           (destructuring-bind (job node at limit spent) stage-a
             (let* ((series (quantum-series job node at spent))
                    (rows (search-rows job node at))
                    (final (final-model-quantum series)))
               (format t "~4D ~5D ~22A ~6D ~4A ~7:D ~11A ~9A ~10A ~{~D~^ ~}~%"
                       node (floor at 1000) (proposal-label job node)
                       (field :node (first (select :node :job job :node node)) :inputs)
                       (if (member node (winning-path job)) "yes" "no")
                       limit
                       (if final (format nil "q~D~:[~;, exact~]" final (third (first (last series)))) "none")
                       (let ((q (stop-quantum *gate* rows '(:improved-p :added-p)))) (if q (format nil "q~D" q) "never"))
                       (let ((q (stop-quantum *score-gate* rows '(:improved-p)))) (if q (format nil "q~D" q) "never"))
                       (mapcar #'second series))))))

;;; The gate as a rule over recorded rows.

(defun judge (label rule inputs)
  "Report what RULE over INPUTS would have stopped: the needed searches it stops, which refute
it, and the work it would have saved on the others."
  (let ((refuted nil) (saved 0) (spent 0))
    (dolist (stage-a (trace-rows :stage-a *jobs*))
      (destructuring-bind (job node at limit used) stage-a
        (declare (ignore limit))
        (let* ((rows (search-rows job node at))
               (stop (stop-quantum rule rows inputs))
               (needed (find-if (lambda (row) (and stop (= stop (fourth row)) (first (last row)))) rows)))
          (incf spent used)
          (cond (needed (push (list (nth job *job-names*) node stop) refuted))
                (stop (incf saved (max 0 (- used (* stop *quantum*)))))))))
    (format t "~%~A~%  rule ~S over ~S~%" label (ast->sexp rule) inputs)
    (format t "  stops a needed search: ~:[never~;~:*~{~{~A node ~D at q~D~}~^; ~}~]~%" (reverse refuted))
    (format t "  work it stops elsewhere: ~:D of ~:D spent in Stage A~%" saved spent)))

(judge "Yield gate (plan9.md 4.2)" *gate* '(:improved-p :added-p))
(judge "Score-only gate" *score-gate* '(:improved-p))

;;; Is being needed a function of what the gate reads? The kernel's own conflict check says.
(dolist (inputs '((:improved-p :added-p) (:improved-p :added-p :has-model-p)
                  (:improved-p :added-p :has-model-p :inputs)
                  (:improved-p :added-p :has-model-p :inputs :quantum)))
  (let* ((frame (trace-frame *quantum-columns* *rows* :needed-p :inputs inputs))
         (conflict (frame-conflict-p frame)))
    (format t "~%needed-p as a function of ~S: ~:[no conflict~;conflict~]~%" inputs conflict)
    (when conflict
      (format t "  rows ~S agree on ~S and differ on needed-p~%"
              (mapcar (lambda (key) (subseq (nth key *rows*) 0 4)) (frame-conflict-keys conflict))
              (frame-conflict-known conflict)))))

;;; Work done twice: a node whose Stage A ran more than once.
(format t "~%Nodes that ran Stage A more than once:~%")
(loop for job from 0 for name in *job-names*
      do (dolist (node (remove-duplicates (mapcar (lambda (row) (field :stage-a row :node))
                                                  (select :stage-a :job job))))
           (let ((searches (select :stage-a :job job :node node)))
             (when (rest searches)
               (format t "  ~A node ~D: ~{~:D~^ then ~} work; models ~D, buckets ~D~%"
                       name node (mapcar (lambda (row) (field :stage-a row :spent)) searches)
                       (length (select :stage-a-model :job job :node node))
                       (length (select :stage-a-bucket :job job :node node)))))))

;;; Proposing a gate. Observation search enumerates the expressions over what a gate may read
;;; and groups them by what they say on every recorded quantum; each group of Boolean
;;; expressions is one way a gate could behave. A group is sound here when it goes on at every
;;; quantum at which a search was still needed, and is then ranked by the work it stops.

(defun propose-gates (inputs slack work)
  (let* ((frame (trace-frame *quantum-columns* *rows* :needed-p :inputs inputs))
         (language (make-language :int (schema-inputs (frame-schema frame))
                                  :operators (list (op :< :int) (op := :int) (op :+ :int) (op :* :int)
                                                   (op :if :bool))
                                  :literals '(0 1 2)))
         (job (start-observation-search (make-observation-scope frame language)))
         (message (resume-observation-search job (+ (language-header-size language :bool) slack) work))
         (needed (mapcar (lambda (row) (first (last row))) *rows*))
         (sound nil) (boolean 0))
    (dolist (bucket (observation-job-buckets job))
      (when (eq :bool (observation-bucket-type bucket))
        (incf boolean)
        (let ((values (observation-bucket-values bucket)))
          (when (every (lambda (value needed-p) (or value (not needed-p))) values needed)
            (let ((rule (observed-expression-expression (car (last (observation-bucket-members bucket)))))
                  (saved 0))
              (dolist (stage-a (trace-rows :stage-a *jobs*))
                (destructuring-bind (job node at limit used) stage-a
                  (declare (ignore limit))
                  (let ((stop (stop-quantum rule (search-rows job node at) inputs)))
                    (when stop (incf saved (max 0 (- used (* stop *quantum*))))))))
              (push (list saved (description-size rule (schema-inputs (frame-schema frame))) rule) sound))))))
    (format t "~%Gates over ~S: ~A at ~:D work; ~D Boolean behaviours, ~D of them sound on these rows.~%"
            inputs (message-claim message) (ledger-total (observation-job-ledger job)) boolean (length sound))
    (loop for (saved bits rule) in (sort sound (lambda (a b) (or (> (first a) (first b))
                                                                 (and (= (first a) (first b))
                                                                      (< (second a) (second b))))))
          repeat 6
          do (format t "  stops ~7:D work, ~3D bits: ~S~%" saved bits (ast->sexp rule)))))

(propose-gates '(:improved-p :added-p) 30 2000000)
(propose-gates '(:quantum :inputs :has-model-p :improved-p :added-p :buckets) 30 3000000)
