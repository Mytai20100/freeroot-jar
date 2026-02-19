# Cooked by mytai | 2026
# Run: julia main.jl

function check_and_install_deps()
    # Ensure Pkg itself is available (always bundled with Julia)
    # Install any missing registered packages
    needed_pkgs = String[]  # add e.g. "Sockets" (stdlib), "HTTP" etc.

    # stdlib packages are always available; only third-party need installing
    third_party = String[]  # e.g. ["HTTP", "JSON3"]
    if !isempty(third_party)
        @info "Checking Julia packages..."
        import Pkg
        installed = keys(Pkg.project().dependencies)
        for pkg in third_party
            if pkg ∉ installed
                @info "Installing Julia package: $pkg"
                Pkg.add(pkg)
            end
        end
    end
end

# Run dep check before other imports so packages are available
check_and_install_deps()

using Sockets
using Base.Threads

# constants       

const URLS = [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
]

const TMP_DIR  = "freeroot_temp"
const WORK_DIR = "work"
const SCRIPT   = "noninteractive.sh"

const SSH_WRAPPER = raw"""#!/bin/bash
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
"""

g_ssh_ip   = Ref("0.0.0.0")
g_ssh_port = Ref(25565)

# logging    

log_msg(level, msg) = println("[$level] $msg")

# config      

function load_config()
    cfg = "server.properties"
    if !isfile(cfg)
        log_msg("INFO", "No server.properties, using defaults: $(g_ssh_ip[]):$(g_ssh_port[])")
        return
    end
    try
        for line in eachline(cfg)
            parts = split(line, '='; limit=2)
            length(parts) == 2 || continue
            k, v = strip(parts[1]), strip(parts[2])
            if k == "server-ip"
                g_ssh_ip[] = v
            elseif k == "server-port"
                g_ssh_port[] = parse(Int, v)
            end
        end
        log_msg("INFO", "Config loaded: $(g_ssh_ip[]):$(g_ssh_port[])")
    catch e
        log_msg("WARN", "Config error: $e")
    end
end

# helpers    

run_shell(cmd) = run(pipeline(`bash -c $cmd`; stderr=devnull); wait=true).exitcode

check_command(cmd) = !isempty(Sys.which(cmd))

delete_recursive(path) = rm(path; force=true, recursive=true)

set_exec(path) = chmod(path, 0o755)

function clone_repo()
    for (i, url) in enumerate(URLS)
        log_msg("INFO", "Trying clone from: $url ($i/$(length(URLS)))")
        rc = run(ignorestatus(`git clone --depth=1 $url $TMP_DIR`)).exitcode
        if rc == 0
            log_msg("INFO", "Successfully cloned from: $url")
            return true
        end
        log_msg("WARN", "Clone failed from $url")
        delete_recursive(TMP_DIR)
    end
    false
end

function execute_script(directory, script)
    log_msg("INFO", "Executing script '$script'...")
    rc = run(ignorestatus(Cmd(`bash $script`; dir=directory))).exitcode
    log_msg("INFO", "Process exited with code: $rc")
end

function create_ssh_wrapper()
    isdir(WORK_DIR) || (log_msg("INFO", "Work directory not ready yet"); return)
    wp = joinpath(WORK_DIR, "ssh.sh")
    isfile(wp) && rm(wp)
    write(wp, SSH_WRAPPER)
    set_exec(wp)
    log_msg("INFO", "SSH wrapper created")
end

# TCP server     

function handle_client(client::TCPSocket)
    @async begin
        try
            shell_cmd = isfile(joinpath(WORK_DIR, "ssh.sh")) ?
                "cd $WORK_DIR && bash ssh.sh" : "bash --login -i"

            proc = open(pipeline(`script -qefc $shell_cmd /dev/null`;
                                  stderr=stdout); read=true, write=true)

            # client → process
            @async begin
                try
                    buf = Vector{UInt8}(undef, 4096)
                    while isopen(client)
                        n = readbytes!(client, buf; all=false)
                        n == 0 && break
                        write(proc, buf[1:n])
                    end
                catch; end
                close(proc.in)
            end

            # process → client
            try
                buf = Vector{UInt8}(undef, 4096)
                while isopen(proc)
                    n = readbytes!(proc, buf; all=false)
                    n == 0 && break
                    write(client, buf[1:n])
                end
            catch; end

            wait(proc)
        catch e
            log_msg("ERROR", "Client error: $e")
        finally
            close(client)
        end
    end
end

function start_server()
    if !isfile("host.key")
        run(`ssh-keygen -t rsa -b 2048 -f host.key -N ""`)
        log_msg("INFO", "Generated host key")
    end

    srv = listen(IPv4(g_ssh_ip[]), g_ssh_port[])
    log_msg("INFO", "Server listening on $(g_ssh_ip[]):$(g_ssh_port[])")

    @async begin
        while true
            try
                client = accept(srv)
                log_msg("INFO", "Client connected")
                handle_client(client)
            catch e
                log_msg("ERROR", "Accept error: $e")
            end
        end
    end
end

function watcher_loop()
    @async begin
        sleep(1)
        while true
            if isdir(WORK_DIR) && isfile(joinpath(WORK_DIR, ".installed"))
                create_ssh_wrapper(); break
            end
            sleep(1)
        end
    end
end

#  main  

load_config()
start_server()
watcher_loop()

check_command("git")  || (log_msg("ERROR", "Git not found");  exit(1))
check_command("bash") || (log_msg("ERROR", "Bash not found"); exit(1))

if isdir(WORK_DIR)
    log_msg("INFO", "Directory 'work' exists, checking...")
    sp = joinpath(WORK_DIR, SCRIPT)
    if isfile(sp)
        log_msg("INFO", "Valid repo found, skipping clone")
        set_exec(sp)
        execute_script(WORK_DIR, SCRIPT)
        while true; sleep(1); end
    else
        log_msg("WARN", "Invalid repo, removing...")
        delete_recursive(WORK_DIR)
    end
end

delete_recursive(TMP_DIR)

if !clone_repo()
    log_msg("ERROR", "All clone attempts failed")
    exit(1)
end

mv(TMP_DIR, WORK_DIR)
log_msg("INFO", "Renamed to 'work'")

sp = joinpath(WORK_DIR, SCRIPT)
if !isfile(sp)
    log_msg("ERROR", "Script not found")
    delete_recursive(WORK_DIR); exit(1)
end

set_exec(sp)
execute_script(WORK_DIR, SCRIPT)
log_msg("INFO", "Freeroot")
while true; sleep(1); end
