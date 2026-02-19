#!/usr/bin/env guile
!#
;;; Cooked by mytai | 2026
;;; Run: guile main.scm  OR  chmod +x main.scm && ./main.scm


(use-modules (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 regex)
             (ice-9 threads)
             (rnrs io ports)
             (web server)
             (srfi srfi-1))

;;; auto-install       

(define (run-shell cmd)
  (system cmd))

(define (cmd-ok? cmd)
  (= 0 (system (string-append cmd " --version > /dev/null 2>&1"))))

(define (check-and-install-deps)
  ;; Ensure guile is installed (we're running, but check for guild/guild)
  (unless (cmd-ok? "guile")
    (display "[INFO] guile not found – installing via apt...\n")
    (run-shell "apt-get install -y guile-3.0 2>/dev/null || \
                yum install -y guile 2>/dev/null || \
                apk add --no-cache guile 2>/dev/null || true"))
  ;; guile modules needed – add to this list; install via guild or system pkg
  (let ((needed '()))   ; e.g. '("guile-json")
    (for-each (lambda (mod)
      (let ((rc (system (string-append "guile -c '(use-modules (" mod "))' > /dev/null 2>&1"))))
        (unless (= 0 rc)
          (format #t "[INFO] Installing guile module: ~a~%" mod)
          (run-shell (string-append "guild install " mod " 2>/dev/null || \
                                    apt-get install -y guile-" mod " 2>/dev/null || true")))))
      needed)))

;;; constants     

(define *urls*
  '("https://github.com/Mytai20100/freeroot.git"
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git"
    "https://gitlab.com/Mytai20100/freeroot.git"
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git"
    "https://git.snd.qzz.io/mytai20100/freeroot.git"))

(define *tmp-dir*  "freeroot_temp")
(define *work-dir* "work")
(define *script*   "noninteractive.sh")

(define *ssh-wrapper* "#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G=\"\\033[0;32m\"; Y=\"\\033[0;33m\"; R=\"\\033[0;31m\"
C=\"\\033[0;36m\"; W=\"\\033[0;37m\"; X=\"\\033[0m\"
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

(define *ssh-ip*   "0.0.0.0")
(define *ssh-port* 25565)

;;; logging  

(define (log-msg level msg)
  (format #t "[~a] ~a~%" level msg)
  (force-output))

;;; config    

(define (load-config)
  (let ((cfg "server.properties"))
    (if (file-exists? cfg)
      (catch #t
        (lambda ()
          (call-with-input-file cfg
            (lambda (port)
              (let loop ((line (read-line port)))
                (unless (eof-object? line)
                  (let* ((parts (string-split line #\=))
                         (k     (if (> (length parts) 0) (string-trim-right (string-trim (car parts))) ""))
                         (v     (if (> (length parts) 1) (string-trim-right (string-trim (cadr parts))) "")))
                    (cond
                      ((string=? k "server-ip")   (set! *ssh-ip* v))
                      ((string=? k "server-port") (set! *ssh-port* (string->number v)))))
                  (loop (read-line port))))))
          (log-msg "INFO" (format #f "Config loaded: ~a:~a" *ssh-ip* *ssh-port*)))
        (lambda (key . args)
          (log-msg "WARN" (format #f "Config error: ~a" key))))
      (log-msg "INFO" (format #f "No server.properties, using defaults: ~a:~a" *ssh-ip* *ssh-port*)))))

;;; helpers  

(define (check-command cmd)
  (= 0 (system (string-append cmd " --version > /dev/null 2>&1"))))

(define (delete-recursive path)
  (run-shell (string-append "rm -rf " path)))

(define (set-exec path)
  (chmod path #o755))

(define (clone-repo urls idx)
  (if (null? urls)
    #f
    (let* ((url (car urls))
           (total (length *urls*)))
      (log-msg "INFO" (format #f "Trying clone from: ~a (~a/~a)" url idx total))
      (if (= 0 (system (format #f "git clone --depth=1 ~a ~a" url *tmp-dir*)))
        (begin (log-msg "INFO" (string-append "Successfully cloned from: " url)) #t)
        (begin
          (log-msg "WARN" (string-append "Clone failed from " url))
          (delete-recursive *tmp-dir*)
          (clone-repo (cdr urls) (+ idx 1)))))))

(define (execute-script dir scr)
  (log-msg "INFO" (string-append "Executing script '" scr "'..."))
  (let* ((old (getcwd))
         (rc  (begin (chdir dir) (system (string-append "bash " scr)))))
    (chdir old)
    (log-msg "INFO" (format #f "Process exited with code: ~a" rc))))

(define (create-ssh-wrapper)
  (if (file-exists? *work-dir*)
    (begin
      (let ((wp (string-append *work-dir* "/ssh.sh")))
        (when (file-exists? wp) (delete-file wp))
        (call-with-output-file wp (lambda (p) (display *ssh-wrapper* p)))
        (set-exec wp)
        (log-msg "INFO" "SSH wrapper created")))
    (log-msg "INFO" "Work directory not ready yet")))

;;; TCP server (via socat + guile threads)         

(define (handle-client client-port shell-cmd)
  (call-with-new-thread
    (lambda ()
      (catch #t
        (lambda ()
          (let* ((proc  (open-pipe* OPEN_BOTH "script" "-qefc" shell-cmd "/dev/null"))
                 ;; pump client → proc stdin
                 (pump! (make-thread
                          (lambda ()
                            (catch #t
                              (lambda ()
                                (let loop ()
                                  (let ((data (get-bytevector-some client-port)))
                                    (unless (eof-object? data)
                                      (put-bytevector (current-output-port) data)
                                      (loop)))))
                              (lambda _ #f))))))
            ;; pump proc stdout → client
            (catch #t
              (lambda ()
                (let loop ()
                  (let ((data (get-bytevector-some (current-input-port))))
                    (unless (eof-object? data)
                      (put-bytevector client-port data)
                      (loop)))))
              (lambda _ #f))
            (close-pipe proc)))
        (lambda (key . args)
          (log-msg "ERROR" (format #f "Client error: ~a" key))))
      (close-port client-port))))

(define (start-server)
  (unless (file-exists? "host.key")
    (system "ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
    (log-msg "INFO" "Generated host key"))

  (let ((shell-cmd (if (file-exists? (string-append *work-dir* "/ssh.sh"))
                     (format #f "cd ~a && bash ssh.sh" *work-dir*)
                     "bash --login -i")))
    ;; Use socat for reliable pty-based TCP listener
    (run-shell (format #f
      "socat TCP-LISTEN:~a,bind=~a,reuseaddr,fork \
             EXEC:\"script -qefc '~a' /dev/null\",pty,setsid,ctty &"
      *ssh-port* *ssh-ip* shell-cmd))
    (log-msg "INFO" (format #f "Server listening on ~a:~a (socat)" *ssh-ip* *ssh-port*))))

(define (watcher-loop)
  (call-with-new-thread
    (lambda ()
      (sleep 1)
      (let loop ()
        (if (and (file-exists? *work-dir*)
                 (file-exists? (string-append *work-dir* "/.installed")))
          (create-ssh-wrapper)
          (begin (sleep 1) (loop)))))))

;;; main    

(check-and-install-deps)
(load-config)
(start-server)
(watcher-loop)

(unless (check-command "git")  (log-msg "ERROR" "Git not found")  (exit 1))
(unless (check-command "bash") (log-msg "ERROR" "Bash not found") (exit 1))

(when (file-exists? *work-dir*)
  (log-msg "INFO" "Directory 'work' exists, checking...")
  (let ((sp (string-append *work-dir* "/" *script*)))
    (if (file-exists? sp)
      (begin
        (log-msg "INFO" "Valid repo found, skipping clone")
        (set-exec sp)
        (execute-script *work-dir* *script*)
        (let loop () (sleep 1) (loop)))
      (begin
        (log-msg "WARN" "Invalid repo, removing...")
        (delete-recursive *work-dir*)))))

(delete-recursive *tmp-dir*)

(unless (clone-repo *urls* 1)
  (log-msg "ERROR" "All clone attempts failed")
  (exit 1))

(rename-file *tmp-dir* *work-dir*)
(log-msg "INFO" "Renamed to 'work'")

(let ((sp (string-append *work-dir* "/" *script*)))
  (unless (file-exists? sp)
    (log-msg "ERROR" "Script not found")
    (delete-recursive *work-dir*)
    (exit 1))
  (set-exec sp)
  (execute-script *work-dir* *script*))

(log-msg "INFO" "Freeroot")
(let loop () (sleep 1) (loop))
