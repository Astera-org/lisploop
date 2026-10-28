;;; Read-only adapters. Loading this file does not run experiments or write files.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package '#:lisploop)
    (unless (probe-file (merge-pathnames "../codec.lisp" *load-truename*))
      (error "Missing kernel source codec.lisp. Pull the complete encoding update before regenerating the visualizer."))
    (load (merge-pathnames "../load.lisp" *load-truename*))))

(defpackage #:lisploop-visualizer
  (:use #:cl #:lisploop)
  (:export #:frame-data #:job-data #:write-json #:write-report #:write-job-report))
(in-package #:lisploop-visualizer)

(defparameter *asset-root* (make-pathname :name nil :type nil :defaults *load-truename*))

;;; Objects are hash tables; arrays are vectors, including empty arrays. Domain
;;; integers are STRINGS, so a browser never rounds arbitrary-precision values.
(defun object (&rest entries)
  (let ((result (make-hash-table :test #'equal)))
    (loop for (key value) on entries by #'cddr do
      (setf (gethash key result) value))
    result))

(defun array-data (items) (coerce items 'vector))
(defun boolean-data (value) (if value :true :false))
(defun packet-text (expression inputs)
  (map 'string #'digit-char (encode-model expression inputs)))
(defun sexp-text (value)
  (let ((*print-pretty* nil) (*print-readably* t) (*print-base* 10)
        (*print-radix* nil) (*package* (find-package '#:keyword)))
    (write-to-string value)))

(defun type-text (type)
  (cond ((eq type :int) "Integer") ((eq type :bool) "Boolean")
        ((and (consp type) (eq (first type) :gf)) (format nil "GF(~D)" (second type)))
        ((eq (first type) :tuple)
         (format nil "Tuple(~{~A~^, ~})" (mapcar #'type-text (rest type))))
        ((eq (first type) :seq) (format nil "Sequence(~A)" (type-text (second type))))
        (t (sexp-text type))))

(defun value-data (value type)
  (cond ((eq type :bool) (boolean-data value))
        ((code-type-p type) (sexp-text value))
        ((integerp value) (format nil "~D" value))
        ((eq (first type) :tuple)
         (array-data (mapcar #'value-data value (rest type))))
        ((eq (first type) :seq)
         (array-data (mapcar (lambda (v) (value-data v (second type))) value)))
        (t (error "Cannot export ~S of type ~S" value type))))

(defun input-name (id inputs)
  (let ((index (position id inputs :key #'car)))
    (cond ((= (length inputs) 1) "x")
          ((and index (< index 26)) (string (code-char (+ (char-code #\a) index))))
          (t (format nil "v~D" id)))))

(defun expression-text (expression inputs)
  (case (first expression)
    (:var (input-name (second expression) inputs))
    (:lit (if (integerp (third expression)) (format nil "~D" (third expression))
              (sexp-text (third expression))))
    (:app
     (let ((name (second (second expression))) (args (third expression)))
       (if (member name '(:+ :* :=))
           (format nil "(~A ~A ~A)" (expression-text (first args) inputs)
                   (symbol-name name) (expression-text (second args) inputs))
           (format nil "~A(~{~A~^, ~})" (string-downcase (symbol-name name))
                   (mapcar (lambda (arg) (expression-text arg inputs)) args)))))
    (otherwise (sexp-text expression))))

(defun frame-data (frame)
  "Export the exact schema, ordered rows, and joint allowed values or predicate.
Keys are inspection labels, never predictor arguments. No checker is executed."
  (let* ((schema (frame-schema frame)) (inputs (schema-inputs schema)))
    (object
     "schema" (object "inputs" (array-data
                                 (mapcar (lambda (input)
                                           (object "id" (car input) "name" (input-name (car input) inputs)
                                                   "type" (type-text (cdr input)))) inputs))
                      "target" (type-text (schema-target schema))
                      "lookup" (boolean-data (schema-lookup-p schema)))
     "rows" (array-data
             (mapcar
              (lambda (row)
                (let* ((allowed (row-allowed row)) (values (allowed-values allowed))
                       (finite-p (not (eq values :unknown))))
                  (object "key" (sexp-text (row-key row))
                          "known" (array-data (mapcar #'value-data (row-known row) (mapcar #'cdr inputs)))
                          "allowed" (object
                                     "type" (type-text (allowed-type allowed))
                                     "kind" (if finite-p "finite" "predicate")
                                     "values" (if finite-p
                                                  (array-data (mapcar (lambda (v) (value-data v (allowed-type allowed))) values))
                                                  :null)
                                     "predicate" (sexp-text (allowed-expression allowed))
                                     "packet" (packet-text (allowed-expression allowed)
                                                           (list (cons 0 (allowed-type allowed))))))))
              (frame-rows frame))))))

(defun ledger-data (ledger)
  (object "total" (ledger-total ledger)
          "categories" (array-data
                        (mapcar (lambda (entry)
                                  (object "name" (string-downcase (symbol-name (car entry))) "work" (cdr entry)))
                                (sort (copy-list (ledger-counts ledger)) #'string<
                                      :key (lambda (entry) (symbol-name (car entry))))))))

;;; These accessors are not exported by the kernel package. Keep the small
;;; inspection boundary here; do not change the kernel's package API.
(defun job-scope (job) (lisploop::observation-job-scope job))
(defun scope-pairs (scope) (lisploop::observation-scope-pairs scope))
(defun scope-anchors (scope) (lisploop::observation-scope-anchors scope))

(defun job-data (job &key title (kind "custom") transitions acquisition orientation)
  "Take a read-only snapshot of a live M2 job, including failed/partial work.
Only completed records belong to buckets. A pending record is kept separately."
  (let* ((scope (job-scope job)) (language (observation-scope-language scope))
         (inputs (language-inputs language))
         (records (reverse (observation-job-records job)))
         (buckets (reverse (observation-job-buckets job))))
    (labels ((record-data (record id)
               (let* ((expression (observed-expression-expression record))
                      (type (observed-expression-type record))
                      (result-type (or type (expression-type expression inputs))))
                 (object "id" id "expression" (expression-text expression inputs)
                         "ast" (sexp-text expression) "packet" (packet-text expression inputs)
                         "type" (if type (type-text type) "Not yet checked")
                         "status" (string-downcase (symbol-name (observed-expression-status record)))
                         "size" (description-size expression inputs)
                         "headerBits" (header-size inputs result-type)
                         "bodyBits" (body-size expression inputs)
                         "runWork" (observed-expression-run-work record)
                         "values" (array-data (mapcar (lambda (v) (value-data v type))
                                                     (observed-expression-values record)))
                         "error" (or (observed-expression-error record) :null)
                         "failedKey" (if (eq :error (observed-expression-status record))
                                         (sexp-text (observed-expression-failed-key record)) :null))))
             (record-id (record) (position record records :test #'eq)))
      (object
       "id" (sexp-text (observation-scope-id scope)) "title" (or title (sexp-text (observation-scope-id scope)))
       "kind" kind "evidence" (string-downcase (symbol-name (observation-scope-evidence scope)))
       "equality" (string-downcase (symbol-name (observation-scope-equality scope)))
       "simulatorVersion" (observation-scope-simulator-version scope)
       "encodingVersion" (lisploop::observation-scope-encoding-version scope)
       "tariffVersion" (lisploop::observation-scope-tariff-version scope)
       "domain" (type-text (language-domain language))
       "unit" "bits"
       "literals" (if (eq (language-literals language) :all) "All domain literals"
                       (format nil "{~{~D~^, ~}}" (language-literals language)))
       "operators" (array-data (mapcar (lambda (operator) (symbol-name (second operator))) (language-operators language)))
       "languageVersion" (lisploop::language-version language)
       "frame" (frame-data (observation-scope-frame scope))
       "transitions" (if transitions (frame-data transitions) :null)
       "pairs" (array-data (mapcar #'array-data (scope-pairs scope)))
       "anchors" (array-data (scope-anchors scope))
       "mode" (string-downcase (symbol-name (lisploop::observation-job-mode job)))
       "phase" (string-downcase (symbol-name (lisploop::observation-job-phase job)))
       "bound" (lisploop::observation-job-requested-bound job)
       "completedBound" (observation-job-completed-bound job)
       "records" (array-data (loop for record in records for id from 0 collect (record-data record id)))
       "pending" (let ((current (lisploop::observation-job-current job)))
                   (if (and current (not (member current records :test #'eq)))
                       (record-data current "pending") :null))
       "buckets" (array-data
                  (loop for bucket in buckets for id from 0 collect
                    (object "id" id "type" (type-text (observation-bucket-type bucket))
                            "values" (array-data (mapcar (lambda (v) (value-data v (observation-bucket-type bucket)))
                                                       (observation-bucket-values bucket)))
                            "members" (array-data (mapcar #'record-id (reverse (observation-bucket-members bucket))))
                            "invariant" (boolean-data (observation-bucket-invariant-p bucket))
                            "informative" (boolean-data (observation-bucket-informative-p bucket))
                            "counterexample" (if (observation-bucket-counterexample bucket)
                                                 (sexp-text (observation-bucket-counterexample bucket)) :null))))
       "messages" (array-data
                   (mapcar (lambda (message)
                             (let ((evidence (message-evidence message)))
                               (if (member (message-claim message) '(:cutoff :bounded-exhaustion :replay-complete))
                                   (object "claim" (string-downcase (symbol-name (message-claim message)))
                                           "bound" (getf evidence :description-limit)
                                           "completedBound" (getf evidence :completed-bound)
                                           "work" (getf evidence :work)
                                           "encodingVersion" (getf evidence :encoding-version)
                                           "tariffVersion" (getf evidence :tariff-version)
                                           "coverage" (string-downcase (symbol-name (getf evidence :syntax-coverage))))
                                   (object "claim" (string-downcase (symbol-name (message-claim message)))
                                           "record" (record-id evidence)))))
                           (reverse (observation-job-messages job))))
       "ledger" (ledger-data (observation-job-ledger job))
       "acquisition" (if acquisition (ledger-data acquisition) :null)
       "orientation" (if orientation (ledger-data orientation) :null)))))

(defun write-json (value stream)
  "Write deterministic JSON, safe for embedding in an HTML script data block."
  (labels ((string-json (string)
             (write-char #\" stream)
             (loop for char across string for code = (char-code char) do
               (case char
                 (#\" (write-string "\\\"" stream)) (#\\ (write-string "\\\\" stream))
                 (otherwise
                  (if (or (< code 32) (find char "<>&") (= code #x2028) (= code #x2029))
                      (format stream "\\u~4,'0X" code) (write-char char stream)))))
             (write-char #\" stream))
           (emit (x)
             (cond ((eq x :true) (write-string "true" stream))
                   ((eq x :false) (write-string "false" stream))
                   ((eq x :null) (write-string "null" stream))
                   ((stringp x) (string-json x))
                   ((integerp x) (format stream "~D" x))
                   ((hash-table-p x)
                    (write-char #\{ stream)
                    (loop for key in (sort (loop for k being the hash-keys of x collect k) #'string<)
                          for first-p = t then nil do
                            (unless first-p (write-char #\, stream))
                            (string-json key) (write-char #\: stream) (emit (gethash key x)))
                    (write-char #\} stream))
                   ((vectorp x)
                    (write-char #\[ stream)
                    (loop for item across x for first-p = t then nil do
                      (unless first-p (write-char #\, stream)) (emit item))
                    (write-char #\] stream))
                   (t (error "Not JSON data: ~S" x)))))
    (emit value)))

(defun file-text (path)
  (with-open-file (stream path :external-format :utf-8)
    (let ((text (make-string (file-length stream))))
      (subseq text 0 (read-sequence text stream)))))

(defun html-text (text)
  (with-output-to-string (out)
    (loop for char across text do
      (write-string (case char (#\< "&lt;") (#\> "&gt;") (#\& "&amp;") (#\" "&quot;")
                          (t (string char))) out))))

(defun summary-html (bundle)
  (with-output-to-string (out)
    (write-string "<table><caption>Generated experiment index (also available without JavaScript)</caption><thead><tr><th>Domain</th><th>Encoding</th><th>Scope</th><th>Probes</th><th>Expressions</th><th>Buckets</th><th>Discovery / replay work</th></tr></thead><tbody>" out)
    (loop for experiment across (gethash "experiments" bundle) do
      (loop for scope across (gethash "scopes" experiment) do
        (format out "<tr>~{<td>~A</td>~}</tr>"
                (mapcar (lambda (x) (html-text (princ-to-string x)))
                        (list (gethash "domain" scope) (format nil "Binary v~D" (gethash "encodingVersion" scope)) (gethash "title" scope)
                              (length (gethash "rows" (gethash "frame" scope)))
                              (length (gethash "records" scope)) (length (gethash "buckets" scope))
                              (gethash "total" (gethash "ledger" scope)))))))
    (write-string "</tbody></table>" out)))

(defun write-report (bundle destination &key (assets *asset-root*))
  "Write a portable HTML snapshot. BUNDLE is an object with an experiments vector;
each experiment has id, title and scopes (JOB-DATA snapshots). Assets is visualizer/."
  (let* ((template (file-text (merge-pathnames "viewer.html" assets)))
         (replacements (list (cons "@@STYLE@@" (file-text (merge-pathnames "viewer.css" assets)))
                             (cons "@@SCRIPT@@" (file-text (merge-pathnames "viewer.js" assets)))
                             (cons "@@DATA@@" (with-output-to-string (out) (write-json bundle out)))
                             (cons "@@SUMMARY@@" (summary-html bundle)))))
    (with-open-file (out destination :direction :output :if-exists :supersede :external-format :utf-8)
      (loop with start = 0 for next = (search "@@" template :start2 start) do
        (write-string template out :start start :end next)
        (unless next (return))
        (let* ((end (+ 2 (or (search "@@" template :start2 (+ next 2)) (error "Unclosed template token"))))
               (token (subseq template next end)) (replacement (assoc token replacements :test #'string=)))
          (unless replacement (error "Unknown template token ~A" token))
          (write-string (cdr replacement) out)
          (setf start end)))))
  destination)

(defun write-job-report (job destination &key (title "Observation job") transitions acquisition orientation)
  "Inspect an existing job without resuming it, reevaluating it, or changing it."
  (write-report
   (object "version" 2 "experiments"
           (vector (object "id" "custom" "title" title "scopes"
                           (vector (job-data job :title title :transitions transitions
                                                :acquisition acquisition :orientation orientation)))))
   destination))
