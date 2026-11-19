(in-package #:lisploop)

;;; A job's messages as rows. A job sends a message for each thing it publishes
;;; (`synthesis-message`). A reader turns the messages of one claim into rows of
;;; object-language values, and a frame built from such rows is an ordinary frame: what the
;;; kernel does to a task it can then do to a record of its own search, and a rule about the
;;; search is an expression the VM evaluates on those rows. Reading messages charges no
;;; ledger of the job that sent them. (The lane choices in `synthesis-job-trace` are not
;;; messages and are not read here.)

(defstruct message-reader
  name
  columns ; ((name . type) ...) of object-language types; the first is always (:job . :int)
  claim   ; the claim of the messages it reads
  rows)   ; a function of one message to the rows it contributes, without their :job value

(defvar *message-readers* nil
  "The defined message readers, latest first.")

(defmacro define-message-reader (name claim columns (message evidence) &body body)
  "Define the reader NAME of the messages whose claim is CLAIM. COLUMNS are the columns of
its rows after :job, ((name . type) ...). BODY, with MESSAGE and its EVIDENCE bound, returns
the rows that message contributes, each a list of values in the order of COLUMNS."
  `(progn
     (setf *message-readers* (remove ,name *message-readers* :key #'message-reader-name))
     (push (make-message-reader
            :name ,name :claim ,claim :columns '((:job . :int) ,@columns)
            :rows (lambda (,message)
                    (let ((,evidence (message-evidence ,message)))
                      (declare (ignorable ,evidence))
                      ,@body)))
           *message-readers*)
     ,name))

(defun find-message-reader (name)
  (or (find name *message-readers* :key #'message-reader-name)
      (error "No message reader is named ~S." name)))

(defun message-columns (reader)
  "The columns of the rows that the message reader named READER gives, ((name . type) ...)."
  (message-reader-columns (find-message-reader reader)))

(defun message-rows (reader jobs-or-job)
  "The rows that the message reader named READER gives for JOBS-OR-JOB, in the order the jobs
are given and their messages were sent. A row lists its values in the order of
`message-columns`; its first is the position of its job, which keeps the node numbers of two
jobs apart."
  (let* ((reader (find-message-reader reader))
         (columns (rest (message-reader-columns reader))))
    (loop for job in (if (listp jobs-or-job) jobs-or-job (list jobs-or-job))
          for index from 0
          append (loop for message in (reverse (synthesis-job-messages job))
                       when (eq (message-reader-claim reader) (message-claim message))
                         append (loop for row in (funcall (message-reader-rows reader) message)
                                      do (assert (and (= (length row) (length columns))
                                                      (every #'value-p row (mapcar #'cdr columns)))
                                                 () "~S is not a row of ~S" row columns)
                                      collect (cons index row))))))

(defun message-frame (columns rows target &key inputs)
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

;;; The readers defined today. A column has an object-language type, so a fact with no value
;;; of that type is given one here: a node without a parent has parent -1. A Stage A search
;;; is named by its node and the job work at which its result was published, since a node
;;; can run one when it is prepared and another when it is expanded.

(define-message-reader :node :prepared
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

(define-message-reader :stage-a :stage-a
    ((:node . :int) (:at . :int) (:work-limit . :int) (:spent . :int))
    (message evidence)
  (list (list (message-call-id message) (getf evidence :work)
              (getf evidence :work-limit) (getf evidence :spent))))

(define-message-reader :stage-a-bucket :stage-a
    ((:node . :int) (:at . :int) (:work . :int))
    (message evidence)
  (loop for (kind work) in (getf evidence :history)
        when (eq kind :bucket)
          collect (list (message-call-id message) (getf evidence :work) work)))

(define-message-reader :stage-a-model :stage-a
    ((:node . :int) (:at . :int) (:work . :int) (:program-bits . :int) (:residual-bits . :int)
     (:run-work . :int) (:exact-p . :bool))
    (message evidence)
  (loop for (kind . fields) in (getf evidence :history)
        when (eq kind :model)
          collect (list* (message-call-id message) (getf evidence :work) fields)))

(define-message-reader :verified :candidate
    ((:node . :int) (:at . :int) (:size . :int) (:run-work . :int))
    (message evidence)
  ;; A job's closing message can also claim :candidate; it names no candidate of a node.
  (let ((candidate (getf evidence :candidate)))
    (when (and candidate (eq :original-root (getf evidence :scope)))
      (list (list (message-call-id message) (getf evidence :work)
                  (candidate-size candidate) (candidate-run-work candidate))))))
