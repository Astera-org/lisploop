(in-package #:lisploop)

;;; One fixed encoding. A packet contains its version, input schema, result type,
;;; and a prefix-coded tree. Text formatting has no role in size or work charges.
;;; Positive integers use delta coding: gamma(bit-length), then the low bits.
(defconstant +encoding-version+ 7)
(defconstant +opcode-width+ 4)
(defparameter +operator-names+
  (append '(:+ :* := :tuple :member :lookup :gather :- :/ :if :concat) *symbolic-primitives*))

(defun emit-operator-name (name emit)
  (let ((index (or (position name +operator-names+) (error "Unknown operator ~S" name))))
    (funcall emit +opcode-width+ (min 15 index))
    (when (>= index 15) (emit-positive (- index 14) emit))))

(defun emit-operator (operator emit)
  (destructuring-bind (tag name type) operator
    (declare (ignore tag))
    (emit-operator-name name emit)
    (case name
      ((:= :member) (emit-bit-type type emit))
      (:lookup (emit-bit-type (second type) emit))
      (otherwise (when (member name *symbolic-primitives*) (emit-bit-type type emit))))))

(defun application-overhead (operator)
  (let ((size 2))
    (emit-operator operator (lambda (width value) (declare (ignore value)) (incf size width)))
    size))

(defun emit-positive (value emit)
  (let* ((width (integer-length value)) (length-width (integer-length width)))
    (assert (plusp value))
    (funcall emit (1- length-width) 0)
    (funcall emit length-width width)
    (funcall emit (1- width) (ldb (byte (1- width) 0) value))))

(defun signed-code (value) (if (minusp value) (* -2 value) (1+ (* 2 value))))
(defun decode-signed-code (value) (if (oddp value) (/ (1- value) 2) (- (/ value 2))))

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
                  (progn (emit-operator-name (second value) emit) (emit-bit-type (third value) emit))
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
  (let ((size 0))
    (emit-bit-header inputs type (lambda (width value) (declare (ignore value)) (incf size width)))
    size))

(defun emit-bit-expression (expression inputs type emit)
  (let ((tag (first expression)))
    (funcall emit 2 (ecase tag (:var 0) (:lit 1) (:app 2)))
    (ecase tag
      (:var (funcall emit (integer-length (max 0 (1- (length inputs))))
                     (or (position (second expression) inputs :key #'car) (error "Undeclared variable"))))
      (:lit (emit-bit-value (third expression) type emit))
      (:app
       (let ((operator (second expression)))
         (emit-operator operator emit)
         (loop for child in (third expression)
               for child-type in (second (operator-type operator)) do
                 (emit-bit-expression child inputs child-type emit)))))))

(defun emit-bit-model (expression inputs emit)
  (assert (valid-inputs-p inputs))
  (let ((type (expression-type expression inputs)))
    (emit-bit-header inputs type emit)
    (emit-bit-expression expression inputs type emit)))

(defun body-size (expression inputs)
  "Expression bits conditional on a declared schema; used by the enumerator."
  (let ((size 0))
    (emit-bit-expression expression inputs (expression-type expression inputs)
                         (lambda (width value) (declare (ignore value)) (incf size width)))
    size))

(defun description-size (expression &optional inputs)
  "Exact packet length in bits, including the schema; same emitter as the codec."
  (let ((size 0))
    (emit-bit-model expression inputs (lambda (width value) (declare (ignore value)) (incf size width)))
    size))

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
                 (dotimes (i width value) (setf value (+ (* 2 value) (aref bits cursor))) (incf cursor))))
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
                 (or (nth index +operator-names+) (error "Unused operator code"))))
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
                        (assert (and input (equal type (cdr input)))) (var (car input) type)))
                   (1 (lit type (read-value type)))
                   (2
                    (let* ((name (read-operator-name))
                           (operand-type (case name
                                           ((:= :member) (read-type))
                                           (:lookup (tuple-type (read-type) type))
                                           ((:gather :concat) (assert (eq (first type) :seq)) (second type))
                                           (otherwise (if (member name *symbolic-primitives*) (read-type) type))))
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
