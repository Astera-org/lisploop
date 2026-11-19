;;; Scans: a state threaded through a sequence of actions, every state reported.
;;; Battery source: read by `load-battery`, never evaluated. See batteries.lisp.
;;;
;;; The two entries are one function at two state types. They keep separate names because
;;; the tasks that use them name them.

(:battery :scans)

;; An integer state.
(:function :scan ((actions (:seq :int)) (state :int)
                  (step (:code ((0 . :int) (1 . :int)) :int)))
    (:seq :int)
  (if (= actions ()) ()
      (cons (code-eval step state (at actions 0))
            (:scan (tail actions) (code-eval step state (at actions 0)) step)))
  :examples ((('() 4 (code ((state :int) (action :int)) :int (+ state action))) => '())
             (('(2 -1 3) 1 (code ((state :int) (action :int)) :int (+ state action))) => '(3 2 5))))

;; A state that is a pair of integers.
(:function :scan-pair ((actions (:seq :int)) (state (:tuple :int :int))
                       (step (:code ((0 . (:tuple :int :int)) (1 . :int)) (:tuple :int :int))))
    (:seq (:tuple :int :int))
  (if (= actions ()) ()
      (cons (code-eval step state (at actions 0))
            (:scan-pair (tail actions) (code-eval step state (at actions 0)) step)))
  :examples ((('(1 1) '(0 10)
               (code ((state (:tuple :int :int)) (action :int)) (:tuple :int :int)
                 (tuple (+ (at state 0) action) (+ (at state 1) action))))
              => '((1 11) (2 12)))))
