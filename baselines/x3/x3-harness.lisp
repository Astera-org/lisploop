;;;; x3-harness.lisp -- the Stage 0 E0b-2 loop (v2/experiments/stage0-audit.lisp:168-233), instrumented.
;;;; It calls the kernel exactly as `measure-bootstrap-distractor-audit` does and records more:
;;;; the grammar offered to each spec, the functions in the library, oracle stubs left behind, the text
;;;; of any error, the program returned in readable form, and held-out scores on the 200 inputs of
;;;; x3-heldout.lisp beside the harness's own one-input check.
;;;;
;;;; Environment:
;;;;   X3_MODE     as-written | repaired | clean | curriculum      (default as-written)
;;;;   X3_MULT     budget multiplier on 350,000 work per spec      (default 1)
;;;;   X3_REGIMES  all | comma list of regime names                (default all)
;;;;   X3_OUT      results file (one plist per spec attempt)
;;;;
;;;; Modes (what library each spec starts from):
;;;;   as-written  one library per regime, specs in order; a prerequisite is loaded from its battery only
;;;;               when (not (defined-function-p ...)), which is the harness's own test and its defect.
;;;;   repaired    the same, but a prerequisite is loaded when the library has no ENTRY for it.
;;;;   clean       a fresh library for every spec; :map and :foldr for the ten battery specs; :seq-corr for
;;;;               best-shift; :seq-corr and :best-shift for argmax-corr (the recount of
;;;;               plan_v2c_audit/scripts/bootstrap-reflection/budget-scaling.lisp).
;;;;   curriculum  a fresh library for every spec holding a correct definition of every function that
;;;;               precedes it: earlier seeds as the bootstrap synthesizes them (whitelist and schemas),
;;;;               :map and :foldr from the seventh spec on, earlier battery functions from the batteries.

(load (merge-pathnames "x3-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)

(defparameter *mode* (intern (string-upcase (or (sb-ext:posix-getenv "X3_MODE") "as-written")) :keyword))
(defparameter *mult* (parse-integer (or (sb-ext:posix-getenv "X3_MULT") "1")))
(defparameter *regime-filter*
  (let ((a (or (sb-ext:posix-getenv "X3_REGIMES") "all")))
    (unless (string= a "all")
      (loop for start = 0 then (1+ pos) for pos = (position #\, a :start start)
            collect (intern (string-upcase (subseq a start pos)) :keyword) while pos))))
(defparameter *out-path* (or (sb-ext:posix-getenv "X3_OUT") "x3-results.sexp"))

(defparameter *regimes*   ; verbatim from stage0-audit.lisp:172-175: (name active-grammar-p schemas-p)
  '((:whitelist+schemas nil t)
    (:whitelist-no-schemas nil nil)
    (:active-grammar+schemas t t)
    (:active-grammar-no-schemas t nil)))

(defparameter *heldout*
  (let ((tab (make-hash-table :test 'eq)))
    (dolist (form (read-plain-file (merge-pathnames "x3-heldout.lisp" cl-user::*x3-work*)) tab)
      (setf (gethash (intern (symbol-name (getf form :name)) :keyword) tab) (getf form :rows)))))

(defparameter *reference*   ; id -> portable expression the bootstrap derives (boot-specs.sexp)
  (let ((tab (make-hash-table :test 'eq)))
    (dolist (rec (read-boot-specs) tab) (setf (gethash (getf rec :id) tab) (getf rec :expression)))))

(defun score-200 (id inputs)
  "The function ID, as now defined, on the 200 held-out rows: counts, and the first miss."
  (let ((ok 0) (err 0) (unk 0) (first-bad nil) (rows (gethash id *heldout*)))
    (dolist (row rows)
      (destructuring-bind (args want) row
        (let* ((call (apply #'app (op id)
                            (loop for a in args for (nil . ty) in inputs
                                  collect (lit ty (unplain-value a ty)))))
               (run (evaluate call nil nil :budget 1000000))
               (status (evaluation-status run)))
          (if (and (eq :value status) (equal want (evaluation-value run)))
              (incf ok)
              (let ((got (if (eq :value status) (evaluation-value run) (list status))))
                (case status
                  (:value nil)
                  (:unknown (incf unk))
                  (t (incf err)))
                (unless first-bad
                  (setf first-bad (emit-string (list args want got))))))))
      )
    (list :ok ok :n (length rows) :errors err :budget-exhausted unk :first-miss first-bad)))

(defun reference-needs (id)
  "Operators (as portable sexps), integer literals and other constants in the reference definition of ID."
  (let ((ops nil) (ints nil) (consts nil))
    (labels ((walk (x)
               (ecase (first x)
                 (:var nil)
                 (:lit (cond ((eq :int (second x)) (pushnew (third x) ints))
                             (t (pushnew x consts :test #'equal))))
                 (:app (let ((o (second x)))
                         (unless (eq id (second o)) (pushnew o ops :test #'equal))
                         (mapc #'walk (cddr x)))))))
      (walk (gethash id *reference*)))
    (list (nreverse ops) (nreverse ints) (nreverse consts))))

(defun grammar-snapshot (spec lib active-g-p fn-name)
  "What `synthesize-spec-entry` (consolidate.lisp:1248-1273) is about to offer the search for SPEC."
  (with-knowledge-library (lib)
    (let* ((meta (knowledge-entry-metadata spec))
           (inputs (knowledge-entry-inputs spec))
           (target (knowledge-entry-target spec))
           (domain (or (knowledge-entry-domain spec) :int))
           (ops (if active-g-p
                    (mapcar #'ast->sexp (active-library-spec-operators domain inputs target lib fn-name))
                    (getf meta :operators)))
           (lits (if active-g-p
                     (remove-duplicates (append '(0 1 2) (getf meta :literals)) :test #'equal)
                     (getf meta :literals)))
           (consts (getf meta :constants)))
      (destructuring-bind (need-ops need-ints need-consts) (reference-needs fn-name)
        (list :operators ops :literals lits :constants consts
              :library-functions (loop for fn in (knowledge-entries-of-kind :function lib)
                                       collect (knowledge-entry-id fn))
              :oracle-stubs (loop for name in *registered-function-names*
                                  for def = (find-function-definition name)
                                  when (and def (function-definition-oracle-table def)) collect name)
              :reference-missing
              (append (set-difference need-ops ops :test #'equal)
                      (set-difference need-ints lits)
                      (set-difference need-consts consts :test #'equal)))))))

(defun load-prerequisites (id bname lib items)
  (ecase *mode*
    (:as-written     ; stage0-audit.lisp:195-200, verbatim
     (when (and (eq id :foldl) (not (defined-function-p :map)))
       (load-battery :sequences :only '(:map :foldr) :library lib :check-examples-p nil))
     (when (and (eq id :best-shift) (not (defined-function-p :seq-corr)))
       (load-battery :sequence-shift :only '(:seq-corr) :library lib :check-examples-p nil))
     (when (and (eq id :argmax-corr) (not (defined-function-p :best-shift)))
       (load-battery :sequence-shift :only '(:seq-corr :best-shift) :library lib :check-examples-p nil)))
    (:repaired       ; the same three, tested on the library's entries instead of on the function table
     (flet ((missing (name) (null (find-knowledge-entry name lib))))
       (when (and (eq id :foldl) (missing :map))
         (load-battery :sequences :only '(:map :foldr) :library lib :check-examples-p nil))
       (when (and (member id '(:best-shift :argmax-corr)) (missing :seq-corr))
         (load-battery :sequence-shift :only '(:seq-corr) :library lib :check-examples-p nil))
       (when (and (eq id :argmax-corr) (missing :best-shift))
         (load-battery :sequence-shift :only '(:best-shift) :library lib :check-examples-p nil))))
    (:clean          ; budget-scaling.lisp:63-68
     (unless (eq bname :seed-corpus)
       (load-battery :sequences :only '(:map :foldr) :library lib :check-examples-p nil))
     (when (member id '(:best-shift :argmax-corr))
       (load-battery :sequence-shift :only '(:seq-corr) :library lib :check-examples-p nil))
     (when (eq id :argmax-corr)
       (load-battery :sequence-shift :only '(:seq-corr :best-shift) :library lib :check-examples-p nil)))
    (:curriculum
     (let* ((before (subseq *x3-order* 0 (position id *x3-order*)))
            (seeds '(:copy :inc-all :dbl-all :sum-all :len-all :prd-all)))
       (dolist (sid seeds)
         (when (member sid before)
           (let ((*use-active-library-grammar* nil)
                 (item (find sid items :key (lambda (it) (getf it :id)))))
             (synthesize-spec-entry (getf item :spec) :library lib :bound 90 :budget 80000
                                    :expanders (list (recursion-schema-expander))))))
       (unless (eq bname :seed-corpus)
         (load-battery :sequences
                       :only (append '(:map :foldr)
                                     (intersection '(:foldl :filter :map-adjacent :positions) before))
                       :library lib :check-examples-p nil)
         (when (member :scan before)
           (load-battery :scans :only '(:scan) :library lib :check-examples-p nil))
         (let ((shift (remove-if-not (lambda (x) (member x before))
                                     '(:shift-seq :seq-corr :best-shift :argmax-corr :last-or))))
           (when shift
             (load-battery :sequence-shift :only shift :library lib :check-examples-p nil))))))))

(defun attempt (item lib active-g-p schemas-p budget rname items)
  "One spec, as in stage0-audit.lisp:186-232."
  (let* ((id (getf item :id))
         (bname (getf item :battery))
         (spec (getf item :spec))
         (rec-p (not (eq id :argmax-corr)))
         (bound (if (eq bname :seed-corpus) 90 130))
         (spec-budget (if (eq bname :seed-corpus) (max 80000 budget) budget))
         (ledger (make-ledger))
         (t0 (get-internal-run-time))
         snapshot ok held-ok expr-sexp plain-expr bits err h200)
    (load-prerequisites id bname lib items)
    (setf snapshot (grammar-snapshot spec lib active-g-p id))
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
            (setf plain-expr (emit-string (plain (knowledge-entry-expression fn-ent)))
                  bits (knowledge-entry-bits fn-ent))
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
                           cases))
              (setf h200 (score-200 id inps)))))
      (error (c) (setf ok nil err (remove #\Newline (princ-to-string c)))))
    ;; a progress line at once, so that a long run that dies still leaves what it had measured
    (format t "~&  [progress] ~(~A ~A~) solved=~A one-input=~A 200=~A work=~:D cpu=~,1Fs~@[ program=~A~]~@[ error=~A~]~%"
            rname id (if ok "YES" "no") (if ok (if held-ok "YES" "IMPOSTOR") "-")
            (if h200 (format nil "~D/~D" (getf h200 :ok) (getf h200 :n)) "-")
            (ledger-total ledger)
            (/ (- (get-internal-run-time) t0) (float internal-time-units-per-second))
            plain-expr err)
    (finish-output)
    (list :mode *mode* :regime rname :budget spec-budget :id id :battery bname
          :bound (if active-g-p (+ bound 24) bound) :recursive-p rec-p
          :solved ok :held-out-1 held-ok :held-out-200 h200
          :work (ledger-total ledger) :bits bits
          :cpu-seconds (/ (- (get-internal-run-time) t0) (float internal-time-units-per-second))
          :error err :program plain-expr :program-typed expr-sexp
          :grammar snapshot)))

(defun run-regime (regime items budget)
  (destructuring-bind (rname active-g-p schemas-p) regime
    (let ((results nil))
      (if (member *mode* '(:as-written :repaired))
          ;; stage0-audit.lisp:179-183: one clean state and one library for the whole regime
          (with-clean-kernel-state
            (let ((*use-active-library-grammar* active-g-p)
                  (lib (make-knowledge-library)))
              (with-knowledge-library (lib)
                (dolist (item items)
                  (push (attempt item lib active-g-p schemas-p budget rname items) results)))))
          (dolist (item items)
            (with-clean-kernel-state
              (let ((lib (make-knowledge-library)))
                (with-knowledge-library (lib)
                  (let ((*use-active-library-grammar* active-g-p))
                    (push (attempt item lib active-g-p schemas-p budget rname items) results)))))))
      (nreverse results))))

(defun sound-200-p (r)
  (let ((h (getf r :held-out-200))) (and (getf r :solved) h (= (getf h :ok) (getf h :n)))))

(let* ((items (collect-bootstrap-function-specs))
       (budget (* 350000 *mult*))
       (t0 (get-internal-real-time)))
  (with-open-file (out *out-path* :direction :output :if-exists :supersede)
    (format t "~&=== x3-harness: mode ~A, budget ~:D work per spec (x~D) ===~%" *mode* budget *mult*)
    (dolist (regime *regimes*)
      (when (or (null *regime-filter*) (member (first regime) *regime-filter*))
        (let* ((results (run-regime regime items budget))
               (n (length results)))
          (format t "~&~%Regime ~A [~A, x~D]: solved ~D/~D, held-out sound (harness, 1 input) ~D/~D, held-out sound (200 inputs) ~D/~D~%"
                  (first regime) *mode* *mult*
                  (count-if (lambda (r) (getf r :solved)) results) n
                  (count-if (lambda (r) (and (getf r :solved) (getf r :held-out-1))) results) n
                  (count-if #'sound-200-p results) n)
          (dolist (r results)
            (let ((h (getf r :held-out-200)) (g (getf r :grammar)))
              (format t "  ~13A solved=~3A one-input=~9A 200=~7A work=~10:D bits=~4A cpu=~6,2Fs~%"
                      (getf r :id)
                      (if (getf r :solved) "YES" "no")
                      (cond ((not (getf r :solved)) "-") ((getf r :held-out-1) "YES") (t "IMPOSTOR!"))
                      (if h (format nil "~D/~D" (getf h :ok) (getf h :n)) "-")
                      (getf r :work) (or (getf r :bits) "-") (getf r :cpu-seconds))
              (when (getf r :program) (format t "      program: ~A~%" (getf r :program)))
              (when (getf r :error) (format t "      error: ~A~%" (getf r :error)))
              (when (and h (getf h :first-miss))
                (format t "      200-input score: ~D errors, ~D out of evaluation budget; first miss (args want got): ~A~%"
                        (getf h :errors) (getf h :budget-exhausted) (getf h :first-miss)))
              (format t "      library functions: ~(~{~A~^ ~}~)~@[;  oracle stubs left defined: ~(~{~A~^ ~}~)~]~%"
                      (or (getf g :library-functions) '("(none)")) (getf g :oracle-stubs))
              (format t "      grammar: ~D operators ~(~{~A~^ ~}~); literals ~A; constants ~(~{~S~^ ~}~)~%"
                      (length (getf g :operators))
                      (mapcar (lambda (o) (if (and (consp (third o)) (eq :code (first (third o)))
                                                   (not (eq :code-eval (second o))) (not (eq := (second o)))
                                                   (not (eq :if (second o))))
                                              (second o)
                                              (format nil "~A@~A" (second o) (third o))))
                              (getf g :operators))
                      (getf g :literals) (getf g :constants))
              (when (getf g :reference-missing)
                (format t "      the library's own definition needs, and this grammar lacks: ~(~{~S~^ ~}~)~%"
                        (getf g :reference-missing))))
            (let ((*package* (find-package :lisploop))) (format out "~S~%" r)))
          (finish-output) (finish-output out)))))
  (format t "~&~%wall ~,1F s~%" (/ (- (get-internal-real-time) t0) (float internal-time-units-per-second))))
