;;;; r4-kraft.lisp -- verify-review R4.  Loads the ROOT kernel from the scratch copy (kernel/load.lisp)
;;;; and computes everything with the kernel's own functions.  No randomness.
(load (merge-pathnames "kernel/load.lisp" *load-truename*))
(in-package :lisploop)
(setf *print-pretty* nil *print-right-margin* 100000)

(defun kraft (u vs type &optional (price #'correction-bit-size))
  "Exact rational sum over V in VS of 2^-(price U V TYPE)."
  (loop for v in vs sum (expt 2 (- (funcall price u v type)))))
(defun show (label x) (format t "  ~62a ~8,4f   (= ~a)~%" label (float x 1d0) x))

(defun part-a ()
  (format t "=== R4-A. conditional Kraft sums  sum_v 2^-d(u->v),  d = correction-bit-size (frame.lisp:1533-1582, :1713) ===~%")
  (format t ":bool   d(T->T)=~d d(T->NIL)=~d d(NIL->T)=~d d(NIL->NIL)=~d~%"
          (correction-bit-size t t :bool) (correction-bit-size t nil :bool)
          (correction-bit-size nil t :bool) (correction-bit-size nil nil :bool))
  (show ":bool u=T" (kraft t '(t nil) :bool))
  (show ":bool u=NIL" (kraft nil '(t nil) :bool))
  (dolist (p '(2 3 5 7 13))
    (let ((ty (list :gf p)) (vs (loop for v below p collect v)))
      (when (= p 5)
        (format t "(:gf 5) distances from u=3 to v=0..4: ~a ; replacement price value-bit-size = ~d~%"
                (mapcar (lambda (v) (correction-bit-size 3 v ty)) vs) (value-bit-size 0 ty)))
      (show (format nil "(:gf ~d) u=~d  (min/max over all u: ~,4f / ~,4f)" p (min 3 (1- p))
                    (loop for u in vs minimize (float (kraft u vs ty) 1d0))
                    (loop for u in vs maximize (float (kraft u vs ty) 1d0)))
            (kraft (min 3 (1- p)) vs ty))))
  (let ((vs (loop for v from -1000 to 1000 collect v)))
    (format t ":int distances from u=0 to v=0..8: ~a~%" (loop for v from 0 to 8 collect (correction-bit-size 0 v :int)))
    (show ":int u=0, |v|<=1000, correction-bit-size" (kraft 0 vs :int))
    (show ":int |v|<=1000, plain value-bit-size (no predicted)"
          (kraft 0 vs :int (lambda (u v ty) (declare (ignore u)) (value-bit-size v ty))))
    (show ":int u=17, |v-u|<=1000, correction-bit-size" (kraft 17 (mapcar (lambda (v) (+ v 17)) vs) :int))
    (show ":int u=0, |v|<=100000 (the sum tends to 1.5)" (kraft 0 (loop for v from -100000 to 100000 collect v) :int)))
  ;; Is the equal -> 0 override (frame.lisp:1581) the sole cause?  Re-price ONLY the v = u cell at what the
  ;; branch above line 1581 computed for it (:int and :gf: value-bit-size 0 :int; :bool: 1 bit).
  (format t "the same sums with ONLY the v = u cell re-priced at the pre-override bits (line 1581 undone):~%")
  (flet ((undone (u v ty) (if (equal u v) (if (eq ty :bool) 1 (value-bit-size 0 :int)) (correction-bit-size u v ty))))
    (show ":bool u=T" (kraft t '(t nil) :bool #'undone))
    (show "(:gf 5) u=3" (kraft 3 '(0 1 2 3 4) '(:gf 5) #'undone))
    (show ":int u=0, |v|<=1000" (kraft 0 (loop for v from -1000 to 1000 collect v) :int #'undone))))

;;; ---- B. Stage A: where per-row prices are summed (condense.lisp price-heuristic-model) ----
(defun int-frame (targets)
  "Rows x = 0,1,2,... with singleton integer targets."
  (let ((inputs '((0 . :int))))
    (make-frame (make-schema :inputs inputs :target :int)
                (loop for y in targets for x from 0
                      collect (make-row :key (list :row x) :known (list x)
                                        :requirement (singleton-requirement :int y))))))
(defun model-row (frame model)
  "RESIDUAL-BITS of MODEL as the kernel charged it, and the same number recomputed as
   sum over listed exception rows of [positive-bit-size(row index + 1) + correction bits]
   + positive-bit-size(1 + number of exceptions)."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (rows (frame-rows frame))
         (residual (heuristic-residual model))
         (parts (loop for (key . witness) in residual
                      for idx = (position key rows :key #'row-key :test #'equal)
                      for pred = (eval-expr-value (heuristic-program model) inputs (row-known (nth idx rows)))
                      collect (list idx pred witness (positive-bit-size (1+ idx))
                                    (correction-bit-size pred witness :int))))
         (recomputed (+ (loop for p in parts sum (+ (fourth p) (fifth p)))
                        (if residual (positive-bit-size (1+ (length residual))) 0))))
    (format t "    program ~a  program-bits ~d  residual-bits ~d  recomputed ~d ~a  exceptions (row pred->witness idx-bits corr-bits): ~a~%"
            (ast->sexp (heuristic-program model)) (heuristic-program-bits model) (heuristic-residual-bits model)
            recomputed (if (= recomputed (heuristic-residual-bits model)) "OK" "MISMATCH") parts)
    (= recomputed (heuristic-residual-bits model))))
(defun part-b ()
  (format t "~%=== R4-B. Stage A (condense-heuristic): what a residual is charged ===~%")
  (let ((all-ok t))
    (dolist (targets '((0 0 0 0 0 0) (0 0 0 0 7 0) (7 0 0 0 0 0) (0 0 0 0 0 7) (0 1 0 0 7 0) (1 1 1 1 1 1) (3 3 0 3 3 3 3 3)))
      (let* ((frame (int-frame targets))
             (language (make-language :int '((0 . :int)) :operators nil :literals '(0 1 3))))
        (multiple-value-bind (best message) (condense-heuristic frame language :work-limit 200000)
          (format t "  targets ~a  (~a)~%" targets (message-claim message))
          (dolist (m (cons best (heuristic-alternatives best)))
            (unless (model-row frame m) (setf all-ok nil))))))
    (format t "  every model's residual-bits equals the sparse-exception formula: ~a~%" (if all-ok "YES" "NO"))
    ;; relational-linkage-residual (enumerate.lisp:607-687): pairs = must-agree links between rows
    (let* ((inputs '((0 . :int)))
           (frame (make-frame (make-schema :inputs inputs :target :int)
                              (loop for x from 0 below 5
                                    collect (make-row :key (list :row x) :known (list x)
                                                      :requirement (singleton-requirement :int 0)))
                              :pairs '(((:row 0) (:row 1)) ((:row 1) (:row 2)) ((:row 2) (:row 3)) ((:row 3) (:row 4))))))
      (dolist (outcomes '((5 5 5 5 5) (5 5 6 6 6) (5 6 6 6 9)))
        (multiple-value-bind (entries total pair-bits anchor-bits) (relational-linkage-residual frame outcomes)
          (format t "  relational-linkage-residual, 4 must-agree pairs, outcomes ~a: entries ~a total ~d (pair ~d anchor ~d) ; recomputed over VIOLATED pairs only: ~d~%"
                  outcomes entries total pair-bits anchor-bits
                  (loop for (a b) on outcomes for idx from 0 while b
                        unless (= a b) sum (+ (positive-bit-size (1+ idx)) (correction-bit-size a b :int)))))))
    ;; Kraft sum of the Stage-A residual code over ALL integer target columns of N rows, for a fixed
    ;; predicted column: sum over exception sets E and nonzero deltas.  W = sum_{delta/=0} 2^-vbs(delta) <= 1/2.
    (let ((w (loop for d from -100000 to 100000 unless (zerop d) sum (expt 2 (- (value-bit-size d :int))))))
      (format t "  sum over nonzero deltas (|delta|<=100000) of 2^-value-bit-size = ~,6f~%" (float w 1d0))
      (dolist (n '(1 2 4 8 16))
        (let ((e (make-array (1+ n) :initial-element 0)))   ; elementary symmetric sums of the per-row weights
          (setf (aref e 0) 1)
          (dotimes (j n)
            (let ((wj (* w (expt 2 (- (positive-bit-size (1+ j)))))))
              (loop for k from n downto 1 do (incf (aref e k) (* wj (aref e (1- k)))))))
          (let ((inexact (loop for k from 1 to n sum (* (aref e k) (expt 2 (- (positive-bit-size (1+ k))))))))
            (format t "  N=~2d rows: Kraft weight of all INEXACT columns ~,6f ; exact column charged 0 bits -> total ~,6f ; with 1 bit for 'exact' -> ~,6f~%"
                    n (float inexact 1d0) (float (+ 1 inexact) 1d0) (float (+ 1/2 inexact) 1d0))))))))

;;; ---- C. the dense site: induce-row-order (proposals.lisp:707-787) ----
(defun keyed-frame (type targets)
  (let ((inputs '((0 . :int))))
    (make-frame (make-schema :inputs inputs :target type)
                (loop for y in targets for x from 1
                      collect (make-row :key (list :row x) :known (list x)
                                        :requirement (singleton-requirement type y))))))
(defun chain-bits* (type targets)
  "chain-bits exactly as INDUCE-ROW-ORDER's local functions compute them for the key X0 over one
   integer input: value-bit-size of the first target + correction-bit-size of each next one from the
   one before + body-size of the key."
  (+ (value-bit-size (first targets) type)
     (loop for (a . more) on targets while more sum (correction-bit-size a (first more) type)) ; (targets may be NIL = false)
     (body-size (var 0 :int) '((0 . :int)))))
(defun all-columns (values n)
  (if (zerop n) (list nil) (loop for v in values append (mapcar (lambda (c) (cons v c)) (all-columns values (1- n))))))
(defun part-c ()
  (format t "~%=== R4-C. induce-row-order: the chain price sums a correction for EVERY consecutive pair ===~%")
  (format t "  body-size of the key x0 = ~d bits~%" (body-size (var 0 :int) '((0 . :int))))
  (dolist (n '(3 4 5 6 8))
    (let ((sum 0) (sum-nokey 0) (induced 0) (agree 0) (cols (all-columns '(t nil) n)))
      (dolist (col cols)
        (let ((mine (chain-bits* :bool col)))
          (incf sum (expt 2 (- mine)))
          (incf sum-nokey (expt 2 (- (- mine (body-size (var 0 :int) '((0 . :int)))))))
          (multiple-value-bind (key edges bits baseline) (induce-row-order (keyed-frame :bool col))
            (declare (ignore edges baseline))
            (when key (incf induced) (when (= bits mine) (incf agree))))))
      (format t "  ~d Boolean rows, all ~d target columns: sum 2^-chain-bits = ~,4f incl. the key body, ~,4f for the chain alone;  induce-row-order returned a key on ~d columns, its chain-bits equal mine on ~d~%"
              n (length cols) (float sum 1d0) (float sum-nokey 1d0) induced agree)))
  (format t "  a decision that flips:~%")
  (dolist (col '((nil nil nil nil t t t t) (nil nil nil t t t)))
    (multiple-value-bind (key edges bits baseline) (induce-row-order (keyed-frame :bool col))
      (declare (ignore edges))
      (format t "    Boolean targets ~a by x0=1..~d: induce-row-order -> key ~a chain-bits ~a baseline ~a ; independent ~d bits ; chain with 1 bit on each equal step ~d bits~%"
              col (length col) (and key (ast->sexp key)) bits baseline (length col)
              (+ 1 (1- (length col)) (body-size (var 0 :int) '((0 . :int)))))))
  ;; integers: the family 'N rows, 0 up to row p, then d' for every p and d in {-1,+1}
  (dolist (n '(8 12 20 40))
    (let* ((cols (loop for p from 1 below n append
                   (loop for d in '(-1 1) collect (append (make-list p :initial-element 0) (make-list (- n p) :initial-element d)))))
           (bits (mapcar (lambda (c) (chain-bits* :int c)) cols))
           (ind 0))
      (dolist (c cols) (when (induce-row-order (keyed-frame :int c)) (incf ind)))
      (format t "  ~d integer rows, the ~d one-step columns (0..0 d..d, d=+-1): chain-bits all = ~a ; sum 2^-chain-bits = ~,4f ; a key is induced on ~d of them~%"
              n (length cols) (remove-duplicates bits) (float (loop for b in bits sum (expt 2 (- b))) 1d0) ind))))

;;; ---- D. a second, separate slack: prices that are a MIN of two codes with no selector bit ----
(defun part-d ()
  (format t "~%=== R4-D. (:seq :int): truncated Kraft sums from u = (1 2) over all v of length<=3 with elements in -3..3 ===~%")
  (let* ((ty (sequence-type :int)) (u '(1 2))
         (vs (loop for n from 0 to 3 append (all-columns '(-3 -2 -1 0 1 2 3) n))))
    (format t "  ~d targets; sum 2^-d(u->v) = ~,4f ; the v = u term alone is ~,4f ; all other terms ~,4f~%"
            (length vs) (float (kraft u vs ty) 1d0) (float (expt 2 (- (correction-bit-size u u ty))) 1d0)
            (float (kraft u (remove u vs :test #'equal) ty) 1d0))
    ;; The replacement code value-bit-size is COMPLETE on (:seq :int) (delta-coded length, delta-coded
    ;; elements), i.e. it sums to exactly 1 over all sequences, and d <= value-bit-size everywhere
    ;; (frame.lisp:1572 takes the MIN, with no bit saying which of the two codes was used).  Hence
    ;; sum_all 2^-d = 1 + sum_all (2^-d - 2^-vbs) >= 1 + the same excess over any finite set.
    (let* ((others (remove u vs :test #'equal))
           (excess (loop for v in others sum (- (expt 2 (- (correction-bit-size u v ty))) (expt 2 (- (value-bit-size v ty))))))
           (cheaper (count-if (lambda (v) (< (correction-bit-size u v ty) (value-bit-size v ty))) others))
           (dearer (count-if (lambda (v) (> (correction-bit-size u v ty) (value-bit-size v ty))) others)))
      (format t "  over the ~d targets v /= u: d < value-bit-size on ~d, d > value-bit-size on ~d ; sum (2^-d - 2^-vbs) = ~,4f~%"
              (length others) cheaper dearer (float excess 1d0))
      (format t "  => even with the v = u cell excluded, sum over ALL sequences of 2^-d(u->v) >= 1 + ~,4f - 2^-vbs(u) = ~,4f~%"
              (float excess 1d0) (float (+ 1 excess (- (expt 2 (- (value-bit-size u ty))))) 1d0))
      (format t "  example: d((1 2)->(1 3)) = ~d against value-bit-size((1 3)) = ~d~%"
              (correction-bit-size '(1 2) '(1 3) ty) (value-bit-size '(1 3) ty)))))

(part-a) (part-b) (part-c) (part-d)
(finish-output)
