# job-queue
;;; job-queue is a simple thread manager that I wrote to play with lisp.
;;; I love playing with this.
;;;
;;; To try it
;;;
;;; First load job-queue.

(load "job-queue.lisp")

;; Then start the job runner

(job-queue:start-job-runner)

;; The runner will wait until a job is added to the queue.

;; Lets declare some code to run.
(defun divisible-by (number divisor)
  (= (mod number divisor) 0))

(defun is-prime? (number)
  (cond ((evenp number) nil)
	((< number 8) t)
	(t (loop for i from 2 to (sqrt number)
	      never (divisible-by number i)))))

(defun count-primes (start end)
  (loop for i from start to end when (is-prime? i) count i))

(defun callback-fn (job)
  (format t "job: ~a, retval: ~a~%" job (slot-value job 'job-queue:job-retval)))

;; Then add a new job.
(job-queue:add-job-to-queue (count-primes 1 2999999) "1 to 2999999" #'callback-fn)

;; You can add as many that you want, the runner will start a new thread for each of them.
(job-queue:add-job-to-queue (count-primes  3000000 6999999) "3000000 to 6999999" #'callback-fn)
