;;; x1-memory.lisp -- retained memory of one observation job, measured in a fresh process.
;;; Environment: X1_V1, X1_OUT as for x1-baseline.lisp;
;;; X1_CFG = "(name nvars ops literals slack work-limit copies)".
;;; Method: live dynamic-space bytes after two full collections, before the jobs exist and
;;; again while they are still reachable. The difference, divided by the number of identical
;;; jobs held (COPIES), is what one job keeps alive, including the kernel's global per-node
;;; table (*node-meta*) that the job's terms populate. Small jobs are measured with many
;;; copies because one copy is below the resolution of the method.
(load (concatenate 'string (sb-ext:posix-getenv "X1_V1") "/load.lisp"))
(load (concatenate 'string (sb-ext:posix-getenv "X1_OUT") "/x1-lib.lisp"))
(in-package #:lisploop)

(defvar *keep* nil)

(defun settled-bytes ()
  (sb-sys:scrub-control-stack)
  (live-bytes))

(declaim (notinline warm-up build-jobs))
(defun warm-up (domain inputs ops lits)
  "A 12-record job, so that one-time allocations are not counted."
  (resume-observation-search (make-obs domain inputs ops lits) (header-bound inputs domain 14) 1000000000)
  nil)

(defun build-jobs (copies domain inputs ops lits bound work)
  (setf *keep*
        (loop repeat copies
              collect (let ((job (make-obs domain inputs ops lits)))
                        (resume-observation-search job bound work)
                        job)))
  nil)

(declaim (notinline job-stats keep-enumerators-only))
(defun job-stats ()
  (let ((job (first *keep*)))
    (list (enumerator-tree-count (observation-job-enumerator job))
          (length (observation-job-records job))
          (length (observation-job-buckets job))
          (length (frame-rows (observation-job-frame job))))))

(defun keep-enumerators-only ()
  (setf *keep* (mapcar #'observation-job-enumerator *keep*))
  nil)

(let ((cfg (let ((*package* (find-package '#:lisploop)))
             (read-from-string (sb-ext:posix-getenv "X1_CFG")))))
  (destructuring-bind (name nvars ops lits slack work copies) cfg
    (let* ((domain (gf 3)) (inputs (make-inputs nvars domain))
           (bound (header-bound inputs domain slack)))
      (warm-up domain inputs ops lits)
      (clrhash *closures*)
      (let ((b0 (settled-bytes)))
        (build-jobs copies domain inputs ops lits bound work)
        (destructuring-bind (trees records classes rows) (job-stats)
         (let* (
               (b1 (settled-bytes))
               (b2 (progn (clrhash *closures*) (settled-bytes)))
               ;; Keep only each enumerator's own store of trees, dropping the observation
               ;; records, their value lists, the record index and the classes.
               (b3 (progn (keep-enumerators-only) (settled-bytes)))
               (b4 (progn (setf *keep* nil) (settled-bytes))))
          (flet ((per (bytes n) (/ bytes (* copies (max 1 n)) 1.0)))
            (format t "~&MEM ~A slack=~D limit=~D copies=~D rows=~D trees=~D records=~D classes=~D ~
                       bytes-per-job: with-closure-cache=~D job=~D enumerator-only=~D after-release=~D ; ~
                       per-tree(job)=~,1F per-tree(enumerator-only)=~,1F per-class(job)=~,1F~%"
                    name slack work copies rows trees records classes
                    (round (- b1 b0) copies) (round (- b2 b0) copies) (round (- b3 b0) copies)
                    (round (- b4 b0) copies)
                    (per (- b2 b0) trees) (per (- b3 b0) trees) (per (- b2 b0) classes)))))))))
