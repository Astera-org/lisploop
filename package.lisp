(defpackage #:lisploop
  (:use #:cl)
  (:export
   ;; 1. ast.lisp — Homoiconic S-expressions, schemas, bidirectional typing, O(1) metadata
   #:gf #:tuple-type #:sequence-type #:code-type #:code-type-p #:code-inputs #:code-sort
   #:valid-type-p #:function-sort-p #:value-p #:seq-type-p #:gf-type-p #:tuple-type-p #:input-alist
   #:schema #:make-schema #:copy-schema #:schema-domain #:schema-inputs #:schema-target #:schema-lookup-p
   #:lit #:var #:op #:app #:hole #:bool-not #:bool-and #:term #:map-ast #:app-of-p
   #:ast-meta #:ensure-ast-meta #:ast-kind #:ast-id #:ast-type #:ast-value
   #:var-p #:lit-p #:app-p #:hole-p #:operator-p #:operator-name #:operator-type #:operator-operand-type #:application-overhead
   #:expression-type #:free-vars #:provably-total-p #:instantiate #:expression-less-p
   #:function-definition #:function-definition-p #:function-definition-name
   #:function-definition-inputs #:function-definition-return-type #:function-definition-code-type
   #:function-definition-body #:function-definition-oracle-table
   #:function-definition-total-p #:function-definition-conditional-code-params
   #:define-function #:find-function-definition #:defined-function-p
   #:clear-function-definitions #:de-novo-function-name #:next-function-name #:rename-function-calls
   #:knowledge-kind-spec #:knowledge-kind-spec-p #:knowledge-kind-spec-name #:knowledge-kind-spec-priority
   #:find-knowledge-kind-spec #:define-knowledge-kind
   #:knowledge-entry #:knowledge-entry-p #:make-knowledge-entry
   #:knowledge-entry-id #:knowledge-entry-kind #:knowledge-entry-domain #:knowledge-entry-inputs
   #:knowledge-entry-target #:knowledge-entry-expression #:knowledge-entry-guard #:knowledge-entry-trigger
   #:knowledge-entry-residual #:knowledge-entry-auxiliary-code #:knowledge-entry-status
   #:knowledge-entry-certificate #:knowledge-entry-bits #:knowledge-entry-gain #:knowledge-entry-work
   #:knowledge-entry-edges #:knowledge-entry-metadata #:knowledge-entry-executable
   #:knowledge-library #:knowledge-library-p #:make-knowledge-library #:*knowledge-library*
   #:knowledge-library-version #:knowledge-library-entries #:knowledge-library-function-names
   #:knowledge-library-priority-predictor
   #:next-knowledge-entry-id #:find-knowledge-entry #:knowledge-entries-of-kind
   #:knowledge-edges-from #:knowledge-edges-to #:add-knowledge-edge
   #:rebuild-knowledge-library-indexes #:register-knowledge-entry #:remove-knowledge-entry
   #:consume-knowledge-entry #:clear-knowledge-library #:with-knowledge-library #:ast->sexp #:sexp->ast
   ;; 2. codec.lisp — Prefix-coded binary serialization & O(1) sizes
   #:+encoding-version+ #:header-size #:body-size #:description-size
   #:encode-model #:decode-model
   #:knowledge-entry->sexp #:sexp->knowledge-entry
   #:serialize-knowledge-library #:deserialize-knowledge-library
   #:save-knowledge-library #:load-knowledge-library
   ;; 3. vm.lisp — Structural tariff, resumable evaluator, constant folding
   #:+tariff-version+ #:+simulator-version+ #:vm-versions
   #:unresolved-evaluation
   #:ledger #:make-ledger #:ledger-total #:ledger-counts #:charge
   #:integer-width #:value-work #:type-work #:syntax-work
   #:evaluation #:start-evaluation #:advance-evaluation #:evaluate
   #:evaluation-status #:evaluation-value #:evaluation-error #:evaluation-work
   #:validated-program #:validated-program-p #:validated-program-expression #:validated-program-inputs #:validated-program-versions
   #:start-program-validation #:start-validated-evaluation
   #:advance-accounted-evaluation #:fold-constants
   ;; 4. frame.lisp — Frames, S-expression requirements, pullbacks, conflicts, support frames, quotients, partitions
   #:row #:make-row #:row-key #:row-known #:row-requirement
   #:frame #:make-frame #:frame-schema #:frame-rows #:frame-pairs #:frame-anchors
   #:singleton-requirement #:set-requirement #:extract-allowed-values #:check-requirement
   #:conjoin-requirements #:frame-conflict #:frame-conflict-p
   #:frame-constrained-row-count #:frame-min-resolved-rows
   #:orient-observations #:transition-probes #:lookup-model #:frame-oracle-table
   #:pullback-frame #:compose-model #:lift-frame #:compose-lifted-model #:*max-active-lifted-rows* #:conserved-quantity-frame #:support-frame
   #:partition #:partition-positions #:partition-groups #:partition-rows #:reassemble-partition #:partition-model
   #:partition-pairs-and-anchors #:with-frame-linkage
   #:centered-mod-difference #:correction-packet #:apply-correction-packet #:correction-bit-size #:select-closest-witness
   #:relational-linkage-residual
   #:quotient-values #:restore-quotient #:quotient-model
   ;; 5. enumerate.lisp — Grammar enumerator, synthesis & observation search, multi-lane propagation search
   #:language #:make-language #:derive-language #:snapshot-language #:language-domain #:language-inputs
   #:language-operators #:language-literals #:language-constants #:language-version
   #:enumerator #:make-enumerator #:enumerator-size #:enumerator-buckets #:enumeration-step
   #:candidate #:make-candidate #:candidate-expression #:candidate-size #:candidate-run-work #:candidate-discovery-work
   #:message #:make-message #:message-call-id #:message-claim #:message-evidence
   #:observation-outcome #:make-observation-outcome #:observation-outcome-status
   #:observation-outcome-value #:observation-outcome-error #:observation-outcome-work
   #:observed-expression #:make-observed-expression #:observed-expression-scope
   #:observed-expression-expression #:observed-expression-type #:observed-expression-status
   #:observed-expression-values #:observed-expression-outcomes #:observed-expression-run-work
   #:observed-expression-error #:observed-expression-failed-key
   #:observation-bucket #:make-observation-bucket #:observation-bucket-scope
   #:observation-bucket-type #:observation-bucket-values #:observation-bucket-members
   #:observation-bucket-invariant-p #:observation-bucket-informative-p #:observation-bucket-counterexample
   #:observation-bucket-pair-bits #:observation-bucket-anchor-bits #:observation-bucket-residual-bits
   #:start-search #:resume-search #:search-job-results #:search-job-best #:search-job-ledger
   #:search-job-completed-bound #:search-job-messages #:search-job-proposals #:search-job-reused-rejections
   #:make-observation-scope #:observation-scope-id #:observation-scope-frame #:observation-scope-language
   #:start-observation-search #:resume-observation-search #:observation-job-records
   #:observation-job-buckets #:observation-job-ledger #:observation-job-completed-bound #:observation-job-messages
   #:find-observation #:observed-agreement-p #:observation-invariants
   ;; 6. factor.lisp — Matching, AU, fiber proposals, corpus compression, heuristic condensation, M6 subgraph search
   #:match-pattern #:anti-unify #:compile-au-constructor #:pattern-has-holes-p #:term-sort
   #:shared-subterm-cover #:abstract-over-subterms
   #:library-abstraction #:library-abstraction-p #:library-abstraction-name
   #:library-abstraction-program-inputs #:library-abstraction-inputs
   #:library-abstraction-return-type #:library-abstraction-body
   #:library-abstraction-definition #:library-abstraction-pattern #:library-abstraction-programs
   #:library-abstraction-refactored-bodies #:library-abstraction-refactored-definitions
   #:library-abstraction-original-bits #:library-abstraction-library-bits
   #:library-abstraction-refactored-call-bits #:library-abstraction-refactored-bits
   #:library-abstraction-gain #:library-abstraction-work
   #:abstract-function-bodies #:discover-library-abstractions
   #:function-body-length-preserving-p #:compute-function-descriptor
   #:compose-hybrid-residual-program #:register-knowledge-relation #:consolidate-residual-relations
   #:consolidate-library-functions
   #:patterns-isomorphic-p #:pattern-holes #:pattern-hole-counts
   #:subtree-at-path #:replace-at-path #:tree-occurrence #:tree-occurrence-p
   #:tree-occurrence-tree-index #:tree-occurrence-path #:tree-occurrence-term
   #:tree-occurrence-sort #:tree-occurrence-signature #:collect-tree-occurrences
   #:au-substitutions-frame #:tree-corpus #:tree-corpus-domain #:tree-corpus-inputs #:tree-corpus-sort
   #:tree-corpus-trees #:tree-corpus-packet #:make-tree-corpus #:decode-tree-corpus #:tree-corpus-frame
   #:corpus-abstraction-model #:subexpression-abstraction #:subexpression-abstraction-p
   #:subexpression-abstraction-kind #:subexpression-abstraction-pattern
   #:subexpression-abstraction-substitutions #:subexpression-abstraction-paths
   #:subexpression-abstraction-model #:subexpression-abstraction-bits
   #:subexpression-abstraction-literal-bits #:subexpression-abstraction-gain
   #:subexpression-abstraction-structural-score #:discover-subexpression-abstractions
   #:shuffle-frame-rows #:partition-view-proposal #:partition-view-proposal-p
   #:partition-view-proposal-kind #:partition-view-proposal-guard #:partition-view-proposal-part-models
   #:partition-view-proposal-model #:partition-view-proposal-conflict
   #:partition-view-proposal-bits #:partition-view-proposal-run-work
   #:evaluate-guard-partition #:synthesize-supplied-partition-view #:discover-partition-views
   #:fiber-class #:fiber-class-p #:fiber-class-id #:fiber-class-requirement #:fiber-class-rows #:fiber-class-keys
   #:infer-fibers #:fiber-pairs-and-anchors
   #:context-label-frame
   #:law-corpus #:make-law-corpus #:law-corpus-laws #:law-corpus-packet #:law-corpus-frame
   #:law-template-group #:law-template-group-positions #:law-template-group-pattern #:law-template-group-substitutions
   #:propose-law-compressions #:decode-law-corpus
   #:condense-heuristic #:heuristic-model #:heuristic-model-p
   #:heuristic-program #:heuristic-residual #:heuristic-exact-p #:heuristic-program-bits
   #:heuristic-residual-bits #:heuristic-run-work #:heuristic-score #:heuristic-alternatives
   #:heuristic-buckets
   ;; 7. laws.lisp — Laws, validation, rewriting, solver discovery, dual-grade propagation
   #:law-type-p #:finite-type-p #:finite-type-cardinality #:law-assignment
   #:law #:make-law #:law-domain #:law-inputs #:law-lhs #:law-rhs #:law-equation #:law-guard #:law-origin #:law-statement
   #:law-certificate #:law-certificate-evidence #:law-certificate-assignments #:law-certificate-active #:law-certificate-work
   #:law-validation #:start-law-validation #:resume-law-validation #:law-validation-law
   #:law-validation-status #:law-validation-ledger #:law-validation-counterexample #:law-validation-certificate
   #:propose-observed-laws #:retype-law #:retype-function-definition
   #:observed-support #:guard-problem #:guard-problem-scope #:guard-problem-support
   #:guard-problem-frame #:guard-problem-equations #:propose-guard-problems #:start-guard-search #:propose-guarded-laws
   #:rewrite-rule #:rewrite-library #:rewrite-library-rules #:prepare-rewrite-library
   #:start-rewriting #:advance-rewriting #:rewriting-status #:rewriting-value #:rewriting-work #:rewriting-steps
   #:arithmetic-relation #:observe-arithmetic-relation #:arithmetic-relation-guard #:arithmetic-relation-records
   #:solve-discovery #:discover-arithmetic-solver #:validate-arithmetic-solver #:certified-solve-discovery-p
   #:solve-discovery-frame #:solve-discovery-witness #:solve-discovery-guard
   #:solve-discovery-validation #:solve-discovery-uniqueness
   #:propagation #:propagation-frame #:propagation-original #:propagation-fallback
   #:propagation-narrowed #:propagation-suggested #:propagation-retained #:propagation-rejected
   #:prepare-propagator-library #:as-propagator-library #:propagate-requirements #:propagation-ambiguous
   #:as-rewrite-library #:register-knowledge-law #:retype-knowledge-laws
   #:knowledge-evidence-current-p #:infer-function-template #:instantiate-function-template
   #:learn-knowledge-transformer
   #:knowledge-library-storage-bits #:walk-typed-ast #:remember-decoder-template
   #:*library-code-argument-bits* #:*library-code-argument-work* #:*library-partial-proposal-limit*
   #:register-knowledge-solver #:induce-functorial-solvers
   #:start-propagation-search #:resume-propagation-search #:propagation-search-results
   #:propagation-search-best #:propagation-search-ledger #:propagation-search-first-work
   ;; Recursive orchestration and explicit dependency/selector targets.
   #:snapshot-frame #:remaining-work #:*synthesis-debug-mode*
   #:decomposition #:make-decomposition #:decomposition-name #:decomposition-solver
   #:decomposition-lift-p #:decomposition-provenance
   #:nogood-clause #:nogood-clause-p #:nogood-clause-parent-id #:nogood-clause-kind
   #:nogood-clause-keys #:nogood-clause-known #:nogood-clause-bindings
   #:nogood-clause-decoder #:nogood-clause-child-id #:nogood-clause-child-type
   #:nogood-clause-parent-incompatible-p #:nogood-clause-clause-expr #:nogood-clause-parent-clause-expr
   #:anti-unify-nogood-clauses #:propose-dip-context-bindings #:dip-repaired-decompositions
   #:make-search-trace-frame #:condense-search-heuristic
   #:start-synthesis #:resume-synthesis #:synthesis-job-best #:synthesis-job-results
   #:synthesis-job-ledger #:synthesis-job-messages #:synthesis-job-debug-p
   #:synthesis-job-nogoods #:synthesis-job-reused-subproblems #:synthesis-job-trace
   #:synthesis-node-priority #:synthesis-node-heuristic #:synthesis-node-provenance #:synthesis-node-reserve-rows
   #:lift-inductive-sequence-context #:explain-synthesis-node #:explain-synthesis-job
   #:library-decompositions #:library-expander #:dependency-expander #:combine-expanders
   #:heuristic-decompositions #:heuristic-expander #:start-heuristic-synthesis
   #:start-recursive-synthesis
   #:synthesis-job-self-name #:synthesis-job-oracle-table #:synthesis-episode-returns
   #:dependency-proposals #:start-selector-search
   #:start-dependency-search #:resume-dependency-search #:dependency-search-synthesis
   #:dependency-search-features #:dependency-search-ledger
   #:start-heuristic-search #:resume-heuristic-search #:heuristic-search-best #:heuristic-search-ledger
   #:register-knowledge-nogood-schema #:register-knowledge-dip-feature #:register-knowledge-heuristic
   #:commit-synthesis-job #:consolidate-knowledge-library #:explain-knowledge-library
   ;; M9 partial fiber probes, compositional secondary addresses, and policy descriptors.
   #:probe-frame-coordinates
   #:descriptor-clause #:descriptor-clause-p #:make-descriptor-clause
   #:descriptor-clause-id #:descriptor-clause-facet #:descriptor-clause-tier
   #:descriptor-clause-status #:descriptor-clause-weight-bits #:descriptor-clause-work-cost
   #:knowledge-entry-compositional-name #:knowledge-entry-descriptor-profile
   #:find-knowledge-entries-by-address
   #:compute-entry-descriptor-profile #:derive-compositional-name
   #:score-entry-by-descriptors #:consolidate-policy-descriptors
   #:decomposition-policy-score #:synthesis-node-deferred-proposals #:promote-next-deferred-proposal))
(in-package #:lisploop)
