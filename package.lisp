(defpackage #:lisploop
  (:use #:cl)
  (:export
   ;; 1. ast.lisp — Homoiconic S-expressions, schemas, bidirectional typing, O(1) metadata
   #:gf #:tuple-type #:sequence-type #:code-type #:code-type-p #:code-inputs #:code-sort
   #:valid-type-p #:function-sort-p #:value-p #:seq-type-p #:gf-type-p #:tuple-type-p #:input-alist
   #:schema #:make-schema #:copy-schema #:schema-domain #:schema-inputs #:schema-target #:schema-lookup-p
   #:schema-availability #:schema-target-availability #:schema-availability-order
   #:rank-le-p #:rank-lt-p #:available-inputs #:expression-respects-availability-p
   #:schema-maximal-availability-id
   #:lit #:var #:op #:app #:hole #:bool-not #:bool-and #:term #:map-ast #:app-of-p
   #:ast-meta #:ensure-ast-meta #:ast-kind #:ast-id #:ast-type #:ast-value
   #:var-p #:lit-p #:app-p #:hole-p #:operator-p
   #:operator-name #:operator-type #:operator-operand-type #:at-container-type #:application-overhead
   #:expression-type #:free-vars #:provably-total-p #:instantiate #:expression-less-p
   #:function-definition #:function-definition-p #:function-definition-name
   #:function-definition-inputs #:function-definition-return-type #:function-definition-code-type
   #:function-definition-body #:function-definition-oracle-table
   #:function-definition-total-p #:function-definition-conditional-code-params
   #:define-function #:find-function-definition #:defined-function-p
   #:clear-function-definitions #:de-novo-function-name #:next-function-name #:rename-function-calls

   ;; 2. knowledge.lisp — Extensible knowledge kinds, synchronized executables, library graph
   #:knowledge-kind-spec #:knowledge-kind-spec-p #:knowledge-kind-spec-name #:knowledge-kind-spec-priority
   #:find-knowledge-kind-spec #:define-knowledge-kind
   #:entry-executable #:entry-executable-p #:ensure-entry-executable #:eval-entry-slot
   #:knowledge-entry #:knowledge-entry-p #:make-knowledge-entry
   #:knowledge-entry-id #:knowledge-entry-kind #:knowledge-entry-domain #:knowledge-entry-inputs
   #:knowledge-entry-target #:knowledge-entry-expression #:knowledge-entry-guard #:knowledge-entry-trigger
   #:knowledge-entry-residual #:knowledge-entry-auxiliary-code #:knowledge-entry-status
   #:knowledge-entry-certificate #:knowledge-entry-bits #:knowledge-entry-gain #:knowledge-entry-work
   #:knowledge-entry-edges #:knowledge-entry-metadata #:knowledge-entry-executable
   #:knowledge-entry-compositional-name #:knowledge-entry-descriptor-profile
   #:knowledge-entry-active-p
   #:knowledge-library #:knowledge-library-p #:make-knowledge-library #:*knowledge-library*
   #:knowledge-library-version #:knowledge-library-entries #:knowledge-library-function-names
   #:knowledge-library-priority-predictor #:knowledge-library-compositional-index
   #:next-knowledge-entry-id #:find-knowledge-entry #:knowledge-entries-of-kind
   #:find-knowledge-entries-by-address
   #:knowledge-edges-from #:knowledge-edges-to #:add-knowledge-edge
   #:rebuild-knowledge-library-indexes #:register-knowledge-entry #:remove-knowledge-entry
   #:consume-knowledge-entry #:clear-knowledge-library #:with-knowledge-library
   #:ast->sexp #:sexp->ast

   ;; 3. codec.lisp — Prefix-coded binary serialization & O(1) description lengths
   #:+encoding-version+ #:header-size #:body-size #:description-size #:value-bit-size
   #:encode-model #:decode-model

   ;; 4. vm.lisp — Structural tariff, resumable stack VM, prepared program execution
   #:+tariff-version+ #:+simulator-version+ #:vm-versions
   #:unresolved-evaluation
   #:ledger #:make-ledger #:ledger-total #:ledger-counts #:charge #:remaining-work
   #:integer-width #:value-work #:type-work #:syntax-work
   #:evaluation #:start-evaluation #:advance-evaluation #:evaluate
   #:evaluation-status #:evaluation-value #:evaluation-error #:evaluation-work
   #:validated-program #:validated-program-p #:validated-program-expression
   #:validated-program-inputs #:validated-program-versions
   #:start-program-validation #:start-validated-evaluation
   #:advance-accounted-evaluation

   ;; 5. evidence.lisp — Provenance tracking & dependency currency
   #:attest-knowledge-entry #:knowledge-evidence-current-p #:knowledge-evidence-tested-p

   ;; 6. persistence.lisp — Homoiconic S-expression library serialization & storage accounting
   #:knowledge-entry->sexp #:sexp->knowledge-entry
   #:serialize-knowledge-library #:deserialize-knowledge-library
   #:save-knowledge-library #:load-knowledge-library
   #:knowledge-library-storage-bits

   ;; 7. requirements.lisp — S-expression requirements, conjunctions, partial evaluation
   #:singleton-requirement #:set-requirement #:extract-allowed-values #:check-requirement
   #:conjoin-requirements #:fold-constants

   ;; 8. frame.lisp — Frames, pullbacks, 1-to-many lifts, coordinate probes, delta packets
   #:row #:make-row #:row-key #:row-known #:row-requirement
   #:frame #:frame-p #:make-frame #:simple-frame #:probe-frame #:snapshot-frame
   #:frame-schema #:frame-rows #:frame-pairs #:frame-anchors #:frame-edges #:hard-edges
   #:frame-conflict #:frame-conflict-p #:frame-conflict-kind #:frame-conflict-keys #:frame-conflict-known
   #:frame-constrained-row-count #:frame-min-resolved-rows
   #:orient-observations #:transition-probes #:lookup-model #:frame-oracle-table
   #:pullback-frame #:pulled-back-metric #:compose-model #:let-call #:share-repeated-subterms
   #:product-slot-frame #:compose-product-model
   #:lift-frame #:compose-lifted-model #:*max-active-lifted-rows* #:probe-frame-coordinates
   #:conserved-quantity-frame #:support-frame #:context-label-frame #:shuffle-frame-rows
   #:orient-available
   #:partition #:partition-positions #:partition-groups #:partition-rows #:reassemble-partition #:partition-model
   #:partition-pairs-and-anchors #:with-frame-linkage
   #:centered-mod-difference #:correction-packet #:apply-correction-packet
   #:correction-bit-size #:select-closest-witness #:relational-linkage-residual
   #:frame-metric #:metric-inputs #:priced-correction
   #:quotient-values #:restore-quotient #:quotient-model

   ;; 9. enumerate.lisp — Grammars, size-indexed enumerator, bounded search & observation search
   #:language #:make-language #:derive-language #:snapshot-language
   #:language-domain #:language-inputs #:language-operators
   #:language-literals #:language-constants #:language-version
   #:enumerator #:make-enumerator #:enumerator-size #:enumerator-buckets #:enumeration-step
   #:candidate #:make-candidate #:candidate-expression #:candidate-size
   #:candidate-run-work #:candidate-discovery-work
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
   #:search-job #:start-search #:resume-search #:search-job-results #:search-job-best #:search-job-ledger
   #:search-job-completed-bound #:search-job-messages #:search-job-proposals #:search-job-reused-rejections
   #:make-observation-scope #:observation-scope-id #:observation-scope-frame #:observation-scope-language
   #:observation-job #:start-observation-search #:resume-observation-search #:observation-job-records
   #:observation-job-buckets #:observation-job-ledger #:observation-job-completed-bound #:observation-job-messages
   #:find-observation #:observed-agreement-p #:observation-invariants

   ;; 10. unify.lisp — Pattern matching, typed anti-unification, AU constructors
   #:match-pattern #:anti-unify #:au-substitutions-frame #:compile-au-constructor
   #:pattern-has-holes-p #:pattern-holes #:term-sort

   ;; 11. fibers.lisp — Hard-EM fiber clustering & linkage extraction
   #:fiber-class #:fiber-class-p #:fiber-class-id #:fiber-class-requirement
   #:fiber-class-rows #:fiber-class-keys
   #:infer-fibers #:fiber-pairs-and-anchors

   ;; 12. laws.lisp — Algebraic laws, validation, term rewriting, requirement propagation
   #:law-type-p #:finite-type-p #:finite-type-cardinality #:law-assignment #:arithmetic-inputs
   #:make-law #:law-statement
   #:law-validation #:start-law-validation #:resume-law-validation #:law-validation-law
   #:law-validation-status #:law-validation-ledger #:law-validation-counterexample #:law-validation-certificate
   #:propose-observed-laws
   #:rewrite-rule #:rewrite-library #:rewrite-library-p #:rewrite-library-rules #:prepare-rewrite-library
   #:rewriting #:start-rewriting #:advance-rewriting
   #:rewriting-status #:rewriting-value #:rewriting-work #:rewriting-steps
   #:propagator-library #:propagator-library-p
   #:propagation #:propagation-frame #:propagation-original #:propagation-fallback
   #:propagation-narrowed #:propagation-suggested #:propagation-retained
   #:propagation-rejected #:propagation-ambiguous
   #:as-propagator-library #:propagate-requirements
   #:callable-rules-library
   #:solve-equality-symbolically #:target-sensitive-p #:orient-conserved-quantity
   #:as-rewrite-library #:register-knowledge-law
   #:make-knowledge-solver #:register-knowledge-solver
   #:register-metric-decoder #:metric-decoders #:metric-delta

   ;; 13. templates.lisp — Polymorphic retyping, template inference & AST transformations
   #:retype-expr #:retype-law #:retype-knowledge-laws #:retype-function-definition
   #:walk-typed-ast #:infer-function-template #:instantiate-function-template
   #:infer-entry-template #:instantiate-entry-template
   #:learn-knowledge-transformer

   ;; 14. bootstrap-inverters.lisp — Functorial & involution solver induction
   #:induce-functorial-solvers

   ;; 15. condense.lisp — Lossy Stage A heuristic condensation
   #:heuristic-model #:heuristic-model-p #:heuristic-program #:heuristic-residual #:heuristic-packets
   #:heuristic-exact-p #:heuristic-total-p #:heuristic-program-bits #:heuristic-residual-bits
   #:heuristic-run-work #:heuristic-score #:heuristic-alternatives #:heuristic-buckets
   #:heuristic-search #:start-heuristic-search #:resume-heuristic-search
   #:heuristic-search-best #:heuristic-search-ledger
   #:condense-heuristic

   ;; 16. abstraction.lisp — Subterm covers & homoiconic higher-order library discovery
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

   ;; 17. descriptors.lisp — Structural recursion shapes, M9 multi-faceted descriptors & policy scoring
   #:function-body-length-preserving-p #:function-body-pointwise-map-p
   #:compute-function-descriptor
   #:descriptor-clause #:descriptor-clause-p #:make-descriptor-clause
   #:descriptor-clause-id #:descriptor-clause-facet #:descriptor-clause-tier
   #:descriptor-clause-status #:descriptor-clause-weight-bits #:descriptor-clause-work-cost
   #:derive-compositional-name #:compute-entry-descriptor-profile
   #:entry-descriptor-necessary-p #:entry-trigger-compatible-p
   #:score-entry-by-descriptors #:library-function-descriptor-compatible-p
   #:evaluate-frame-descriptors #:frame-addressed-entries

   ;; 18. relations.lisp — Hybrid parametric/lookup relations & delayed residual consolidation
   #:compose-hybrid-residual-program #:register-knowledge-relation #:consolidate-residual-relations

   ;; 19. synthesize.lisp — Anytime hierarchical agenda, decompositions, deferred proposals & CEGAR
   #:*synthesis-debug-mode* #:candidate-score
   #:decomposition #:make-decomposition #:decomposition-name
   #:decomposition-decoder #:decomposition-child-id #:decomposition-child-type
   #:decomposition-bindings #:decomposition-language #:decomposition-bound
   #:decomposition-children #:decomposition-solver #:decomposition-lift-p
   #:decomposition-fallback-p #:decomposition-policy-score #:decomposition-provenance
   #:decomposition-slots #:decomposition-structural-p
   #:synthesis-node #:synthesis-node-id #:synthesis-node-parent #:synthesis-node-proposal
   #:synthesis-node-frame #:synthesis-node-reserve-rows #:synthesis-node-language
   #:synthesis-node-bound #:synthesis-node-priority #:synthesis-node-heuristic
   #:synthesis-node-search #:synthesis-node-deferred-proposals #:synthesis-node-provenance
   #:synthesis-job #:start-synthesis #:resume-synthesis #:synthesis-finished-p
   #:synthesis-job-root #:synthesis-job-nodes #:synthesis-job-best #:synthesis-job-results
   #:synthesis-job-ledger #:synthesis-job-messages #:synthesis-job-debug-p
   #:synthesis-job-nogoods #:synthesis-job-reused-subproblems #:synthesis-job-trace
   #:synthesis-job-self-name #:synthesis-job-oracle-table
   #:promote-next-deferred-proposal #:synthesis-episode-returns
   #:*max-eager-proposals-per-node* #:eager-proposals #:stage-a-budget #:node-price

   ;; 20. nogoods.lisp — Deductive leaf nogoods, UIP generalization & DIP context repair
   #:nogood-clause #:nogood-clause-p #:nogood-clause-parent-id #:nogood-clause-kind
   #:nogood-clause-keys #:nogood-clause-known #:nogood-clause-bindings
   #:nogood-clause-decoder #:nogood-clause-child-id #:nogood-clause-child-type
   #:nogood-clause-parent-incompatible-p #:nogood-clause-clause-expr #:nogood-clause-parent-clause-expr
   #:anti-unify-nogood-clauses #:propose-dip-context-bindings #:dip-repaired-decompositions
   #:register-knowledge-nogood-schema #:register-knowledge-dip-feature

   ;; 21. decompose.lisp — Inductive sequence & heuristic residual expanders
   #:lift-inductive-sequence-context #:combine-expanders
   #:heuristic-decompositions #:heuristic-expander
   #:make-metric-residual-decoder #:metric-residual-decompositions
   #:feature-pair-predicates #:*feature-guard-bits*
   #:start-heuristic-synthesis #:start-recursive-synthesis

   ;; 22. proposals.lisp — Library, partial-application, template & dependency proposal generators
   #:*library-code-argument-bits* #:*library-code-argument-work* #:*library-partial-proposal-limit*
   #:remember-decoder-template #:learned-decoder-decompositions
   #:library-decompositions #:library-expander
   #:dependency-proposals #:dependency-expander #:start-selector-search
   #:*product-arity-limit* #:component-bindings #:structural-decompositions #:structural-expander
   #:canonical-row-order #:induce-row-order #:with-induced-row-order
   #:projection-language #:projection-row-keys #:stored-row-keys
   #:generalize-decoder-templates #:remember-motif-decoder #:decoder-template-live-p

   ;; 23. consolidate.lisp — Trace heuristic learning, specs, solver induction, batteries & consolidation
   #:make-search-trace-frame #:condense-search-heuristic #:register-knowledge-heuristic
   #:make-knowledge-spec #:register-knowledge-spec #:spec-entry-frame
   #:verify-entry-against-spec #:synthesize-spec-entry
   #:induce-law-solvers #:induce-conditional-solver #:induce-conditional-solvers
   #:consolidate-library-functions #:consolidate-policy-descriptors
   #:commit-synthesis-job #:consolidate-knowledge-library #:*consolidation-pass-limit*
   #:lift-field-solvers
   #:induce-fold-motifs #:amortize-library-entries #:*search-weight* #:*archive-epochs*
   #:archive-dependent-templates #:sampled-solver-validations

   ;; 24. messages.lisp — A job's messages as rows of object-language values
   #:define-message-reader #:message-columns #:message-rows #:message-frame

   ;; 25. explain.lisp — Read-only synthesis & library inspection reports
   #:explain-synthesis-node #:explain-synthesis-job #:explain-knowledge-library

   ;; 26. Battery packets (.sexp knowledge libraries in library/)
   #:*battery-directory* #:battery-names #:read-battery #:load-battery))
(in-package #:lisploop)
