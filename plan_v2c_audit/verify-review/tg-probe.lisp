;;;; tg-probe.lisp -- measurement probe for a "factored execution graph" store.
;;;; Standalone (SBCL only, no dependencies, does not load the lisploop kernel).
;;;;
;;;; Idea under test: evaluating one expression over many rows gives an
;;;; execution graph of shape (pattern x rows).  Store it factored:
;;;;   BASE   = a set of rows (a "space")
;;;;   COLUMN = one value per row of a base
;;;;   CLASS  = one distinct column, plus the smallest term that produces it
;;;;   BANK   = all classes on one base, content-addressed by their column
;;;; Sections: 1 core store | 2 interpreter | 3 change of base | 4 exp D (lift)
;;;;           5 exp A (growth) | 6 exp C (inverses) | 7 exp B (laws) | 8 main

(defpackage :tg (:use :cl))
(in-package :tg)
(declaim (optimize (speed 2) (safety 1) (debug 0)))

;;; ===================================================================
;;; SECTION 1: CORE STORE
;;; ===================================================================

;;; A BASE is a set of rows: the examples of a task, the rows of an operator's
;;; input/output table, or -- after a change of base -- (example, index) pairs.
(defstruct base
  n        ; number of rows
  parent   ; the base this one was derived from, or nil
  pmap)    ; simple-vector: row of this base -> row of PARENT

;;; A COLUMN is a simple-vector with one cell per row of a base.  A cell is:
;;;   an integer | :t | :f | a Lisp list of integers (a sequence) | :err
;;;   | the name of a binary operator (a :code cell: a function-valued input)
;;; :err means "undefined here" (division by zero, index out of range).
;;;
;;; A CLASS is one distinct column on a base.  Every term whose column equals
;;; it belongs to the class (observational equivalence); only the smallest
;;; term is kept as the representative.  "Two terms landed in one class" is an
;;; equation (a law candidate); a :bool class is a partition of the rows (a guard).
(defstruct cls
  id      ; creation index within its bank
  col     ; the column (simple-vector, one cell per row)
  type    ; :int, :bool, :seq or :code
  size    ; number of nodes of the representative term
  term)   ; representative term, e.g. (+ x (* y 2)); a leaf is a symbol or integer

;;; An operator.  FN works on single cells; the store applies it column-wise.
(defstruct op name args res fn arity)

;;; A BANK holds every class found so far on one base.
(defstruct bank
  base ops buf                            ; BUF: scratch column for candidates
  (table (make-hash-table))               ; column hash -> ((column . class) ...)
  (by (make-hash-table :test 'equal))     ; (type . size) -> vector of classes
  (all (make-array 64 :adjustable t :fill-pointer 0)) ; all classes, creation order = size order
  (done 1)                                ; largest term size fully enumerated
  (ncand 0) (ncells 0) (ncoll 0)          ; candidates / cells evaluated, collisions
  on-new                                  ; hook (class): called for each new class
  on-coll                                 ; hook (old-class op c1 c2 c3): a new term hit an old class
  limit deadline                          ; candidate budget / wall-clock deadline
  frontier nfront)                        ; hash-only mode for a last size level (experiment A only)

(defun new-bank (base ops)
  (make-bank :base base :ops ops :buf (make-array (base-n base) :initial-element :err)))

;;; --- content hash over the cells of a column (sxhash would not look inside) ---
(defun cell-hash (v)
  (cond ((integerp v) (logand v #xFFFFFFF))
        ((symbolp v) (logior #x10000000 (logand (sxhash v) #xFFFFFFF))) ; :err :t :f, (), operator names
        (t (let ((h 7))                   ; a sequence: fold its elements
             (dolist (e v (+ h #x20000000))
               (setf h (logand (+ (* h 31) (cell-hash e)) #xFFFFFFF)))))))
(declaim (inline mix))
(defun mix (h v) (logand (* (logxor h (cell-hash v)) 16777619) #xFFFFFFFFF)) ; FNV-style, 36 bits
(defun col-hash (col)
  (let ((h 2166136261)) (dotimes (r (length col) h) (setf h (mix h (svref col r))))))
(defun col= (a b)                         ; exact equality, confirms every hash hit
  (dotimes (r (length a) t) (unless (equal (svref a r) (svref b r)) (return nil))))
(defun col-get (table col &optional (h (col-hash col)))
  (cdr (assoc col (gethash h table) :test #'col=)))
(defun lookup (bank col) "The class whose column is COL, or nil: one hash probe."
  (col-get (bank-table bank) col))
(defun classes (bank type size) (or (gethash (cons type size) (bank-by bank)) #()))

(defun new-class (bank col h type size term)
  (let ((c (make-cls :id (length (bank-all bank)) :col col :type type :size size :term term))
        (key (cons type size)))
    (push (cons col c) (gethash h (bank-table bank)))
    (vector-push-extend c (or (gethash key (bank-by bank))
                              (setf (gethash key (bank-by bank))
                                    (make-array 16 :adjustable t :fill-pointer 0))))
    (vector-push-extend c (bank-all bank))
    (when (bank-on-new bank) (funcall (bank-on-new bank) c))
    c))

(defun add-leaf (bank term type col)
  "A size-1 class: a given column or a constant.  Duplicated columns share one class."
  (or (lookup bank col) (new-class bank col (col-hash col) type 1 term)))

(defun try (bank op size c1 c2 c3)
  "Evaluate OP column-wise on the argument classes and file the resulting column:
   a new class, or a collision with an existing one.  A cell is :err when any
   argument cell is :err; only IF (which has no cell function) is lazy in the
   branch it does not take.  A column that is :err on every row is dropped."
  (let* ((n (base-n (bank-base bank))) (buf (bank-buf bank)) (fn (op-fn op)) (k (op-arity op))
         (a1 (cls-col c1)) (a2 (and c2 (cls-col c2))) (a3 (and c3 (cls-col c3)))
         (h 2166136261) (ok nil))
    (declare (type simple-vector buf a1) (type fixnum n h k))
    (dotimes (r n)
      (let* ((x (svref a1 r))
             (v (cond ((eq x :err) :err)
                      ((= k 1) (funcall fn x))
                      ((null fn) (if (eq x :t) (svref a2 r) (svref a3 r)))      ; IF
                      (t (let ((y (svref a2 r)) (z (and a3 (svref a3 r))))
                           (cond ((or (eq y :err) (eq z :err)) :err)
                                 (a3 (funcall fn x y z))
                                 (t (funcall fn x y))))))))
        (unless (eq v :err) (setf ok t))
        (setf (svref buf r) v  h (mix h v))))
    (let ((nc (incf (bank-ncand bank))))
      (incf (bank-ncells bank) n)
      (when (and (bank-limit bank) (> nc (bank-limit bank))) (throw :stop :budget))
      (when (and (bank-deadline bank) (zerop (logand nc 1023))
                 (> (get-internal-real-time) (bank-deadline bank)))
        (throw :stop :time)))
    (when ok
      (let ((old (col-get (bank-table bank) buf h)))
        (cond (old (incf (bank-ncoll bank))
                   (when (bank-on-coll bank) (funcall (bank-on-coll bank) old op c1 c2 c3)))
              ((bank-frontier bank)       ; last level, hash-only: count the new column, do not store it
               (if (gethash h (bank-frontier bank))
                   (incf (bank-ncoll bank))
                   (progn (setf (gethash h (bank-frontier bank)) t)
                          (incf (getf (bank-nfront bank) (op-res op) 0)))))
              (t (new-class bank (copy-seq buf) h (op-res op) size
                            (list* (op-name op) (cls-term c1)
                                   (and c2 (cons (cls-term c2) (and c3 (list (cls-term c3)))))))))))))

(defun enumerate-size (bank s)
  "All terms of size S: each operator over every type-correct tuple of existing
   classes whose sizes sum to S-1.  Arguments are classes, never raw terms."
  (dolist (op (bank-ops bank))
    (destructuring-bind (t1 &optional t2 t3) (op-args op)
      (cond (t3 (loop for s1 from 1 to (- s 3) do
                  (loop for s2 from 1 to (- s 2 s1) do
                    (let ((v2 (classes bank t2 s2)) (v3 (classes bank t3 (- s 1 s1 s2))))
                      (loop for c1 across (classes bank t1 s1) do
                        (loop for c2 across v2 do
                          (loop for c3 across v3 do (try bank op s c1 c2 c3))))))))
            (t2 (loop for s1 from 1 to (- s 2) do
                  (let ((v2 (classes bank t2 (- s 1 s1))))
                    (loop for c1 across (classes bank t1 s1) do
                      (loop for c2 across v2 do (try bank op s c1 c2 nil))))))
            (t (loop for c1 across (classes bank t1 (- s 1)) do (try bank op s c1 nil nil)))))))

(defun now () (/ (get-internal-real-time) (float internal-time-units-per-second 1d0)))
(defun tsize (e) "Number of nodes of a term." (if (consp e) (1+ (loop for a in (cdr e) sum (tsize a))) 1))

(defun run (bank max-size &key limit seconds)
  "Enumerate sizes up to MAX-SIZE.  Returns :done, :budget, :time, or whatever
   a hook threw to :stop (hooks stop the search with (throw :stop value))."
  (setf (bank-limit bank) limit
        (bank-deadline bank) (and seconds (+ (get-internal-real-time)
                                             (round (* seconds internal-time-units-per-second)))))
  (catch :stop
    (loop for s from (1+ (bank-done bank)) to max-size
          do (enumerate-size bank s) (setf (bank-done bank) s))
    :done))

;;; --- goals: predicates on a class ---
(defun goal-exact (type target)           ; the column equals TARGET on every row
  (lambda (c) (and (eq (cls-type c) type) (col= (cls-col c) target))))
(defun goal-masked (type target mask)     ; equal where MASK is true; anything (even :err) elsewhere
  (lambda (c) (and (eq (cls-type c) type)
                   (let ((col (cls-col c)))
                     (dotimes (r (length col) t)
                       (when (and (svref mask r) (not (equal (svref col r) (svref target r))))
                         (return nil)))))))
(defun goal-allowed (type sets)           ; each row's cell is a member of that row's allowed set
  (lambda (c) (and (eq (cls-type c) type)
                   (let ((col (cls-col c)))
                     (dotimes (r (length col) t)
                       (unless (member (svref col r) (svref sets r) :test #'equal) (return nil)))))))

(defun search-goals (bank goals max-size limit)
  "Enumerate until every goal in GOALS (alist name -> predicate) has a class, or
   the budget ends.  Returns an alist name -> smallest satisfying class."
  (let ((found '()))
    (flet ((check (c)
             (dolist (g goals)
               (when (and (not (assoc (car g) found)) (funcall (cdr g) c))
                 (push (cons (car g) c) found)))
             (when (= (length found) (length goals)) (throw :stop :all))))
      (setf (bank-on-new bank) #'check)
      (unless (eq :all (catch :stop (map nil #'check (bank-all bank))))
        (run bank max-size :limit limit)))
    found))
(defun search-goal (bank goal max-size limit)
  (cdr (assoc :g (search-goals bank (list (cons :g goal)) max-size limit))))

;;; --- operators ---
(defun bool (x) (if x :t :f))
(defvar *all-ops*)
(defparameter *all-ops*
  (flet ((o (name args res fn) (make-op :name name :args args :res res :fn fn :arity (length args))))
    (list (o '+ '(:int :int) :int #'+) (o '- '(:int :int) :int #'-) (o '* '(:int :int) :int #'*)
          (o 'neg '(:int) :int #'-)
          (o 'div '(:int :int) :int (lambda (a b) (if (zerop b) :err (values (floor a b)))))
          (o 'mod '(:int :int) :int (lambda (a b) (if (zerop b) :err (mod a b))))
          (o 'max '(:int :int) :int #'max) (o 'min '(:int :int) :int #'min)
          (o '= '(:int :int) :bool (lambda (a b) (bool (= a b))))
          (o '< '(:int :int) :bool (lambda (a b) (bool (< a b))))
          (o 'and '(:bool :bool) :bool (lambda (a b) (bool (and (eq a :t) (eq b :t)))))
          (o 'not '(:bool) :bool (lambda (a) (bool (eq a :f))))
          (o 'if '(:bool :int :int) :int nil)          ; handled inside TRY and EV
          (o 'at '(:seq :int) :int                     ; element J of sequence S, :err out of range
             (lambda (s j) (if (and (<= 0 j) (< j (length s))) (nth j s) :err)))
          (o 'len '(:seq) :int #'length)
          (o 'call '(:code :int :int) :int             ; apply a function-valued input: (call f a b)
             (lambda (f a b) (funcall (op-fn (find f *all-ops* :key #'op-name)) a b))))))
(defun ops (&rest names) (mapcar (lambda (nm) (find nm *all-ops* :key #'op-name)) names))
(defparameter *g1* '(+ - * neg))
(defparameter *g2* (append *g1* '(div mod max min)))
(defparameter *g3* (append *g2* '(= < and not if)))

;;; ===================================================================
;;; SECTION 2: INTERPRETER for terms and the emitted array-style programs
;;; ===================================================================
(defvar *steps* 0)                        ; fold-step applications (cost accounting)
(defun ev (e env)
  "Evaluate term E; ENV is an alist symbol -> value.  Used to VERIFY results on
   fresh examples, so it shares only the per-cell operator functions with TRY."
  (cond ((integerp e) e)
        ((symbolp e) (cdr (assoc e env)))
        (t (destructuring-bind (head a &optional b c) e
             (flet ((lam (f &rest vals) (ev (third f) (pairlis (second f) vals env))))
               (case head
                 (if (case (ev a env) (:t (ev b env)) (:f (ev c env)) (t :err)))
                 (tabulate                ; (tabulate L (lambda (i prev) elem)); prev = previous output
                  (let ((n (ev a env)) (prev :err))
                    (if (integerp n) (loop for i below n collect (setf prev (lam b i prev))) :err)))
                 (select (loop for x in (ev a env) for j from 0 when (eq :t (lam b j x)) collect x))
                 (where  (loop for x in (ev a env) for j from 0 when (eq :t (lam b j x)) collect j))
                 ((fold foldr)            ; (fold init (lambda (acc x) step) xs)
                  (let ((acc (ev a env)) (xs (ev c env)))
                    (dolist (x (if (eq head 'fold) xs (reverse xs)) acc)
                      (incf *steps*) (setf acc (lam b acc x)))))
                 (t (let ((op (find head *all-ops* :key #'op-name))
                          (x (ev a env)) (y (and b (ev b env))) (z (and c (ev c env))))
                      (cond ((or (eq x :err) (eq y :err) (eq z :err)) :err)
                            (c (funcall (op-fn op) x y z))
                            (b (funcall (op-fn op) x y))
                            (t (funcall (op-fn op) x)))))))))))

;;; ===================================================================
;;; SECTION 3: CHANGE OF BASE (the LIFT primitive)
;;; ===================================================================
(defun explode (b counts)
  "New base with one row per (row r of B, index i < COUNTS[r]).  Returns the
   new base (which remembers the map back to B) and its index column."
  (let ((pm '()) (ix '()))
    (dotimes (r (base-n b)) (dotimes (i (svref counts r)) (push r pm) (push i ix)))
    (values (make-base :n (length pm) :parent b :pmap (coerce (nreverse pm) 'simple-vector))
            (coerce (nreverse ix) 'simple-vector))))
(defun pull (b2 col) "Pull a column of the parent base back: each child row reads its parent row."
  (map 'simple-vector (lambda (r) (svref col r)) (base-pmap b2)))
(defun collect (b2 col) "Push a column forward: per parent row, the list of its children's cells."
  (let ((out (make-array (base-n (base-parent b2)) :initial-element nil)))
    (loop for r across (base-pmap b2) for v across col do (push v (svref out r)))
    (map 'simple-vector #'reverse out)))
(defun elt-col (seqs idx &optional (off 0))
  "Column: element IDX+OFF of each row's sequence, :err out of range."
  (map 'simple-vector
       (lambda (s i) (let ((j (+ i off))) (if (and (<= 0 j) (< j (length s))) (nth j s) :err)))
       seqs idx))

;;; ===================================================================
;;; SECTION 4: EXPERIMENT D -- lift by change of base
;;; ===================================================================
(defstruct task name ins ref (out :seq))  ; INS: ((name kind lo hi) ...); REF: hidden reference
(defun tk (name ins ref &optional (out :seq)) (make-task :name name :ins ins :ref ref :out out))
(defparameter *tasks*
  (list (tk "reverse" '((xs :seq)) #'reverse)
        (tk "shift-seq (spec)" '((xs :seq) (k :int 0 3))          ; shift left by k, zero fill
            (lambda (xs k) (loop for i below (length xs) collect (or (nth (+ i k) xs) 0))))
        (tk "rotate-left k" '((xs :seq) (k :int 0 3))
            (lambda (xs k) (loop with n = (length xs) for i below n collect (nth (mod (+ i k) n) xs))))
        (tk "map-adjacent +" '((xs :seq)) (lambda (xs) (loop for (a b) on xs while b collect (+ b a))))
        (tk "map-adjacent -" '((xs :seq)) (lambda (xs) (loop for (a b) on xs while b collect (- b a))))
        (tk "running-sum" '((xs :seq)) (lambda (xs) (let ((a 0)) (loop for x in xs collect (incf a x)))))
        (tk "scan + init a (spec)" '((xs :seq) (a :int -5 9)) (lambda (xs a) (loop for x in xs collect (incf a x))))
        (tk "scan 2*acc-x init a" '((xs :seq) (a :int -3 3))
            (lambda (xs a) (loop for x in xs collect (setf a (- (* 2 a) x)))))
        (tk "positions (spec)" '((xs :seq) (k :int 0 4))          ; spec semantics: k, k+1, ..
            (lambda (xs k) (loop for i below (length xs) collect (+ k i))))
        (tk "positions-of v" '((xs :seq) (v :elt))
            (lambda (xs v) (loop for x in xs for j from 0 when (= x v) collect j)))
        (tk "filter x>k" '((xs :seq) (k :int -3 7)) (lambda (xs k) (remove-if-not (lambda (x) (> x k)) xs)))
        (tk "take k" '((xs :seq) (k :int 0 8)) (lambda (xs k) (subseq xs 0 (min k (length xs)))))
        (tk "zip-add" '((xs :seq) (zs :seq)) (lambda (xs zs) (mapcar #'+ xs zs)))
        ;; the two :spec signatures with a function-valued argument f (one of + - * per example)
        (tk "map-adjacent f (spec)" '((xs :seq) (f :code))
            (lambda (xs f) (loop for (a b) on xs while b collect (funcall f b a))))
        (tk "scan f init a (spec)" '((xs :seq) (a :int -5 9) (f :code))
            (lambda (xs a f) (loop for x in xs collect (setf a (funcall f a x)))))))
(defparameter *fold-tasks*
  (list (tk "sum" '((xs :seq)) (lambda (xs) (reduce #'+ xs)) :int)
        (tk "alternating sum" '((xs :seq))                        ; x0 - x1 + x2 - ...
            (lambda (xs) (loop for x in xs for s = 1 then (- s) sum (* s x))) :int)
        (tk "horner base 2" '((xs :seq)) (lambda (xs) (reduce (lambda (a x) (+ (* 2 a) x)) xs :initial-value 0)) :int)))

(defun rnd (rs lo hi) (+ lo (random (1+ (- hi lo)) rs)))
(defun gen-example (task rs maxlen)
  "One example: (inputs-alist . output).  Sequences: length 0..MAXLEN, values -5..9."
  (let ((ins '()))
    (dolist (spec (task-ins task))
      (destructuring-bind (name kind &optional lo hi) spec
        (push (cons name
                    (ecase kind
                      (:seq (loop repeat (rnd rs 0 maxlen) collect (rnd rs -5 9)))
                      (:int (rnd rs lo hi))
                      (:code (nth (random 3 rs) '(+ - *)))
                      (:elt (let ((s (cdr (car (last ins)))))   ; mostly a value that occurs in xs
                              (if (and s (< (random 4 rs) 3)) (nth (random (length s) rs) s) (rnd rs -5 9))))))
              ins)))
    (setf ins (nreverse ins))
    (cons ins (apply (task-ref task) (mapcar #'cdr ins)))))
(defun gen-examples (task seed n maxlen)
  (let ((rs (sb-ext:seed-random-state seed))) (loop repeat n collect (gen-example task rs maxlen))))
(defun verify (task prog &key (n 200) (seed 999) (maxlen 12))
  "Number of N fresh held-out examples (longer sequences) on which PROG is right."
  (count-if (lambda (ex) (equal (cdr ex) (ev prog (car ex)))) (gen-examples task seed n maxlen)))

(defun input-cols (task exs)
  "Leaf columns on the example base: ((term type column) ...).  Per sequence
   input its length and the sequence itself; integer inputs; constants 0 and 1."
  (let ((out '()))
    (flet ((col (name) (map 'simple-vector (lambda (ex) (cdr (assoc name (car ex)))) exs)))
      (dolist (spec (task-ins task))
        (let ((name (first spec)))
          (when (eq (second spec) :seq)
            (push (list `(len ,name) :int (map 'simple-vector #'length (col name))) out))
          (push (list name (case (second spec) (:seq :seq) (:code :code) (t :int)) (col name)) out)))
      (dolist (k '(0 1)) (push (list k :int (make-array (length exs) :initial-element k)) out)))
    (nreverse out)))

(defvar *cand* 0) (defvar *cells* 0) (defvar *scan* 0) (defvar *note* nil)
(defun tally (bank) (incf *cand* (bank-ncand bank)) (incf *cells* (bank-ncells bank)))
(defparameter *shape-ops* (ops '+ '- 'max 'min))
(defparameter *d-ops* (ops '+ '- '* 'mod 'max 'min 'at '= '< 'and 'not 'call)) ; ONE grammar for every task

(defun cover (bank y rows depth)
  "A term equal to Y on every row in ROWS (a list of row numbers), built from the
   classes already in BANK.  (1) a single class that matches all of ROWS; else
   (2) SPLIT: among classes whose match-mask (restricted to ROWS) is itself the
   column of a boolean class -- the guard, found by one hash probe -- take the
   one matching the most rows and recurse on the rows it does not match."
  (let ((guards (make-hash-table)) (cands '()) (nrows (length rows)) (best 0))
    (flet ((key (c f) (map 'simple-vector (lambda (r) (funcall f (svref (cls-col c) r) r)) rows)))
      (loop for c across (bank-all bank) when (eq (cls-type c) :bool) do
        (let* ((k (key c (lambda (v r) (declare (ignore r)) v))) (h (col-hash k)))
          (unless (col-get guards k h) (push (cons k c) (gethash h guards)))))
      (loop for c across (bank-all bank) when (eq (cls-type c) :int) do
        (let* ((k (key c (lambda (v r) (bool (equal v (svref y r)))))) (m (count :t k)))
          (incf *scan* nrows)
          (setf best (max best m))
          (cond ((= m nrows) (return-from cover (cls-term c)))
                ((and (> m 0) (> depth 0))
                 (let ((g (col-get guards k))) (when g (push (list m c g k) cands)))))))
      (loop for (nil c g k) in (let ((s (stable-sort (nreverse cands) #'> :key #'first)))
                                 (subseq s 0 (min 2 (length s))))
            do (let ((rest (cover bank y (loop for r in rows for b across k when (eq b :f) collect r)
                                  (1- depth))))
                 (when rest
                   (push (format nil "split: chosen term matches ~d of ~d rows; best-matching class (guard or not) ~d"
                                 (count :t k) nrows best) *note*)
                   (return `(if ,(cls-term g) ,(cls-term c) ,rest))))))))

(defvar *greedy* nil)                     ; T: allow nested (two-guard) splits at every size level
(defvar *inverses* nil)                   ; optional goal transformers, see TOTAL-INVERSES (section 6)
(defun residual (bank y)
  "ADDED, OPTIONAL: goal inversion.  If operator OP has a total inverse in
   argument P, then for each class K taken as the other argument the missing
   argument's column is forced: inverse(K, Y).  One hash probe says whether
   that column already exists as a class D; if so Y = OP(D, K) (or OP(K, D))."
  (loop for (name p inv-name c-first) in *inverses* do
    (let ((f (op-fn (first (ops inv-name)))))
      (loop for k across (bank-all bank)
            when (and (eq (cls-type k) :int) (not (find :err (cls-col k)))) do
              (let ((d (lookup bank (map 'simple-vector
                                         (lambda (yv kv) (if c-first (funcall f yv kv) (funcall f kv yv)))
                                         y (cls-col k)))))
                (incf *scan* (length y))
                (when d
                  (return-from residual
                    (if (= p 0) (list name (cls-term d) (cls-term k)) (list name (cls-term k) (cls-term d))))))))))
(defvar *occam* nil)                      ; T: a split is accepted only if no smaller single term exists
(defun solve-col (bank y max-size limit)
  "A term equal to the integer column Y on every row.  Iterative deepening on
   term size; after each size level: a single class (caught by the on-new hook)
   or else a ONE-guard split over the classes present (COVER).  Nested splits
   are tried only when the size budget is exhausted (they overfit otherwise).
   Default: the first fit is returned.  With *OCCAM* a split is only HELD, and
   enumeration continues until every single term smaller than it is excluded."
  (let ((goal (goal-exact :int y)) (rows (loop for r below (length y) collect r)) (held nil))
    (when (lookup bank y) (return-from solve-col (cls-term (lookup bank y))))
    (setf (bank-on-new bank) (lambda (c) (when (funcall goal c) (throw :stop c))))
    (loop for s from 2 to max-size do
      (let ((r (run bank s :limit limit)))
        (when (cls-p r) (return-from solve-col (cls-term r)))
        (unless held
          (setf held (or (and *inverses* (residual bank y))
                         (cover bank y rows (if (or *greedy* (= s max-size) (not (eq r :done))) 2 1)))))
        (when (or (not (eq r :done)) (and held (or (not *occam*) (>= s (1- (tsize held))))))
          (return))))
    held))

(defun solve-tabulate (base leaves ys max-size limit)
  "STEP 1 shape: L = len(ys) as a term over scalar leaves.  STEP 2 lift over the
   OUTPUT index: explode to rows (r,i), solve the scalar problem y = ys[i].
   STEP 3 (split) happens inside SOLVE-COL."
  (let ((shape (new-bank base *shape-ops*)) (lens (map 'simple-vector #'length ys)))
    (dolist (l leaves) (unless (eq (second l) :seq) (apply #'add-leaf shape l)))
    (let ((len-cls (search-goal shape (goal-exact :int lens) 7 limit)))
      (tally shape)
      (if (null len-cls)
          (progn (push "no shape term" *note*) nil)
          (multiple-value-bind (b2 i) (explode base lens)
            (let ((bank (new-bank b2 *d-ops*)) (yseq (pull b2 ys)))
              (assert (col= ys (collect b2 (elt-col yseq i))))  ; explode, then collect, is the identity
              (add-leaf bank 'i :int i)
              (dolist (l leaves) (add-leaf bank (first l) (second l) (pull b2 (third l))))
              (add-leaf bank 'prev :int (elt-col yseq i -1))   ; lag column: ys[i-1]
              (let ((elem (solve-col bank (elt-col yseq i) max-size limit)))
                (tally bank)
                (push (format nil "B'=~d rows, ~d classes" (base-n b2) (length (bank-all bank))) *note*)
                (when elem `(tabulate ,(cls-term len-cls) (lambda (i prev) ,elem))))))))))

(defun align (xs ys)
  "Keep-mask (one :t/:f per element of XS) picking YS out of XS as a subsequence,
   leftmost match; :fail if YS is not a subsequence."
  (let ((mask (loop for x in xs collect (if (and ys (eql x (car ys))) (progn (pop ys) :t) :f))))
    (if ys :fail mask)))
(defun index-mask (xs ys)
  "Keep-mask when YS is an increasing list of valid indices into XS; else :fail."
  (if (and (every (lambda (j) (< -1 j (length xs))) ys) (or (null ys) (apply #'< ys)))
      (loop for j below (length xs) collect (bool (member j ys)))
      :fail))

(defun solve-select (base leaves ys max-size limit)
  "STEP 4 lift over the INPUT index: explode a sequence input to rows (r,j),
   derive a latent boolean column keep_j, solve the boolean problem."
  (dolist (l leaves)
    (when (eq (second l) :seq)
      (dolist (form '(select where))
        (let ((keeps (map 'simple-vector (if (eq form 'select) #'align #'index-mask) (third l) ys)))
          (unless (find :fail keeps)
            (multiple-value-bind (b2 j) (explode base (map 'simple-vector #'length (third l)))
              (let ((bank (new-bank b2 *d-ops*)))
                (add-leaf bank 'j :int j)
                (add-leaf bank 'x :int (elt-col (pull b2 (third l)) j))
                (dolist (m leaves) (add-leaf bank (first m) (second m) (pull b2 (third m))))
                (let ((k (search-goal bank (goal-exact :bool (elt-col (pull b2 keeps) j)) max-size limit)))
                  (tally bank)
                  (push (format nil "~a: B''=~d rows" form (base-n b2)) *note*)
                  (when k
                    (return-from solve-select `(,form ,(first l) (lambda (j x) ,(cls-term k))))))))))))))

(defun solve-scalar (base leaves ys max-size limit)
  "Scalar output, no lift: all leaves on the example base (sequences read through AT)."
  (let ((bank (new-bank base *d-ops*)))
    (dolist (l leaves) (apply #'add-leaf bank l))
    (prog1 (solve-col bank ys max-size limit) (tally bank))))

(defun solve-fold (task exs limit)
  "ADDED MECHANISM (not a change of base): (fold init (lambda (acc x) step) xs).
   The accumulator is latent, so STEP cannot be posed as a column goal; instead
   each step CLASS from a small bank over leaves acc, x (deduped on a 7x7 probe
   grid) is run through the fold on every example: generate and test."
  (let* ((grid (loop for a from -3 to 3 append (loop for x from -3 to 3 collect (cons a x))))
         (bank (new-bank (make-base :n (length grid)) *d-ops*)) (tried 0)
         (seqs (loop for s in (task-ins task) when (eq (second s) :seq) collect (first s)))
         (inits (append '(0 1) (loop for s in (task-ins task) unless (eq (second s) :seq) collect (first s)))))
    (add-leaf bank 'acc :int (map 'simple-vector #'car grid))
    (add-leaf bank 'x :int (map 'simple-vector #'cdr grid))
    (dolist (k '(0 1)) (add-leaf bank k :int (make-array (length grid) :initial-element k)))
    (flet ((test (c)
             (when (eq (cls-type c) :int)
               (dolist (s seqs) (dolist (dir '(fold foldr)) (dolist (init inits)
                 (let ((prog `(,dir ,init (lambda (acc x) ,(cls-term c)) ,s)))
                   (incf tried)
                   (when (every (lambda (ex) (equal (cdr ex) (ev prog (car ex)))) exs)
                     (throw :stop prog)))))))))
      (let ((r (or (catch :stop (map nil #'test (bank-all bank)) nil)
                   (progn (setf (bank-on-new bank) #'test) (run bank 7 :limit limit)))))
        (tally bank)
        (push (format nil "~d fold programs tried, ~d step classes" tried (length (bank-all bank))) *note*)
        (and (consp r) r)))))

(defun timed (thunk)
  "Run THUNK with fresh counters; returns (result cand cells ms notes scan-cells)."
  (sb-ext:gc :full t)                     ; drop the previous task's bank before the clock starts
  (setf *cand* 0 *cells* 0 *scan* 0 *note* nil)
  (let* ((t0 (now)) (r (funcall thunk)))
    (list r *cand* *cells* (round (* 1000 (- (now) t0))) (reverse *note*) *scan*)))

(defun solve-task (task exs max-size limit)
  (let ((base (make-base :n (length exs))) (leaves (input-cols task exs))
        (ys (map 'simple-vector #'cdr exs)))
    (or (solve-tabulate base leaves ys max-size limit)
        (solve-select base leaves ys max-size limit))))

(defun exp-d (&key (seed 1) (nex 12) (max-size 10) (limit 30000000) (folds t))
  (format t "~%=== D. LIFT BY CHANGE OF BASE (seed ~d, ~d examples, max size ~d, budget ~d cand, greedy-nested-split ~a, occam ~a) ===~%grammar ~a~%goal inverses ~a~%"
          seed nex max-size limit *greedy* *occam* (mapcar #'op-name *d-ops*) *inverses*)
  (format t "~22a ~3a ~10a ~11a ~7a ~8a  program~%" "task" "ok" "cand" "cells" "ms" "held-out")
  (dolist (task *tasks*)
    (let ((exs (gen-examples task seed nex 7)))
      (destructuring-bind (prog cand cells ms notes scan) (timed (lambda () (solve-task task exs max-size limit)))
        (format t "~22a ~3a ~10d ~11d ~7d ~8a  ~s~%~26t[~{~a~^; ~}; split-scan cells ~d]~%"
                (task-name task) (if prog "yes" "NO") cand cells ms
                (if prog (format nil "~d/200" (verify task prog)) "-") prog notes scan))))
  (when folds (format t "~%--- D negatives: scalar-output folds ---~%"))
  (dolist (task (and folds *fold-tasks*))
    (let* ((exs (gen-examples task seed nex 7)) (base (make-base :n nex)) (leaves (input-cols task exs))
           (ys (map 'simple-vector #'cdr exs)))
      (destructuring-bind (prog cand cells ms notes scan)
          (timed (lambda () (solve-scalar base leaves ys 9 3000000)))
        (declare (ignore notes scan))
        (format t "~22a base-change only (size<=9): ~a  cand ~d cells ~d ms ~d~%" (task-name task)
                (if prog (format nil "~s held-out ~d/200" prog (verify task prog)) "FAIL") cand cells ms))
      (setf *steps* 0)
      (destructuring-bind (prog cand cells ms notes scan) (timed (lambda () (solve-fold task exs 3000000)))
        (declare (ignore scan))
        (format t "~22a + fold form: ~a  cand ~d cells ~d step-applications ~d ms ~d [~{~a~}]~%" ""
                (if prog (format nil "~s held-out ~d/200" prog (verify task prog)) "FAIL")
                cand cells *steps* ms notes)))))

(defun exp-d-seeds (&key (seeds '(2 3 4 5 6 7 8 9)) (max-size 10) (limit 30000000))
  "Robustness: the same procedure on other random example sets."
  (format t "~%=== D-seeds: per task over seeds ~a: solved / held-out-perfect, median cand, max ms ===~%" seeds)
  (dolist (task *tasks*)
    (let ((res (loop for seed in seeds collect
                 (let ((exs (gen-examples task seed 12 7)))
                   (destructuring-bind (prog cand cells ms notes scan)
                       (timed (lambda () (solve-task task exs max-size limit)))
                     (declare (ignore cells notes scan))
                     (list prog cand ms (and prog (verify task prog))))))))
      (format t "~22a solved ~d/~d  perfect ~d/~d  median-cand ~d  max-ms ~d~%" (task-name task)
              (count-if #'first res) (length res) (count 200 res :key #'fourth) (length res)
              (nth (floor (length res) 2) (sort (mapcar #'second res) #'<)) (reduce #'max res :key #'third))
      (loop for r in res for seed in seeds
            when (and (first r) (/= 200 (fourth r)))
              do (format t "~26tseed ~d IMPOSTOR ~d/200: ~s~%" seed (fourth r) (first r))))))

;;; ===================================================================
;;; SECTION 5: EXPERIMENT A -- growth and throughput
;;; ===================================================================
(defun probe-rows (n lo hi seed)
  "N rows (x y z) of random integers; the first three rows are made of 0, 1, -1."
  (let ((rs (sb-ext:seed-random-state seed)))
    (append '((0 1 -1) (1 -1 0) (-1 0 1))
            (loop repeat (- n 3) collect (loop repeat 3 collect (rnd rs lo hi))))))
(defun xyz-bank (rows opnames leaves)
  "Bank over the probe rows; LEAVES lists variables (x y z) and integer constants in creation order."
  (let ((bank (new-bank (make-base :n (length rows)) (apply #'ops opnames))))
    (dolist (v leaves bank)
      (add-leaf bank v :int (if (integerp v)
                                (make-array (length rows) :initial-element v)
                                (map 'simple-vector (lambda (r) (nth (position v '(x y z)) r)) rows))))))

(defun count-tuples (types total tab)
  "Ways to fill argument slots TYPES with items whose sizes sum to TOTAL, given
   TAB: (type . size) -> number of items.  With term counts this counts raw
   syntax (no dedupe); with class counts it predicts the candidates of a size."
  (if (null (cdr types))
      (gethash (cons (car types) total) tab 0)
      (loop for s1 from 1 below total
            sum (* (gethash (cons (car types) s1) tab 0) (count-tuples (cdr types) (- total s1) tab)))))
(defun syntactic-counts (ops nleaves smax)
  "Vector: number of syntactic terms (all types) per size, no dedupe, no evaluation."
  (let ((tab (make-hash-table :test 'equal)) (out (make-array (1+ smax) :initial-element 0)))
    (setf (gethash '(:int . 1) tab) nleaves (svref out 1) nleaves)
    (loop for s from 2 to smax do
      (dolist (ty '(:int :bool))
        (setf (gethash (cons ty s) tab)
              (loop for op in ops when (eq (op-res op) ty) sum (count-tuples (op-args op) (- s 1) tab)))
        (incf (svref out s) (gethash (cons ty s) tab))))
    out))
(defun max-size-within (cum budget) ; largest s with CUM[s+1] > budget, i.e. size s still fits
  (loop for s from 1 below 58 while (<= (aref cum (1+ s)) budget) finally (return s)))

(defvar *bytes-per-class* 453d0)          ; live bytes per stored class, re-measured below
(defvar *bytes-per-hash* 48d0)            ; live bytes per hash-only class, re-measured below
(defun exp-a (&key (secs 90) (cap 6000000) (ram-gb 24))
  "Per grammar: enumerate size by size for SECS seconds.  When storing the next
   size would exceed CAP classes (RAM), that size is run HASH-ONLY (new columns
   are counted by their 36-bit hash but not stored) and is the last one."
  (loop for (gname g) in `((g1 ,*g1*) (g2 ,*g2*) (g3 ,*g3*)) do
    (sb-ext:gc :full t)
    (let* ((mem0 (sb-kernel:dynamic-usage))
           (bank (xyz-bank (probe-rows 32 -9 9 7) g '(x y z 0 1 2)))
           (syn (syntactic-counts (bank-ops bank) 6 60)) (t0 (now)) (status :done) (s0 1)
           (tab (make-hash-table :test 'equal))           ; (type . size) -> class count
           (cand (make-array 60 :initial-element 0d0))    ; candidates per size (measured, then modelled)
           (cls (make-array 60 :initial-element 0d0)))    ; new classes per size
      (setf (aref cls 1) 6d0 (gethash '(:int . 1) tab) 6)
      (format t "~%=== A. ~a = ~a; 32 rows, leaves x y z 0 1 2; ~d s, class cap ~d ===~%" gname g secs cap)
      (format t "~4a ~12a ~11a ~12a ~11a ~8a ~18a ~7a ~a~%" "size" "cand@size" "new-cls" "cum-cand"
              "cum-cls" "new/cand" "syntactic@size" "sec" "status")
      (format t "~4d ~12d ~11d ~12d ~11d ~8a ~18d ~7,2f ~a~%" 1 0 6 0 6 "-" 6 0 :leaves)
      (flet ((predict (s) (loop for op in (bank-ops bank) sum (count-tuples (op-args op) (- s 1) tab))))
        (loop for s from 2 while (and (eq status :done) (not (bank-frontier bank))) do
          (let ((c0 (bank-ncand bank)) (k0 (length (bank-all bank))) (ts (now)) (pred (predict s)))
            (when (> (+ k0 (* pred (if (> s 3) (/ (aref cls (- s 2)) (aref cand (- s 2))) 1))) cap)
              (setf (bank-frontier bank) (make-hash-table)))
            (setf status (run bank s :seconds (- secs (- (now) t0))))
            (let* ((dc (- (bank-ncand bank) c0)) (nf (bank-nfront bank))
                   (dk (if (bank-frontier bank) (+ (getf nf :int 0) (getf nf :bool 0)) (- (length (bank-all bank)) k0))))
              (when (eq status :done)
                (assert (= dc pred))      ; candidates of a size are a pure function of smaller class counts
                (setf s0 s (aref cand s) (float dc 1d0) (aref cls s) (float dk 1d0))
                (dolist (ty '(:int :bool))
                  (setf (gethash (cons ty s) tab)
                        (if (bank-frontier bank) (getf nf ty 0) (length (classes bank ty s))))))
              (format t "~4d ~12d ~11d ~12d ~11d ~8,4f ~18d ~7,2f ~a~a~%" s dc dk (bank-ncand bank)
                      (+ k0 dk) (if (plusp dc) (/ dk dc 1.0) 0) (svref syn s) (- (now) ts) status
                      (if (bank-frontier bank) " (hash-only)" "")))))
        (setf (aref cand (1+ s0)) (float (predict (1+ s0)) 1d0))
        (format t "exact candidate count of the first incomplete size ~d (from class counts): ~d~%"
                (1+ s0) (predict (1+ s0))))
      (let* ((el (- (now) t0)) (rate (/ (bank-ncand bank) el))
             (nfr (if (bank-frontier bank) (hash-table-count (bank-frontier bank)) 0))
             (m1 (progn (sb-ext:gc :full t) (sb-kernel:dynamic-usage))))
        (setf (bank-frontier bank) nil)
        (sb-ext:gc :full t)
        (when (> nfr 100000) (setf *bytes-per-hash* (/ (- m1 (sb-kernel:dynamic-usage)) (float nfr 1d0))))
        (setf *bytes-per-class* (/ (- (sb-kernel:dynamic-usage) mem0) (float (length (bank-all bank)) 1d0)))
        (format t "throughput: ~,2e candidates/s, ~,2e cells/s (~,1f s); ~d stored classes at ~,0f live bytes each; ~d hash-only at ~,0f bytes each~%"
                rate (* 32 rate) el (length (bank-all bank)) *bytes-per-class* nfr *bytes-per-hash*)
        ;; Model beyond: per-parity two-step ratio of candidates; novelty (new/cand) of the last complete
        ;; size of the same parity.  (Sizes alternate because binary operators change size by 2.)
        (loop for s from (1+ s0) below 60 do
          (when (> s (1+ s0))
            (setf (aref cand s) (* (aref cand (- s 2))
                                   (if (evenp (- s s0)) (/ (aref cand s0) (aref cand (- s0 2)))
                                       (/ (aref cand (1+ s0)) (aref cand (- s0 1)))))))
          (setf (aref cls s) (* (aref cand s) (let ((u (if (evenp (- s s0)) s0 (1- s0))))
                                                (/ (aref cls u) (aref cand u))))))
        (let ((cumc (make-array 60 :initial-element 0d0)) (cumk (make-array 60 :initial-element 0d0))
              (cums (make-array 60 :initial-element 0d0)))
          (loop for s from 1 below 60 do
            (setf (aref cumc s) (+ (aref cumc (1- s)) (aref cand s)) (aref cumk s) (+ (aref cumk (1- s)) (aref cls s))
                  (aref cums s) (+ (aref cums (1- s)) (svref syn s))))
          (format t "two-step ratios cand(s)/cand(s-2):~{ ~,1f~}  classes:~{ ~,1f~}  (sizes ~d..~d)~%"
                  (loop for s from (max 4 (- s0 3)) to s0 collect (/ (aref cand s) (aref cand (- s 2))))
                  (loop for s from (max 4 (- s0 3)) to s0 collect (/ (aref cls s) (aref cls (- s 2))))
                  (max 4 (- s0 3)) s0)
          (format t "growth per unit size (latest two-step ratios): candidates x~,2f, classes x~,2f; syntactic terms x~,2f (at size 58)~%"
                  (expt (* (/ (aref cand s0) (aref cand (- s0 2))) (/ (aref cand (1+ s0)) (aref cand (- s0 1)))) 0.25)
                  (expt (* (/ (aref cls s0) (aref cls (- s0 2))) (/ (aref cls (- s0 1)) (aref cls (- s0 3)))) 0.25)
                  (sqrt (/ (svref syn 59) (svref syn 57) 1d0)))
          (format t "extrapolation (largest size FULLY enumerable at the measured rate):~%")
          (flet ((gb-all (s) (/ (* (aref cumk s) *bytes-per-class*) 1d9))       ; every class stored
                 (gb-top (s) (/ (+ (* (aref cumk (1- s)) *bytes-per-class*)     ; top size hash-only
                                   (* (aref cls s) *bytes-per-hash*)) 1d9)))
            (loop for (label tsec) in '(("1 min" 60) ("1 hour" 3600) ("10 hours" 36000)) do
              (let ((with (max-size-within cumc (* rate tsec))) (without (max-size-within cums (* rate tsec))))
                (format t "  ~9a time-limited, with dedupe: size ~2d (RAM: ~,1f GB all stored, ~,1f GB top size hash-only) | without dedupe: size ~2d~%"
                        label with (gb-all with) (gb-top with) without)))
            (let ((sm (loop for s from 3 below 57 while (<= (gb-top (1+ s)) ram-gb) finally (return s))))
              (format t "  memory-limited at ~d GB (top size hash-only): size ~d, reached after ~,0f s (~,2f h)~%"
                      ram-gb sm (/ (aref cumc sm) rate) (/ (aref cumc sm) rate 3600)))))))))

;;; ===================================================================
;;; SECTION 6: EXPERIMENT C -- inverses and guards from functional dependencies
;;; ===================================================================
(defun fd-probe (name p &key (pad 0) (limit 300000) (wide 40))
  "For c = op(a,b) on the grid a,b in -6..6: is argument P a function of (other
   argument, c)?  Returns (fraction-of-rows-where-it-is  found-classes  goals  bank).
   PAD widens the range of the inverted argument when the groups are formed, so
   that 'unique in its group' is not an artifact of the grid boundary.  WIDE is
   a much larger range used only to list every preimage (for the section goal)."
  (let* ((op (first (ops name))) (unary (= 1 (op-arity op)))
         (rows                            ; (inverted-arg other-arg c) with :err rows dropped
           (loop for tgt from (- -6 wide) to (+ 6 wide) append
             (loop for oth in (if unary '(0) (loop for v from -6 to 6 collect v))
                   for c = (cond (unary (funcall (op-fn op) tgt))
                                 ((= p 0) (funcall (op-fn op) tgt oth))
                                 (t (funcall (op-fn op) oth tgt)))
                   unless (eq c :err) collect (list tgt oth c))))
         (groups (make-hash-table :test 'equal))) ; (other . c) -> every inverted-arg value giving c
    (dolist (r rows) (push (first r) (gethash (cons (second r) (third r)) groups)))
    (let* ((inner (remove-if-not (lambda (r) (<= -6 (first r) 6)) rows)) (n (length inner))
           (pre (map 'simple-vector (lambda (r) (gethash (cons (second r) (third r)) groups)) inner))
           (mask (map 'simple-vector      ; row lies in a group with ONE value (within the pad)
                      (lambda (s) (= 1 (count-if (lambda (v) (<= (- -6 pad) v (+ 6 pad))) s))) pre))
           (frac (/ (count t mask) n)) (total (= frac 1))
           (target (map 'simple-vector #'first inner))
           (bank (new-bank (make-base :n n) (apply #'ops (if total *g2* *g3*)))))
      (unless unary (add-leaf bank (if (= p 0) 'b 'a) :int (map 'simple-vector #'second inner)))
      (add-leaf bank 'c :int (map 'simple-vector #'third inner))
      (dolist (k '(0 1)) (add-leaf bank k :int (make-array n :initial-element k)))
      (let ((goals (if total
                       `((:inv . ,(goal-exact :int target)))
                       `(,@(when (> frac 0)
                             `((:guard . ,(goal-exact :bool (map 'simple-vector #'bool mask)))
                               (:inv . ,(goal-masked :int target mask))))
                         (:section . ,(goal-allowed :int pre))))))
        (list frac (search-goals bank goals 9 limit) goals bank)))))

(defun exp-c (&key (pad 0) (limit 300000))
  (format t "~%=== C. INVERSES FROM FUNCTIONAL DEPENDENCIES (grid -6..6, pad ~d, budget ~d cand, size<=9) ===~%" pad limit)
  (format t "~4a ~3a ~6a ~24a ~14a ~32a ~7a ~4a ~5a~%" "op" "arg" "FD%" "guard" "inverse" "section (any preimage)" "cand" "done" "ms")
  (dolist (name '(+ - * neg div mod max))
    (dotimes (p (op-arity (first (ops name))))
      (let ((t0 (now)))
        (destructuring-bind (frac found goals bank) (fd-probe name p :pad pad :limit limit)
          (flet ((show (k) (let ((c (cdr (assoc k found))))
                             (cond (c (format nil "~s [~d]" (cls-term c) (cls-size c)))
                                   ((assoc k goals) "not found") (t "-")))))
            (format t "~4a ~3a ~6,1f ~24a ~14a ~32a ~7d ~4d ~5d~%" name (if (= p 0) 'a 'b) (* 100.0 frac)
                    (show :guard) (show :inv) (show :section) (bank-ncand bank) (bank-done bank)
                    (round (* 1000 (- (now) t0))))))))))

(defun total-inverses (ops)
  "Goal transformers for experiment D, DERIVED by the probe above rather than
   written by hand: (op p inverse-op c-first?) for each binary integer operator
   and argument P whose dependency holds everywhere with a one-operator inverse."
  (loop for op in ops when (and (equal (op-args op) '(:int :int)) (eq (op-res op) :int)) append
    (loop for p below 2
          for (frac found) = (fd-probe (op-name op) p :pad 3 :limit 20000)
          for inv = (and (= frac 1) (cdr (assoc :inv found)))
          when (and inv (= 3 (cls-size inv)))
            collect (list (op-name op) p (first (cls-term inv)) (eq 'c (second (cls-term inv)))))))

;;; ===================================================================
;;; SECTION 7: EXPERIMENT B -- laws from collisions, pruned by ordered rewriting
;;; ===================================================================
(defvar *rank* '(x y z 0 1 + * neg))      ; leaf order (= leaf creation order), then operator order
(defun term< (a b)
  "Total order on terms: size first, then lexicographic by *RANK*.  Because the
   enumerator creates classes in exactly this order, a class representative is
   the earliest term of its class."
  (let ((sa (tsize a)) (sb (tsize b)))
    (flet ((rank (s) (position s *rank*)))
      (cond ((/= sa sb) (< sa sb))
            ((atom a) (< (rank a) (rank b)))
            ((not (eq (car a) (car b))) (< (rank (car a)) (rank (car b))))
            (t (loop for p in (cdr a) for q in (cdr b)
                     do (cond ((term< p q) (return t)) ((term< q p) (return nil)))))))))
(defun pmatch (pat term binds)
  "One-way match: the variables x y z of a law match any term; constants and
   operators match themselves.  Returns the bindings, or :fail."
  (cond ((member pat '(x y z))
         (let ((b (assoc pat binds)))
           (cond ((null b) (acons pat term binds)) ((equal (cdr b) term) binds) (t :fail))))
        ((atom pat) (if (eql pat term) binds :fail))
        ((or (atom term) (not (eq (car pat) (car term)))) :fail)
        (t (loop for p in (cdr pat) for u in (cdr term)
                 do (setf binds (pmatch p u binds)) (when (eq binds :fail) (return :fail))
                 finally (return binds)))))
(defun instance (pat binds)
  (cond ((member pat '(x y z)) (cdr (assoc pat binds)))
        ((atom pat) pat)
        (t (cons (car pat) (mapcar (lambda (p) (instance p binds)) (cdr pat))))))
(defun rewrite1 (term rules)
  "A term EARLIER than TERM reached by one instance of a kept law (at the root
   or inside), or nil.  RULES: ((lhs . rhs) ...), both directions of each law."
  (or (loop for (l . r) in rules
            do (let ((b (pmatch l term nil)))
                 (unless (eq b :fail)
                   (let ((new (instance r b))) (when (term< new term) (return new))))))
      (and (consp term)
           (loop for arg in (cdr term) for k from 1
                 do (let ((new (rewrite1 arg rules)))
                      (when new (return (append (subseq term 0 k) (list new) (nthcdr (1+ k) term)))))))))
(defun normalize (term rules)
  (loop for new = (rewrite1 term rules) while new do (setf term new) finally (return term)))
(defun vars (e)
  (cond ((member e '(x y z)) (list e)) ((atom e) nil) (t (reduce #'union (mapcar #'vars (cdr e))))))
(defun oriented (a b)
  "Rewrite directions of the law a = b whose right side introduces no new variable."
  (append (when (and (consp a) (subsetp (vars b) (vars a))) (list (cons a b)))
          (when (and (consp b) (subsetp (vars a) (vars b))) (list (cons b a)))))

(defparameter *named-laws*
  '(("commutativity +" (+ y x) (+ x y)) ("commutativity *" (* y x) (* x y))
    ("associativity +" (+ (+ x y) z) (+ x (+ y z))) ("associativity *" (* (* x y) z) (* x (* y z)))
    ("identity x+0" (+ x 0) x) ("identity x*1" (* x 1) x) ("zero x*0" (* x 0) 0)
    ("double negation" (neg (neg x)) x) ("distributivity" (* x (+ y z)) (+ (* x y) (* x z)))))

(defun inter-reduce (laws)
  "ADDED post-pass: drop a law when its two sides rewrite to one normal form
   using only the OTHER kept laws (earlier special cases of later general laws)."
  (let ((keep (copy-list laws)))
    (dolist (w laws keep)
      (let ((rules (loop for v in keep unless (eq v w) append (oriented (first v) (second v)))))
        (when (equal (normalize (first w) rules) (normalize (second w) rules))
          (setf keep (remove w keep)))))))

(defun exp-b (&key (max-size 7) (secs 60) (nrows 32) (leaves '(x y z 0 1)) brief)
  (let* ((*rank* (append leaves '(+ * neg)))
         (bank (xyz-bank (probe-rows nrows -9 9 7) '(+ * neg) leaves))
         (laws '()) (rules '()) (first-at '()) (t0 (now)))
    (format t "~%=== B. LAWS FROM COLLISIONS: {+ * neg}, leaf order ~a, ~d rows, size<=~d ===~%" leaves nrows max-size)
    (setf (bank-on-coll bank)
          (lambda (old op c1 c2 c3)
            (declare (ignore c3))
            (let* ((new (list* (op-name op) (cls-term c1) (and c2 (list (cls-term c2)))))
                   (rep (cls-term old)) (big (if (term< rep new) new rep)) (small (if (eq big new) rep new)))
              (unless (rewrite1 big rules)   ; redundant: a kept law already rewrites the larger side
                (push (list big small (bank-done bank)) laws)
                (setf rules (append rules (oriented big small)))))))
    (unless (eq brief t) (format t "~4a ~10a ~10a ~10a ~8a ~6a~%" "size" "cand" "collisions" "classes" "laws" "sec"))
    (loop for s from 2 to max-size do
      (let ((r (run bank s :seconds (- secs (- (now) t0)))))
        (unless (eq brief t)
          (format t "~4d ~10d ~10d ~10d ~8d ~6,2f ~a~%" s (bank-ncand bank) (bank-ncoll bank)
                  (length (bank-all bank)) (length laws) (- (now) t0) r))
        (loop for (name l r2) in *named-laws*   ; derivable yet? both sides reach one normal form
              unless (assoc name first-at :test #'string=)
                do (when (equal (normalize l rules) (normalize r2 rules)) (push (cons name s) first-at)))
        (unless (eq r :done) (return))))
    (setf laws (reverse laws))
    (format t "raw collisions ~d, kept laws ~d (~a after inter-reduction), time ~,2f s~%"
            (bank-ncoll bank) (length laws)
            (if (< (length laws) 2500) (length (inter-reduce laws)) "not computed: quadratic") (- (now) t0))
    (unless brief
      (format t "first kept laws ([n] = size being enumerated when found):~%")
      (loop for (big small s) in laws for k from 1 to 40
            do (format t "  ~2d. [~d] ~s = ~s~%" k (1+ s) big small))
      (format t "kept laws by size of the larger side: ~{~a~^, ~}~%"
              (loop for s from 2 to max-size
                    collect (format nil "~d:~d" s (count s laws :key (lambda (l) (tsize (first l)))))))
      (format t "laws surviving inter-reduction:~%~{  ~a~%~}"
              (loop for (big small) in (inter-reduce laws) for k from 1 to 40
                    collect (format nil "~s = ~s" big small)))
      (format t "named laws: size at which the two sides first rewrite to one normal form; * = also literally kept~%")
      (loop for (name l r) in *named-laws*
            do (format t "  ~18a ~a~a~%" name (or (cdr (assoc name first-at :test #'string=)) "NOT derivable")
                       (if (find-if (lambda (w) (or (and (equal (first w) l) (equal (second w) r))
                                                    (and (equal (first w) r) (equal (second w) l))))
                                    laws)
                           " *" ""))))
    (let* ((rs (sb-ext:seed-random-state 4242))
           (envs (loop repeat 1000 collect (loop for v in '(x y z) collect (cons v (rnd rs -1000 1000)))))
           (bad (remove-if (lambda (w) (every (lambda (env) (equal (ev (first w) env) (ev (second w) env))) envs))
                           laws)))
      (format t "laws false on 1000 fresh rows in -1000..1000: ~d of ~d~%" (length bad) (length laws))
      (loop for w in bad for k from 1 to 5 do (format t "  SPURIOUS ~s = ~s~%" (first w) (second w))))))

;;; ===================================================================
;;; SECTION 8: MAIN
;;; ===================================================================
(defun main (which)
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
    (ecase which
      (:d (exp-d)
       (let ((*greedy* t)) (exp-d :folds nil))                       ; variant: nested splits at every level
       (let ((*d-ops* (apply #'ops (append *g3* '(at call)))))            ; variant: every operator of the probe
         (exp-d :folds nil :limit 12000000)
         (let ((*inverses* (total-inverses *d-ops*))) (exp-d :folds nil :limit 12000000))) ; + goal inversion
       (let ((*inverses* (total-inverses *d-ops*))) (exp-d :folds nil)))
      (:docc (let ((*occam* t))                                       ; variant: size-minimal split acceptance
               (exp-d :folds nil :limit 15000000) (exp-d-seeds :limit 15000000)))
      (:dseeds (exp-d-seeds)
       (let ((*greedy* t)) (format t "~%with greedy nested splits") (exp-d-seeds))
       (let ((*inverses* (total-inverses *d-ops*)))
         (format t "~%with goal inverses ~a" *inverses*) (exp-d-seeds)))
      (:a (exp-a))
      (:c (exp-c :pad 0) (exp-c :pad 3))
      (:b (exp-b :max-size 7)
       (exp-b :max-size 7 :leaves '(0 1 x y z))                      ; sensitivity: term order
       (exp-b :max-size 14 :brief :table)                            ; how far 60 s goes
       (dolist (n '(3 4 6 8 12)) (exp-b :max-size 7 :nrows n :brief t)))) ; sensitivity: probe rows
    (finish-output)))
