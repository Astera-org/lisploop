;;;; Verify codec & description-length geometry properties on the root lisploop kernel
(load "/home/tlh24/lisploop/load.lisp")
(in-package #:lisploop)

(format t "~&=== 1. INTEGER DELTA CODE LENGTHS d(0 -> delta) ===~%")
(loop for d in '(0 1 -1 2 -2 3 4 7 8 15 16 31 32 63 64 100 1000) do
  (format t "  delta=~5d  signed-code=~5a  value-bits=~2d  correction-bits(0->d)=~2d~%"
          d (if (zerop d) (signed-code 0) (signed-code d))
          (value-bit-size d :int)
          (correction-bit-size 0 d :int)))

(format t "~&=== 2. KRAFT SUMS OF CONDITIONAL CORRECTION CODES sum_v 2^{-d(u -> v)} ===~%")
;; :bool
(let* ((u t)
       (ksum (+ (expt 2.0d0 (- (correction-bit-size u t :bool)))
                (expt 2.0d0 (- (correction-bit-size u nil :bool))))))
  (format t "  :bool from u=T: d(T->T)=~d, d(T->NIL)=~d  => Kraft sum = ~,4f (> 1 violates prefix-free!)~%"
          (correction-bit-size u t :bool)
          (correction-bit-size u nil :bool)
          ksum))

;; (:gf 5)
(let* ((gf5 (gf 5))
       (u 3)
       (dists (loop for v below 5 collect (correction-bit-size u v gf5)))
       (ksum (loop for b in dists sum (expt 2.0d0 (- b)))))
  (format t "  (:gf 5) from u=3: dists=~a  => Kraft sum = ~,4f; note replacement value-bit-size=~d~%"
          dists ksum (value-bit-size 4 gf5)))

;; :int truncated [-1000..1000]
(let ((ksum-corr (loop for v from -1000 to 1000 sum (expt 2.0d0 (- (correction-bit-size 0 v :int)))))
      (ksum-val  (loop for v from -1000 to 1000 sum (expt 2.0d0 (- (value-bit-size v :int))))))
  (format t "  :int [-1000..1000]: plain value-bit-size Kraft sum = ~,6f (<=1 valid prefix code)~%" ksum-val)
  (format t "  :int [-1000..1000]: correction-bit-size  Kraft sum = ~,6f (>1 because d(u,u)=0 forced!)~%" ksum-corr))

(format t "~&=== 3. SYMMETRY AND DIRECTED TRIANGLE INEQUALITY CHECKS ===~%")
;; Test triangle inequality on :int for [-20..20]
(let ((int-tri-violations 0)
      (int-asym 0))
  (loop for u from -15 to 15 do
    (loop for v from -15 to 15 do
      (when (/= (correction-bit-size u v :int) (correction-bit-size v u :int))
        (incf int-asym))
      (loop for w from -15 to 15 do
        (let ((duv (correction-bit-size u v :int))
              (dvw (correction-bit-size v w :int))
              (duw (correction-bit-size u w :int)))
          (when (> duw (+ duv dvw))
            (when (< int-tri-violations 5)
              (format t "  :int triangle violation: u=~d v=~d w=~d: d(u->w)=~d > d(u->v)=~d + d(v->w)=~d~%"
                      u v w duw duv dvw))
            (incf int-tri-violations))))))
  (format t "  :int [-15..15]: asymmetries=~d, triangle violations=~d~%" int-asym int-tri-violations))

;; Test symmetry and triangle inequality on (:seq :int)
(let* ((seq-t (sequence-type :int))
       (seqs '(() (0) (1) (2) (1 2) (2 1) (1 2 3) (2 3 4) (0 1 2 3) (1 2 3 4)))
       (seq-asym 0)
       (seq-tri-violations 0))
  (dolist (u seqs)
    (dolist (v seqs)
      (let ((duv (correction-bit-size u v seq-t))
            (dvu (correction-bit-size v u seq-t)))
        (when (/= duv dvu)
          (when (< seq-asym 5)
            (format t "  :seq asymmetry: d(~a -> ~a)=~d vs d(~a -> ~a)=~d~%" u v duv v u dvu))
          (incf seq-asym))
        (dolist (w seqs)
          (let ((dvw (correction-bit-size v w seq-t))
                (duw (correction-bit-size u w seq-t)))
            (when (> duw (+ duv dvw))
              (when (< seq-tri-violations 5)
                (format t "  :seq triangle violation: u=~a v=~a w=~a: d(u->w)=~d > ~d + ~d~%"
                        u v w duw duv dvw))
              (incf seq-tri-violations)))))))
  (format t "  (:seq :int) over 10 sample seqs: asymmetries=~d, triangle violations=~d~%"
          seq-asym seq-tri-violations))

;; Test symmetry and triangle inequality on :code
(let* ((inps '((0 . :int) (1 . :int)))
       (code-t (code-type inps :int))
       (x (var 0 :int))
       (y (var 1 :int))
       (exprs (list x y
                    (term `(+ ,x 1))
                    (term `(+ ,x 2))
                    (term `(+ ,x ,y))
                    (term `(+ ,y ,x))
                    (term `(* ,x 2))
                    (term `(+ (+ ,x 1) (+ ,x 1)))
                    (term `(+ (* ,x 2) (* ,x 2)))))
       (code-asym 0)
       (code-tri-violations 0))
  (dolist (u exprs)
    (dolist (v exprs)
      (let ((duv (correction-bit-size u v code-t))
            (dvu (correction-bit-size v u code-t)))
        (when (/= duv dvu)
          (when (< code-asym 4)
            (format t "  :code asymmetry: d(~a -> ~a)=~d vs reverse=~d~%"
                    (ast->sexp u) (ast->sexp v) duv dvu))
          (incf code-asym))
        (dolist (w exprs)
          (let ((dvw (correction-bit-size v w code-t))
                (duw (correction-bit-size u w code-t)))
            (when (> duw (+ duv dvw))
              (when (< code-tri-violations 5)
                (format t "  :code triangle violation: u=~a -> v=~a -> w=~a: d(u->w)=~d > ~d + ~d~%"
                        (ast->sexp u) (ast->sexp v) (ast->sexp w) duw duv dvw))
              (incf code-tri-violations)))))))
  (format t "  :code over 9 sample ASTs: asymmetries=~d, triangle violations=~d~%"
          code-asym code-tri-violations))

(format t "~&=== 4. CHECK KERNEL INTEGER DIVISION AND :SOLVE-/-1 ===~%")
(dolist (pair '((12 4) (15 4) (-15 4) (15 -4) (10 4) (10 5)))
  (let ((res (evaluate (term `(/ ,(lit :int (first pair)) ,(lit :int (second pair)))) nil nil)))
    (format t "  (/ ~3d ~3d) => ~a (~a)~%"
            (first pair) (second pair) (evaluation-value res) (evaluation-status res))))
