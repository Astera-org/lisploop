(in-package #:lisploop)

;;; Conflict clauses from failed child frames: construction, UIP generalisation, DIP repair.

(defstruct (nogood-clause (:predicate nogood-clause-p))
  parent-id kind keys known bindings decoder child-id child-type
  parent-incompatible-p clause-expr parent-clause-expr)

(defun nogood-identity (clause)
  "What makes CLAUSE the same deduction as another, invariant to row storage permutation."
  (list (nogood-clause-parent-id clause) (nogood-clause-kind clause)
        (sort (mapcar #'prin1-to-string
                      (if (eq :uip-clause (nogood-clause-kind clause))
                          (mapcar #'ast->sexp (extract-conjuncts (nogood-clause-clause-expr clause)))
                          (nogood-clause-keys clause)))
              #'string<)))

(defun pure-projection-decomposition-p (proposal)
  "True when PROPOSAL is a pure dependency projection `decoder = (var child-id child-type)`."
  (and proposal (var-p (decomposition-decoder proposal))
       (= (ast-id (decomposition-decoder proposal)) (decomposition-child-id proposal))))

(defun eval-expr-value (expr inputs known &optional ledger)
  "Evaluate EXPR on KNOWN under INPUTS in the VM and return (VALUES value ok-p)."
  (let ((run (evaluate expr inputs known :ledger ledger)))
    (if (eq :value (evaluation-status run)) (values (evaluation-value run) t) (values nil nil))))

(defun normalize-proposal-decoder (decoder child-id child-type)
  "Normalize DECODER by replacing CHILD-ID with `(var 0 child-type)`."
  (when (and decoder child-id child-type)
    (instantiate decoder (list (cons child-id (var 0 child-type))) :var)))

(defun same-lifted-decoder-p (entry proposal)
  (and proposal (decomposition-lift-p proposal) (nogood-clause-decoder entry)
       (equal (nogood-clause-child-type entry) (decomposition-child-type proposal))
       (equal (normalize-proposal-decoder (nogood-clause-decoder entry)
                                          (nogood-clause-child-id entry) (nogood-clause-child-type entry))
              (normalize-proposal-decoder (decomposition-decoder proposal)
                                          (decomposition-child-id proposal) (decomposition-child-type proposal)))))

(defun proposal-parent-expressions (proposal parent-inputs)
  (let ((bexprs (mapcar #'cdr (decomposition-bindings proposal))))
    (if (pure-projection-decomposition-p proposal)
        bexprs
        (let ((dvars (loop for id in (remove (decomposition-child-id proposal)
                                             (free-vars (decomposition-decoder proposal)) :test #'eql)
                           for spec = (assoc id parent-inputs :test #'eql)
                           when spec collect (var id (cdr spec)))))
          (remove-duplicates (append dvars bexprs) :test #'equal)))))

(defun lifted-nogood-p (clause)
  (member (nogood-clause-kind clause) '(:lift-incompatible-rows :uip-clause)))

(defun parent-row-keys (keys)
  (mapcar (lambda (k) (if (consp k) (first k) k)) keys))

(defun nogood-parent-keys (clause)
  (let ((keys (nogood-clause-keys clause)))
    (if (lifted-nogood-p clause) (parent-row-keys keys) keys)))

(defun matched-parent-rows (keys rows)
  (let ((matched (mapcar (lambda (k) (find k rows :key #'row-key :test #'equal)) keys)))
    (and (>= (length matched) 2) (every #'identity matched) matched)))

(defun shared-row-values (exprs inputs rows ledger)
  (flet ((rv (row) (evaluate-row-bindings (mapcar (lambda (e) (cons nil e)) exprs) inputs (row-known row)
                                          :ledger ledger :error-p nil)))
    (let ((shared (rv (first rows))))
      (if (and (not (eq shared :error)) (every (lambda (r) (equal shared (rv r))) (rest rows)))
          (values shared t) (values nil nil)))))

(defun binding-equalities (exprs values inputs)
  (loop for expr in exprs for val in values
        do (expression-type expr inputs)
        unless (eq val :unresolved) collect (term `(= ,expr ',val))))

(defun equalities-conjunction (equalities)
  (if equalities (reduce #'bool-and equalities :from-end t) (lit :bool t)))

(defun incompatible-rows-conflict (keys known)
  (make-frame-conflict :kind :incompatible-rows :keys (copy-list keys) :known known :expression (lit :bool nil)))

(defun build-nogood-clause (parent proposal conflict &optional ledger)
  "Construct a homoiconic S-expression nogood clause over PARENT's scope from a child CONFLICT."
  (let* ((pframe (synthesis-node-frame parent))
         (pinputs (schema-inputs (frame-schema pframe)))
         (keys (copy-list (frame-conflict-keys conflict)))
         (known (copy-tree (frame-conflict-known conflict)))
         (bindings (copy-tree (and proposal (decomposition-bindings proposal))))
         (bexprs (mapcar #'cdr bindings))
         (lift-p (and proposal (decomposition-lift-p proposal)))
         (ctype (and proposal (decomposition-child-type proposal)))
         (pkeys (if lift-p (parent-row-keys keys) keys))
         (mrows (matched-parent-rows pkeys (frame-rows pframe)))
         (pexprs (and lift-p mrows (proposal-parent-expressions proposal pinputs)))
         (pincompat-p
           (and (eq :incompatible-rows (frame-conflict-kind conflict)) mrows
                (or (pure-projection-decomposition-p proposal)
                    (and lift-p (every #'consp keys) (not (equal (first pkeys) (second pkeys)))
                         (every (lambda (k) (equal (second k) (second (first keys)))) (rest keys))
                         (nth-value 1 (shared-row-values pexprs pinputs mrows ledger))))))
         (pclause
           (when (and lift-p mrows)
             (equalities-conjunction
              (loop for e in pexprs
                    for (shared agree-p) = (multiple-value-list (shared-row-values (list e) pinputs mrows ledger))
                    when agree-p append (binding-equalities (list e) shared pinputs)))))
         (code-in (and lift-p (code-type-p ctype) (code-inputs ctype)))
         (cexpr
           (equalities-conjunction
            (if code-in
                (append (binding-equalities (loop for (id . tp) in code-in collect (var id tp)) known code-in)
                        (binding-equalities bexprs (nthcdr (length code-in) known) pinputs))
                (binding-equalities bexprs known pinputs)))))
    (make-nogood-clause
     :parent-id (synthesis-node-id parent)
     :kind (if lift-p :lift-incompatible-rows (frame-conflict-kind conflict))
     :keys keys :known known :bindings bindings
     :decoder (and proposal (copy-tree (decomposition-decoder proposal)))
     :child-id (and proposal (decomposition-child-id proposal)) :child-type (copy-tree ctype)
     :parent-incompatible-p pincompat-p :clause-expr cexpr :parent-clause-expr (or pclause cexpr))))

(defun collect-frame-nogood-clauses (parent proposal frame primary-conflict &optional ledger (budget 1000))
  "Collect PRIMARY-CONFLICT's nogood clause plus colliding `known` buckets on a lifted FRAME."
  (let ((clauses (list (build-nogood-clause parent proposal primary-conflict ledger))))
    (when (and frame proposal (decomposition-lift-p proposal)
               (eq :incompatible-rows (frame-conflict-kind primary-conflict)))
      (let ((joints (make-hash-table :test #'equal))
            (collided (list (frame-conflict-known primary-conflict))))
        (dolist (row (frame-rows frame))
          (unless (member :unresolved (row-known row))
            (let ((folded (fold-constants (row-requirement row) :ledger ledger :budget budget)))
              (unless (or (unsatisfiable-requirement-p folded) (member (row-known row) collided :test #'equal))
                (let ((extra (nth-value 1 (join-same-input joints row folded :ledger ledger :budget budget))))
                  (when extra
                    (push (row-known row) collided)
                    (push (build-nogood-clause parent proposal extra ledger) clauses)))))))))
    (nreverse clauses)))

(defun anti-unify-nogood-clauses (nogoods &optional ledger)
  "Anti-unify compatible NOGOODS to extract a UIP least-general generalization clause."
  (let ((valid (remove-if-not (lambda (ng) (and (not (eq :uip-clause (nogood-clause-kind ng)))
                                                (nogood-clause-clause-expr ng)))
                              nogoods)))
    (when (>= (length valid) 2)
      (let* ((fng (first valid))
             (compat (remove-if-not (lambda (ng)
                                      (and (eql (nogood-clause-parent-id ng) (nogood-clause-parent-id fng))
                                           (eq (nogood-clause-kind ng) (nogood-clause-kind fng))
                                           (equal (nogood-clause-child-type ng) (nogood-clause-child-type fng))))
                                    valid))
             (exprs (remove-duplicates (mapcar #'nogood-clause-clause-expr compat) :test #'equal)))
        (when (>= (length exprs) 2)
          (flet ((au (es) (anti-unify es (infer-exprs-inputs es) ledger)))
            (multiple-value-bind (pattern substitutions) (au exprs)
              (let* ((u-pexprs (remove-duplicates (remove nil (mapcar #'nogood-clause-parent-clause-expr compat))
                                                  :test #'equal))
                     (ppattern (when (>= (length u-pexprs) 2) (nth-value 0 (au u-pexprs)))))
                (values (make-nogood-clause
                         :parent-id (nogood-clause-parent-id fng) :kind :uip-clause
                         :keys (nogood-clause-keys fng) :known (nogood-clause-known fng)
                         :bindings (copy-tree (nogood-clause-bindings fng))
                         :decoder (copy-tree (nogood-clause-decoder fng))
                         :child-id (nogood-clause-child-id fng)
                         :child-type (copy-tree (nogood-clause-child-type fng))
                         :parent-incompatible-p (every #'nogood-clause-parent-incompatible-p compat)
                         :clause-expr pattern
                         :parent-clause-expr (or ppattern (nogood-clause-parent-clause-expr fng)))
                        pattern substitutions)))))))))

(defun clause-expr-matches-known-p (clause-expr scope-inputs known ledger)
  "Check whether CLAUSE-EXPR (concrete Boolean or UIP hole pattern) holds on KNOWN under SCOPE-INPUTS."
  (let ((hole-env (make-hash-table :test #'eql)))
    (labels ((holds-p (e) (multiple-value-bind (v ok) (eval-expr-value e scope-inputs known ledger) (and ok (eq t v))))
             (hole-eq-p (h closed)
               (multiple-value-bind (v ok) (eval-expr-value closed scope-inputs known ledger)
                 (and ok (multiple-value-bind (bound present) (gethash (ast-id h) hole-env)
                           (if present (equal bound v) (progn (setf (gethash (ast-id h) hole-env) v) t))))))
             (conj-ok-p (c)
               (if (pattern-has-holes-p c)
                   (and (app-of-p c :=)
                        (let ((l (second c)) (r (third c)))
                          (cond ((and (hole-p r) (not (pattern-has-holes-p l))) (hole-eq-p r l))
                                ((and (hole-p l) (not (pattern-has-holes-p r))) (hole-eq-p l r))
                                (t t))))
                   (holds-p c))))
      (cond ((or (null clause-expr) (equal clause-expr (lit :bool t))) t)
            ((pattern-has-holes-p clause-expr) (every #'conj-ok-p (extract-conjuncts clause-expr)))
            (t (holds-p clause-expr))))))

(defun check-library-nogood-schemas (library parent proposal ledger)
  "Check whether a unary higher-order `:lift-p t` PROPOSAL is refuted by a persisted `:nogood-schema`."
  (when (and parent proposal (decomposition-lift-p proposal)
             (null (decomposition-bindings proposal)) (code-type-p (decomposition-child-type proposal)))
    (let* ((schemas (active-knowledge-entries-of-kind :nogood-schema library))
           (ctype (decomposition-child-type proposal))
           (code-in (code-inputs ctype))
           (norm-dec (normalize-proposal-decoder (decomposition-decoder proposal)
                                                 (decomposition-child-id proposal) ctype))
           (schema (and schemas (= 1 (length code-in))
                        (find-if (lambda (e)
                                   (let* ((m (knowledge-entry-metadata e))
                                          (ecid (getf m :child-id)) (ect (getf m :child-type))
                                          (edec (knowledge-entry-auxiliary-code e)))
                                     (and edec ecid ect (equal ect ctype)
                                          (equal (normalize-proposal-decoder edec ecid ect) norm-dec))))
                                 schemas))))
      (when schema
        (let ((cexpr (knowledge-entry-expression schema))
              (by-elem (make-hash-table :test #'equal))
              conflicts)
          (dolist (row (frame-rows (synthesis-node-frame parent)))
            (when (and (constrained-row-p row) (= 1 (length (row-known row))) (listp (first (row-known row))))
              (let ((seq-in (first (row-known row)))
                    (allowed (extract-allowed-values (row-requirement row))))
                (when (and (consp allowed) (= 1 (length allowed)) (listp (first allowed))
                           (= (length seq-in) (length (first allowed))))
                  (loop for ein in seq-in for eout in (first allowed) for idx from 0
                        for okey = (list (row-key row) idx)
                        do (charge ledger :nogood-check 1)
                           (let ((prev (gethash ein by-elem)))
                             (if (null prev)
                                 (setf (gethash ein by-elem) (list (row-key row) okey eout))
                                 (when (and (not (equal (first prev) (row-key row)))
                                            (not (equal (third prev) eout))
                                            (clause-expr-matches-known-p cexpr code-in (list ein) ledger))
                                   (push (incompatible-rows-conflict (list (second prev) okey) (list ein))
                                         conflicts)))))))))
          (when conflicts
            (let ((ordered (nreverse conflicts)))
              (values (first ordered) (mapcar (lambda (c) (build-nogood-clause parent proposal c ledger)) ordered)))))))))

(defun check-parent-nogoods (job parent proposal ledger)
  "Deductively check whether PROPOSAL is refuted by any nogood on PARENT or `:nogood-schema` in JOB."
  (when (and job (synthesis-job-deductive-nogoods-p job) parent proposal
             (or (pure-projection-decomposition-p proposal) (decomposition-lift-p proposal)))
    (let* ((pframe (synthesis-node-frame parent))
           (inputs (schema-inputs (frame-schema pframe)))
           (bexprs (mapcar #'cdr (decomposition-bindings proposal)))
           (pure-p (pure-projection-decomposition-p proposal)))
      (dolist (entry (synthesis-job-nogoods job))
        (let* ((pkeys (nogood-parent-keys entry))
               (mrows (and (= (nogood-clause-parent-id entry) (synthesis-node-id parent))
                           (matched-parent-rows pkeys (frame-rows pframe)))))
          (when mrows
            (when (or (and pure-p (eq :incompatible-rows (nogood-clause-kind entry)))
                      (nogood-clause-parent-incompatible-p entry))
              (if pure-p
                  (multiple-value-bind (known agree-p) (shared-row-values bexprs inputs mrows ledger)
                    (when agree-p (return-from check-parent-nogoods (incompatible-rows-conflict pkeys known))))
                  (when (and (nth-value 1 (shared-row-values (proposal-parent-expressions proposal inputs)
                                                             inputs mrows ledger))
                             (clause-expr-matches-known-p (nogood-clause-parent-clause-expr entry)
                                                          inputs (row-known (first mrows)) ledger))
                    (return-from check-parent-nogoods
                      (incompatible-rows-conflict
                       pkeys (shared-row-values bexprs inputs (list (first mrows)) ledger))))))
            (when (and (lifted-nogood-p entry) (same-lifted-decoder-p entry proposal))
              (let* ((code-in (code-inputs (decomposition-child-type proposal)))
                     (cknown (subseq (nogood-clause-known entry)
                                     0 (min (length code-in) (length (nogood-clause-known entry))))))
                (when (or (nogood-clause-bindings entry)
                          (clause-expr-matches-known-p (nogood-clause-clause-expr entry) code-in cknown ledger))
                  (multiple-value-bind (extra agree-p) (shared-row-values bexprs inputs mrows ledger)
                    (when agree-p
                      (return-from check-parent-nogoods
                        (incompatible-rows-conflict (nogood-clause-keys entry) (append cknown extra)))))))))))
      (check-library-nogood-schemas (synthesis-job-knowledge job) parent proposal ledger))))

(defun conflict-distinct-parent-row-pairs (parent-frame nogoods)
  (let (pairs)
    (dolist (ng nogoods (nreverse pairs))
      (when (and (or (lifted-nogood-p ng) (eq :incompatible-rows (nogood-clause-kind ng)))
                 (>= (length (nogood-clause-keys ng)) 2))
        (destructuring-bind (&optional r1 r2)
            (matched-parent-rows (subseq (nogood-parent-keys ng) 0 2) (frame-rows parent-frame))
          (when (and r1 (not (equal (row-key r1) (row-key r2))))
            (pushnew (cons r1 r2) pairs :test #'equal)))))))

(defun candidate-dip-context-expressions (parent-frame language &key existing-bindings allow-sequence-p)
  (let* ((inputs (schema-inputs (frame-schema parent-frame)))
         (existing (mapcar #'cdr existing-bindings))
         cands)
    (labels ((ok-type-p (tp) (and (not (code-type-p tp)) (or allow-sequence-p (not (seq-type-p tp)))))
             (add (e) (unless (member e existing :test #'equal) (pushnew e cands :test #'equal)))
             (tvars (tp) (loop for (id . itp) in inputs when (equal itp tp) collect (var id itp))))
      (dolist (s inputs) (when (ok-type-p (cdr s)) (add (var (car s) (cdr s)))))
      (dolist (op (language-operators language))
        (when (operator-p op)
          (let* ((sig (operator-type op)) (args (second sig)) (ret (third sig)))
            (when (and (ok-type-p ret) (not (member (operator-name op) '(:= :< :if :tuple :cons))))
              (cond ((= 1 (length args)) (dolist (v (tvars (first args))) (add (app op v))))
                    ((and (= 2 (length args)) (eq :at (operator-name op)))
                     (dolist (v (tvars (first args))) (add (app op v (lit :int 0)))))
                    ((= 2 (length args))
                     (dolist (v1 (tvars (first args)))
                       (dolist (v2 (tvars (second args)))
                         (unless (eql (ast-id v1) (ast-id v2)) (add (app op v1 v2)))))))))))
      (stable-sort (nreverse cands) #'< :key (lambda (e) (description-size e inputs))))))

(defun propose-dip-context-bindings (parent-frame language nogoods
                                     &key existing-bindings (max-candidates 2)
                                          allow-sequence-p ledger (library *knowledge-library*))
  "Dual Implication Point (DIP) context introduction: up to MAX-CANDIDATES minimal total
expressions separating conflicting parent row pairs in NOGOODS (`:dip-feature` library entries first)."
  (let* ((pairs (conflict-distinct-parent-row-pairs parent-frame nogoods))
         (inputs (schema-inputs (frame-schema parent-frame)))
         (existing (mapcar #'cdr existing-bindings))
         (crows (remove-if-not #'constrained-row-p (frame-rows parent-frame))))
    (when pairs
      (labels ((ev (cand known)
                 (if (knowledge-entry-p cand)
                     (multiple-value-bind (v st) (eval-entry-slot cand :expr known :ledger ledger)
                       (values v (eq st :value)))
                     (eval-expr-value cand inputs known ledger)))
               (seps-all-p (cand)
                 (and (every (lambda (p)
                               (multiple-value-bind (v1 ok1) (ev cand (row-known (car p)))
                                 (multiple-value-bind (v2 ok2) (ev cand (row-known (cdr p)))
                                   (and ok1 ok2 (not (equal v1 v2))))))
                             pairs)
                      (every (lambda (r) (nth-value 1 (ev cand (row-known r)))) crows))))
        (let ((lib-seps (loop for e in (active-knowledge-entries-of-kind :dip-feature library)
                              for expr = (knowledge-entry-expression e)
                              when (and expr (not (member expr existing :test #'equal))
                                        (equal (ignore-errors (expression-type expr inputs)) (knowledge-entry-target e))
                                        (seps-all-p (if (equal (knowledge-entry-inputs e) inputs) e expr)))
                                collect expr)))
          (if lib-seps
              (let ((dedup (remove-duplicates lib-seps :test #'equal :from-end t)))
                (subseq dedup 0 (min max-candidates (length dedup))))
              (let (seps)
                (dolist (expr (candidate-dip-context-expressions parent-frame language
                                                                 :existing-bindings existing-bindings
                                                                 :allow-sequence-p allow-sequence-p)
                              (nreverse seps))
                  (when (and (< (length seps) max-candidates) (seps-all-p expr))
                    (push expr seps))))))))))

(defun dip-repaired-decompositions (parent proposal nogoods
                                    &key (max-repairs 1) ledger (debug-p *synthesis-debug-mode*)
                                         (library *knowledge-library*))
  "Use DIP context introduction to propose repaired decompositions with an added separator variable."
  (when (and parent proposal nogoods
             (not (and (consp (decomposition-name proposal)) (eq :dip-repair (first (decomposition-name proposal)))))
             (or (decomposition-lift-p proposal) (pure-projection-decomposition-p proposal)))
    (let* ((pframe (synthesis-node-frame parent))
           (pinputs (schema-inputs (frame-schema pframe)))
           (seps (propose-dip-context-bindings pframe (synthesis-node-language parent) nogoods
                                               :existing-bindings (decomposition-bindings proposal)
                                               :max-candidates max-repairs :ledger ledger :library library)))
      (loop for sep in seps
            for stype = (expression-type sep pinputs)
            for base-in = (if (decomposition-lift-p proposal)
                              (append (code-inputs (decomposition-child-type proposal))
                                      (decomposition-bindings proposal))
                              (decomposition-bindings proposal))
            for new-cid = (next-child-id base-in)
            for repaired = (copy-decomposition-tree proposal)
            do (setf (decomposition-name repaired) (list :dip-repair (decomposition-name proposal) sep)
                     (decomposition-bindings repaired)
                     (append (copy-tree (decomposition-bindings proposal)) (list (cons new-cid sep)))
                     (decomposition-language repaired)
                     (derive-language (decomposition-language proposal)
                                      :inputs (append (copy-tree (language-inputs (decomposition-language proposal)))
                                                      (list (cons new-cid stype))))
                     (decomposition-provenance repaired)
                     (when debug-p (list :origin :dip-repair :from (decomposition-name proposal)
                                         :introduced-binding (cons new-cid sep))))
            collect repaired))))
