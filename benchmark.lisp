;;; Bounded scaling measurements; the synthesis kernel is not modified.
;;; Fresh process per search case, for independent process peak-RSS measurements:
;;;   sbcl --dynamic-space-size 2048 --script benchmark.lisp search quadratic 70 30
;;; Arguments: workload (linear/quadratic/quartic), packet-bit bound, wall seconds.
;;; Optional fifth argument "unit" retains one-unit dispatch as a reference;
;;; default "batch" uses batched search. "profile" enables a separate CPU profile.
;;;   sbcl --script benchmark.lisp meter
;;; The meter comparison uses the SAME evaluator/tariff with different work quanta.
(load (merge-pathnames "load.lisp" *load-truename*))
(in-package #:lisploop)

(defvar *benchmark-job* nil)
(defconstant +benchmark-chunk+ 1000000)
(defconstant +benchmark-work-cap+ 10000000000)
(defconstant +benchmark-heap-cap+ (* 768 1024 1024))

(defun benchmark-seconds (ticks)
  (/ ticks (float internal-time-units-per-second 1d0)))

(defun process-memory-kib (key)
  "Linux process memory, including runtime/loading; NIL on other platforms."
  (when (probe-file #P"/proc/self/status")
    (with-open-file (stream #P"/proc/self/status")
      (loop for line = (read-line stream nil) while line
            when (and (>= (length line) (length key))
                      (string= key line :end2 (length key)))
              return (parse-integer line :start (length key) :junk-allowed t)))))

(defun benchmark-frame (workload)
  "Complete GF(5) observations; planted syntax supplies data, never a search sketch."
  (let* ((field (gf 5))
         (inputs (list (cons 0 field) (cons 1 field)))
         (a (var 0 field)) (b (var 1 field))
         (planted (cond ((string= workload "linear") (term `(* 2 ,b)))
                        ((string= workload "quadratic") (term `(* ,b (+ ,b 2))))
                        ((string= workload "quartic") (term `(* (* ,b ,b) (* ,b ,b))))
                        (t (error "Unknown workload ~A" workload))))
         (oracle (term `(+ ,a ,planted)))
         (records (loop for x below 5 append
                    (loop for y below 5 collect
                      (let ((run (evaluate oracle inputs (list x y))))
                        (assert (eq :value (evaluation-status run)))
                        (list (+ (* x 5) y) x y (evaluation-value run)))))))
    (values (orient-observations (list field field field) records '(0 1) '(2))
            (description-size oracle inputs))))

(defun benchmark-search (workload bound seconds &optional quantum)
  (multiple-value-bind (frame oracle-size) (benchmark-frame workload)
    (setf bound (or bound oracle-size))
    (setf *benchmark-job*
          (start-search frame (make-language (gf 5) (schema-inputs (frame-schema frame)))
                        :call-id :scaling))
    (sb-ext:gc :full t)
    (let* ((job *benchmark-job*)
           (initial-live (sb-kernel:dynamic-usage))
           (initial-allocation (sb-ext:get-bytes-consed))
           (initial-gc sb-ext:*gc-run-time*)
           (initial-wall (get-internal-real-time))
           (initial-cpu (get-internal-run-time))
           (status :work-cutoff))
      (loop
        (let* ((work (ledger-total (search-job-ledger job)))
               (outcome (resume-search job bound (min +benchmark-work-cap+
                                                      (+ work +benchmark-chunk+))
                                       :quantum quantum)))
          (when (eq :bounded-exhaustion (message-claim outcome))
            (setf status :complete) (return))
          (when (>= (ledger-total (search-job-ledger job)) +benchmark-work-cap+) (return)))
        (when (>= (benchmark-seconds (- (get-internal-real-time) initial-wall)) seconds)
          (setf status :wall-cutoff) (return))
        (when (>= (sb-kernel:dynamic-usage) +benchmark-heap-cap+)
          (setf status :heap-cutoff) (return)))
      (let* ((wall (benchmark-seconds (- (get-internal-real-time) initial-wall)))
             (cpu (benchmark-seconds (- (get-internal-run-time) initial-cpu)))
             (gc (benchmark-seconds (- sb-ext:*gc-run-time* initial-gc)))
             (allocated (- (sb-ext:get-bytes-consed) initial-allocation))
             (peak-rss (process-memory-kib "VmHWM:"))
             (syntax-count (loop for bucket being the hash-values of
                                 (enumerator-buckets (search-job-enumerator job))
                                 sum (length bucket)))
             (successes (length (search-job-results job)))
             (best (search-job-best job)))
        ;; Measure retained objects after full GC, outside the timed search.
        ;; *BENCHMARK-JOB* keeps every bucket and result rooted during this GC.
        (sb-ext:gc :full t)
        (format t "~&SEARCH workload=~A bound=~D oracle-size=~D status=~S dispatch=~A~%"
                workload bound oracle-size status (if quantum "unit" "batch"))
        (format t "  wall_s=~,6F cpu_s=~,6F gc_cpu_s=~,6F~%" wall cpu gc)
        (format t "  work=~D completed_bound=~D retained_syntax=~D successes=~D rejections=~D~%"
                (ledger-total (search-job-ledger job)) (search-job-completed-bound job)
                syntax-count successes (search-job-rejected job))
        (format t "  allocated_MiB=~,3F live_heap_increment_MiB=~,3F peak_process_RSS_MiB=~,3F~%"
                (/ allocated 1048576d0) (/ (- (sb-kernel:dynamic-usage) initial-live) 1048576d0)
                (if peak-rss (/ peak-rss 1024d0) -1d0))
        (when best
          (format t "  best_bits=~D first_solution_work=~D model=~S~%"
                  (candidate-size best)
                  (reduce #'min (search-job-results job) :key #'candidate-discovery-work)
                  (candidate-expression best)))
        (format t "  ledger=~S~%" (ledger-counts (search-job-ledger job)))
        (format t "  caps: wall_s=~D (checked each ~D units), heap_MiB=768, work=~D~%"
                seconds +benchmark-chunk+ +benchmark-work-cap+)
        (format t "  Timing excludes loading, fixture construction, and final measurement GC.~%")))))

(defun meter-trial (expression quantum repetitions)
  (sb-ext:gc :full t)
  (let ((wall (get-internal-real-time)) (cpu (get-internal-run-time))
        (last-state nil) (last-ledger nil))
    (dotimes (i repetitions)
      (let ((state (start-evaluation expression nil nil)) (ledger (make-ledger)))
        (loop while (eq :unknown (evaluation-status state))
              do (advance-evaluation state quantum ledger))
        (assert (eq :value (evaluation-status state)))
        (setf last-state state last-ledger ledger)))
    (values (/ (benchmark-seconds (- (get-internal-real-time) wall)) repetitions)
            (/ (benchmark-seconds (- (get-internal-run-time) cpu)) repetitions)
            last-state last-ledger)))

(defun benchmark-meter ()
  (format t "~&METER: identical integer multiplications, identical tariff, different VM quanta.~%")
  ;; Enough repetitions to resolve short runs with the platform's wall timer.
  (loop for bits in '(32 256 1024 4096)
        for unit-reps in '(5000 100 10 3)
        for batch-reps in '(100000 40000 10000 1000) do
    (let* ((value (1- (ash 1 bits)))
           (expression (term `(* ,value ,value) :int)))
      (multiple-value-bind (single-wall single-cpu single-state single-ledger)
          (meter-trial expression 1 unit-reps)
        (multiple-value-bind (batch-wall batch-cpu batch-state batch-ledger)
            (meter-trial expression +benchmark-work-cap+ batch-reps)
          (assert (and (= (* value value) (evaluation-value single-state)
                          (evaluation-value batch-state))
                       (= (evaluation-work single-state) (evaluation-work batch-state)
                          (ledger-total single-ledger) (ledger-total batch-ledger))
                       (equal (ledger-counts single-ledger) (ledger-counts batch-ledger))))
          (format t "  bits=~D work=~D one_unit_wall_s=~,9F batched_wall_s=~,9F~%"
                  bits (evaluation-work single-state) single-wall batch-wall)
          (format t "    one_unit_cpu_s=~,9F batched_cpu_s=~,9F reps=~D/~D; result and ledgers agree.~%"
                  single-cpu batch-cpu unit-reps batch-reps))))))

(let* ((arguments (rest sb-ext:*posix-argv*))
       (mode (or (first arguments) "search")))
  (format t "Encoding ~D, tariff ~D; SBCL ~A; seed=none; serial baseline, GF(5) +/* with two inputs.~%"
          +encoding-version+ +tariff-version+ (lisp-implementation-version))
  (cond
    ((string= mode "search")
     (let ((workload (or (second arguments) "linear"))
           (bound (when (third arguments) (parse-integer (third arguments))))
           (seconds (parse-integer (or (fourth arguments) "30")))
           (quantum (if (equal (fifth arguments) "unit") 1 nil)))
       (assert (and (or (null bound) (>= bound 0)) (> seconds 0)))
       (assert (member (fifth arguments) '(nil "unit" "batch" "profile") :test #'equal))
       (if (member "profile" (nthcdr 4 arguments) :test #'equal)
           (progn
             (require :sb-sprof)
             ;; Read only after the profiler package has been loaded.
             (eval (read-from-string
                    (format nil "(sb-sprof:with-profiling (:mode :cpu :sample-interval 0.002 :max-samples 2000 :reset t :report :flat) (benchmark-search ~S ~S ~D ~S))"
                            workload bound seconds quantum))))
           (benchmark-search workload bound seconds quantum))))
    ((string= mode "meter") (benchmark-meter))
    (t (error "Use search [linear|quadratic|quartic] [bit-bound] [wall-seconds] [unit|batch] [profile], or meter"))))
