;;; Standalone before/after diagnostics for findings in audit-review.txt.
;;; Assertions for the repaired contracts live in audit.lisp and higher-order.lisp.
;;; Run: sbcl --script tests/audit-probes.lisp
(load (merge-pathnames "../load.lisp" *load-truename*))
(load (merge-pathnames "support.lisp" *load-truename*))
(load (merge-pathnames "higher-order.lisp" *load-truename*))
(in-package #:lisploop)

;; OPEN: projection folding can still erase a partial code evaluation.
(let* ((ct (code-type nil :int))
       (inputs (list (cons 0 ct)))
       (head (app (op :code-eval ct) (var 0 ct)))
       (expr (app (op :tail :int)
                  (app (op :cons :int) head (lit (sequence-type :int) nil))))
       (bad-code (app (op :/ :int) (lit :int 1) (lit :int 0))))
  (format t "~&projection-definedness: original=~S folded=~S~%"
          (evaluation-status (evaluate expr inputs (list bad-code)))
          (evaluation-status (evaluate (fold-constants expr) inputs (list bad-code)))))

;; OPEN: a recognizer which sees no CONS accepts a constant function as a filter.
(with-knowledge-library ((make-knowledge-library))
  (let* ((st (sequence-type :int))
         (ct (code-type '((0 . :int)) :bool))
         (def (define-function :audit-constant (list (cons 0 st) (cons 1 ct)) st
                               (lit st '(9))))
         (frame (simple-frame st (list (cons 0 st)) '((((1)) (9))))))
    (format t "descriptor-pruning: compatible=~S actual=~S~%"
            (library-function-descriptor-compatible-p frame 0 (function-definition-name def) (make-ledger))
            (result (app (op :audit-constant) (lit st '(1)) (lit ct (lit :bool t)))))))

;; OPEN: replacing an entry leaves obsolete incoming edges and old kind entries.
(with-knowledge-library ((make-knowledge-library))
  (register-knowledge-entry
   (make-knowledge-entry :id :audit-entry :kind :relation :inputs nil :target :int
                         :expression (lit :int 1) :edges '((:derived-from :old))))
  (register-knowledge-entry
   (make-knowledge-entry :id :audit-entry :kind :heuristic :inputs nil :target :int
                         :expression (lit :int 2) :edges '((:derived-from :new))))
  (format t "entry-replacement: old-incoming=~S old-kind-count=~D new-kind=~S~%"
          (knowledge-edges-to :old)
          (length (knowledge-entries-of-kind :relation))
          (knowledge-entry-kind (find-knowledge-entry :audit-entry))))

;; OPEN: law certificate provenance is lost on registration; status authorizes rewrites.
(with-knowledge-library ((make-knowledge-library))
  (let* ((d (gf 5))
         (x (var 0 d))
         (law (make-law d (list (cons 0 d)) (app (op :+ d) x (lit d 0)) x))
         (validation (resume-law-validation (start-law-validation law) 100000))
         (entry (register-knowledge-law validation)))
    (setf (knowledge-entry-expression entry)
          (app (op := d) (app (op :+ d) x (lit d 0)) (lit d 0)))
    (let ((library (as-rewrite-library *knowledge-library* :domain d)))
      (format t "mutated-law: status=~S accepted-rules=~D false-at-x=1~%"
              (knowledge-entry-status entry) (if library (length (rewrite-library-rules library)) 0)))))

;; OPEN: a guarded involution establishes an inverse on its guard, not global uniqueness.
(with-knowledge-library ((make-knowledge-library))
  (let* ((d (gf 3)) (inputs (list (cons 0 d))) (x (var 0 d)))
    (define-function :audit-collapse inputs d (lit d 0))
    (let* ((guard (app (op := d) x (lit d 0)))
           (law (make-law d inputs (app (op :audit-collapse) (app (op :audit-collapse) x)) x
                          :guard guard))
           (validation (resume-law-validation (start-law-validation law) 100000)))
      (register-knowledge-law validation)
      (induce-involution-solvers *knowledge-library*)
      (let* ((req (app (op := d) (app (op :audit-collapse) x) (lit d 0)))
             (frame (make-frame (make-schema :inputs nil :target d)
                                (list (make-row :key 0 :known nil :requirement req))))
             (prop (propagate-requirements frame *knowledge-library* (make-ledger))))
        (format t "guarded-involution: status=~S narrowed=~D fallback=~S accepts-x=1-before=~S after=~S~%"
                (law-validation-status validation) (propagation-narrowed prop)
                (not (null (propagation-fallback prop)))
                (accepts req 1)
                (accepts (row-requirement (first (frame-rows (propagation-frame prop)))) 1))))))

;; OPEN: CEGAR checks run synchronously inside a nominal one-unit verification step.
(with-knowledge-library ((make-knowledge-library))
  (define-standard-int-combinators)
  (let* ((st (sequence-type :int)) (inputs (list (cons 0 st)))
         (frame (simple-frame st inputs '((((0 2)) (0 4)) (((3 5)) (9 25)))))
         (language (make-language :int inputs :operators (list (op :map) (op :+ :int) (op :* :int))
                                  :literals nil :constants (list (lit st nil))))
         (*max-active-lifted-rows* 2)
         (job (start-synthesis frame language 60 :expand (library-expander) :max-depth 1))
         (max-overrun 0) (first-overrun nil))
    (loop for limit from 1 to 30000
          until (or (synthesis-finished-p job) (synthesis-job-best job))
          do (resume-synthesis job limit :stop-on-first t)
             (let ((overrun (- (ledger-total (synthesis-job-ledger job)) limit)))
               (when (plusp overrun)
                 (unless first-overrun (setf first-overrun limit))
                 (setf max-overrun (max max-overrun overrun)))))
    (format t "cegar-budget: solved=~S refinements=~D first-overrun-at=~S max-overrun=~D~%"
            (not (null (synthesis-job-best job)))
            (count :cegar-refinement (synthesis-job-messages job) :key #'message-claim)
            first-overrun max-overrun)))
