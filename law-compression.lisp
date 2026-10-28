(in-package #:lisploop)

;;; Compress syntax, not truth values. The output is the canonical packet of a
;;; literal (domain marker, ordered list of law packets). Each law packet includes
;;; its input schema and COMPLETE guarded statement. No certificate is encoded.
;;; This storage task uses ordinary Boolean sequences and generic concatenation.
;;; SYMBOLIC.LISP separately lowers AU to constructors on typed quoted values.
(defstruct (law-corpus (:constructor %make-law-corpus)) domain inputs laws packet)

(defun bits-as-values (bits)
  (map 'list (lambda (bit) (= bit 1)) bits))

(defun values-as-bits (values)
  (assert (value-p values (sequence-type :bool)))
  (map 'bit-vector (lambda (value) (if value 1 0)) values))

(defun collect-code-values (writer &optional ledger)
  (let ((values nil))
    (funcall writer (lambda (width value)
                      (charge ledger :packet-assembly width)
                      (loop for i downfrom (1- width) to 0 do
                        (push (logbitp i value) values))))
    (nreverse values)))

(defun law-corpus-type (domain)
  (tuple-type domain (sequence-type (sequence-type :bool))))

(defun make-law-corpus (laws &optional ledger)
  "Snapshot one domain/schema's ordered statements, including duplicate occurrences.
Evidence/provenance are not part of this syntax-compression task."
  (assert laws)
  (let ((domain (law-domain (first laws))) (inputs (law-inputs (first laws))))
    (assert (every (lambda (law) (and (equal domain (law-domain law))
                                     (equal inputs (law-inputs law)))) laws))
    (let* ((copies (mapcar (lambda (law)
                            (make-law domain inputs (first (third (law-equation law)))
                                      (second (third (law-equation law))) :guard (law-guard law))) laws))
           (packets (mapcar (lambda (law)
                             (let ((statement (law-statement law)))
                               (charge ledger :corpus-encoding (syntax-work statement))
                               (collect-code-values (lambda (emit) (emit-bit-model statement inputs emit)) ledger)))
                           copies))
           (literal (lit (law-corpus-type domain) (list 0 packets))))
      (%make-law-corpus :domain (copy-tree domain) :inputs (copy-tree inputs) :laws copies
                       :packet (collect-code-values (lambda (emit) (emit-bit-model literal nil emit)) ledger)))))

(defun decode-law-corpus (packet)
  "Decode a standalone reconstructed corpus into fresh law proposals, never certificates."
  (multiple-value-bind (literal inputs) (decode-model (values-as-bits packet))
    (assert (and (null inputs) (eq :lit (first literal))))
    (let* ((type (second literal)) (domain (second type)) (value (third literal)))
      (assert (equal type (law-corpus-type domain)))
      (assert (eql 0 (first value)))
      (let ((laws
              (loop for bits in (second value) collect
                (multiple-value-bind (statement schema) (decode-model (values-as-bits bits))
                  (assert (and (eq :app (first statement)) (equal (op :if :bool) (second statement))
                               (equal (lit :bool t) (third (third statement)))))
                  (let ((guard (first (third statement))) (equation (second (third statement))))
                    (assert (and (eq :app (first equation)) (eq := (second (second equation)))))
                    (make-law domain schema (first (third equation)) (second (third equation))
                              :guard guard :origin '(:decoded-syntax)))))))
        (assert laws)
        (assert (every (lambda (law) (equal (law-inputs (first laws)) (law-inputs law))) laws))
        laws))))

(defun law-corpus-prefix (corpus &optional ledger)
  (collect-code-values
   (lambda (emit)
     (emit-bit-header nil (law-corpus-type (law-corpus-domain corpus)) emit)
     (funcall emit 2 1) ; literal
     (emit-bit-value 0 (law-corpus-domain corpus) emit)
     (emit-positive (1+ (length (law-corpus-laws corpus))) emit)) ledger))

(defun au-packet-pieces (pattern inputs &optional ledger)
  "Compile a typed AU pattern to fixed packet fragments and typed hole references.
Adjacent fixed fragments merge; operator holes encode opcodes, expression holes
encode bodies. Repeated holes keep their identity. This is only serialization."
  (let ((pieces nil) (fixed nil))
    (labels ((emit (width value)
               (charge ledger :packet-assembly width)
               (loop for i downfrom (1- width) to 0 do (push (logbitp i value) fixed)))
             (flush-fixed ()
               (when fixed (push (list :fixed (nreverse fixed)) pieces) (setf fixed nil)))
             (walk (term)
               (charge ledger :au-compilation (syntax-work term))
               (cond
                 ((eq :hole (first term)) (flush-fixed) (push (copy-tree term) pieces))
                 ((eq :op (first term)) (emit-operator term #'emit))
                 ((not (pattern-has-holes-p term))
                  (emit-bit-expression term inputs (expression-type term inputs) #'emit))
                 (t (assert (eq :app (first term)))
                    (emit 2 2) (walk (second term)) (mapc #'walk (third term))))))
      (emit-bit-header inputs (expression-type pattern inputs t) #'emit)
      (walk pattern) (flush-fixed)
      (nreverse pieces))))

(defun instantiate-packet-pieces (pieces substitution inputs &optional ledger)
  (mapcar
   (lambda (piece)
     (if (eq :fixed (first piece)) (second piece)
         (let ((entry (assoc (second piece) substitution)))
           (assert entry)
           (assert (equal (third piece) (term-sort (cdr entry) inputs)))
           (charge ledger :au-substitution (syntax-work (cdr entry)))
           (collect-code-values
            (lambda (emit)
              (if (eq :op (first (cdr entry))) (emit-operator (cdr entry) emit)
                  (emit-bit-expression (cdr entry) inputs (third piece) emit))) ledger)))) pieces))

(defun packet-chunks-model (chunks &optional ledger)
  "A normal closed VM program; its dictionary and full occurrence order are encoded."
  (multiple-value-bind (representatives residual) (quotient-values chunks ledger)
    (let ((model (app (op :concat :bool)
                      (quotient-model (sequence-type :bool) representatives residual ledger))))
      (charge ledger :construction (syntax-work model))
      model)))

(defun law-row-pieces-model (corpus rows &optional ledger)
  (assert (= (length rows) (length (law-corpus-laws corpus))))
  (let ((chunks (list (law-corpus-prefix corpus ledger))))
    (map nil (lambda (body)
               (let ((size (reduce #'+ body :key #'length)))
                 (push (collect-code-values (lambda (emit) (emit-positive (1+ size) emit)) ledger) chunks)
                 (dolist (piece body) (push piece chunks)))) rows)
    (packet-chunks-model (nreverse chunks) ledger)))

(defun law-template-model (corpus pattern substitutions &optional ledger)
  (assert (= (length substitutions) (length (law-corpus-laws corpus))))
  (let* ((inputs (law-corpus-inputs corpus))
         (pieces (au-packet-pieces pattern inputs ledger)))
    (law-row-pieces-model corpus (mapcar (lambda (substitution)
                                          (instantiate-packet-pieces pieces substitution inputs ledger))
                                        substitutions) ledger)))

(defstruct law-template-group positions pattern substitutions)

(defun law-syntax-shape (term inputs &optional ledger)
  "A supplied structural view, not a learned equivalence: erase leaf values and
compatible operator names, preserving application shape and all types."
  (charge ledger :law-shape)
  (if (eq :app (first term))
      (list :app (operator-type (second term))
            (mapcar (lambda (child) (law-syntax-shape child inputs ledger)) (third term)))
      (list :leaf (expression-type term inputs))))

(defun grouped-law-template-model (corpus &optional ledger)
  "One supplied shape partition; AU each group and encode all occurrence ordering.
This finite proposal construction is not a second acceptance/search loop."
  (let* ((inputs (law-corpus-inputs corpus)) (statements (mapcar #'law-statement (law-corpus-laws corpus)))
         (table (make-hash-table :test #'equal)) (groups nil)
         (rows (make-array (length statements))))
    (loop for statement in statements for i from 0 do
      (let* ((shape (law-syntax-shape statement inputs ledger)) (group (gethash shape table)))
        (unless group
          (setf group (make-law-template-group) (gethash shape table) group)
          (push group groups))
        (push i (law-template-group-positions group))))
    (setf groups (nreverse groups))
    (let ((vector (coerce statements 'vector)))
      (dolist (group groups)
        (setf (law-template-group-positions group) (nreverse (law-template-group-positions group)))
        (multiple-value-bind (pattern substitutions)
            (anti-unify (mapcar (lambda (i) (aref vector i)) (law-template-group-positions group)) inputs ledger)
          (setf (law-template-group-pattern group) pattern (law-template-group-substitutions group) substitutions)
          (let ((pieces (au-packet-pieces pattern inputs ledger)))
            (loop for i in (law-template-group-positions group) for substitution in substitutions do
              (setf (aref rows i) (instantiate-packet-pieces pieces substitution inputs ledger)))))))
    (values (law-row-pieces-model corpus rows ledger) groups)))

(defun propose-law-compressions (corpus &optional ledger)
  "Four complete proposals: literal, whole-packet dictionary, global/grouped AU.
No claim that these exhaust possible templates, groupings or decoder programs."
  (let* ((inputs (law-corpus-inputs corpus))
         (statements (mapcar #'law-statement (law-corpus-laws corpus)))
         (literal (lit (sequence-type :bool) (law-corpus-packet corpus)))
         (chunks (list (law-corpus-prefix corpus ledger))))
    (charge ledger :construction (syntax-work literal))
    (dolist (statement statements)
      (let ((packet (collect-code-values (lambda (emit) (emit-bit-model statement inputs emit)) ledger)))
        (push (append (collect-code-values (lambda (emit) (emit-positive (1+ (length packet)) emit)) ledger)
                      packet) chunks)))
    (multiple-value-bind (pattern substitutions) (anti-unify statements inputs ledger)
      (multiple-value-bind (grouped groups) (grouped-law-template-model corpus ledger)
        (values (list literal (packet-chunks-model (nreverse chunks) ledger)
                      (law-template-model corpus pattern substitutions ledger) grouped)
                pattern substitutions groups)))))

(defun law-corpus-frame (corpus &optional ledger)
  (let ((allowed (finite-allowed (sequence-type :bool) (list (law-corpus-packet corpus)))))
    (charge ledger :corpus-frame (syntax-work (allowed-expression allowed)))
    (make-frame (make-schema :inputs nil :target (sequence-type :bool))
                (list (make-row :key :law-corpus :known nil :allowed allowed)))))
