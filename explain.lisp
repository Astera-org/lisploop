(in-package #:lisploop)

;;; Read-only causal summaries of synthesis jobs and of the knowledge library.

(defun print-fields (stream indent plist fields)
  "Print each (key label) of FIELDS whose value in PLIST is non-nil, one per line."
  (loop for (key label) in fields
        for value = (getf plist key)
        when value
          do (format stream "~A~A ~S~%" indent label value)))

(defun explain-synthesis-node (node &key job stream)
  "Return a structured causal summary plist for NODE (and print it to STREAM when non-NIL).
Shows the ancestor decoder chain from the root, reconstructed partial AST with hole,
bindings, row status breakdown, Stage A heuristic model, conflicts/nogoods, and search results."
  (let* ((ancestors (loop for cur = node then (synthesis-node-parent cur)
                          while cur collect cur into chain
                          finally (return (nreverse chain))))
         (proposal (synthesis-node-proposal node))
         (frame (synthesis-node-frame node))
         (target (when frame (schema-target (frame-schema frame))))
         (rows-summary
           (when frame
             (loop for r in (frame-rows frame)
                   collect (list :key (row-key r)
                                 :known (row-known r)
                                 :status (cond ((not (constrained-row-p r)) :dead-unconstrained)
                                               ((member :unresolved (row-known r)) :unresolved)
                                               (t :constrained))
                                 :requirement (row-requirement r)))))
         (h-model (synthesis-node-heuristic node))
         (search (synthesis-node-search node))
         (report
           (list :node-id (synthesis-node-id node)
                 :depth (node-depth node)
                 :phase (synthesis-node-phase node)
                 :expansion (synthesis-node-expansion node)
                 :path (mapcar (lambda (n)
                                 (list :id (synthesis-node-id n)
                                       :proposal (when (synthesis-node-proposal n)
                                                   (decomposition-name (synthesis-node-proposal n)))))
                               ancestors)
                 :reconstructed-hole-ast
                 (when target (ignore-errors (reconstruct-synthesis-candidate node (hole 0 target))))
                 :bindings (when proposal (decomposition-bindings proposal))
                 :lift-p (when proposal (decomposition-lift-p proposal))
                 :proposal-provenance (when proposal (decomposition-provenance proposal))
                 :node-provenance (synthesis-node-provenance node)
                 :priority (synthesis-node-priority node)
                 :stage-a (when h-model
                            (list :program (heuristic-program h-model)
                                  :exact-p (heuristic-exact-p h-model)
                                  :score (heuristic-score h-model)
                                  :residual (heuristic-residual h-model)
                                  :unresolved-keys (heuristic-unresolved-keys h-model)))
                 :reused-from (synthesis-node-reused-from node)
                 :deferred-proposals (mapcar #'decomposition-name (synthesis-node-deferred-proposals node))
                 :rows rows-summary
                 :search-results (when search
                                   (mapcar #'candidate-expression (search-job-results search)))
                 :job-work (when job (ledger-total (synthesis-job-ledger job))))))
    (when stream
      (format stream "~&=== Synthesis Node ~D (depth ~D, phase ~S, priority ~S) ===~%"
              (getf report :node-id) (getf report :depth) (getf report :phase) (getf report :priority))
      (print-fields stream "  " report
                    '((:path "Path:") (:reconstructed-hole-ast "Reconstructed AST with ?0:")
                      (:bindings "Bindings:") (:proposal-provenance "Proposal Provenance:")
                      (:node-provenance "Node Provenance:") (:stage-a "Stage A:")))
      (when rows-summary
        (format stream "  Rows (~D):~%~{    ~S~%~}" (length rows-summary) rows-summary))
      (print-fields stream "  " report '((:search-results "Search Results:"))))
    report))

(defun explain-synthesis-job (job &key stream)
  "Return a structured causal summary plist of JOB's entire synthesis DAG (and print to STREAM when non-NIL)."
  (let ((summary
          (list :work (ledger-total (synthesis-job-ledger job))
                :self-name (synthesis-job-self-name job)
                :debug-p (synthesis-job-debug-p job)
                :best (when (synthesis-job-best job)
                        (candidate-expression (synthesis-job-best job)))
                :results (mapcar #'candidate-expression (synthesis-job-results job))
                :reused-subproblems (synthesis-job-reused-subproblems job)
                :nogoods (synthesis-job-nogoods job)
                :nodes (mapcar (lambda (n) (explain-synthesis-node n :job job))
                               (synthesis-job-nodes job)))))
    (when stream
      (format stream "~&=== Synthesis Job Summary (work ~D, self ~S, best ~S) ===~%"
              (getf summary :work) (getf summary :self-name) (getf summary :best))
      (when (getf summary :nogoods)
        (format stream "  Nogoods (~D): ~S~%" (length (getf summary :nogoods)) (getf summary :nogoods)))
      (dolist (n (synthesis-job-nodes job))
        (explain-synthesis-node n :job job :stream stream)))
    summary))

(defun explain-knowledge-library (&key (library *knowledge-library*) kind id stream)
  "Return a structured summary plist of LIBRARY (optionally filtered by KIND or ID),
and print a readable report to STREAM when non-NIL."
  (let* ((entries (cond (id (let ((e (find-knowledge-entry id library)))
                              (when e (list e))))
                        (kind (knowledge-entries-of-kind kind library))
                        (t (knowledge-library-entries library))))
         (counts-by-kind
           (loop for spec in *knowledge-kind-specs*
                 for k = (knowledge-kind-spec-name spec)
                 for k-entries = (knowledge-entries-of-kind k library)
                 when k-entries
                   collect (cons k (length k-entries))))
         (total-bits (reduce #'+ entries :key #'knowledge-entry-bits :initial-value 0))
         (total-gain (reduce #'+ entries :key #'knowledge-entry-gain :initial-value 0))
         ;; Every slot of the entry, plus its secondary address and its edges in both directions.
         (entry-summaries
           (loop for e in entries
                 collect (append (loop for (key reader) in +knowledge-entry-slots+
                                       append (list key (funcall reader e)))
                                 (list :compositional-name (knowledge-entry-compositional-name e)
                                       :descriptor-profile (knowledge-entry-descriptor-profile e)
                                       :outgoing-edges (knowledge-edges-from e nil library)
                                       :incoming-edges (knowledge-edges-to (knowledge-entry-id e)
                                                                           nil library)))))
         (report (list :version (knowledge-library-version library)
                       :total-entries (length entries)
                       :counts-by-kind counts-by-kind
                       :total-bits total-bits
                       :total-gain total-gain
                       :priority-predictor (knowledge-library-priority-predictor library)
                       :entries entry-summaries)))
    (when stream
      (format stream "~&=== Knowledge Library (v~D, ~D entries, ~D bits, gain ~D) ===~%"
              (getf report :version) (getf report :total-entries) total-bits total-gain)
      (format stream "  Counts by kind: ~S~%" counts-by-kind)
      (print-fields stream "  " report '((:priority-predictor "Active Priority Predictor:")))
      (dolist (es entry-summaries)
        (format stream "  [~S ~S] (~S -> ~S) status=~S bits=~D gain=~D~%"
                (getf es :kind) (getf es :id) (getf es :inputs) (getf es :target)
                (getf es :status) (getf es :bits) (getf es :gain))
        ;; A guard that is trivially true says nothing; leave it out of the printout.
        (print-fields stream "    "
                      (if (equal (getf es :guard) (lit :bool t)) (list* :guard nil es) es)
                      '((:expression "expression:") (:guard "guard:     ") (:trigger "trigger:   ")
                        (:residual "residual:  ") (:outgoing-edges "edges ->:  ")
                        (:incoming-edges "edges <-:  ")))))
    report))
