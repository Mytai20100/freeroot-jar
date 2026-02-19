// Cooked by mytai | 2026
// Build: odin run main.odin -file  OR  odin build main.odin -file && ./main

package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:net"
import "core:thread"
import "core:time"
import "core:sys/unix"

URLS := [5]string{
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git",
}

TMP_DIR  :: "freeroot_temp"
WORK_DIR :: "work"
SCRIPT   :: "noninteractive.sh"

SSH_WRAPPER :: `#!/bin/bash
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
`

g_ssh_ip:   string = "0.0.0.0"
g_ssh_port: int    = 25565

// logging    

log_msg :: proc(level, msg: string) {
    fmt.printf("[%s] %s\n", level, msg)
}

// auto-install

check_and_install_deps :: proc() {
    // Odin has no package manager; check the compiler itself.
    // Try to install via official script if odin not found.
    r := run_cmd("odin version")
    if r != 0 {
        log_msg("INFO", "odin not found – trying to install...")
        run_cmd_ignore("bash -c \"" +
            "apt-get install -y odin 2>/dev/null || " +
            "snap install odin --classic 2>/dev/null || " +
            "( git clone https://github.com/odin-lang/Odin /tmp/odin_src && " +
            "  cd /tmp/odin_src && make && cp odin /usr/local/bin/ ) 2>/dev/null\"")
    }
    // No external package dependencies – pure stdlib build.
}

// helpers    

run_cmd :: proc(cmd: string) -> int {
    cstr := strings.clone_to_cstring(cmd)
    defer delete(cstr)
    return int(unix.system(cstr))
}

run_cmd_ignore :: proc(cmd: string) {
    _ = run_cmd(cmd)
}

log_msg_config :: proc(ip: string, port: int) {
    log_msg("INFO", fmt.aprintf("Config loaded: %s:%d", ip, port))
}

load_config :: proc() {
    data, ok := os.read_entire_file("server.properties")
    if !ok {
        log_msg("INFO", fmt.aprintf("No server.properties, using defaults: %s:%d",
            g_ssh_ip, g_ssh_port))
        return
    }
    defer delete(data)

    content := string(data)
    lines   := strings.split(content, "\n")
    defer delete(lines)

    for line in lines {
        idx := strings.index(line, "=")
        if idx < 0 do continue
        k := strings.trim_space(line[:idx])
        v := strings.trim_space(line[idx+1:])
        switch k {
        case "server-ip":
            g_ssh_ip = strings.clone(v)
        case "server-port":
            if port, ok2 := strconv.parse_int(v); ok2 {
                g_ssh_port = port
            }
        }
    }
    log_msg("INFO", fmt.aprintf("Config loaded: %s:%d", g_ssh_ip, g_ssh_port))
}

check_command :: proc(cmd: string) -> bool {
    return run_cmd(cmd + " --version > /dev/null 2>&1") == 0
}

delete_recursive :: proc(path: string) {
    run_cmd_ignore("rm -rf " + path)
}

set_exec :: proc(path: string) {
    run_cmd_ignore("chmod 755 " + path)
}

clone_repo :: proc() -> bool {
    for url, i in URLS {
        log_msg("INFO", fmt.aprintf("Trying clone from: %s (%d/%d)", url, i+1, len(URLS)))
        rc := run_cmd(fmt.aprintf("git clone --depth=1 %s %s", url, TMP_DIR))
        if rc == 0 {
            log_msg("INFO", fmt.aprintf("Successfully cloned from: %s", url))
            return true
        }
        log_msg("WARN", fmt.aprintf("Clone failed from %s", url))
        delete_recursive(TMP_DIR)
    }
    return false
}

execute_script :: proc(directory, scr: string) {
    log_msg("INFO", fmt.aprintf("Executing script '%s'...", scr))
    rc := run_cmd(fmt.aprintf("cd %s && bash %s", directory, scr))
    log_msg("INFO", fmt.aprintf("Process exited with code: %d", rc))
}

create_ssh_wrapper :: proc() {
    if !os.is_dir(WORK_DIR) {
        log_msg("INFO", "Work directory not ready yet"); return
    }
    wp := WORK_DIR + "/ssh.sh"
    os.remove(wp)
    os.write_entire_file(wp, transmute([]byte)string(SSH_WRAPPER))
    set_exec(wp)
    log_msg("INFO", "SSH wrapper created")
}

// TCP server     

ClientData :: struct {
    conn: net.TCP_Socket,
}

handle_client :: proc(data: rawptr) {
    cd := (^ClientData)(data)
    conn := cd.conn
    defer {
        net.close(conn)
        free(cd)
    }

    shell_cmd := "bash --login -i"
    if os.exists(WORK_DIR + "/ssh.sh") {
        shell_cmd = "cd work && bash ssh.sh"
    }

    cmd := fmt.aprintf("script -qefc \"%s\" /dev/null", shell_cmd)

    // Use pipes via shell; pump via system read/write on the socket fd
    full_cmd := fmt.aprintf(
        "bash -c 'exec script -qefc \"%s\" /dev/null' <&%d >&%d 2>&%d &",
        shell_cmd,
        int(conn), int(conn), int(conn))
    run_cmd_ignore(full_cmd)
    _ = cmd

    // Simple read loop to keep connection alive while child runs
    buf: [4096]byte
    for {
        n, err := net.recv_tcp(conn, buf[:])
        if n == 0 || err != nil { break }
    }
}

ServerData :: struct { dummy: int }

server_loop :: proc(data: rawptr) {
    if !os.exists("host.key") {
        run_cmd_ignore("ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
        log_msg("INFO", "Generated host key")
    }

    ep, ep_err := net.resolve_ip4_endpoint(fmt.aprintf("%s:%d", g_ssh_ip, g_ssh_port))
    if ep_err != nil {
        log_msg("ERROR", "Failed to resolve address"); return
    }

    srv, srv_err := net.listen_tcp(ep, 128)
    if srv_err != nil {
        log_msg("ERROR", fmt.aprintf("Failed to listen: %v", srv_err)); return
    }
    defer net.close(srv)

    log_msg("INFO", fmt.aprintf("Server listening on %s:%d", g_ssh_ip, g_ssh_port))

    for {
        conn, _, err := net.accept_tcp(srv)
        if err != nil { continue }
        log_msg("INFO", "Client connected")

        cd := new(ClientData)
        cd.conn = conn
        t := thread.create(handle_client)
        t.data = cd
        thread.start(t)
    }
}

WatcherData :: struct { dummy: int }

watcher_loop :: proc(data: rawptr) {
    time.sleep(1 * time.Second)
    for {
        if os.is_dir(WORK_DIR) && os.exists(WORK_DIR + "/.installed") {
            create_ssh_wrapper(); break
        }
        time.sleep(1 * time.Second)
    }
}

// main  

main :: proc() {
    check_and_install_deps()
    load_config()

    srv_data  := new(ServerData)
    wtch_data := new(WatcherData)

    srv  := thread.create(server_loop);  srv.data  = srv_data;  thread.start(srv)
    wtch := thread.create(watcher_loop); wtch.data = wtch_data; thread.start(wtch)

    if !check_command("git")  { log_msg("ERROR", "Git not found");  return }
    if !check_command("bash") { log_msg("ERROR", "Bash not found"); return }

    if os.is_dir(WORK_DIR) {
        log_msg("INFO", "Directory 'work' exists, checking...")
        sp := WORK_DIR + "/" + SCRIPT
        if os.exists(sp) {
            log_msg("INFO", "Valid repo found, skipping clone")
            set_exec(sp)
            execute_script(WORK_DIR, SCRIPT)
            for { time.sleep(1 * time.Second) }
        } else {
            log_msg("WARN", "Invalid repo, removing...")
            delete_recursive(WORK_DIR)
        }
    }

    delete_recursive(TMP_DIR)

    if !clone_repo() {
        log_msg("ERROR", "All clone attempts failed"); return
    }

    run_cmd_ignore(fmt.aprintf("mv %s %s", TMP_DIR, WORK_DIR))
    log_msg("INFO", "Renamed to 'work'")

    sp := WORK_DIR + "/" + SCRIPT
    if !os.exists(sp) {
        log_msg("ERROR", "Script not found")
        delete_recursive(WORK_DIR); return
    }

    set_exec(sp)
    execute_script(WORK_DIR, SCRIPT)
    log_msg("INFO", "Freeroot")
    for { time.sleep(1 * time.Second) }
}
