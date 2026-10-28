(in-package #:lisploop)

(defun check-codec-roundtrip (expression inputs)
  (let ((bits (encode-model expression inputs)))
    (check (= (length bits) (description-size expression inputs)))
    (multiple-value-bind (decoded schema) (decode-model bits)
      (check (equal expression decoded)) (check (equal inputs schema)))
    (raises (decode-model (subseq bits 0 (1- (length bits)))))
    (raises (decode-model (concatenate 'bit-vector bits #*0)))))

(deftest codec-roundtrip-and-boundaries
  (let* ((inputs '((0 . :int) (1 . :int))) (a (var 0 :int)) (b (var 1 :int)))
    (check (= 23 (header-size inputs :int)))
    (check (= 35 (description-size (app (op :+ :int) a b) inputs)))
    (check (equalp #*100000000001 (subseq (encode-model (app (op :+ :int) a b) inputs) 23)))
    (loop for n in '(0 1 -1 2 -2 3 -3 4 -4) for size in '(3 6 6 7 7 7 7 10 10) do
      (check (= size (- (description-size (lit :int n) inputs) 23))))
    (dolist (n (append '(0 -1 1) (loop for width in '(7 8 31 32 256 257) append
                                 (list (1- (ash 1 width)) (ash 1 width) (- (ash 1 width))))))
      (check-codec-roundtrip (lit :int n) inputs))
    (dolist (expression (list a (app (op :+ :int) a b) (app (op := :int) a b)
                              (app (op :member :int) a (lit (sequence-type :int) '(-1 0 1)))
                              (app (op :tuple (tuple-type :int :bool)) a (lit :bool nil))
                              (app (op :gather :int) (lit (sequence-type :int) '(4 5 6))
                                   (lit (sequence-type :index) '(2 0 2)))
                              (lit (tuple-type (tuple-type) (sequence-type :bool)) '(nil (t nil)))))
      (check-codec-roundtrip expression inputs)))
  (multiple-value-bind (frame oracle) (gf5-fixture)
    (check-codec-roundtrip oracle (schema-inputs (frame-schema frame)))
    (check-codec-roundtrip (lookup-model frame) (schema-inputs (frame-schema frame))))
  (dolist (prime '(2 5 7 257))
    (check-codec-roundtrip (lit (gf prime) (1- prime)) nil))
  (check-codec-roundtrip (var 99 :int) '((99 . :int)))
  (raises (decode-model #*))
  ;; Reserved expression tag and a retired packet version must be rejected.
  (let* ((bits (encode-model (lit :int 0) nil)) (header (header-size nil :int)))
    (setf (subseq bits header (+ header 2)) #*11)
    (raises (decode-model bits)))
  (let ((bits (encode-model (lit :int 0))))
    (setf (aref bits 0) 1)
    (raises (decode-model bits)))
  ;; Three GF(5) payload bits have unused values 5..7.
  (let ((bits (encode-model (lit (gf 5) 0) nil)))
    (setf (subseq bits (- (length bits) 3)) #*111)
    (raises (decode-model bits))))

(defun reference-node-trees (leaves operators applications)
  "Enumerate by application count, independently of the size-indexed search."
  (if (zerop applications) leaves
      (loop for left-count below applications append
        (loop for left in (reference-node-trees leaves operators left-count) append
          (loop for right in (reference-node-trees leaves operators (- applications 1 left-count)) append
            (loop for operator in operators collect (app operator left right)))))))

(deftest codec-enumerator-complete-tiny-grammars
  (dolist (domain (list :int (gf 2) (gf 5)))
    (let* ((inputs (list (cons 0 domain) (cons 1 domain)))
           (language (make-language domain inputs))
           (bound (+ (header-size inputs domain) (if (eq domain :int) 12 23)))
           (leaves (append (list (var 0 domain) (var 1 domain))
                           (loop for n from (if (eq domain :int) -31 0)
                                 to (if (eq domain :int) 31 (1- (second domain))) collect (lit domain n))))
           (reference (remove-if (lambda (expression) (> (description-size expression inputs) bound))
                                  (loop for count from 0 to (if (eq domain :int) 1 2) append
                                    (reference-node-trees leaves (language-operators language) count))))
           (frame (probe-frame domain inputs '((0 0) (0 1) (1 0) (1 1))))
           (job (start-observation-search (make-observation-scope frame language))))
      (check (eq :bounded-exhaustion (message-claim (resume-observation-search job bound 1000000))))
      (check (= (length reference) (length (observation-job-records job))))
      (check (null (set-exclusive-or reference
                                     (mapcar #'observed-expression-expression (observation-job-records job))
                                     :test #'equal)))
      (dolist (expression reference)
        (check-codec-roundtrip expression inputs)
        (check (equal (observed-expression-values (find-observation job expression))
                       (loop for row in (frame-rows frame) collect
                         (if (eq domain :int)
                             (integer-reference-value expression (mapcar #'cons '(0 1) (row-known row)))
                             (reference-value expression (mapcar #'cons '(0 1) (row-known row))
                                              (second domain)))))))
      (when (eq domain :int) (check (= 83 (length reference)))))))

(deftest codec-literal-ranges-and-vocabulary
  (let ((header (header-size nil :int)))
    ;; All magnitudes with <= 10 bits; include code-length gaps and sign boundaries.
    (loop for payload from 1 to 16 do
      (let ((expected (loop for n from -511 to 511
                            when (= (+ header 2 payload) (length (encode-model (lit :int n) nil))) collect n))
            (actual nil))
        (dotimes (pass 2)
          (multiple-value-bind (lo hi) (literal-range :int (+ 2 payload) pass)
            (loop for n from lo to hi do (push (if (= pass 1) (- n) n) actual))))
        (check (equal (sort actual #'<) expected)))))
  (let* ((language (make-language :int nil :operators nil :literals '(0 -1 1)))
         (job (start-observation-search (make-observation-scope (probe-frame :int nil '(nil)) language)))
         (bound (description-size (lit :int 1))))
    (resume-observation-search job (1- bound) 100000)
    (check (= 1 (length (observation-job-records job))))
    (resume-observation-search job bound 100000)
    (check (= 3 (length (observation-job-records job))))))

(deftest structural-tariff-and-print-independence
  (let* ((value (ash 1 256))
         (expression (app (op :* :int) (lit :int value) (lit :int value)))
         (size (description-size expression)) (work (syntax-work expression))
         (run (evaluate expression nil nil)))
    (check (= 259 (value-work value :int))) ; visit, sign, 257 magnitude bits
    (check (= (* 257 257) (arithmetic-cost :* :int (list value value))))
    (let ((*print-base* 2) (*print-pretty* t) (*print-case* :downcase))
      (check (= size (description-size expression)))
      (check (= work (syntax-work expression)))
      (check (equalp run (evaluate expression nil nil)))))
  ;; A compact description of many empty tuples still incurs work for each visit.
  (let* ((type (sequence-type (tuple-type)))
         (few (lit type (list nil))) (many (lit type (make-list 100))))
    (check (< (- (description-size many) (description-size few))
               (- (syntax-work many) (syntax-work few))))
    (check (= 101 (value-work (third many) type))))
  (let ((expression (lit :int 0)))
    (check (= 9 (evaluation-work (evaluate expression nil nil))))))

(deftest schema-header-does-not-add-enumeration-work
  (let ((counts nil))
    (dolist (ids '((0 1) (1000000 1000001)))
      (let* ((inputs (mapcar (lambda (id) (cons id :int)) ids))
             (language (make-language :int inputs))
             (scope (make-observation-scope (probe-frame :int inputs '((0 1))) language))
             (job (start-observation-search scope))
             (header (header-size inputs :int)))
        (let ((message (resume-observation-search job header 0)))
          (check (eq :bounded-exhaustion (message-claim message)))
          (check (= +encoding-version+ (getf (message-evidence message) :encoding-version)))
          (check (= +tariff-version+ (getf (message-evidence message) :tariff-version))))
        (check (null (observation-job-records job)))
        (resume-observation-search job (+ header 12) 100000)
        (check (= 83 (length (observation-job-records job))))
        (push (cdr (assoc :enumeration (ledger-counts (observation-job-ledger job)))) counts)))
    (check (= (first counts) (second counts)))))

