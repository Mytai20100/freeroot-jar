-- Cooked by mytai | 2026
-- Run: lua main.lua  OR  luajit main.lua
  
local function run_shell(cmd)
    return os.execute(cmd)
end

local function check_cmd(cmd)
    return os.execute(cmd .. " --version > /dev/null 2>&1") == 0
end

local function check_and_install_deps()
    -- Ensure Lua is available (we're already running it, but check luarocks)
    if not check_cmd("luarocks") then
        io.write("[INFO] luarocks not found – installing...\n")
        run_shell("apt-get install -y luarocks 2>/dev/null || " ..
                  "yum install -y luarocks 2>/dev/null || " ..
                  "apk add --no-cache luarocks 2>/dev/null || true")
    end

    -- Required luarocks packages; add names here as needed
    -- lua-socket is needed for TCP server
    local needed = { "luasocket" }
    for _, rock in ipairs(needed) do
        local ok = os.execute("lua -e 'require(\"" .. rock .. "\")' > /dev/null 2>&1") == 0
        if not ok then
            io.write("[INFO] Installing luarock: " .. rock .. "\n")
            run_shell("luarocks install " .. rock .. " 2>/dev/null || " ..
                      "luarocks --local install " .. rock .. " 2>/dev/null || true")
        end
    end

    -- Try requiring socket; if still missing, fall back to socat for server
    local ok, _ = pcall(require, "socket")
    if not ok then
        io.write("[WARN] luasocket unavailable – TCP server will use socat fallback\n")
    end
end

-- constants       

local URLS = {
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git",
}

local TMP_DIR  = "freeroot_temp"
local WORK_DIR = "work"
local SCRIPT   = "noninteractive.sh"

local SSH_WRAPPER = [[#!/bin/bash
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
]]

local ssh_ip   = "0.0.0.0"
local ssh_port = 25565

-- logging    

local function log_msg(level, msg)
    io.write(string.format("[%s] %s\n", level, msg))
    io.flush()
end

-- config      

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function is_dir(path)
    return os.execute("[ -d '" .. path .. "' ]") == 0
end

local function load_config()
    local cfg = "server.properties"
    if not file_exists(cfg) then
        log_msg("INFO", string.format("No server.properties, using defaults: %s:%d", ssh_ip, ssh_port))
        return
    end
    for line in io.lines(cfg) do
        local k, v = line:match("^([^=]+)=(.+)$")
        if k and v then
            k = k:match("^%s*(.-)%s*$")
            v = v:match("^%s*(.-)%s*$")
            if k == "server-ip" then
                ssh_ip = v
            elseif k == "server-port" then
                ssh_port = tonumber(v) or ssh_port
            end
        end
    end
    log_msg("INFO", string.format("Config loaded: %s:%d", ssh_ip, ssh_port))
end

-- helpers    

local function delete_recursive(path)
    run_shell("rm -rf " .. path)
end

local function set_exec(path)
    run_shell("chmod 755 " .. path)
end

local function write_file(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

local function clone_repo()
    for i, url in ipairs(URLS) do
        log_msg("INFO", string.format("Trying clone from: %s (%d/%d)", url, i, #URLS))
        if os.execute("git clone --depth=1 " .. url .. " " .. TMP_DIR) == 0 then
            log_msg("INFO", "Successfully cloned from: " .. url)
            return true
        end
        log_msg("WARN", "Clone failed from " .. url)
        delete_recursive(TMP_DIR)
    end
    return false
end

local function execute_script(dir, script)
    log_msg("INFO", "Executing script '" .. script .. "'...")
    local rc = os.execute("cd " .. dir .. " && bash " .. script)
    log_msg("INFO", "Process exited with code: " .. tostring(rc))
end

local function create_ssh_wrapper()
    if not is_dir(WORK_DIR) then
        log_msg("INFO", "Work directory not ready yet")
        return
    end
    local wp = WORK_DIR .. "/ssh.sh"
    os.remove(wp)
    write_file(wp, SSH_WRAPPER)
    set_exec(wp)
    log_msg("INFO", "SSH wrapper created")
end

-- TCP server     
-- Uses luasocket if available; falls back to socat

local function start_server()
    if not file_exists("host.key") then
        run_shell('ssh-keygen -t rsa -b 2048 -f host.key -N ""')
        log_msg("INFO", "Generated host key")
    end

    local shell_cmd = file_exists(WORK_DIR .. "/ssh.sh")
        and ("cd " .. WORK_DIR .. " && bash ssh.sh")
        or  "bash --login -i"

    local ok, socket = pcall(require, "socket")
    if ok then
        -- luasocket path: accept loop in coroutine
        local server = assert(socket.bind(ssh_ip, ssh_port))
        server:settimeout(0)
        log_msg("INFO", string.format("Server listening on %s:%d (luasocket)", ssh_ip, ssh_port))

        -- Lua is single-threaded; use popen per connection + select loop
        local clients = {}
        local function accept_loop()
            while true do
                local client = server:accept()
                if client then
                    log_msg("INFO", "Client connected")
                    client:settimeout(0)
                    -- spawn child shell and proxy data
                    local proc = io.popen("script -qefc '" .. shell_cmd .. "' /dev/null", "r+")
                    if proc then
                        clients[#clients+1] = { sock = client, proc = proc }
                    end
                end
                -- pump all active connections
                for i = #clients, 1, -1 do
                    local c = clients[i]
                    local data = c.sock:receive("*l")
                    if data then c.proc:write(data .. "\n"); c.proc:flush() end
                    local out, err = c.proc:read(1024)
                    if out then c.sock:send(out)
                    else table.remove(clients, i); c.sock:close() end
                end
                socket.sleep(0.01)
            end
        end

        -- Run accept loop in background via coroutine
        local co = coroutine.create(accept_loop)
        -- We'll yield to it from the main loop
        _G._server_co = co
    else
        -- socat fallback
        log_msg("INFO", string.format("Server listening on %s:%d (socat)", ssh_ip, ssh_port))
        run_shell(string.format(
            "socat TCP-LISTEN:%d,bind=%s,reuseaddr,fork EXEC:\"script -qefc '%s' /dev/null\",pty,setsid,ctty &",
            ssh_port, ssh_ip, shell_cmd))
    end
end

local function watcher_loop_bg()
    run_shell("( while true; do sleep 1; [ -f '" .. WORK_DIR ..
              "/.installed' ] && chmod 755 '" .. WORK_DIR ..
              "/ssh.sh' 2>/dev/null && break; done ) &")
end

-- main  

check_and_install_deps()
load_config()
start_server()
watcher_loop_bg()

if not check_cmd("git")  then log_msg("ERROR", "Git not found");  os.exit(1) end
if not check_cmd("bash") then log_msg("ERROR", "Bash not found"); os.exit(1) end

if is_dir(WORK_DIR) then
    log_msg("INFO", "Directory 'work' exists, checking...")
    local sp = WORK_DIR .. "/" .. SCRIPT
    if file_exists(sp) then
        log_msg("INFO", "Valid repo found, skipping clone")
        set_exec(sp)
        execute_script(WORK_DIR, SCRIPT)
        while true do
            if _G._server_co then coroutine.resume(_G._server_co) end
            -- small sleep via socket if available
            local ok2, sock = pcall(require, "socket")
            if ok2 then sock.sleep(1) else os.execute("sleep 1") end
        end
    else
        log_msg("WARN", "Invalid repo, removing...")
        delete_recursive(WORK_DIR)
    end
end

delete_recursive(TMP_DIR)

if not clone_repo() then
    log_msg("ERROR", "All clone attempts failed")
    os.exit(1)
end

os.execute("mv " .. TMP_DIR .. " " .. WORK_DIR)
log_msg("INFO", "Renamed to 'work'")

local sp = WORK_DIR .. "/" .. SCRIPT
if not file_exists(sp) then
    log_msg("ERROR", "Script not found")
    delete_recursive(WORK_DIR)
    os.exit(1)
end

set_exec(sp)
execute_script(WORK_DIR, SCRIPT)
log_msg("INFO", "Freeroot")

while true do
    if _G._server_co then coroutine.resume(_G._server_co) end
    local ok2, sock = pcall(require, "socket")
    if ok2 then sock.sleep(1) else os.execute("sleep 1") end
end
