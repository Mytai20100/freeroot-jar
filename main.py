# Cooked by mytai | 2026
#!/usr/bin/env python3
import socket
import os
import sys
import time
import random
import json
import struct
import shutil
import subprocess
import threading
import platform

urls = [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git",
]

extra_bins = [
    ("cryruss-amd64",    "https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-amd64"),
    ("cryruss-arm64",    "https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-arm64"),
    ("journalctl-amd64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-amd64"),
    ("journalctl-arm64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-arm64"),
    ("systemctl-amd64",  "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-amd64"),
    ("systemctl-arm64",  "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-arm64"),
]

TMPDIR = "freeroot_temp"
DIR    = "work"
SH     = "noninteractive.sh"

ssh_ip           = "0.0.0.0"
proxy_port       = 2222
ssh_backend_port = 2223
running          = True
player_count     = 0
player_lock      = threading.Lock()
users            = {}


def log_info(msg):
    print(f"[INFO] {msg}", flush=True)

def log_warn(msg):
    print(f"[WARN] {msg}", flush=True)

def log_severe(msg):
    print(f"[SEVERE] {msg}", flush=True)


def get_arch():
    m = platform.machine().lower()
    return m

def get_arch_suffix():
    m = get_arch()
    if m in ("aarch64", "arm64"):
        return "arm64"
    if m.startswith("arm"):
        return "armv7"
    return "amd64"

def get_arch_suffix_full():
    m = get_arch()
    if m in ("aarch64", "arm64"):
        return "aarch64"
    if m.startswith("arm"):
        return "armv7"
    return "x86_64"


def file_exists(p):
    return os.path.exists(p)

def must_cwd():
    return os.getcwd()

def del_path(p):
    if not file_exists(p):
        return
    try:
        if os.path.isdir(p):
            shutil.rmtree(p)
        else:
            os.remove(p)
    except Exception as e:
        log_warn(f"Delete failed: {p} {e}")

def clean_path(d):
    if d:
        del_path(d)

def is_port_available(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        s.connect(("127.0.0.1", port))
        s.close()
        return False
    except:
        return True

def cmd_exists(c):
    try:
        result = subprocess.run(
            [c, "--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3
        )
        return result.returncode == 0
    except:
        return False

def clone_repo():
    for i, url in enumerate(urls):
        log_info(f"[*] Trying clone: {url} ({i+1}/{len(urls)})")
        result = subprocess.run(
            ["git", "clone", "--depth=1", url, TMPDIR],
            stdout=sys.stdout,
            stderr=sys.stderr
        )
        if result.returncode == 0:
            log_info(f"[+] Cloned: {url}")
            return True
        else:
            log_warn(f"Clone failed from {url}")
            del_path(TMPDIR)
    return False


def read_varint(data, pos):
    value = 0
    position = 0
    while True:
        if pos >= len(data):
            return None, pos
        b = data[pos]
        pos += 1
        value |= (b & 0x7F) << position
        if (b & 0x80) == 0:
            break
        position += 7
        if position >= 32:
            return None, pos
    return value, pos

def write_varint(value):
    buf = bytearray()
    while True:
        if (value & ~0x7F) == 0:
            buf.append(value)
            break
        buf.append((value & 0x7F) | 0x80)
        value >>= 7
    return bytes(buf)

def read_mc_string(data, pos):
    length, pos = read_varint(data, pos)
    if length is None:
        return None, pos
    s = data[pos:pos+length].decode("utf-8", errors="replace")
    return s, pos + length

def write_mc_string(s):
    sb = s.encode("utf-8")
    return write_varint(len(sb)) + sb

def write_varint_packet(packet_id, payload):
    id_buf  = write_varint(packet_id)
    str_buf = write_mc_string(payload)
    data    = id_buf + str_buf
    return write_varint(len(data)) + data

def build_status_json(protocol_version):
    global player_count
    with player_lock:
        online = player_count
    s = {
        "version": {"name": "1.21.8", "protocol": protocol_version},
        "players": {"max": 219999, "online": online, "sample": []},
        "description": {"text": "A Minecraft Server\nPaper 1.21.8"},
        "enforcesSecureChat": False,
        "previewsChat": False,
    }
    return json.dumps(s)

def build_kick_message():
    k = {
        "text": "",
        "extra": [
            {"text": "You are banned from this server\n\n", "color": "red", "bold": True},
            {"text": "Reason: ", "color": "gray"},
            {"text": "You wanna fuck dinosakura?\n", "color": "yellow"},
            {"text": "Banned by: ", "color": "gray"},
            {"text": "Console\n", "color": "aqua"},
            {"text": "Unban date: ", "color": "gray"},
            {"text": "Never\n\n", "color": "dark_red"},
            {"text": "Appeals are not available.", "color": "dark_gray", "italic": True},
        ],
    }
    return json.dumps(k)


def recv_exact(conn, n):
    buf = b""
    while len(buf) < n:
        try:
            chunk = conn.recv(n - len(buf))
            if not chunk:
                return None
            buf += chunk
        except:
            return None
    return buf

def handle_minecraft_inline(conn, peeked):
    try:
        conn.settimeout(10)
        all_data = bytearray(peeked)

        def drain(needed):
            while len(all_data) < needed:
                conn.settimeout(3)
                try:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    all_data.extend(chunk)
                except:
                    break

        drain(10)
        pos = 0
        data = bytes(all_data)

        _, pos = read_varint(data, pos)
        if _ is None:
            return

        pkt_id, pos = read_varint(data, pos)
        if pkt_id is None or pkt_id != 0x00:
            return

        protocol_version, pos = read_varint(data, pos)
        if protocol_version is None:
            return

        _, pos = read_mc_string(data, pos)
        if _ is None:
            return

        pos += 2

        next_state, pos = read_varint(data, pos)
        if next_state is None:
            return

        data = bytes(all_data)

        if next_state == 1:
            drain(len(all_data) + 4)
            data = bytes(all_data)
            _, pos = read_varint(data, pos)
            if _ is None:
                return
            req_id, pos = read_varint(data, pos)
            if req_id is None or req_id != 0x00:
                return

            status_pkt = write_varint_packet(0x00, build_status_json(protocol_version))
            conn.sendall(status_pkt)

            drain(len(all_data) + 13)
            data = bytes(all_data)
            _, pos = read_varint(data, pos)
            if _ is None:
                return
            ping_id, pos = read_varint(data, pos)
            if ping_id == 0x01:
                payload = data[pos:pos+8]
                if len(payload) == 8:
                    pong_id   = write_varint(0x01)
                    pong_data = pong_id + payload
                    pong_len  = write_varint(len(pong_data))
                    conn.sendall(pong_len + pong_data)

        elif next_state == 2:
            time.sleep(0.1)
            kick_pkt = write_varint_packet(0x00, build_kick_message())
            conn.sendall(kick_pkt)
            time.sleep(0.1)

    except:
        pass
    finally:
        time.sleep(0.2)
        conn.close()


def pipe_conns(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except:
        pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass


def route_connection(client):
    try:
        client.settimeout(5)
        peek = client.recv(9)
        client.settimeout(None)

        if not peek:
            client.close()
            return

        is_ssh = (
            len(peek) >= 4 and
            peek[0] == 0x53 and
            peek[1] == 0x53 and
            peek[2] == 0x48 and
            peek[3] == 0x2D
        )

        if is_ssh:
            try:
                backend = socket.create_connection(("127.0.0.1", ssh_backend_port))
            except Exception as e:
                log_warn(f"[!] SSH backend unreachable: {e}")
                client.close()
                return
            backend.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            backend.sendall(peek)
            threading.Thread(target=pipe_conns, args=(client, backend), daemon=True).start()
            threading.Thread(target=pipe_conns, args=(backend, client), daemon=True).start()
            return

        looks_like_mc = (peek[0] & 0x80) == 0 and peek[0] > 0
        if looks_like_mc:
            threading.Thread(target=handle_minecraft_inline, args=(client, peek), daemon=True).start()
            return

        client.close()
    except:
        try: client.close()
        except: pass


def start_proxy():
    global running
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind((ssh_ip, proxy_port))
        server.listen(128)
    except Exception as e:
        log_severe(f"Proxy failed to start: {e}")
        return
    server.settimeout(1)
    log_info(f"[+] Proxy on {ssh_ip}:{proxy_port} (SSH->127.0.0.1:{ssh_backend_port} | MC handled inline)")
    while running:
        try:
            client, _ = server.accept()
            threading.Thread(target=route_connection, args=(client,), daemon=True).start()
        except socket.timeout:
            continue
        except:
            continue
    server.close()


def start_player_count_ticker():
    global player_count, running
    with player_lock:
        player_count = random.randint(20500, 219999)

    def tick():
        global player_count, running
        while running:
            time.sleep(3)
            with player_lock:
                player_count = random.randint(20500, 219999)

    t = threading.Thread(target=tick, daemon=True)
    t.start()


def wait_for_backend_then_start_proxy():
    log_info(f"[*] Waiting for SSH backend on port {ssh_backend_port}...")

    def waiter():
        for _ in range(120):
            if not is_port_available(ssh_backend_port):
                log_info("[+] SSH backend up, starting proxy")
                start_player_count_ticker()
                start_proxy()
                return
            time.sleep(1)
        log_warn("[!] SSH backend timeout after 120s, starting proxy anyway")
        start_player_count_ticker()
        start_proxy()

    t = threading.Thread(target=waiter, daemon=True)
    t.start()


def create_ssh_wrapper():
    work_dir = os.path.join(must_cwd(), "work")
    if not file_exists(work_dir):
        return
    wrapper = os.path.join(work_dir, "ssh.sh")
    try:
        os.remove(wrapper)
    except:
        pass
    script = r"""#!/bin/bash
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
"""
    try:
        with open(wrapper, "w") as f:
            f.write(script)
        os.chmod(wrapper, 0o755)
    except Exception as e:
        log_warn(f"createSSHWrapper: {e}")


def watch_for_installed():
    def watcher():
        work_dir = os.path.join(must_cwd(), "work")
        for _ in range(60):
            if file_exists(work_dir) and file_exists(os.path.join(work_dir, ".installed")):
                time.sleep(1)
                create_ssh_wrapper()
                return
            time.sleep(1)

    t = threading.Thread(target=watcher, daemon=True)
    t.start()


def create_default_script(script_path):
    s = r"""#!/bin/sh
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
"""
    try:
        with open(script_path, "w") as f:
            f.write(s)
        os.chmod(script_path, 0o755)
        return True
    except:
        return False


def extract_tar_xz(tar_path, dest_dir):
    os.makedirs(dest_dir, exist_ok=True)
    ret = subprocess.run(["tar", "-xJf", tar_path, "-C", dest_dir])
    return ret.returncode == 0


def extract_bin_from_tar_xz(tar_path, dest_dir, dest_name):
    dest_file   = os.path.join(dest_dir, dest_name)
    tmp_extract = f"/tmp/bin_extract_{dest_name}_{int(time.time()*1000000)}"
    del_path(tmp_extract)
    os.makedirs(tmp_extract, exist_ok=True)

    if extract_tar_xz(tar_path, tmp_extract):
        try:
            entries = [e for e in os.listdir(tmp_extract) if os.path.isfile(os.path.join(tmp_extract, e))]
            if entries:
                os.makedirs(dest_dir, exist_ok=True)
                src = os.path.join(tmp_extract, entries[0])
                shutil.copy2(src, dest_file)
        except Exception as e:
            log_warn(f"extract_bin_from_tar_xz [{tar_path}]: {e}")
    else:
        log_warn(f"extract_bin_from_tar_xz [{tar_path}]: tar failed")

    del_path(tmp_extract)

    if file_exists(dest_file):
        os.chmod(dest_file, 0o755)

    return dest_file


def is_executable(p):
    return os.path.isfile(p) and os.access(p, os.X_OK)


def install_bins(work_dir):
    suffix  = get_arch_suffix()
    bin_dir = os.path.join(work_dir, "usr/local/bin")
    os.makedirs(bin_dir, exist_ok=True)

    targets = [
        ("cryruss",    "cryruss-"    + suffix),
        ("journalctl", "journalctl-" + suffix),
        ("systemctl",  "systemctl-"  + suffix),
    ]

    for name, resource_name in targets:
        dest_file = os.path.join(bin_dir, name)
        if file_exists(dest_file) and is_executable(dest_file):
            continue
        tar_path = os.path.join(must_cwd(), resource_name + ".tar.xz")
        result   = extract_bin_from_tar_xz(tar_path, bin_dir, name)
        if not file_exists(result):
            for dep_name, dep_url in extra_bins:
                if dep_name == resource_name:
                    log_info(f"[*] Downloading {resource_name}...")
                    ret = subprocess.run(["curl", "-fsSL", "-o", dest_file, dep_url])
                    if ret.returncode != 0:
                        log_warn(f"Failed to download {resource_name}")
                    else:
                        os.chmod(dest_file, 0o755)
                    break
        if file_exists(dest_file):
            log_info(f"[+] Ready: {dest_file}")
        else:
            log_warn(f"[!] Binary missing: {name}")


def fallback_local():
    log_info("[*] Local resources fallback...")
    w           = os.path.join(must_cwd(), DIR)
    arch_suffix = get_arch_suffix_full()
    bin_suffix  = get_arch_suffix()

    arch_alt_map = {"aarch64": "arm64", "armv6": "armv6", "armv7": "armv7"}
    arch_alt     = arch_alt_map.get(arch_suffix, "amd64")

    supported = {"x86_64", "aarch64", "armv6", "armv7"}
    if arch_suffix not in supported:
        log_severe(f"Unsupported arch: {arch_suffix}")
        return False

    os.makedirs(w, exist_ok=True)
    bin_dir = os.path.join(w, "usr/local/bin")
    os.makedirs(bin_dir, exist_ok=True)

    proot_tar = os.path.join(must_cwd(), f"proot-{arch_suffix}.tar.xz")
    proot_bin = extract_bin_from_tar_xz(proot_tar, bin_dir, "proot")
    if not file_exists(proot_bin):
        log_severe("proot not extracted")
        return False

    busybox_tar = os.path.join(must_cwd(), f"busybox-{arch_suffix}.tar.xz")
    extract_bin_from_tar_xz(busybox_tar, w, f"busybox-{arch_suffix}")

    local_bins = [
        ("cryruss",    "cryruss-"    + bin_suffix),
        ("journalctl", "journalctl-" + bin_suffix),
        ("systemctl",  "systemctl-"  + bin_suffix),
    ]

    for name, resource_name in local_bins:
        dest_bin = os.path.join(bin_dir, name)
        if file_exists(dest_bin) and is_executable(dest_bin):
            continue
        tar_path = os.path.join(must_cwd(), resource_name + ".tar.xz")
        result   = extract_bin_from_tar_xz(tar_path, bin_dir, name)
        if not file_exists(result):
            for dep_name, dep_url in extra_bins:
                if dep_name == resource_name:
                    ret = subprocess.run(["curl", "-fsSL", "-o", dest_bin, dep_url])
                    if ret.returncode != 0:
                        log_warn(f"Failed to download {resource_name}")
                    else:
                        os.chmod(dest_bin, 0o755)
                    break
        if file_exists(dest_bin):
            log_info(f"[+] Ready: {name}")

    ubuntu_tar = os.path.join(must_cwd(), f"ubuntu-base-22.04.5-base-{arch_alt}.tar.xz")
    if not extract_tar_xz(ubuntu_tar, w):
        log_warn("ubuntu tar extract failed")

    script_path      = os.path.join(w, SH)
    embedded_script  = os.path.join(must_cwd(), "META-INF", "noninteractive.sh")
    if file_exists(embedded_script):
        try:
            with open(embedded_script, "r") as f:
                data = f.read()
            with open(script_path, "w") as f:
                f.write(data)
            os.chmod(script_path, 0o755)
        except:
            create_default_script(script_path)
    else:
        create_default_script(script_path)

    log_info("[+] Local fallback done")
    return True


def load_config():
    global ssh_ip, proxy_port, ssh_backend_port
    users["root"] = "root"

    try:
        f = open("server.properties", "r")
    except:
        log_info("[*] No server.properties found, using defaults")
        ssh_ip           = "0.0.0.0"
        proxy_port       = 2222
        ssh_backend_port = 2223
        return

    props = {}
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        idx = line.find("=")
        if idx != -1:
            props[line[:idx].strip()] = line[idx+1:].strip()
    f.close()

    ssh_ip = props.get("server-ip", "") or "0.0.0.0"

    try:
        p = int(props.get("server-port", "2222"))
        proxy_port = p if p > 0 else 2222
    except:
        proxy_port = 2222

    ssh_backend_port = proxy_port + 1
    log_info(f"[+] Config loaded: proxy={ssh_ip}:{proxy_port} | ssh_backend=127.0.0.1:{ssh_backend_port}")


def after_install(work_dir, script_name):
    global running
    if not file_exists(os.path.join(work_dir, ".installed")):
        log_severe("[!] .installed not found, abort.")
        return

    install_bins(work_dir)
    subprocess.run(["chmod", "-R", "755", os.path.join(work_dir, "usr/local/bin")])
    create_ssh_wrapper()

    term        = os.environ.get("TERM", "xterm-256color")
    script_path = os.path.join(work_dir, script_name)

    env = os.environ.copy()
    env["TERM"]   = term
    env["LC_ALL"] = "C"
    env["LANG"]   = "C"
    env["TMOUT"]  = "0"

    while running:
        ret = subprocess.run(["bash", script_path], cwd=work_dir, env=env)
        if ret.returncode != 0:
            log_info(f"[*] Session exited ({ret.returncode}), restarting in 2s...")
        else:
            log_info("[*] Session exited (0), restarting in 2s...")
        time.sleep(2)


def exec_script(work_dir, script_name):
    log_info("[*] Executing noninteractive.sh...")
    installed_marker = os.path.join(work_dir, ".installed")
    script_path      = os.path.join(work_dir, script_name)

    if not file_exists(installed_marker):
        proc = subprocess.Popen(
            ["bash", script_name],
            cwd=work_dir,
            stdin=subprocess.DEVNULL,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
        killed = False
        for _ in range(300):
            time.sleep(1)
            if file_exists(installed_marker):
                if not killed:
                    proc.kill()
                    killed = True
                break
        if not killed:
            proc.kill()
        proc.wait()

    after_install(work_dir, script_name)


def run_after_fallback():
    wf = os.path.join(must_cwd(), DIR)
    sf = os.path.join(wf, SH)
    if file_exists(sf):
        os.chmod(sf, 0o755)
        exec_script(wf, SH)
    else:
        log_warn("[!] Fallback did not create work dir")


def main():
    global running
    args   = sys.argv[1:]
    no_net = False

    for a in args:
        if a in ("--help", "help"):
            print("Usage: python main.py [options]")
            print("  --help    Show this help")
            print("  --nonet   Use embedded resources, skip git clone")
            return
        if a == "--nonet":
            no_net = True
            log_info("[*] --nonet mode: using embedded resources")

    random.seed(time.time())
    load_config()
    wait_for_backend_then_start_proxy()
    watch_for_installed()

    if not cmd_exists("bash"):
        log_severe("Bash not found")
        sys.exit(1)

    w = os.path.join(must_cwd(), DIR)
    if file_exists(w):
        log_info("[*] 'work' exists, checking...")
        s = os.path.join(w, SH)
        if file_exists(s):
            log_info("[+] Valid repo found, skipping clone")
            os.chmod(s, 0o755)
            exec_script(w, SH)
            return
        log_warn("Invalid repo, removing...")
        del_path(w)

    t = os.path.join(must_cwd(), TMPDIR)
    del_path(t)

    if no_net:
        log_info("[*] --nonet: skipping clone, using embedded resources")
        if not fallback_local():
            log_severe("Fallback failed")
            sys.exit(1)
        run_after_fallback()
        return

    if not cmd_exists("git"):
        log_warn("Git not found, using fallback")
        if not fallback_local():
            log_severe("Fallback failed")
            sys.exit(1)
        run_after_fallback()
        return

    if not clone_repo():
        log_warn("All clones failed, trying fallback...")
        clean_path(t)
        if not fallback_local():
            log_severe("Fallback failed")
            sys.exit(1)
        run_after_fallback()
        return

    try:
        shutil.move(t, w)
    except Exception as e:
        log_severe(f"Rename failed: {e}")
        clean_path(t)
        sys.exit(1)

    log_info("[+] Renamed to 'work'")

    s = os.path.join(w, SH)
    if not file_exists(s):
        log_severe("Script not found")
        clean_path(w)
        sys.exit(1)

    os.chmod(s, 0o755)
    exec_script(w, SH)
    log_info("[+] Freeroot")


if __name__ == "__main__":
    main()