;;;; xs-m3.lisp -- M3: finding a row correspondence when no key identifies rows.
;;;; A directed graph is two spaces: a NODE space and an EDGE space with two map
;;;; columns (source, target).  H is G with the rows of both spaces permuted.
;;;; The node bijection is found with colour refinement + individualization,
;;;; using only the prototype's change-of-base primitives:
;;;;   PULL    (re-index: an edge row reads the colour of the node it points to)
;;;;   COLLECT (group edge cells by the node they belong to)
;;;; plus one group-by that turns keys into dense colour ids.
;;;; Loaded AFTER the unmodified tg-probe.lisp (see run.sh).  Everything is seeded.
(in-package :tg)
(declaim (optimize (speed 2) (safety 1) (debug 0)))

(defun fine-now () (multiple-value-bind (s us) (sb-ext:get-time-of-day) (+ s (* us 1d-6))))

;;; --- a graph as two spaces and two maps ---
(defstruct gr n m src tgt esrc etgt)      ; ESRC / ETGT: the edge space seen along the source / target map
(defun mk-gr (n src tgt)
  (let ((nb (make-base :n n)) (src (coerce src 'simple-vector)) (tgt (coerce tgt 'simple-vector)))
    (make-gr :n n :m (length src) :src src :tgt tgt
             :esrc (make-base :n (length src) :parent nb :pmap src)
             :etgt (make-base :n (length src) :parent nb :pmap tgt))))
(defun iota-vec (n) (let ((v (make-array n))) (dotimes (i n v) (setf (svref v i) i))))
(defun shuffle (v rs)
  (loop for i from (1- (length v)) downto 1 do (rotatef (svref v i) (svref v (random (1+ i) rs)))) v)
(defun permuted-copy (g rs)
  "H: node rows renamed by a random permutation, edge rows shuffled.  Returns H and
   the hidden permutation (used afterwards only to say whether the same one was found)."
  (let* ((perm (shuffle (iota-vec (gr-n g)) rs)) (sg (shuffle (iota-vec (gr-m g)) rs))
         (src (make-array (gr-m g))) (tgt (make-array (gr-m g))))
    (dotimes (e (gr-m g))
      (setf (svref src (svref sg e)) (svref perm (svref (gr-src g) e))
            (svref tgt (svref sg e)) (svref perm (svref (gr-tgt g) e))))
    (values (mk-gr (gr-n g) src tgt) perm)))

;;; --- one refinement round = two re-indexes, two collects, one group-by ---
(defvar *rounds* 0)
(defun key-hash (c out in)
  (let ((h (logand (* (+ c 7) 2654435761) #xFFFFFFFFFF)))
    (declare (type fixnum h))
    (dolist (x out) (setf h (logand (+ (* h 1000003) x 1) #xFFFFFFFFFF)))
    (setf h (logand (+ (* h 1000003) 999983) #xFFFFFFFFFF))
    (dolist (x in) (setf h (logand (+ (* h 1000003) x 1) #xFFFFFFFFFF)))
    h))
(defun round-ids (g col tab next)
  "New colour of every node of G: the group-by id of (colour, sorted out-neighbour
   colours, sorted in-neighbour colours).  TAB / NEXT are shared between the two
   graphs of a round, so equal keys get equal ids in both."
  (let* ((out (collect (gr-esrc g) (pull (gr-etgt g) col)))   ; per node: colours of its out-neighbours
         (in (collect (gr-etgt g) (pull (gr-esrc g) col)))    ; per node: colours of its in-neighbours
         (new (make-array (gr-n g))))
    (dotimes (v (gr-n g) new)
      (let* ((o (sort (svref out v) #'<)) (i (sort (svref in v) #'<)) (c (svref col v))
             (key (list* c o i)) (h (key-hash c o i))
             (hit (assoc key (gethash h tab) :test #'equal)))
        (setf (svref new v)
              (if hit (cdr hit)
                  (progn (push (cons key (car next)) (gethash h tab)) (1- (incf (car next))))))))))

(defun refine (g h cg ch ncol)
  "Refine the colourings CG of G and CH of H together until no class splits.
   Returns (values cg ch ncol), or NIL as soon as the two colour histograms differ."
  (loop
    (let* ((tab (make-hash-table)) (next (list 0))
           (ng (round-ids g cg tab next)) (nh (round-ids h ch tab next)) (k (car next))
           (cnt (make-array k :initial-element 0)))
      (incf *rounds*)
      (loop for c across ng do (incf (svref cnt c)))
      (loop for c across nh do (decf (svref cnt c)))
      (unless (every #'zerop cnt) (return nil))
      (when (= k ncol) (return (values ng nh k)))            ; nothing split: stable
      (setf cg ng ch nh ncol k))))

(defun pick-class (cg ncol)
  "Colour of the smallest class with at least 2 nodes (lowest id on ties), or NIL."
  (let ((cnt (make-array ncol :initial-element 0)) (best nil))
    (loop for c across cg do (incf (svref cnt c)))
    (dotimes (c ncol best)
      (when (and (> (svref cnt c) 1) (or (null best) (< (svref cnt c) (svref cnt best)))) (setf best c)))))

(defun verify-iso (g h p)
  "Re-index G's two edge columns through the node map P and compare with H's
   edge rows as multisets (a group-by on the pair)."
  (let ((tab (make-hash-table)) (n (gr-n g)))
    (dotimes (e (gr-m g))
      (incf (gethash (+ (* n (svref p (svref (gr-src g) e))) (svref p (svref (gr-tgt g) e))) tab 0)))
    (dotimes (e (gr-m h))
      (decf (gethash (+ (* n (svref (gr-src h) e)) (svref (gr-tgt h) e)) tab 0)))
    (loop for v being the hash-values of tab always (zerop v))))

(defun find-iso (g h &key (max-back 2000000))
  "Colour refinement, then individualize-and-refine with backtracking.
   Returns a plist: :perm (node map G->H or nil) and the counters."
  (let* ((n (gr-n g)) (*rounds* 0) (indiv 0) (back 0) (stack '())
         (cg (make-array n :initial-element 0)) (ch (make-array n :initial-element 0)) (ncol 1)
         (first-pass t) rounds0 classes0 uniq0 perm (status :searching))
    (when (or (/= n (gr-n h)) (/= (gr-m g) (gr-m h))) (setf status :sizes-differ))
    (loop while (eq status :searching) do
      (let ((ok nil))
        (multiple-value-bind (ng nh k) (refine g h cg ch ncol)
          (when first-pass
            (setf first-pass nil rounds0 *rounds* classes0 (or k 0)
                  uniq0 (if ng (let ((cnt (make-array k :initial-element 0)))
                                 (loop for c across ng do (incf (svref cnt c)))
                                 (count 1 cnt))
                            0)))
          (when ng
            (setf cg ng ch nh ncol k ok t)
            (let ((cls (pick-class cg ncol)))
              (if (null cls)
                  ;; every colour is unique: read the bijection off the colours, then verify it
                  (let ((at (make-array ncol)) (p (make-array n)))
                    (dotimes (v n) (setf (svref at (svref ch v)) v))
                    (dotimes (u n) (setf (svref p u) (svref at (svref cg u))))
                    (if (verify-iso g h p) (setf perm p status :isomorphic) (setf ok nil)))
                  ;; individualize: the first G node of the class against each H node of the class
                  (let ((u (position cls cg)) (vs (loop for v below n when (= (svref ch v) cls) collect v)))
                    (push (list cg ch ncol u (cdr vs)) stack)
                    (setf cg (copy-seq cg) ch (copy-seq ch))
                    (setf (svref cg u) ncol (svref ch (car vs)) ncol)
                    (incf ncol) (incf indiv))))))
        (unless (or ok (not (eq status :searching)))
          ;; contradiction: undo the latest individualization, try its next candidate
          (loop
            (when (null stack) (setf status :not-isomorphic) (return))
            (incf back)
            (when (> back max-back) (setf status :gave-up) (return))
            (destructuring-bind (cg0 ch0 n0 u vs) (car stack)
              (cond (vs (setf (fifth (car stack)) (cdr vs))
                        (setf cg (copy-seq cg0) ch (copy-seq ch0) ncol n0)
                        (setf (svref cg u) ncol (svref ch (car vs)) ncol)
                        (incf ncol) (incf indiv)
                        (return))
                    (t (pop stack))))))))
    (list :status status :perm perm :rounds0 rounds0 :classes0 classes0 :uniq0 uniq0
          :indiv indiv :back back :rounds *rounds*)))

;;; --- graph generators (all seeded) ---
(defun g-sparse (n m rs)
  "Random simple digraph: M distinct ordered pairs (u,v), u /= v."
  (let ((seen (make-hash-table)) src tgt)
    (loop while (< (length src) m)
          do (let ((u (random n rs)) (v (random n rs)))
               (unless (or (= u v) (gethash (+ (* u n) v) seen))
                 (setf (gethash (+ (* u n) v) seen) t) (push u src) (push v tgt))))
    (mk-gr n src tgt)))
(defun g-tree (n rs)
  "Random recursive tree, edges child -> parent."
  (mk-gr n (loop for i from 1 below n collect i) (loop for i from 1 below n collect (random i rs))))
(defun g-grid (w h &key directed)
  "W x H grid; arcs right and down, and their reverses unless DIRECTED."
  (let (src tgt)
    (flet ((arc (a b) (push a src) (push b tgt) (unless directed (push b src) (push a tgt))))
      (dotimes (i h) (dotimes (j w)
        (let ((v (+ (* i w) j)))
          (when (< (1+ j) w) (arc v (1+ v)))
          (when (< (1+ i) h) (arc v (+ v w)))))))
    (mk-gr (* w h) src tgt)))
(defun g-cycles (lens &key undirected)
  "Disjoint cycles of the given lengths."
  (let (src tgt (base 0))
    (dolist (l lens)
      (dotimes (i l)
        (let ((a (+ base i)) (b (+ base (mod (1+ i) l))))
          (push a src) (push b tgt) (when undirected (push b src) (push a tgt))))
      (incf base l))
    (mk-gr base src tgt)))
(defun g-regular (n k rs)
  "K random permutations: every node has out-degree K and in-degree K (a multigraph)."
  (let (src tgt)
    (dotimes (j k) (let ((p (shuffle (iota-vec n) rs))) (dotimes (i n) (push i src) (push (svref p i) tgt))))
    (mk-gr n src tgt)))

;;; --- driver ---
(defun m3-case (name g h &optional hidden quiet)
  (sb-ext:gc :full t)
  (let* ((t0 (fine-now)) (r (find-iso g h)) (ms (* 1000 (- (fine-now) t0))) (p (getf r :perm)))
    (setf (getf r :ms) ms)
    (when quiet (return-from m3-case r))
    (format t "~38a ~6d ~6d ~15a ~7d ~7d ~5d ~7d ~8d ~8d ~10,1f  ~a~%" name (gr-n g) (gr-m g)
            (getf r :status) (getf r :classes0) (getf r :uniq0) (getf r :rounds0)
            (getf r :indiv) (getf r :back) (getf r :rounds) ms
            (cond ((null p) "")
                  ((null hidden) "verified")
                  ((equalp p hidden) "verified; = the hidden permutation")
                  (t (format nil "verified; differs from the hidden permutation on ~d nodes (an automorphism)"
                             (count nil (map 'list #'eql p hidden))))))
    (finish-output)
    r))

(defun m3 (&key (big t))
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
    (format t "=== M3. ROW CORRESPONDENCE WITHOUT A KEY: colour refinement + individualization, from group-by and re-index ===~%")
    (format t "H = G with node rows and edge rows randomly permuted (unless stated).  classes1 / unique1 / rnd1 = colour classes, nodes with a~%unique colour, and rounds after the FIRST refinement; indiv = individualizations tried; backtr = those undone; rounds = all refinement rounds.~%~%")
    (format t "~38a ~6a ~6a ~15a ~7a ~7a ~5a ~7a ~8a ~8a ~10a~%" "case" "n" "m" "result" "classes1" "unique1" "rnd1"
            "indiv" "backtr" "rounds" "ms")
    (flet ((iso (name g seed)
             (multiple-value-bind (h hidden) (permuted-copy g (sb-ext:seed-random-state seed))
               (m3-case name g h hidden))))
      (dolist (n (if big '(100 1000 10000) '(100 1000)))
        (iso (format nil "sparse random, m=3n (out-deg 3)") (g-sparse n (* 3 n) (sb-ext:seed-random-state (+ 10 n))) 1))
      (dolist (n (if big '(100 1000 10000) '(100 1000)))
        (iso (format nil "sparse random, m=1.5n (deg in+out 3)") (g-sparse n (floor (* 3 n) 2) (sb-ext:seed-random-state (+ 20 n))) 2))
      (dolist (n (if big '(100 1000 10000) '(100 1000)))
        (iso "random recursive tree" (g-tree n (sb-ext:seed-random-state (+ 30 n))) 3))
      (iso "grid 30x30, arcs both ways" (g-grid 30 30) 4)
      (iso "grid 30x30, arcs right/down only" (g-grid 30 30 :directed t) 5)
      (iso "one directed cycle" (g-cycles '(200)) 6)
      (iso "one cycle, arcs both ways" (g-cycles '(200) :undirected t) 7)
      (format t "~%non-isomorphic pairs (must be rejected):~%")
      (dolist (n '(50 100 200 400))
        (m3-case (format nil "2 cycles of ~d vs 1 cycle of ~d" (/ n 2) n)
                 (g-cycles (list (/ n 2) (/ n 2)))
                 (permuted-copy (g-cycles (list n)) (sb-ext:seed-random-state 8))))
      (m3-case "same, arcs both ways (n=200)" (g-cycles '(100 100) :undirected t)
               (permuted-copy (g-cycles '(200) :undirected t) (sb-ext:seed-random-state 9)))
      (format t "~%ADDED: where backtracking grows~%")
      (dolist (n (if big '(100 300 1000 3000) '(100 300)))   ; 5 graphs per size: the right partner sits at a random place
        (let ((rs (loop for seed from 1 to 5
                        collect (multiple-value-bind (h hidden)
                                    (permuted-copy (g-regular n 3 (sb-ext:seed-random-state (+ 40 n seed)))
                                                   (sb-ext:seed-random-state (+ 100 seed)))
                                  (declare (ignore hidden))
                                  (m3-case "" (g-regular n 3 (sb-ext:seed-random-state (+ 40 n seed))) h nil t)))))
          (flet ((avg (k) (/ (reduce #'+ rs :key (lambda (r) (getf r k))) 5.0)))
            (format t "~38a ~6d ~6d ~15a ~7d ~7d ~5d ~7,1f ~8,1f ~8,1f ~10,1f  mean of 5 graphs; backtracks per graph ~a~%"
                    "3-regular random (3 permutations)" n (* 3 n)
                    (format nil "~d/5 isomorphic" (count :isomorphic rs :key (lambda (r) (getf r :status))))
                    1 0 1 (avg :indiv) (avg :back) (avg :rounds) (avg :ms)
                    (mapcar (lambda (r) (getf r :back)) rs)))))
      (iso "isomorphic: C3+C3+C6 (regular, mixed)" (g-cycles '(3 3 6)) 11)
      (dolist (k '(2 3 4 5))
        (iso (format nil "isomorphic: ~d x C6" k) (g-cycles (make-list k :initial-element 6)) 12))
      (dolist (k '(2 3 4 5))
        (m3-case (format nil "NON-iso: ~d x C6 vs ~d x C6 + 2 x C3" k (1- k))
                 (g-cycles (make-list k :initial-element 6))
                 (permuted-copy (g-cycles (append (make-list (1- k) :initial-element 6) '(3 3)))
                                (sb-ext:seed-random-state 13)))))
    (finish-output)))
