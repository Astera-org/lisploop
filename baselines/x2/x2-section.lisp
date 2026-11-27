;;;; x2-section.lisp -- the milestone code picks the answer term that satisfies the most rows.
;;;; At a 16-bit body bound only one-operator terms exist, so the plain inverse wins. This script
;;;; scores, with the same row test, some terms that a richer answer language would contain,
;;;; to see whether the plain inverse would still be picked. Nothing is enumerated here.
(load (merge-pathnames "x2-common.lisp" (make-pathname :name nil :type nil :defaults *load-truename*)))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defun rows-satisfied (discovery model)
  (let* ((relation (solve-discovery-relation discovery))
         (domain (arithmetic-relation-domain relation))
         (inputs (arithmetic-inputs domain))
         (check (instantiate (arithmetic-requirement relation (solve-discovery-position discovery))
                             (list (cons 2 model)) :var)))
    (loop for row in (frame-rows (solve-discovery-frame discovery))
          count (multiple-value-bind (status value) (x2-eval check inputs (row-known row))
                  (and (eq status :value) (eq value t))))))

(format t "~&===== Rows satisfied by hand-written candidates, under the milestone code's own row test =====~%")
(dolist (domain (list (gf 5) :int))
  (let* ((values (x2-values domain)) (inputs (arithmetic-inputs domain))
         (k (var 0 domain)) (c (var 1 domain)))
    (dolist (spec (list (list :* 1 (list (term `(/ ,c ,k))
                                         (term `(if (= ,k 0) 0 (/ ,c ,k)))
                                         (term `(if (= ,k 0) ,c (/ ,c ,k)))))
                        (list :/ 1 (list (term `(/ ,k ,c))
                                         (term `(if (= ,c 0) 1 (/ ,k ,c)))
                                         (term `(if (= ,c 0) (+ ,k 1) (/ ,k ,c)))))))
      (destructuring-bind (name position candidates) spec
        (let* ((relation (observe-arithmetic-relation domain name values))
               (discovery (discover-arithmetic-solver relation position values :literals (x2-literals domain))))
          (format t "~%~A, operator ~A, unknown = argument ~D; ~D frame rows; the milestone code's answer: ~A~%"
                  (domain-name domain) (string-downcase name) position
                  (length (frame-rows (solve-discovery-frame discovery)))
                  (short (solve-discovery-witness discovery)))
          (dolist (candidate candidates)
            (format t "   ~3D rows   body ~3D bits   ~A~%" (rows-satisfied discovery candidate)
                    (body-size candidate inputs) (short candidate))))))))
