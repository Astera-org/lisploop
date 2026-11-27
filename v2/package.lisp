;;; The topology-geometry kernel of plan_v2c.md. Stage A: the store core.
;;;
;;; The whole structure is four nouns (plan section 5.2):
;;;   SPACE   a finite set of rows; rows are independent contexts and have no content of their own
;;;   COLUMN  one cell per row of a space
;;;   TERM    an operator applied to terms, or a leaf; stored once each
;;;   CLASS   all the terms that denote the same column on a given space
;;; plus ordinary hash tables to find things.

(defpackage #:lisploop2
  (:nicknames #:ll2)
  (:use #:cl)
  (:shadow #:space))   ; SPACE is this kernel's first noun; the optimization quality is not used
