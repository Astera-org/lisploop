;;;; Print the cold/warm numbers that tests/library.lisp L4 only compares with `<`. (scratch copy)
(defvar *args* (cdr (member "--" sb-ext:*posix-argv* :test #'string=)))
(defvar *v2-root* (pathname (concatenate 'string (first *args*) "/")))
(load (merge-pathnames "load.lisp" *v2-root*))
(load (merge-pathnames "tests/support.lisp" *v2-root*))
(load (merge-pathnames "tests/library.lisp" *v2-root*))
(in-package #:lisploop)
(setf *print-pretty* nil)
(sb-int:encapsulate
 'resume-synthesis 'audit
 (lambda (fn job work-limit &rest keys)
   (prog1 (apply fn job work-limit keys)
     (let* ((best (synthesis-job-best job)) (win (job-winning-node job)))
       (format t "~&  job self=~12A work=~7:D solved=~A size=~A nodes=~D nogoods=~D reused-nogood-conflicts=~D chain=~S~%"
               (synthesis-job-self-name job) (ledger-total (synthesis-job-ledger job)) (not (null best))
               (and best (candidate-size best)) (length (synthesis-job-nodes job)) (length (synthesis-job-nogoods job))
               (count-if (lambda (m) (and (eq :conflict (message-claim m)) (getf (message-evidence m) :reused-nogood)))
                         (synthesis-job-messages job))
               (and win (loop for cur = win then (synthesis-node-parent cur) while cur
                              for p = (synthesis-node-proposal cur)
                              when p collect (let ((n (decomposition-name p))) (if (consp n) (first n) n)))))))))
(sb-int:encapsulate
 'consolidate-knowledge-library 'audit
 (lambda (fn library &rest keys)
   (let ((report (apply fn library keys)))
     (format t "~&  consolidate: work=~:D passes=~D ingested=~S~%     consolidated=~S~%     library now: ~S~%"
             (getf report :work) (getf report :passes)
             (mapcar #'knowledge-entry-id (getf report :ingested))
             (loop for (k . v) in (getf report :consolidated)
                   collect (cons k (if (listp v) (mapcar (lambda (e) (if (knowledge-entry-p e) (knowledge-entry-id e) e)) v) v)))
             (loop for e in (knowledge-library-entries library) collect (list (knowledge-entry-kind e) (knowledge-entry-id e))))
     (let ((p (find-knowledge-entry :default-priority-predictor library)))
       (when p (format t "     learned priority predictor: ~S~%" (ast->sexp (knowledge-entry-expression p)))))
     report)))
(format t "L4 curriculum (tests/library.lisp:348): cold shift4; cold inc, add3; consolidate; add-len; [serialize/deserialize]; warm inc, shift4, add-len~%")
(library-l4-continual-learning-curriculum-amortization)
