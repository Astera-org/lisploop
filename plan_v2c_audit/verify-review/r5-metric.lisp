;;;; r5-metric.lisp -- verify-review R5.  Root kernel from the scratch copy; the kernel's own
;;;; correction-bit-size (frame.lisp:1713 -> correction, :1533-1582).  Seeded.
(load (merge-pathnames "kernel/load.lisp" *load-truename*))
(in-package :lisploop)
(setf *print-pretty* nil *print-right-margin* 100000)

(defun show-value (v) (if (and (consp v) (ast-kind v)) (ast->sexp v) v))
(defun triangle (label values type)
  "All ordered triples (u v w) of VALUES: count d(u->w) > d(u->v) + d(v->w); also asymmetric pairs."
  (let* ((n (length values)) (vals (coerce values 'vector))
         (d (make-array (list n n))) (viol 0) (worst 0) (worst-ex nil) (asym 0) (maxasym 0) (asym-ex nil)
         (zero-off-diagonal 0))
    (dotimes (i n) (dotimes (j n) (setf (aref d i j) (correction-bit-size (aref vals i) (aref vals j) type))))
    (dotimes (i n)
      (dotimes (j n)
        (when (and (/= i j) (zerop (aref d i j))) (incf zero-off-diagonal))
        (when (< i j)
          (let ((a (abs (- (aref d i j) (aref d j i)))))
            (when (plusp a) (incf asym))
            (when (> a maxasym) (setf maxasym a asym-ex (list i j)))))
        (dotimes (k n)
          (let ((gap (- (aref d i k) (+ (aref d i j) (aref d j k)))))
            (when (plusp gap)
              (incf viol)
              (when (> gap worst) (setf worst gap worst-ex (list i j k))))))))
    (format t "~a: ~d values, ~d triples, TRIANGLE VIOLATIONS ~d~@[ (worst by ~d bits)~]; d(u,u)=0 on all: ~a; zero distance between distinct values: ~d; asymmetric unordered pairs ~d of ~d (largest |d(u->v)-d(v->u)| = ~d)~%"
            label n (* n n n) viol (and (plusp viol) worst)
            (loop for i below n always (zerop (aref d i i))) zero-off-diagonal asym (/ (* n (1- n)) 2) maxasym)
    (when worst-ex
      (destructuring-bind (i j k) worst-ex
        (format t "    worst: u=~a v=~a w=~a : d(u->w)=~d > d(u->v)+d(v->w) = ~d+~d~%"
                (show-value (aref vals i)) (show-value (aref vals j)) (show-value (aref vals k))
                (aref d i k) (aref d i j) (aref d j k))))
    (when (and asym-ex (plusp maxasym))
      (destructuring-bind (i j) asym-ex
        (format t "    most asymmetric pair: u=~a v=~a : d(u->v)=~d, d(v->u)=~d~%"
                (show-value (aref vals i)) (show-value (aref vals j)) (aref d i j) (aref d j i))))
    viol))

(defun seqs (alphabet maxlen)
  (let ((out (list nil)) (layer (list nil)))
    (loop repeat maxlen do
      (setf layer (loop for s in layer append (loop for a in alphabet collect (cons a s))))
      (setf out (append out layer)))
    out))

(defun code-terms (scope leaves ops n-random seed)
  "All terms of depth <= 2 over LEAVES and binary OPS, plus N-RANDOM distinct depth-3 terms (seeded)."
  (declare (ignorable scope))
  (let* ((d1 leaves)
         (d2 (loop for o in ops append (loop for a in d1 append (loop for b in d1 collect (term `(,o ,a ,b))))))
         (pool (append d1 d2)) (rs (sb-ext:seed-random-state seed)) (d3 '()))
    (loop while (< (length d3) n-random)
          do (pushnew (term `(,(nth (random (length ops) rs) ops)
                              ,(nth (random (length pool) rs) pool)
                              ,(nth (random (length pool) rs) pool)))
                      d3 :test #'equal))
    (remove-duplicates (append pool d3) :test #'equal)))

(format t "=== R5-i. directed triangle inequality d(u->w) <= d(u->v) + d(v->w), d = correction-bit-size ===~%")
(triangle ":int, all of -60..60" (loop for v from -60 to 60 collect v) :int)
(triangle ":int, magnitudes at power-of-two boundaries up to 2^20"
          (remove-duplicates
           (loop for k in '(0 1 2 3 4 5 7 8 15 16 31 32 63 64 100 127 128 255 256 511 512 1000 1023 1024 5000 65535 65536 1048575 1048576)
                 append (list k (- k))))
          :int)
(dolist (p '(2 3 5 7 13 31)) (triangle (format nil "(:gf ~d), all residues" p) (loop for v below p collect v) (list :gf p)))
(let ((st (sequence-type :int)))
  (triangle "(:seq :int), all sequences of length<=3 over {-1,0,1,2}" (seqs '(-1 0 1 2) 3) st)
  (triangle "(:seq :int), length<=4 over {0,5} plus length<=3 over {0,7,-100}"
            (remove-duplicates (append (seqs '(0 5) 4) (seqs '(0 7 -100) 3)) :test #'equal) st)
  (triangle "(:seq :int), length<=6 over {3}" (seqs '(3) 6) st))
(let* ((s1 '((0 . :int))) (s2 '((0 . :int) (1 . :int))))
  (triangle ":code, scope (x0): depth<=2 over {x0,0,1,2} x {+,*,-} plus 60 random depth-3 (seed 11)"
            (code-terms s1 (list (var 0 :int) (lit :int 0) (lit :int 1) (lit :int 2)) '(+ * -) 60 11)
            (code-type s1 :int))
  (triangle ":code, scope (x0 x1): depth<=2 over {x0,x1,0,1} x {+,*} plus 60 random depth-3 (seed 12)"
            (code-terms s2 (list (var 0 :int) (var 1 :int) (lit :int 0) (lit :int 1)) '(+ *) 60 12)
            (code-type s2 :int)))

;; wider, seeded random grids (added after the first seq grid with a large element showed violations)
(defun random-seqs (n maxlen lo hi seed)
  (let ((rs (sb-ext:seed-random-state seed)) (out '()))
    (loop while (< (length out) n)
          do (pushnew (loop repeat (random (1+ maxlen) rs) collect (+ lo (random (1+ (- hi lo)) rs))) out :test #'equal))
    out))
(let ((st (sequence-type :int)))
  (triangle "(:seq :int), 150 random sequences, length 0..5, elements -3..3 (seed 22)" (random-seqs 150 5 -3 3 22) st)
  (triangle "(:seq :int), 150 random sequences, length 0..5, elements -20..20 (seed 23)" (random-seqs 150 5 -20 20 23) st)
  (triangle "(:seq :int), 150 random sequences, length 0..5, elements -100..100 (seed 21)" (random-seqs 150 5 -100 100 21) st)
  (format t "    by hand: d((-100 -100)->(-100 0 0)) = ~d ; d((-100 -100)->(-100)) = ~d ; d((-100)->(-100 0 0)) = ~d ; value-bit-size (-100 0 0) = ~d~%"
          (correction-bit-size '(-100 -100) '(-100 0 0) st) (correction-bit-size '(-100 -100) '(-100) st)
          (correction-bit-size '(-100) '(-100 0 0) st) (value-bit-size '(-100 0 0) st))
  (format t "    smallest instance of the pattern (a a c)->(a a)->(a a 0) with a=50: c=-100: ~d vs ~d+~d ; c=9: ~d vs ~d+~d~%"
          (correction-bit-size '(50 50 -100) '(50 50 0) st) (correction-bit-size '(50 50 -100) '(50 50) st) (correction-bit-size '(50 50) '(50 50 0) st)
          (correction-bit-size '(50 50 9) '(50 50 0) st) (correction-bit-size '(50 50 9) '(50 50) st) (correction-bit-size '(50 50) '(50 50 0) st)))
(let* ((s2 '((0 . :int) (1 . :int))))
  (triangle ":code, scope (x0 x1): depth<=2 over {x0,x1,0,1,1000,-77} x {+,*} plus 150 random depth-3 (seed 13)"
            (code-terms s2 (list (var 0 :int) (var 1 :int) (lit :int 0) (lit :int 1) (lit :int 1000) (lit :int -77)) '(+ *) 150 13)
            (code-type s2 :int)))
(triangle "(:tuple :int :int), all pairs over {-100,-1,0,1,2,50}" (loop for a in '(-100 -1 0 1 2 50) append (loop for b in '(-100 -1 0 1 2 50) collect (list a b))) (tuple-type :int :int))

(format t "~%=== R5-ii. integers ===~%")
(format t "d(0 -> D) for D = 0 1 2 3 4 5 8 16 100 1000: ~a~%"
        (mapcar (lambda (d) (correction-bit-size 0 d :int)) '(0 1 2 3 4 5 8 16 100 1000)))
(format t "d(0 -> -D) for the same D:                    ~a~%"
        (mapcar (lambda (d) (correction-bit-size 0 (- d) :int)) '(0 1 2 3 4 5 8 16 100 1000)))
(format t "d(0->D) = d(0->-D) = d(D->0) for every D in 1..1000000: ~a~%"
        (loop for d from 1 to 1000000
              always (= (correction-bit-size 0 d :int) (correction-bit-size 0 (- d) :int) (correction-bit-size d 0 :int))))
(format t "d(u->v) depends only on v-u: checked for u in -50..50, v-u in -200..200: ~a~%"
        (loop for u from -50 to 50
              always (loop for k from -200 to 200 always (= (correction-bit-size u (+ u k) :int) (correction-bit-size 0 k :int)))))
(format t "distinct values of d(0->D), D=0..1000, with the first D reaching each: ~a~%"
        (let ((seen '())) (loop for d from 0 to 1000 for b = (correction-bit-size 0 d :int)
                                unless (assoc b seen) do (push (cons b d) seen))
          (reverse seen)))

(format t "~%=== R5-iii. asymmetry on sequences and code ===~%")
(let ((st (sequence-type :int)))
  (format t "(:seq :int)  d(() -> (1 2)) = ~d   d((1 2) -> ()) = ~d   [value-bit-size (1 2) = ~d, () = ~d]~%"
          (correction-bit-size '() '(1 2) st) (correction-bit-size '(1 2) '() st)
          (value-bit-size '(1 2) st) (value-bit-size '() st)))
(dolist (k '(1 2 3 4 5))
  (let* ((scope (loop for i below k collect (cons i :int))) (ct (code-type scope :int))
         (x0 (var 0 :int)) (x0+1 (term `(+ ,(var 0 :int) 1))))
    (format t ":code, scope of ~d integer input~:p:  d(x0 -> x0+1) = ~2d   d(x0+1 -> x0) = ~d   [value-bit-size x0 = ~d, x0+1 = ~d]~%"
            k (correction-bit-size x0 x0+1 ct) (correction-bit-size x0+1 x0 ct)
            (value-bit-size x0 ct) (value-bit-size x0+1 ct))))
(finish-output)
