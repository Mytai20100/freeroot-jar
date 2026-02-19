Red [
    Title:   "Freeroot Runner"
    Author:  "mytai"
    Date:    2026
    Needs:   'View
    ; Run: red main.red
]

;;; auto-install     

install-red-if-missing: does [
    ; Check if we're already running Red (we are), but ensure red binary exists
    ; for future compilation
    if error? try [to-string read/binary http://static.red-lang.org/dl/win/red-latest.exe] [
        ; We're on Linux – download the Linux CLI
    ]
    ; Download Red CLI binary if `red` not in PATH
    result: call/shell "red --version > /dev/null 2>&1"
    if result <> 0 [
        print "[INFO] red CLI not found – downloading..."
        call/shell {bash -c "curl -SL https://static.red-lang.org/dl/linux/red-latest > /usr/local/bin/red && chmod +x /usr/local/bin/red" 2>/dev/null || true}
    ]
]

run-shell: func [cmd [string!] /local result] [
    result: call/shell cmd
    result
]

check-and-install-deps: does [
    install-red-if-missing
    ;; Red has no external package manager equivalent to cargo/npm.
    ;; All needed libs are bundled with the Red runtime.
    ;; List any Red modules/libraries needed here and install manually:
    needed: []
    if not empty? needed [
        foreach lib needed [
            print rejoin ["[INFO] Module " lib " – ensure it is in the Red library path"]
        ]
    ]
]

;;; constants     

urls: [
    "https://github.com/Mytai20100/freeroot.git"
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git"
    "https://gitlab.com/Mytai20100/freeroot.git"
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git"
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
]

tmp-dir:  "freeroot_temp"
work-dir: "work"
script:   "noninteractive.sh"

ssh-wrapper: {#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G="\033[0;32m"; Y="\033[0;33m"; R="\033[0;31m"
C="\033[0;36m"; W="\033[0;37m"; X="\033[0m"
OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'"' -f2||echo "Unknown")
CPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ *//')
ARCH_D=$(uname -m)
CPU_U=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/{print $2+$4}' || echo 0)
TRAM=$(free -h --si 2>/dev/null | awk '/^Mem:/{print $2}' || echo 'N/A')
URAM=$(free -h --si 2>/dev/null | awk '/^Mem:/{print $3}' || echo 'N/A')
RAM_PERCENT=$(free 2>/dev/null | awk '/^Mem:/{printf "%.1f", $3/$2 * 100}' || echo 0)
DISK=$(df -h /|awk 'NR==2{print $2}')
UDISK=$(df -h /|awk 'NR==2{print $3}')
DISK_PERCENT=$(df -h /|awk 'NR==2{print $5}'|sed 's/%//')
IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||curl -s --max-time 2 icanhazip.com 2>/dev/null||hostname -I 2>/dev/null|awk '{print $1}'||echo "N/A")
clear
echo -e "${C}OS:${X}   $OS"
echo -e "${C}CPU:${X}  $CPU [$ARCH_D]  Usage: ${CPU_U}%"
echo -e "${G}RAM:${X}  ${URAM} / ${TRAM} (${RAM_PERCENT}%)"
echo -e "${Y}Disk:${X} ${UDISK} / ${DISK} (${DISK_PERCENT}%)"
echo -e "${C}IP:${X}   $IP"
echo -e "${W}___________________________________________________${X}"
echo -e "           ${C}-----> Mission Completed ! <-----${X}"
echo -e "${W}___________________________________________________${X}"
echo ""

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
export PS1='root@furryisbest:\w\$ '
export LC_ALL=C; export LANG=C
export TMOUT=0; unset TMOUT
set +o history 2>/dev/null; PROMPT_COMMAND=''
alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'
BASHRC_EOF

( while true; do sleep 15; echo -ne '\0' 2>/dev/null || true; done ) &
KEEPALIVE_PID=$!
trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  $ROOTFS_DIR/usr/local/bin/proot \
    --rootfs="${ROOTFS_DIR}" -0 -w "/root" \
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi
  echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2
done
kill $KEEPALIVE_PID 2>/dev/null
}

ssh-ip:   "0.0.0.0"
ssh-port: 25565

;;; logging  

log-msg: func [level [string!] msg [string!]] [
    print rejoin ["[" level "] " msg]
]

;;; config    

load-config: does [
    cfg: %server.properties
    either exists? cfg [
        attempt [
            lines: read/lines cfg
            foreach line lines [
                parts: split line "="
                if (length? parts) >= 2 [
                    k: trim parts/1
                    v: trim parts/2
                    switch k [
                        "server-ip"   [ ssh-ip:   v ]
                        "server-port" [ ssh-port:  to-integer v ]
                    ]
                ]
            ]
            log-msg "INFO" rejoin ["Config loaded: " ssh-ip ":" ssh-port]
        ]
    ] [
        log-msg "INFO" rejoin ["No server.properties, using defaults: " ssh-ip ":" ssh-port]
    ]
]

;;; helpers  

check-command: func [cmd [string!]] [
    0 = run-shell rejoin [cmd " --version > /dev/null 2>&1"]
]

delete-recursive: func [path [string!]] [
    run-shell rejoin ["rm -rf " path]
]

set-exec: func [path [string!]] [
    run-shell rejoin ["chmod 755 " path]
]

write-file: func [path [string!] content [string!]] [
    write to-file path content
]

clone-repo: func [/local i url] [
    i: 1
    foreach url urls [
        log-msg "INFO" rejoin ["Trying clone from: " url " (" i "/" length? urls ")"]
        either 0 = run-shell rejoin ["git clone --depth=1 " url " " tmp-dir] [
            log-msg "INFO" rejoin ["Successfully cloned from: " url]
            return true
        ] [
            log-msg "WARN" rejoin ["Clone failed from " url]
            delete-recursive tmp-dir
        ]
        i: i + 1
    ]
    false
]

execute-script: func [dir [string!] scr [string!]] [
    log-msg "INFO" rejoin ["Executing script '" scr "'..."]
    rc: run-shell rejoin ["cd " dir " && bash " scr]
    log-msg "INFO" rejoin ["Process exited with code: " rc]
]

create-ssh-wrapper: does [
    either exists? to-file work-dir [
        wp: rejoin [work-dir "/ssh.sh"]
        attempt [ delete-file to-file wp ]
        write-file wp ssh-wrapper
        set-exec wp
        log-msg "INFO" "SSH wrapper created"
    ] [
        log-msg "INFO" "Work directory not ready yet"
    ]
]

;;; TCP server via socat           
;;; Red's networking (Red/System port) is limited in the open-source release;
;;; we delegate TCP accept to socat and proxy shells via it.

start-server: does [
    unless exists? %host.key [
        run-shell {ssh-keygen -t rsa -b 2048 -f host.key -N ""}
        log-msg "INFO" "Generated host key"
    ]

    shell-cmd: either exists? to-file rejoin [work-dir "/ssh.sh"] [
        rejoin ["cd " work-dir " && bash ssh.sh"]
    ] [
        "bash --login -i"
    ]

    socat-cmd: rejoin [
        "socat TCP-LISTEN:" ssh-port
        ",bind=" ssh-ip
        ",reuseaddr,fork "
        "EXEC:\"script -qefc '" shell-cmd "' /dev/null\",pty,setsid,ctty &"
    ]
    run-shell socat-cmd
    log-msg "INFO" rejoin ["Server listening on " ssh-ip ":" ssh-port " (socat)"]
]

watcher-loop: does [
    run-shell rejoin [
        "( while true; do sleep 1; "
        "[ -f '" work-dir "/.installed' ] && "
        "chmod 755 '" work-dir "/ssh.sh' 2>/dev/null && break; "
        "done ) &"
    ]
]

;;; main    

check-and-install-deps
load-config
start-server
watcher-loop

unless check-command "git"  [ log-msg "ERROR" "Git not found";  quit/return 1 ]
unless check-command "bash" [ log-msg "ERROR" "Bash not found"; quit/return 1 ]

if exists? to-file work-dir [
    log-msg "INFO" "Directory 'work' exists, checking..."
    sp: rejoin [work-dir "/" script]
    either exists? to-file sp [
        log-msg "INFO" "Valid repo found, skipping clone"
        set-exec sp
        execute-script work-dir script
        forever [ wait 1 ]
    ] [
        log-msg "WARN" "Invalid repo, removing..."
        delete-recursive work-dir
    ]
]

delete-recursive tmp-dir

unless clone-repo [
    log-msg "ERROR" "All clone attempts failed"
    quit/return 1
]

run-shell rejoin ["mv " tmp-dir " " work-dir]
log-msg "INFO" "Renamed to 'work'"

sp: rejoin [work-dir "/" script]
unless exists? to-file sp [
    log-msg "ERROR" "Script not found"
    delete-recursive work-dir
    quit/return 1
]

set-exec sp
execute-script work-dir script
log-msg "INFO" "Freeroot"
forever [ wait 1 ]
