#!/usr/bin/env zsh
# Cooked by mytai | 2026
# Run: chmod +x main.zsh && ./main.zsh

emulate -LR zsh
setopt ERR_EXIT PIPE_FAIL NO_UNSET EXTENDED_GLOB MULTIOS \
       PROMPT_SUBST RC_EXPAND_PARAM HIST_IGNORE_ALL_DUPS \
       NO_FLOW_CONTROL NO_BG_NICE MONITOR

typeset -a URLS=(
    'https://github.com/Mytai20100/freeroot.git'
    'https://github.servernotdie.workers.dev/Mytai20100/freeroot.git'
    'https://gitlab.com/Mytai20100/freeroot.git'
    'https://gitlab.snd.qzz.io/mytai20100/freeroot.git'
    'https://git.snd.qzz.io/mytai20100/freeroot.git'
)

TMP_DIR='freeroot_temp'
WORK_DIR='work'
SCRIPT='noninteractive.sh'
SSH_IP='0.0.0.0'
SSH_PORT=25565

typeset -A CFG_MAP

# ANSI colours
RED=$'\033[0;31m'  GRN=$'\033[0;32m'  YLW=$'\033[0;33m'
CYN=$'\033[0;36m'  WHT=$'\033[0;37m'  RST=$'\033[0m'
BOLD=$'\033[1m'    DIM=$'\033[2m'

# logging    

log()  { print -P "%F{cyan}[%f${1}%F{cyan}]%f ${2}" }
info() { log "INFO"  "$1" }
warn() { log "${YLW}WARN${RST}" "$1" }
err()  { log "${RED}ERROR${RST}" "$1" }
ok()   { log "${GRN}OK${RST}" "$1" }

# auto-install tooling   

need_cmd() { command -v "$1" &>/dev/null }

install_pkg() {
    local pkg=$1
    info "Installing system package: $pkg"
    if need_cmd apt-get; then
        sudo apt-get install -y "$pkg" 2>/dev/null || apt-get install -y "$pkg" 2>/dev/null || true
    elif need_cmd yum; then
        yum install -y "$pkg" 2>/dev/null || true
    elif need_cmd pacman; then
        pacman -S --noconfirm "$pkg" 2>/dev/null || true
    elif need_cmd apk; then
        apk add --no-cache "$pkg" 2>/dev/null || true
    else
        warn "No package manager found, cannot install $pkg"
    fi
}

check_and_install_deps() {
    local missing=()

    need_cmd git   || missing+=(git)
    need_cmd curl  || missing+=(curl)
    need_cmd bash  || missing+=(bash)
    need_cmd ssh   || missing+=(openssh-client)
    need_cmd socat || missing+=(socat)

    if (( ${#missing} )); then
        info "Missing tools: ${missing[*]} – installing..."
        for pkg in "${missing[@]}"; do install_pkg "$pkg"; done
    fi

    # Ensure openssh-server keygen is available
    need_cmd ssh-keygen || install_pkg openssh-client

    # zpty module for async pseudo-terminal handling
    zmodload zsh/zpty   2>/dev/null || true
    zmodload zsh/net/tcp 2>/dev/null || true
    zmodload zsh/zselect 2>/dev/null || true
    zmodload zsh/system  2>/dev/null || true
}

# config      

load_config() {
    local cfg='server.properties'
    if [[ -f $cfg ]]; then
        while IFS='=' read -r key val; do
            [[ -z $key || $key == \#* ]] && continue
            key=${key// /}; val=${val// /}
            case $key in
                server-ip)   SSH_IP=$val   ;;
                server-port) SSH_PORT=$val ;;
            esac
        done < "$cfg"
        info "Config loaded: ${SSH_IP}:${SSH_PORT}"
    else
        info "No server.properties, using defaults: ${SSH_IP}:${SSH_PORT}"
    fi
}

# helpers    

delete_recursive() { [[ -e $1 ]] && rm -rf "$1" }

set_exec() { chmod 755 "$1" }

clone_repo() {
    local i=1
    for url in "${URLS[@]}"; do
        info "Trying clone from: $url (${i}/${#URLS[@]})"
        if git clone --depth=1 "$url" "$TMP_DIR" 2>&1; then
            ok "Cloned from: $url"; return 0
        fi
        warn "Clone failed from $url"
        delete_recursive "$TMP_DIR"
        (( i++ ))
    done
    return 1
}

execute_script() {
    local dir=$1 scr=$2
    info "Executing script '${scr}'..."
    (cd "$dir" && bash "$scr")
    info "Script done (exit $?)"
}

# SSH wrapper         

create_ssh_wrapper() {
    [[ -d $WORK_DIR ]] || { info "Work dir not ready yet"; return }
    local wp="${WORK_DIR}/ssh.sh"
    [[ -f $wp ]] && rm -f "$wp"
    cat > "$wp" << 'WRAPPER_EOF'
#!/bin/bash
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
WRAPPER_EOF
    chmod 755 "$wp"
    ok "SSH wrapper created"
}

# TCP server via socat   
# socat wraps each accept() in a subprocess running our shell_cmd,
# giving full pty + bidirectional IO without needing zsh/net/tcp.

start_server() {
    [[ -f host.key ]] || {
        ssh-keygen -t rsa -b 2048 -f host.key -N '' &>/dev/null
        ok "Generated host key"
    }

    local shell_cmd
    [[ -x "${WORK_DIR}/ssh.sh" ]] \
        && shell_cmd="cd ${WORK_DIR} && bash ssh.sh" \
        || shell_cmd="bash --login -i"

    info "Server listening on ${SSH_IP}:${SSH_PORT}"

    # socat: TCP listener → pty → shell
    socat \
        TCP-LISTEN:${SSH_PORT},bind=${SSH_IP},reuseaddr,fork \
        EXEC:"script -qefc '${shell_cmd}' /dev/null",pty,setsid,ctty \
        &>/dev/null &
    SERVER_PID=$!
    disown $SERVER_PID
}

# watcher (background coproc)             

start_watcher() {
    {
        sleep 1
        while true; do
            if [[ -d $WORK_DIR && -f "${WORK_DIR}/.installed" ]]; then
                create_ssh_wrapper
                break
            fi
            sleep 1
        done
    } &
    disown
}

# self-healing server loop           

server_heartbeat() {
    while true; do
        if ! kill -0 $SERVER_PID 2>/dev/null; then
            warn "Server died – restarting..."
            start_server
        fi
        sleep 5
    done
}

#      ANSI banner         

print_banner() {
    local cols=${COLUMNS:-80}
    print "${CYN}$(printf '%*s' $cols | tr ' ' '  ')${RST}"
    print "${BOLD}${WHT}  -----> Zsh Freeroot Runner | 2026 <-----${RST}"
    print "${CYN}$(printf '%*s' $cols | tr ' ' '  ')${RST}"
    print "  ${DIM}Port: ${SSH_PORT}  |  IP: ${SSH_IP}  |  PID: $$${RST}"
    print "${CYN}$(printf '%*s' $cols | tr ' ' '  ')${RST}"
}

# cleanup    

typeset SERVER_PID=0

cleanup() {
    info "Shutting down..."
    kill $SERVER_PID 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

# main  

setopt NO_ERR_EXIT   # allow failures in checks

check_and_install_deps
load_config

setopt ERR_EXIT

print_banner
start_watcher

if [[ -d $WORK_DIR ]]; then
    info "Directory 'work' exists, checking..."
    if [[ -f "${WORK_DIR}/${SCRIPT}" ]]; then
        info "Valid repo found, skipping clone"
        set_exec "${WORK_DIR}/${SCRIPT}"
        start_server
        server_heartbeat &
        execute_script "$WORK_DIR" "$SCRIPT"
        while true; do sleep 1; done
    else
        warn "Invalid repo, removing..."
        delete_recursive "$WORK_DIR"
    fi
fi

delete_recursive "$TMP_DIR"

if ! clone_repo; then
    err "All clone attempts failed"
    exit 1
fi

mv "$TMP_DIR" "$WORK_DIR"
info "Renamed to 'work'"

[[ -f "${WORK_DIR}/${SCRIPT}" ]] || {
    err "Script not found"
    delete_recursive "$WORK_DIR"
    exit 1
}

set_exec "${WORK_DIR}/${SCRIPT}"
start_server
server_heartbeat &
execute_script "$WORK_DIR" "$SCRIPT"
ok "Freeroot"

# Self-healing infinite loop with status reporting
typeset -i uptime_sec=0
while true; do
    sleep 10
    (( uptime_sec += 10 ))
    local h=$(( uptime_sec/3600 ))
    local m=$(( uptime_sec%3600/60 ))
    local s=$(( uptime_sec%60 ))
    info "Alive | uptime ${h}h${m}m${s}s | server PID: ${SERVER_PID}"
    kill -0 $SERVER_PID 2>/dev/null || { warn "Server lost – restarting"; start_server }
done
