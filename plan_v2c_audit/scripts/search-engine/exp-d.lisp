;;; EXP-D (v2 only): do the opt-in Stage 0 enumerator flags work, and what do they buy?
;;; Read-only w.r.t. the repository.
(load "/home/tlh24/lisploop/v2/load.lisp")
(in-package #:lisploop)
(clear-knowledge-library)

(defun obs-run (name frame language slack work &rest flags)
  (handler-case
      (let* ((scope (make-observation-scope frame language))
             (job (apply #'start-observation-search scope flags))
             (bound (+ (language-header-size language (schema-target (frame-schema frame))) slack))
             (start (get-internal-real-time))
             (message (resume-observation-search job bound work))
             (wall (/ (- (get-internal-real-time) start) (float internal-time-units-per-second)))
             (syntax (loop for b being the hash-values of (enumerator-buckets (observation-job-enumerator job))
                           sum (length b))))
        (format t "[v2 obs] ~A slack=~D flags=~S: ~A work=~D wall=~,2Fs syntax=~D records=~D buckets=~D~%"
                name slack flags (message-claim message) (ledger-total (observation-job-ledger job)) wall
                syntax (length (observation-job-records job)) (length (observation-job-buckets job)))
        (sort (mapcar (lambda (b) (with-standard-io-syntax
                                    (prin1-to-string (list (observation-bucket-type b)
                                                           (observation-bucket-values b)))))
                      (observation-job-buckets job))
              #'string<))
    (error (c) (format t "[v2 obs] ~A slack=~D flags=~S: ERROR ~A~%" name slack flags c) :error)))

(defun search-run (name frame language slack work &rest flags)
  (handler-case
      (let* ((job (apply #'start-search frame language flags))
             (bound (+ (language-header-size language (schema-target (frame-schema frame))) slack))
             (start (get-internal-real-time))
             (message (resume-search job bound work))
             (wall (/ (- (get-internal-real-time) start) (float internal-time-units-per-second)))
             (syntax (loop for b being the hash-values of (enumerator-buckets (search-job-enumerator job))
                           sum (length b))))
        (format t "[v2 search] ~A slack=~D flags=~S: ~A work=~D wall=~,2Fs syntax=~D rejected=~D results=~D best=~A first-work=~A~%"
                name slack flags (message-claim message) (ledger-total (search-job-ledger job)) wall
                syntax (search-job-rejected job) (length (search-job-results job))
                (and (search-job-best job) (ast->sexp (candidate-expression (search-job-best job))))
                (and (search-job-results job)
                     (reduce #'min (search-job-results job) :key #'candidate-discovery-work))))
    (error (c) (format t "[v2 search] ~A slack=~D flags=~S: ERROR ~A~%" name slack flags c))))

(let* ((in2 '((0 . :int) (1 . :int)))
       (l1 (make-language :int in2 :operators (list (op :+ :int) (op :* :int)) :literals '(0 1)))
       (l2 (make-language :int in2 :operators (list (op :+ :int) (op :* :int) (op :- :int)
                                                    (op :if :int) (op := :int) (op :< :int))
                                :literals '(0 1)))
       (frame (simple-frame :int in2 '(((0 1) 0) ((1 2) 3) ((2 3) 8) ((3 1) 6) ((2 5) 12) ((4 2) 12))))
       ;; (x+y)^2+y : 39 body bits in L1
       (frame2 (simple-frame :int in2 '(((0 1) 2) ((1 2) 11) ((2 3) 28) ((3 1) 17) ((2 5) 54) ((4 2) 38)))))
  (dolist (slack '(26 30))
    (let ((plain (obs-run "L1" frame l1 slack 50000000))
          (pruned (obs-run "L1" frame l1 slack 50000000 :prune-behaviors-p t))
          (both (obs-run "L1" frame l1 slack 50000000 :prune-behaviors-p t :columnar-p t)))
      (format t "   same behaviour set plain/pruned: ~A   plain/pruned+columnar: ~A~%"
              (equal plain pruned) (equal plain both))))
  (dolist (slack '(36 42 48))
    (obs-run "L1" frame l1 slack 400000000 :prune-behaviors-p t :columnar-p t))
  (obs-run "L2" frame l2 24 50000000)
  (obs-run "L2" frame l2 24 50000000 :prune-behaviors-p t :columnar-p t)
  (obs-run "L2" frame l2 36 400000000 :prune-behaviors-p t :columnar-p t)
  ;; exact search for the 39-bit target
  (search-run "L1 (x+y)^2+y" frame2 l1 40 400000000)
  (search-run "L1 (x+y)^2+y" frame2 l1 40 400000000 :prune-behaviors-p t)
  (search-run "L1 (x+y)^2+y" frame2 l1 40 400000000 :prune-behaviors-p t :columnar-p t))
