(in-package #:lisploop)

(defstruct (language (:constructor %make-language))
  domain inputs operators (literals :all) constants (version 3))

(defun make-language (domain inputs &key (operators (list (op :+ domain) (op :* domain)))
                                        (literals :all) constants)
  "Finite typed productions over the VM's primitives, including quoted syntax.
LITERALS defaults to :ALL, or declares a finite vocabulary without bounding values.
CONSTANTS supplies additional typed literal ASTs. The default operators stay +/*."
  (assert (or (eq domain :int) (and (consp domain) (eq (first domain) :gf))))
  (assert (valid-inputs-p inputs))
  (mapc #'operator-type operators)
  (dolist (constant constants)
    (assert (eq :lit (first constant)))
    (expression-type constant nil))
  (assert (or (eq literals :all)
              (and (listp literals) (every (lambda (value) (value-p value domain)) literals))))
  (%make-language :domain (copy-tree domain) :inputs (copy-tree inputs)
                  :operators (remove-duplicates (copy-tree operators) :test #'equal)
                  :constants (remove-duplicates (copy-tree constants) :test #'equal)
                  :literals (if (eq literals :all) :all
                                (remove-duplicates (copy-list literals) :from-end t))))

(defun snapshot-language (language)
  (let ((snapshot (copy-language language)))
    (setf (language-domain snapshot) (copy-tree (language-domain language))
          (language-inputs snapshot) (copy-tree (language-inputs language))
          (language-operators snapshot) (copy-tree (language-operators language))
          (language-literals snapshot) (copy-tree (language-literals language))
          (language-constants snapshot) (copy-tree (language-constants language)))
    snapshot))

(defun language-header-size (language &optional (target (language-domain language)))
  (header-size (language-inputs language) target))

(defun language-booleans-p (language)
  (or (find :bool (language-inputs language) :key #'cdr)
      (some (lambda (operator)
              (member :bool (cons (third (operator-type operator))
                                 (second (operator-type operator)))))
            (language-operators language))))

(defstruct (enumerator (:constructor make-enumerator (language)))
  language (size 1) (phase :variables) (cursor 0) (literal-pass 0) (literal-index 0)
  literal-next literal-end (boolean-index 0) (constant-index 0) (operator-index 0) sizes indices
  (buckets (make-hash-table :test #'equal)))

(defun syntax-bucket (enumerator type size)
  (gethash (list type size) (enumerator-buckets enumerator)))

(defun index-expression (enumerator expression)
  (let* ((language (enumerator-language enumerator))
         (type (expression-type expression (language-inputs language)))
         (key (list type (enumerator-size enumerator)))
         (buckets (enumerator-buckets enumerator)))
    (assert (= (enumerator-size enumerator) (body-size expression (language-inputs language))))
    (unless (gethash key buckets)
      (setf (gethash key buckets) (make-array 0 :adjustable t :fill-pointer 0)))
    (vector-push-extend expression (gethash key buckets))
    type))

(defun literal-range (domain size pass)
  "Exact body-bit intervals, without visiting integers outside the current bound."
  (let ((payload (- size 2)))
    (if (eq domain :int)
        (let ((width (loop for width from 1 to payload
                          when (= payload (+ width (* 2 (1- (integer-length width))))) return width)))
          (if (null width) (values 1 0)
              (let ((lo (ash 1 (1- width))) (hi (1- (ash 1 width))))
                (if (= pass 0)
                    (values (ceiling (1- lo) 2) (floor (1- hi) 2))
                    (values (max 1 (ceiling lo 2)) (floor hi 2))))))
        (if (and (= pass 0) (= payload (integer-length (1- (second domain)))))
            (values 0 (1- (second domain))) (values 1 0)))))

(defun reset-enumerator-bound (enumerator)
  (incf (enumerator-size enumerator))
  (setf (enumerator-phase enumerator) :variables
        (enumerator-cursor enumerator) 0
        (enumerator-literal-pass enumerator) 0
        (enumerator-literal-index enumerator) 0
        (enumerator-literal-next enumerator) nil
        (enumerator-operator-index enumerator) 0
        (enumerator-boolean-index enumerator) 0
        (enumerator-constant-index enumerator) 0
        (enumerator-sizes enumerator) nil
        (enumerator-indices enumerator) nil))

(defun first-composition (total arity)
  (when (>= total arity)
    (append (make-list (1- arity) :initial-element 1) (list (- total (1- arity))))))

(defun next-composition (sizes)
  "Next positive composition of the same total, in lexicographic order."
  (loop for i downfrom (- (length sizes) 2) to 0
        for tail = (nthcdr (1+ i) sizes)
        for total = (reduce #'+ tail)
        when (> total (length tail)) do
          (return (append (subseq sizes 0 i) (list (1+ (nth i sizes)))
                          (make-list (1- (length tail)) :initial-element 1)
                          (list (- total (length tail)))))))

(defun advance-application-cursor (enumerator buckets)
  (let ((indices (enumerator-indices enumerator)))
    (loop for i downfrom (1- (length indices)) to 0 do
      (incf (nth i indices))
      (when (< (nth i indices) (length (nth i buckets))) (return-from advance-application-cursor))
      (setf (nth i indices) 0)))
  (setf (enumerator-sizes enumerator) (next-composition (enumerator-sizes enumerator)))
  (unless (enumerator-sizes enumerator) (incf (enumerator-operator-index enumerator))))

(defun enumeration-step (enumerator)
  "One cursor operation; return (candidate, event). No eager Cartesian products."
  (let* ((language (enumerator-language enumerator))
         (size (enumerator-size enumerator)))
    (ecase (enumerator-phase enumerator)
      (:variables
       (let ((input (nth (enumerator-cursor enumerator) (language-inputs language))))
         (if input
             (progn
               (incf (enumerator-cursor enumerator))
               (let ((expression (var (car input) (cdr input))))
                 (when (= size (body-size expression (language-inputs language)))
                   (return-from enumeration-step (values expression :candidate)))))
             (setf (enumerator-phase enumerator) :literals))))
      (:literals
       (unless (eq (language-literals language) :all)
         (let ((tail (nthcdr (enumerator-literal-index enumerator) (language-literals language))))
           (if tail
               (let ((expression (lit (language-domain language) (first tail))))
                 (incf (enumerator-literal-index enumerator))
                 (when (= size (body-size expression (language-inputs language)))
                   (return-from enumeration-step (values expression :candidate))))
               (setf (enumerator-phase enumerator) :booleans)))
         (return-from enumeration-step (values nil :progress)))
       (if (>= (enumerator-literal-pass enumerator) 2)
           (setf (enumerator-phase enumerator) :booleans)
           (progn
             (unless (enumerator-literal-next enumerator)
               (multiple-value-bind (lo hi)
                   (literal-range (language-domain language) size (enumerator-literal-pass enumerator))
                 (setf (enumerator-literal-next enumerator) lo
                       (enumerator-literal-end enumerator) hi)))
             (if (> (enumerator-literal-next enumerator) (enumerator-literal-end enumerator))
                 (setf (enumerator-literal-next enumerator) nil
                       (enumerator-literal-pass enumerator) (1+ (enumerator-literal-pass enumerator)))
                 (let ((value (enumerator-literal-next enumerator)))
                   (incf (enumerator-literal-next enumerator))
                   (return-from enumeration-step
                     (values (lit (language-domain language)
                                  (if (= 1 (enumerator-literal-pass enumerator)) (- value) value))
                             :candidate)))))))
      (:booleans
       (if (and (= size 3) (language-booleans-p language)
                (< (enumerator-boolean-index enumerator) 2))
           (return-from enumeration-step
             (values (lit :bool (= 1 (prog1 (enumerator-boolean-index enumerator)
                                      (incf (enumerator-boolean-index enumerator))))) :candidate))
           (setf (enumerator-phase enumerator) (if (language-constants language) :constants :applications))))
      (:constants
       (let ((constant (nth (enumerator-constant-index enumerator) (language-constants language))))
         (if constant
             (progn (incf (enumerator-constant-index enumerator))
                    (when (and (= size (body-size constant (language-inputs language)))
                               ;; Numeric/Boolean vocabulary may already emit it.
                               (not (and (equal (second constant) (language-domain language))
                                         (or (eq :all (language-literals language))
                                             (member (third constant) (language-literals language)))))
                               (not (and (eq :bool (second constant)) (language-booleans-p language))))
                      (return-from enumeration-step (values constant :candidate))))
             (setf (enumerator-phase enumerator) :applications))))
      (:applications
       (let ((operator (nth (enumerator-operator-index enumerator) (language-operators language))))
         (if (null operator)
             (setf (enumerator-phase enumerator) :finish)
             (let ((types (second (operator-type operator))))
               (when (null types)
                 (incf (enumerator-operator-index enumerator))
                 (return-from enumeration-step
                   (if (= size (application-overhead operator)) (values (app operator) :candidate)
                       (values nil :progress))))
               (unless (enumerator-sizes enumerator)
                 (setf (enumerator-sizes enumerator)
                       (first-composition (- size (application-overhead operator)) (length types))
                       (enumerator-indices enumerator) (make-list (length types) :initial-element 0)))
               (if (null (enumerator-sizes enumerator))
                   (incf (enumerator-operator-index enumerator))
                   (let ((buckets (mapcar (lambda (type bits) (syntax-bucket enumerator type bits))
                                          types (enumerator-sizes enumerator))))
                     (if (some #'null buckets)
                         (progn
                           (setf (enumerator-sizes enumerator)
                                 (next-composition (enumerator-sizes enumerator)))
                           (unless (enumerator-sizes enumerator)
                             (incf (enumerator-operator-index enumerator))))
                         (let ((expression (apply #'app operator
                                                  (mapcar #'aref buckets (enumerator-indices enumerator)))))
                           (advance-application-cursor enumerator buckets)
                           (return-from enumeration-step (values expression :candidate))))))))))
      (:finish
       (reset-enumerator-bound enumerator)
       (return-from enumeration-step (values nil :bound))))
    (values nil :progress)))

