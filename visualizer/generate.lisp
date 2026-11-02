;;; Run from any working directory: sbcl --script /path/to/visualizer/generate.lisp
(load (merge-pathnames "export.lisp" *load-truename*))
(load (merge-pathnames "../fixtures.lisp" *load-truename*))
(in-package #:lisploop-visualizer)

(defun transitions-for (domain ledger &key fresh changed)
  (let ((starts (if (eq domain :int) (lisploop::integer-held-out-starts)
                    '((0 2) (0 3) (0 4) (2 0) (2 1) (2 2))))
        (shift (if (eq domain :int) (if changed -2 -1) (if changed 3 4))))
    (if (eq domain :int)
        (if fresh (lisploop::integer-transition-fixture :starts starts :steps 1 :shift-b shift :ledger ledger)
            (lisploop::integer-transition-fixture :ledger ledger))
        (if fresh (lisploop::gf5-transition-fixture :starts starts :steps 1 :shift-b shift :ledger ledger)
            (lisploop::gf5-transition-fixture :ledger ledger)))))

(defun run-job (frame language id bound &key pairs anchors (expressions nil supplied-p))
  (let* ((scope (make-observation-scope frame language :id id :pairs pairs :anchors anchors))
         (job (if supplied-p (start-observation-search scope :expressions expressions)
                  (start-observation-search scope))))
    (unless supplied-p
      (assert (eq :cutoff (message-claim (resume-observation-search job bound 100)))))
    (assert (eq (if supplied-p :replay-complete :bounded-exhaustion)
                (message-claim (resume-observation-search job bound 1000000))))
    job))

(defun probe-frame (domain values)
  (make-frame (make-schema :inputs (list (cons 0 domain)) :target domain)
              (loop for value in values for key from 0 collect
                (make-row :key key :known (list value)
                          :requirement (lit :bool t)))))

(defun experiment-data (domain)
  (let* ((field-p (not (eq domain :int)))
         (id (if field-p "gf5" "integer"))
         (acquisition (make-ledger)) (orientation (make-ledger))
         (scopes nil))
    (multiple-value-bind (transitions anchors) (transitions-for domain acquisition)
      (multiple-value-bind (frame pairs) (transition-probes transitions domain orientation)
        (let* ((inputs (schema-inputs (frame-schema frame)))
               (language (make-language domain inputs))
               (sum (app (op :+ domain) (var 0 domain) (var 1 domain)))
               (bound (description-size sum inputs))
               (job (run-job frame language (concatenate 'string id "/training") bound :pairs pairs :anchors anchors))
               (invariants (observation-invariants job))
               (expressions (mapcar #'observed-expression-expression (observation-bucket-members (first invariants)))))
          (assert (and (= 1 (length invariants)) (= 2 (length expressions))))
          (push (job-data job :title "Discovery" :kind "training" :transitions transitions
                              :acquisition acquisition :orientation orientation) scopes)
          (loop for changed in '(nil t) do
            (let ((extra (make-ledger)) (extra-orientation (make-ledger)))
              (multiple-value-bind (fresh starts) (transitions-for domain extra :fresh t :changed changed)
                (multiple-value-bind (probes links) (transition-probes fresh domain extra-orientation)
                  ;; Standalone decode checks the same representation used by the run.
                  (let* ((decoded (mapcar (lambda (expression)
                                            (multiple-value-bind (model decoded-inputs)
                                                (decode-model (encode-model expression inputs))
                                              (assert (equal inputs decoded-inputs))
                                              model)) expressions))
                         (replay (run-job probes language
                                          (concatenate 'string id (if changed "/changed" "/fresh")) bound
                                          :pairs links :anchors starts :expressions decoded)))
                    (assert (eq (not changed) (not (null (observation-invariants replay)))))
                    (push (job-data replay :title (if changed "Changed transition" "Fresh states")
                                           :kind (if changed "changed" "fresh") :transitions fresh
                                           :acquisition extra :orientation extra-orientation) scopes))))))
          (when field-p
            (let ((extended-bound (+ (header-size inputs domain) 16)))
              (assert (eq :bounded-exhaustion (message-claim (resume-observation-search job extended-bound 1000000))))
              (push (job-data job :title (format nil "Extended bound · ~D bits" extended-bound)
                                  :kind "extended" :transitions transitions
                                  :acquisition acquisition :orientation orientation) scopes))))))
    (let* ((inputs (list (cons 0 domain))) (language (make-language domain inputs))
           (x (var 0 domain)) (square (app (op :* domain) x x))
           (bound (description-size square inputs))
           (old (run-job (probe-frame domain '(0 1)) language (concatenate 'string id "/ambiguous") bound))
           (new (run-job (probe-frame domain (if field-p '(0 1 2) (let ((n (ash 1 256))) (list 0 1 -1 2 n (1+ n)))))
                         language (concatenate 'string id "/expanded") bound
                         :expressions (mapcar #'observed-expression-expression (observation-job-records old)))))
      (assert (observed-agreement-p (find-observation old x) (find-observation old square)))
      (assert (not (observed-agreement-p (find-observation new x) (find-observation new square))))
      (push (job-data old :title "Agreement on {0,1}" :kind "ambiguous") scopes)
      (push (job-data new :title "Expanded inputs · agreement splits" :kind "expanded") scopes))
    (object "id" id "title" (type-text domain)
            "scopes" (array-data (nreverse scopes)))))

(defun generate ()
  (let* ((bundle (object "version" 2 "title" "Milestone 2 · observed equivalence"
                         "implementation" (format nil "~A ~A" (lisp-implementation-type) (lisp-implementation-version))
                         "experiments" (array-data
                                        (loop for domain in (list (gf 5) :int) collect
                                          (experiment-data domain)))))
         (json-path (merge-pathnames "data.json" *asset-root*))
         (report-path (merge-pathnames "report.html" *asset-root*)))
    (with-open-file (out json-path :direction :output :if-exists :supersede :external-format :utf-8)
      (write-json bundle out) (terpri out))
    (write-report bundle report-path)
    (format t "Generated ~A~%Data: ~A~%~D experiments, ~D scopes. Only visualizer/ was written.~%"
            report-path json-path (length (gethash "experiments" bundle))
            (loop for experiment across (gethash "experiments" bundle) sum (length (gethash "scopes" experiment))))
    bundle))

(generate)
