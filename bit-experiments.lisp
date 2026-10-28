(load (merge-pathnames "load.lisp" *load-truename*))
(load (merge-pathnames "fixtures.lisp" *load-truename*))
(in-package #:lisploop)

(defun bits-ledger (label ledger)
  (format t "~A: work=~D ~S~%" label (ledger-total ledger) (ledger-counts ledger)))

(defun bits-replay (expression frame &optional ledger)
  (multiple-value-bind (decoded inputs)
      (decode-bit-model (encode-bit-model expression (schema-inputs (frame-schema frame))))
    (assert (equal inputs (schema-inputs (frame-schema frame))))
    (loop for row in (frame-rows frame) sum
      (let ((run (evaluate decoded inputs (row-known row) :ledger ledger)))
        (assert (eq :value (evaluation-status run)))
        (let ((check (check-allowed (row-allowed row) (evaluation-value run) :ledger ledger)))
          (assert (and (eq :value (evaluation-status check)) (evaluation-value check))))
        (evaluation-work run)))))

(defun bits-size-report (label expression inputs)
  (let* ((total (bit-description-size expression inputs))
         (header (bit-header-size inputs (expression-type expression inputs))))
    (format t "~A: S=~D bits = ~D header + ~D body; legacy=~D bytes.~%"
            label total header (- total header) (description-size expression))))

(defun bits-syntax-count (job)
  (loop for bucket being the hash-values of (enumerator-buckets (search-job-enumerator job)) sum (length bucket)))

(defun run-bit-m1 ()
  (let ((acquisition (make-ledger)))
    (format t "~%M1 / GF(5) / complete 25-row y=a+2b table.~%")
    (multiple-value-bind (frame oracle records) (gf5-fixture acquisition)
      (let* ((inputs (schema-inputs (frame-schema frame)))
             (language (make-language (gf 5) inputs :cost-model :bits-v2))
             (job (start-search frame language :call-id :m1-bits))
             (header (bit-header-size inputs (gf 5)))
             (bound (language-expression-size language oracle)))
        (assert (eq :cutoff (message-claim (resume-search job (+ header 8) 100))))
        (assert (eq :bounded-exhaustion (message-claim (resume-search job (+ header 8) 1000000))))
        (assert (null (search-job-results job)))
        (format t "No predictor at ~D bits (8-bit body); interrupted and resumed, then extend to ~D bits.~%"
                (+ header 8) bound)
        (assert (eq :bounded-exhaustion (message-claim (resume-search job bound 1000000))))
        (let* ((best (search-job-best job)) (model (candidate-expression best))
               (lookup (lookup-model frame acquisition))
               (targets (lit (sequence-type (gf 5)) (mapcar #'fourth records))))
          (assert (= (candidate-run-work best) (bits-replay model frame acquisition)))
          (format t "Returned ~S; ~D retained syntax, ~D solutions, first accepted at work ~D.~%"
                  model (bits-syntax-count job) (length (search-job-results job))
                  (reduce #'min (search-job-results job) :key #'candidate-discovery-work))
          (bits-size-report "Formula" model inputs)
          (bits-size-report "Packaged executable lookup" lookup inputs)
          (bits-size-report "Literal target sequence (ordered whole-object task)" targets nil)
          (format t "Execution on 25 rows: formula=~D, lookup=~D. Both bit-decode and replay successfully.~%"
                  (candidate-run-work best) (bits-replay lookup frame acquisition))
          ;; Description weights are in bits here; the work tariff stays v1.
          (dolist (weights '((0 0) (1/100 1/1000)))
            (let* ((chosen (first (stable-sort (copy-list (search-job-results job)) #'<
                                               :key (lambda (c) (candidate-score c (first weights))))))
                   (score (candidate-score chosen (first weights))))
              (format t "Weights run/search=~S: J=~,3F; procedure J=~,3F (v2 objective, not v1 unit conversion).~%"
                      weights score (+ score (* (second weights)
                                                 (+ (ledger-total (search-job-ledger job))
                                                    (ledger-total acquisition)))))))
          (bits-ledger "M1 discovery" (search-job-ledger job))
          (bits-ledger "M1 acquisition/baselines/independent replay" acquisition)
          (format t "Evidence: exhaustive finite-domain validation on GF(5); whole-object and function tasks differ.~%"))
        (let* ((bad (make-frame (frame-schema frame)
                                (list (make-row :key 0 :known '(1 1) :allowed (finite-allowed (gf 5) '(0)))
                                      (make-row :key 1 :known '(1 1) :allowed (finite-allowed (gf 5) '(1))))))
               (negative (start-search bad language)))
          (assert (eq :bounded-exhaustion (message-claim (resume-search negative (+ header 8) 1000000))))
          (assert (null (search-job-results negative)))
          (format t "Contradictory-output control: bounded exhaustion with no predictor.~%")))))
  ;; Integer counterpart, enabled by the new unrestricted-literal ordering.
  (let* ((inputs '((0 . :int) (1 . :int))) (acquisition (make-ledger))
         (frame (integer-linear-fixture :ledger acquisition))
         (language (make-language :int inputs :cost-model :bits-v2))
         (job (start-search frame language)) (bound (+ (bit-header-size inputs :int) 13)))
    (format t "~%M1 / integer control / y=a+2b on [-2,2]^2, all integer literals admitted.~%")
    (assert (eq :bounded-exhaustion (message-claim (resume-search job bound 1000000))))
    (let* ((best (search-job-best job)) (model (candidate-expression best))
           (extra (make-ledger))
           (fresh (integer-linear-fixture :starts (integer-held-out-starts) :ledger extra)))
      (bits-size-report "Returned integer formula" model inputs)
      (format t "  ~S; ~D retained syntax, ~D solutions, first accepted at work ~D.~%"
              model (bits-syntax-count job) (length (search-job-results job))
              (reduce #'min (search-job-results job) :key #'candidate-discovery-work))
      (format t "  Training replay work=~D; six fresh signed starts around 2^256: replay work=~D.~%"
              (bits-replay model frame acquisition) (bits-replay model fresh extra))
      (bits-ledger "Integer M1 discovery" (search-job-ledger job))
      (bits-ledger "Integer M1 original generation/orientation/independent replay" acquisition)
      (bits-ledger "Integer M1 fresh generation/orientation/independent replay" extra)
      (format t "  Evidence: replayed observations, not a theorem over integers.~%"))))

(defun run-bit-m2-domain (domain)
  (let ((acquisition (make-ledger)) (field-p (not (eq domain :int))))
    (multiple-value-bind (transitions anchors)
        (if field-p (gf5-transition-fixture :ledger acquisition) (integer-transition-fixture :ledger acquisition))
      (multiple-value-bind (frame pairs) (transition-probes transitions domain acquisition)
        (let* ((inputs (schema-inputs (frame-schema frame)))
               (language (make-language domain inputs :cost-model :bits-v2))
               (sum (app (op :+ domain) (var 0 domain) (var 1 domain)))
               (bound (language-expression-size language sum))
               (job (start-observation-search (make-observation-scope frame language :pairs pairs :anchors anchors))))
          (format t "~%M2 / ~S / unrestricted domain literals / bound ~D bits.~%" domain bound)
          (assert (eq :cutoff (message-claim (resume-observation-search job bound 100))))
          (assert (eq :bounded-exhaustion (message-claim (resume-observation-search job bound 1000000))))
          (let* ((invariants (observation-invariants job))
                 (expressions (mapcar #'observed-expression-expression
                                      (observation-bucket-members (first invariants)))))
            (assert (and (= 1 (length invariants)) (= 2 (length expressions))))
            (format t "~D expressions, ~D buckets; exactly one informative bucket: ~S.~%"
                    (length (observation-job-records job)) (length (observation-job-buckets job)) expressions)
            (bits-size-report "a+b" sum inputs)
            (format t "W_run=~D per returned sum over ~D probes; constants fail variation.~%"
                    (observed-expression-run-work (find-observation job sum)) (length (frame-rows frame)))
            (bits-ledger "M2 discovery" (observation-job-ledger job))
            (bits-ledger "M2 transition generation and orientation" acquisition)
            (loop for shift in (if field-p '(4 3) '(-1 -2)) for positive-p in '(t nil) do
              (let ((extra (make-ledger)))
                (multiple-value-bind (fresh starts)
                    (if field-p
                        (gf5-transition-fixture :starts '((0 2) (0 3) (0 4) (2 0) (2 1) (2 2))
                                                :steps 1 :shift-b shift :ledger extra)
                        (integer-transition-fixture :starts (integer-held-out-starts) :steps 1 :shift-b shift :ledger extra))
                  (multiple-value-bind (probes links) (transition-probes fresh domain extra)
                    (let ((replay (start-observation-search
                                   (make-observation-scope probes language :pairs links :anchors starts)
                                   :expressions (mapcar (lambda (e) (decode-bit-model (encode-bit-model e inputs))) expressions))))
                      (assert (eq :replay-complete (message-claim (resume-observation-search replay bound 1000000))))
                      (assert (eq positive-p (not (null (observation-invariants replay)))))
                      (format t "Fresh six-pair replay, shift=~D: informative invariance ~A; work=~D; acquisition=~D.~%"
                              shift (if positive-p "passes" "fails") (ledger-total (observation-job-ledger replay))
                              (ledger-total extra)))))))
            (when field-p
              (assert (eq :bounded-exhaustion
                          (message-claim (resume-observation-search job (+ (bit-header-size inputs domain) 12) 1000000))))
              (assert (= 105 (length (observation-job-records job))))
              (format t "At 12 body bits, same 105 expressions as legacy 41-byte run; work=~D.~%"
                      (ledger-total (observation-job-ledger job))))))))))

(defun run-bit-split (domain)
  (let* ((inputs (list (cons 0 domain))) (language (make-language domain inputs :cost-model :bits-v2))
         (x (var 0 domain)) (square (app (op :* domain) x x))
         (bound (language-expression-size language square)))
    (flet ((scope (values)
             (make-observation-scope
              (make-frame (make-schema :inputs inputs :target domain)
                          (loop for value in values for key from 0 collect
                            (make-row :key key :known (list value) :allowed (predicate-allowed domain (lit :bool t)))))
              language)))
      (let ((old (start-observation-search (scope '(0 1)))))
        (resume-observation-search old bound 1000000)
        (assert (observed-agreement-p (find-observation old x) (find-observation old square)))
        (let ((new (start-observation-search
                    (scope (if (eq domain :int) (list 0 1 -1 2 (ash 1 256) (1+ (ash 1 256))) '(0 1 2)))
                    :expressions (mapcar #'observed-expression-expression (observation-job-records old)))))
          (resume-observation-search new bound 1000000)
          (assert (not (observed-agreement-p (find-observation new x) (find-observation new square))))
          (format t "Split control ~S: x=x*x on {0,1}, then separate; all ~D syntax retained. Old scope unchanged.~%"
                  domain (length (observation-job-records old))))))))

(let ((mode (second sb-ext:*posix-argv*)) (start (get-internal-real-time)))
  (format t "Bit encoding v2; SBCL ~A; deterministic fixtures; no seed. Work tariff v1 unchanged.~%"
          (lisp-implementation-version))
  (format t "S includes standalone version/schema/type/profile header once; bounds are total bits.~%")
  (format t "No laws, semantic pruning, inverse rules, or restricted integer literal vocabulary.~%")
  (cond ((equal mode "m1") (run-bit-m1))
        ((equal mode "m2") (run-bit-m2-domain (gf 5)) (run-bit-m2-domain :int)
                           (run-bit-split (gf 5)) (run-bit-split :int))
        (t (error "Expected m1 or m2")))
  (format t "Wall seconds (includes fixtures/controls, excludes loading): ~,6F.~%"
          (/ (- (get-internal-real-time) start) (float internal-time-units-per-second 1d0))))
