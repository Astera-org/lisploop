;;;; Budget-scaling experiment (scratch copy). Does a larger work budget alone recover the specs
;;;; that the Stage 0 ablation reports as TIMEOUT at 350k work?
;;;; argv tail: <v2-root> <max-budget> [bound-bonus] [max-depth]
(defvar *args* (cdr (member "--" sb-ext:*posix-argv* :test #'string=)))
(defvar *v2-root* (pathname (concatenate 'string (first *args*) "/")))
(defvar *max-budget* (parse-integer (second *args*)))
(defvar *bound-bonus* (if (third *args*) (parse-integer (third *args*)) 0))
(defvar *max-depth* (if (fourth *args*) (parse-integer (fourth *args*)) 2))
(load (merge-pathnames "load.lisp" *v2-root*))
(load (merge-pathnames "bootstrap/recursion-schemas.lisp" *v2-root*))
(load (merge-pathnames "tests/support.lisp" *v2-root*))
(in-package #:lisploop)
(setf *print-pretty* nil)

;; Borrow the audit's spec collection and held-out cases without running its top-level.
(with-open-file (s (merge-pathnames "experiments/stage0-audit.lisp" cl-user::*v2-root*))
  (let ((*package* (find-package :lisploop)))
    (loop for form = (read s nil :eof) until (eq form :eof)
          do (when (and (consp form) (eq 'defun (first form))
                        (member (second form) '(collect-bootstrap-function-specs held-out-test-cases)))
               (eval form)))))

(defun try-spec (spec fn-name &key active-grammar-p schemas-p budget bound recursive-p max-depth)
  "The body of `synthesize-spec-entry`, returning the job instead of asserting."
  (let* ((*use-active-library-grammar* active-grammar-p)
         (library *knowledge-library*)
         (meta (knowledge-entry-metadata spec))
         (inputs (knowledge-entry-inputs spec))
         (target (knowledge-entry-target spec))
         (domain (or (knowledge-entry-domain spec) :int))
         (ops (if active-grammar-p
                  (active-library-spec-operators domain inputs target library fn-name)
                  (mapcar #'sexp->ast (getf meta :operators))))
         (lits (if active-grammar-p
                   (remove-duplicates (append '(0 1 2) (getf meta :literals)) :test #'equal)
                   (getf meta :literals)))
         (consts (mapcar #'sexp->ast (getf meta :constants)))
         (eff-bound (if active-grammar-p (+ bound 24) bound))
         (frame (spec-entry-frame spec))
         (lang (make-language domain inputs :operators ops :literals lits :constants consts))
         (expanders (when schemas-p (list (recursion-schema-expander))))
         (job (if recursive-p
                  (start-recursive-synthesis frame lang eff-bound :self-name fn-name :max-depth max-depth
                                             :heuristic-budget 15000 :expanders expanders)
                  (start-heuristic-synthesis frame lang eff-bound :max-depth max-depth :expanders expanders))))
    (resume-synthesis job budget :stop-on-first t)
    job))

(defun held-out-ok (id inputs)
  (every (lambda (tc)
           (destructuring-bind (args want) tc
             (let* ((call (apply #'app (op id) (loop for v in args for (nil . ty) in inputs collect (lit ty v))))
                    (run (evaluate call nil nil :budget 20000)))
               (and (eq :value (evaluation-status run)) (equal want (evaluation-value run))))))
         (held-out-test-cases id)))

(defun run-one (item active-grammar-p schemas-p budget)
  (let* ((id (getf item :id)) (bname (getf item :battery)) (spec (getf item :spec))
         (t0 (get-internal-real-time)))
    (with-clean-kernel-state
      ;; Prerequisites exactly as the curriculum has them at this point.
      (unless (eq bname :seed-corpus)
        (load-battery :sequences :only '(:map :foldr) :check-examples-p nil))
      (when (member id '(:best-shift :argmax-corr))
        (load-battery :sequence-shift :only '(:seq-corr) :check-examples-p nil))
      (when (eq id :argmax-corr)
        (load-battery :sequence-shift :only '(:seq-corr :best-shift) :check-examples-p nil))
      (let* ((job (handler-case
                      (try-spec spec id :active-grammar-p active-grammar-p :schemas-p schemas-p
                                        :budget budget
                                        :bound (+ cl-user::*bound-bonus* (if (eq bname :seed-corpus) 90 130))
                                        :recursive-p (not (eq id :argmax-corr))
                                        :max-depth cl-user::*max-depth*)
                    (error (e) (format t "   ERROR ~A~%" e) nil)))
             (best (and job (synthesis-job-best job)))
             (sound (and best
                         (progn (commit-synthesis-job job :name id)
                                (ignore-errors (held-out-ok id (knowledge-entry-inputs spec)))))))
        (format t "~&~14A grammar=~9A schemas=~3A budget=~11:D -> ~8A work=~11:D finished=~3A nodes=~4D msgs=~5D nogoods=~3D reused=~3D bits=~A ~,1Fs~%"
                id (if active-grammar-p "active" "whitelist") (if schemas-p "on" "off") budget
                (cond ((null job) "ERROR") ((null best) "no") (sound "SOUND") (t "IMPOSTOR"))
                (if job (ledger-total (synthesis-job-ledger job)) 0)
                (if (and job (synthesis-finished-p job)) "yes" "no")
                (if job (length (synthesis-job-nodes job)) 0)
                (if job (length (synthesis-job-messages job)) 0)
                (if job (length (synthesis-job-nogoods job)) 0)
                (if job (synthesis-job-reused-subproblems job) 0)
                (and best (candidate-size best))
                (/ (- (get-internal-real-time) t0) internal-time-units-per-second))
        (when (and best (not sound))
          (format t "   impostor: ~S~%" (ast->sexp (candidate-expression best))))
        (when (and job (not best))
          (format t "   where-work-went: ~S~%   per-node: ~S~%"
                  (sort (copy-tree (ledger-counts (synthesis-job-ledger job))) #'> :key #'cdr)
                  (loop for n in (synthesis-job-nodes job)
                        collect (list (synthesis-node-id n)
                                      (let ((p (synthesis-node-proposal n))) (and p (let ((nm (decomposition-name p))) (if (consp nm) (first nm) nm))))
                                      (synthesis-node-phase n)
                                      (let ((sj (synthesis-node-search n))) (and sj (ledger-total (search-job-ledger sj))))))))
        (finish-output)
        (and best sound)))))

(defvar *only* (let ((a (fifth cl-user::*args*)))
                 (and a (not (string= a "all"))
                      (loop for start = 0 then (1+ pos)
                            for pos = (position #\, a :start start)
                            collect (intern (string-upcase (subseq a start pos)) :keyword)
                            while pos))))
(defvar *regimes* (let ((a (sixth cl-user::*args*)))
                    (cond ((null a) '((nil nil) (t nil) (t t)))
                          ((string= a "wl-off") '((nil nil)))
                          ((string= a "ag-off") '((t nil)))
                          ((string= a "ag-on") '((t t)))
                          ((string= a "wl-on") '((nil t))))))
(defvar *min-budget* (let ((a (seventh cl-user::*args*))) (if a (parse-integer a) 350000)))
(let ((items (collect-bootstrap-function-specs)))
  (dolist (regime *regimes*)
    (destructuring-bind (active-p schemas-p) regime
      (dolist (item items)
        (when (and (not (eq :seed-corpus (getf item :battery)))
                   (or (null *only*) (member (getf item :id) *only*)))
          (loop for budget = *min-budget* then (* budget 10)
                while (<= budget cl-user::*max-budget*)
                until (run-one item active-p schemas-p budget)))))))
