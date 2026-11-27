;;;; r1-variants.lisp -- sensitivity of R1 counts to things the review does not state:
;;;; (1) order of the inputs (= leaf creation order) for scan and map-adjacent;
;;;; (2) the level at which the map-adjacent split is accepted, and the impostor's size
;;;;     under three measures.  Loaded after tg-probe-r1.lisp and r1-spec.lisp.
(in-package :tg)

(defun permuted (name order)
  "Task NAME with its inputs (and rows) re-ordered by ORDER (a list of input names)."
  (let* ((task (spec-task name)) (exs (spec-exs name)) (ins (task-ins task))
         (ref (task-ref task)) (names (mapcar #'first ins)))
    (values (tk (format nil "~a ~a" name order)
                (mapcar (lambda (n) (assoc n ins)) order)
                (lambda (&rest args)   ; args arrive in ORDER; call the reference in kernel order
                  (apply ref (mapcar (lambda (n) (nth (position n order) args)) names)))
                (task-out task))
            (mapcar (lambda (ex) (cons (mapcar (lambda (n) (assoc n (car ex))) order) (cdr ex))) exs))))

(defun bank-size (e)
  "Size as the BANK counts it: (len xs) is a leaf of size 1."
  (cond ((atom e) 1) ((eq (car e) 'len) 1) (t (1+ (loop for a in (cdr e) sum (bank-size a))))))

(defun variants ()
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
    (format t "=== input-order sensitivity (default policy; max size 10; 30M) ===~%")
    (dolist (spec '(("scan" (xs a f)) ("scan" (xs f a)) ("scan" (a xs f)) ("scan" (a f xs)) ("scan" (f xs a)) ("scan" (f a xs))
                    ("map-adjacent" (xs f)) ("map-adjacent" (f xs))))
      (multiple-value-bind (task exs) (permuted (first spec) (second spec))
        (dolist (occ (if (string= (first spec) "scan") '(nil) '(nil t)))
          (let ((*occam* occ))
            (destructuring-bind (prog cand cells ms notes scan) (timed (lambda () (solve-task task exs 10 30000000)))
              (declare (ignore cells notes scan))
              (let ((e (elem-of prog)))
                (format t "~28a occam ~3a cand ~9d ms ~5d held-out ~a/200 elem tsize ~d bank-size ~d~%   ~s~%"
                        (task-name task) occ cand ms (held-out task prog) (tsize e) (bank-size e) prog)))))))
    ;; level at which COVER first returns a split for map-adjacent (default policy)
    (format t "~%=== map-adjacent: level at which the split is accepted ===~%")
    (sb-int:encapsulate 'cover 'trace-level
                        (lambda (f bank y rows depth)
                          (let ((r (funcall f bank y rows depth)))
                            (when (= (length rows) (length y))   ; top-level call only
                              (format t "  cover after level ~d (depth ~d, ~d classes, ~d cand so far): ~a~%"
                                      (bank-done bank) depth (length (bank-all bank)) (bank-ncand bank)
                                      (if r (format nil "SPLIT tsize ~d bank-size ~d ~s" (tsize r) (bank-size r) r) "none")))
                            r)))
    (let ((task (spec-task "map-adjacent")) (exs (spec-exs "map-adjacent")))
      (solve-task task exs 10 30000000))
    (sb-int:unencapsulate 'cover 'trace-level)
    (finish-output)))
