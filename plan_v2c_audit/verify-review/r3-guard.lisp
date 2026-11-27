;;;; r3-guard.lisp -- verify-review R3.  Loaded after the UNMODIFIED tg-probe.lisp (only its EV is used,
;;;; to evaluate the guard term in the probe's own semantics).  No randomness.
(in-package :tg)

(defun fdiv (a b) (values (floor a b)))
(defun tdiv (a b) (values (truncate a b)))

(defun r3-mul (&key (n 20) (big 2000))
  "c = a*b solved for a.  Brute force: #{a in [-BIG,BIG] : a*b = c}.  For b/=0 every solution has
   |a| <= |c| <= N, so the window is complete; for b=0,c=0 every a is a solution (count = 2*BIG+1)."
  (format t "=== R3a. guard for inverting c = a*b for a, all (b,c) in [-~d,~d]^2 = ~d pairs ===~%" n n (expt (1+ (* 2 n)) 2))
  (let ((prog '(and (not (= b 0)) (= (* (div c b) b) c))))
    (dolist (div (list (cons "floor" #'fdiv) (cons "truncate" #'tdiv)))
      (let ((pairs 0) (truth-1 0) (fp 0) (fn 0) (wit-bad 0) (uniq-only-fp 0) (uniq-only-fn 0)
            (n0 0) (nmany 0))
        (loop for b from (- n) to n do
          (loop for c from (- n) to n do
            (let* ((sols (loop for a from (- big) to big when (= (* a b) c) collect a))
                   (unique (= 1 (length sols)))
                   (guard (and (/= b 0) (= (* (funcall (cdr div) c b) b) c)))   ; short-circuit AND
                   (uniq-only (/= b 0)))
              (incf pairs)
              (when unique (incf truth-1))
              (when (null sols) (incf n0))
              (when (cdr sols) (incf nmany))
              (when (and guard (not unique)) (incf fp))
              (when (and unique (not guard)) (incf fn))
              (when (and uniq-only (not unique)) (incf uniq-only-fp))
              (when (and unique (not uniq-only)) (incf uniq-only-fn))
              (when (and guard (/= (funcall (cdr div) c b) (first sols))) (incf wit-bad)))))
        (format t "~8a division: pairs ~d | exactly-one-a ~d, no a ~d, many a ~d | guard false-positives ~d, false-negatives ~d, wrong witness on guard-true ~d~%"
                (car div) pairs truth-1 n0 nmany fp fn wit-bad)
        (format t "~8a           uniqueness guard alone (not (= b 0)): false-positives ~d, false-negatives ~d~%"
                "" uniq-only-fp uniq-only-fn)))
    ;; the same term in the probe's own evaluator (floor DIV, strict AND: any :err argument gives :err)
    (let ((tt 0) (ff 0) (err 0) (bad 0))
      (loop for b from (- n) to n do
        (loop for c from (- n) to n do
          (let ((v (ev prog (list (cons 'b b) (cons 'c c))))
                (unique (and (/= b 0) (zerop (mod c b)))))
            (case v (:t (incf tt)) (:f (incf ff)) (t (incf err)))
            (unless (eq (eq v :t) unique) (incf bad)))))
      (format t "probe EV of ~s: :t ~d, :f ~d, :err ~d; disagreements of (value = :t) with exactly-one-a: ~d~%"
              prog tt ff err bad)
      (format t "  (the ~d :err cells are the b = 0 column: the probe's AND is strict, so (div c 0) = :err poisons it;~%   the guard is exact as written only if :err is read as false, or AND short-circuits)~%" err))))

(defun r3-div (&key (n 20) (big 3000))
  "div(a,b) = c solved for b.  Brute force over b in [-BIG,BIG], b /= 0."
  (format t "~%=== R3b. div(a,b) = c solved for b, all (a,c) in [-~d,~d]^2; b searched in [-~d,~d] minus 0 ===~%" n n big big)
  (dolist (div (list (cons "floor" #'fdiv) (cons "truncate" #'tdiv)))
    (format t "~a: 10/4 = ~d, 10/5 = ~d~%" (car div) (funcall (cdr div) 10 4) (funcall (cdr div) 10 5))
    (let ((h (make-hash-table :test 'equal)) (on-image 0) (inj 0))
      (loop for a from (- n) to n do
        (loop for c from (- n) to n do
          (let* ((k (count-if (lambda (b) (and (/= b 0) (= c (funcall (cdr div) a b))))
                              (loop for b from (- big) to big collect b)))
                 (cls (cond ((= k 0) :none) ((= k 1) :one) (t :many)))
                 (g (< (abs a) (* c (+ c 1)))))
            (when (> k 0) (incf on-image) (when (= k 1) (incf inj)))
            (incf (gethash (list g cls) h 0)))))
      (format t "  (a,c) pairs on the image (some b exists): ~d; of these with exactly one b: ~d (~,1f%)~%"
              on-image inj (* 100.0 (/ inj on-image)))
      (format t "  reviewer's guard |a| < c(c+1) against #b:  guard-true: none ~d, one ~d, many ~d | guard-false: none ~d, one ~d, many ~d~%"
              (gethash '(t :none) h 0) (gethash '(t :one) h 0) (gethash '(t :many) h 0)
              (gethash '(nil :none) h 0) (gethash '(nil :one) h 0) (gethash '(nil :many) h 0))))
  (format t "~%--- :spec/solve-/-1 rows (bootstrap/build-batteries.lisp:234-235): inputs (a c) -> b ---~%")
  (dolist (row '(((12 4) 3) ((15 3) 5) ((-12 3) -4) ((0 4) :none) ((12 0) :none) ((0 0) :none)))
    (destructuring-bind ((a c) b) row
      (flet ((pre (f) (let ((s (loop for bb from -200 to 200 when (and (/= bb 0) (= c (funcall f a bb))) collect bb)))
                        (if (> (length s) 6) (format nil "~d solutions in [-200,200]" (length s)) s))))
        (format t "  a=~3d c=~2d spec b=~5a exact multiple (b*c = a): ~3a  preimages truncate (kernel /): ~a   floor: ~a~%"
                a c b (if (integerp b) (if (= (* b c) a) "yes" "NO") "-") (pre #'tdiv) (pre #'fdiv))))))

(defun r3 ()
  (let ((*package* (find-package :tg)) (*print-pretty* nil) (*print-case* :downcase))
    (r3-mul) (r3-div) (finish-output)))
