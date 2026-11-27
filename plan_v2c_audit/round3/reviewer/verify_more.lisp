;;;; Follow-up checks: (1) map-adjacent :spec with *occam* T,
;;;; (2) triangle inequality stress test on (:gf 5) and (:seq :int) replacement cap!
(load "/home/tlh24/lisploop/load.lisp")
(load "/home/tlh24/lisploop/plan_v2c_audit/proto/tg-probe.lisp")

;; Check (:gf 5) and (:seq :int) wider triangle inequality in lisploop
(let ((gf5 (lisploop:gf 5))
      (gf-viol 0))
  (dotimes (u 5)
    (dotimes (v 5)
      (dotimes (w 5)
        (let ((duv (lisploop:correction-bit-size u v gf5))
              (dvw (lisploop:correction-bit-size v w gf5))
              (duw (lisploop:correction-bit-size u w gf5)))
          (when (> duw (+ duv dvw))
            (format t "GF(5) tri viol: ~d -> ~d -> ~d : ~d > ~d + ~d~%" u v w duw duv dvw)
            (incf gf-viol))))))
  (format t "GF(5) triangle violations: ~d~%" gf-viol))

;; Test wider (:seq :int) for triangle inequality violations (especially around replacement cap!)
(let* ((seq-t (lisploop:sequence-type :int))
       (seqs '(() (0) (100) (0 0 0) (0 0 100) (100 100 100) (1 2 3 4 5) (1 2 3 4 999) (9 8 7)))
       (viol 0))
  (dolist (u seqs)
    (dolist (v seqs)
      (dolist (w seqs)
        (let ((duv (lisploop:correction-bit-size u v seq-t))
              (dvw (lisploop:correction-bit-size v w seq-t))
              (duw (lisploop:correction-bit-size u w seq-t)))
          (when (> duw (+ duv dvw))
            (when (< viol 8)
              (format t "SEQ tri viol: ~a -> ~a -> ~a : d(u->w)=~d > d(u->v)=~d + d(v->w)=~d~%"
                      u v w duw duv dvw))
            (incf viol))))))
  (format t "(:seq :int) wider triangle violations: ~d~%" viol))

;; Test tg-probe with *occam* = T on map-adjacent's actual 8 :spec rows!
(in-package :tg)
(let* ((*occam* t)
       (task (tk "map-adjacent" '((xs :seq) (f :code))
                 (lambda (xs f) (loop for (a b) on xs while b collect (funcall f b a)))))
       (exs (mapcar (lambda (r) (cons (list (cons 'xs (first r)) (cons 'f (second r))) (third r)))
                    '((() - ()) ((9) - ()) ((4 9) - (5)) ((1 4 9) - (3 5))
                      (() + ()) ((5) + ()) ((2 5) + (7)) ((1 2 5) + (3 7))))))
  (destructuring-bind (prog cand cells ms notes scan)
      (timed (lambda () (solve-task task exs 10 15000000)))
    (declare (ignore cells scan))
    (format t "map-adjacent (:spec, 8 rows) with *OCCAM*=T -> cand=~d ms=~d held-out=~d/200 prog=~s~%  notes=~a~%"
            cand ms (if prog (verify task prog) 0) prog notes)))
