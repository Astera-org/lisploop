(defpackage #:lisploop
  (:use #:cl)
  (:export
   ;; 1. ast.lisp — Homoiconic S-expressions, schemas, bidirectional typing, O(1) metadata
   #:gf #:tuple-type #:sequence-type #:code-type #:code-type-p #:code-inputs #:code-sort
   #:valid-type-p #:function-sort-p #:value-p
   #:schema #:make-schema #:copy-schema #:schema-domain #:schema-inputs #:schema-target #:schema-lookup-p
   #:lit #:var #:op #:app #:hole #:bool-not #:bool-and
   #:ast-meta #:ensure-ast-meta #:ast-kind #:ast-id #:ast-type #:ast-value
   #:var-p #:lit-p #:app-p #:hole-p #:operator-p #:operator-name #:operator-type #:operator-operand-type #:application-overhead
   #:expression-type #:free-vars #:provably-total-p #:instantiate #:expression-less-p
   ;; 2. codec.lisp — Prefix-coded binary serialization & O(1) sizes
   #:+encoding-version+ #:header-size #:body-size #:description-size
   #:encode-model #:decode-model
   ;; 3. vm.lisp — Structural tariff, resumable evaluator, constant folding
   #:+tariff-version+ #:+simulator-version+ #:vm-versions
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
   #:orient-observations #:transition-probes #:lookup-model
   #:pullback-frame #:compose-model #:support-frame
   #:partition #:partition-positions #:partition-groups #:partition-rows #:reassemble-partition #:partition-model
   #:quotient-values #:restore-quotient #:quotient-model
   ;; 5. enumerate.lisp — Grammar enumerator, synthesis & observation search, multi-lane propagation search
   #:language #:make-language #:snapshot-language #:language-domain #:language-inputs
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
   #:start-search #:resume-search #:search-job-results #:search-job-best #:search-job-ledger
   #:search-job-completed-bound #:search-job-messages #:search-job-proposals #:search-job-reused-rejections
   #:make-observation-scope #:observation-scope-id #:observation-scope-frame #:observation-scope-language
   #:start-observation-search #:resume-observation-search #:observation-job-records
   #:observation-job-buckets #:observation-job-ledger #:observation-job-completed-bound #:observation-job-messages
   #:find-observation #:observed-agreement-p #:observation-invariants
   ;; 6. factor.lisp — Matching, AU, Hard-EM infer-fibers, corpus compression, heuristic condensation
   #:match-pattern #:anti-unify #:compile-au-constructor #:pattern-has-holes-p #:term-sort
   #:fiber-class #:fiber-class-p #:fiber-class-id #:fiber-class-requirement #:fiber-class-rows #:fiber-class-keys #:infer-fibers
   #:law-corpus #:make-law-corpus #:law-corpus-laws #:law-corpus-packet #:law-corpus-frame
   #:law-template-group #:law-template-group-positions #:law-template-group-pattern #:law-template-group-substitutions
   #:propose-law-compressions #:decode-law-corpus
   #:condense-heuristic #:heuristic-model #:heuristic-model-p
   #:heuristic-program #:heuristic-residual #:heuristic-exact-p #:heuristic-program-bits
   #:heuristic-residual-bits #:heuristic-run-work #:heuristic-score
   ;; 7. laws.lisp — Laws, validation, rewriting, solver discovery, dual-grade propagation
   #:law #:make-law #:law-domain #:law-inputs #:law-lhs #:law-rhs #:law-equation #:law-guard #:law-origin #:law-statement
   #:law-certificate #:law-certificate-evidence #:law-certificate-assignments #:law-certificate-active #:law-certificate-work
   #:law-validation #:start-law-validation #:resume-law-validation #:law-validation-law
   #:law-validation-status #:law-validation-ledger #:law-validation-counterexample #:law-validation-certificate
   #:propose-observed-laws #:retype-law
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
   #:prepare-propagator-library #:match-arithmetic-propagator #:propagate-arithmetic-child
   #:start-propagation-search #:resume-propagation-search #:propagation-search-results
   #:propagation-search-best #:propagation-search-ledger #:propagation-search-first-work))
(in-package #:lisploop)
