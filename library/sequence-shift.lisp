;;; A metric for integer sequences: the delay between a prediction and its target.
;;; Battery source: read by `load-battery`, never evaluated. See batteries.lisp.
;;;
;;; :shift-seq is the decoder, and :argmax-corr solves it for the delay as the advance at
;;; which the prediction correlates best with the target. The solver is a conjecture and is
;;; not unique: a delay counts only where it replays through the decoder, and a narrowing by
;;; it keeps the original requirement as a fallback.
;;;
;;; The correlation is costly, and a metric decoder is asked about every miss of its type.
;;; So the solver's guard says when a delay can exist at all: the two sequences are equal,
;;; or they are of one length and the target ends in the zero that an advance fills with.
;;; The guard costs a few steps, and where it fails the correlation is not run.

(:battery :sequence-shift)

;; The sequence advanced by k places, its end filled with zeros.
(:function :shift-seq ((xs (:seq :int)) (k :int)) (:seq :int)
  (if (= xs ()) ()
      (if (< 0 k)
          (concat (cons (:shift-seq (tail xs) (- k 1)) (cons (cons 0 ()) ())))
          xs))
  :examples ((('(3 1 4 1 5) 0) => '(3 1 4 1 5))
             (('(3 1 4 1 5) 2) => '(4 1 5 0 0))))

;; The correlation of two sequences over their common length.
(:function :seq-corr ((xs (:seq :int)) (ys (:seq :int))) :int
  (if (= xs ()) 0
      (if (= ys ()) 0
          (+ (* (at xs 0) (at ys 0)) (:seq-corr (tail xs) (tail ys)))))
  :examples ((('(1 2 3) '(4 5)) => 14)))

;; The best correlation of a suffix of xs with ys and the place it starts, counted from
;; index; an earlier place wins a tie.
(:function :best-shift ((xs (:seq :int)) (ys (:seq :int)) (index :int)) (:tuple :int :int)
  (if (= xs ()) (tuple 0 index)
      (code-eval (code ((best (:tuple :int :int)) (here :int) (place :int)) (:tuple :int :int)
                   (if (< here (at best 0)) best (tuple here place)))
                 (:best-shift (tail xs) ys (+ index 1))
                 (:seq-corr xs ys)
                 index)))

;; The advance at which xs correlates best with ys.
(:function :argmax-corr ((xs (:seq :int)) (ys (:seq :int))) :int
  (at (:best-shift xs ys 0) 1)
  :examples ((('(3 1 4 1 5) '(4 1 5 0 0)) => 2)))

;; The last element of the sequence, or the default when it has none.
(:function :last-or ((xs (:seq :int)) (default :int)) :int
  (if (= xs ()) default
      (if (= (tail xs) ()) (at xs 0)
          (:last-or (tail xs) default)))
  :examples ((('() 7) => 7)
             (('(3 1 4) 7) => 4)))

(:solver :solve-shift-seq-by-correlation :inverts :shift-seq :at 1 :given (xs ys)
  :witness (:argmax-corr xs ys)
  :guard (if (= xs ys) t
             (and (= (length xs) (length ys))
                  (= (:last-or ys 0) 0)))
  :unique nil
  :metric t
  :examples ((('(3 1 4 1 5) '(4 1 5 0 0)) => 2)
             (('(3 1 4 1 5) '(3 1 4 1 5)) => 0)
             (('(3 1 4 1 5) '(4 1 5 9 2)) => :none)
             (('(3 1 4 1 5) '(4 1 5 0)) => :none)))
