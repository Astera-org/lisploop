;;; Inverses of the four arithmetic operators, one per operator and argument position.
;;; Battery source: read by `load-battery`, never evaluated. See batteries.lisp.
;;;
;;; Each solver reads k, the argument that is known, and c, the value the operator must
;;; take, and names the z that makes it so. Over a prime field the load certifies witness
;;; and uniqueness exhaustively. Over the integers nothing can be: the witness stays a
;;; conjecture that is replayed where it is used, and division and multiplication are not
;;; unique there at all (truncating division has many preimages, and 0 * z = 0 has every z).
;;; That addition and subtraction have one solution over the integers is taken as an axiom.

(:battery :arithmetic
  :parameters ((?n :int)))

;; z + k = c  and  k + z = c
(:solver :solve-+-0 :inverts :+ :at 0 :over ?n :given (k c)
  :witness (- c k)
  :axioms (:uniqueness)
  :examples (((2 5) => 3)))

(:solver :solve-+-1 :inverts :+ :at 1 :over ?n :given (k c)
  :witness (- c k)
  :axioms (:uniqueness)
  :examples (((2 5) => 3)))

;; z - k = c
(:solver :solve---0 :inverts :- :at 0 :over ?n :given (k c)
  :witness (+ c k)
  :axioms (:uniqueness)
  :examples (((2 5) => 7)))

;; k - z = c
(:solver :solve---1 :inverts :- :at 1 :over ?n :given (k c)
  :witness (- k c)
  :axioms (:uniqueness)
  :examples (((7 5) => 2)))

;; z * k = c  and  k * z = c
(:solver :solve-*-0 :inverts :* :at 0 :over ?n :given (k c)
  :witness (/ c k)
  :guard (not (= k 0))
  :unique :finite
  :examples (((3 12) => 4)
             ((0 5) => :none)))

(:solver :solve-*-1 :inverts :* :at 1 :over ?n :given (k c)
  :witness (/ c k)
  :guard (not (= k 0))
  :unique :finite
  :examples (((3 12) => 4)
             ((0 5) => :none)))

;; z / k = c
(:solver :solve-/-0 :inverts :/ :at 0 :over ?n :given (k c)
  :witness (* c k)
  :guard (not (= k 0))
  :unique :finite
  :examples (((3 4) => 12)
             ((0 4) => :none)))

;; k / z = c
(:solver :solve-/-1 :inverts :/ :at 1 :over ?n :given (k c)
  :witness (/ k c)
  :guard (and (not (= k 0)) (not (= c 0)))
  :unique :finite
  :examples (((12 4) => 3)
             ((12 0) => :none)))
