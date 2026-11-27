;;;; xs-m2.lisp -- M2: analogy as a verified map between two operators' tables.
;;;; A homomorphism f : (Z, op1) -> (Z, op2) is one column equation on the grid
;;;; space of (a, b) rows:      f(op1(a,b)) = op2(f(a), f(b)).
;;;; f is a CLASS of a small bank over one variable x; its column on the base
;;;; x = -R..R is its table, and "f of a column" is a re-index (PULL) of that
;;;; table along the map  row -> row of the f base.
;;;; Loaded AFTER the unmodified tg-probe.lisp (see run.sh).  Everything is seeded.
(in-package :tg)
(declaim (optimize (speed 1) (safety 1) (debug 1)))

(defparameter *bin* '(+ - * max min))
(defun opf (name) (op-fn (first (ops name))))
(defun fine-now ()                        ; the prototype's NOW has 4 ms resolution; this one has 1 us
  (multiple-value-bind (s us) (sb-ext:get-time-of-day) (+ s (* us 1d-6))))
(defun ms-since (t0) (* 1000 (- (fine-now) t0)))
(defun avg (xs) (if xs (/ (reduce #'+ xs) (float (length xs) 1d0)) 0d0))

(defun f-bank (opnames max-size r)
  "Classes of unary maps over one variable x, on the base x = -R..R."
  (let* ((n (1+ (* 2 r))) (bank (new-bank (make-base :n n) (apply #'ops opnames))))
    (add-leaf bank 'x :int (let ((v (make-array n))) (dotimes (i n v) (setf (svref v i) (- i r)))))
    (dolist (k '(0 1 2)) (add-leaf bank k :int (make-array n :initial-element k)))
    (run bank max-size)
    bank))
(defun constant-col-p (col) (every (lambda (v) (equal v (svref col 0))) col))

;;; --- law flags of one operator, from its own table (class collisions) ---
(defun op-flags (fn vals)
  "(commutative idempotent associative) of the binary function FN on VALS x VALS."
  (list (every (lambda (a) (every (lambda (b) (equal (funcall fn a b) (funcall fn b a))) vals)) vals)
        (every (lambda (a) (equal (funcall fn a a) a)) vals)
        (every (lambda (a) (every (lambda (b) (every (lambda (c) (equal (funcall fn (funcall fn a b) c)
                                                                       (funcall fn a (funcall fn b c))))
                                                     vals))
                                  vals))
               vals)))

(defun flags-of (op flags) (cdr (assoc op flags)))
(defstruct tr f op1 op2 holds first-bad f1 f2 f3 (truth :unknown)) ; one tested triple and what each pre-filter says

(defun hom-part1 (&key (fops '(neg + *)) (max-size 4) (g 6) (label "spec") (verbose t))
  (let* ((t0 (fine-now)) (r (* g g))
         (bank (f-bank fops max-size r)) (fbase (bank-base bank))
         (fs (remove-if (lambda (c) (constant-col-p (cls-col c))) (coerce (bank-all bank) 'list)))
         (rows (loop for a from (- g) to g append (loop for b from (- g) to g collect (cons a b))))
         (n (length rows))
         (acol (map 'simple-vector #'car rows)) (bcol (map 'simple-vector #'cdr rows))
         (t-bank (ms-since t0)) (t1 (fine-now)))
    (flet ((via (col)                      ; a map column into the f base: value v -> row v+R
             (make-base :n (length col) :parent fbase :pmap (map 'simple-vector (lambda (v) (+ v r)) col)))
           (app (name c1 c2) (map 'simple-vector (opf name) c1 c2)))
      (let* ((ba (via acol)) (bb (via bcol))
             (order (let ((rs (sb-ext:seed-random-state 5)) (v (make-array n)))   ; a seeded row order
                      (dotimes (i n) (setf (svref v i) i))
                      (loop for i from (1- n) downto 1 do (rotatef (svref v i) (svref v (random (1+ i) rs))))
                      v))
             (vals (loop for a from (- g) to g collect a))
             (flags (loop for o in *bin* collect (cons o (op-flags (opf o) vals))))
             (diag (loop for i below n when (= (svref acol i) (svref bcol i)) collect i))
             (triples '()) (plain 0)
             (t-plain (let ((tp (fine-now))) ; the test alone, timed over 20 passes: 3 re-indexes per (f, op1), one column op per triple
                        (dotimes (pass 20)
                          (setf plain 0)
                          (dolist (op1 *bin*)
                            (let ((bc (via (app op1 acol bcol))))
                              (dolist (f fs)
                                (let ((fa (pull ba (cls-col f))) (fb (pull bb (cls-col f))) (fc (pull bc (cls-col f))))
                                  (dolist (op2 *bin*) (when (col= fc (app op2 fa fb)) (incf plain))))))))
                        (/ (ms-since tp) 20))))
        (dolist (op1 *bin*)
          (let* ((c1 (app op1 acol bcol)) (bc (via c1)) (bc-swap (via (app op1 bcol acol))))
            (dolist (f fs)
              (let* ((fcol (cls-col f)) (fa (pull ba fcol)) (fb (pull bb fcol)) (fc (pull bc fcol))
                     (sym (col= fc (pull bc-swap fcol)))                       ; f(op1(a,b)) = f(op1(b,a))
                     (idm (every (lambda (i) (equal (svref fc i) (svref fa i))) diag))) ; f(op1(a,a)) = f(a)
                (dolist (op2 *bin*)
                  (let* ((rhs (app op2 fa fb))
                         (bad (position-if-not (lambda (i) (equal (svref fc i) (svref rhs i))) order))
                         (f2 (flags-of op2 flags)) (f1 (flags-of op1 flags))
                         (sym2 (col= rhs (app op2 fb fa)))                     ; op2(fa,fb) = op2(fb,fa)
                         (idm2 (every (lambda (i) (equal (svref rhs i) (svref fa i))) diag))) ; op2(fa,fa) = fa
                    (push (make-tr :f f :op1 op1 :op2 op2 :holds (null bad) :first-bad bad
                                   ;; F1: op-level flags only: skip when op1 has a law that op2 lacks
                                   :f1 (some (lambda (x y) (and x (not y))) f1 f2)
                                   ;; F2: a law of op2, pulled back along f, must hold for f o op1
                                   :f2 (or (and (first f2) (not sym)) (and (second f2) (not idm)))
                                   ;; F3: a law of op1, pushed forward, must hold for op2 on the image of f
                                   :f3 (or (and (first f1) (not sym2)) (and (second f1) (not idm2))))
                          triples)))))))
        (setf triples (nreverse triples))
        (let* ((t-test (ms-since t1))
               (trivial (lambda (x) (and (eq (cls-term (tr-f x)) 'x) (eq (tr-op1 x) (tr-op2 x)))))
               (found (remove-if trivial (remove-if-not #'tr-holds triples)))
               (failing (remove-if #'tr-holds triples))
               (rs (sb-ext:seed-random-state 4242))
               (fresh (loop repeat 1000 collect (cons (rnd rs -1000 1000) (rnd rs -1000 1000))))
               (truth (lambda (x)       ; memoized: does the triple hold on the 1000 fresh rows?
                        (when (eq (tr-truth x) :unknown)
                          (setf (tr-truth x)
                                (let ((term (cls-term (tr-f x))) (o1 (opf (tr-op1 x))) (o2 (opf (tr-op2 x))))
                                  (flet ((f (v) (ev term (list (cons 'x v)))))
                                    (every (lambda (p) (= (f (funcall o1 (car p) (cdr p)))
                                                          (funcall o2 (f (car p)) (f (cdr p)))))
                                           fresh)))))
                        (tr-truth x)))
               (false-found (remove-if truth found)))
          (format t "~%--- M2.1 [~a] f in classes of {~{~a~^ ~}} over x 0 1 2, size<=~d; op1, op2 in ~a; grid a,b in -~d..~d (~d rows) ---~%"
                  label fops max-size *bin* g g n)
          (format t "f bank: ~d candidates, ~d classes on x=-~d..~d, ~d non-constant; bank ~,2f ms; all triple tests ~,2f ms (~d hold);~%  the same with the pre-filter columns and first-counterexample positions also computed: ~,2f ms~%"
                  (bank-ncand bank) (length (bank-all bank)) r r (length fs) t-bank t-plain plain t-test)
          (format t "triples tested ~d (~d f x 25 operator pairs); hold on the grid ~d, of which ~d trivial (identity, op1=op2);~%listed ~d; false on 1000 fresh rows in -1000..1000: ~d~%"
                  (length triples) (length fs) (count-if #'tr-holds triples)
                  (count-if trivial (remove-if-not #'tr-holds triples)) (length found) (length false-found))
          (when verbose
            (format t "found (f, op1 -> op2):~%")
            (dolist (f fs)
              (let ((mine (remove-if-not (lambda (x) (eq (tr-f x) f)) found)))
                (when mine
                  (format t "  ~22s ~{~a~^, ~}~%" (cls-term f)
                          (mapcar (lambda (x) (format nil "~a->~a" (tr-op1 x) (tr-op2 x))) mine)))))
            (format t "operator law flags from the tables (commutative idempotent associative): ~{~a~^  ~}~%"
                    (mapcar (lambda (fl) (format nil "~a ~a" (car fl) (mapcar (lambda (b) (if b 'y 'n)) (cdr fl)))) flags)))
          ;; --- pre-filters ---
          (format t "pre-filters (failing triples: ~d; true non-trivial: ~d):~%" (length failing) (length found))
          (format t "  ~58a ~8a ~10a ~12a~%" "filter" "tests" "skips fail" "skips TRUE")
          (flet ((line (name ntests pred)
                   (format t "  ~58a ~8d ~4d (~3d%) ~8d~%" name ntests (count-if pred failing)
                           (round (* 100 (count-if pred failing)) (max 1 (length failing)))
                           (count-if pred found))))
            (line "F1 op-level: op1 has comm/idem/assoc that op2 lacks" (* 3 (length *bin*)) #'tr-f1)
            (line "F2 (f,op1): op2's comm/idem pulled back along f" (* 2 (length fs) (length *bin*)) #'tr-f2)
            (line "F3 (f,op2): op1's comm/idem must hold on image(f)" (* 2 (length fs) (length *bin*)) #'tr-f3)
            (line "F2 or F3" (* 4 (length fs) (length *bin*)) (lambda (x) (or (tr-f2 x) (tr-f3 x))))
            (line "F1 or F2 or F3" (+ 15 (* 4 (length fs) (length *bin*)))
                  (lambda (x) (or (tr-f1 x) (tr-f2 x) (tr-f3 x)))))
          (dolist (x (remove-if-not #'tr-f1 found))
            (format t "  F1 WRONGLY skips the true triple ~s: ~a->~a~%" (cls-term (tr-f x)) (tr-op1 x) (tr-op2 x)))
          (let ((fb (mapcar #'tr-first-bad failing)))
            (format t "  early exit instead: rows read until the first counterexample (seeded random row order), failing triples:~%    mean ~,2f, median ~d, max ~d;  rejected within 1 row ~d%, 2 rows ~d%, 4 rows ~d%, 8 rows ~d%~%"
                    (avg (mapcar #'1+ fb)) (1+ (nth (floor (length fb) 2) (sort (copy-list fb) #'<)))
                    (1+ (reduce #'max fb))
                    (round (* 100 (count-if (lambda (v) (< v 1)) fb)) (length fb))
                    (round (* 100 (count-if (lambda (v) (< v 2)) fb)) (length fb))
                    (round (* 100 (count-if (lambda (v) (< v 4)) fb)) (length fb))
                    (round (* 100 (count-if (lambda (v) (< v 8)) fb)) (length fb)))
            (format t "    cells: full test of every triple ~d; with early exit ~d (true triples still read all ~d rows)~%"
                    (* n (length triples))
                    (+ (reduce #'+ (mapcar #'1+ fb)) (* n (count-if #'tr-holds triples))) n))
          ;; --- how few rows make a false analogy? ---
          (format t "  accepted when tested on only the first k rows of that order (false = fails on the fresh rows):~%   ")
          (dolist (k '(1 2 3 4 6 8 12 16))
            (let ((acc (remove-if trivial (remove-if-not (lambda (x) (or (tr-holds x) (>= (tr-first-bad x) k))) triples))))
              (format t " k=~d: ~d (~d false);" k (length acc) (count-if-not truth acc))))
          (format t "~%")
          (list (length triples) (length found) (length false-found)))))))
;;; ------------------------------------------------------------------
;;; Part 2: sequence -> integer maps against (append, op2)
;;; ------------------------------------------------------------------
(defparameter *seq-fs*
  (list (cons 'len #'length) (cons 'sum (lambda (s) (reduce #'+ s)))
        (cons 'max (lambda (s) (reduce #'max s))) (cons 'min (lambda (s) (reduce #'min s)))
        (cons 'first #'first) (cons 'last (lambda (s) (car (last s))))))
(defun hom-part2 (&key (nrows 64) (seed 11))
  (let* ((t0 (fine-now)) (rs (sb-ext:seed-random-state seed))
         (rseq (lambda (maxlen lo hi) (loop repeat (rnd rs 1 maxlen) collect (rnd rs lo hi))))
         (xs (coerce (loop repeat nrows collect (funcall rseq 6 -5 9)) 'simple-vector))
         (ys (coerce (loop repeat nrows collect (funcall rseq 6 -5 9)) 'simple-vector))
         (zs (map 'simple-vector #'append xs ys))        ; the op1 column
         (zswap (map 'simple-vector #'append ys xs)) (zdbl (map 'simple-vector #'append xs xs))
         (fresh (loop repeat 1000 collect (cons (funcall rseq 12 -1000 1000) (funcall rseq 12 -1000 1000))))
         (ops2 '(+ max min)) (rows '())
         (aflags (let ((v (list '(1) '(2 3) '(4) '(5 6 7) '(1 1))))
                   (op-flags #'append v)))
         (iflags (let ((v (loop for a from -6 to 6 collect a)))
                   (loop for o in ops2 collect (cons o (op-flags (opf o) v))))))
    (loop for (fname . f) in *seq-fs* do
      (let* ((fx (map 'simple-vector f xs)) (fy (map 'simple-vector f ys)) (fz (map 'simple-vector f zs))
             (sym (col= fz (map 'simple-vector f zswap)))            ; f(xs++ys) = f(ys++xs)
             (idm (col= fx (map 'simple-vector f zdbl))))            ; f(xs++xs) = f(xs)
        (dolist (o ops2)
          (let* ((rhs (map 'simple-vector (opf o) fx fy))
                 (bad (position-if-not #'identity (map 'list #'equal fz rhs)))
                 (f2 (flags-of o iflags)))
            (push (list fname o (null bad) bad
                        (every (lambda (p) (= (funcall f (append (car p) (cdr p)))
                                              (funcall (opf o) (funcall f (car p)) (funcall f (cdr p)))))
                               fresh)
                        (some (lambda (x y) (and x (not y))) aflags f2)                 ; F1
                        (or (and (first f2) (not sym)) (and (second f2) (not idm))))    ; F2
                  rows)))))
    (setf rows (nreverse rows))
    (let ((found (remove-if-not #'third rows)) (failing (remove-if #'third rows)))
      (format t "~%--- M2.2 f in {len sum max min first last}: f(append(xs,ys)) = op2(f(xs), f(ys)), op2 in ~a; ~d rows of non-empty sequences ---~%"
              ops2 nrows)
      (format t "triples tested ~d; found ~d: ~{~a~^, ~}; false on 1000 fresh rows (values to +-1000, lengths 1..12): ~d; ~,2f ms~%"
              (length rows) (length found)
              (mapcar (lambda (r) (format nil "~a: append->~a" (first r) (second r))) found)
              (count-if-not #'fifth found) (ms-since t0))
      (format t "law flags (commutative idempotent associative): append ~a; ~{~a~^  ~}~%"
              (mapcar (lambda (b) (if b 'y 'n)) aflags)
              (mapcar (lambda (fl) (format nil "~a ~a" (car fl) (mapcar (lambda (b) (if b 'y 'n)) (cdr fl)))) iflags))
      (format t "pre-filters over ~d failing triples: F1 (op-level flags) skips ~d, wrongly skips ~d true;~%  F2 (op2's comm/idem pulled back: f(xs++ys)=f(ys++xs), f(xs++xs)=f(xs); ~d tests) skips ~d (~d%), wrongly skips ~d true~%"
              (length failing) (count-if #'sixth failing) (count-if #'sixth found)
              (* 2 (length *seq-fs*)) (count-if #'seventh failing)
              (round (* 100 (count-if #'seventh failing)) (length failing)) (count-if #'seventh found))
      (format t "  failing triples F2 does not skip: ~{~a~^, ~}~%"
              (mapcar (lambda (r) (format nil "~a/~a" (first r) (second r)))
                      (remove-if #'seventh failing)))
      (format t "  early exit: first counterexample at row (1-based), failing triples: mean ~,2f, max ~d~%"
              (avg (mapcar (lambda (r) (1+ (fourth r))) failing))
              (reduce #'max (mapcar (lambda (r) (1+ (fourth r))) failing))))))

(defun m2 ()
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
    (format t "=== M2. ANALOGY AS A VERIFIED MAP BETWEEN TWO OPERATORS' TABLES ===~%")
    (hom-part1)
    (hom-part2)
    ;; ADDED: a richer f bank, to see whether the op-level flag filter stays harmless
    (hom-part1 :fops '(neg + * max min) :max-size 5 :label "added: richer f bank" :verbose t)
    (hom-part1 :fops '(neg + *) :max-size 6 :label "added: same grammar, size<=6" :verbose nil)
    (finish-output)))
