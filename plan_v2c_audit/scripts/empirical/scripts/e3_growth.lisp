;;;; E3 growth of the canonical enumerator on a plain integer grammar (auditor `empirical`).
;;;;
;;;;   sbcl --dynamic-space-size 3000 --script e3_growth.lisp KERNEL-ROOT GRAMMAR MODE CPU-SECONDS [MAX-SYNTAX]
;;;;
;;;; KERNEL-ROOT : directory holding load.lisp (the scratch copy's root = v1, or its v2/).
;;;; GRAMMAR     : g2 = {+ - *} over 2 :int inputs, literals (0 1)
;;;;               g3 = {+ - * / mod < = if:int} over 3 :int inputs, literals (0 1 2)
;;;; MODE        : exact   = start-search, no pruning (v1 behaviour; every syntax tree kept).
;;;;                         Each new expression's output vector on ALL rows is hashed by this
;;;;                         script (plain `evaluate`, off the ledger, not timed) to count the
;;;;                         observationally distinct behaviours among what was enumerated.
;;;;               prune   = start-search :prune-behaviors-p t :columnar-p t (v2 only): the kernel's
;;;;                         own observational-equivalence pruning; children are distinct behaviours.
;;;;               observe = start-observation-search (what Stage A runs): every candidate is
;;;;                         evaluated on every row and bucketed by behaviour by the kernel.
;;;; One line per completed body-size (bits). Stops at CPU-SECONDS of search or MAX-SYNTAX trees.
(defvar *root* (pathname (second sb-ext:*posix-argv*)))
(load (merge-pathnames "load.lisp" *root*))
(in-package #:lisploop)
(setf *print-pretty* nil)

(defun secs (ticks) (/ ticks (float internal-time-units-per-second 1d0)))

(defparameter *rows-2*
  ;; 10 rows, fixed. The target column is x0^3 - 2*x0*x1 + 7*x1 - 3, far outside the horizon
  ;; reached here, so no candidate is ever accepted and the enumeration is never cut short.
  (loop for (a b) in '((3 -2) (-5 4) (7 1) (2 9) (-8 -3) (6 -7) (1 5) (-4 8) (9 2) (-6 -9))
        collect (list (list a b) (+ (* a a a) (* -2 a b) (* 7 b) -3))))
(defparameter *rows-3*
  (loop for (a b c) in '((3 -2 5) (-5 4 1) (7 1 -6) (2 9 4) (-8 -3 2) (6 -7 -1) (1 5 8) (-4 8 -9) (9 2 3) (-6 -9 7))
        collect (list (list a b c) (+ (* a a a) (* -2 a b c) (* 7 b) (* c c 11) -3))))

(let* ((args (rest sb-ext:*posix-argv*))
       (grammar (third sb-ext:*posix-argv*))
       (mode (fourth sb-ext:*posix-argv*))
       (cpu-cap (parse-integer (fifth sb-ext:*posix-argv*)))
       (max-syntax (if (sixth sb-ext:*posix-argv*) (parse-integer (sixth sb-ext:*posix-argv*)) 4000000))
       (g3-p (string= grammar "g3"))
       (inputs (if g3-p '((0 . :int) (1 . :int) (2 . :int)) '((0 . :int) (1 . :int))))
       (ops (if g3-p
                (list (op :+ :int) (op :- :int) (op :* :int) (op :/ :int) (op :mod :int)
                      (op :< :int) (op := :int) (op :if :int))
                (list (op :+ :int) (op :- :int) (op :* :int))))
       (lits (if g3-p '(0 1 2) '(0 1)))
       (rows (if g3-p *rows-3* *rows-2*))
       (frame (simple-frame :int inputs rows))
       (language (make-language :int inputs :operators ops :literals lits))
       (header (language-header-size language :int))
       (prune-p (string= mode "prune"))
       (observe-p (string= mode "observe"))
       (job (cond (observe-p (start-observation-search (make-observation-scope frame language)))
                  (prune-p (start-search frame language :prune-behaviors-p t :columnar-p t))
                  (t (start-search frame language))))
       (enumerator (row-job-enumerator job))
       (behaviours (make-hash-table :test #'equal))
       (seen-sizes (make-hash-table :test #'equal))
       (cpu 0d0) (prev-syntax 0) (prev-work 0) (prev-beh 0))
  (declare (ignorable args))
  (format t "E3 kernel=~A grammar=~A mode=~A inputs=~D ops=~D (~{~A~^ ~}) literals=~S rows=~D header=~D bits~%"
          cl-user::*root* grammar mode (length inputs) (length ops) (mapcar #'operator-name ops) lits (length rows) header)
  (format t "   bit costs: var=~D lit0=~D lit1=~D ~{~A~^ ~}~%"
          (body-size (var 0 :int) inputs) (body-size (lit :int 0) inputs) (body-size (lit :int 1) inputs)
          (loop for o in ops collect (format nil "~A-overhead=~D" (operator-name o) (application-overhead o))))
  (format t "~4A ~10A ~10A ~12A ~12A ~8A ~8A ~10A ~10A ~9A ~9A ~9A~%"
          "body" "syn_cum" "syn_new" "behav_cum" "work_cum" "w/syn" "x_syn" "x_work" "x_behav" "cpu_s" "work/s" "cand/s")
  (format t "     (prune mode adds: tried = retained + candidates dropped as duplicate behaviours; live_MiB without forced GC)~%")
  (loop for body from 1
        for bound = (+ header body)
        do (let ((c0 (get-internal-run-time)))
             (if observe-p
                 (resume-observation-search job bound most-positive-fixnum)
                 (resume-search job bound most-positive-fixnum))
             (incf cpu (secs (- (get-internal-run-time) c0))))
           (let* ((syntax (loop for b being the hash-values of (enumerator-buckets enumerator) sum (length b)))
                  (work (ledger-total (row-job-ledger job)))
                  (beh
                    (cond (observe-p (length (observation-job-buckets job)))
                          (prune-p (hash-table-count (enumerator-behavior-table enumerator)))
                          (t
                           ;; off-ledger, untimed: hash the output vector of each new expression
                           (maphash (lambda (key bucket)
                                      (unless (gethash key seen-sizes)
                                        (when (= (second key) body)
                                          (setf (gethash key seen-sizes) t)
                                          (loop for expression across bucket
                                                do (setf (gethash
                                                          (cons (first key)
                                                                (loop for (known nil) in rows
                                                                      collect (let ((run (evaluate expression inputs known)))
                                                                                (if (eq :value (evaluation-status run))
                                                                                    (evaluation-value run)
                                                                                    (evaluation-status run)))))
                                                          behaviours)
                                                         t)))))
                                    (enumerator-buckets enumerator))
                           (hash-table-count behaviours)))))
             (when (> syntax prev-syntax)
               (format t "~4D ~10D ~10D ~12D ~12D ~8,1F ~8,3F ~10,3F ~10,3F ~9,2F ~9,0F ~9,0F~%"
                       body syntax (- syntax prev-syntax) beh work
                       (/ work (max 1 syntax) 1d0)
                       (if (plusp prev-syntax) (/ syntax prev-syntax 1d0) 0)
                       (if (plusp prev-work) (/ work prev-work 1d0) 0)
                       (if (plusp prev-beh) (/ beh prev-beh 1d0) 0)
                       cpu (/ work (max cpu 1d-3)) (/ syntax (max cpu 1d-3)))
               (when prune-p
                 (let ((tried (+ syntax (or (cdr (assoc :equality-cache (ledger-counts (row-job-ledger job)))) 0))))
                   (format t "       tried=~D tried/s=~,0F column-cache-entries=~D dyn_MiB=~,0F~%" tried (/ tried (max cpu 1d-3))
                           (hash-table-count (enumerator-column-cache enumerator))
                           (/ (sb-kernel:dynamic-usage) 1048576d0))))
               (finish-output))
             (setf prev-syntax syntax prev-work work prev-beh beh)
             (when (or (> cpu cpu-cap) (> syntax max-syntax))
               (format t "STOP body=~D cpu_s=~,2F syntax=~D work=~D live_MiB=~,1F~%" body cpu syntax work
                       (progn (sb-ext:gc :full t) (/ (sb-kernel:dynamic-usage) 1048576d0)))
               (format t "  ledger=~S~%" (ledger-counts (row-job-ledger job)))
               (return)))))
