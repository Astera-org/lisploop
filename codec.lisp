(in-package #:lisploop)

;;; Module 2: codec.lisp
;;; Prefix-coded binary serialization & O(1) size queries over homoiconic S-expressions.
;;; Positive integers use delta coding: gamma(bit-length), then the low bits.

(defconstant +encoding-version+ 7)
(defconstant +opcode-width+ 4)

(defun emit-operator-name (name emit)
  (let ((index (or (operator-index name) (error "Unknown operator ~S" name))))
    (funcall emit +opcode-width+ (min 15 index))
    (when (>= index 15) (emit-positive (- index 14) emit))))

(defun emit-operator (operator emit)
  (let* ((meta (ensure-ast-meta operator))
         (name (ast-meta-id meta))
         (encoded-type (operator-encoded-type name (ast-meta-type meta))))
    (assert (eq :op (ast-meta-kind meta)))
    (emit-operator-name name emit)
    (when encoded-type
      (emit-bit-type encoded-type emit))))

(defun emit-positive (value emit)
  (let* ((width (integer-length value)) (length-width (integer-length width)))
    (assert (plusp value))
    (funcall emit (1- length-width) 0)
    (funcall emit length-width width)
    (funcall emit (1- width) (ldb (byte (1- width) 0) value))))

(defun emit-bit-type (type emit)
  (case type
    (:int (funcall emit 3 0)) (:bool (funcall emit 3 1))
    (otherwise
     (ecase (first type)
       (:gf (funcall emit 3 2) (emit-positive (second type) emit))
       (:tuple (funcall emit 3 3) (emit-positive (length type) emit)
               (dolist (part (rest type)) (emit-bit-type part emit)))
       (:seq (funcall emit 3 4) (emit-bit-type (second type) emit))
       (:code
        (funcall emit 3 5) (emit-bit-inputs (code-inputs type) emit)
        (let ((sort (code-sort type)))
          (funcall emit 1 (if (function-sort-p sort) 1 0))
          (if (function-sort-p sort)
              (progn (emit-positive (1+ (length (second sort))) emit)
                     (mapc (lambda (arg) (emit-bit-type arg emit)) (second sort))
                     (emit-bit-type (third sort) emit))
              (emit-bit-type sort emit))))))))

(defun emit-bit-value (value type emit)
  (case type
    (:int (emit-positive (signed-code value) emit))
    (:bool (funcall emit 1 (if value 1 0)))
    (otherwise
     (ecase (first type)
       (:gf (funcall emit (integer-length (1- (second type))) value))
       (:tuple (loop for item in value for part in (rest type) do (emit-bit-value item part emit)))
       (:seq (emit-positive (1+ (length value)) emit)
             (dolist (item value) (emit-bit-value item (second type) emit)))
       (:code (if (function-sort-p (code-sort type))
                  (let ((meta (ensure-ast-meta value)))
                    (emit-operator-name (ast-meta-id meta) emit)
                    (emit-bit-type (ast-meta-type meta) emit))
                  (emit-bit-expression value (code-inputs type) (code-sort type) emit)))))))

(defun emit-bit-inputs (inputs emit)
  (emit-positive (1+ (length inputs)) emit)
  (dolist (input inputs)
    (emit-positive (1+ (car input)) emit)
    (emit-bit-type (cdr input) emit)))

(defun emit-bit-header (inputs type emit)
  (emit-positive +encoding-version+ emit)
  (emit-bit-inputs inputs emit)
  (emit-bit-type type emit))

(defun header-size (inputs type)
  (let ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs)))
    (+ (positive-bit-size +encoding-version+)
       (inputs-bit-size norm-inputs)
       (type-bit-size type))))

(defun emit-bit-expression (expression inputs type emit)
  (let* ((meta (ensure-ast-meta expression))
         (tag (ast-meta-kind meta)))
    (funcall emit 2 (ecase tag (:var 0) (:lit 1) (:app 2)))
    (ecase tag
      (:var (funcall emit (integer-length (max 0 (1- (length inputs))))
                     (or (position (ast-meta-id meta) inputs :key #'car)
                         (error "Undeclared variable"))))
      (:lit (emit-bit-value (ast-meta-value meta) type emit))
      (:app
       (let ((operator (first expression)))
         (emit-operator operator emit)
         (loop for child in (rest expression)
               for child-type in (second (operator-type operator)) do
                 (emit-bit-expression child inputs child-type emit)))))))

(defun emit-bit-model (expression inputs emit)
  (let ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs)))
    (assert (valid-inputs-p norm-inputs))
    (let ((type (expression-type expression norm-inputs)))
      (emit-bit-header norm-inputs type emit)
      (emit-bit-expression expression norm-inputs type emit))))

(defun description-size (expression &optional inputs)
  "Exact packet length in bits, including the schema; O(1) via cached AST metadata."
  (let ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs)))
    (assert (valid-inputs-p norm-inputs))
    (let ((type (expression-type expression norm-inputs)))
      (+ (header-size norm-inputs type)
         (body-size expression norm-inputs)))))

(defun encode-model (expression &optional inputs)
  (let ((bits (make-array 0 :element-type 'bit :adjustable t :fill-pointer 0)))
    (emit-bit-model expression inputs
                    (lambda (width value)
                      (loop for index downfrom (1- width) to 0 do
                        (vector-push-extend (ldb (byte 1 index) value) bits))))
    bits))

(defun decode-model (bits)
  "Decode the fixed packet format; return expression and declared input schema.
Reject truncation, trailing bits, unused codes and unsupported versions."
  (assert (typep bits 'bit-vector))
  (let ((cursor 0))
    (labels ((take-bits (width)
               (assert (<= (+ cursor width) (length bits)) () "Truncated bit packet")
               (let ((value 0))
                 (dotimes (i width value)
                   (setf value (+ (* 2 value) (aref bits cursor)))
                   (incf cursor))))
             (positive ()
               (let ((zeros 0))
                 (loop while (zerop (take-bits 1)) do (incf zeros))
                 (let ((width (+ (ash 1 zeros) (take-bits zeros))))
                   (assert (<= (1- width) (- (length bits) cursor)) () "Truncated integer")
                   (+ (ash 1 (1- width)) (take-bits (1- width))))))
             (read-inputs ()
               (let ((count (1- (positive))))
                 (assert (<= count (- (length bits) cursor)))
                 (loop repeat count collect (cons (1- (positive)) (read-type)))))
             (read-operator-name ()
               (let* ((prefix (take-bits +opcode-width+))
                      (index (if (= 15 prefix) (+ 14 (positive)) prefix)))
                 (or (operator-by-index index) (error "Unused operator code"))))
             (read-type ()
               (ecase (take-bits 3)
                 (0 :int) (1 :bool) (2 (gf (positive)))
                 (3 (let ((arity (1- (positive))))
                      (assert (<= arity (- (length bits) cursor)))
                      (cons :tuple (loop repeat arity collect (read-type)))))
                 (4 (sequence-type (read-type)))
                 (5 (let* ((inputs (read-inputs)) (function-p (= 1 (take-bits 1)))
                           (sort (if function-p
                                     (let ((count (1- (positive))))
                                       (assert (<= count (- (length bits) cursor)))
                                       (list :fn (loop repeat count collect (read-type)) (read-type)))
                                     (read-type))))
                      (code-type inputs sort)))))
             (read-value (type)
               (case type
                 (:int (decode-signed-code (positive))) (:bool (= 1 (take-bits 1)))
                 (otherwise
                  (ecase (first type)
                    (:gf (let ((value (take-bits (integer-length (1- (second type))))))
                           (assert (< value (second type))) value))
                    (:tuple (mapcar #'read-value (rest type)))
                    (:seq (loop repeat (1- (positive)) collect (read-value (second type))))
                    (:code (if (function-sort-p (code-sort type))
                               (op (read-operator-name) (read-type))
                               (read-expression (code-inputs type) (code-sort type))))))))
             (read-expression (inputs type)
               (ecase (take-bits 2)
                 (0 (let* ((slot (take-bits (integer-length (max 0 (1- (length inputs))))))
                           (input (nth slot inputs)))
                      (assert (and input (equal type (cdr input))))
                      (var (car input) type)))
                 (1 (lit type (read-value type)))
                 (2
                  (let* ((name (read-operator-name))
                         (operand-type (case name
                                         ((:= :member :at :length) (read-type))
                                         (:lookup (tuple-type (read-type) type))
                                         ((:gather :concat :cons :tail)
                                          (assert (and (consp type) (eq (first type) :seq)))
                                          (second type))
                                         (:< (assert (eq type :bool)) :int)
                                         (otherwise
                                          (if (member name *symbolic-primitives*)
                                              (read-type)
                                              type))))
                         (operator (op name operand-type)))
                    (assert (equal type (third (operator-type operator))))
                    (apply #'app operator
                           (mapcar (lambda (child-type) (read-expression inputs child-type))
                                   (second (operator-type operator)))))))))
      (assert (= +encoding-version+ (positive)) () "Unsupported encoding version")
      (let* ((inputs (read-inputs))
             (type (read-type))
             (expression (read-expression inputs type)))
        (assert (= cursor (length bits)) () "Trailing bits")
        (assert (equalp bits (encode-model expression inputs)) () "Noncanonical packet")
        (values expression inputs)))))

(defun expression-less-p (left right inputs)
  "Compare two expressions by O(1) description-size, breaking ties by canonical packet bits."
  (let ((norm-inputs (if (schema-p inputs) (schema-inputs inputs) inputs)))
    (and (not (equal left right))
         (let ((left-size (description-size left norm-inputs))
               (right-size (description-size right norm-inputs)))
           (or (< left-size right-size)
               (and (= left-size right-size)
                    (let ((left-bits (encode-model left norm-inputs))
                          (right-bits (encode-model right norm-inputs)))
                      (loop for i below (length left-bits)
                            for lb = (aref left-bits i)
                            for rb = (aref right-bits i)
                            when (/= lb rb) return (< lb rb)
                            finally (return nil)))))))))

;;; Generic Knowledge Library Serialization & Deserialization

(defun serialize-hybrid-slot (value)
  "Serialize VALUE as `(:ast ...)` when it is a valid AST node, or `(:data ...)` otherwise."
  (when value
    (if (ignore-errors (ensure-ast-meta value))
        (list :ast (ast->sexp value))
        (list :data (copy-tree value)))))

(defun deserialize-hybrid-slot (encoded)
  "Restore a value serialized by `serialize-hybrid-slot`."
  (when (consp encoded)
    (ecase (first encoded)
      (:ast (sexp->ast (second encoded)))
      (:data (copy-tree (second encoded))))))

(defun knowledge-entry->sexp (entry)
  "Serialize `knowledge-entry` ENTRY into a portable homoiconic plist S-expression."
  (list :id (knowledge-entry-id entry)
        :kind (knowledge-entry-kind entry)
        :domain (copy-tree (knowledge-entry-domain entry))
        :inputs (copy-tree (knowledge-entry-inputs entry))
        :target (copy-tree (knowledge-entry-target entry))
        :expression (ast->sexp (knowledge-entry-expression entry))
        :guard (ast->sexp (knowledge-entry-guard entry))
        :trigger (ast->sexp (knowledge-entry-trigger entry))
        :residual (serialize-hybrid-slot (knowledge-entry-residual entry))
        :auxiliary-code (ast->sexp (knowledge-entry-auxiliary-code entry))
        :status (knowledge-entry-status entry)
        :certificate (serialize-hybrid-slot (knowledge-entry-certificate entry))
        :bits (knowledge-entry-bits entry)
        :gain (knowledge-entry-gain entry)
        :work (knowledge-entry-work entry)
        :edges (copy-tree (knowledge-entry-edges entry))
        :metadata (copy-tree (knowledge-entry-metadata entry))))

(defun sexp->knowledge-entry (plist &optional (library *knowledge-library*))
  "Reconstruct a `knowledge-entry` from its `knowledge-entry->sexp` plist representation."
  (make-knowledge-entry
   :id (getf plist :id)
   :kind (getf plist :kind)
   :domain (getf plist :domain)
   :inputs (getf plist :inputs)
   :target (getf plist :target)
   :expression (sexp->ast (getf plist :expression))
   :guard (sexp->ast (getf plist :guard))
   :trigger (sexp->ast (getf plist :trigger))
   :residual (deserialize-hybrid-slot (getf plist :residual))
   :auxiliary-code (sexp->ast (getf plist :auxiliary-code))
   :status (or (getf plist :status) :empirical)
   :certificate (deserialize-hybrid-slot (getf plist :certificate))
   :bits (or (getf plist :bits) 0)
   :gain (or (getf plist :gain) 0)
   :work (or (getf plist :work) 0)
   :edges (getf plist :edges)
   :metadata (getf plist :metadata)
   :library library))

(defun serialize-knowledge-library (&optional (library *knowledge-library*))
  "Serialize LIBRARY into a self-contained homoiconic S-expression packet."
  (list :knowledge-library
        :encoding-version +encoding-version+
        :version (knowledge-library-version library)
        :function-names (copy-list (knowledge-library-function-names library))
        :de-novo-counter (knowledge-library-de-novo-counter library)
        :entry-counter (knowledge-library-entry-counter library)
        :entries (mapcar #'knowledge-entry->sexp (knowledge-library-entries library))))

(defun deserialize-knowledge-library (sexp &key (target-library nil) ledger)
  "Reconstruct a `knowledge-library` from a `serialize-knowledge-library` S-expression,
installing all entries in priority order (`:function` before `:law`, `:solver`, `:functor`, `:heuristic`)."
  (assert (and (consp sexp) (eq :knowledge-library (first sexp))))
  (let* ((plist (rest sexp))
         (enc-ver (getf plist :encoding-version))
         (lib (if target-library
                  (clear-knowledge-library target-library)
                  (make-knowledge-library)))
         (fn-names (getf plist :function-names))
         (entry-plists (getf plist :entries))
         (ordered-plists
           (stable-sort (copy-list entry-plists)
                        #'<
                        :key (lambda (ep)
                               (let ((spec (find-knowledge-kind-spec (getf ep :kind))))
                                 (if spec (knowledge-kind-spec-priority spec) 50))))))
    (assert (eql +encoding-version+ enc-ver) () "Unsupported knowledge-library encoding version ~S" enc-ver)
    (setf (knowledge-library-de-novo-counter lib) (or (getf plist :de-novo-counter) 0)
          (knowledge-library-entry-counter lib) (or (getf plist :entry-counter) 0)
          (knowledge-library-function-names lib) (copy-list fn-names))
    (flet ((populate ()
             (dolist (fn-name fn-names)
               (let ((kfn (canonical-op-name fn-name)))
                 (unless (member kfn *registered-function-names*)
                   (setf *registered-function-names* (append *registered-function-names* (list kfn))))))
             (let ((installed-by-id (make-hash-table :test #'eq)))
               (dolist (ep ordered-plists)
                 (let ((entry (sexp->knowledge-entry ep lib)))
                   (register-knowledge-entry entry :library lib :ledger ledger)
                   (setf (gethash (knowledge-entry-id entry) installed-by-id) entry)))
               ;; Preserve original chronological entry order
               (setf (knowledge-library-entries lib)
                     (loop for ep in entry-plists
                           for id = (canonical-op-name (getf ep :id))
                           for e = (gethash id installed-by-id)
                           when e collect e)))))
      (if (eq lib *knowledge-library*)
          (populate)
          (with-knowledge-library (lib)
            (populate))))
    (setf (knowledge-library-version lib) (or (getf plist :version) (knowledge-library-version lib)))
    lib))

(defun save-knowledge-library (pathname &optional (library *knowledge-library*))
  "Write LIBRARY as a canonical homoiconic S-expression file at PATHNAME."
  (with-open-file (stream pathname :direction :output :if-exists :supersede :if-does-not-exist :create)
    (with-standard-io-syntax
      (let ((*print-circle* nil)
            (*print-pretty* t))
        (prin1 (serialize-knowledge-library library) stream)
        (terpri stream))))
  pathname)

(defun load-knowledge-library (pathname &key (library *knowledge-library*) target-library ledger)
  "Load a `knowledge-library` saved by `save-knowledge-library` from PATHNAME."
  (with-open-file (stream pathname :direction :input)
    (with-standard-io-syntax
      (let ((sexp (read stream nil nil)))
        (deserialize-knowledge-library sexp
                                       :target-library (or target-library library)
                                       :ledger ledger)))))
