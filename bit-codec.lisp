(in-package #:lisploop)

;;; Encoding v2. A packet contains its version, ordered input schema, result type,
;;; profile bit, and a prefix-coded tree. No host pointers or free context.
;;; Positive integers use delta coding: gamma(bit-length), then the low bits.
(defun delta-size (positive)
  (assert (and (integerp positive) (plusp positive)))
  (let ((width (integer-length positive)))
    (+ width (* 2 (1- (integer-length width))))))

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
    (:int (funcall emit 3 0)) (:bool (funcall emit 3 1)) (:index (funcall emit 3 2))
    (otherwise
     (ecase (first type)
       (:gf (funcall emit 3 3) (emit-positive (second type) emit))
       (:tuple (funcall emit 3 4) (emit-positive (length type) emit)
               (dolist (part (rest type)) (emit-bit-type part emit)))
       (:seq (funcall emit 3 5) (emit-bit-type (second type) emit))))))

(defun emit-bit-value (value type emit)
  (case type
    (:int (emit-positive (signed-code value) emit))
    (:index (emit-positive (1+ value) emit))
    (:bool (funcall emit 1 (if value 1 0)))
    (otherwise
     (ecase (first type)
       (:gf (funcall emit (integer-length (1- (second type))) value))
       (:tuple (loop for item in value for part in (rest type) do (emit-bit-value item part emit)))
       (:seq (emit-positive (1+ (length value)) emit)
             (dolist (item value) (emit-bit-value item (second type) emit)))))))

(defun arithmetic-tree-p (expression type)
  (and (or (eq type :int) (and (consp type) (eq (first type) :gf)))
       (case (first expression)
         (:lit (equal (second expression) type))
         (:var (equal (third expression) type))
         (:app (and (member (second (second expression)) '(:+ :*))
                    (equal (third (second expression)) type)
                    (every (lambda (child) (arithmetic-tree-p child type)) (third expression)))))))

(defun emit-bit-header (inputs type arithmetic-p emit)
  (emit-positive 2 emit)
  (emit-positive (1+ (length inputs)) emit)
  (dolist (input inputs)
    (emit-positive (1+ (car input)) emit)
    (emit-bit-type (cdr input) emit))
  (emit-bit-type type emit)
  (funcall emit 1 (if arithmetic-p 0 1)))

(defun bit-header-size (inputs type &optional (arithmetic-p t))
  (let ((size 0))
    (emit-bit-header inputs type arithmetic-p (lambda (width value) (declare (ignore value)) (incf size width)))
    size))

(defun emit-bit-expression (expression inputs type arithmetic-p emit)
  (let* ((tag (first expression))
         (name (when (eq tag :app) (second (second expression))))
         (code (cond ((eq tag :var) 0) ((eq tag :lit) 1)
                     (t (or (position name '(:+ :* := :tuple :member :lookup :gather))
                            (error "Unsupported bit-codec node ~S" expression)))))
         (node-code (if (eq tag :app) (+ 2 code) code)))
    (funcall emit (if arithmetic-p 2 3) (min 7 node-code))
    (when (>= node-code 7) (funcall emit 1 (- node-code 7)))
    (case tag
      (:var (funcall emit (integer-length (max 0 (1- (length inputs))))
                     (or (position (second expression) inputs :key #'car) (error "Undeclared variable"))))
      (:lit (emit-bit-value (third expression) type emit))
      (:app
       (let* ((operator (second expression)) (operand-type (third operator)))
         ;; These result types do not determine all operand types.
         (case name
           ((:= :member) (emit-bit-type operand-type emit))
           (:lookup (emit-bit-type (second operand-type) emit)))
         (loop for child in (third expression)
               for child-type in (second (operator-type operator)) do
                 (emit-bit-expression child inputs child-type arithmetic-p emit)))))))

(defun emit-bit-model (expression inputs emit)
  (assert (= (length inputs) (length (remove-duplicates inputs :key #'car))))
  (dolist (input inputs) (var (car input) (cdr input)))
  (let* ((type (expression-type expression inputs))
         (arithmetic-p (arithmetic-tree-p expression type)))
    (emit-bit-header inputs type arithmetic-p emit)
    (emit-bit-expression expression inputs type arithmetic-p emit)))

(defun bit-description-size (expression inputs)
  "Exact packet length in bits, including the schema; same emitter as the codec."
  (let ((size 0))
    (emit-bit-model expression inputs (lambda (width value) (declare (ignore value)) (incf size width)))
    size))

(defun encode-bit-model (expression inputs)
  (let ((bits (make-array 0 :element-type 'bit :adjustable t :fill-pointer 0)))
    (emit-bit-model expression inputs
                    (lambda (width value)
                      (loop for index downfrom (1- width) to 0 do
                        (vector-push-extend (ldb (byte 1 index) value) bits))))
    bits))

(defun decode-bit-model (bits)
  "Decode a standalone v2 packet; return expression and declared input schema.
Reject truncation, trailing bits, unused codes and noncanonical profile choices."
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
             (read-type ()
               (ecase (take-bits 3)
                 (0 :int) (1 :bool) (2 :index) (3 (gf (positive)))
                 (4 (let ((arity (1- (positive))))
                      (assert (<= arity (- (length bits) cursor)))
                      (cons :tuple (loop repeat arity collect (read-type)))))
                 (5 (sequence-type (read-type)))))
             (read-value (type)
               (case type
                 (:int (decode-signed-code (positive))) (:index (1- (positive))) (:bool (= 1 (take-bits 1)))
                 (otherwise
                  (ecase (first type)
                    (:gf (let ((value (take-bits (integer-length (1- (second type))))))
                           (assert (< value (second type))) value))
                    (:tuple (mapcar #'read-value (rest type)))
                    (:seq (loop repeat (1- (positive)) collect (read-value (second type))))))))
             (read-expression (inputs type arithmetic-p)
               (let ((code (take-bits (if arithmetic-p 2 3))))
                 (when (= code 7) (incf code (take-bits 1)))
                 (case code
                   (0 (let* ((slot (take-bits (integer-length (max 0 (1- (length inputs))))))
                             (input (nth slot inputs)))
                        (assert (and input (equal type (cdr input)))) (var (car input) type)))
                   (1 (lit type (read-value type)))
                   (otherwise
                    (let* ((name (nth (- code 2) '(:+ :* := :tuple :member :lookup :gather)))
                           (operand-type (case name
                                           ((:= :member) (read-type))
                                           (:lookup (tuple-type (read-type) type))
                                           (:gather (assert (eq (first type) :seq)) (second type))
                                           (otherwise type)))
                           (operator (op name operand-type)))
                      (assert (equal type (third (operator-type operator))))
                      (apply #'app operator
                             (mapcar (lambda (child-type) (read-expression inputs child-type arithmetic-p))
                                     (second (operator-type operator))))))))))
      (assert (= 2 (positive)) () "Unsupported encoding version")
      (let* ((count (1- (positive)))
             (inputs (progn (assert (<= count (- (length bits) cursor)))
                            (loop repeat count collect (cons (1- (positive)) (read-type)))))
             (type (read-type)) (arithmetic-p (zerop (take-bits 1)))
             (expression (read-expression inputs type arithmetic-p)))
        (assert (= cursor (length bits)) () "Trailing bits")
        (assert (equalp bits (encode-bit-model expression inputs)) () "Noncanonical bit packet")
        (values expression inputs)))))
