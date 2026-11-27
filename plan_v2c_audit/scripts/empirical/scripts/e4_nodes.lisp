;;;; E4 budget-rescue harness (auditor `empirical`).
;;;; Regime: "active-library grammar, no recursion schemas" of v2/experiments/stage0-audit.lisp.
;;;;
;;;;   sbcl --dynamic-space-size 8192 --script e4_rescue.lisp TARGET MAX-BUDGET [BOUND-ADD] [MAX-DEPTH] [HEUR-BUDGET] [WALL-SECONDS]
;;;;
;;;; 1. Replays every spec that precedes TARGET in the audit's order, with the audit's own code
;;;;    path (synthesize-spec-entry, 350k cap), so the library the target sees is the library the
;;;;    audit's ACTIVE-GRAMMAR-NO-SCHEMAS regime had when it reached TARGET.
;;;; 2. Runs TARGET with the same construction as synthesize-spec-entry, but keeps the job and
;;;;    resumes it through a ladder of cumulative work caps (350k x 1, 10, 100, ...) up to
;;;;    MAX-BUDGET, logging at every rung. resume-synthesis is cumulative/anytime, so one run to
;;;;    MAX-BUDGET answers every smaller cap.
;;;; BOUND-ADD is added to the description-bit bound (130+24 by default); MAX-DEPTH and
;;;; HEUR-BUDGET override the audit's :max-depth 2 / :heuristic-budget 15000.
(defvar *v2-root* #P"/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical/repo/v2/")
(load (merge-pathnames "load.lisp" *v2-root*))
(load (merge-pathnames "tests/support.lisp" *v2-root*))
(in-package #:lisploop)
(setf *print-pretty* nil)

;;; --- verbatim from v2/experiments/stage0-audit.lisp -------------------------------------
(defun collect-bootstrap-function-specs ()
  (let ((specs nil))
    (dolist (bname '(:sequences :scans :sequence-shift))
      (let* ((packet (read-battery bname))
             (lib (deserialize-knowledge-library packet)))
        (dolist (sp (knowledge-entries-of-kind :spec lib))
          (let* ((meta (knowledge-entry-metadata sp))
                 (edge (first (knowledge-edges-from sp :specifies lib)))
                 (tid (second edge))
                 (ref-fn (and tid (find-knowledge-entry tid lib))))
            (when (and (eq :function (getf meta :target-kind :function))
                       (getf meta :operators)
                       ref-fn)
              (push (list :battery bname :id tid :spec sp :ref ref-fn) specs))))))
    (let* ((seq-t (sequence-type :int))
           (in1 (list (cons 0 seq-t)))
           (s-ops (list (op :cons :int) (op :tail :int) (op :at seq-t) (op := seq-t)
                        (op :if seq-t) (op :+ :int) (op :* :int)))
           (i-ops (list (op :tail :int) (op :at seq-t) (op := seq-t)
                        (op :if :int) (op :+ :int) (op :* :int)))
           (seed-defs
             (list (list :copy seq-t '(((()) ()) (((3)) (3)) (((1 3)) (1 3)) (((4 1 3)) (4 1 3))) s-ops nil '((9 2 5)))
                   (list :inc-all seq-t '(((()) ()) (((3)) (4)) (((1 3)) (2 4)) (((4 1 3)) (5 2 4))) s-ops '(1) '((9 -2 5)))
                   (list :dbl-all seq-t '(((()) ()) (((3)) (6)) (((1 3)) (2 6)) (((4 1 3)) (8 2 6))) s-ops '(2) '((9 -2 5)))
                   (list :sum-all :int '(((()) 0) (((3)) 3) (((2 3)) 5) (((4 2 3)) 9)) i-ops '(0) '((10 -3 7)))
                   (list :len-all :int '(((()) 0) (((3)) 1) (((2 3)) 2) (((4 2 3)) 3)) i-ops '(0 1) '((10 -3 7 8)))
                   (list :prd-all :int '(((()) 1) (((3)) 3) (((2 3)) 6) (((4 2 3)) 24)) i-ops '(1) '((2 5 3)))))
           (seed-items
             (loop for (id ret rows ops lits held) in seed-defs
                   collect (list :battery :seed-corpus
                                 :id id
                                 :spec (make-knowledge-spec (keyword-id "SPEC/~A" id) in1 ret rows
                                                            :target-id id :operators ops :literals lits
                                                            :constants (list (lit seq-t '()))
                                                            :library nil)
                                 :held-out-args (list held)))))
      (append seed-items (nreverse specs)))))

(defun held-out-test-cases (id)
  (case id
    (:copy (list '(((9 2 5)) (9 2 5))))
    (:inc-all (list '(((9 -2 5)) (10 -1 6))))
    (:dbl-all (list '(((9 -2 5)) (18 -4 10))))
    (:sum-all (list '(((10 -3 7)) 14)))
    (:len-all (list '(((10 -3 7 8)) 4)))
    (:prd-all (list '(((2 5 3)) 30)))
    (:foldl (list (list (list '(1 2 3) 10 (term `(- (* 2 ,(var 0 :int)) ,(var 1 :int)))) 69)))
    (:filter (list (list (list '(-5 8 0 3 -1) (term `(< 0 ,(var 0 :int)))) '(8 3))))
    (:map-adjacent (list (list (list '(10 3 9 1) (term `(- ,(var 0 :int) ,(var 1 :int)))) '(-7 6 -8))))
    (:positions (list '(((10 20 30 40) 2) (2 3 4 5))))
    (:scan (list (list (list '(1 2 3) 10 (term `(- (* 2 ,(var 0 :int)) ,(var 1 :int)))) '(19 36 69))))
    (:shift-seq (list '(((8 6 4 2) 2) (4 2 0 0))))
    (:seq-corr (list '(((2 -1 3) (4 5 2)) 9)))
    (:best-shift (list '(((2 4 1) (4 1) 0) (17 1))))
    (:argmax-corr (list '(((1 4 1 5) (4 1 5 0)) 1)))
    (:last-or (list '(((9 5 2) 7) 2)))))
;;; ---------------------------------------------------------------------------------------

(defun compact (sexp)
  "ast->sexp output as ordinary prefix code: (name args...), Xi, literal."
  (cond ((atom sexp) sexp)
        ((eq :app (first sexp)) (cons (second (second sexp)) (mapcar #'compact (cddr sexp))))
        ((eq :var (first sexp)) (intern (format nil "X~D" (second sexp)) :keyword))
        ((eq :lit (first sexp)) (let ((v (third sexp))) (if (and (listp v) v) (list 'quote v) (or v "()/NIL"))))
        (t sexp)))

(defun secs (ticks) (/ ticks (float internal-time-units-per-second 1d0)))

(defun held-out-ok (id fn-ent)
  (let ((inps (knowledge-entry-inputs fn-ent)))
    (every (lambda (tc)
             (destructuring-bind (args want) tc
               (let* ((call (apply #'app (op id)
                                   (loop for v in args for (nil . ty) in inps collect (lit ty v))))
                      (run (evaluate call nil nil :budget 20000)))
                 (and (eq :value (evaluation-status run))
                      (equal want (evaluation-value run))))))
           (held-out-test-cases id))))

(defun node-census (job)
  (let ((phases nil) (maxdepth 0))
    (dolist (n (synthesis-job-nodes job))
      (incf (getf phases (synthesis-node-phase n) 0))
      (setf maxdepth (max maxdepth (node-depth n))))
    (list :nodes (length (synthesis-job-nodes job)) :phases phases :max-depth maxdepth
          :deferred (loop for n in (synthesis-job-nodes job)
                          sum (length (synthesis-node-deferred-proposals n)))
          :expandable (count-if (lambda (n) (node-expandable-p job n)) (synthesis-job-nodes job))
          ;; per searching node: (id proposal-name node-bound completed-bound header enumerator-size retained-syntax search-work rejected)
          :searching
          (loop for n in (synthesis-job-nodes job)
                for search = (synthesis-node-search n)
                when (and search (eq :search (synthesis-node-phase n)))
                  collect (let* ((en (search-job-enumerator search))
                                 (lang (search-job-language search))
                                 (hdr (language-header-size lang (schema-target (frame-schema (search-job-frame search))))))
                            (list (synthesis-node-id n)
                                  (let ((p (synthesis-node-proposal n)))
                                    (and p (let ((nm (decomposition-name p))) (if (consp nm) (first nm) nm))))
                                  :bound (synthesis-node-bound n)
                                  :done-bits (search-job-completed-bound search)
                                  :hdr hdr
                                  :body-size (and en (enumerator-size en))
                                  :ops (length (language-operators lang))
                                  :inputs (length (language-inputs lang))
                                  :syntax (and en (loop for b being the hash-values of (enumerator-buckets en) sum (length b)))
                                  :work (ledger-total (search-job-ledger search))
                                  :rejected (search-job-rejected search)))))))

(let* ((args (rest sb-ext:*posix-argv*))
       (target (intern (string-upcase (first args)) :keyword))
       (max-budget (parse-integer (second args)))
       (bound-add (if (third args) (parse-integer (third args)) 0))
       (max-depth (if (fourth args) (parse-integer (fourth args)) 2))
       (heur-budget (if (fifth args) (parse-integer (fifth args)) 15000))
       (wall-cap (if (sixth args) (parse-integer (sixth args)) 100000))
       (items (collect-bootstrap-function-specs))
       (*use-active-library-grammar* t)
       (lib (make-knowledge-library)))
  (format t "E4 target=~A max-budget=~D bound-add=~D max-depth=~D heuristic-budget=~D wall-cap=~Ds~%"
          target max-budget bound-add max-depth heur-budget wall-cap)
  (with-clean-kernel-state
    (with-knowledge-library (lib)
      (dolist (item items)
        (let* ((id (getf item :id))
               (bname (getf item :battery))
               (spec (getf item :spec))
               (rec-p (not (eq id :argmax-corr)))
               (bound (if (eq bname :seed-corpus) 90 130))
               (ledger (make-ledger)))
          (when (and (eq id :foldl) (not (defined-function-p :map)))
            (load-battery :sequences :only '(:map :foldr) :library lib :check-examples-p nil))
          (when (and (eq id :best-shift) (not (defined-function-p :seq-corr)))
            (load-battery :sequence-shift :only '(:seq-corr) :library lib :check-examples-p nil))
          (when (and (eq id :argmax-corr) (not (defined-function-p :best-shift)))
            (load-battery :sequence-shift :only '(:seq-corr :best-shift) :library lib :check-examples-p nil))
          (cond
            ((not (eq id target))
             ;; Prefix replay: the audit's own call, 350k cap.
             (let ((ok nil))
               (handler-case
                   (setf ok (not (null (synthesize-spec-entry spec :library lib :bound bound
                                                                  :budget (if (eq bname :seed-corpus) 350000 350000)
                                                                  :recursive-p rec-p :expanders nil
                                                                  :ledger ledger))))
                 (error () (setf ok nil)))
               (format t "  prefix ~14A solved=~3A work=~D~%" id (if ok "YES" "no") (ledger-total ledger))))
            (t
             ;; Target: synthesize-spec-entry's construction, job kept.
             (with-knowledge-library (lib)
               (let* ((spec-edge (first (knowledge-edges-from spec :specifies lib)))
                      (fn-name (or (second spec-edge) (knowledge-entry-id spec)))
                      (meta (knowledge-entry-metadata spec))
                      (inputs (knowledge-entry-inputs spec))
                      (tgt (knowledge-entry-target spec))
                      (domain (or (knowledge-entry-domain spec) :int))
                      (ops (active-library-spec-operators domain inputs tgt lib fn-name))
                      (lits (remove-duplicates (append '(0 1 2) (getf meta :literals)) :test #'equal))
                      (consts (mapcar #'sexp->ast (getf meta :constants)))
                      (eff-bound (+ bound 24 bound-add))
                      (frame (spec-entry-frame spec :ledger ledger))
                      (lang (make-language domain inputs :operators ops :literals lits :constants consts))
                      (job (if rec-p
                               (start-recursive-synthesis frame lang eff-bound :self-name fn-name
                                                          :max-depth max-depth :heuristic-budget heur-budget
                                                          :expanders nil)
                               (start-heuristic-synthesis frame lang eff-bound :max-depth max-depth
                                                                               :expanders nil)))
                      (wall0 (get-internal-real-time)) (cpu0 (get-internal-run-time))
                      (gc0 sb-ext:*gc-run-time*) (forced 0d0) (forced-wall 0d0)
                      (claim nil))
                 (let ((ref (getf item :ref)))
                   (when ref
                     (format t "REFERENCE ~A (battery, whitelist+schemas): ~D bits: ~S~%" id
                             (ignore-errors (description-size (knowledge-entry-expression ref) inputs))
                             (compact (ast->sexp (knowledge-entry-expression ref))))))
                 (format t "TARGET ~A: inputs=~D rows=~D operators=~D (~{~A~^ ~}) literals=~S eff-bound=~D bits~%"
                         id (length inputs) (length (frame-rows frame)) (length ops)
                         (mapcar #'operator-name ops) lits eff-bound)
                 (finish-output)
                 (loop for cap in (remove-duplicates
                                   (sort (append (loop for c = 350000 then (* c 10) while (< c max-budget) collect c)
                                                 (loop for c = 1000000 then (* c 10) while (< c max-budget)
                                                       append (list c (* 2 c) (* 5 c) (* 7 c)))
                                                 (list max-budget))
                                         #'<))
                       when (<= cap max-budget)
                       do (let* ((msg (resume-synthesis job cap :stop-on-first t))
                                 (cpu (- (secs (- (get-internal-run-time) cpu0)) forced))
                                 (wall (- (secs (- (get-internal-real-time) wall0)) forced-wall))
                                 (gc (- (secs (- sb-ext:*gc-run-time* gc0)) forced)))
                            (setf claim (message-claim msg))
                            ;; retained heap, measured by a forced full GC whose time is excluded from cpu_s/wall_s/gc_s
                            (let ((c0 (get-internal-run-time)) (w0 (get-internal-real-time)))
                              (when (>= cap 10000000) (sb-ext:gc :full t))
                              (incf forced (secs (- (get-internal-run-time) c0)))
                              (incf forced-wall (secs (- (get-internal-real-time) w0))))
                            (format t "  rung cap=~12D work=~12D claim=~18A cpu_s=~9,2F wall_s=~9,2F gc_s=~7,2F live_MiB=~7,1F ~S~%"
                                    cap (ledger-total (synthesis-job-ledger job)) claim cpu wall gc
                                    (/ (sb-kernel:dynamic-usage) 1048576d0)
                                    (node-census job))
                            (finish-output)
                            (when (or (not (eq claim :cutoff))
                                      (> wall wall-cap))
                              (return))))
                 (dolist (n (synthesis-job-nodes job))
                   (let* ((p (synthesis-node-proposal n))
                          (fr (synthesis-node-frame n))
                          (lang (synthesis-node-language n)))
                     (format t "NODE ~D parent=~A phase=~A depth=~D bound=~A~%" (synthesis-node-id n)
                             (and (synthesis-node-parent n) (synthesis-node-id (synthesis-node-parent n)))
                             (synthesis-node-phase n) (node-depth n) (synthesis-node-bound n))
                     (when p
                       (format t "   proposal name=~S lift-p=~S structural-p=~S~%   decoder=~S~%   bindings=~S~%"
                               (decomposition-name p) (decomposition-lift-p p) (decomposition-structural-p p)
                               (compact (ignore-errors (ast->sexp (decomposition-decoder p))))
                               (loop for b in (decomposition-bindings p)
                                     collect (ignore-errors (if (consp b) (cons (car b) (compact (ast->sexp (cdr b)))) b)))))
                     (when fr
                       (format t "   inputs=~S target=~S~%" (schema-inputs (frame-schema fr)) (schema-target (frame-schema fr)))
                       (loop for r in (frame-rows fr) repeat 4
                             do (format t "   row ~S known=~S req=~S~%" (row-key r) (row-known r)
                                        (compact (ast->sexp (row-requirement r))))))
                     (when lang
                       (format t "   language ops=~S literals=~S constants=~S~%"
                               (mapcar #'operator-name (language-operators lang)) (language-literals lang)
                               (mapcar (lambda (c) (compact (ast->sexp c))) (language-constants lang))))
                     (let ((h (synthesis-node-heuristic n)))
                       (when h (format t "   stage-a: exact=~S score=~S program=~S~%" (heuristic-exact-p h) (heuristic-score h)
                                       (compact (ast->sexp (heuristic-program h))))))))
                 (format t "RESULT ~A claim=~A work=~D cpu_s=~,2F wall_s=~,2F~%" id claim
                         (ledger-total (synthesis-job-ledger job))
                         (secs (- (get-internal-run-time) cpu0)) (secs (- (get-internal-real-time) wall0)))
                 (format t "  ledger=~S~%" (ledger-counts (synthesis-job-ledger job)))
                 (if (synthesis-job-best job)
                     (let* ((cand (synthesis-job-best job)))
                       (format t "  PROGRAM (~D bits): ~S~%" (candidate-size cand)
                               (compact (ast->sexp (candidate-expression cand))))
                       (handler-case
                           (progn
                             (commit-synthesis-job job :library lib :name fn-name :ledger ledger)
                             (let ((fn-entry (find-knowledge-entry fn-name lib)))
                               (verify-entry-against-spec fn-entry spec :library lib :ledger ledger)
                               (format t "  spec-verified=YES held-out=~A~%"
                                       (if (held-out-ok id fn-entry) "PASS" "FAIL (IMPOSTOR)"))))
                         (error (c) (format t "  commit/verify ERROR: ~A~%" c))))
                     (format t "  no program. final claim ~A => ~A~%" claim
                             (if (eq claim :bounded-exhaustion)
                                 "search space of the configured proposals EXHAUSTED (cap-limited, not budget-limited)"
                                 "cutoff: budget ran out before exhaustion")))
                 (finish-output)
                 (sb-ext:exit :code 0 :abort t))))))))))
