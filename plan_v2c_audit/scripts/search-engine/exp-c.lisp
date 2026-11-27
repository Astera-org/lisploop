;;; EXP-C: how many candidates does a Stage A budget buy?  Read-only w.r.t. the repository.
(load "/home/tlh24/lisploop/load.lisp")
(in-package #:lisploop)
(clear-knowledge-library)

(defun stage-a-yield (name frame language limit &optional description-limit)
  (let* ((job (start-heuristic-search frame language :description-limit description-limit))
         (message (resume-heuristic-search job limit))
         (obs (heuristic-search-observation job))
         (best (heuristic-search-best job)))
    (format t "[stage-a] ~A work-limit=~D -> ~A spent=~D records(priced candidates)=~D buckets=~D models=~D enum-size=~D completed-bound=~D bound=~D~%   best=~A exact=~A program-bits=~A residual-bits=~A~%   ledger=~S~%"
            name limit (message-claim message) (ledger-total (heuristic-search-ledger job))
            (length (observation-job-records obs)) (length (observation-job-buckets obs))
            (length (heuristic-search-models job))
            (enumerator-size (observation-job-enumerator obs))
            (observation-job-completed-bound obs) (heuristic-search-bound job)
            (and best (ast->sexp (heuristic-program best)))
            (and best (heuristic-exact-p best))
            (and best (heuristic-program-bits best)) (and best (heuristic-residual-bits best))
            (sort (copy-list (ledger-counts (heuristic-search-ledger job))) #'> :key #'cdr))))

(let* ((in2 '((0 . :int) (1 . :int)))
       (l1 (make-language :int in2 :operators (list (op :+ :int) (op :* :int)) :literals '(0 1)))
       (l2 (make-language :int in2 :operators (list (op :+ :int) (op :* :int) (op :- :int)
                                                    (op :if :int) (op := :int) (op :< :int))
                                :literals '(0 1)))
       ;; target x*y+x : body = (+ (* x y) x) = 6+6+3+3+3 = 21 bits
       (frame (simple-frame :int in2 '(((0 1) 0) ((1 2) 3) ((2 3) 8) ((3 1) 6) ((2 5) 12) ((4 2) 12))))
       ;; target (x+y)*(x+y)+y : 39 body bits
       (frame2 (simple-frame :int in2 '(((0 1) 2) ((1 2) 11) ((2 3) 28) ((3 1) 17) ((2 5) 54) ((4 2) 38)))))
  (format t "header(2 int inputs -> int)=~D default Stage A bound = header+18 = ~D~%"
          (header-size in2 :int) (header-bound in2 :int 18))
  (dolist (limit '(2000 5000 15000 100000 1000000))
    (stage-a-yield "L1 x*y+x (21 body bits)" frame l1 limit (header-bound in2 :int 40)))
  (dolist (limit '(2000 15000 100000))
    (stage-a-yield "L2 x*y+x (21 body bits)" frame l2 limit (header-bound in2 :int 40)))
  (dolist (limit '(2000 15000 1000000 10000000))
    (stage-a-yield "L1 (x+y)^2+y (39 body bits)" frame2 l1 limit (header-bound in2 :int 40)))
  ;; default bound (18 body bits of slack) with a huge budget: what does it exhaust at?
  (stage-a-yield "L1 default bound, big budget" frame2 l1 10000000))
