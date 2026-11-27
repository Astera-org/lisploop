;;;; xs-m1.lisp -- M1: do store-generated signatures prioritize inter-task mixing?
;;;; Loaded AFTER the unmodified tg-probe.lisp (see run.sh).  Everything is seeded.
;;;;
;;;; (a) signature = the set of generic Boolean classes that are true on every
;;;;     example row of a task; (b) leave-one-out retrieval by Jaccard;
;;;; (c) does a grammar restricted to the 3 nearest neighbours' operators save search?
(in-package :tg)
(declaim (optimize (speed 1) (safety 1) (debug 1)))

;;; ------------------------------------------------------------------
;;; Task pool: the prototype's 15 sequence tasks + its 3 fold tasks + 12 of mine.
;;; ------------------------------------------------------------------
(defparameter *own-seq-tasks*
  (list
   ;; intended form: tabulate with a guard
   (tk "shift-right k" '((xs :seq) (k :int 0 3))                  ; shift right by k, zero fill
       (lambda (xs k) (loop for i below (length xs) collect (if (< i k) 0 (nth (- i k) xs)))))
   (tk "prepend k" '((xs :seq) (k :int -5 9)) (lambda (xs k) (cons k xs)))
   (tk "append k" '((xs :seq) (k :int -5 9)) (lambda (xs k) (append xs (list k))))
   ;; intended form: recurrence on the previous output
   (tk "running-max" '((xs :seq))
       (lambda (xs) (let ((a nil)) (loop for x in xs collect (setf a (if a (max a x) x))))))
   ;; intended form: select
   (tk "remove v" '((xs :seq) (v :elt)) (lambda (xs v) (remove v xs)))
   (tk "keep positive" '((xs :seq)) (lambda (xs) (remove-if-not #'plusp xs)))
   (tk "keep even x" '((xs :seq)) (lambda (xs) (remove-if-not #'evenp xs)))
   ;; intended form: where
   (tk "positions x>k" '((xs :seq) (k :int -3 7))
       (lambda (xs k) (loop for x in xs for j from 0 when (> x k) collect j)))
   (tk "positions of negatives" '((xs :seq))
       (lambda (xs) (loop for x in xs for j from 0 when (< x 0) collect j)))
   (tk "positions of even x" '((xs :seq))
       (lambda (xs) (loop for x in xs for j from 0 when (evenp x) collect j)))))
(defparameter *own-fold-tasks*            ; intended form: scalar fold
  (list (tk "product" '((xs :seq)) (lambda (xs) (reduce #'* xs)) :int)
        (tk "sum of squares" '((xs :seq)) (lambda (xs) (reduce #'+ (mapcar (lambda (x) (* x x)) xs))) :int)))
(defparameter *excluded-tasks*            ; tried, and dropped: the FULL grammar returns impostors (see log)
  (list (list (tk "keep a<x<b" '((xs :seq) (a :int -3 2) (b :int 3 8))
                  (lambda (xs a b) (remove-if-not (lambda (x) (< a x b)) xs)))
              '(and <))
        (list (tk "keep x<=k" '((xs :seq) (k :int -3 7)) (lambda (xs k) (remove-if-not (lambda (x) (<= x k)) xs)))
              '(not <))
        (list (tk "max with floor k" '((xs :seq) (k :int -5 9))
                  (lambda (xs k) (reduce #'max xs :initial-value k)) :int)
              '(max))
        (list (tk "max with floor 0" '((xs :seq)) (lambda (xs) (reduce #'max xs :initial-value 0)) :int)
              '(max))))
(defparameter *intended*                  ; my intent per task, printed next to the form the solver emits
  '(:tab :tabg :tab :tab :tab :rec :rec :rec :tab :where :sel :tab :tab :tab :rec     ; the prototype's 15
    :tabg :tabg :tabg :rec :sel :sel :sel :where :where :where                        ; my 10 sequence tasks
    :fold :fold :fold :fold :fold))                                                   ; 3 prototype folds + my 2
(defun m1-pool () (append *tasks* *own-seq-tasks* *fold-tasks* *own-fold-tasks*))

;;; ------------------------------------------------------------------
;;; The prototype's standard procedure, as one entry point.
;;; ------------------------------------------------------------------
(defvar *full-ops* (mapcar #'op-name *d-ops*))   ; the 12-operator element grammar
(defvar *route1* 0)                              ; candidates spent on the route tried first
(defvar *order* :std)                            ; :alt = try the second route first (used only in (c2))
(defun solve-any (task exs max-size limit)
  "Sequence output: SOLVE-TABULATE, then SOLVE-SELECT (= the prototype's SOLVE-TASK).
   Integer output: SOLVE-SCALAR (size<=9, 3M), then SOLVE-FOLD (3M), as in EXP-D."
  (let ((base (make-base :n (length exs))) (leaves (input-cols task exs))
        (ys (map 'simple-vector #'cdr exs)))
    (flet ((r1 (x) (setf *route1* *cand*) x)
           (tab () (solve-tabulate base leaves ys max-size limit))
           (sel () (solve-select base leaves ys max-size limit))
           (sca () (solve-scalar base leaves ys 9 (min limit 3000000)))
           (fol () (solve-fold task exs (min limit 3000000))))
      (if (eq (task-out task) :int)
          (if (eq *order* :std) (or (r1 (sca)) (fol)) (or (r1 (fol)) (sca)))
          (if (eq *order* :std) (or (r1 (tab)) (sel)) (or (r1 (sel)) (tab)))))))

(defstruct res prog score cand ms route1)
(defun res-ok (r) (eql (res-score r) 200))
(defun res-status (r) (cond ((res-ok r) "ok") ((res-prog r) "IMPOSTOR") (t "fail")))
(defvar *cache* (make-hash-table :test 'equal))  ; (example-set task order . operators) -> res; runs are deterministic
(defun solve-with (tag task exs opnames &key (max-size 10) (limit 12000000) (order :std))
  "The standard procedure with the element grammar restricted to OPNAMES.
   TAG names the example set (for the cache only)."
  (let* ((names (remove-if-not (lambda (o) (member o opnames)) *full-ops*))
         (key (list* tag (task-name task) order names)))
    (or (gethash key *cache*)
        (setf (gethash key *cache*)
              (let ((*d-ops* (apply #'ops names)) (*order* order))
                (destructuring-bind (prog cand cells ms notes scan)
                    (timed (lambda () (solve-any task exs max-size limit)))
                  (declare (ignore cells notes scan))
                  (make-res :prog prog :score (and prog (verify task prog)) :cand cand :ms ms
                            :route1 *route1*)))))))

;;; --- reading a solution: its form and its operators ---
(defun heads (e) (when (consp e) (cons (car e) (loop for a in (cdr e) append (heads a)))))
(defun atoms (e) (if (consp e) (loop for a in e append (atoms a)) (list e)))
(defun prog-body (p)                      ; the term the element grammar produced (lambda body)
  (if (and (consp p) (member (car p) '(tabulate select where fold foldr))) (third (third p)) p))
(defun prog-form (p)
  (cond ((null p) :none)
        ((atom p) :scalar)
        (t (case (car p)
             (tabulate (let ((b (atoms (prog-body p))))
                         (cond ((member 'prev b) :rec) ((member 'if b) :tabg) (t :tab))))
             (select :sel) (where :where) ((fold foldr) :fold) (t :scalar)))))
(defun prog-ops (p)                       ; operators of the 12-op grammar in the body (IF is not one)
  (remove-duplicates (remove-if-not (lambda (h) (member h *full-ops*)) (heads (prog-body p)))))
(defun grammar-of (opsets) (remove-duplicates (cons 'at (apply #'append opsets))))

;;; ------------------------------------------------------------------
;;; (a) Signatures.  ONE space: 64 generic probe rows, then every task's
;;; example rows.  Generic leaves are columns on it (:err where a task has no
;;; such input/output).  The prototype's enumerator builds the Boolean classes;
;;; a class is a PROPERTY, and it HOLDS for a task when its column, restricted
;;; to that task's rows (a fiber of the space), has no :f and is :t on at least
;;; half of them.  Class identity on the shared space is the canonical name:
;;; terms equal on the probe rows and on every task row are one property.
;;; ------------------------------------------------------------------
(defun ex-row (task ex)
  "Generic view of an example: (sequence-inputs integer-inputs output-seq output-int)."
  (let (seqs ints)
    (loop for spec in (task-ins task) for (nil . v) in (car ex)
          do (case (second spec) (:seq (push v seqs)) ((:int :elt) (push v ints))))
    (list (nreverse seqs) (nreverse ints)
          (if (eq (task-out task) :seq) (cdr ex) :none)
          (if (eq (task-out task) :int) (cdr ex) :none))))
(defun agg (kind s)
  (if (eq s :none) :err
      (ecase kind
        (len (length s)) (sum (reduce #'+ s))
        (min (if s (reduce #'min s) :err)) (max (if s (reduce #'max s) :err))
        (first (if s (first s) :err)) (last (if s (car (last s)) :err)))))
(defun sig-leaf-specs (nseq nint in-fl)
  "((term function-of-row) ...): constants, per sequence input len/sum/min/max
   (+ first/last when IN-FL), integer inputs, the output's len/first/last/sum/min/max,
   and the output itself when it is an integer."
  (append
   (list (list 0 (constantly 0)) (list 1 (constantly 1)))
   (loop for k below nseq for nm = (intern (format nil "S~d" (1+ k)) :tg)
         append (loop for kind in (if in-fl '(len sum min max first last) '(len sum min max))
                      collect (let ((k k) (kind kind))
                                (list (list kind nm)
                                      (lambda (r) (agg kind (if (< k (length (first r))) (nth k (first r)) :none)))))))
   (loop for k below nint
         collect (let ((k k)) (list (intern (format nil "N~d" (1+ k)) :tg)
                                    (lambda (r) (if (< k (length (second r))) (nth k (second r)) :err)))))
   (loop for kind in '(len first last sum min max)
         collect (let ((kind kind)) (list (list kind 'out) (lambda (r) (agg kind (third r))))))
   (list (list 'outv (lambda (r) (if (eq (fourth r) :none) :err (fourth r)))))))

(defstruct sig name pool ntaut nbool sets leafsets cand cells ms)
(defun signatures (name tasks exsets &key arith (max-size 3) in-fl (nprobe 64) (probe-seed 77))
  (let* ((t0 (now))
         (nseq (reduce #'max tasks :key (lambda (tk) (count :seq (task-ins tk) :key #'second))))
         (nint (reduce #'max tasks :key (lambda (tk) (count-if (lambda (s) (member (second s) '(:int :elt)))
                                                                (task-ins tk)))))
         (rs (sb-ext:seed-random-state probe-seed))
         (rseq (lambda () (loop repeat (rnd rs 0 7) collect (rnd rs -5 9))))
         (rows (append (loop repeat nprobe
                             collect (list (loop repeat nseq collect (funcall rseq))
                                           (loop repeat nint collect (rnd rs -5 9))
                                           (funcall rseq) (rnd rs -5 9)))
                       (loop for task in tasks for exs in exsets
                             append (mapcar (lambda (ex) (ex-row task ex)) exs))))
         (starts (let ((a nprobe)) (loop for exs in exsets collect a do (incf a (length exs)))))
         (bank (new-bank (make-base :n (length rows)) nil))
         (cmp (ops '= '<)) (leafcls '()))
    (loop for (term fn) in (sig-leaf-specs nseq nint in-fl)
          do (push (add-leaf bank term :int (map 'simple-vector fn rows)) leafcls))
    (setf (bank-ops bank) (append (apply #'ops arith) cmp)) (run bank (- max-size 2))
    (setf (bank-ops bank) cmp) (run bank max-size)
    (flet ((counts (c a n) (let ((nt 0) (nf 0))
                             (loop for r from a below (+ a n)
                                   do (case (svref (cls-col c) r) (:t (incf nt)) (:f (incf nf))))
                             (values nt nf))))
      (let* ((bools (remove :bool (coerce (bank-all bank) 'list) :key #'cls-type :test-not #'eq))
             (pool (remove-if (lambda (c) (multiple-value-bind (nt nf) (counts c 0 nprobe)   ; true wherever
                                            (declare (ignore nt)) (zerop nf)))               ; defined on generic rows
                              bools)))
        (make-sig :name name :pool (coerce pool 'simple-vector) :nbool (length bools)
                  :ntaut (- (length bools) (length pool))
                  :sets (loop for a in starts for exs in exsets
                              collect (let ((bv (make-array (length pool) :element-type 'bit :initial-element 0))
                                            (n (length exs)))
                                        (loop for c in pool for k from 0
                                              do (multiple-value-bind (nt nf) (counts c a n)
                                                   (when (and (zerop nf) (>= (* 2 nt) n)) (setf (sbit bv k) 1))))
                                        bv))
                  ;; type-only baseline: which generic leaves exist for the task at all
                  :leafsets (loop for a in starts for exs in exsets
                                  collect (let ((bv (make-array (length leafcls) :element-type 'bit :initial-element 0)))
                                            (loop for c in leafcls for k from 0
                                                  do (when (find-if-not (lambda (v) (eq v :err)) (cls-col c)
                                                                        :start a :end (+ a (length exs)))
                                                       (setf (sbit bv k) 1)))
                                            bv))
                  :cand (bank-ncand bank) :cells (bank-ncells bank) :ms (round (* 1000 (- (now) t0))))))))

(defun jaccard (a b)
  (let ((u (count 1 (bit-ior a b)))) (if (zerop u) 0d0 (/ (count 1 (bit-and a b)) (float u 1d0)))))
(defun mean (xs) (if xs (/ (reduce #'+ xs) (float (length xs) 1d0)) 0d0))
(defun geomean (xs) (exp (mean (mapcar (lambda (x) (log (max x 1d-12))) xs))))

;;; ------------------------------------------------------------------
;;; (b) Leave-one-out retrieval.  Ties are handled exactly (expected value
;;; under a random tie-break), never by task order.
;;; ------------------------------------------------------------------
(defun retrieval (sets rel)
  "SETS: one bit-vector per task.  REL: (i j) -> true when j is relevant to i.
   Returns (nn-hit-rate chance-nn mean-first-rank chance-first-rank n-evaluable)."
  (let ((n (length sets)) hits chance ranks crank)
    (dotimes (i n)
      (let* ((others (remove i (loop for j below n collect j)))
             (sim (mapcar (lambda (j) (jaccard (nth i sets) (nth j sets))) others))
             (rl (mapcar (lambda (j) (and (funcall rel i j) t)) others))
             (k (count t rl)))
        (when (plusp k)
          (let* ((top (reduce #'max sim))
                 (m (count top sim)) (h (loop for s in sim for r in rl count (and r (= s top))))
                 (best (loop for s in sim for r in rl when r maximize s))
                 (g (loop for s in sim for r in rl count (and (not r) (> s best))))
                 (tie (loop for s in sim for r in rl count (and (not r) (= s best))))
                 (same (loop for s in sim for r in rl count (and r (= s best)))))
            (push (/ h m) hits) (push (/ k (- n 1)) chance)
            (push (+ 1 g (/ tie (+ same 1))) ranks) (push (/ n (+ k 1)) crank)))))
    (list (mean hits) (mean chance) (mean ranks) (mean crank) (length hits))))

(defun neighbours (sets i prio &optional (k 3))
  "The K most similar other tasks; ties broken by the seeded priorities PRIO."
  (let ((others (remove i (loop for j below (length sets) collect j))))
    (subseq (sort others (lambda (a b)
                           (let ((sa (jaccard (nth i sets) (nth a sets))) (sb (jaccard (nth i sets) (nth b sets))))
                             (or (> sa sb) (and (= sa sb) (< (nth a prio) (nth b prio)))))))
            0 k)))


;;; ------------------------------------------------------------------
;;; Replicates: one example set per task, every task with its OWN seed.
;;; ------------------------------------------------------------------
(defstruct rep id exsets full forms opsets p3 p5 p3f variants)

(defun pick-classes (sig pred)
  "The signature sets of SIG restricted to the pool classes that satisfy PRED."
  (let ((keep (loop for c across (sig-pool sig) for k from 0 when (funcall pred c) collect k)))
    (mapcar (lambda (s) (map 'simple-bit-vector (lambda (k) (sbit s k)) keep)) (sig-sets sig))))
(defun mentions-out (c) (intersection '(out outv) (atoms (cls-term c))))

(defun make-replicate (id tasks seed-of nex limit)
  (let* ((exsets (loop for tk in tasks for i from 0 collect (gen-examples tk (funcall seed-of i) nex 7)))
         (full (loop for tk in tasks for exs in exsets collect (solve-with id tk exs *full-ops* :limit limit)))
         (p3 (signatures "P3" tasks exsets))
         (p5 (signatures "P5" tasks exsets :arith '(+ -) :max-size 5))
         (p3f (signatures "P3f" tasks exsets :in-fl t))
         (ex48 (loop for tk in tasks for i from 0 collect (gen-examples tk (+ 500000 (funcall seed-of i)) 48 7))))
    (make-rep :id id :exsets exsets :full full
              :forms (mapcar (lambda (r) (prog-form (res-prog r))) full)
              :opsets (mapcar (lambda (r) (prog-ops (res-prog r))) full)
              :p3 p3 :p5 p5 :p3f p3f
              :variants (list (cons "P3  {= <}, size 3" (sig-sets p3))
                              (cons "P5  {+ - = <}, size<=5" (sig-sets p5))
                              (cons "P3f = P3 + first/last of inputs" (sig-sets p3f))
                              (cons "P3 minus input-only properties" (pick-classes p3 #'mentions-out))
                              (cons "P5 minus input-only properties" (pick-classes p5 #'mentions-out))
                              (cons "P5 equalities only" (pick-classes p5 (lambda (c) (eq '= (car (cls-term c))))))
                              (cons "type only (which leaves exist)" (sig-leafsets p3))
                              (cons "P3 from 48 other examples/task" (sig-sets (signatures "P3" tasks ex48)))
                              (cons "P5 from 48 other examples/task"
                                    (sig-sets (signatures "P5" tasks ex48 :arith '(+ -) :max-size 5)))))))

(defun rel-form (rep) (lambda (i j) (eq (nth i (rep-forms rep)) (nth j (rep-forms rep)))))
(defun rel-ops (rep)
  (let ((noat (mapcar (lambda (s) (remove 'at s)) (rep-opsets rep))))
    (lambda (i j) (>= (* 2 (length (intersection (nth i noat) (nth j noat)))) (length (nth i noat))))))
(defun priorities (n) (let ((rs (sb-ext:seed-random-state 4242))) (loop repeat n collect (random 1d0 rs))))
(defun coverage (rep sets)
  "(share of tasks whose NN3 grammar contains every operator of their own solution,
    the exact expectation of the same for 3 random other tasks)."
  (let* ((n (length sets)) (ops (rep-opsets rep)) (prio (priorities n)))
    (list (mean (loop for i below n
                      collect (if (subsetp (nth i ops)
                                           (grammar-of (mapcar (lambda (j) (nth j ops)) (neighbours sets i prio))))
                                  1 0)))
          (mean (loop for i below n collect
                  (let ((others (remove i (loop for j below n collect j))) (hit 0) (tot 0))
                    (loop for (a . r1) on others do
                      (loop for (b . r2) on r1 do
                        (loop for c in r2 do
                          (incf tot)
                          (when (subsetp (nth i ops) (grammar-of (list (nth a ops) (nth b ops) (nth c ops))))
                            (incf hit)))))
                    (/ hit tot)))))))

(defun coverage-k (rep sets k &optional (draws 2000))
  "ADDED: for the K nearest neighbours: (share of tasks whose own operators are all
   in the neighbours' grammar, the same for K random other tasks (DRAWS seeded draws
   per task), mean size of the neighbours' grammar)."
  (let* ((n (length sets)) (ops (rep-opsets rep)) (prio (priorities n)) (rs (sb-ext:seed-random-state 777))
         (gs (loop for i below n
                   collect (grammar-of (mapcar (lambda (j) (nth j ops)) (neighbours sets i prio k))))))
    (list (mean (loop for i below n for g in gs collect (if (subsetp (nth i ops) g) 1 0)))
          (mean (loop for i below n collect
                  (let ((others (coerce (remove i (loop for j below n collect j)) 'simple-vector)) (hit 0))
                    (dotimes (d draws)
                      (dotimes (q k) (rotatef (svref others q) (svref others (+ q (random (- (length others) q) rs)))))
                      (when (subsetp (nth i ops) (grammar-of (loop for q below k collect (nth (svref others q) ops))))
                        (incf hit)))
                    (/ hit draws))))
          (mean (mapcar #'length gs)))))

;;; ------------------------------------------------------------------
;;; (c) Restricted grammars.
;;; ------------------------------------------------------------------
(defun fair (r full cap)
  "Honest cost of 'restricted attempt, capped at CAP candidates, then the full
   grammar if it did not return a held-out-correct program'."
  (if (and (res-ok r) (<= (res-cand r) cap))
      (res-cand r)
      (+ (min cap (res-cand r)) (res-cand full))))
(defparameter *caps* (list most-positive-fixnum 1000000 100000 10000))
(defun short (name) (subseq name 0 (min 14 (length name))))

(defun freq-grammar (rep i k)
  "ADDED control: {at} + the K operators that occur in the most OTHER tasks' solutions
   (ties in grammar order).  It uses the pool but no signature."
  (let ((cnt (mapcar (lambda (o) (cons o (loop for s in (rep-opsets rep) for j from 0
                                               count (and (/= i j) (member o s)))))
                     (remove 'at *full-ops*))))
    (cons 'at (mapcar #'car (subseq (stable-sort cnt #'> :key #'cdr) 0 k)))))

(defun m1c (rep label sets tasks limit &optional gfn)
  "GFN, when given, maps a task index to its restricted grammar (no neighbours used)."
  (let* ((n (length tasks)) (prio (priorities n)) (tag (rep-id rep))
         (full (rep-full rep)) (opsets (rep-opsets rep))
         (rows
           (loop for i below n collect
             (let* ((task (nth i tasks)) (exs (nth i (rep-exsets rep)))
                    (nn (if gfn nil (neighbours sets i prio)))
                    (g-nn (if gfn (funcall gfn i) (grammar-of (mapcar (lambda (j) (nth j opsets)) nn))))
                    (r-nn (solve-with tag task exs g-nn :limit limit))
                    (r-rand (loop for d below 5 collect
                              (let* ((rs2 (sb-ext:seed-random-state (+ 9000 (* 10 i) d)))
                                     (others (remove i (loop for j below n collect j)))
                                     (pick (loop repeat 3 collect
                                             (let ((x (nth (random (length others) rs2) others)))
                                               (setf others (remove x others)) x))))
                                (solve-with tag task exs (grammar-of (mapcar (lambda (j) (nth j opsets)) pick))
                                            :limit limit))))
                    (r-or (solve-with tag task exs (grammar-of (list (nth i opsets))) :limit limit)))
               (list nn g-nn r-nn r-rand r-or)))))
    (format t "~%--- (c) replicate ~d, ~a: ~a ---~%" tag label
            (if gfn "grammar from the pool only" "grammar = {at} + operators of the 3 nearest neighbours' solutions"))
    (format t "~22a ~9a | ~8a ~9a ~10a ~8a | ~5a ~10a ~8a | ~9a ~7a | neighbours -> grammar~%"
            "task" "full" "NN3" "cand" "fair" "ratio" "rand" "fair(avg)" "ratio" "oracle" "ratio")
    (loop for i below n for (nn g-nn r-nn r-rand r-or) in rows do
      (let* ((f (nth i full)) (fc (res-cand f)) (inf most-positive-fixnum)
             (fn (fair r-nn f inf)) (fr (mean (mapcar (lambda (r) (fair r f inf)) r-rand))))
        (format t "~22a ~9d | ~8a ~9d ~10d ~8,3f | ~d/5   ~10d ~8,3f | ~9d ~7,3f | ~{~a~^, ~} -> ~a~%"
                (task-name (nth i tasks)) fc (res-status r-nn) (res-cand r-nn) fn (/ fn (max fc 1) 1.0)
                (count-if #'res-ok r-rand) (round fr) (/ fr (max fc 1))
                (res-cand r-or) (/ (res-cand r-or) (max fc 1) 1.0)
                (mapcar (lambda (j) (short (task-name (nth j tasks)))) nn) g-nn)
        (unless (res-ok r-nn)
          (format t "~24t^ NN3 ~a~@[: ~s~]~@[ (held-out ~d/200)~]; needed ~a, missing ~a~%"
                  (res-status r-nn) (res-prog r-nn) (res-score r-nn) (nth i opsets)
                  (set-difference (nth i opsets) g-nn)))))
    (format t "~%aggregate, ~a, ~d tasks (candidates; 'fair' = restricted attempt + full grammar when the attempt is not held-out-correct):~%" label n)
    (let ((tot-full (reduce #'+ full :key #'res-cand)))
      (format t "  full grammar: ~d candidates in total~%" tot-full)
      (format t "  NN3:    held-out-correct ~d/~d, impostors ~d, no program ~d;  mean grammar size ~,1f operators~%"
              (count-if (lambda (r) (res-ok (third r))) rows) n
              (count-if (lambda (r) (and (res-prog (third r)) (not (res-ok (third r))))) rows)
              (count-if (lambda (r) (null (res-prog (third r)))) rows)
              (mean (mapcar (lambda (r) (length (second r))) rows)))
      (format t "  random: held-out-correct ~d/~d draws, impostors ~d, no program ~d~%"
              (loop for r in rows sum (count-if #'res-ok (fourth r))) (* 5 n)
              (loop for r in rows sum (count-if (lambda (x) (and (res-prog x) (not (res-ok x)))) (fourth r)))
              (loop for r in rows sum (count-if (lambda (x) (null (res-prog x))) (fourth r))))
      (format t "  oracle (own operators + at): held-out-correct ~d/~d; total ~d = ~,3f of full; geo-mean ratio ~,3f~%"
              (count-if (lambda (r) (res-ok (fifth r))) rows) n
              (reduce #'+ rows :key (lambda (r) (res-cand (fifth r))))
              (/ (reduce #'+ rows :key (lambda (r) (res-cand (fifth r)))) tot-full 1.0)
              (geomean (loop for r in rows for f in full
                             collect (/ (max 1 (res-cand (fifth r))) (max 1 (res-cand f)) 1d0))))
      (format t "  NN3 on the tasks it solved: ~d cand against ~d for the full grammar (~,3f)~%"
              (loop for r in rows when (res-ok (third r)) sum (res-cand (third r)))
              (loop for r in rows for f in full when (res-ok (third r)) sum (res-cand f))
              (/ (loop for r in rows when (res-ok (third r)) sum (res-cand (third r)))
                 (max 1.0 (loop for r in rows for f in full when (res-ok (third r)) sum (res-cand f)))))
      (format t "  ~12a | ~12a ~8a ~8a ~5a | ~12a ~8a ~8a~%" "attempt cap" "NN3 fair" "/full" "geomean" "wins"
              "rand fair" "/full" "geomean")
      (dolist (cap *caps*)
        (let* ((fn (loop for r in rows for f in full collect (fair (third r) f cap)))
               (fr (loop for r in rows for f in full
                         collect (mean (mapcar (lambda (x) (fair x f cap)) (fourth r)))))
               (fc (mapcar (lambda (f) (max 1 (res-cand f))) full)))
          (format t "  ~12a | ~12d ~8,3f ~8,3f ~2d/~2d | ~12d ~8,3f ~8,3f~%"
                  (if (= cap most-positive-fixnum) "none" cap)
                  (reduce #'+ fn) (/ (reduce #'+ fn) tot-full 1.0)
                  (geomean (mapcar (lambda (a b) (/ (max 1 a) b 1d0)) fn fc))
                  (count t (mapcar #'< fn (mapcar #'res-cand full))) n
                  (round (reduce #'+ fr)) (/ (reduce #'+ fr) tot-full)
                  (geomean (mapcar (lambda (a b) (/ (max 1 a) b 1d0)) fr fc))))))
    (finish-output)
    rows))

;;; --- (c) summary over replicates ---
(defun policy-stats (costs fulls)
  "(total/full  geo-mean of per-task ratios  total/full without the costliest task  tasks cheaper than full)"
  (let* ((big (position (reduce #'max fulls) fulls))
         (drop (lambda (l) (append (subseq l 0 big) (subseq l (1+ big))))))
    (list (/ (reduce #'+ costs) (float (reduce #'+ fulls) 1d0))
          (geomean (mapcar (lambda (c f) (/ (max 1 c) (max 1 f) 1d0)) costs fulls))
          (/ (reduce #'+ (funcall drop costs)) (float (reduce #'+ (funcall drop fulls)) 1d0))
          (count t (mapcar #'< costs fulls)))))
(defun c-summary (results rs)
  "RESULTS: ((label rep rows) ...) from M1C."
  (format t "~%--- (c) summary: means over replicates ~a ---~%" (remove-duplicates (mapcar (lambda (r) (rep-id (second r))) results)))
  (format t "fair cost = restricted attempt (cut at the cap) + the full grammar whenever the attempt is not held-out-correct; all as a ratio to the full grammar~%")
  (format t "~32a ~7a ~6a ~6a | ~7a ~7a ~7a ~5a | ~7a ~7a ~7a ~5a~%" "restriction from" "correct" "impost" "none"
          "total" "geomean" "total*" "wins" "total" "geomean" "total*" "wins")
  (format t "~32a ~7a ~6a ~6a | ~29a | ~29a~%" "" "" "" "" "no cap on the attempt" "attempt capped at 100,000 cand")
  (flet ((line (label per)             ; PER: per replicate (ok imp none stats-nocap stats-100k)
           (format t "~32a ~7,3f ~6,3f ~6,3f | ~7,3f ~7,3f ~7,3f ~5,1f | ~7,3f ~7,3f ~7,3f ~5,1f~%" label
                   (mean (mapcar #'first per)) (mean (mapcar #'second per)) (mean (mapcar #'third per))
                   (mean (mapcar (lambda (p) (first (fourth p))) per)) (mean (mapcar (lambda (p) (second (fourth p))) per))
                   (mean (mapcar (lambda (p) (third (fourth p))) per)) (mean (mapcar (lambda (p) (fourth (fourth p))) per))
                   (mean (mapcar (lambda (p) (first (fifth p))) per)) (mean (mapcar (lambda (p) (second (fifth p))) per))
                   (mean (mapcar (lambda (p) (third (fifth p))) per)) (mean (mapcar (lambda (p) (fourth (fifth p))) per))))
         (frac (pred items) (/ (count-if pred items) (float (length items) 1d0))))
    (let ((labels (remove-duplicates (mapcar #'first results) :test #'string= :from-end t))
          (inf most-positive-fixnum))
      (dolist (label labels)
        (line label
              (loop for (l rep rows) in results when (string= l label)
                    collect (let ((full (rep-full rep)) (rn (mapcar #'third rows)))
                              (list (frac #'res-ok rn)
                                    (frac (lambda (x) (and (res-prog x) (not (res-ok x)))) rn)
                                    (frac (lambda (x) (null (res-prog x))) rn)
                                    (policy-stats (mapcar (lambda (r f) (fair r f inf)) rn full) (mapcar #'res-cand full))
                                    (policy-stats (mapcar (lambda (r f) (fair r f 100000)) rn full) (mapcar #'res-cand full)))))))
      (let ((first-label (first labels)))
        (line "3 random other tasks (5 draws)"
              (loop for (l rep rows) in results when (string= l first-label)
                    collect (let ((full (rep-full rep)) (all (loop for r in rows append (fourth r))))
                              (list (frac #'res-ok all)
                                    (frac (lambda (x) (and (res-prog x) (not (res-ok x)))) all)
                                    (frac (lambda (x) (null (res-prog x))) all)
                                    (policy-stats (loop for r in rows for f in full
                                                        collect (mean (mapcar (lambda (x) (fair x f inf)) (fourth r))))
                                                  (mapcar #'res-cand full))
                                    (policy-stats (loop for r in rows for f in full
                                                        collect (mean (mapcar (lambda (x) (fair x f 100000)) (fourth r))))
                                                  (mapcar #'res-cand full))))))
        (line "oracle: the task's own operators"
              (loop for (l rep rows) in results when (string= l first-label)
                    collect (let ((full (rep-full rep)) (ro (mapcar #'fifth rows)))
                              (list (frac #'res-ok ro)
                                    (frac (lambda (x) (and (res-prog x) (not (res-ok x)))) ro)
                                    (frac (lambda (x) (null (res-prog x))) ro)
                                    (policy-stats (mapcar (lambda (r f) (fair r f inf)) ro full) (mapcar #'res-cand full))
                                    (policy-stats (mapcar (lambda (r f) (fair r f 100000)) ro full) (mapcar #'res-cand full))))))))
    (format t "(correct / impost / none = share of restricted attempts that are held-out-correct / return a wrong program / return nothing;~% total = sum of fair cost over sum of full cost; total* = the same without the costliest task of the replicate;~% geomean = geometric mean of the per-task ratio; wins = number of tasks, of ~d, where the fair cost is below the full cost)~%"
            (length (rep-full (first rs))))
    ;; what the misses were missing
    (let ((miss (make-hash-table)))
      (loop for (l rep rows) in results when (string= l (first (mapcar #'first results)))
            do (loop for r in rows for o in (rep-opsets rep)
                     do (dolist (m (set-difference o (second r))) (incf (gethash m miss 0)))))
      (format t "operators missing from the ~a grammars, over all replicates: ~{~a ~d~^, ~}~%" (first (mapcar #'first results))
              (let (l) (maphash (lambda (k v) (push v l) (push k l)) miss) l))))
  (finish-output))

;;; ------------------------------------------------------------------
;;; (c2) ADDED: route order from the nearest neighbour's FORM.  The standard
;;; procedure tries tabulate (or the scalar term) first; here the second route
;;; (select/where, or fold) goes first when the nearest neighbour was solved by it.
;;; ------------------------------------------------------------------
(defparameter *alt-forms* '(:sel :where :fold))
(defun m1-route (rep tasks limit)
  (let* ((n (length tasks)) (prio (priorities n)) (std (rep-full rep)) (forms (rep-forms rep))
         (alt (loop for tk in tasks for exs in (rep-exsets rep)
                    collect (solve-with (rep-id rep) tk exs *full-ops* :limit limit :order :alt))))
    (flet ((cost (i use-alt)
             (let ((s (nth i std)) (a (nth i alt)))
               (cond ((not use-alt) (res-cand s))
                     ((res-ok a) (res-cand a))
                     (t (+ (res-cand a) (res-cand s)))))))
      (format t "~%--- (c2) replicate ~d: route order chosen from the nearest neighbour's form (full grammar) ---~%" (rep-id rep))
      (format t "~22a ~6a ~10a | ~10a ~9a ~9a  program when the second route goes first~%"
              "task" "form" "std cand" "alt cand" "status" "of which 1st")
      (dotimes (i n)
        (let ((a (nth i alt)))
          (format t "~22a ~6a ~10d | ~10d ~9a ~9d  ~s~%" (task-name (nth i tasks)) (nth i forms)
                  (res-cand (nth i std)) (res-cand a) (res-status a) (res-route1 a) (res-prog a))))
      (let ((tot (reduce #'+ std :key #'res-cand)))
        (format t "~%~34a ~12a ~8a ~9a ~9a ~9a~%" "policy" "total cand" "/std" "alt-first" "right" "impostors")
        (flet ((line (label choose)
                 (let ((ch (loop for i below n collect (funcall choose i))))
                   (format t "~34a ~12d ~8,3f ~9d ~9d ~9d~%" label
                           (loop for i below n for c in ch sum (cost i c))
                           (/ (loop for i below n for c in ch sum (cost i c)) tot 1.0)
                           (count-if #'identity ch)
                           (loop for i below n for c in ch
                                 count (eq (and c t) (and (member (nth i forms) *alt-forms*) t)))
                           (loop for i below n for c in ch count (and c (not (res-ok (nth i alt)))))))))
          (line "standard order (never alt)" (constantly nil))
          (line "always second route first" (constantly t))
          (line "oracle (own form)" (lambda (i) (member (nth i forms) *alt-forms*)))
          (loop for (label . sets) in (rep-variants rep)
                do (line label (lambda (i) (member (nth (first (neighbours sets i prio 1)) forms) *alt-forms*)))))
        (format t "~34a ~12d ~8,3f   (expected, exact)~%" "form of a random other task"
                (round (loop for i below n
                             sum (let ((p (/ (loop for j below n count (and (/= i j) (member (nth j forms) *alt-forms*)))
                                             (- n 1))))
                                   (+ (* p (cost i t)) (* (- 1 p) (cost i nil))))))
                (/ (loop for i below n
                         sum (let ((p (/ (loop for j below n count (and (/= i j) (member (nth j forms) *alt-forms*)))
                                         (- n 1))))
                               (+ (* p (cost i t)) (* (- 1 p) (cost i nil)))))
                   tot 1.0))))
    (finish-output)))

;;; ------------------------------------------------------------------
;;; Driver
;;; ------------------------------------------------------------------
(defun pool-table (rep tasks)
  (format t "~2a ~22a ~6a ~6a ~8a ~9a ~6a ~8a ~14a program~%" "#" "task" "intent" "form" "status" "cand" "ms"
          "held-out" "ops(body)")
  (loop for i from 0 for tk in tasks for r in (rep-full rep) for f in (rep-forms rep) for o in (rep-opsets rep) do
    (format t "~2d ~22a ~6a ~6a ~8a ~9d ~6d ~8a ~14a ~s~%" i (task-name tk) (nth i *intended*) f
            (res-status r) (res-cand r) (res-ms r) (format nil "~@[~d~]/200" (res-score r)) o (res-prog r)))
  (format t "forms: ~{~a ~d~^, ~};  first-route candidates wasted on select/where/fold tasks: ~d of ~d total~%"
          (loop for f in (remove-duplicates (rep-forms rep)) append (list f (count f (rep-forms rep))))
          (loop for r in (rep-full rep) for f in (rep-forms rep) when (member f *alt-forms*) sum (res-route1 r))
          (reduce #'+ (rep-full rep) :key #'res-cand)))

(defun m1 (&key (reps '(1 2 3 4 5)) (nex 12) (limit 12000000) (c-reps reps) (c-labels '(0 1 6)))
  (let* ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase)
         (tasks (m1-pool)) (n (length tasks)) (t0 (now))
         (rs (loop for s in reps
                   collect (make-replicate s tasks (lambda (i) (+ (* 1000 s) i)) nex limit)))
         (r1 (first rs)))
    (format t "=== M1. SIGNATURES AND INTER-TASK MIXING (~d tasks, ~d examples/task, size<=10, budget ~d cand) ===~%" n nex limit)
    (format t "replicate s = one example set per task, task i generated with seed 1000*s+i; replicates ~a~%" reps)
    (format t "~%--- task pool, replicate ~d: full 12-operator grammar ~a ---~%" (rep-id r1) *full-ops*)
    (pool-table r1 tasks)
    (format t "~%other replicates (full grammar): held-out-correct, and every task whose form or status differs from replicate ~d~%" (rep-id r1))
    (dolist (r rs)
      (format t "  replicate ~d: ~d/~d correct, ~d cand in total~%" (rep-id r)
              (count-if #'res-ok (rep-full r)) n (reduce #'+ (rep-full r) :key #'res-cand))
      (loop for i below n
            unless (and (res-ok (nth i (rep-full r))) (eq (nth i (rep-forms r)) (nth i (rep-forms r1))))
              do (format t "      ~a: ~a ~a ~@[~d/200~] ~s~%" (task-name (nth i tasks)) (nth i (rep-forms r))
                         (res-status (nth i (rep-full r))) (res-score (nth i (rep-full r)))
                         (res-prog (nth i (rep-full r))))))
    (format t "~%tasks tried and EXCLUDED from the pool because the full grammar returns impostors (5 example sets, seeds 1..5):~%")
    (format t "  ~18a ~22a ~28a first non-correct program under the full grammar~%" "task" "full: correct, cand" "{at + intended ops}: correct, cand")
    (loop for (tk own) in *excluded-tasks* do
      (let* ((fs (loop for s from 1 to 5 collect (solve-with (list :x s) tk (gen-examples tk s nex 7) *full-ops* :limit limit)))
             (os (loop for s from 1 to 5 collect (solve-with (list :x s) tk (gen-examples tk s nex 7) (cons 'at own) :limit limit)))
             (bad (find-if-not #'res-ok fs)))
        (format t "  ~18a ~d/5 ~17d ~d/5 ~23d ~@[~d/200 ~]~s~%" (task-name tk)
                (count-if #'res-ok fs) (round (mean (mapcar #'res-cand fs)))
                (count-if #'res-ok os) (round (mean (mapcar #'res-cand os)))
                (and bad (res-score bad)) (and bad (res-prog bad)))))
    ;; ---------- (a) ----------
    (format t "~%--- (a) signatures: one shared space = 64 generic probe rows + ~d x ~d task rows ---~%" n nex)
    (format t "~4a ~5a ~8a ~10a ~8a ~8a ~10a ~10a ~6a~%" "rep" "pool" "bool-cls" "tautology" "pool" "active" "cand" "cells" "ms")
    (dolist (r rs)
      (dolist (v (list (rep-p3 r) (rep-p5 r) (rep-p3f r)))
        (format t "~4d ~5a ~8d ~10d ~8d ~8d ~10d ~10d ~6d~%" (rep-id r) (sig-name v) (sig-nbool v) (sig-ntaut v)
                (length (sig-pool v))
                (loop for k below (length (sig-pool v)) count (some (lambda (s) (= 1 (sbit s k))) (sig-sets v)))
                (sig-cand v) (sig-cells v) (sig-ms v))))
    (format t "(bool-cls = Boolean classes enumerated; tautology = no :f on the probe rows, dropped; pool = the rest; active = holds for >=1 task)~%")
    (format t "~%signature sizes, replicate ~d, and mean over replicates:~%" (rep-id r1))
    (format t "~2a ~22a ~6a ~5a ~5a ~5a ~7a ~7a  nearest 3 by P3 (Jaccard, form)~%" "#" "task" "form" "|P3|" "|P5|" "|P3f|" "P3 mean" "P5 mean")
    (let ((prio (priorities n)))
      (dotimes (i n)
        (format t "~2d ~22a ~6a ~5d ~5d ~5d ~7,1f ~7,1f  ~{~a~^; ~}~%" i (task-name (nth i tasks)) (nth i (rep-forms r1))
                (count 1 (nth i (sig-sets (rep-p3 r1)))) (count 1 (nth i (sig-sets (rep-p5 r1))))
                (count 1 (nth i (sig-sets (rep-p3f r1))))
                (mean (mapcar (lambda (r) (count 1 (nth i (sig-sets (rep-p3 r))))) rs))
                (mean (mapcar (lambda (r) (count 1 (nth i (sig-sets (rep-p5 r))))) rs))
                (mapcar (lambda (j) (format nil "~a ~,2f ~a" (short (task-name (nth j tasks)))
                                            (jaccard (nth i (sig-sets (rep-p3 r1))) (nth j (sig-sets (rep-p3 r1))))
                                            (nth j (rep-forms r1))))
                        (neighbours (sig-sets (rep-p3 r1)) i prio)))))
    (format t "~%P3 signatures in full, replicate ~d (a property is printed as the representative term of its class):~%" (rep-id r1))
    (dotimes (i n)
      (format t "~2d ~22a ~{~s~^ ~}~%" i (task-name (nth i tasks))
              (loop for c across (sig-pool (rep-p3 r1)) for k from 0
                    when (= 1 (sbit (nth i (sig-sets (rep-p3 r1))) k)) collect (cls-term c))))
    (format t "~%P5 signatures, replicate ~d: equalities only (first 12 per task):~%" (rep-id r1))
    (dotimes (i n)
      (let ((eqs (loop for c across (sig-pool (rep-p5 r1)) for k from 0
                       when (and (= 1 (sbit (nth i (sig-sets (rep-p5 r1))) k)) (eq '= (car (cls-term c))))
                         collect (cls-term c))))
        (format t "~2d ~22a [~d] ~{~s~^ ~}~%" i (task-name (nth i tasks)) (length eqs)
                (subseq eqs 0 (min 12 (length eqs))))))
    ;; ---------- (b) ----------
    (format t "~%--- (b) leave-one-out retrieval, ~d tasks, mean over replicates ~a ---~%" n reps)
    (format t "~32a | ~27a | ~27a | ~11a | ~a~%" "" "same program form" ">= half of solution's ops" "NN3 covers" "NN-hit (form) per replicate")
    (format t "~32a | ~6a ~6a ~6a ~6a | ~6a ~6a ~6a ~6a | ~5a ~5a |~%" "signature" "NN-hit" "chance" "rank1" "chance"
            "NN-hit" "chance" "rank1" "chance" "NN3" "rand3")
    (loop for (label) in (rep-variants r1) for vi from 0 do
      (let* ((per (loop for r in rs
                        collect (let ((sets (cdr (nth vi (rep-variants r)))))
                                  (append (subseq (retrieval sets (rel-form r)) 0 4)
                                          (subseq (retrieval sets (rel-ops r)) 0 4)
                                          (coverage r sets)))))
             (avg (loop for k below 10 collect (mean (mapcar (lambda (p) (nth k p)) per)))))
        (format t "~32a | ~6,3f ~6,3f ~6,2f ~6,2f | ~6,3f ~6,3f ~6,2f ~6,2f | ~5,2f ~5,2f | ~{~4,2f~^ ~}~%" label
                (nth 0 avg) (nth 1 avg) (nth 2 avg) (nth 3 avg) (nth 4 avg) (nth 5 avg) (nth 6 avg) (nth 7 avg)
                (nth 8 avg) (nth 9 avg) (mapcar #'first per))))
    (format t "(NN-hit = share of tasks whose nearest neighbour is relevant; rank1 = mean rank of the first relevant task; chance = the same~% for a random order; ties get their expected value.  'ops' excludes AT.  NN3 covers = the 3 nearest neighbours' operators contain~% every operator of the task's own solution; rand3 = exact expectation of that for 3 random other tasks.)~%")
    (format t "~%operator coverage against the number of neighbours k (mean over replicates; 2000 seeded random draws per task):~%")
    (format t "  ~3a | ~28a | ~28a | ~28a | ~8a~%" "k" "P3: covers, grammar size" "P5: covers, grammar size" "type only: covers, size" "k random")
    (dolist (k '(1 2 3 5 8))
      (let ((per (loop for r in rs collect (loop for vi in '(0 1 6) collect (coverage-k r (cdr (nth vi (rep-variants r))) k)))))
        (flet ((m (vi f) (mean (mapcar (lambda (p) (funcall f (nth vi p))) per))))
          (format t "  ~3d | ~12,2f ~15,1f | ~12,2f ~15,1f | ~12,2f ~15,1f | ~8,2f~%" k
                  (m 0 #'first) (m 0 #'third) (m 1 #'first) (m 1 #'third) (m 2 #'first) (m 2 #'third) (m 0 #'second)))))
    (format t "~%NN same-form hit by the form of the held-out task (pooled over replicates):~%")
    (format t "  ~6a ~4a ~6a ~6a ~6a ~9a ~6a~%" "form" "n" "P3" "P5" "P5-io" "type-only" "chance")
    (dolist (f '(:tab :tabg :rec :sel :where :fold))
      (flet ((hit (vi)
               (mean (loop for r in rs append
                       (let ((sets (cdr (nth vi (rep-variants r)))) (forms (rep-forms r)))
                         (loop for i below n when (eq (nth i forms) f)
                               collect (let* ((others (remove i (loop for j below n collect j)))
                                              (sim (mapcar (lambda (j) (jaccard (nth i sets) (nth j sets))) others))
                                              (top (reduce #'max sim)))
                                         (/ (loop for s in sim for j in others
                                                  count (and (= s top) (eq (nth j forms) f)))
                                            (count top sim)))))))))
        (let ((cnt (mean (mapcar (lambda (r) (count f (rep-forms r))) rs))))
          (format t "  ~6a ~4,1f ~6,2f ~6,2f ~6,2f ~9,2f ~6,2f~%" f cnt (hit 0) (hit 1) (hit 4) (hit 6)
                  (/ (- cnt 1) (- n 1.0))))))
    (let ((r0 (make-replicate 0 tasks (constantly 1) nex limit)))
      (format t "~%for comparison, replicate 0 = seed 1 for EVERY task (the prototype's own example sets; tasks with the same input~%spec then share their inputs).  ~d/~d correct.  Candidates of the prototype's 15 tasks: ~{~d~^ ~}~%"
              (count-if #'res-ok (rep-full r0)) n (mapcar #'res-cand (subseq (rep-full r0) 0 15)))
      (loop for (label . sets) in (rep-variants r0) do
        (let ((f (retrieval sets (rel-form r0))) (o (retrieval sets (rel-ops r0))) (c (coverage r0 sets)))
          (format t "~32a | ~6,3f ~6,3f ~6,2f ~6,2f | ~6,3f ~6,3f ~6,2f ~6,2f | ~5,2f ~5,2f |~%" label
                  (first f) (second f) (third f) (fourth f) (first o) (second o) (third o) (fourth o)
                  (first c) (second c)))))
    (format t "~%[(a)+(b) took ~,1f s including all full-grammar solves]~%" (- (now) t0))
    (finish-output)
    ;; ---------- (c) ----------
    (let ((results '()))
      (dolist (r rs)
        (when (member (rep-id r) c-reps)
          (loop for vi in c-labels
                do (push (list (car (nth vi (rep-variants r))) r
                               (m1c r (car (nth vi (rep-variants r))) (cdr (nth vi (rep-variants r))) tasks limit))
                         results))
          (push (list "pool prior: 4 most frequent ops" r
                      (m1c r "pool prior: 4 most frequent ops" nil tasks limit (lambda (i) (freq-grammar r i 4))))
                results)
          (m1-route r tasks limit)))
      (when results (c-summary (reverse results) rs)))
    (format t "~%[total ~,1f s]~%" (- (now) t0))
    (finish-output)))
