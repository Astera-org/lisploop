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

(defun additive-transition-fixture (domain starts steps shift-b key-prefix ledger)
  "Record forward transitions T(a,b)=(a+1,b+SHIFT-B). Return the frame and start keys.
The transition is supplied fixture machinery; no invariant sketch enters search."
  (assert (and (integerp steps) (plusp steps)))
  (let* ((field domain) (state-type (tuple-type field field))
         (inputs (list (cons 0 field) (cons 1 field)))
         (transition (app (op :tuple state-type)
                          (app (op :+ field) (var 0 field) (lit field 1))
                          (app (op :+ field) (var 1 field) (lit field shift-b))))
         (rows nil) (anchors nil))
    (loop for start in starts for orbit from 0 do
      (let ((state start))
        (dotimes (step steps)
          (let* ((key (list key-prefix orbit step))
                 (run (evaluate transition inputs state :ledger ledger)))
            (assert (eq (evaluation-status run) :value))
            (when (zerop step) (push (list key :before) anchors))
            (push (make-row :key key :known state
                            :allowed (finite-allowed state-type (list (evaluation-value run)))) rows)
            (setf state (evaluation-value run))))))
    (values (make-frame (make-schema :inputs inputs :target state-type) (nreverse rows))
            (nreverse anchors))))

(defun gf5-transition-fixture (&key (starts '((0 0) (0 1))) (steps 5)
                                  (shift-b 4) (key-prefix :training) ledger)
  (additive-transition-fixture (gf 5) starts steps shift-b key-prefix ledger))

(defun integer-transition-fixture (&key (starts '((-3 1) (0 0) (2 3))) (steps 3)
                                       (shift-b -1) (key-prefix :integer-training) ledger)
  (additive-transition-fixture :int starts steps shift-b key-prefix ledger))

(defun integer-held-out-starts ()
  "Exact cancellation, adjacent large integers, and positive/negative large outputs."
  (let ((n (ash 1 256)))
    (list (list n (- n)) (list (1+ n) (- n))
          (list (- n) n) (list (- (1+ n)) n)
          (list n n) (list (- n) (- n)))))
