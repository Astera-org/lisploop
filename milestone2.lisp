(load (merge-pathnames "load.lisp" *load-truename*))
(load (merge-pathnames "fixtures.lisp" *load-truename*))
(in-package #:lisploop)

(defun m2-outcome (message)
  (let ((evidence (message-evidence message)))
    (format t "  call=~S ~S; bound=~D, completed=~D, work=~D, coverage=~S~%"
            (message-call-id message) (message-claim message)
            (getf evidence :description-limit) (getf evidence :completed-bound)
            (getf evidence :work) (getf evidence :syntax-coverage))))

(defun m2-ledger (label ledger)
  (format t "~A: ~D ~S~%" label (ledger-total ledger)
          (sort (copy-tree (ledger-counts ledger)) #'string< :key (lambda (x) (symbol-name (car x))))))

(defun m2-bucket (job expression)
  (find-if (lambda (bucket)
             (find expression (observation-bucket-members bucket)
                   :key #'observed-expression-expression :test #'equal))
           (observation-job-buckets job)))

(defun m2-probe-frame (values)
  (let ((field (gf 5)))
    (make-frame (make-schema :inputs (list (cons 0 field)) :target field)
                (loop for value in values for key from 0 collect
                  (make-row :key key :known (list value)
                            :allowed (predicate-allowed field (lit :bool t)))))))

(let ((start (get-internal-real-time)) (generation (make-ledger)) (orientation (make-ledger)))
  (format t "lisploop / plan4 milestone 2 / empirical observations, simulator and encoding v1~%")
  (format t "SBCL ~A; fixed fixtures, no random seed. Grammar: GF(5), a, b, literals, +, *.~%"
          (lisp-implementation-version))
  (format t "Description limit 41 bytes; work ceiling 1,000,000 per job, with an intentional cutoff.~%")
  (format t "Evidence stays REPLAYED OBSERVATIONS; no laws, rewrites, inverse rules, or pruning.~2%")
  (multiple-value-bind (transitions anchors) (gf5-transition-fixture :ledger generation)
    (format t "Forward observations T(a,b)=(a+1,b+4), five transitions from each of (0,0), (0,1):~%")
    (dolist (row (frame-rows transitions))
      (format t "  ~S: ~S -> ~S~%" (row-key row) (row-known row) (first (allowed-values (row-allowed row)))))
    (multiple-value-bind (frame pairs) (transition-probes transitions (gf 5) orientation)
      (let* ((language (make-language (gf 5) (schema-inputs (frame-schema frame))))
             (scope (make-observation-scope frame language :id :m2-training :pairs pairs :anchors anchors))
             (job (start-observation-search scope)))
        (format t "Frame/view: 20 input probes, retaining before/after occurrence keys and their 10 pair links.~%")
        (format t "Known inputs are only (a,b). Start anchors ~S stay outside those inputs.~%" anchors)
        (format t "Proposal: enumerate h; require h(before)=h(after) and different values at the two starts.~%")
        (format t "Child/assembled decoder: none. This seeks an informative observable, not a reconstruction.~%")
        (let ((cutoff (resume-observation-search job 41 100)))
          (assert (eq :cutoff (message-claim cutoff)))
          (m2-outcome cutoff))
        (let ((complete (resume-observation-search job 41 1000000)))
          (assert (eq :bounded-exhaustion (message-claim complete)))
          (m2-outcome complete))
        (let* ((invariants (observation-invariants job))
               (members (reverse (observation-bucket-members (first invariants))))
               (expressions (mapcar #'observed-expression-expression members))
               (constant (find-observation job (lit (gf 5) 0))))
          (assert (and (= 1 (length invariants)) (= 2 (length members))))
          (format t "~%~D expressions retained in ~D typed output buckets; one informative invariant bucket.~%"
                  (length (observation-job-records job)) (length (observation-job-buckets job)))
          (dolist (record members)
            (format t "  Returned ~S; S=~D bytes; W_run=~D over 20 probes.~%"
                    (observed-expression-expression record)
                    (description-size (observed-expression-expression record))
                    (observed-expression-run-work record)))
          (format t "  Shared vector (before/after for each transition): ~S~%"
                  (observed-expression-values (first members)))
          (format t "Baseline constant 0: S=11; W_run=~D; invariant but fails variation between starts.~%"
                  (observed-expression-run-work constant))
          (format t "The baseline and all alternate syntax remain stored. Buckets change no search decisions.~%")
          (m2-ledger "Discovery W_search" (observation-job-ledger job))
          (m2-ledger "Original transition generation" generation)
          (m2-ledger "Probe reorientation (no simulator rerun)" orientation)
          (format t "Discovery plus original acquisition: ~D units.~%"
                  (+ (ledger-total (observation-job-ledger job)) (ledger-total generation) (ledger-total orientation)))
          ;; Later questions can still read the original recorded transitions.
          (let ((reuse (make-ledger)))
            (transition-probes transitions (gf 5) reuse)
            (assert (null (assoc :simulation (ledger-counts reuse))))
            (m2-ledger "Separate reuse control, original 10 transitions retained" reuse))
          (loop for shift in '(4 3) for label in '(:m2-fresh :m2-changed-transition) do
            (let ((extra (make-ledger)))
              (multiple-value-bind (fresh-transitions fresh-anchors)
                  (gf5-transition-fixture :starts '((0 2) (0 3) (0 4) (2 0) (2 1) (2 2))
                                          :steps 1 :shift-b shift :key-prefix label :ledger extra)
                (assert (every (lambda (row)
                                 (not (member (row-known row) (frame-rows transitions)
                                              :key #'row-known :test #'equal)))
                               (frame-rows fresh-transitions)))
                (multiple-value-bind (fresh-frame fresh-pairs) (transition-probes fresh-transitions (gf 5) extra)
                  (let* ((fresh-scope (make-observation-scope fresh-frame language :id label
                                                             :pairs fresh-pairs :anchors fresh-anchors))
                         (fresh (start-observation-search
                                 fresh-scope :expressions
                                 (mapcar (lambda (expression)
                                           (read-model (canonical-string expression) (language-inputs language)))
                                         expressions))))
                    (format t "~%Fresh replay ~S: six unseen source states, b shift=~D.~%" label shift)
                    (m2-outcome (resume-observation-search fresh 41 1000000))
                    (if (= shift 4)
                        (progn
                          (assert (= 1 (length (observation-invariants fresh))))
                          (format t "  Both returned expressions pass all six transition pairs and vary across starts.~%"))
                        (progn
                          (assert (null (observation-invariants fresh)))
                          (format t "  Both fail invariance; counterexample ~S~%"
                                  (observation-bucket-counterexample (m2-bucket fresh (first expressions))))))
                    (format t "  New scope; these observations cannot upgrade the old evidence to a universal law.~%")
                    (m2-ledger "  Replay work" (observation-job-ledger fresh))
                    (m2-ledger "  Fresh acquisition and orientation" extra))))))))))
  (let* ((field (gf 5)) (language (make-language field (list (cons 0 field))))
         (x (var 0 field)) (square (app (op :* field) x x))
         (old (start-observation-search (make-observation-scope (m2-probe-frame '(0 1)) language :id :m2-ambiguous))))
    (format t "~%Accidental-agreement control: enumerate on x in {0,1}, then recheck retained syntax on {0,1,2}.~%")
    (m2-outcome (resume-observation-search old 41 1000000))
    (assert (observed-agreement-p (find-observation old x) (find-observation old square)))
    (let ((new (start-observation-search
                (make-observation-scope (m2-probe-frame '(0 1 2)) language :id :m2-extended)
                :expressions (mapcar #'observed-expression-expression (observation-job-records old)))))
      (m2-outcome (resume-observation-search new 41 1000000))
      (assert (not (observed-agreement-p (find-observation new x) (find-observation new square))))
      (format t "  Old scope: x and x*x share ~S; old evidence remains unchanged.~%"
              (observed-expression-values (find-observation old x)))
      (format t "  New scope: x -> ~S, x*x -> ~S; now in separate buckets.~%"
              (observed-expression-values (find-observation new x))
              (observed-expression-values (find-observation new square)))
      (format t "  All ~D expressions survive: ~D old buckets, ~D new buckets. No syntax is discarded.~%"
              (length (observation-job-records old)) (length (observation-job-buckets old))
              (length (observation-job-buckets new)))
      (m2-ledger "  Ambiguous discovery" (observation-job-ledger old))
      (m2-ledger "  Expanded-scope replay" (observation-job-ledger new))))
  (format t "~%Conclusion: useful observed invariance and accidental agreement are retained with explicit scopes.~%")
  (format t "No compression or speedup claim. Milestones 3 (laws) and 4 (inverse learning) are not executed.~%")
  (format t "Wall time: ~,3F s including fixture generation and controls; excludes loading.~%"
          (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
