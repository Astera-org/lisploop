(in-package #:lisploop)

(defun gf5-fixture (&optional ledger)
  "The oracle generates observations only; neither its syntax nor sketch enters search."
  (let* ((field (gf 5))
         (inputs (list (cons 0 field) (cons 1 field)))
         (oracle (app (op :+ field) (var 0 field)
                      (app (op :* field) (lit field 2) (var 1 field))))
         (records
           (loop for a below 5 append
             (loop for b below 5 for key from (* a 5) collect
               (let ((run (evaluate oracle inputs (list a b) :ledger ledger)))
                 (assert (eq (evaluation-status run) :value))
                 (list key a b (evaluation-value run)))))))
    (values (orient-observations (list field field field) records '(0 1) '(2)
                                  :lookup-p t :ledger ledger)
            oracle records)))

(defun replay-model (expression frame &optional ledger)
  "Decode a fresh model, pass declared values only, and separately check each output."
  (let* ((inputs (schema-inputs (frame-schema frame)))
         (model (read-model (canonical-string expression) inputs))
         (work 0))
    (dolist (row (frame-rows frame))
      (let ((run (evaluate model inputs (row-known row) :ledger ledger)))
        (assert (eq (evaluation-status run) :value))
        (incf work (evaluation-work run))
        (let ((check (check-allowed (row-allowed row) (evaluation-value run) :ledger ledger)))
          (assert (and (eq (evaluation-status check) :value) (evaluation-value check))))))
    work))
