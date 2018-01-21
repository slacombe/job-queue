(defpackage :job-queue
  (:use "CL" "SB-THREAD" "SB-EXT")
  (:export :print-object :list-running-jobs :job-retval
	   :add-to-queue :add-job-to-queue :remove-from-queue :list-jobs
	   :start-job-runner :stop-job-runner
	   :notify-queue))

(in-package :job-queue)

(defvar *max-threads* 4)

(defvar *job-runner-thread* nil)
(defvar *job-runner-running* nil)
(defvar *job-queue* nil)
(defvar *job-queue-wait* (make-waitqueue))
(defvar *job-queue-mutex* (make-mutex :name "job queue lock"))
(defvar *job-running* nil)
(defvar *job-running-mutex* (make-mutex :name "job running lock"))

(defclass job ()
  ((job-name :initarg :name)
   (job-fn :initarg :job-fn)
   (job-thread)
   (job-retval)
   (job-callback-fn :initarg :callback-fn)))

(defun create-job (name job-fn callback-fn)
  (make-instance 'job :name name :job-fn job-fn :callback-fn callback-fn))

(defmethod start-job ((job job))
  (let* ((job-fn (slot-value job 'job-fn))
	 (callback-fn (slot-value job 'job-callback-fn))
	 (new-thread
	  (make-thread  #'(lambda ()
			    (let ((retval (funcall job-fn)))
			      (setf (slot-value job 'job-retval) retval)
			      (remove-running-job job)
			      (schedule-jobs)
			      (format t "job finish: ~a - retval = ~a~%"
				      job
				      (slot-value job 'job-retval))
			      (funcall callback-fn job))))))
      (setf (slot-value job 'job-thread) new-thread)
      (add-running-job job)))

(defmethod print-object ((object job) stream)
  (print-unreadable-object (object stream :type t)
    (with-slots (job-name) object
      (format stream "name: ~s" job-name))))

(defun add-to-queue (job-fn name callback-fn)
  (with-mutex (*job-queue-mutex*)
    (let ((new-job (create-job name job-fn callback-fn)))
      (setf *job-queue* (append *job-queue* (list new-job)))
      (condition-notify *job-queue-wait*)
      new-job)))

(defmacro add-job-to-queue (job-fn name callback-fn)
  `(add-to-queue #'(lambda () (,@job-fn)) ,name ,callback-fn))

(defun remove-from-queue ()
  (with-mutex (*job-queue-mutex*)
    (pop *job-queue*)))

(defun list-jobs ()
  (with-mutex (*job-queue-mutex*)
    *job-queue*))

(defun list-running-jobs ()
  (with-mutex (*job-running-mutex*)
    *job-running*))

(defun add-running-job (job)
  (with-mutex (*job-running-mutex*)
    (push job *job-running*)))

(defun remove-running-job (job)
  (with-mutex (*job-running-mutex*)
    (setf *job-running* (remove job *job-running*))))

(defun schedule-jobs ()
  (let ((empty-threads (- *max-threads* (nb-jobs-running))))
    (loop
       for i from 1 to empty-threads do
	 (let ((job (pop *job-queue*)))
	   (if job (progn (start-job job)
			  (format t "running job: ~a~%" job)))))))


(defun run-jobs ()
  (with-mutex (*job-queue-mutex*)
    (setf *job-runner-running* t)
    (format t "Running jobs~%")
    (loop
       (unless *job-runner-running* (return))
       (condition-wait *job-queue-wait* *job-queue-mutex*)
       (schedule-jobs))))
  
(defun nb-jobs-running ()
  (with-mutex (*job-running-mutex*)
    (length *job-running*)))

(defun notify-queue ()
  (with-mutex (*job-queue-mutex*)
    (condition-notify *job-queue-wait*)))

(defun start-job-runner ()
  (format t "Starting job runner thread~%")
  (setf *job-runner-thread* (make-thread #'run-jobs :name "job-runner")))

(defun stop-job-runner ()
  (with-mutex (*job-queue-mutex*)
    (format t "Stopping job runner thread~%")
    (setf *job-runner-running* nil)
    (condition-notify *job-queue-wait*))
  (join-thread *job-runner-thread* :timeout 2000)
  (format t "Job runner thread stopped~%"))
