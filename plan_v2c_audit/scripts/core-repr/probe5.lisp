;;; probe5.lisp — isolate v2 :tabulate totality check failure.
(load "/home/tlh24/lisploop/v2/load.lisp")
(in-package #:lisploop)
(defmacro show (label form)
  `(format t "~&~A~%   => ~S~%" ,label (handler-case (multiple-value-list ,form)
                                          (error (c) (list :HOST-ERROR (let ((s (princ-to-string c))) (subseq s 0 (min 200 (length s)))))))))
(let* ((seq (sequence-type :int)) (xs (var 0 seq)) (ins (list (cons 0 seq)))
       (idx-code (code-type '((0 . :int)) :int)))
  (show "(var -1 :int)" (var -1 :int))
  (show "tabulate with total literal code" (provably-total-p (app (op :tabulate :int) (lit :int 4) (lit idx-code (term `(* ,(var 0 :int) ,(var 0 :int)))))))
  (show "tabulate with non-total literal code (/ 1 j): app construction"
        (app (op :tabulate :int) (lit :int 4) (lit idx-code (term `(/ 1 ,(var 0 :int))))))
  (show "grep: where is (var -1 used" nil))
