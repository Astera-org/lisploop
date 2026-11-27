;;;; Instrumented cold bootstrap (scratch copy only). argv: <tree-root> (v2 dir or root dir)
;;;; Evaluates build-batteries.lisp forms but wraps kernel entry points to report work.
(defvar *root* (pathname (concatenate 'string (car (last sb-ext:*posix-argv*)) "/")))
(load (merge-pathnames "load.lisp" *root*))
(load (merge-pathnames "bootstrap/recursion-schemas.lisp" *root*))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defvar *job-log* nil)
(defvar *grand* (make-ledger))
(defvar *schema-names* '(:lookahead-inductive :state-fold-inductive :state-scan-inductive
                         :countdown-inductive :counter-inductive))

(defun proposal-chain (node)
  (loop for cur = node then (synthesis-node-parent cur)
        while cur
        for p = (synthesis-node-proposal cur)
        when p collect (let ((n (decomposition-name p))) (if (consp n) (first n) n))))

;; Record every synthesis job at the moment resume-synthesis returns.
(sb-int:encapsulate
 'resume-synthesis 'audit
 (lambda (fn job work-limit &rest keys)
   (let ((before (ledger-total (synthesis-job-ledger job))))
     (prog1 (apply fn job work-limit keys)
       (let* ((win (job-winning-node job))
              (chain (and win (proposal-chain win)))
              (claims (make-hash-table)))
         (dolist (m (synthesis-job-messages job)) (incf (gethash (message-claim m) claims 0)))
         (push (list :self (synthesis-job-self-name job)
                     :limit work-limit
                     :work (- (ledger-total (synthesis-job-ledger job)) before)
                     :solved (not (null (synthesis-job-best job)))
                     :bits (and (synthesis-job-best job) (candidate-size (synthesis-job-best job)))
                     :nodes (length (synthesis-job-nodes job))
                     :messages (length (synthesis-job-messages job))
                     :claims (let (l) (maphash (lambda (k v) (push (cons k v) l)) claims) l)
                     :trace (length (synthesis-job-trace job))
                     :nogoods (length (synthesis-job-nogoods job))
                     :reused (synthesis-job-reused-subproblems job)
                     :win-chain chain
                     :schema-on-win (intersection chain *schema-names*)
                     :schema-nodes (count-if (lambda (n) (intersection (proposal-chain n) *schema-names*))
                                             (synthesis-job-nodes job))
                     :cats (copy-tree (ledger-counts (synthesis-job-ledger job))))
               *job-log*))))))

(sb-int:encapsulate
 'save-clean-battery 'audit
 (lambda (fn name ids source-library &rest keys &key ledger &allow-other-keys)
   (let ((kinds (make-hash-table)))
     (dolist (e (knowledge-library-entries source-library))
       (incf (gethash (knowledge-entry-kind e) kinds 0)))
     (format t "~&[audit] battery ~A: ledger-total=~D cats=~S~%        source-library kinds=~S saved-ids=~D~%"
             name (if ledger (ledger-total ledger) -1)
             (and ledger (sort (copy-tree (ledger-counts ledger)) #'> :key #'cdr))
             (let (l) (maphash (lambda (k v) (push (cons k v) l)) kinds) l)
             (length ids))
     (when ledger (incf (ledger-total *grand*) (ledger-total ledger))))
   (apply fn name ids source-library keys)))

;; Evaluate the definitions of build-batteries.lisp, skipping its loader form and its runner.
(with-open-file (s (merge-pathnames "bootstrap/build-batteries.lisp" cl-user::*root*))
  (let ((*package* (find-package :lisploop)) (forms nil))
    (loop for form = (read s nil :eof) until (eq form :eof) do (push form forms))
    (setf forms (nreverse forms))
    (dolist (form (butlast (cddr forms)))   ; drop (let* ..load..), (in-package), and final runner
      (eval form))))

(setf *bootstrap-output-directory*
      (pathname "/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/bootstrap-reflection/out-library/"))
(ensure-directories-exist *bootstrap-output-directory*)

(defun flush-jobs (label)
  (dolist (j (reverse *job-log*))
    (format t "~&[job ~A] self=~S limit=~D work=~D solved=~S bits=~S nodes=~D msgs=~D trace=~D nogoods=~D reused=~D~%        win-chain=~S schema-on-win=~S schema-nodes=~D~%        claims=~S~%        cats=~S~%"
            label (getf j :self) (getf j :limit) (getf j :work) (getf j :solved) (getf j :bits)
            (getf j :nodes) (getf j :messages) (getf j :trace) (getf j :nogoods) (getf j :reused)
            (getf j :win-chain) (getf j :schema-on-win) (getf j :schema-nodes)
            (getf j :claims)
            (sort (copy-tree (getf j :cats)) #'> :key #'cdr)))
  (setf *job-log* nil))

(let ((t00 (get-internal-real-time)))
  (dolist (fn '(build-algebra-battery build-arithmetic-battery build-constructors-battery
                build-functors-battery build-sequences-and-descriptors-batteries
                build-scans-battery build-sequence-shift-battery))
    (let ((t0 (get-internal-real-time)))
      (funcall fn)
      (format t "~&[time] ~A ~,3F s~%" fn (/ (- (get-internal-real-time) t0) internal-time-units-per-second))
      (flush-jobs fn)))
  (format t "~&[total] wall=~,3F s  sum-of-battery-ledgers=~D (sequences+descriptors share one ledger and are counted twice)~%"
          (/ (- (get-internal-real-time) t00) internal-time-units-per-second)
          (ledger-total *grand*)))
