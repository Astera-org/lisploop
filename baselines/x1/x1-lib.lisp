;;; x1-lib.lisp -- helpers for recording the X1 baseline on the v1 kernel.
;;; Loaded after the kernel copy's load.lisp. Nothing here changes kernel behaviour: it only
;;; calls the kernel's own entry points and reads the structures they leave behind.
(in-package #:lisploop)

(defparameter *x1-out* (or (sb-ext:posix-getenv "X1_OUT") (error "X1_OUT is not set")))

(defun out-path (name) (concatenate 'string *x1-out* "/" name))

(defun short (ast)
  "Print a term in the surface syntax that the kernel's `term` reader accepts: lower-case
operator names, variables as x<id>, literals as bare values."
  (labels ((p (x)
             (ecase (ast-kind x)
               (:var (format nil "x~D" (ast-id x)))
               (:lit (format nil "~S" (ast-value x)))
               (:app (format nil "(~(~A~)~{ ~A~})" (operator-name (first x)) (mapcar #'p (rest x)))))))
    (p ast)))

(defun law-line (law)
  "(= LHS RHS) for a proposed law. LHS is the later member, RHS the class representative."
  (let ((e (knowledge-entry-expression law)))
    (format nil "(= ~A ~A)" (short (second e)) (short (third e)))))

(defun count-apps (e) (if (app-p e) (1+ (reduce #'+ (rest e) :key #'count-apps)) 0))
(defun count-nodes (e) (if (app-p e) (1+ (reduce #'+ (rest e) :key #'count-nodes)) 1))
(defun count-leaves (e) (if (app-p e) (reduce #'+ (rest e) :key #'count-leaves) 1))

(defun all-rows (inputs)
  "Every assignment to INPUTS, in the order an exhaustive validation visits them."
  (loop for i below (finite-type-cardinality (inputs-tuple-type inputs))
        collect (law-assignment inputs i)))

(defun make-inputs (nvars domain) (loop for i below nvars collect (cons i domain)))

(defun make-obs (domain inputs ops literals)
  "The observation job that bootstrap/build-batteries.lisp:127-146 builds for this grammar."
  (start-observation-search
   (make-observation-scope (probe-frame domain inputs (all-rows inputs))
                           (make-language domain inputs
                                          :operators (mapcar (lambda (n) (op n domain)) ops)
                                          :literals literals))))

(defun enumerator-tree-count (enumerator)
  (loop for v being the hash-values of (enumerator-buckets enumerator) sum (length v)))

(defun live-bytes ()
  (sb-ext:gc :full t) (sb-ext:gc :full t)
  (sb-kernel:dynamic-usage))

(defvar *held* nil "Keeps the measured job reachable while live bytes are read.")

(defun ledger-alist (ledger)
  (sort (copy-alist (ledger-counts ledger)) #'string< :key (lambda (c) (symbol-name (car c)))))

(defun now-ns ()
  "Monotonic clock in nanoseconds. `get-internal-real-time` ticks every 4 ms on this host."
  (multiple-value-bind (s ns) (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ (* s 1000000000) ns)))

(defun wall-us (t0 t1) (round (- t1 t0) 1000))

(defun file-tag (name)
  "NAME with the characters a file name cannot carry spelled out."
  (with-output-to-string (s)
    (loop for ch across name
          do (case ch (#\+ (write-string "plus" s)) (#\* (write-string "times" s))
               (#\@ (write-string "-at-" s)) (t (write-char ch s))))))

(defstruct x1-result
  name job message laws rows inputs domain slack bound work-limit wall-us)

(defun run-config (name nvars ops literals slack work-limit &key (p 3))
  "Run one observation job to SLACK body bits or WORK-LIMIT ledger units, whichever first."
  (let* ((domain (gf p))
         (inputs (make-inputs nvars domain))
         (bound (header-bound inputs domain slack)))
    (clrhash *closures*)
    (let* ((job (make-obs domain inputs ops literals))
           (t0 (now-ns))
           (msg (resume-observation-search job bound work-limit))
           (t1 (now-ns))
           (laws (propose-observed-laws job)))
      (make-x1-result :name name :job job :message msg :laws laws
                      :rows (all-rows inputs) :inputs inputs :domain domain
                      :slack slack :bound bound :work-limit work-limit
                      :wall-us (wall-us t0 t1)))))

(defun report-result (r &optional (stream t))
  (let* ((job (x1-result-job r))
         (records (observation-job-records job))
         (buckets (observation-job-buckets job))
         (nrows (length (x1-result-rows r)))
         (ledger (observation-job-ledger job))
         (complete (remove :complete records :key #'observed-expression-status :test-not #'eq))
         (apps (reduce #'+ complete :key (lambda (x) (count-apps (observed-expression-expression x)))))
         (nodes (reduce #'+ complete :key (lambda (x) (count-nodes (observed-expression-expression x)))))
         (nonleaf (count-if (lambda (x) (app-p (observed-expression-expression x))) complete))
         (trees (enumerator-tree-count (observation-job-enumerator job)))
         (by-leaves (let ((h nil))
                      (dolist (x complete)
                        (let* ((k (count-leaves (observed-expression-expression x)))
                               (e (assoc k h)))
                          (if e (incf (cdr e)) (push (cons k 1) h))))
                      (sort h #'< :key #'car))))
    (format stream "~&[~A] field=~S vars=~D rows=~D slack=~D header=~D bound=~D work-limit=~D~%"
            (x1-result-name r) (x1-result-domain r) (length (x1-result-inputs r)) nrows
            (x1-result-slack r) (header-size (x1-result-inputs r) (x1-result-domain r))
            (x1-result-bound r) (x1-result-work-limit r))
    (format stream "   claim=~S completed-bound=~D work=~D wall-us=~D~%"
            (message-claim (x1-result-message r))
            (getf (message-evidence (x1-result-message r)) :completed-bound)
            (ledger-total ledger) (x1-result-wall-us r))
    (format stream "   ledger-by-category=~S~%" (ledger-alist ledger))
    (format stream "   records=~D complete=~D classes=~D multi-member-classes=~D equations=~D trees-kept-by-enumerator=~D~%"
            (length records) (length complete) (length buckets)
            (count-if (lambda (b) (rest (observation-bucket-members b))) buckets)
            (length (x1-result-laws r)) trees)
    (format stream "   complete-by-leaf-count=~S~%" by-leaves)
    (format stream "   cells: operator-applications=~D x rows=~D ; nodes x rows=~D ; nonleaf-trees x rows=~D ; trees x rows=~D~%"
            apps (* apps nrows) (* nodes nrows) (* nonleaf nrows) (* (length complete) nrows))
    (format stream "   work/(tree*row)=~,2F work/(operator-application*row)=~,2F~%"
            (/ (ledger-total ledger) (max 1 (* (length complete) nrows)) 1.0)
            (/ (ledger-total ledger) (max 1 (* apps nrows)) 1.0))
    ;; Retained memory is measured by x1-memory.lisp, one fresh process per configuration:
    ;; inside this long-running process the reading is dominated by earlier sections.
    r))

(defun bucket-list (job)
  "Classes in order of creation, each with members in order of observation."
  (mapcar (lambda (b) (cons b (reverse (observation-bucket-members b))))
          (reverse (observation-job-buckets job))))

(defun write-lines (path lines)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (dolist (line lines) (write-line line s)))
  (length lines))

(defun write-classes (r path &key (append nil) (max-members nil))
  "One line per class: job, index, member count, value vector, representative, then members."
  (with-open-file (s path :direction :output :if-exists (if append :append :supersede)
                          :if-does-not-exist :create)
    (format s "# job ~A: ~D classes over ~D rows; row i assigns x_j = floor(i / 3^j) mod 3~%"
            (x1-result-name r) (length (observation-job-buckets (x1-result-job r)))
            (length (x1-result-rows r)))
    (format s "# columns: job <tab> class-index <tab> member-count <tab> values-on-rows <tab> representative <tab> members-in-observation-order~%")
    (loop for (bucket . members) in (bucket-list (x1-result-job r))
          for i from 0
          do (format s "~A~C~D~C~D~C~{~D~}~C~A~C~{~A~^ ~}~%"
                     (x1-result-name r) #\Tab i #\Tab (length members) #\Tab
                     (observation-bucket-values bucket) #\Tab
                     (short (observed-expression-expression (first members))) #\Tab
                     (mapcar (lambda (m) (short (observed-expression-expression m)))
                             (if max-members
                                 (subseq members 0 (min max-members (length members)))
                                 members))))))

(defun equation-lines (r) (mapcar #'law-line (x1-result-laws r)))

(defun sorted (lines) (sort (copy-list lines) #'string<))

(defun record-thresholds (nvars ops literals slack &key (p 3))
  "Ledger total at the moment each record is finished, in an uncut run to SLACK body bits.
A run cut at work limit L has finished exactly the records whose threshold is <= L."
  (let* ((domain (gf p))
         (inputs (make-inputs nvars domain))
         (bound (header-bound inputs domain slack))
         (job (make-obs domain inputs ops literals))
         (n 0) (out nil))
    (loop until (observation-bound-complete-p job bound)
          do (observation-step job most-positive-fixnum)
             (let ((m (length (observation-job-records job))))
               (when (> m n)
                 (setf n m)
                 (push (cons (ledger-total (observation-job-ledger job))
                             (observed-expression-expression (first (observation-job-records job))))
                       out))))
    (values (nreverse out) (ledger-total (observation-job-ledger job)))))

(defun certify-all (laws &optional (limit 100000))
  "Exhaustive validation of every law, as bootstrap/build-batteries.lisp:156 does for the
ones it keeps. Returns (validated refuted other work max-work assignments certificates)."
  (let ((ok 0) (refuted 0) (other 0) (work 0) (max-work 0) (assignments 0) (methods nil))
    (dolist (law laws)
      (let* ((val (resume-law-validation (start-law-validation law) limit))
             (w (ledger-total (law-validation-ledger val)))
             (cert (law-validation-certificate val)))
        (incf work w) (setf max-work (max max-work w))
        (case (law-validation-status val)
          (:validated (incf ok)) (:refuted (incf refuted)) (t (incf other)))
        (when cert
          (incf assignments (getf cert :assignments))
          (pushnew (list (getf cert :method) (getf cert :obligations)) methods :test #'equal))))
    (list :validated ok :refuted refuted :other other :work work :max-work max-work
          :assignments assignments :certificate-kinds methods)))
