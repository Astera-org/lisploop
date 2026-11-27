;;;; labels.lisp -- L1: quotient labels, verb tables and a label filter INSIDE the tg-probe store.
;;;; Loaded AFTER tg-probe-l1.lisp (the probe copy carrying the hooks marked "L1 MOD").
;;;; Everything in this file is new.  Sections:
;;;;   1 quotients | 2 verb tables (one group-by over joint probes) | 3 the filter context
;;;;   4 the candidate test | 5 passes over a size level | 6 look-ahead (decline to store) | 7 bookkeeping
(in-package :tg)
(declaim (optimize (speed 2) (safety 1) (debug 0)))

;;; ===================================================================
;;; 1. QUOTIENTS: a cell -> a small label.  Nothing here names a task.
;;; ===================================================================
(defstruct quot
  name
  nint      ; integers get labels 0..NINT-1; label NINT is "undefined" (the :err cell)
  int-fn    ; integer -> 0..NINT-1
  seqlab)   ; NIL: every sequence has the same label ("anything").
            ; T:   a sequence is labelled by the SET of its elements' labels (a bitmask), so that
            ;      "all even", "no negative element", "all = 1 mod 3" are particular labels.
(defparameter *sym-names* '(+ - * pos even neg)) ; function-/predicate-valued cells are labelled by their name

(defun make-q (name &optional seqlab)
  (ecase name
    (def  (make-quot :name name :nint 1 :seqlab seqlab :int-fn (lambda (v) (declare (ignore v)) 0))) ; defined or not
    (par  (make-quot :name name :nint 2 :seqlab seqlab :int-fn (lambda (v) (if (evenp v) 0 1))))
    (mod3 (make-quot :name name :nint 3 :seqlab seqlab :int-fn (lambda (v) (mod v 3))))
    (sgn  (make-quot :name name :nint 3 :seqlab seqlab
                     :int-fn (lambda (v) (cond ((minusp v) 0) ((zerop v) 1) (t 2)))))))

(defun nlab (q type)
  "Number of labels quotient Q gives to cells of TYPE."
  (ecase type
    (:int (1+ (quot-nint q)))
    (:bool 3)                                              ; :t :f :err
    ((:code :pred) (1+ (length *sym-names*)))
    (:seq (if (quot-seqlab q) (ash 1 (quot-nint q)) 1))))
(defun cell-label (q type v)
  (ecase type
    (:int (if (integerp v) (funcall (quot-int-fn q) v) (quot-nint q)))
    (:bool (case v (:t 0) (:f 1) (t 2)))
    ((:code :pred) (or (position v *sym-names*) (length *sym-names*)))
    (:seq (if (quot-seqlab q)
              (let ((m 0)) (dolist (e v m) (setf m (logior m (ash 1 (funcall (quot-int-fn q) e))))))
              0))))

;;; The one quotient on a PAIR: where index J falls relative to sequence S.  It is the natural label
;;; of the (position, length) pair on a lifted space, and it predicts whether (at S J) is defined.
(declaim (inline pair-label))
(defun pair-label (s j)
  (cond ((not (integerp j)) 3) ((< j 0) 0) ((< j (length (the list s))) 1) (t 2)))

;;; ===================================================================
;;; 2. VERB TABLES: for one operator and one quotient, the table from the labels of the inputs
;;;    to the SET of output labels seen (a bitmask), by one group-by over JOINT probes of all arguments.
;;; ===================================================================
(defvar *grid* '(-12 12))                 ; integer probe grid lo..hi (plus the undefined cell)
(defvar *probe-seqs* nil)
(defun probe-seqs ()
  "703 probe sequences, fixed seed: (), every sequence of length 1..3 over -2..3, 300 random of
   length 4..8 over -6..10, and 144 drawn from a single label class of a quotient (edge cases)."
  (or *probe-seqs*
      (setf *probe-seqs*
            (let ((rs (sb-ext:seed-random-state 20261126)) (out (list nil)) (al '(-2 -1 0 1 2 3)))
              (dolist (a al)
                (push (list a) out)
                (dolist (b al) (push (list a b) out) (dolist (c al) (push (list a b c) out))))
              (loop repeat 300 do (push (loop repeat (rnd rs 4 8) collect (rnd rs -6 10)) out))
              (dolist (pool '((-6 -4 -2 0 2 4 6 8) (-5 -3 -1 1 3 5 7 9) (-6 -3 0 3 6 9) (-5 -2 1 4 7) (-4 -1 2 5 8)
                              (-6 -5 -4 -3 -2 -1) (1 2 3 4 5 6 7 8 9) (0) (0 1 2 3 4 5 6) (-3 -2 -1 0)
                              (-6 -4 -2 2 4 6) (-5 -3 -1 1 3 5)))
                (loop repeat 12 do
                  (push (loop repeat (rnd rs 1 8) collect (nth (random (length pool) rs) pool)) out)))
              (nreverse out)))))
(defun probe-values (type)
  (ecase type
    (:int (cons :err (loop for v from (first *grid*) to (second *grid*) collect v)))
    (:bool '(:t :f :err))
    (:code '(+ - *))
    (:pred '(pos even neg))
    (:seq (probe-seqs))))

(defun cell-apply (op x y z)
  "One cell of OP with exactly the conventions of TRY (strict in :err; IF lazy in the branch not taken)."
  (let ((fn (op-fn op)) (k (op-arity op)))
    (cond ((eq x :err) :err)
          ((= k 1) (funcall fn x))
          ((null fn) (if (eq x :t) y z))
          ((or (eq y :err) (eq z :err)) :err)
          ((= k 3) (funcall fn x y z))
          (t (funcall fn x y)))))
(defun map-probes (op fn)
  "Call FN on every joint probe (x y z) of OP's argument grid (unused arguments are NIL)."
  (let ((vals (mapcar #'probe-values (op-args op))))
    (dolist (x (first vals))
      (if (null (cdr vals))
          (funcall fn x nil nil)
          (dolist (y (second vals))
            (if (null (cddr vals))
                (funcall fn x y nil)
                (dolist (z (third vals)) (funcall fn x y z))))))))

(defstruct vt tab n1 n12 nprobe trivial dep)
(defvar *vts* (make-hash-table :test 'equal))
(defun entropy (counts)
  (let ((tot (reduce #'+ counts)))
    (if (zerop tot) 0d0
        (- (loop for c in counts when (plusp c) sum (* (/ c tot 1d0) (log (/ c tot 1d0) 2)))))))
(defun build-vt (op q)
  (let* ((types (op-args op)) (rt (op-res op))
         (n1 (nlab q (first types))) (n2 (if (second types) (nlab q (second types)) 1))
         (n3 (if (third types) (nlab q (third types)) 1)) (nout (nlab q rt))
         (tab (make-array (* n1 n2 n3) :initial-element 0)) (np 0)
         (cnt (make-array (list (* n1 n2 n3) nout) :initial-element 0)))
    (map-probes op (lambda (x y z)
                     (let ((idx (+ (cell-label q (first types) x)
                                   (if (second types) (* n1 (cell-label q (second types) y)) 0)
                                   (if (third types) (* n1 n2 (cell-label q (third types) z)) 0)))
                           (ol (cell-label q rt (cell-apply op x y z))))
                       (incf np) (incf (aref cnt idx ol))
                       (setf (svref tab idx) (logior (svref tab idx) (ash 1 ol))))))
    (let* ((nonerr (1- (ash 1 (1- nout))))   ; the labels a defined target can have
           (hout (entropy (loop for o below nout collect (loop for i below (length tab) sum (aref cnt i o)))))
           (hcond (/ (loop for i below (length tab)
                           sum (let ((row (loop for o below nout collect (aref cnt i o))))
                                 (* (reduce #'+ row) (entropy row))))
                     (max np 1))))
      (dotimes (i (length tab)) (when (zerop (svref tab i)) (setf (svref tab i) -1))) ; inputs never seen: anything
      (make-vt :tab tab :n1 n1 :n12 (* n1 n2) :nprobe np
               :trivial (every (lambda (m) (= (logand m nonerr) nonerr)) tab) ; can never rule a defined label out
               :dep (if (< hout 1d-9) 0d0 (- 1 (/ hcond hout)))))))          ; dependency score, COMMON.md
(defun verb-table (op q)
  (let ((key (list (op-name op) (quot-name q) (quot-seqlab q) *grid*)))
    (or (gethash key *vts*) (setf (gethash key *vts*) (build-vt op q)))))
(defun pair-table (op)
  "Group-by over the same joint probes: PAIR-LABEL of (sequence, index) -> {defined, undefined} seen."
  (let ((key (list (op-name op) :pair *grid*)))
    (or (gethash key *vts*)
        (setf (gethash key *vts*)
              (let ((tab (make-array 4 :initial-element 0)))
                (map-probes op (lambda (s j z)
                                 (let ((l (pair-label s j)))
                                   (setf (svref tab l)
                                         (logior (svref tab l) (if (eq (cell-apply op s j z) :err) 2 1))))))
                (substitute -1 0 tab))))))

;;; ===================================================================
;;; 3. THE FILTER CONTEXT attached to a bank once its target column is known
;;; ===================================================================
(defvar *lf-cfg* nil)   ; NIL = plain search.  Else a plist:
                        ;   :mode  :first  evaluate label-feasible candidates of a level first, then the rest
                        ;          :strict at size level :LEVEL (an ORACLE) evaluate only the feasible; never the rest
                        ;          :la     look-ahead with size bound :LEVEL (restarts per bound if :LEVEL is nil)
                        ;          :audit  plain search, but test every candidate and count false rejects
                        ;   :qs (def par mod3 sgn ...)   :seqlab T|NIL   :pair T|NIL   :nchk rows checked (NIL = all)
(defstruct te qi tab n1 n12)                ; one useful verb table of an operator
(defstruct gate type-ok tabs pair)          ; what the filter knows about one operator, for this bank's target
(defstruct lf
  mode ops qs rows (nchk 0 :type fixnum) ttype target tlab pairq level keep-bool
  (gates nil)
  (bits (make-array 4096 :element-type 'bit) :type simple-bit-vector) (nbit 0 :type fixnum) (cursor 0 :type fixnum)
  (nfeas 0 :type fixnum)    ; candidates the tables could not rule out (evaluated first)
  (nskip 0 :type fixnum)    ; candidates ruled out by a label
  (ntype 0 :type fixnum)    ; candidates ruled out by result type alone (no look-up)
  (nlook 0 :type fixnum)    ; table look-ups
  (ndecl 0 :type fixnum)    ; classes evaluated but not stored (look-ahead)
  (nfalse 0 :type fixnum)   ; audit: ruled-out candidates that in fact equal the target
  (nrestl 0 :type fixnum)   ; label-ruled-out candidates evaluated after all (pass B of a completed level)
  (nrestt 0 :type fixnum)   ; type-ruled-out candidates evaluated after all (pass B)
  (nprobe 0 :type fixnum)   ; candidates given the exact row-by-row test (PROBE-MATCH)
  (ncell 0 :type fixnum)    ; cells evaluated by that test
  (nlab 0 :type fixnum)     ; label cells computed (quotient applied to one cell of a stored class)
  pending dtab uses ubhist)

(defun col-labels (lf type col)
  "The label columns of COL: one (unsigned-byte 8) vector per quotient, over the checked rows."
  (declare (optimize (speed 3) (safety 0)) (simple-vector col))
  (let* ((qs (lf-qs lf)) (rows (lf-rows lf)) (n (lf-nchk lf)) (out (make-array (length (the list qs)))))
    (declare (simple-vector rows out) (fixnum n))
    (incf (lf-nlab lf) (the fixnum (* n (length out))))
    (loop for q in qs for qi fixnum from 0 do
      (let ((v (make-array n :element-type '(unsigned-byte 8))))
        (if (eq type :int)
            (let ((f (quot-int-fn q)) (e (quot-nint q)))
              (declare (function f))
              (dotimes (k n)
                (let ((x (svref col (the fixnum (svref rows k)))))
                  (setf (aref v k) (if (eq x :err) e (funcall f x))))))
            (dotimes (k n) (setf (aref v k) (cell-label q type (svref col (the fixnum (svref rows k)))))))
        (setf (svref out qi) v)))
    out))
(defun lf-label-class (lf c)
  (setf (cls-labs c) (or (shiftf (lf-pending lf) nil) (col-labels lf (cls-type c) (cls-col c)))))

(defun lf-attach (bank type col mode level)
  (let* ((cfg *lf-cfg*) (n (length col)) (k (min n (or (getf cfg :nchk) n)))
         (rows (coerce (loop for j below k collect (floor (* j n) k)) 'simple-vector)) ; evenly spaced rows
         (lf (make-lf :mode mode :ops (bank-ops bank) :rows rows :nchk k :ttype type :target col
                      :qs (mapcar (lambda (nm) (make-q nm (getf cfg :seqlab))) (getf cfg :qs))
                      :pairq (getf cfg :pair) :level level :keep-bool (getf cfg :keep-bool)
                      :ubhist (and (getf cfg :ubhist) (make-array (1+ k) :initial-element 0)))))
    (setf (lf-tlab lf) (col-labels lf type col)
          (bank-lf bank) lf)
    (loop for c across (bank-all bank) do (lf-label-class lf c))
    lf))

(defun make-gate-for (lf op)
  (let* ((same (eq (op-res op) (lf-ttype lf)))
         (ok (or same (and (lf-keep-bool lf) (eq (op-res op) :bool))))) ; :keep-bool: guards are never filtered
    (make-gate :type-ok ok
               :tabs (and same (loop for q in (lf-qs lf) for qi from 0
                                   for vt = (verb-table op q)
                                   unless (vt-trivial vt)   ; a table that says "anything" costs no look-up
                                     collect (make-te :qi qi :tab (vt-tab vt) :n1 (vt-n1 vt) :n12 (vt-n12 vt))))
               :pair (and same (lf-pairq lf) (equal (op-args op) '(:seq :int)) (pair-table op)))))

;;; ===================================================================
;;; 4. THE CANDIDATE TEST: could OP on these argument classes give the target's label on every
;;;    checked row, under every quotient?  Early exit at the first (quotient, row) that says no.
;;; ===================================================================
(defun feasible-p (lf gate c1 c2 c3)
  (declare (optimize (speed 3) (safety 0)) (type lf lf) (type gate gate))
  (if (not (gate-type-ok gate))
      (progn (incf (lf-ntype lf)) nil)
      (let ((look 0) (nr (lf-nchk lf)) (ok t) (tlabs (lf-tlab lf)))
        (declare (fixnum look nr) (simple-vector tlabs))
        (block check
          (let ((pt (gate-pair gate)))    ; the pair quotient first: is the index inside the sequence?
            (when pt
              (let ((a (cls-col c1)) (b (cls-col c2)) (rows (lf-rows lf)))
                (declare (simple-vector a b rows pt))
                (dotimes (r nr)
                  (let ((row (svref rows r)))
                    (declare (fixnum row))
                    (incf look)
                    (unless (logbitp 0 (the fixnum (svref pt (pair-label (svref a row) (svref b row)))))
                      (setf ok nil) (return-from check)))))))
          (dolist (e (gate-tabs gate))
            (let* ((qi (te-qi e)) (tab (te-tab e)) (n1 (te-n1 e)) (n12 (te-n12 e))
                   (tl (svref tlabs qi))
                   (l1 (svref (the simple-vector (cls-labs c1)) qi))
                   (l2 (if c2 (svref (the simple-vector (cls-labs c2)) qi) l1))
                   (l3 (if c3 (svref (the simple-vector (cls-labs c3)) qi) l1)))
              (declare (fixnum qi n1 n12) (simple-vector tab)
                       (type (simple-array (unsigned-byte 8) (*)) tl l1 l2 l3))
              (dotimes (r nr)
                (let ((idx (aref l1 r)))
                  (declare (fixnum idx))
                  (when c2 (incf idx (the fixnum (* n1 (aref l2 r)))))
                  (when c3 (incf idx (the fixnum (* n12 (aref l3 r)))))
                  (incf look)
                  (unless (logbitp (aref tl r) (the fixnum (svref tab idx)))
                    (setf ok nil) (return-from check)))))))
        (incf (lf-nlook lf) look)
        (if ok (incf (lf-nfeas lf)) (incf (lf-nskip lf)))
        ok)))

(defun allow-count (lf gate c1 c2 c3)
  "Number of checked rows on which NO quotient rules the target's label out (no early exit): an upper
   bound on the rows this candidate can match.  Used only for the near-miss statistics."
  (let* ((nr (lf-nchk lf)) (bad (make-array nr :element-type 'bit :initial-element 0)))
    (let ((pt (gate-pair gate)))
      (when pt
        (dotimes (r nr)
          (let ((row (svref (lf-rows lf) r)))
            (unless (logbitp 0 (svref pt (pair-label (svref (cls-col c1) row) (svref (cls-col c2) row))))
              (setf (sbit bad r) 1))))))
    (dolist (e (gate-tabs gate))
      (let* ((qi (te-qi e)) (tl (svref (lf-tlab lf) qi)) (l1 (svref (cls-labs c1) qi))
             (l2 (and c2 (svref (cls-labs c2) qi))) (l3 (and c3 (svref (cls-labs c3) qi))))
        (dotimes (r nr)
          (unless (logbitp (aref tl r)
                           (svref (te-tab e) (+ (aref l1 r) (if l2 (* (te-n1 e) (aref l2 r)) 0)
                                                (if l3 (* (te-n12 e) (aref l3 r)) 0))))
            (setf (sbit bad r) 1)))))
    (- nr (count 1 bad))))

;;; ===================================================================
;;; 5. PASSES OVER ONE SIZE LEVEL
;;; ===================================================================
(defun lf-gate (lf op s)
  (let ((g (or (cdr (assoc op (lf-gates lf)))
               (cdar (push (cons op (make-gate-for lf op)) (lf-gates lf))))))
    (if (and (eq (lf-mode lf) :la) (lf-op-dead-p lf op s)) :dead g)))

(declaim (inline push-bit))
(defun push-bit (lf ok)
  (let ((n (lf-nbit lf)) (b (lf-bits lf)))
    (declare (fixnum n) (simple-bit-vector b))
    (when (>= n (length b))
      (let ((nb (make-array (* 2 (length b)) :element-type 'bit)))
        (replace nb b) (setf (lf-bits lf) nb b nb)))
    (setf (sbit b n) (if ok 1 0) (lf-nbit lf) (1+ n))))

(defun lf-gated-try (bank op s c1 c2 c3 pass gate)
  (let ((lf (bank-lf bank)))
    (ecase pass
      (:first                             ; pass A: evaluate what the tables cannot rule out; remember the rest
       (let ((ok (feasible-p lf gate c1 c2 c3)))
         (push-bit lf ok)
         (when ok (try bank op s c1 c2 c3))))
      (:rest                              ; pass B: evaluate what pass A left (one bit per candidate, no look-up)
       (let ((k (lf-cursor lf)))
         (setf (lf-cursor lf) (1+ k))
         (when (zerop (sbit (lf-bits lf) k))
           (if (gate-type-ok gate) (incf (lf-nrestl lf)) (incf (lf-nrestt lf)))
           (try bank op s c1 c2 c3))))
      (:strict                            ; the last level, if one knew it was the last: the rest is never evaluated
       (when (feasible-p lf gate c1 c2 c3) (try bank op s c1 c2 c3)))
      (:probe                             ; NO labels: the exact test against the target, row by row, first mismatch stops
       (when (and (gate-type-ok gate) (probe-match lf op c1 c2 c3)) (try bank op s c1 c2 c3)))
      (:lfprobe                           ; the label test, then the exact row-by-row test on what it lets through
       (when (and (feasible-p lf gate c1 c2 c3) (probe-match lf op c1 c2 c3)) (try bank op s c1 c2 c3)))
      (:la (try bank op s c1 c2 c3))      ; below the bound: evaluate; storing is decided in TRY (LF-DECLINE-P)
      (:audit                             ; plain search; count ruled-out candidates that equal the target
       (let ((ok (feasible-p lf gate c1 c2 c3)))
         (when (and (lf-ubhist lf) (gate-type-ok gate) (eql s (lf-level lf)))
           (incf (svref (lf-ubhist lf) (allow-count lf gate c1 c2 c3))))
         (if ok
             (try bank op s c1 c2 c3)
             (let ((r (catch :stop (try bank op s c1 c2 c3) :none)))
               (unless (eq r :none)
                 (when (or (cls-p r) (eq r :all)) (incf (lf-nfalse lf)))
                 (throw :stop r)))))))))

(defun lf-run-level (bank s)
  (let ((lf (bank-lf bank)))
    (ecase (lf-mode lf)
      (:first (setf (lf-nbit lf) 0)
       (enumerate-size bank s :first)
       (setf (lf-cursor lf) 0)
       (enumerate-size bank s :rest))
      (:first-last                        ; as :first, but a bound is known: at the bound there is no pass B
       (if (eql s (lf-level lf))
           (enumerate-size bank s :strict)
           (progn (setf (lf-nbit lf) 0) (enumerate-size bank s :first)
                  (setf (lf-cursor lf) 0) (enumerate-size bank s :rest))))
      (:strict (enumerate-size bank s (and (eql s (lf-level lf)) :strict)))
      (:la (enumerate-size bank s (if (eql s (lf-level lf)) :strict :la)))
      ((:probe :lfprobe)                  ; pass A stores nothing but an answer; pass B is the plain pass, in plain order
       (enumerate-size bank s (lf-mode lf))
       (unless (eql s (lf-level lf)) (enumerate-size bank s)))
      (:audit (enumerate-size bank s :audit)))))

(defun lf-bound (lf b)
  "A size bound became known WITHOUT an oracle: under *occam* a split is held and only a single term
   of size <= B can still replace it.  No class larger than B is needed, and none of size B as an argument."
  (case (lf-mode lf)
    (:first (setf (lf-level lf) b
                  (lf-mode lf) (if (getf *lf-cfg* :occam-la) :la :first-last)))
    ((:probe :lfprobe) (setf (lf-level lf) b))))

(defun probe-match (lf op c1 c2 c3)
  "The identity quotient: evaluate OP on the argument classes one row at a time against the target and stop
   at the first row that differs.  Same cell conventions as TRY.  Counts the cells it evaluates."
  (declare (optimize (speed 3) (safety 0)) (type lf lf))
  (let* ((y (lf-target lf)) (n (length (the simple-vector y))) (fn (op-fn op)) (k (op-arity op))
         (a1 (cls-col c1)) (a2 (if c2 (cls-col c2) a1)) (a3 (if c3 (cls-col c3) a1)) (cells 0) (ok t))
    (declare (simple-vector y a1 a2 a3) (fixnum n k cells))
    (incf (lf-nprobe lf))
    (dotimes (r n)
      (let* ((x (svref a1 r))
             (v (cond ((eq x :err) :err)
                      ((= k 1) (funcall (the function fn) x))
                      ((null fn) (if (eq x :t) (svref a2 r) (svref a3 r)))
                      (t (let ((yy (svref a2 r)) (z (and c3 (svref a3 r))))
                           (cond ((or (eq yy :err) (eq z :err)) :err)
                                 (c3 (funcall (the function fn) x yy z))
                                 (t (funcall (the function fn) x yy))))))))
        (incf cells)
        (unless (equal v (svref y r)) (setf ok nil) (return))))
    (incf (lf-ncell lf) cells)
    ok))

;;; ===================================================================
;;; 6. LOOK-AHEAD: with a size bound S, decline to STORE a class of size s when (a) it is too large
;;;    to sit two or more operators below the root, and (b) no operator, with any partner, can take
;;;    its labels to the target's on every checked row.  Operators whose result type cannot reach
;;;    the target's type in the size left are not enumerated at all.
;;; ===================================================================
(defun type-dist (ops ttype)
  "alist type -> least number of nodes added above a value of that type to reach type TTYPE through
   one or more operators (each operator adds itself and one node per other argument)."
  (let ((d '()) (changed t))
    (flet ((dist-of (ty) (or (cdr (assoc ty d)) 1000)))
      (loop while changed do
        (setf changed nil)
        (dolist (op ops)
          (let ((via (+ (op-arity op) (if (eq (op-res op) ttype) 0 (dist-of (op-res op))))))
            (dolist (a (remove-duplicates (op-args op)))
              (when (< via (dist-of a)) (setf d (acons a via (remove a d :key #'car)) changed t)))))))
    d))
(defun lf-dist (lf type)
  (or (cdr (assoc type (or (lf-dtab lf) (setf (lf-dtab lf) (type-dist (lf-ops lf) (lf-ttype lf)))))) 1000))
(defun lf-d2 (lf type)
  "Least size above a class of TYPE when it sits two or more operators below the root."
  (loop for op in (lf-ops lf) when (member type (op-args op))
        minimize (+ (op-arity op) (lf-dist lf (op-res op))) into m
        finally (return (or m 1000))))
(defun lf-op-dead-p (lf op s)
  (let ((d (- (lf-level lf) s)))
    (and (> d 0) (not (and (lf-keep-bool lf) (eq (op-res op) :bool)))
         (> (lf-dist lf (op-res op)) d))))

(defun reach-table (vt p n-p)
  "For argument position P: label there -> OR of the output-label sets over all labels of the other arguments."
  (let* ((tab (vt-tab vt)) (n1 (vt-n1 vt)) (n12 (vt-n12 vt)) (out (make-array n-p :initial-element 0)))
    (dotimes (i (length tab) out)
      (let ((lp (ecase p (0 (mod i n1)) (1 (mod (floor i n1) (floor n12 n1))) (2 (floor i n12)))))
        (setf (svref out lp) (logior (svref out lp) (svref tab i)))))))
(defun lf-uses-for (lf type)
  "((arity (qi . reach-table) ...) ...): every (operator, argument position) that takes a TYPE to the target's type."
  (cdr (or (assoc type (lf-uses lf))
           (car (push (cons type
                            (loop for op in (lf-ops lf) when (eq (op-res op) (lf-ttype lf)) append
                              (loop for a in (op-args op) for p from 0 when (eq a type)
                                    collect (cons (op-arity op)
                                                  (loop for q in (lf-qs lf) for qi from 0
                                                        collect (cons qi (reach-table (verb-table op q) p (nlab q type))))))))
                      (lf-uses lf))))))
(defun depth1-ok (lf labs type d)
  (let ((tl (lf-tlab lf)) (nr (lf-nchk lf)))
    (dolist (u (lf-uses-for lf type) nil)
      (when (and (if (= (car u) 1) (= d 1) (>= d (car u)))
                 (loop for (qi . rv) in (cdr u)
                       always (let ((l (svref labs qi)) (tv (svref tl qi)))
                                (dotimes (r nr t)
                                  (incf (lf-nlook lf))
                                  (unless (logbitp (aref tv r) (svref rv (aref l r))) (return nil))))))
        (return t)))))
(defun lf-decline-p (lf buf type size)
  (and (eq (lf-mode lf) :la)
       (let ((d (- (lf-level lf) size)))
         (and (> d 0)
              (not (and (lf-keep-bool lf) (eq type :bool)))
              (< d (lf-d2 lf type))
              (let ((labs (col-labels lf type buf)))
                (cond ((depth1-ok lf labs type d) (setf (lf-pending lf) labs) nil)
                      ((and (eq type (lf-ttype lf)) (col= buf (lf-target lf))) ; never decline the answer itself
                       (setf (lf-pending lf) labs) nil)
                      (t (incf (lf-ndecl lf)) t)))))))

;;; ===================================================================
;;; 7. BOOKKEEPING, and the look-ahead driver (restart from the leaves for each size bound)
;;; ===================================================================
(defvar *banks* nil)     ; ((bank kind target-type target-column) ...) every bank given a target, newest first
(defvar *levels* nil)    ; snapshots (bank tag . counters), see SNAPSHOT
(defvar *trace* nil)     ; T only inside the L1 drivers: record banks and per-level snapshots (they keep banks alive)
(defun snapshot (bank tag)
  (let ((lf (bank-lf bank)))
    (list bank tag (bank-ncand bank) (length (bank-all bank))
          (if lf (lf-nfeas lf) 0) (if lf (lf-nskip lf) 0) (if lf (lf-ntype lf) 0) (if lf (lf-nlook lf) 0)
          (if lf (lf-ndecl lf) 0) (if lf (lf-nfalse lf) 0) (if lf (lf-nrestl lf) 0) (if lf (lf-nrestt lf) 0)
          (if lf (lf-nprobe lf) 0) (if lf (lf-ncell lf) 0) (bank-ncells bank) (if lf (lf-nlab lf) 0))))
(defun lf-note-level (bank s) (when *trace* (push (snapshot bank s) *levels*)))
(defun lf-tally (bank) (when *trace* (push (snapshot bank :final) *levels*)))

(defun lf-set-target (bank type col kind)
  "Called where the prototype first knows a bank's target column.  KIND: :shape, :elem or :select."
  (when *trace* (push (list bank kind type col) *banks*))
  (let* ((cfg *lf-cfg*) (mode (getf cfg :mode)))
    (cond ((null cfg) nil)
          ((and (eq mode :la) (eq kind :elem)) :la)
          (t (lf-attach bank type col
                        (if (and (member mode '(:strict :la)) (not (eq kind :elem))) :first mode)
                        (getf cfg :level))
             nil))))

(defun clone-leaves (b)
  (let ((n (new-bank (bank-base b) (bank-ops b))))
    (loop for c across (bank-all b) when (= (cls-size c) 1) do (add-leaf n (cls-term c) (cls-type c) (cls-col c)))
    n))
(defun lf-solve-col-la (bank0 y max-size limit)
  "Look-ahead needs a size bound.  :LEVEL L in the config runs the single bound L (an oracle); otherwise
   the bound is deepened 2, 3, ... with a restart from the leaves each time, and every pass is counted."
  (let* ((cfg *lf-cfg*) (goal (goal-exact :int y)) (rows (loop for r below (length y) collect r)))
    (loop for bound from (or (getf cfg :level) 2) to (or (getf cfg :level) (getf cfg :maxbound) max-size) do
      (let ((bank (clone-leaves bank0)))
        (when *trace* (push (list bank (list :elem-la bound) :int y) *banks*))
        (lf-attach bank :int y :la bound)
        (setf (bank-on-new bank) (lambda (c) (when (funcall goal c) (throw :stop c))))
        (let ((r (run bank bound :limit limit)))
          (tally bank)
          (when (cls-p r) (return (cls-term r)))
          (when *inverses*                  ; goal inversion, as SOLVE-COL does it, on the thinned bank
            (let ((h (residual bank y))) (when h (return h))))
          (when (getf cfg :cover)           ; does the guard split survive on the thinned bank?
            (let ((h (cover bank y rows 1))) (when h (return h))))
          (unless (eq r :done) (return nil))
          ;; this bound failed: drop its classes before the restart (its counts are already recorded)
          (setf (bank-all bank) (make-array 0 :adjustable t :fill-pointer 0))
          (clrhash (bank-table bank)) (clrhash (bank-by bank)))))))
