;;;; experiments/stage0-audit.lisp
;;;; Stage 0 Empirical Audit (E0a + E0b):
;;;;   1. Post-E0a Plan 8 probe check & complexity summary
;;;;   2. E0b-1a: Gating `requirements.lisp` `:cons` fold rules vs. `library/constructors.sexp`
;;;;   3. E0b-1b: Gating `descriptors.lisp` prototype synthesis vs. `library/descriptors.sexp`
;;;;   4. E0b-2:  Stripping per-spec `:operators` whitelists in bootstrap (with & without schemas,
;;;;              plus held-out non-symmetric semantic checks for impostor detection)

(defvar *v2-root* #P"/tmp/claude-1000/-home-tlh24-lisploop/d1a4b558-b777-4749-af5d-51001946d6e1/scratchpad/empirical/repo/v2/")

(load (merge-pathnames "load.lisp" *v2-root*))
(load (merge-pathnames "bootstrap/recursion-schemas.lisp" *v2-root*))
(load (merge-pathnames "tests/support.lisp" *v2-root*))

(in-package #:lisploop)

(defun collect-bootstrap-function-specs ()
  "Load all `:spec` entries targeting `:function` across the saved batteries in `library/`,
along with ground-truth reference expressions for held-out semantic verification."
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
    ;; Also add the 6 de-novo L3 seed corpus specs from `build-batteries.lisp`!
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
  "Non-symmetric held-out input vectors catching order/boundary impostors (e.g. `foldl` on `2a - b`,
`last-or` on distinct head vs last element)."
  (let ((bin-t (code-type '((0 . :int) (1 . :int)) :int))
        (pred-t (code-type '((0 . :int)) :bool)))
    (case id
      (:copy (list '(((9 2 5)) (9 2 5))))
      (:inc-all (list '(((9 -2 5)) (10 -1 6))))
      (:dbl-all (list '(((9 -2 5)) (18 -4 10))))
      (:sum-all (list '(((10 -3 7)) 14)))
      (:len-all (list '(((10 -3 7 8)) 4)))
      (:prd-all (list '(((2 5 3)) 30)))
      ;; Non-commutative `2*acc - elem` starting at 10 on `(1 2 3)`:
      ;; Left fold: ((10*2 - 1)*2 - 2)*2 - 3 = (19*2 - 2)*2 - 3 = 36*2 - 3 = 69!
      ;; Tail-first impostor gives a different answer!
      (:foldl (list (list (list '(1 2 3) 10 (term `(- (* 2 ,(var 0 :int)) ,(var 1 :int)))) 69)))
      (:filter (list (list (list '(-5 8 0 3 -1) (term `(< 0 ,(var 0 :int)))) '(8 3))))
      (:map-adjacent (list (list (list '(10 3 9 1) (term `(- ,(var 0 :int) ,(var 1 :int)))) '(-7 6 -8))))
      (:positions (list '(((10 20 30 40) 2) (2 3 4 5))))
      (:scan (list (list (list '(1 2 3) 10 (term `(- (* 2 ,(var 0 :int)) ,(var 1 :int)))) '(19 36 69))))
      (:shift-seq (list '(((8 6 4 2) 2) (4 2 0 0))))
      (:seq-corr (list '(((2 -1 3) (4 5 2)) 9)))
      (:best-shift (list '(((2 4 1) (4 1) 0) (17 1))))
      (:argmax-corr (list '(((1 4 1 5) (4 1 5 0)) 1)))
      ;; Distinct head (9) vs last element (2): true `last-or` returns 2, head-returning impostor returns 9!
      (:last-or (list '(((9 5 2) 7) 2))))))

(defun measure-cons-fold-gate ()
  "E0b-1a: Measure exact pass/fail & work of representative `:cons` tasks across 3 regimes."
  (flet ((probe-suite (cons-folds-p load-constructors-p)
           (with-clean-kernel-state
             (let ((*enable-host-cons-folds* cons-folds-p)
                   (ledger (make-ledger))
                   (seq-t (sequence-type :int)))
               (when load-constructors-p
                 (load-battery :constructors :ledger ledger))
               (load-battery :sequences :only '(:map :filter :foldr) :check-examples-p nil)
               (let* ((in1 (list (cons 0 seq-t)))
                      ;; 1. Lifting `:map` (`fold-equal-cons` needed to split `(= (cons (Z 1) ...) '(2 3))`)
                      (map-frame (simple-frame seq-t in1 '(((()) ()) (((1 2)) (2 3)) (((4 1 2)) (5 2 3)))))
                      (map-lang (make-language :int in1 :operators (list (op :map) (op :+ :int))
                                                        :literals '(1) :constants (list (lit seq-t '()))))
                      (j-map (start-heuristic-synthesis map-frame map-lang 70))
                      (_1 (resume-synthesis j-map 60000 :stop-on-first t))
                      ;; 2. Direct `:cons` requirement propagation `(= (cons H T) '(10 20))`
                      (pair-t (tuple-type :int seq-t))
                      (v (var 0 pair-t))
                      (req (term `(= (cons (at ,v 0) (at ,v 1)) '(10 20))))
                      (folded (fold-constants req :contract :necessary :ledger ledger))
                      (prop (propagate-requirements
                             (make-frame (make-schema :inputs nil :target pair-t)
                                         (list (make-row :key 0 :known nil :requirement folded)))
                             *knowledge-library* ledger))
                      (prop-req (row-requirement (first (frame-rows (propagation-frame prop)))))
                      ;; 3. Recursive synthesis of `:inc-all`
                      (rec-lang (make-language :int in1
                                               :operators (list (op :cons :int) (op :tail :int)
                                                                (op :at seq-t) (op := seq-t)
                                                                (op :if seq-t) (op :+ :int))
                                               :literals '(1) :constants (list (lit seq-t '()))))
                      (j-rec (start-recursive-synthesis map-frame rec-lang 90 :self-name :test-inc))
                      (_2 (resume-synthesis j-rec 80000 :stop-on-first t)))
                 (declare (ignore _1 _2))
                 (list :map-lift-solved (not (null (synthesis-job-best j-map)))
                       :map-lift-work (ledger-total (synthesis-job-ledger j-map))
                       :cons-prop-narrowed (+ (propagation-narrowed prop) (propagation-suggested prop))
                       :cons-prop-certified (plusp (propagation-narrowed prop))
                       :cons-prop-result (ast->sexp prop-req)
                       :rec-solved (not (null (synthesis-job-best j-rec)))
                       :rec-work (ledger-total (synthesis-job-ledger j-rec))))))))
    (list (cons :host-folds-on (probe-suite t nil))
          (cons :host-folds-off-empty (probe-suite nil nil))
          (cons :host-folds-off-with-constructors-sexp (probe-suite nil t)))))

(defun measure-descriptor-gate ()
  "E0b-1b: Compare host `synthesize-io-descriptor-specs` vs preloaded `descriptors.sexp`
on fresh descriptor-profile computation and frame scoring."
  (flet ((run-mode (host-synth-p)
           (with-clean-kernel-state
             (let ((*enable-host-descriptor-synthesis* host-synth-p)
                   (profile-ledger (make-ledger))
                   (score-ledger (make-ledger))
                   (seq-t (sequence-type :int)))
               (unless host-synth-p
                 (load-battery :descriptors :check-examples-p nil))
               (load-battery :sequences :only '(:map :foldr :filter :map-adjacent) :check-examples-p nil)
               (load-battery :scans :only '(:scan) :check-examples-p nil)
               ;; Recompute profiles from scratch so `profile-ledger` measures genuine profile induction vs matching!
               (dolist (fn '(:map :foldr :filter :map-adjacent :scan))
                 (let ((ent (find-knowledge-entry fn)))
                   (setf (knowledge-entry-descriptor-profile ent) nil)
                   (compute-entry-descriptor-profile ent *knowledge-library* profile-ledger)))
               (let* ((in1 (list (cons 0 seq-t)))
                      (map-f (simple-frame seq-t in1 '(((()) ()) (((1 2 3)) (2 3 4)))))
                      (flt-f (simple-frame seq-t in1 '(((()) ()) (((-1 2 -3 4)) (2 4)))))
                      (adj-f (simple-frame seq-t in1 '(((()) ()) (((5)) ()) (((1 4 9)) (3 5))))))
                 (flet ((scores (f)
                          (loop for fn in '(:map :filter :map-adjacent)
                                collect (multiple-value-bind (ok delta)
                                            (score-entry-by-descriptors fn f 0 :ledger score-ledger)
                                          (list fn ok delta)))))
                   (list :install-work (ledger-total profile-ledger)
                         :score-work (ledger-total score-ledger)
                         :map-frame (scores map-f)
                         :filter-frame (scores flt-f)
                         :adj-frame (scores adj-f))))))))
    (list (cons :host-prototype-synthesis (run-mode t))
          (cons :library-descriptors-sexp (run-mode nil)))))

(defvar *fix-prereq* nil)
(defvar *regime-filter* nil)
(defun measure-bootstrap-distractor-audit (&key (budget 350000))
  "E0b-2: Run all 16 bootstrap `:function` specs across 4 regimes:
(whitelist vs active-library grammar) x (recursion-schemas ON vs OFF), checking held-out semantics."
  (let ((items (collect-bootstrap-function-specs))
        (regimes (remove-if-not (lambda (r) (or (null *regime-filter*) (member (first r) *regime-filter*)))
                                '((:whitelist+schemas nil t)
                                  (:whitelist-no-schemas nil nil)
                                  (:active-grammar+schemas t t)
                                  (:active-grammar-no-schemas t nil))))
        (rows nil))
    (dolist (regime regimes (nreverse rows))
      (destructuring-bind (rname active-g-p schemas-p) regime
        (with-clean-kernel-state
          (let ((*use-active-library-grammar* active-g-p)
                (lib (make-knowledge-library))
                (regime-results nil))
            (with-knowledge-library (lib)
              ;; Pre-install `:map` and `:foldr` before the post-seed specs just as `build-batteries.lisp` does
              ;; once the 6 seed corpus functions finish.
              (dolist (item items)
                (let* ((id (getf item :id))
                       (bname (getf item :battery))
                       (spec (getf item :spec))
                       (rec-p (not (eq id :argmax-corr)))
                       (bound (if (eq bname :seed-corpus) 90 130))
                       (spec-budget (if (eq bname :seed-corpus) (max 80000 budget) budget))
                       (ledger (make-ledger)))
                  ;; Ensure prerequisite library functions are available even if an earlier spec failed in this regime:
                  (when (and (eq id :foldl) (if *fix-prereq* (not (ignore-errors (find-knowledge-entry :map lib))) (not (defined-function-p :map))))
                    (load-battery :sequences :only '(:map :foldr) :library lib :check-examples-p nil))
                  (when (and (eq id :best-shift) (if *fix-prereq* (not (ignore-errors (find-knowledge-entry :seq-corr lib))) (not (defined-function-p :seq-corr))))
                    (load-battery :sequence-shift :only '(:seq-corr) :library lib :check-examples-p nil))
                  (when (and (eq id :argmax-corr) (if *fix-prereq* (not (ignore-errors (find-knowledge-entry :best-shift lib))) (not (defined-function-p :best-shift))))
                    (load-battery :sequence-shift :only '(:seq-corr :best-shift) :library lib :check-examples-p nil))
                  (when (and active-g-p (member id '(:best-shift :argmax-corr)))
                    (format t "GRAMMAR-AT ~A regime=~A: ~S~%" id rname
                            (mapcar (lambda (o) (list (operator-name o) (operator-operand-type o)))
                                    (remove-if-not (lambda (o) (member (operator-name o) '(:seq-corr :best-shift :at :tuple)))
                                                   (active-library-spec-operators :int (knowledge-entry-inputs spec) (knowledge-entry-target spec) lib id)))))
                  (let ((ok nil)
                        (held-ok nil)
                        (expr-sexp nil) (err-text nil) (cpu0 (get-internal-run-time)))
                    (handler-case
                        (let ((fn-ent (synthesize-spec-entry
                                       spec
                                       :library lib
                                       :bound bound
                                       :budget spec-budget
                                       :recursive-p rec-p
                                       :expanders (when schemas-p (list (recursion-schema-expander)))
                                       :ledger ledger)))
                          (setf ok (not (null fn-ent))
                                expr-sexp (and fn-ent (ast->sexp (knowledge-entry-expression fn-ent))))
                          (when ok
                            (let ((cases (held-out-test-cases id))
                                  (inps (knowledge-entry-inputs fn-ent)))
                              (setf held-ok
                                    (every (lambda (tc)
                                             (destructuring-bind (args want) tc
                                               (let* ((call (apply #'app (op id)
                                                                   (loop for v in args
                                                                         for (nil . ty) in inps
                                                                         collect (lit ty v))))
                                                      (run (evaluate call nil nil :budget 20000)))
                                                 (and (eq :value (evaluation-status run))
                                                      (equal want (evaluation-value run))))))
                                           cases)))))
                      (error (c) (setf ok nil err-text (let ((s (princ-to-string c))) (subseq s 0 (min 70 (length s)))))))
                    (push (list :id id :solved ok :held-out-ok held-ok
                                :work (ledger-total ledger) :expr expr-sexp :err err-text
                                :cpu (/ (- (get-internal-run-time) cpu0) (float internal-time-units-per-second 1d0)))
                          regime-results)))))
            (push (cons rname (nreverse regime-results)) rows)))))))


;;; ---- driver (auditor `empirical`) ----
;;;   sbcl --dynamic-space-size N --script e4_sequence.lisp BUDGET [fix|nofix] [regime-keyword ...]
;;; The audit's own measure-bootstrap-distractor-audit (v2/experiments/stage0-audit.lisp), whole
;;; 16-spec sequence, with the per-spec cap BUDGET. `fix` loads a prerequisite battery function
;;; whenever the library has no knowledge entry for it (the audit tests defined-function-p, which is
;;; true for the oracle stub left by a failed synthesis, so a failed prerequisite is silently absent
;;; from every later grammar).
(setf *print-pretty* nil)
(defun compact (sexp)
  (cond ((atom sexp) sexp)
        ((eq :app (first sexp)) (cons (second (second sexp)) (mapcar #'compact (cddr sexp))))
        ((eq :var (first sexp)) (intern (format nil "X~D" (second sexp)) :keyword))
        ((eq :lit (first sexp)) (let ((v (third sexp))) (if (and (listp v) v) (list 'quote v) (or v "()/NIL"))))
        (t sexp)))
(let* ((args (rest sb-ext:*posix-argv*))
       (budget (parse-integer (first args)))
       (*fix-prereq* (equal (second args) "fix"))
       (*regime-filter* (mapcar (lambda (s) (intern (string-upcase s) :keyword)) (cddr args)))
       (c0 (get-internal-run-time))
       (report (measure-bootstrap-distractor-audit :budget budget)))
  (format t "E4-SEQUENCE budget=~D (x~,1F of 350k) prereq-fix=~A total_cpu_s=~,1F~%" budget (/ budget 350000.0) *fix-prereq*
          (/ (- (get-internal-run-time) c0) (float internal-time-units-per-second 1d0)))
  (dolist (regime report)
    (let* ((entries (cdr regime))
           (solved (count-if (lambda (r) (getf r :solved)) entries))
           (sound (count-if (lambda (r) (and (getf r :solved) (getf r :held-out-ok))) entries)))
      (format t "~%Regime ~A budget=~D: solved ~D/~D, held-out sound ~D/~D~%" (car regime) budget solved (length entries) sound (length entries))
      (dolist (r entries)
        (format t "  ~14A solved=~3A sound=~9A work=~10D cpu_s=~7,2F~@[ err=~A~]~@[ program=~S~]~%"
                (getf r :id) (if (getf r :solved) "YES" "no")
                (cond ((not (getf r :solved)) "-") ((getf r :held-out-ok) "YES") (t "IMPOSTOR"))
                (getf r :work) (getf r :cpu) (getf r :err)
                (and (getf r :solved) (compact (getf r :expr))))))))
