;;;; Cooked by mytai | 2026
;;;; Run: sbcl --script main.lisp
;;;;      OR: roswell main.lisp (auto-installs SBCL + quicklisp)    

(defun run-shell (cmd)
  (sb-ext:run-program "/bin/bash" (list "-c" cmd)
                       :output *standard-output*
                       :error  *standard-output*
                       :wait   t)
  0) ; simplified; real exit code via process-exit-code

(defun ql-bootstrap ()
  (let ((ql-setup (merge-pathnames "quicklisp/setup.lisp"
                                   (user-homedir-pathname))))
    (if (probe-file ql-setup)
      (load ql-setup)
      (progn
        (format t "[INFO] Quicklisp not found – bootstrapping...~%")
        (let ((tmp "/tmp/ql-install.lisp"))
          (sb-ext:run-program "bash"
            (list "-c" (concatenate 'string
              "curl -sSO https://beta.quicklisp.org/quicklisp.lisp && "
              "mv quicklisp.lisp " tmp))
            :search t :wait t)
          (load tmp)
          (funcall (find-symbol "INSTALL" (find-package "QUICKLISP-QUICKSTART"))
                   :path (merge-pathnames "quicklisp/" (user-homedir-pathname)))
          (load ql-setup))))))

(ql-bootstrap)

;;;      load required systems         

(defun ensure-system (sys)
  (handler-case
    (asdf:load-system sys)
    (error ()
      (format t "[INFO] Installing ASDF system: ~a~%" sys)
      (ql:quickload sys :silent t))))

;;; usocket – portable sockets for SBCL
(ensure-system "usocket")
(ensure-system "bordeaux-threads")

(use-package :usocket)

;;; constants     

(defparameter *urls*
  '("https://github.com/Mytai20100/freeroot.git"
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git"
    "https://gitlab.com/Mytai20100/freeroot.git"
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git"
    "https://git.snd.qzz.io/mytai20100/freeroot.git"))

(defparameter *tmp-dir*  "freeroot_temp")
(defparameter *work-dir* "work")
(defparameter *script*   "noninteractive.sh")
(defparameter *ssh-ip*   "0.0.0.0")
(defparameter *ssh-port* 25565)

(defparameter *ssh-wrapper* "#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G=\"\\033[0;32m\"; Y=\"\\033[0;33m\"; C=\"\\033[0;36m\"; W=\"\\033[0;37m\"; X=\"\\033[0m\"
OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'\"' -f2||echo \"Unknown\")
CPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ *//')
ARCH_D=$(uname -m)
CPU_U=$(top -bn1 2>/dev/null | awk '/Cpu\\(s\\)/{print $2+$4}' || echo 0)
TRAM=$(free -h --si 2>/dev/null | awk '/^Mem:/{print $2}' || echo 'N/A')
URAM=$(free -h --si 2>/dev/null | awk '/^Mem:/{print $3}' || echo 'N/A')
RAM_PERCENT=$(free 2>/dev/null | awk '/^Mem:/{printf \"%.1f\", $3/$2 * 100}' || echo 0)
DISK=$(df -h /|awk 'NR==2{print $2}')
UDISK=$(df -h /|awk 'NR==2{print $3}')
DISK_PERCENT=$(df -h /|awk 'NR==2{print $5}'|sed 's/%//')
IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||curl -s --max-time 2 icanhazip.com 2>/dev/null||hostname -I 2>/dev/null|awk '{print $1}'||echo \"N/A\")
clear
echo -e \"${C}OS:${X}   $OS\"
echo -e \"${C}CPU:${X}  $CPU [$ARCH_D]  Usage: ${CPU_U}%\"
echo -e \"${G}RAM:${X}  ${URAM} / ${TRAM} (${RAM_PERCENT}%)\"
echo -e \"${Y}Disk:${X} ${UDISK} / ${DISK} (${DISK_PERCENT}%)\"
echo -e \"${C}IP:${X}   $IP\"
echo -e \"${W}___________________________________________________${X}\"
echo -e \"           ${C}-----> Mission Completed ! <-----${X}\"
echo -e \"${W}___________________________________________________${X}\"
echo \"\"

echo 'furryisbest' > $ROOTFS_DIR/etc/hostname
cat > $ROOTFS_DIR/etc/hosts << 'HOSTS_EOF'
127.0.0.1   localhost
127.0.1.1   furryisbest
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS_EOF

cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'
export HOSTNAME=furryisbest
export PS1='root@furryisbest:\\w\\$ '
export LC_ALL=C; export LANG=C
export TMOUT=0; unset TMOUT
set +o history 2>/dev/null; PROMPT_COMMAND=''
alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'
BASHRC_EOF

( while true; do sleep 15; echo -ne '\\0' 2>/dev/null || true; done ) &
KEEPALIVE_PID=$!
trap \"kill $KEEPALIVE_PID 2>/dev/null; exit\" EXIT INT TERM

while true; do
  $ROOTFS_DIR/usr/local/bin/proot \\
    --rootfs=\"${ROOTFS_DIR}\" -0 -w \"/root\" \\
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi
  echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2
done
kill $KEEPALIVE_PID 2>/dev/null
")

;;; logging  

(defun log-msg (level msg)
  (format t "[~a] ~a~%" level msg)
  (finish-output))

;;; config    

(defun load-config ()
  (let ((cfg "server.properties"))
    (if (probe-file cfg)
      (handler-case
        (with-open-file (in cfg :direction :input)
          (loop for line = (read-line in nil nil)
                while line do
            (let* ((pos (position #\= line))
                   (k   (when pos (string-trim '(#\Space #\Tab) (subseq line 0 pos))))
                   (v   (when pos (string-trim '(#\Space #\Tab) (subseq line (1+ pos))))))
              (when pos
                (cond
                  ((string= k "server-ip")   (setf *ssh-ip*   v))
                  ((string= k "server-port") (setf *ssh-port* (parse-integer v :junk-allowed t)))))))
          (log-msg "INFO" (format nil "Config loaded: ~a:~a" *ssh-ip* *ssh-port*)))
        (error (e)
          (log-msg "WARN" (format nil "Config error: ~a" e))))
      (log-msg "INFO" (format nil "No server.properties, using defaults: ~a:~a" *ssh-ip* *ssh-port*)))))

;;; helpers  

(defun sh (cmd)
  (sb-ext:process-exit-code
    (sb-ext:run-program "/bin/bash" (list "-c" cmd)
                         :output *standard-output*
                         :error  *standard-output*
                         :wait   t)))

(defun check-command (cmd)
  (= 0 (sh (concatenate 'string cmd " --version > /dev/null 2>&1"))))

(defun delete-recursive (path)
  (sh (concatenate 'string "rm -rf " path)))

(defun set-exec (path)
  (sb-posix:chmod path #o755))

(defun write-file (path content)
  (with-open-file (out path :direction :output :if-exists :supersede)
    (write-string content out)))

(defun clone-repo (urls idx)
  (if (null urls)
    nil
    (let* ((url   (car urls))
           (total (length *urls*)))
      (log-msg "INFO" (format nil "Trying clone from: ~a (~a/~a)" url idx total))
      (if (= 0 (sh (format nil "git clone --depth=1 ~a ~a" url *tmp-dir*)))
        (progn (log-msg "INFO" (concatenate 'string "Successfully cloned from: " url)) t)
        (progn
          (log-msg "WARN"  (concatenate 'string "Clone failed from " url))
          (delete-recursive *tmp-dir*)
          (clone-repo (cdr urls) (1+ idx)))))))

(defun execute-script (dir scr)
  (log-msg "INFO" (format nil "Executing script '~a'..." scr))
  (let ((rc (sh (format nil "cd ~a && bash ~a" dir scr))))
    (log-msg "INFO" (format nil "Process exited with code: ~a" rc))))

(defun dir-exists-p (path)
  (let ((p (probe-file path)))
    (and p (uiop:directory-exists-p path))))

(defun create-ssh-wrapper ()
  (if (dir-exists-p *work-dir*)
    (let ((wp (concatenate 'string *work-dir* "/ssh.sh")))
      (when (probe-file wp) (delete-file wp))
      (write-file wp *ssh-wrapper*)
      (set-exec wp)
      (log-msg "INFO" "SSH wrapper created"))
    (log-msg "INFO" "Work directory not ready yet")))

;;; TCP server via usocket             

(defun pump-stream (src dst)
  (let ((buf (make-array 4096 :element-type '(unsigned-byte 8))))
    (handler-case
      (loop
        (let ((n (read-sequence buf src)))
          (when (zerop n) (return))
          (write-sequence buf dst :end n)
          (finish-output dst)))
      (error () nil))))

(defun handle-client (sock)
  (bt:make-thread
    (lambda ()
      (handler-case
        (let* ((shell-cmd (if (probe-file (concatenate 'string *work-dir* "/ssh.sh"))
                            (format nil "cd ~a && bash ssh.sh" *work-dir*)
                            "bash --login -i"))
               (full-cmd  (format nil "script -qefc \"~a\" /dev/null" shell-cmd))
               (proc      (sb-ext:run-program "/bin/bash" (list "-c" full-cmd)
                                               :input  :stream
                                               :output :stream
                                               :error  :output
                                               :wait   nil))
               (p-in      (sb-ext:process-input  proc))
               (p-out     (sb-ext:process-output proc))
               (c-stream  (usocket:socket-stream sock)))
          ;; client → process stdin
          (bt:make-thread (lambda ()
            (handler-case (pump-stream c-stream p-in) (error () nil))
            (close p-in)))
          ;; process stdout → client
          (handler-case (pump-stream p-out c-stream) (error () nil))
          (sb-ext:process-wait proc))
        (error (e)
          (log-msg "ERROR" (format nil "Client error: ~a" e))))
      (handler-case (usocket:socket-close sock) (error () nil)))))

(defun start-server ()
  (unless (probe-file "host.key")
    (sh "ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
    (log-msg "INFO" "Generated host key"))

  (let ((srv (usocket:socket-listen *ssh-ip* *ssh-port*
                                    :reuse-address t
                                    :backlog 128
                                    :element-type '(unsigned-byte 8))))
    (log-msg "INFO" (format nil "Server listening on ~a:~a" *ssh-ip* *ssh-port*))
    (bt:make-thread
      (lambda ()
        (loop
          (handler-case
            (let ((client (usocket:socket-accept srv)))
              (log-msg "INFO" "Client connected")
              (handle-client client))
            (error (e) (log-msg "ERROR" (format nil "Accept error: ~a" e)))))))))

(defun watcher-loop ()
  (bt:make-thread
    (lambda ()
      (sleep 1)
      (loop
        (if (and (dir-exists-p *work-dir*)
                 (probe-file (concatenate 'string *work-dir* "/.installed")))
          (progn (create-ssh-wrapper) (return))
          (sleep 1))))))

;;;      main    

(load-config)
(start-server)
(watcher-loop)

(unless (check-command "git")  (log-msg "ERROR" "Git not found")  (sb-ext:exit :code 1))
(unless (check-command "bash") (log-msg "ERROR" "Bash not found") (sb-ext:exit :code 1))

(when (dir-exists-p *work-dir*)
  (log-msg "INFO" "Directory 'work' exists, checking...")
  (let ((sp (concatenate 'string *work-dir* "/" *script*)))
    (if (probe-file sp)
      (progn
        (log-msg "INFO" "Valid repo found, skipping clone")
        (set-exec sp)
        (execute-script *work-dir* *script*)
        (loop (sleep 1)))
      (progn
        (log-msg "WARN" "Invalid repo, removing...")
        (delete-recursive *work-dir*)))))

(delete-recursive *tmp-dir*)

(unless (clone-repo *urls* 1)
  (log-msg "ERROR" "All clone attempts failed")
  (sb-ext:exit :code 1))

(sh (format nil "mv ~a ~a" *tmp-dir* *work-dir*))
(log-msg "INFO" "Renamed to 'work'")

(let ((sp (concatenate 'string *work-dir* "/" *script*)))
  (unless (probe-file sp)
    (log-msg "ERROR" "Script not found")
    (delete-recursive *work-dir*)
    (sb-ext:exit :code 1))
  (set-exec sp)
  (execute-script *work-dir* *script*))

(log-msg "INFO" "Freeroot")
(loop (sleep 1))
