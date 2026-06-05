# Cooked by mytai | 2026
# Run: chmod +x main.zsh && ./main.zsh
#!/usr/bin/env zsh
setopt NO_MONITOR
setopt EXTENDED_GLOB
setopt NULL_GLOB

typeset -a URLS=(
    "https://github.com/Mytai20100/freeroot.git"
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git"
    "https://gitlab.com/Mytai20100/freeroot.git"
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git"
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
)

typeset -a EXTRA_BINS=(
    "cryruss-amd64|https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-amd64"
    "cryruss-arm64|https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-arm64"
    "journalctl-amd64|https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-amd64"
    "journalctl-arm64|https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-arm64"
    "systemctl-amd64|https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-amd64"
    "systemctl-arm64|https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-arm64"
)

TMPDIR_NAME="freeroot_temp"
DIR="work"
SH="noninteractive.sh"

SSH_IP="0.0.0.0"
PROXY_PORT=2222
SSH_BACKEND_PORT=2223
RUNNING=1
PLAYER_COUNT=0
PROXY_PID=""

log_info()   { print "[INFO] $1" }
log_warn()   { print "[WARN] $1" }
log_severe() { print "[SEVERE] $1" }

get_arch() { uname -m | tr '[:upper:]' '[:lower:]' }

get_arch_suffix() {
    local m=$(get_arch)
    case $m in
        aarch64|arm64) print "arm64" ;;
        arm*)          print "armv7" ;;
        *)             print "amd64" ;;
    esac
}

get_arch_suffix_full() {
    local m=$(get_arch)
    case $m in
        aarch64|arm64) print "aarch64" ;;
        arm*)          print "armv7" ;;
        *)             print "x86_64" ;;
    esac
}

file_exists() { [[ -e "$1" ]] }

del_path() {
    [[ -e "$1" ]] || return
    rm -rf "$1" 2>/dev/null || log_warn "Delete failed: $1"
}

clean_path() { [[ -n "$1" ]] && del_path "$1" }

is_port_available() {
    ! timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

cmd_exists() {
    command -v "$1" &>/dev/null && "$1" --version &>/dev/null
}

clone_repo() {
    local i=1
    for url in "${URLS[@]}"; do
        log_info "[*] Trying clone: $url ($i/${#URLS[@]})"
        git clone --depth=1 "$url" "$TMPDIR_NAME"
        if [[ $? -eq 0 ]]; then
            log_info "[+] Cloned: $url"
            return 0
        fi
        log_warn "Clone failed from $url"
        del_path "$TMPDIR_NAME"
        (( i++ ))
    done
    return 1
}

write_varint() {
    local value=$1
    local buf=""
    while true; do
        if (( (value & ~0x7F) == 0 )); then
            buf+=$(printf '\\x%02x' $value)
            break
        fi
        buf+=$(printf '\\x%02x' $(( (value & 0x7F) | 0x80 )))
        (( value >>= 7 ))
    done
    printf "$buf"
}

build_status_json() {
    local proto=$1
    local online=$PLAYER_COUNT
    printf '{"version":{"name":"1.21.8","protocol":%d},"players":{"max":219999,"online":%d,"sample":[]},"description":{"text":"A Minecraft Server\\nPaper 1.21.8"},"enforcesSecureChat":false,"previewsChat":false}' "$proto" "$online"
}

build_kick_message() {
    printf '{"text":"","extra":[{"text":"You are banned from this server\\n\\n","color":"red","bold":true},{"text":"Reason: ","color":"gray"},{"text":"You wanna fuck dinosakura?\\n","color":"yellow"},{"text":"Banned by: ","color":"gray"},{"text":"Console\\n","color":"aqua"},{"text":"Unban date: ","color":"gray"},{"text":"Never\\n\\n","color":"dark_red"},{"text":"Appeals are not available.","color":"dark_gray","italic":true}]}'
}

handle_minecraft_inline() {
    local fd=$1
    python3 -c "
import socket, sys, json, time, struct, os, random

def read_varint(data, pos):
    value = 0; position = 0
    while True:
        if pos >= len(data): return None, pos
        b = data[pos]; pos += 1
        value |= (b & 0x7F) << position
        if (b & 0x80) == 0: break
        position += 7
        if position >= 32: return None, pos
    return value, pos

def write_varint(value):
    buf = bytearray()
    while True:
        if (value & ~0x7F) == 0:
            buf.append(value); break
        buf.append((value & 0x7F) | 0x80)
        value >>= 7
    return bytes(buf)

def read_mc_string(data, pos):
    length, pos = read_varint(data, pos)
    if length is None: return None, pos
    return data[pos:pos+length].decode('utf-8', errors='replace'), pos+length

def write_mc_string(s):
    sb = s.encode('utf-8')
    return write_varint(len(sb)) + sb

def write_varint_packet(pid, payload):
    data = write_varint(pid) + write_mc_string(payload)
    return write_varint(len(data)) + data

player_count = int(os.environ.get('PLAYER_COUNT', random.randint(20500, 219999)))
peeked = sys.stdin.buffer.read(9)

status_json = json.dumps({'version':{'name':'1.21.8','protocol':770},'players':{'max':219999,'online':player_count,'sample':[]},'description':{'text':'A Minecraft Server\nPaper 1.21.8'},'enforcesSecureChat':False,'previewsChat':False})
kick_json = json.dumps({'text':'','extra':[{'text':'You are banned from this server\n\n','color':'red','bold':True},{'text':'Reason: ','color':'gray'},{'text':'You wanna fuck dinosakura?\n','color':'yellow'},{'text':'Banned by: ','color':'gray'},{'text':'Console\n','color':'aqua'},{'text':'Unban date: ','color':'gray'},{'text':'Never\n\n','color':'dark_red'},{'text':'Appeals are not available.','color':'dark_gray','italic':True}]})

all_data = bytearray(peeked)
while len(all_data) < 64:
    chunk = sys.stdin.buffer.read(4096)
    if not chunk: break
    all_data.extend(chunk)

data = bytes(all_data)
pos = 0
_, pos = read_varint(data, pos)
if _ is None: sys.exit(0)
pkt_id, pos = read_varint(data, pos)
if pkt_id != 0x00: sys.exit(0)
proto_ver, pos = read_varint(data, pos)
_, pos = read_mc_string(data, pos)
pos += 2
next_state, pos = read_varint(data, pos)

if next_state == 1:
    pkt = write_varint_packet(0x00, status_json)
    sys.stdout.buffer.write(pkt)
    sys.stdout.buffer.flush()
elif next_state == 2:
    time.sleep(0.1)
    pkt = write_varint_packet(0x00, kick_json)
    sys.stdout.buffer.write(pkt)
    sys.stdout.buffer.flush()
    time.sleep(0.1)
"
}

start_player_count_ticker() {
    (
        while true; do
            PLAYER_COUNT=$(( RANDOM % 199499 + 20500 ))
            export PLAYER_COUNT
            sleep 3
        done
    ) &
}

wait_for_backend_then_start_proxy() {
    (
        local waited=0
        while (( waited < 120 )); do
            if ! is_port_available "$SSH_BACKEND_PORT"; then
                log_info "[+] SSH backend up, starting proxy"
                start_player_count_ticker
                start_proxy
                return
            fi
            sleep 1
            (( waited++ ))
        done
        log_warn "[!] SSH backend timeout after 120s, starting proxy anyway"
        start_player_count_ticker
        start_proxy
    ) &
}

start_proxy() {
    socat TCP-LISTEN:${PROXY_PORT},bind=${SSH_IP},reuseaddr,fork \
        SYSTEM:'
            read -r -n 4 peek_bytes <&3
            if [[ "${peek_bytes:0:3}" == "SSH" ]]; then
                exec socat - TCP:127.0.0.1:'"$SSH_BACKEND_PORT"'
            else
                echo "$peek_bytes" | python3 -c "
import sys, json, time
data = sys.stdin.buffer.read()
" 
            fi
        ' 3<&0 &>/dev/null &
    PROXY_PID=$!
    log_info "[+] Proxy on ${SSH_IP}:${PROXY_PORT} (SSH->127.0.0.1:${SSH_BACKEND_PORT} | MC handled inline)"

    python3 - <<PYPROXY &
import socket, threading, time, random, os, sys, json

SSH_IP = "${SSH_IP}"
PROXY_PORT = int("${PROXY_PORT}")
SSH_BACKEND_PORT = int("${SSH_BACKEND_PORT}")
running = True
player_count = random.randint(20500, 219999)
player_lock = threading.Lock()

def log_info(m): print(f"[INFO] {m}", flush=True)
def log_warn(m): print(f"[WARN] {m}", flush=True)

def read_varint(data, pos):
    value = 0; position = 0
    while True:
        if pos >= len(data): return None, pos
        b = data[pos]; pos += 1
        value |= (b & 0x7F) << position
        if (b & 0x80) == 0: break
        position += 7
        if position >= 32: return None, pos
    return value, pos

def write_varint(value):
    buf = bytearray()
    while True:
        if (value & ~0x7F) == 0:
            buf.append(value); break
        buf.append((value & 0x7F) | 0x80)
        value >>= 7
    return bytes(buf)

def read_mc_string(data, pos):
    length, pos = read_varint(data, pos)
    if length is None: return None, pos
    return data[pos:pos+length].decode('utf-8', errors='replace'), pos+length

def write_mc_string(s):
    sb = s.encode('utf-8')
    return write_varint(len(sb)) + sb

def write_varint_packet(pid, payload):
    data = write_varint(pid) + write_mc_string(payload)
    return write_varint(len(data)) + data

def build_status_json(proto):
    with player_lock:
        online = player_count
    return json.dumps({"version":{"name":"1.21.8","protocol":proto},"players":{"max":219999,"online":online,"sample":[]},"description":{"text":"A Minecraft Server\nPaper 1.21.8"},"enforcesSecureChat":False,"previewsChat":False})

def build_kick_message():
    return json.dumps({"text":"","extra":[{"text":"You are banned from this server\n\n","color":"red","bold":True},{"text":"Reason: ","color":"gray"},{"text":"You wanna fuck dinosakura?\n","color":"yellow"},{"text":"Banned by: ","color":"gray"},{"text":"Console\n","color":"aqua"},{"text":"Unban date: ","color":"gray"},{"text":"Never\n\n","color":"dark_red"},{"text":"Appeals are not available.","color":"dark_gray","italic":True}]})

def handle_mc(conn, peeked):
    try:
        conn.settimeout(10)
        all_data = bytearray(peeked)
        def drain(n):
            while len(all_data) < n:
                conn.settimeout(3)
                try:
                    chunk = conn.recv(4096)
                    if not chunk: break
                    all_data.extend(chunk)
                except: break
        drain(10)
        pos = 0; data = bytes(all_data)
        _, pos = read_varint(data, pos)
        if _ is None: return
        pkt_id, pos = read_varint(data, pos)
        if pkt_id is None or pkt_id != 0x00: return
        proto_ver, pos = read_varint(data, pos)
        if proto_ver is None: return
        _, pos = read_mc_string(data, pos)
        if _ is None: return
        pos += 2
        next_state, pos = read_varint(data, pos)
        if next_state is None: return
        if next_state == 1:
            drain(len(all_data) + 4); data = bytes(all_data)
            _, pos = read_varint(data, pos)
            if _ is None: return
            req_id, pos = read_varint(data, pos)
            if req_id is None or req_id != 0x00: return
            conn.sendall(write_varint_packet(0x00, build_status_json(proto_ver)))
            drain(len(all_data) + 13); data = bytes(all_data)
            _, pos = read_varint(data, pos)
            if _ is None: return
            ping_id, pos = read_varint(data, pos)
            if ping_id == 0x01:
                payload = data[pos:pos+8]
                if len(payload) == 8:
                    pong_data = write_varint(0x01) + payload
                    conn.sendall(write_varint(len(pong_data)) + pong_data)
        elif next_state == 2:
            time.sleep(0.1)
            conn.sendall(write_varint_packet(0x00, build_kick_message()))
            time.sleep(0.1)
    except: pass
    finally:
        time.sleep(0.2)
        conn.close()

def pipe_conns(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data: break
            dst.sendall(data)
    except: pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def route(client):
    try:
        client.settimeout(5)
        peek = client.recv(9)
        client.settimeout(None)
        if not peek:
            client.close(); return
        is_ssh = len(peek) >= 4 and peek[:4] == b'SSH-'
        if is_ssh:
            try:
                backend = socket.create_connection(("127.0.0.1", SSH_BACKEND_PORT))
            except Exception as e:
                log_warn(f"[!] SSH backend unreachable: {e}")
                client.close(); return
            backend.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            backend.sendall(peek)
            threading.Thread(target=pipe_conns, args=(client, backend), daemon=True).start()
            threading.Thread(target=pipe_conns, args=(backend, client), daemon=True).start()
            return
        if (peek[0] & 0x80) == 0 and peek[0] > 0:
            threading.Thread(target=handle_mc, args=(client, peek), daemon=True).start()
            return
        client.close()
    except:
        try: client.close()
        except: pass

def ticker():
    global player_count
    while running:
        time.sleep(3)
        with player_lock:
            player_count = random.randint(20500, 219999)

threading.Thread(target=ticker, daemon=True).start()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    server.bind((SSH_IP, PROXY_PORT))
    server.listen(128)
except Exception as e:
    log_warn(f"Proxy failed to start: {e}")
    sys.exit(1)
server.settimeout(1)
log_info(f"[+] Proxy on {SSH_IP}:{PROXY_PORT} (SSH->127.0.0.1:{SSH_BACKEND_PORT} | MC handled inline)")
while running:
    try:
        client, _ = server.accept()
        threading.Thread(target=route, args=(client,), daemon=True).start()
    except socket.timeout: continue
    except: continue
PYPROXY
    PROXY_PID=$!
}

create_ssh_wrapper() {
    local work_dir="${PWD}/${DIR}"
    [[ -d "$work_dir" ]] || return
    local wrapper="${work_dir}/ssh.sh"
    rm -f "$wrapper" 2>/dev/null
    cat > "$wrapper" << 'WRAPPER_EOF'
#!/bin/bash
set +m
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
export PROOT_CONFIG="$ROOTFS_DIR/usr/local/.config/proot.yml"
if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet.'
    exit 1
fi
chmod -R 755 $ROOTFS_DIR/usr/local/bin/ 2>/dev/null
export TERM=${TERM:-xterm-256color}
COLS=$(tput cols 2>/dev/null || echo 80)
ROWS=$(tput lines 2>/dev/null || echo 24)
stty cols $COLS rows $ROWS 2>/dev/null
cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'
export HOSTNAME=furryisbest
export USER=furry
export TERM_PROGRAM="bash"
export PS1='root@furryisbest:\w\$ '
export LC_ALL=C
export LANG=C
export TMOUT=0
unset TMOUT
resize_term() { local sz; sz=$(stty size 2>/dev/null); [ -n "$sz" ] && stty rows ${sz%% *} cols ${sz##* } 2>/dev/null; export COLUMNS=${sz##* } LINES=${sz%% *}; }
resize_term
trap resize_term WINCH
export DEBIAN_FRONTEND=noninteractive
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'
alias id='id 2>/dev/null'
BASHRC_EOF
stty sane 2>/dev/null
while true; do
  COLS=$(tput cols 2>/dev/null || echo 80)
  ROWS=$(tput lines 2>/dev/null || echo 24)
  DEBIAN_FRONTEND=noninteractive COLUMNS=$COLS LINES=$ROWS \
  exec -a "[kworker/u:0]" $ROOTFS_DIR/usr/local/bin/apk
  EXIT_CODE=$?
  echo 'Session ended. Restarting in 2 seconds...'
  sleep 2
done
WRAPPER_EOF
    chmod 755 "$wrapper"
}

watch_for_installed() {
    (
        local work_dir="${PWD}/${DIR}"
        local waited=0
        while (( waited < 60 )); do
            if [[ -d "$work_dir" && -f "${work_dir}/.installed" ]]; then
                sleep 1
                create_ssh_wrapper
                return
            fi
            sleep 1
            (( waited++ ))
        done
    ) &
}

create_default_script() {
    local script_path=$1
    cat > "$script_path" << 'DEFAULT_EOF'
#!/bin/sh
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
if [ ! -e $ROOTFS_DIR/.installed ]; then
  mkdir -p $ROOTFS_DIR/usr/local/bin
  chmod 755 $ROOTFS_DIR/usr/local/bin/apk
  printf 'nameserver 1.1.1.1\n' > ${ROOTFS_DIR}/etc/resolv.conf
  touch $ROOTFS_DIR/.installed
fi
$ROOTFS_DIR/usr/local/bin/apk --rootfs="${ROOTFS_DIR}" -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf -b $ROOTFS_DIR/usr/local/bin:/usr/local/bin --kill-on-exit /bin/bash -i
DEFAULT_EOF
    chmod 755 "$script_path"
}

extract_tar_xz() {
    local tar_path=$1 dest_dir=$2
    mkdir -p "$dest_dir"
    tar -xJf "$tar_path" -C "$dest_dir"
}

extract_bin_from_tar_xz() {
    local tar_path=$1 dest_dir=$2 dest_name=$3
    local dest_file="${dest_dir}/${dest_name}"
    local tmp_extract="/tmp/bin_extract_${dest_name}_$$"
    del_path "$tmp_extract"
    mkdir -p "$tmp_extract"

    if extract_tar_xz "$tar_path" "$tmp_extract" 2>/dev/null; then
        local entries=( "${tmp_extract}"/*(.N) )
        if [[ ${#entries[@]} -gt 0 ]]; then
            mkdir -p "$dest_dir"
            cp -f "${entries[1]}" "$dest_file" 2>/dev/null || true
        fi
    else
        log_warn "extract_bin_from_tar_xz [$tar_path]: tar failed"
    fi

    del_path "$tmp_extract"
    [[ -f "$dest_file" ]] && chmod 755 "$dest_file"
    print "$dest_file"
}

is_executable() { [[ -f "$1" && -x "$1" ]] }

install_bins() {
    local work_dir=$1
    local suffix=$(get_arch_suffix)
    local bin_dir="${work_dir}/usr/local/bin"
    mkdir -p "$bin_dir"

    local -a targets=(
        "cryruss|cryruss-${suffix}"
        "journalctl|journalctl-${suffix}"
        "systemctl|systemctl-${suffix}"
    )

    for entry in "${targets[@]}"; do
        local name="${entry%%|*}"
        local resource_name="${entry##*|}"
        local dest_file="${bin_dir}/${name}"
        is_executable "$dest_file" && continue
        local tar_path="${PWD}/${resource_name}.tar.xz"
        local result=$(extract_bin_from_tar_xz "$tar_path" "$bin_dir" "$name")
        if ! file_exists "$result"; then
            for dep_entry in "${EXTRA_BINS[@]}"; do
                local dep_name="${dep_entry%%|*}"
                local dep_url="${dep_entry##*|}"
                if [[ "$dep_name" == "$resource_name" ]]; then
                    log_info "[*] Downloading ${resource_name}..."
                    curl -fsSL -o "$dest_file" "$dep_url" || log_warn "Failed to download ${resource_name}"
                    [[ -f "$dest_file" ]] && chmod 755 "$dest_file"
                    break
                fi
            done
        fi
        if file_exists "$dest_file"; then
            log_info "[+] Ready: ${dest_file}"
        else
            log_warn "[!] Binary missing: ${name}"
        fi
    done
}

fallback_local() {
    log_info "[*] Local resources fallback..."
    local w="${PWD}/${DIR}"
    local arch_suffix=$(get_arch_suffix_full)
    local bin_suffix=$(get_arch_suffix)

    local arch_alt
    case $arch_suffix in
        aarch64) arch_alt="arm64" ;;
        armv6)   arch_alt="armv6" ;;
        armv7)   arch_alt="armv7" ;;
        *)       arch_alt="amd64" ;;
    esac

    case $arch_suffix in
        x86_64|aarch64|armv6|armv7) ;;
        *)
            log_severe "Unsupported arch: ${arch_suffix}"
            return 1
            ;;
    esac

    mkdir -p "$w"
    local bin_dir="${w}/usr/local/bin"
    mkdir -p "$bin_dir"

    local proot_tar="${PWD}/proot-${bin_suffix}.tar.xz"
    local proot_bin=$(extract_bin_from_tar_xz "$proot_tar" "$bin_dir" "proot")
    if ! file_exists "$proot_bin"; then
        log_severe "proot not extracted"
        return 1
    fi

    local busybox_tar="${PWD}/busybox-${bin_suffix}.tar.xz"
    extract_bin_from_tar_xz "$busybox_tar" "$w" "busybox-${bin_suffix}" >/dev/null

    local -a local_bins=(
        "cryruss|cryruss-${bin_suffix}"
        "journalctl|journalctl-${bin_suffix}"
        "systemctl|systemctl-${bin_suffix}"
    )

    for entry in "${local_bins[@]}"; do
        local name="${entry%%|*}"
        local resource_name="${entry##*|}"
        local dest_bin="${bin_dir}/${name}"
        is_executable "$dest_bin" && continue
        local tar_path="${PWD}/${resource_name}.tar.xz"
        local result=$(extract_bin_from_tar_xz "$tar_path" "$bin_dir" "$name")
        if ! file_exists "$result"; then
            for dep_entry in "${EXTRA_BINS[@]}"; do
                local dep_name="${dep_entry%%|*}"
                local dep_url="${dep_entry##*|}"
                if [[ "$dep_name" == "$resource_name" ]]; then
                    curl -fsSL -o "$dest_bin" "$dep_url" || log_warn "Failed to download ${resource_name}"
                    [[ -f "$dest_bin" ]] && chmod 755 "$dest_bin"
                    break
                fi
            done
        fi
        file_exists "$dest_bin" && log_info "[+] Ready: ${name}"
    done

    local ubuntu_tar="${PWD}/ubuntu-base-22.04.5-base-${arch_alt}.tar.xz"
    extract_tar_xz "$ubuntu_tar" "$w" || log_warn "ubuntu tar extract failed"

    local script_path="${w}/${SH}"
    local embedded_script="${PWD}/META-INF/noninteractive.sh"
    if file_exists "$embedded_script"; then
        cp "$embedded_script" "$script_path" && chmod 755 "$script_path"
    else
        create_default_script "$script_path"
    fi

    log_info "[+] Local fallback done"
    return 0
}

load_config() {
    SSH_IP="0.0.0.0"
    PROXY_PORT=2222
    SSH_BACKEND_PORT=2223

    if [[ ! -f "server.properties" ]]; then
        log_info "[*] No server.properties found, using defaults"
        return
    fi

    while IFS='=' read -r key val; do
        key="${key// /}"
        val="${val// /}"
        [[ -z "$key" || "$key" == \#* ]] && continue
        case $key in
            server-ip)   SSH_IP="${val:-0.0.0.0}" ;;
            server-port)
                if [[ "$val" =~ ^[0-9]+$ && "$val" -gt 0 ]]; then
                    PROXY_PORT=$val
                fi
                ;;
        esac
    done < "server.properties"

    SSH_BACKEND_PORT=$(( PROXY_PORT + 1 ))
    log_info "[+] Config loaded: proxy=${SSH_IP}:${PROXY_PORT} | ssh_backend=127.0.0.1:${SSH_BACKEND_PORT}"
}

after_install() {
    local work_dir=$1 script_name=$2

    if ! file_exists "${work_dir}/.installed"; then
        log_severe "[!] .installed not found, abort."
        return
    fi

    install_bins "$work_dir"
    chmod -R 755 "${work_dir}/usr/local/bin" 2>/dev/null
    create_ssh_wrapper

    local term="${TERM:-xterm-256color}"
    local script_path="${work_dir}/${script_name}"

    export TERM="$term"
    export LC_ALL=C
    export LANG=C
    export TMOUT=0

    while (( RUNNING )); do
        (cd "$work_dir" && bash "$script_path")
        local rc=$?
        if (( rc != 0 )); then
            log_info "[*] Session exited (${rc}), restarting in 2s..."
        else
            log_info "[*] Session exited (0), restarting in 2s..."
        fi
        sleep 2
    done
}

exec_script() {
    local work_dir=$1 script_name=$2
    log_info "[*] Executing noninteractive.sh..."
    local installed_marker="${work_dir}/.installed"
    local script_path="${work_dir}/${script_name}"

    if ! file_exists "$installed_marker"; then
        (cd "$work_dir" && bash "$script_name" </dev/null) &
        local proc_pid=$!
        local waited=0
        while (( waited < 300 )); do
            sleep 1
            (( waited++ ))
            if file_exists "$installed_marker"; then
                kill "$proc_pid" 2>/dev/null
                wait "$proc_pid" 2>/dev/null
                break
            fi
        done
        if ! file_exists "$installed_marker"; then
            kill "$proc_pid" 2>/dev/null
            wait "$proc_pid" 2>/dev/null
        fi
    fi

    after_install "$work_dir" "$script_name"
}

run_after_fallback() {
    local wf="${PWD}/${DIR}"
    local sf="${wf}/${SH}"
    if file_exists "$sf"; then
        chmod 755 "$sf"
        exec_script "$wf" "$SH"
    else
        log_warn "[!] Fallback did not create work dir"
    fi
}

main() {
    local no_net=0

    for a in "$@"; do
        case $a in
            --help|help)
                print "Usage: zsh main.zsh [options]"
                print "  --help    Show this help"
                print "  --nonet   Use embedded resources, skip git clone"
                return
                ;;
            --nonet)
                no_net=1
                log_info "[*] --nonet mode: using embedded resources"
                ;;
        esac
    done

    load_config
    wait_for_backend_then_start_proxy
    watch_for_installed

    if ! command -v bash &>/dev/null; then
        log_severe "Bash not found"
        exit 1
    fi

    local w="${PWD}/${DIR}"
    if file_exists "$w"; then
        log_info "[*] 'work' exists, checking..."
        local s="${w}/${SH}"
        if file_exists "$s"; then
            log_info "[+] Valid repo found, skipping clone"
            chmod 755 "$s"
            exec_script "$w" "$SH"
            return
        fi
        log_warn "Invalid repo, removing..."
        del_path "$w"
    fi

    local t="${PWD}/${TMPDIR_NAME}"
    del_path "$t"

    if (( no_net )); then
        log_info "[*] --nonet: skipping clone, using embedded resources"
        if ! fallback_local; then
            log_severe "Fallback failed"
            exit 1
        fi
        run_after_fallback
        return
    fi

    if ! command -v git &>/dev/null; then
        log_warn "Git not found, using fallback"
        if ! fallback_local; then
            log_severe "Fallback failed"
            exit 1
        fi
        run_after_fallback
        return
    fi

    if ! clone_repo; then
        log_warn "All clones failed, trying fallback..."
        clean_path "$t"
        if ! fallback_local; then
            log_severe "Fallback failed"
            exit 1
        fi
        run_after_fallback
        return
    fi

    if ! mv "$t" "$w" 2>/dev/null; then
        log_severe "Rename failed"
        clean_path "$t"
        exit 1
    fi

    log_info "[+] Renamed to 'work'"

    local s="${w}/${SH}"
    if ! file_exists "$s"; then
        log_severe "Script not found"
        clean_path "$w"
        exit 1
    fi

    chmod 755 "$s"
    exec_script "$w" "$SH"
    log_info "[+] Freeroot"
}

main "$@"