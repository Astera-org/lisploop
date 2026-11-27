;;; EXP-A: enumerator growth per body bit, and syntactic vs observational redundancy.
;;; Read-only with respect to the repository: loads sources, writes nothing.
(load "/home/tlh24/lisploop/load.lisp")
(in-package #:lisploop)
(clear-knowledge-library)

(defun count-enumeration (language max-size max-steps)
  "Candidates per body-bit size straight from the enumerator, all types."
  (let ((e (make-enumerator language)) (counts (make-hash-table)) (steps 0)
        (target (language-domain language)) (tcounts (make-hash-table)))
    (loop while (and (<= (enumerator-size e) max-size) (< steps max-steps))
          do (incf steps)
             (multiple-value-bind (expr event) (enumeration-step e)
               (when (eq event :candidate)
                 (let ((size (enumerator-size e))
                       (type (index-expression e expr)))
                   (incf (gethash size counts 0))
                   (when (equal type target) (incf (gethash size tcounts 0)))))))
    (values counts tcounts steps (enumerator-size e))))

(defun report-growth (name language max-size &optional (max-steps 3000000))
  (multiple-value-bind (counts tcounts steps reached) (count-enumeration language max-size max-steps)
    (format t "~%[growth] ~A  operators=~D inputs=~D  steps=~D reached-size=~D~%"
            name (length (language-operators language)) (length (language-inputs language))
            steps reached)
    (let ((cum 0) (prev nil))
      (loop for size from 1 to max-size
            for c = (gethash size counts 0)
            for tc = (gethash size tcounts 0)
            do (incf cum c)
               (when (plusp c)
                 (format t "  bits=~3D new=~8D (target-typed ~8D) cumulative=~9D~@[  x~,2F vs previous non-empty size~]~%"
                         size c tc cum (and prev (plusp prev) (/ c (float prev))))
                 (setf prev c))))))

(defun report-redundancy (name frame language slack work)
  "Records = target-typed candidates evaluated; buckets = distinct complete behaviours."
  (let* ((scope (make-observation-scope frame language))
         (job (start-observation-search scope))
         (bound (+ (language-header-size language (schema-target (frame-schema frame))) slack))
         (message (resume-observation-search job bound work))
         (records (length (observation-job-records job)))
         (complete (count :complete (observation-job-records job) :key #'observed-expression-status))
         (buckets (length (observation-job-buckets job)))
         (syntax (loop for b being the hash-values of (enumerator-buckets (observation-job-enumerator job))
                       sum (length b))))
    (format t "~%[redundancy] ~A slack=~D: ~A at work ~D; completed-bound=~D (header ~D)~%"
            name slack (message-claim message) (ledger-total (observation-job-ledger job))
            (observation-job-completed-bound job)
            (language-header-size language (schema-target (frame-schema frame))))
    (format t "  retained syntax (all types)=~D  target-typed evaluated=~D  total on all rows=~D  distinct behaviours=~D  ratio=~,1F~%"
            syntax records complete buckets (if (plusp buckets) (/ complete (float buckets)) 0))
    (format t "  ledger=~S~%" (ledger-counts (observation-job-ledger job)))))

(let* ((in2 '((0 . :int) (1 . :int)))
       (seq-t (sequence-type :int))
       (in-seq (list (cons 0 seq-t)))
       (l1 (make-language :int in2 :operators (list (op :+ :int) (op :* :int)) :literals '(0 1)))
       (l2 (make-language :int in2 :operators (list (op :+ :int) (op :* :int) (op :- :int)
                                                    (op :if :int) (op := :int) (op :< :int))
                                :literals '(0 1)))
       (l3 (make-language :int in-seq
                          :operators (list (op :cons :int) (op :tail :int) (op :at seq-t) (op := seq-t)
                                           (op :if seq-t) (op :+ :int) (op :* :int))
                          :literals '(0 1) :constants (list (lit seq-t '()))))
       (l4 (make-language :int in2 :operators (list (op :+ :int) (op :* :int)) :literals :all)))
  (format t "application-overhead: +int=~D *int=~D -int=~D if-int=~D =int=~D <int=~D cons=~D tail=~D at-seq=~D =seq=~D if-seq=~D~%"
          (application-overhead (op :+ :int)) (application-overhead (op :* :int))
          (application-overhead (op :- :int)) (application-overhead (op :if :int))
          (application-overhead (op := :int)) (application-overhead (op :< :int))
          (application-overhead (op :cons :int)) (application-overhead (op :tail :int))
          (application-overhead (op :at seq-t)) (application-overhead (op := seq-t))
          (application-overhead (op :if seq-t)))
  (format t "leaf bits: var(2 inputs)=~D var(1 input)=~D lit0=~D lit1=~D lit2=~D lit7=~D~%"
          (body-size (var 0 :int) in2) (body-size (var 0 seq-t) in-seq)
          (body-size (lit :int 0) in2) (body-size (lit :int 1) in2) (body-size (lit :int 2) in2)
          (body-size (lit :int 7) in2))
  (report-growth "L1 int{+,*} lits{0,1} 2 inputs" l1 34)
  (report-growth "L2 int{+,*,-,if,=,<} lits{0,1} 2 inputs" l2 30)
  (report-growth "L3 seq{cons,tail,at,=,if,+,*} 1 seq input" l3 34)
  (report-growth "L4 int{+,*} lits :all 2 inputs" l4 28)
  ;; Redundancy on a 6-row probe frame (target x*y+x).
  (let* ((frame (simple-frame :int in2 '(((0 1) 0) ((1 2) 3) ((2 3) 8) ((3 1) 6) ((2 5) 12) ((4 2) 12)))))
    (report-redundancy "L1 on 6 rows" frame l1 26 4000000)
    (report-redundancy "L1 on 6 rows" frame l1 30 8000000)
    (report-redundancy "L2 on 6 rows" frame l2 24 8000000)))
