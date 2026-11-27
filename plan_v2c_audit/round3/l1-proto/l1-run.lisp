;;;; l1-run.lisp -- L1 drivers.  Loaded after tg-probe-l1.lisp, labels.lisp, r1-spec.lisp.
;;;; Every experiment prints to standard output; run.sh sends that to logs/<experiment>.log.
(in-package :tg)

(defun now-us ()
  (multiple-value-bind (s ns) (sb-unix:clock-gettime sb-unix:clock-monotonic) (+ (* s 1000000) (floor ns 1000))))

;;; ---- one run under a filter configuration ---------------------------------------------------
;;; snapshot fields: 0 cand  1 classes  2 feasible  3 label-ruled-out  4 type-ruled-out  5 look-ups
;;;                  6 declined-to-store  7 false-rejects  8 label-ruled-out evaluated in pass B  9 type-... in pass B
;;; TIME: "ms" everywhere is PROCESS CPU TIME (the machine was shared with other jobs while these ran, so
;;; wall-clock time is not meaningful); fastest of REPS runs; a full GC before each run, outside the clock.
(defun cpu-us ()
  (multiple-value-bind (s ns) (sb-unix:clock-gettime sb-unix:clock-process-cputime-id) (+ (* s 1000000) (floor ns 1000))))
(defstruct res prog us cand banks notes)
(defun bank-summaries ()
  (loop for (bank kind) in (reverse *banks*)
        collect (let* ((snaps (remove bank *levels* :key #'first :test-not #'eq))
                       (fin (find :final snaps :key #'second)))
                  (list :kind kind :done (bank-done bank) :rows (base-n (bank-base bank))
                        :final (if fin (cddr fin) (cddr (snapshot bank :final)))
                        :levels (sort (mapcar #'cdr (remove :final snaps :key #'second)) #'< :key #'first)))))
(defun lrun (cfg thunk &key (reps 1))
  "Run THUNK under filter configuration CFG, REPS times; keep the fastest (counts are deterministic)."
  (let (best)
    (dotimes (k reps)
      (setf *banks* nil *levels* nil *cand* 0 *cells* 0 *scan* 0 *note* nil)
      (sb-ext:gc :full t)
      (let* ((*lf-cfg* cfg) (*trace* t) (t0 (cpu-us))
             (prog (handler-case (funcall thunk) (error (c) (list :error (princ-to-string c)))))
             (us (- (cpu-us) t0)))
        (when (or (null best) (< us (res-us best)))
          (setf best (make-res :prog prog :us us :cand *cand* :banks (bank-summaries) :notes (reverse *note*))))
        (when (> us 3000000) (return))))  ; a run over 3 s of CPU is not repeated
    (setf *banks* nil *levels* nil)
    best))

(defun main-bank (r)
  "The bank in which the answer was (or was not) found: the last element / select bank of the run."
  (or (find-if (lambda (b) (let ((k (getf b :kind))) (or (member k '(:elem :select)) (consp k))))
               (res-banks r) :from-end t)
      (car (last (res-banks r)))
      (list :kind :none :done 0 :final (make-list 14 :initial-element 0) :levels nil))) ; answered by a leaf: no bank
(defun tot (r i) (loop for b in (res-banks r) sum (nth i (getf b :final))))
(defun peak-classes (r)
  "Classes held at the end.  Banks of one run coexist, except look-ahead restarts, of which only the last counts."
  (loop for b in (res-banks r)
        unless (and (consp (getf b :kind)) (not (eq b (main-bank r))))
          sum (second (getf b :final))))
(defun at-done (b)
  "(cand classes) of bank summary B at its last COMPLETED level."
  (let ((l (find (getf b :done) (getf b :levels) :key #'first)))
    (if l (list (second l) (third l)) (list 0 0))))
(defun spared (r) (- (+ (tot r 3) (tot r 4)) (tot r 8) (tot r 9)))  ; candidates considered and never evaluated
(defun ok-prog (p) (and p (not (and (consp p) (eq (first p) :error)))))
(defun ho (task prog)
  (cond ((not (ok-prog prog)) "-")
        (t (let ((h (held-out task prog))) (if (integerp h) (format nil "~d/200" h) "ERR")))))

;; work = cells of full evaluations + cells of row-by-row tests + look-ups + label cells computed for stored classes
(defun work (r) (+ (tot r 12) (tot r 11) (tot r 5) (tot r 13)))
(defun header ()
  (format t "~%~24a ~12a ~9a | ~4a ~9a ~9a ~8a ~8a | ~9a ~9a ~10a ~6a ~9a ~9a ~10a | ~8a ~8a ~4a~%"
          "task" "mode" "cand" "done" "cand<=dn" "cand>dn" "cls<=dn" "cls>dn"
          "spar-lab" "spar-typ" "look-ups" "lk/gat" "p-cells" "lab-cells" "work" "ms" "held-out" "same"))
(defun row (name mode r task &optional base)
  "One line.  cand: candidates FULLY evaluated (a whole column), all banks.  Then, for the main bank: done = last
   COMPLETED size level; candidates and classes up to it, and in the level cut short after it.  spar-lab /
   spar-typ: candidates considered and never evaluated, ruled out by a label / by result type.  lk/gat: look-ups
   per candidate that reached a table.  p-cells: cells evaluated by the row-by-row exact test.  lab-cells: labels
   computed for stored classes.  work = cells of full evaluations + p-cells + look-ups + lab-cells.
   same: is the program EQUAL to plain's."
  (let* ((b (main-bank r)) (fin (getf b :final)) (dn (at-done b)) (gated (+ (tot r 2) (tot r 3))))
    (format t "~24a ~12a ~9d | ~4d ~9d ~9d ~8d ~8d | ~9d ~9d ~10d ~6a ~9d ~9d ~10d | ~8,2f ~8a ~4a~%"
            name mode (res-cand r) (getf b :done) (first dn) (- (first fin) (first dn))
            (second dn) (- (second fin) (second dn))
            (- (tot r 3) (tot r 8)) (- (tot r 4) (tot r 9)) (tot r 5)
            (if (plusp gated) (format nil "~,2f" (/ (tot r 5) gated 1.0)) "-")
            (tot r 11) (tot r 13) (work r)
            (/ (res-us r) 1000.0) (ho task (res-prog r))
            (cond ((null base) "") ((equal (res-prog r) (res-prog base)) "yes") (t "NO")))
    (when (plusp (tot r 7)) (format t "   !! FALSE REJECTS (audit): ~d~%" (tot r 7)))
    (when (plusp (tot r 6)) (format t "   classes evaluated but not stored (look-ahead): ~d~%" (tot r 6)))
    (when (and base (not (equal (res-prog r) (res-prog base))))
      (format t "   plain: ~s~%   ~a: ~s~%" (res-prog base) mode (res-prog r)))
    (finish-output)))

;;; ---- the task sets --------------------------------------------------------------------------
(defun proto-tasks (&key (seed 1) occam inverses (limit 30000000) only)
  "The prototype's own 15 sequence tasks on its own example sets (EXP-D: 12 examples, lengths 0..7)."
  (loop for task in *tasks*
        when (or (null only) (member (task-name task) only :test #'string=))
          collect (let ((task task) (exs (gen-examples task seed 12 7)))
                    (list (task-name task) task
                          (lambda () (let ((*occam* occam) (*inverses* inverses)) (solve-task task exs 10 limit)))))))
(defun spec-tasks (&key occam only)
  "The kernel :spec rows the verify-review version solves through SOLVE-TASK / SOLVE-SCALAR."
  (remove-if-not
   (lambda (e) (or (null only) (member (first e) only :test #'string=)))
   (append
    (loop for n in '("copy" "inc-all" "dbl-all" "positions" "scan" "shift-seq" "filter" "map-adjacent")
          collect (let ((task (spec-task n)) (exs (spec-exs n)))
                    (list (format nil "spec ~a" n) task
                          (lambda () (let ((*d-ops* (append *d-ops* (ops 'call1b))) (*occam* occam))
                                       (solve-task task exs 10 30000000))))))
    (unless occam
      (loop for n in '("len-all" "last-or")
            collect (let* ((task (spec-task n)) (exs (spec-exs n)) (base (make-base :n (length exs)))
                           (leaves (input-cols task exs)) (ys (map 'simple-vector #'cdr exs)))
                      (list (format nil "spec ~a (scalar)" n) task
                            (lambda () (solve-scalar base leaves ys 9 3000000)))))))))

(defparameter *q3* '(par mod3 sgn))
(defparameter *cfg-first* `(:mode :first :qs ,*q3*))
(defparameter *cfg-audit* `(:mode :audit :qs ,*q3*))
(defparameter *single* '("reverse" "rotate-left k" "map-adjacent +" "map-adjacent -" "positions-of v" "filter x>k"
                         "take k" "zip-add" "map-adjacent f (spec)"))
(defparameter *guarded* '("shift-seq (spec)" "running-sum" "scan + init a (spec)" "scan 2*acc-x init a"
                          "scan f init a (spec)"))

(defun compare (tasks cfgs &key (reps 3) (plain t) quiet)
  "For each task: plain, then each (label . cfg).  Returns ((name plain-res (label . res) ...) ...).
   QUIET prints a line only when a program differs from plain's, is lost, or the audit finds a false reject."
  (unless quiet (header))
  (loop for (name task thunk) in tasks
        collect (let ((base (and plain (lrun nil thunk :reps reps))))
                  (when (and base (not quiet)) (row name "plain" base task))
                  (list* name base
                         (loop for (label . cfg) in cfgs
                               collect (let ((r (lrun cfg thunk :reps reps)))
                                         (when (or (not quiet) (plusp (tot r 7))
                                                   (and base (not (equal (res-prog r) (res-prog base)))))
                                           (row name label r task base))
                                         (cons label r)))))))
(defun gmean (xs) (if xs (exp (/ (loop for x in xs sum (log x)) (length xs))) 0))
(defun summary (results label &key (min-cand 1) (tag ""))
  "Totals and geometric-mean gains of configuration LABEL over plain."
  (let* ((rs (remove-if-not (lambda (e) (and (second e) (>= (res-cand (second e)) min-cand))) results))
         (pairs (loop for e in rs collect (cons (second e) (cdr (assoc label (cddr e) :test #'equal))))))
    (flet ((sum (f which) (loop for p in pairs sum (funcall f (funcall which p)))))
      (format t "SUMMARY ~a~a vs plain, ~d tasks (plain cand >= ~d): cand ~d -> ~d (total ~,2fx, geo-mean ~,2fx); ~
                 work ~d -> ~d (total ~,2fx, geo-mean ~,2fx); ~
                 ms ~,1f -> ~,1f (total ~,2fx, geo-mean ~,2fx); classes held ~d -> ~d (~,2fx); look-ups ~d; ~
                 programs changed ~d; lost ~d; false rejects ~d~%"
              tag label (length pairs) min-cand (sum #'res-cand #'car) (sum #'res-cand #'cdr)
              (/ (sum #'res-cand #'car) (max 1 (sum #'res-cand #'cdr)) 1.0)
              (gmean (loop for p in pairs collect (/ (max 1 (res-cand (car p))) (max 1 (res-cand (cdr p))) 1.0)))
              (sum #'work #'car) (sum #'work #'cdr) (/ (sum #'work #'car) (max 1 (sum #'work #'cdr)) 1.0)
              (gmean (loop for p in pairs collect (/ (max 1 (work (car p))) (max 1 (work (cdr p))) 1.0)))
              (/ (sum #'res-us #'car) 1000.0) (/ (sum #'res-us #'cdr) 1000.0)
              (/ (sum #'res-us #'car) (max 1 (sum #'res-us #'cdr)) 1.0)
              (gmean (loop for p in pairs collect (/ (max 1 (res-us (car p))) (max 1 (res-us (cdr p))) 1.0)))
              (sum #'peak-classes #'car) (sum #'peak-classes #'cdr)
              (/ (sum #'peak-classes #'car) (max 1 (sum #'peak-classes #'cdr)) 1.0)
              (loop for p in pairs sum (tot (cdr p) 5))
              (count-if-not (lambda (p) (equal (res-prog (car p)) (res-prog (cdr p)))) pairs)
              (count-if (lambda (p) (and (ok-prog (res-prog (car p))) (not (ok-prog (res-prog (cdr p)))))) pairs)
              (loop for p in pairs sum (tot (cdr p) 7))))))

;;; ---- E0: the tables -------------------------------------------------------------------------
(defun wide-check (op q)
  "Soundness of a table beyond its grid: evaluate OP on integers -40..40 plus 60 large random values
   (and, for sequences, 400 fresh random sequences); count probes whose output label is not in the table."
  (let* ((rs (sb-ext:seed-random-state 77)) (vt (verb-table op q)) (bad 0) (n 0)
         (ints (append '(:err) (loop for v from -40 to 40 collect v)
                       (loop repeat 60 collect (- (random 20001 rs) 10000))))
         (seqs (cons nil (loop repeat 400 collect (loop repeat (rnd rs 1 12) collect (rnd rs -9 12)))))
         (types (op-args op)))
    (flet ((vals (ty) (ecase ty (:int ints) (:seq seqs) (:bool '(:t :f :err)) (:code '(+ - *)) (:pred '(pos even neg))))
           (test (x y z)
             (let ((idx (+ (cell-label q (first types) x)
                           (if (second types) (* (vt-n1 vt) (cell-label q (second types) y)) 0)
                           (if (third types) (* (vt-n12 vt) (cell-label q (third types) z)) 0))))
               (incf n)
               (unless (logbitp (cell-label q (op-res op) (cell-apply op x y z)) (svref (vt-tab vt) idx))
                 (incf bad)))))
      (dolist (x (vals (first types)))
        (if (null (cdr types)) (test x nil nil)
            (dolist (y (vals (second types)))
              (if (null (cddr types)) (test x y nil)
                  (dolist (z (vals (third types))) (test x y z)))))))
    (values bad n)))
(defun e0 ()
  (dolist (grid '((-12 12) (-3 3)))
    (let ((*grid* grid))
      (format t "~%=== E0. Verb tables: one group-by over joint probes; integer grid ~a (+ the undefined cell); ~d probe sequences ===~%"
              *grid* (length (probe-seqs)))
      (format t "singleton = input-label combinations with exactly one defined output label; anything = combinations that~%")
      (format t "rule no defined label out; useless = the whole table rules nothing out; unsound/n = probes on a WIDER range~%")
      (format t "(-40..40, 60 values up to +-10000, 400 fresh sequences) whose output label the table does not list.~%")
      (dolist (seqlab '(nil t))
        (format t "~%--- sequences labelled by ~a ---~%"
                (if seqlab "the SET of their elements' labels" "nothing (one label)"))
        (format t "~8a ~5a ~8a ~8a ~10a ~9a ~8a ~9a ~10a~%" "op" "quot" "probes" "entries" "singleton" "anything" "useless" "dep-score" "unsound/n")
        (dolist (op (append *d-ops* (ops 'call1b 'neg 'div 'if 'len)))
          (dolist (qn '(def par mod3 sgn))
            (unless (and seqlab (not (member :seq (op-args op))))
              (let* ((q (make-q qn seqlab)) (vt (verb-table op q))
                     (nonerr (1- (ash 1 (1- (nlab q (op-res op)))))))
                (multiple-value-bind (bad n) (wide-check op q)
                  (format t "~8a ~5a ~8d ~8d ~10d ~9d ~8a ~9,3f ~d/~d~%" (op-name op) qn (vt-nprobe vt) (length (vt-tab vt))
                          (count-if (lambda (m) (and (/= m -1) (= 1 (logcount (logand m nonerr))))) (vt-tab vt))
                          (count-if (lambda (m) (= (logand m nonerr) nonerr)) (vt-tab vt))
                          (if (vt-trivial vt) "yes" "no") (vt-dep vt) bad n)))))))
      (format t "~%pair table for AT (index below / inside / above the sequence / undefined; 1 = defined seen, 2 = undefined seen): ~a~%"
              (pair-table (first (ops 'at))))))
  (clrhash *vts*) (setf *probe-seqs* nil)
  (let ((t0 (now-us)))
    (dolist (op (append *d-ops* (ops 'call1b))) (dolist (qn *q3*) (verb-table op (make-q qn nil))))
    (format t "~%build time, 13 operators x 3 quotients, grid -12..12, sequences unlabelled: ~,1f ms~%" (/ (- (now-us) t0) 1000.0)))
  (let ((t0 (now-us)))
    (dolist (op (ops 'at)) (dolist (qn *q3*) (verb-table op (make-q qn t))) (pair-table op))
    (format t "build time, AT with sequence labels x 3 quotients + pair table: ~,1f ms~%" (/ (- (now-us) t0) 1000.0))))

;;; ---- E1: with and without the filter --------------------------------------------------------
(defparameter *cfgs-main*
  `(("first" . ,*cfg-first*)                       ; label-feasible candidates of a level first (stored), then the rest
    ("lfprobe" :mode :lfprobe :qs ,*q3*)           ; label test, then exact row-by-row test; nothing stored; then the plain pass
    ("probe" :mode :probe :qs ())                  ; NO labels: exact row-by-row test of every candidate; then the plain pass
    ("audit" . ,*cfg-audit*)))                     ; plain search, every candidate tested, false rejects counted
(defun summaries (r &optional (tag ""))
  (dolist (l '("first" "lfprobe" "probe")) (summary r l :tag tag))
  (dolist (l '("first" "lfprobe" "probe")) (summary r l :tag tag :min-cand 20000))
  (summary r "audit" :tag tag))
(defun e1 ()
  (format t "=== E1. With and without the filter.  All modes keep every answer reachable: within a size level they test first,~%")
  (format t "and evaluate the rest of the level afterwards unless the answer was found. ===~%")
  (format t "first   = label-feasible candidates are evaluated and stored first, then the others (class order changes).~%")
  (format t "lfprobe = label test, then an exact row-by-row test against the target (stop at the first mismatch) on what~%")
  (format t "          the labels let through; nothing is stored unless it is the answer; then the plain pass in plain order.~%")
  (format t "probe   = the same with NO labels: the exact row-by-row test on every candidate of the target's type.~%")
  (format t "audit   = plain search with every candidate label-tested: a FALSE REJECT is a ruled-out candidate equal to the target.~%")
  (format t "quotients ~a on integers; sequences unlabelled (AT says 'anything' unless the index is negative); all rows checked.~%" *q3*)
  (format t "times: fastest of 3 runs, full GC before each.~%")
  (format t "~%--- (a) the prototype's 15 tasks, seed 1, 12 examples ---")
  (summaries (compare (proto-tasks) *cfgs-main*))
  (format t "~%--- (b) the kernel's :spec rows, default split policy (first fit) ---")
  (summaries (compare (spec-tasks) *cfgs-main*))
  (format t "~%--- (c) the kernel's :spec rows, size-ordered split acceptance (*occam*); a held split bounds the size ---")
  (summaries (compare (spec-tasks :occam t) *cfgs-main*)))

;;; ---- E2: which quotient does the work; AT variants; how many rows -----------------------------
(defun matrix (tasks cfgs &key (reps 1))
  "One line per configuration: per task the candidates evaluated; then totals."
  (let ((plain (loop for (nil nil thunk) in tasks collect (lrun nil thunk :reps reps))))
    (format t "~26a~{ ~11a~} | ~10a ~10a ~7a ~11a ~9a ~4a~%" "config"
            (mapcar (lambda (e) (subseq (first e) 0 (min 11 (length (first e))))) tasks)
            "total-cand" "look-ups" "lk/gat" "work" "ms" "chg")
    (format t "~26a~{ ~11d~} | ~10d ~10a ~7a ~11d ~9,1f~%" "plain" (mapcar #'res-cand plain)
            (reduce #'+ plain :key #'res-cand) "-" "-" (reduce #'+ plain :key #'work)
            (/ (reduce #'+ plain :key #'res-us) 1000.0))
    (loop for (label . cfg) in cfgs do
      (let* ((rs (loop for (nil nil thunk) in tasks collect (lrun cfg thunk :reps reps)))
             (look (loop for r in rs sum (tot r 5))) (gated (loop for r in rs sum (+ (tot r 2) (tot r 3)))))
        (format t "~26a~{ ~11d~} | ~10d ~10d ~7a ~11d ~9,1f ~4d~%" label (mapcar #'res-cand rs)
                (reduce #'+ rs :key #'res-cand) look
                (if (plusp gated) (format nil "~,2f" (/ look gated 1.0)) "-")
                (reduce #'+ rs :key #'work)
                (/ (reduce #'+ rs :key #'res-us) 1000.0)
                (loop for r in rs for p in plain count (not (equal (res-prog r) (res-prog p)))))
        (finish-output)))))
(defun last-level-pass (tasks cfg)
  "Per task, in the level where the answer is found: of the candidates that reached a table, the share
   the tables could not rule out; and look-ups per such candidate."
  (loop for (name nil thunk) in tasks
        collect (let* ((r (lrun cfg thunk)) (b (main-bank r)) (fin (getf b :final))
                       (l (find (getf b :done) (getf b :levels) :key #'first))
                       (feas (- (nth 2 fin) (if l (nth 3 l) 0))) (skip (- (nth 3 fin) (if l (nth 4 l) 0)))
                       (look (- (nth 5 fin) (if l (nth 6 l) 0))))
                  (list name feas skip look))))
(defun e2 ()
  (let ((tasks (proto-tasks :only *single*)))
    (format t "=== E2. Ablation on the nine tasks answered by a single class (seed 1).  Mode :first.  Cells: candidates evaluated. ===~%")
    (format t "~%--- (a) which quotient does the work (sequences unlabelled, all rows) ---~%")
    (matrix tasks `(("types only" :mode :first :qs ())
                    ("def (defined or not)" :mode :first :qs (def))
                    ("par" :mode :first :qs (par)) ("mod3" :mode :first :qs (mod3)) ("sgn" :mode :first :qs (sgn))
                    ("par+mod3" :mode :first :qs (par mod3))
                    ("par+mod3+sgn" :mode :first :qs ,*q3*)
                    ("lfprobe par+mod3+sgn" :mode :lfprobe :qs ,*q3*)
                    ("lfprobe par" :mode :lfprobe :qs (par))
                    ("probe (no labels)" :mode :probe :qs ()))
            :reps 3)
    (format t "~%--- (b) the AT table: 'anything' / + the pair quotient (index inside the sequence?) / + sequence labels ---~%")
    (matrix tasks `(("q3, AT anything" :mode :first :qs ,*q3*)
                    ("q3 + pair" :mode :first :qs ,*q3* :pair t)
                    ("q3 + seq labels" :mode :first :qs ,*q3* :seqlab t)
                    ("q3 + pair + seq labels" :mode :first :qs ,*q3* :pair t :seqlab t))
            :reps 3)
    (format t "~%--- (c) rows checked (evenly spaced over the lifted rows; q3) ---~%")
    (matrix tasks (loop for k in '(1 2 3 4 6 8 12 16 24 nil)
                        collect `(,(format nil "rows ~a" (or k "all")) :mode :first :qs ,*q3* :nchk ,k))
            :reps 3)
    (format t "~%--- (d) sharpness in the level where the answer lies: share of table-tested candidates NOT ruled out, ~
               and look-ups per tested candidate ---~%")
    (format t "~10a~{ ~22a~}~%" "rows" (mapcar #'first tasks))
    (dolist (k '(1 2 4 8 16 nil))
      (format t "~10a~{ ~22a~}~%" (or k "all")
              (loop for (nil feas skip look) in (last-level-pass tasks `(:mode :first :qs ,*q3* :nchk ,k))
                    collect (if (plusp (+ feas skip))
                                (format nil "~d/~d=~,4f% ~,2flk" feas (+ feas skip) (/ (* 100.0 feas) (+ feas skip))
                                        (/ look (+ feas skip) 1.0))
                                "-"))))))

;;; ---- E3: the guard split and the near-miss ---------------------------------------------------
(defun run-keep (cfg thunk)
  "Run THUNK under CFG and keep the main bank: (values program bank target-column)."
  (setf *banks* nil *levels* nil *cand* 0 *cells* 0 *scan* 0 *note* nil)
  (let* ((*lf-cfg* cfg) (*trace* t) (prog (funcall thunk))
         (e (find-if (lambda (e) (member (second e) '(:elem :select))) *banks*)))
    (multiple-value-prog1 (values prog (first e) (fourth e)) (setf *banks* nil *levels* nil))))
(defun find-cls (bank term) (find term (bank-all bank) :key #'cls-term :test #'equal))
(defun matches (c y) (loop for v across (cls-col c) for w across y count (equal v w)))
(defun part-line (bank y name term cfgs)
  "Where a part of the split sits, how many rows it matches, and what each filter would do to the
   candidate that creates it: PASS, or ruled out, with the number of rows the tables allow."
  (let ((c (find-cls bank term)) (n (length y)))
    (cond ((null c) (format t "      ~5a ~40s : not a single class (nested)~%" name term))
          ((= 1 (cls-size c)) (format t "      ~5a ~40s size 1 (a leaf, always present); matches ~d/~d rows~%"
                                      name term (matches c y) n))
          (t (format t "      ~5a ~40s size ~d ~5a matches ~2d/~d rows |" name term (cls-size c) (cls-type c)
                     (if (eq (cls-type c) :int) (matches c y) 0) n)
             (loop for (label . cfg) in cfgs do
               (let* ((*lf-cfg* cfg) (lf (lf-attach bank :int y :audit nil))
                      (op (first (ops (car term)))) (args (mapcar (lambda (a) (find-cls bank a)) (cdr term)))
                      (gate (make-gate-for lf op)))
                 (format t " ~a: ~a;" label
                         (cond ((not (gate-type-ok gate)) "TYPE-OUT")
                               ((feasible-p lf gate (first args) (second args) (third args)) "pass")
                               (t (format nil "OUT (allowed on ~d/~d rows)"
                                          (allow-count lf gate (first args) (second args) (third args)) n))))))
             (setf (bank-lf bank) nil)
             (terpri)))))
(defun e3-one (name task thunk)
  (multiple-value-bind (prog bank y) (run-keep nil thunk)
    (let* ((elem (elem-of prog)) (lv (bank-done bank)) (n (length y))
           (cfgs `(("q3" :qs ,*q3*) ("q3+pair" :qs ,*q3* :pair t) ("def" :qs (def)))))
      (format t "~%## ~a: plain element term after level ~d on ~d rows (held-out ~a):~%   ~s~%" name lv n (ho task prog) elem)
      (when (and (consp elem) (eq (first elem) 'if))
        (destructuring-bind (g u rest) (cdr elem)
          (part-line bank y "guard" g cfgs) (part-line bank y "near" u cfgs) (part-line bank y "else" rest cfgs)
          ;; composition of the plain bank
          (let ((nb 0) (ni 0) (np 0))
            (loop for c across (bank-all bank) do
              (cond ((eq (cls-type c) :bool) (incf nb))
                    ((eq (cls-type c) :int) (if (find :err (cls-col c)) (incf np) (incf ni)))))
            (format t "      plain bank: ~d classes = ~d boolean + ~d integer with an undefined row + ~d integer defined everywhere~%"
                    (length (bank-all bank)) nb np ni))
          ;; how many rows could the candidates of the split's level match, by the tables?
          (let ((m (let ((c (find-cls bank u))) (if c (matches c y) 0))))
            (multiple-value-bind (p2 b2) (run-keep `(:mode :audit :qs ,*q3* :ubhist t :level ,lv) thunk)
              (declare (ignore p2))
              (let* ((h (lf-ubhist (bank-lf b2))) (tot (reduce #'+ h)))
                (flet ((ge (k) (loop for i from (max 0 k) to n sum (svref h i))))
                  (format t "      level ~d has ~d integer-result candidates; the q3 tables allow all ~d rows for ~d (~,2f%), ~
                             >= ~d rows (the near-miss's count) for ~d (~,2f%), >= ~d rows (the else-branch's share) for ~d (~,1f%)~%"
                          lv tot n (ge n) (/ (* 100.0 (ge n)) (max 1 tot)) m (ge m) (/ (* 100.0 (ge m)) (max 1 tot))
                          (- n m) (ge (- n m)) (/ (* 100.0 (ge (- n m))) (max 1 tot))))))))
        ;; now really run the filters
        (flet ((show (label cfg &optional stop)
                 (let* ((r (lrun cfg (lambda () (let ((*lf-stop* stop)) (funcall thunk))) :reps 3))
                        (p (res-prog r)))
                   (format t "      ~34a cand ~8d  spared ~8d  look-ups ~9d  ms ~8,2f  held-out ~8a  ~a~%"
                           label (res-cand r) (spared r) (tot r 5) (/ (res-us r) 1000.0) (ho task p)
                           (cond ((equal p prog) "SAME PROGRAM")
                                 ((not (ok-prog p)) "LOST (no program)")
                                 (t (format nil "CHANGED: ~s" (elem-of p))))))))
          (show "plain" nil)
          (show "first (order only)" *cfg-first*)
          (show (format nil "strict@~d types only" lv) `(:mode :strict :qs () :level ,lv) lv)
          (show (format nil "strict@~d q3" lv) `(:mode :strict :qs ,*q3* :level ,lv) lv)
          (show (format nil "strict@~d q3, guards exempt" lv) `(:mode :strict :qs ,*q3* :level ,lv :keep-bool t) lv)
          (show (format nil "strict@~d q3+pair, guards exempt" lv) `(:mode :strict :qs ,*q3* :pair t :level ,lv :keep-bool t) lv)
          (show (format nil "strict@~d def, guards exempt" lv) `(:mode :strict :qs (def) :level ,lv :keep-bool t) lv)
          (show (format nil "look-ahead@~d q3 + split" lv) `(:mode :la :qs ,*q3* :level ,lv :cover t))
          (show (format nil "look-ahead@~d q3 + split, guards exempt" lv) `(:mode :la :qs ,*q3* :level ,lv :cover t :keep-bool t)))))))
(defun e3 ()
  (format t "=== E3. The guard split against the label filter.  strict@L = at size level L (the level after which plain finds~%")
  (format t "its split: an ORACLE) only label-feasible candidates are evaluated, and the search stops after L.~%")
  (format t "'guards exempt' = boolean-result candidates are never filtered.  look-ahead@L = bound L, classes that no operator~%")
  (format t "can take to the target's labels are not stored, then the split is attempted on what is left. ===~%")
  (loop for (name task thunk) in (append (proto-tasks :only *guarded*)
                                         (spec-tasks :only '("spec scan" "spec shift-seq" "spec last-or (scalar)" "spec map-adjacent")))
        do (e3-one name task thunk)))

;;; ---- E4: goal inversion (the prototype's "computed residual") with and without the filter ----
(defun e4 ()
  (let ((inv (total-inverses *d-ops*)))
    (format t "=== E4. Goal inversion on (inverses ~a, derived by the prototype's experiment C).~%" inv)
    (format t "plain/first here both run WITH inversion; 'no-inv' rows repeat E1 for reference. ===~%")
    (summaries (compare (proto-tasks :inverses inv) *cfgs-main*) "with inversion: ")
    (format t "~%--- strict filter at the level where inversion succeeds, for the tasks inversion solves (oracle level) ---~%")
    (loop for (name task thunk) in (proto-tasks :inverses inv :only '("map-adjacent +" "map-adjacent -" "zip-add")) do
      (let* ((base (lrun nil thunk)) (lv (getf (main-bank base) :done)))
        (dolist (cfg `(("plain" . nil) ("strict q3" :mode :strict :qs ,*q3* :level ,lv)
                       ("look-ahead q3" :mode :la :qs ,*q3* :level ,lv)))
          (let ((r (lrun (cdr cfg) (lambda () (let ((*lf-stop* lv)) (funcall thunk))))))
            (format t "~24a ~16a level ~d cand ~8d classes ~8d held-out ~8a ~a~%" name (car cfg) lv (res-cand r)
                    (peak-classes r) (ho task (res-prog r))
                    (cond ((equal (res-prog r) (res-prog base)) "SAME") ((ok-prog (res-prog r)) "CHANGED") (t "LOST")))))))))

;;; ---- E5: look-ahead (decline to store) --------------------------------------------------------
(defun e5 ()
  (format t "=== E5. Look-ahead: decline to STORE a class that no operator can take to the target's labels. ===~%")
  (format t "~%--- (a) single-class tasks.  la-oracle: the bound is the answer's level, handed over.  la-deepen: bound 2,3,..~%")
  (format t "with a restart from the leaves for each bound, every pass counted; classes = those of the last pass. ---~%")
  (format t "~24a ~22a ~9a ~9a ~9a ~10a ~9a ~8a ~4a~%" "task" "mode" "cand" "classes" "declined" "look-ups" "ms" "held-out" "same")
  (loop for (name task thunk) in (proto-tasks :only (remove "positions-of v" (remove "filter x>k" *single* :test #'string=) :test #'string=)) do
    (let* ((base (lrun nil thunk :reps 3)) (lv (1+ (getf (main-bank base) :done))))
      (flet ((show (label r)
               (format t "~24a ~22a ~9d ~9d ~9d ~10d ~9,2f ~8a ~4a~%" name label (res-cand r) (peak-classes r)
                       (tot r 6) (tot r 5) (/ (res-us r) 1000.0) (ho task (res-prog r))
                       (if (equal (res-prog r) (res-prog base)) "yes" "NO"))
               (finish-output)))
        (show "plain" base)
        (show "first q3" (lrun *cfg-first* thunk :reps 3))
        (show (format nil "la-oracle@~d types" lv) (lrun `(:mode :la :qs () :level ,lv) thunk :reps 3))
        (show (format nil "la-oracle@~d def" lv) (lrun `(:mode :la :qs (def) :level ,lv) thunk :reps 3))
        (show (format nil "la-oracle@~d q3" lv) (lrun `(:mode :la :qs ,*q3* :level ,lv) thunk :reps 3))
        (show "la-deepen q3" (lrun `(:mode :la :qs ,*q3*) thunk :reps 3)))))
  (format t "~%--- (b) guarded tasks under size-ordered split acceptance (*occam*, budget 15M): the held split gives the bound B,~%")
  (format t "no oracle.  first = order within a level, and at B only the label-feasible are evaluated; +la = also decline to~%")
  (format t "store classes that cannot reach the target by B; lfprobe / probe = test first (labels+exact / exact only), and at B~%")
  (format t "nothing but the test. ---~%")
  (let* ((labels '("first" "first+la" "first+la types" "lfprobe" "probe"))
         (r (compare (append (proto-tasks :occam t :limit 15000000 :only *guarded*)
                             (spec-tasks :occam t :only '("spec scan" "spec shift-seq")))
                     `(("first" . ,*cfg-first*) ("first+la" :mode :first :qs ,*q3* :occam-la t)
                       ("first+la types" :mode :first :qs () :occam-la t)
                       ("lfprobe" :mode :lfprobe :qs ,*q3*) ("probe" :mode :probe :qs ()))
                     :reps 1)))
    (dolist (l labels) (summary r l))))

;;; ---- E6: other example sets -------------------------------------------------------------------
(defun e6 ()
  (format t "=== E6. Seeds 2..9 of the prototype's example generator, 15 tasks each: plain / first / lfprobe / probe / audit. ===~%")
  (format t "Lines are printed only where a program differs from plain's, is lost, or the audit finds a false reject.~%")
  (let ((all '()))
    (dolist (seed '(2 3 4 5 6 7 8 9))
      (let ((r (compare (proto-tasks :seed seed) *cfgs-main* :reps 1 :quiet t)))
        (summary r "first" :tag (format nil "seed ~d: " seed))
        (summary r "probe" :tag (format nil "seed ~d: " seed))
        (setf all (append all r))))
    (summaries all "ALL SEEDS: ")
    (flet ((get-r (e label) (cdr (assoc label (cddr e) :test #'equal))))
      (format t "~%per task over the 8 seeds: geo-mean gain in candidates fully evaluated (first, probe), in work (first, lfprobe, probe),~%")
      (format t "in CPU time (first, lfprobe, probe); held-out perfect: plain / first / probe~%")
      (dolist (task *tasks*)
        (let ((es (remove (task-name task) all :key #'first :test-not #'string=)))
          (flet ((g (f label) (gmean (loop for e in es collect (/ (max 1 (funcall f (second e)))
                                                                  (max 1 (funcall f (get-r e label))) 1.0))))
                 (perfect (sel) (count-if (lambda (e) (equal "200/200" (ho task (res-prog (funcall sel e))))) es)))
            (format t "~24a cand ~6,2fx ~6,2fx | work ~6,2fx ~6,2fx ~6,2fx | cpu ~5,2fx ~5,2fx ~5,2fx | ~d/~d ~d/~d ~d/~d~%"
                    (task-name task) (g #'res-cand "first") (g #'res-cand "probe")
                    (g #'work "first") (g #'work "lfprobe") (g #'work "probe")
                    (g #'res-us "first") (g #'res-us "lfprobe") (g #'res-us "probe")
                    (perfect #'second) (length es) (perfect (lambda (e) (get-r e "first"))) (length es)
                    (perfect (lambda (e) (get-r e "probe"))) (length es))))))))

;;; ---- E7: the order of the operator list -------------------------------------------------------
(defun e7 ()
  (format t "=== E7. The gain depends on where the answer's outermost operator sits in the operator list. ===~%")
  (format t "Eight single-class tasks (map-adjacent f left out: 8.5M candidates per run), seed 1; candidates fully evaluated, plain -> first;~%work gains of first, lfprobe, probe over plain (work = cells evaluated + look-ups + label cells).~%")
  (let* ((rs (sb-ext:seed-random-state 5)) (base *d-ops*)
         (orders (flet ((shuffle () (let ((v (coerce base 'vector)))   ; Fisher-Yates, fixed seed
                                      (loop for i from (1- (length v)) downto 1
                                            do (rotatef (aref v i) (aref v (random (1+ i) rs))))
                                      (coerce v 'list))))
                   (list (cons "prototype order" base)
                         (cons "AT first" (cons (first (ops 'at)) (remove 'at base :key #'op-name)))
                         (cons "reversed" (reverse base))
                         (cons "shuffle 1" (shuffle)) (cons "shuffle 2" (shuffle)) (cons "shuffle 3" (shuffle))))))
    (loop for (label . order) in orders do
      (let* ((*d-ops* order)
             (tasks (loop for (name task thunk) in (proto-tasks :only (remove "map-adjacent f (spec)" *single* :test #'string=))
                          collect (let ((thunk thunk)) (list name task (lambda () (let ((*d-ops* order)) (funcall thunk))))))))
        (format t "~%--- ~a: ~a ---~%" label (mapcar #'op-name order))
        (format t "~24a ~10a ~10a ~7a | ~9a ~9a ~9a | ~8a ~4a | ~s~%" "task" "plain" "first" "gain"
                "work-gain" "(lfprobe)" "(probe)" "held-out" "same" "element term (plain)")
        (let ((res (loop for (name task thunk) in tasks
                         collect (let ((p (lrun nil thunk)) (f (lrun *cfg-first* thunk))
                                       (lp (lrun `(:mode :lfprobe :qs ,*q3*) thunk)) (pr (lrun '(:mode :probe :qs ()) thunk)))
                                   (format t "~24a ~10d ~10d ~6,2fx | ~8,2fx ~8,2fx ~8,2fx | ~8a ~4a | ~s~%" name (res-cand p) (res-cand f)
                                           (/ (res-cand p) (max 1 (res-cand f)) 1.0)
                                           (/ (work p) (max 1 (work f)) 1.0) (/ (work p) (max 1 (work lp)) 1.0)
                                           (/ (work p) (max 1 (work pr)) 1.0) (ho task (res-prog f))
                                           (if (and (equal (res-prog p) (res-prog f)) (equal (res-prog p) (res-prog lp))
                                                    (equal (res-prog p) (res-prog pr)))
                                               "yes" "NO")
                                           (elem-of (res-prog p)))
                                   (finish-output)
                                   (list name p (cons "first" f) (cons "lfprobe" lp) (cons "probe" pr))))))
          (dolist (l '("first" "lfprobe" "probe")) (summary res l :tag (format nil "~a: " label))))))))

(defun noop () (format t "loaded~%"))     ; ./run.sh noop : a load / compile check

;;; ---- entry point ----------------------------------------------------------------------------
(defun l1-main (fn)
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase) (t0 (now-us)))
    (funcall fn)
    (format t "~%[~a finished in ~,1f s]~%" fn (/ (- (now-us) t0) 1d6))
    (finish-output)))
