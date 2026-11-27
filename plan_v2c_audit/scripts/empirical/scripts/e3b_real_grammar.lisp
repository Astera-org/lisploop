;;;; E3b: E3's growth measurement on the REAL grammar of an E4 spec (generated from e4_rescue.lisp).
;;;;   sbcl --dynamic-space-size N --script e3b_real_grammar.lisp TARGET MODE CPU-SECONDS MAX-SYNTAX
;;;; The library is brought to the state the audit's ACTIVE-GRAMMAR-NO-SCHEMAS regime has when it reaches
;;;; TARGET (prefix replay at 350k); then ONE flat search is run on TARGET's spec frame with TARGET's
;;;; active-library grammar (the root lane's language: no self-call), reporting per completed body size:
;;;; syntax trees (all types), observationally distinct behaviours on the spec rows, work, cpu.
;;;; MODE exact = start-search without pruning; behaviours counted off-ledger by this script (each new
;;;;              tree evaluated on every row with a 20000-unit budget; outcome = value / :error / status).
;;;; MODE prune = start-search :prune-behaviors-p t :columnar-p t (v2's own observational pruning).
;;;; (header text below is e4_rescue.lisp's)
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
;;;; Optional 7th argument REGIME: agns (default; active grammar, no schemas), ags (active grammar +
;;;; recursion schemas), wlns (per-spec whitelist, no schemas), wls (whitelist + schemas): the audit's
;;;; other three regimes, with the prefix replayed in the same regime.
;;;; BOUND-ADD is added to the description-bit bound (130+24 by default); MAX-DEPTH and
;;;; HEUR-BUDGET override the audit's :max-depth 2 / :heuristic-budget 15000.
(defvar *v2-root* #P"/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical/repo/v2/")
(load (merge-pathnames "load.lisp" *v2-root*))
(load (merge-pathnames "bootstrap/recursion-schemas.lisp" *v2-root*))
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
       (mode (second args))
       (cpu-cap (parse-integer (third args)))
       (max-syntax (parse-integer (fourth args)))
       (prune-p (string= mode "prune"))
       (items (collect-bootstrap-function-specs))
       (*use-active-library-grammar* t)
       (lib (make-knowledge-library)))
  (with-clean-kernel-state
    (with-knowledge-library (lib)
      (dolist (item items)
        (let* ((id (getf item :id)) (bname (getf item :battery)) (spec (getf item :spec))
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
             (handler-case (synthesize-spec-entry spec :library lib :bound bound :budget 350000
                                                       :recursive-p rec-p :expanders nil :ledger ledger)
               (error () nil)))
            (t
             (let* ((spec-edge (first (knowledge-edges-from spec :specifies lib)))
                    (fn-name (or (second spec-edge) (knowledge-entry-id spec)))
                    (meta (knowledge-entry-metadata spec))
                    (inputs (knowledge-entry-inputs spec))
                    (tgt (knowledge-entry-target spec))
                    (ops (active-library-spec-operators :int inputs tgt lib fn-name))
                    (lits (remove-duplicates (append '(0 1 2) (getf meta :literals)) :test #'equal))
                    (consts (mapcar #'sexp->ast (getf meta :constants)))
                    (frame (spec-entry-frame spec :ledger ledger))
                    (rows (frame-rows frame))
                    (language (make-language :int inputs :operators ops :literals lits :constants consts))
                    (header (language-header-size language tgt))
                    (job (if prune-p
                             (start-search frame language :prune-behaviors-p t :columnar-p t)
                             (start-search frame language)))
                    (enumerator (row-job-enumerator job))
                    (behaviours (make-hash-table :test #'equal))
                    (seen (make-hash-table :test #'equal))
                    (cpu 0d0) (prev-syntax 0) (prev-work 0) (prev-beh 0))
               (format t "E3b target=~A mode=~A inputs=~D rows=~D operators=~D literals=~S header=~D bits~%"
                       id mode (length inputs) (length rows) (length ops) lits header)
               (format t "~4A ~10A ~10A ~12A ~12A ~8A ~8A ~8A ~8A ~9A ~11A ~9A~%"
                       "body" "syn_cum" "syn_new" "behav_cum" "work_cum" "w/syn" "x_syn" "x_work" "x_behav" "cpu_s" "work/s" "cand/s")
               (loop for body from 1
                     do (let ((c0 (get-internal-run-time)))
                          (resume-search job (+ header body) most-positive-fixnum)
                          (incf cpu (secs (- (get-internal-run-time) c0))))
                        (let* ((syntax (loop for b being the hash-values of (enumerator-buckets enumerator) sum (length b)))
                               (work (ledger-total (row-job-ledger job)))
                               (beh (if prune-p
                                        (hash-table-count (enumerator-behavior-table enumerator))
                                        (progn
                                          (maphash (lambda (key bucket)
                                                     (unless (gethash key seen)
                                                       (when (= (second key) body)
                                                         (setf (gethash key seen) t)
                                                         (loop for expression across bucket
                                                               do (setf (gethash
                                                                         (cons (first key)
                                                                               (loop for row in rows
                                                                                     collect (let ((run (evaluate expression inputs (row-known row) :budget 20000)))
                                                                                               (if (eq :value (evaluation-status run))
                                                                                                   (evaluation-value run)
                                                                                                   (evaluation-status run)))))
                                                                         behaviours)
                                                                        t)))))
                                                   (enumerator-buckets enumerator))
                                          (hash-table-count behaviours)))))
                          (when (> syntax prev-syntax)
                            (format t "~4D ~10D ~10D ~12D ~12D ~8,1F ~8,3F ~8,3F ~8,3F ~9,2F ~11,0F ~9,0F~%"
                                    body syntax (- syntax prev-syntax) beh work (/ work (max 1 syntax) 1d0)
                                    (if (plusp prev-syntax) (/ syntax prev-syntax 1d0) 0)
                                    (if (plusp prev-work) (/ work prev-work 1d0) 0)
                                    (if (plusp prev-beh) (/ beh prev-beh 1d0) 0)
                                    cpu (/ work (max cpu 1d-3)) (/ syntax (max cpu 1d-3)))
                            (when prune-p
                              (let ((tried (+ syntax (or (cdr (assoc :equality-cache (ledger-counts (row-job-ledger job)))) 0))))
                                (format t "       tried=~D column-cache-entries=~D dyn_MiB=~,0F~%" tried
                                        (hash-table-count (enumerator-column-cache enumerator))
                                        (/ (sb-kernel:dynamic-usage) 1048576d0))))
                            (finish-output))
                          (setf prev-syntax syntax prev-work work prev-beh beh)
                          (when (or (> cpu cpu-cap) (> syntax max-syntax))
                            (format t "STOP body=~D cpu_s=~,2F syntax=~D work=~D results=~D~%" body cpu syntax work
                                    (length (search-job-results job)))
                            (return))))
               (finish-output)
               (sb-ext:exit :code 0 :abort t)))))))))
