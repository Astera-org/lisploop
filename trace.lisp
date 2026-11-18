(in-package #:lisploop)

;;; The search trace as relations. A job's messages are its trace. A relation reads rows of
;;; object-language values off them, and a frame built from such rows is an ordinary frame:
;;; what the kernel does to a task it can then do to a record of its own search, and a rule
;;; about the search is an expression the VM evaluates on those rows. Reading a trace charges
;;; no ledger of the job it describes.

(defstruct trace-relation
  name
  columns ; ((name . type) ...) of object-language types; the first is always (:job . :int)
  claim   ; the claim of the messages the relation reads
  reader) ; a function of one message to the rows it contributes, without their :job value

(defvar *trace-relations* nil
  "The defined trace relations, latest first.")

(defmacro define-trace-relation (name claim columns (message evidence) &body body)
  "Define the trace relation NAME over the messages whose claim is CLAIM. COLUMNS are its
columns after :job, ((name . type) ...). BODY, with MESSAGE and its EVIDENCE bound, returns
the rows that message contributes, each a list of values in the order of COLUMNS."
  `(progn
     (setf *trace-relations* (remove ,name *trace-relations* :key #'trace-relation-name))
     (push (make-trace-relation
            :name ,name :claim ,claim :columns '((:job . :int) ,@columns)
            :reader (lambda (,message)
                      (let ((,evidence (message-evidence ,message)))
                        (declare (ignorable ,evidence))
                        ,@body)))
           *trace-relations*)
     ,name))

(defun find-trace-relation (name)
  (or (find name *trace-relations* :key #'trace-relation-name)
      (error "No trace relation is named ~S." name)))

(defun trace-columns (relation)
  "The columns of the trace relation named RELATION, ((name . type) ...)."
  (trace-relation-columns (find-trace-relation relation)))

(defun trace-rows (relation jobs-or-job)
  "The rows of the trace relation named RELATION in JOBS-OR-JOB, in the order the jobs are
given and their messages were sent. A row lists its values in the order of `trace-columns`;
its first is the position of its job, which keeps the node numbers of two jobs apart."
  (let* ((relation (find-trace-relation relation))
         (columns (rest (trace-relation-columns relation))))
    (loop for job in (if (listp jobs-or-job) jobs-or-job (list jobs-or-job))
          for index from 0
          append (loop for message in (reverse (synthesis-job-messages job))
                       when (eq (trace-relation-claim relation) (message-claim message))
                         append (loop for row in (funcall (trace-relation-reader relation) message)
                                      do (assert (and (= (length row) (length columns))
                                                      (every #'value-p row (mapcar #'cdr columns)))
                                                 () "~S is not a row of ~S" row columns)
                                      collect (cons index row))))))

(defun trace-frame (columns rows target &key inputs)
  "The frame that asks for the column TARGET of ROWS, which list their values in the order of
COLUMNS, ((name . type) ...), as a function of the columns named in INPUTS; left out, those
are all the others. Rows that agree on the inputs and differ on the target are kept as they
are, so `frame-conflict-p` says whether the target is a function of the inputs at all."
  (let* ((names (mapcar #'car columns))
         (inputs (or inputs (remove target names)))
         (places (loop for name in inputs
                       collect (or (position name names)
                                   (error "~S is not among the columns ~S." name names))))
         (target-place (or (position target names)
                           (error "~S is not among the columns ~S." target names)))
         (target-type (cdr (nth target-place columns))))
    (make-frame (make-schema :domain :int
                             :inputs (loop for place in places for id from 0
                                           collect (cons id (cdr (nth place columns))))
                             :target target-type)
                (loop for row in rows for key from 0
                      collect (make-row :key key
                                        :known (loop for place in places collect (nth place row))
                                        :requirement (singleton-requirement
                                                      target-type (nth target-place row)))))))

;;; The relations read today. A column has an object-language type, so a fact with no value
;;; of that type is given one here: a node without a parent has parent -1. A Stage A search
;;; is named by its node and the job work at which its result was published, since a node
;;; can run one when it is prepared and another when it is expanded.

(define-trace-relation :node :prepared
    ((:node . :int) (:parent . :int) (:depth . :int) (:inputs . :int) (:rows . :int)
     (:conflict-p . :bool) (:at . :int))
    (message evidence)
  (list (list (message-call-id message)
              (or (getf evidence :parent-id) -1)
              (getf evidence :depth)
              (or (getf evidence :inputs) 0)
              (or (getf evidence :constrained-rows) 0)
              (getf evidence :conflict-p)
              (getf evidence :work))))

(define-trace-relation :stage-a :stage-a
    ((:node . :int) (:at . :int) (:work-limit . :int) (:spent . :int))
    (message evidence)
  (list (list (message-call-id message) (getf evidence :work)
              (getf evidence :work-limit) (getf evidence :spent))))

(define-trace-relation :stage-a-bucket :stage-a
    ((:node . :int) (:at . :int) (:work . :int))
    (message evidence)
  (loop for (kind work) in (getf evidence :trace)
        when (eq kind :bucket)
          collect (list (message-call-id message) (getf evidence :work) work)))

(define-trace-relation :stage-a-model :stage-a
    ((:node . :int) (:at . :int) (:work . :int) (:program-bits . :int) (:residual-bits . :int)
     (:run-work . :int) (:exact-p . :bool))
    (message evidence)
  (loop for (kind . fields) in (getf evidence :trace)
        when (eq kind :model)
          collect (list* (message-call-id message) (getf evidence :work) fields)))

(define-trace-relation :verified :candidate
    ((:node . :int) (:at . :int) (:size . :int) (:run-work . :int))
    (message evidence)
  ;; A job's closing message can also claim :candidate; it names no candidate of a node.
  (let ((candidate (getf evidence :candidate)))
    (when (and candidate (eq :original-root (getf evidence :scope)))
      (list (list (message-call-id message) (getf evidence :work)
                  (candidate-size candidate) (candidate-run-work candidate))))))
