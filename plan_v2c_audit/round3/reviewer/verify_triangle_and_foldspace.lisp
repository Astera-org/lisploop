;;;; Test: (1) Can :code or (:gf p) ever violate directed triangle inequality?
;;;; (2) Does generalizing collect from "list only" to "monoidal fold along pmap"
;;;;     immediately solve seq-corr AND best-shift / argmax-corr on the actual :spec rows?
(load "/home/tlh24/lisploop/load.lisp")
(load "/home/tlh24/lisploop/plan_v2c_audit/proto/tg-probe.lisp")

;; 1a. Shared-hole :code triangle check
(let* ((inps '((0 . :int) (1 . :int) (2 . :int)))
       (ct (lisploop:code-type inps :int))
       (x (lisploop:var 0 :int))
       (y (lisploop:var 1 :int))
       (z (lisploop:var 2 :int))
       (u (lisploop:term `(+ (+ ,x ,x) (+ ,x ,x))))
       (v (lisploop:term `(+ (+ ,y ,y) (+ ,y ,y))))
       (w (lisploop:term `(+ (+ ,y ,y) (+ ,y ,z))))
       (duv (lisploop:correction-bit-size u v ct))
       (dvw (lisploop:correction-bit-size v w ct))
       (duw (lisploop:correction-bit-size u w ct)))
  (format t "Shared-hole :code check: d(u->v)=~d, d(v->w)=~d, sum=~d vs d(u->w)=~d (~a)~%"
          duv dvw (+ duv dvw) duw (if (> duw (+ duv dvw)) "VIOLATION!" "OK")))

;; 1b. Check :seq cap triangle violation!
;; Suppose u = (1000 1000 1000), v = (1001 1001 1001), w = (0)!
;; Wait: u = (0), v = (1000 1000 1000), w = (1001 1001 1001)!
;; d(u -> v) is capped at value-bit-size(v)! d(v -> w) is tiny delta (1 1 1)!
;; Whereas d(u -> w) is capped at value-bit-size(w)! What if value-bit-size(w) > value-bit-size(v) + d(v->w)?!
(let* ((st (lisploop:sequence-type :int))
       (u '())
       (v '(63 63 63 63))     ;; 63 has signed-code 127 (width 7 -> 11 bits each!)
       (w '(64 64 64 64))     ;; 64 has signed-code 129 (width 8 -> 14 bits each! +12 bits jump!)
       (duv (lisploop:correction-bit-size u v st))
       (dvw (lisploop:correction-bit-size v w st))
       (duw (lisploop:correction-bit-size u w st)))
  (format t "Boundary :seq cap check u=() v=(63x4) w=(64x4): d(u->v)=~d + d(v->w)=~d = ~d vs d(u->w)=~d (~a)~%"
          duv dvw (+ duv dvw) duw (if (> duw (+ duv dvw)) "TRIANGLE VIOLATION!" "OK")))

;; Also check :int Elias-delta boundary jump! 63 -> 64!
;; d(0 -> 63) = 11, d(63 -> 64) = 4 (delta=1 -> 4 bits), sum = 15 vs d(0 -> 64) = 14 (OK: 14 <= 15).
;; What about 3 -> 4? d(0 -> 3) = 5, d(3 -> 4) = 4, sum = 9 vs d(0 -> 4) = 8 (OK).
;; What about GF(7) or (:seq :int) with 8 elements of 63 -> 64?!
(let* ((st (lisploop:sequence-type :int))
       (u '())
       (v '(63 63 63 63 63 63 63 63))
       (w '(64 64 64 64 64 64 64 64))
       (duv (lisploop:correction-bit-size u v st))
       (dvw (lisploop:correction-bit-size v w st))
       (duw (lisploop:correction-bit-size u w st)))
  (format t "Boundary :seq cap check 8-elem u=() v=(63x8) w=(64x8): d(u->v)=~d + d(v->w)=~d = ~d vs d(u->w)=~d (~a)~%"
          duv dvw (+ duv dvw) duw (if (> duw (+ duv dvw)) "TRIANGLE VIOLATION!" "OK")))

;; 2. Test unified "reduce along pmap" (pushforward fold over lifted position space) on seq-corr!
(in-package :tg)
(defun reduce-pmap (b2 col init fn)
  "Push a column forward along B2's pmap via monoidal/fold step FN and INIT."
  (let ((out (copy-seq init)))
    (loop for r across (base-pmap b2)
          for v across col
          do (setf (svref out r)
                   (if (or (eq (svref out r) :err) (eq v :err))
                       :err
                       (funcall fn (svref out r) v))))
    out))

;; Try solving seq-corr (:spec, 7 rows) via shape + explode + element class + reduce-pmap!
(let* ((exs (mapcar (lambda (r) (cons (list (cons 'xs (caar r)) (cons 'ys (cadar r))) (second r)))
                    '(((() ()) 0) ((() (5)) 0) (((3) ()) 0)
                      (((3) (5)) 15) (((2 3) (4 5)) 23) (((1 2 3) (2 4 5)) 25)
                      (((2 3) (5)) 10))))
       (task (tk "seq-corr" '((xs :seq) (ys :seq))
                 (lambda (xs ys) (loop for x in xs for y in ys sum (* x y))) :int))
       (base (make-base :n (length exs)))
       (leaves (input-cols task exs))
       (target (map 'simple-vector #'cdr exs))
       ;; Candidate fiber shapes on base: any non-negative :int class up to size 3 in *shape-ops*
       (shape-bank (new-bank base *shape-ops*)))
  (dolist (l leaves) (unless (eq (second l) :seq) (apply #'add-leaf shape-bank l)))
  (run shape-bank 3 :limit 1000)
  (let ((found nil))
    (loop for len-c across (bank-all shape-bank)
          when (and (eq (cls-type len-c) :int)
                    (every (lambda (n) (and (integerp n) (<= 0 n 20))) (cls-col len-c))
                    (some #'plusp (cls-col len-c)))
          do (multiple-value-bind (b2 i) (explode base (cls-col len-c))
               (let ((ebank (new-bank b2 (ops '+ '- '* 'at 'min 'max))))
                 (add-leaf ebank 'i :int i)
                 (dolist (l leaves) (add-leaf ebank (first l) (second l) (pull b2 (third l))))
                 (run ebank 7 :limit 25000)
                 ;; Check monoidal reductions (+ with 0, * with 1, max with 0)
                 (dolist (agg `((+ 0 ,#'+) (* 1 ,#'*) (max 0 ,#'max)))
                   (let ((init-vec (make-array (base-n base) :initial-element (second agg))))
                     (loop for ec across (bank-all ebank)
                           when (and (eq (cls-type ec) :int)
                                     (col= target (reduce-pmap b2 (cls-col ec) init-vec (third agg))))
                           do (setf found (list 'fold-space (cls-term len-c) (first agg) (second agg) (cls-term ec)))
                              (return))))
                 (when found (return)))))
    ;; Verify found fold-space on 200 fresh held-out examples!
    (let ((ho 0)
          (rs (sb-ext:seed-random-state 999)))
      (when found
        (destructuring-bind (_ shape-term agg-op init-val elem-term) found
          (declare (ignore _))
          (let ((agg-fn (ecase agg-op (+ #'+) (* #'*) (max #'max))))
            (dotimes (k 200)
              (let* ((xs (loop repeat (rnd rs 0 12) collect (rnd rs -5 9)))
                     (ys (loop repeat (rnd rs 0 12) collect (rnd rs -5 9)))
                     (env (list (cons 'xs xs) (cons 'ys ys)))
                     (n (ev shape-term env))
                     (pred (let ((acc init-val))
                             (dotimes (i n acc)
                               (setf acc (funcall agg-fn acc (ev elem-term (acons 'i i env))))))))
                (when (equal pred (funcall (task-ref task) xs ys))
                  (incf ho)))))))
      (format t "Unified fold-along-pmap on seq-corr (:spec, 7 rows): found=~s  held-out=~d/200~%"
              found ho))))
