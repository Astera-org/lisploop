;;;; proto-table-check.lisp -- loaded after the UNMODIFIED tg-probe.lisp.
;;;; On the rows the prototype's experiment C actually builds for c = a*b (a, b in -6..6, every row
;;;; a forward evaluation), how often is the divisibility condition false? If never, no search over
;;;; those rows can prefer a guard that contains it.
(in-package :tg)

(defun table-check ()
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase)
        (divisible '(= (* (div c b) b) c)) (nonzero '(not (= b 0)))
        (counts (list :t 0 :f 0 :err 0)) (agree 0) (rows 0) (unique-rows 0))
    (loop for a from -6 to 6 do
      (loop for b from -6 to 6 do
        (let* ((c (* a b))
               (env (list (cons 'a a) (cons 'b b) (cons 'c c)))
               (d (ev divisible env)) (n (ev nonzero env)))
          (incf rows)
          (when (/= b 0) (incf unique-rows))
          (incf (getf counts (if (member d '(:t :f)) d :err)))
          (when (eq (eq d :t) (eq n :t)) (incf agree)))))
    (format t "prototype table for c = a*b: ~d rows (a, b in -6..6); a is determined by (b, c) on ~d rows (~,1f%)~%"
            rows unique-rows (* 100.0 (/ unique-rows rows)))
    (format t "~s on those rows: true ~d, false ~d, error ~d~%"
            divisible (getf counts :t) (getf counts :f) (getf counts :err))
    (format t "it is true on exactly the rows where ~s is true: ~d of ~d rows agree~%" nonzero agree rows)
    ;; the unknown-divisor table: c = (div a b), floor division, b /= 0
    ;; The same table with flooring division (the prototype's div) and with truncating division
    ;; (the v1 kernel's integer /), in host arithmetic.
    (dolist (division (list (cons "flooring (the prototype's div)" (lambda (x y) (values (floor x y))))
                            (cons "truncating (the v1 kernel's integer /)" (lambda (x y) (values (truncate x y))))))
      (let ((div (cdr division))
            (groups (make-hash-table :test 'equal)) (rows 0) (unique 0) (replay-ok 0) (answer-is-b 0) (answer-err 0)
            (unique-and-right 0) (example nil))
        (loop for b from -9 to 9 unless (zerop b) do
          (loop for a from -6 to 6 do (push b (gethash (cons a (funcall div a b)) groups))))
        (loop for b from -6 to 6 unless (zerop b) do
          (loop for a from -6 to 6 do
            (let* ((c (funcall div a b)) (others (gethash (cons a c) groups)) (unique-p (null (rest others)))
                   (answer (if (zerop c) :err (funcall div a c))))
              (incf rows)
              (when unique-p (incf unique))
              (cond ((eq answer :err) (incf answer-err))
                    (t (when (eql answer b) (incf answer-is-b))
                       (when (eql c (funcall div a answer)) (incf replay-ok))))
              (if (and unique-p (eql answer b))
                  (incf unique-and-right)
                  (when (and unique-p (null example)) (setf example (list a b c answer)))))))
        (format t "table for c = a div b with b unknown, ~a: ~d rows; b is determined by (a, c) on ~d (~,1f%, range padded by 3)~%"
                (car division) rows unique (* 100.0 (/ unique rows)))
        (format t "   the milestone code's answer, a div c: undefined on ~d rows (c = 0), equal to b on ~d, replays to c on ~d~%"
                answer-err answer-is-b replay-ok)
        (format t "   on the ~d rows where b is determined, a div c equals b on ~d; first miss (a b c answer) = ~s~%"
                unique unique-and-right example)))
    (finish-output)))
