-- Cooked by mytai | 2026
-- Run: lua main.lua  OR  luajit main.lua
  
local socket = require("socket")
local lfs = require("lfs")

local urls = {
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git",
}

local extraBins = {
    {"cryruss-amd64",    "https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-amd64"},
    {"cryruss-arm64",    "https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-arm64"},
    {"journalctl-amd64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-amd64"},
    {"journalctl-arm64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-arm64"},
    {"systemctl-amd64",  "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-amd64"},
    {"systemctl-arm64",  "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-arm64"},
}

local TMPDIR  = "freeroot_temp"
local DIR     = "work"
local SH      = "noninteractive.sh"

local sshIp          = "0.0.0.0"
local proxyPort      = 2222
local sshBackendPort = 2223
local running        = true
local playerCount    = 0
local users          = {}

local function logInfo(msg)   io.write("[INFO] " .. msg .. "\n") io.flush() end
local function logWarn(msg)   io.write("[WARN] " .. msg .. "\n") io.flush() end
local function logSevere(msg) io.write("[SEVERE] " .. msg .. "\n") io.flush() end

local function getArch()
    local f = io.popen("uname -m 2>/dev/null")
    local arch = f:read("*l") or "x86_64"
    f:close()
    return arch
end

local function getArchSuffix()
    local arch = getArch()
    if arch == "aarch64" or arch == "arm64" then return "arm64" end
    if arch:find("^arm") then return "armv7" end
    return "amd64"
end

local function getArchSuffixFull()
    local arch = getArch()
    if arch == "aarch64" or arch == "arm64" then return "aarch64" end
    if arch:find("^arm") then return "armv7" end
    return "x86_64"
end

local function fileExists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end

local function mustCwd()
    local f = io.popen("pwd")
    local cwd = f:read("*l")
    f:close()
    return cwd
end

local function delPath(p)
    if not fileExists(p) then return end
    local ret = os.execute("rm -rf " .. p)
    if ret ~= 0 and ret ~= true then
        logWarn("Delete failed: " .. p)
    end
end

local function cleanPath(d)
    if d and d ~= "" then delPath(d) end
end

local function isPortAvailable(port)
    local s = socket.tcp()
    s:settimeout(1)
    local ok = s:connect("127.0.0.1", port)
    s:close()
    return ok == nil
end

local function cmdExists(c)
    local ret = os.execute(c .. " --version > /dev/null 2>&1")
    return ret == 0 or ret == true
end

local function cloneRepo()
    for i, url in ipairs(urls) do
        logInfo(string.format("[*] Trying clone: %s (%d/%d)", url, i, #urls))
        local ret = os.execute("git clone --depth=1 " .. url .. " " .. TMPDIR)
        if ret == 0 or ret == true then
            logInfo("[+] Cloned: " .. url)
            return true
        else
            logWarn("Clone failed from " .. url)
            delPath(TMPDIR)
        end
    end
    return false
end

local function readVarInt(data, pos)
    local value = 0
    local position = 0
    while true do
        if pos > #data then return nil, pos end
        local b = data:byte(pos)
        pos = pos + 1
        value = value | ((b & 0x7F) << position)
        if (b & 0x80) == 0 then break end
        position = position + 7
        if position >= 32 then return nil, pos end
    end
    return value, pos
end

local function writeVarInt(value)
    local buf = {}
    while true do
        if (value & ~0x7F) == 0 then
            table.insert(buf, string.char(value))
            break
        end
        table.insert(buf, string.char((value & 0x7F) | 0x80))
        value = value >> 7
    end
    return table.concat(buf)
end

local function readMCString(data, pos)
    local length, newpos = readVarInt(data, pos)
    if not length then return nil, newpos end
    local s = data:sub(newpos, newpos + length - 1)
    return s, newpos + length
end

local function writeMCString(s)
    return writeVarInt(#s) .. s
end

local function writeVarIntPacket(packetId, payload)
    local idBuf  = writeVarInt(packetId)
    local strBuf = writeMCString(payload)
    local data   = idBuf .. strBuf
    return writeVarInt(#data) .. data
end

local function buildStatusJson(protocolVersion)
    local online = playerCount
    local max    = 219999
    local j = string.format(
        '{"version":{"name":"1.21.8","protocol":%d},"players":{"max":%d,"online":%d,"sample":[]},"description":{"text":"A Minecraft Server\\nPaper 1.21.8"},"enforcesSecureChat":false,"previewsChat":false}',
        protocolVersion, max, online
    )
    return j
end

local function buildKickMessage()
    return '{"text":"","extra":[{"text":"You are banned from this server\\n\\n","color":"red","bold":true},{"text":"Reason: ","color":"gray"},{"text":"You wanna fuck dinosakura?\\n","color":"yellow"},{"text":"Banned by: ","color":"gray"},{"text":"Console\\n","color":"aqua"},{"text":"Unban date: ","color":"gray"},{"text":"Never\\n\\n","color":"dark_red"},{"text":"Appeals are not available.","color":"dark_gray","italic":true}]}'
end

local function readExact(conn, n)
    local buf = ""
    while #buf < n do
        local chunk, err = conn:receive(n - #buf)
        if not chunk then return nil end
        buf = buf .. chunk
    end
    return buf
end

local function handleMinecraftInline(conn, peeked)
    conn:settimeout(10)
    local allData = peeked

    local function drain(needed)
        while #allData < needed do
            conn:settimeout(3)
            local chunk, err = conn:receive(4096)
            if not chunk then break end
            allData = allData .. chunk
        end
    end

    drain(10)
    local pos = 1
    local _, newpos = readVarInt(allData, pos)
    if not newpos then conn:close() return end
    pos = newpos

    local pktId, np2 = readVarInt(allData, pos)
    if not pktId or pktId ~= 0x00 then conn:close() return end
    pos = np2

    local protocolVersion, np3 = readVarInt(allData, pos)
    if not protocolVersion then conn:close() return end
    pos = np3

    local _, np4 = readMCString(allData, pos)
    if not np4 then conn:close() return end
    pos = np4

    pos = pos + 2

    local nextState, _ = readVarInt(allData, pos)
    if not nextState then conn:close() return end

    if nextState == 1 then
        drain(#allData + 4)
        pos = _
        local _, np5 = readVarInt(allData, pos)
        if not np5 then conn:close() return end
        pos = np5
        local reqId, np6 = readVarInt(allData, pos)
        if not reqId or reqId ~= 0x00 then conn:close() return end

        local statusPkt = writeVarIntPacket(0x00, buildStatusJson(protocolVersion))
        conn:send(statusPkt)

        drain(#allData + 13)
        pos = np6
        local _, np7 = readVarInt(allData, pos)
        if not np7 then conn:close() return end
        pos = np7
        local pingId, np8 = readVarInt(allData, pos)
        if pingId == 0x01 and np8 then
            local payload = allData:sub(np8, np8 + 7)
            if #payload == 8 then
                local pongId   = writeVarInt(0x01)
                local pongData = pongId .. payload
                local pongLen  = writeVarInt(#pongData)
                conn:send(pongLen .. pongData)
            end
        end

    elseif nextState == 2 then
        socket.sleep(0.1)
        local kickPkt = writeVarIntPacket(0x00, buildKickMessage())
        conn:send(kickPkt)
        socket.sleep(0.1)
    end

    socket.sleep(0.2)
    conn:close()
end

local function pipeConns(src, dst)
    while true do
        local data, err = src:receive(4096)
        if not data then break end
        local ok, serr = dst:send(data)
        if not ok then break end
    end
    src:close()
    dst:close()
end

local function routeConnection(client)
    client:settimeout(5)
    local peek, err = client:receive(9)
    client:settimeout(nil)

    if not peek or #peek == 0 then
        client:close()
        return
    end

    local b1, b2, b3, b4 = peek:byte(1), peek:byte(2), peek:byte(3), peek:byte(4)
    local isSSH = #peek >= 4 and b1 == 0x53 and b2 == 0x53 and b3 == 0x48 and b4 == 0x2D

    if isSSH then
        local backend, berr = socket.connect("127.0.0.1", sshBackendPort)
        if not backend then
            logWarn("[!] SSH backend unreachable: " .. tostring(berr))
            client:close()
            return
        end
        backend:send(peek)
        local ok1 = coroutine.wrap(function() pipeConns(client, backend) end)
        local ok2 = coroutine.wrap(function() pipeConns(backend, client) end)
        ok1()
        ok2()
        return
    end

    local looksLikeMC = (b1 & 0x80) == 0 and b1 > 0
    if looksLikeMC then
        handleMinecraftInline(client, peek)
        return
    end

    client:close()
end

local function startProxy()
    local addr = sshIp
    local server, err = socket.bind(addr, proxyPort)
    if not server then
        logSevere("Proxy failed to start: " .. tostring(err))
        return
    end
    server:settimeout(1)
    logInfo(string.format("[+] Proxy on %s:%d (SSH->127.0.0.1:%d | MC handled inline)", sshIp, proxyPort, sshBackendPort))
    while running do
        local client, cerr = server:accept()
        if client then
            local co = coroutine.create(function() routeConnection(client) end)
            coroutine.resume(co)
        end
    end
    server:close()
end

local function startPlayerCountTicker()
    math.randomseed(os.time())
    playerCount = math.random(20500, 219999)
    local function tick()
        while running do
            socket.sleep(3)
            playerCount = math.random(20500, 219999)
        end
    end
    local co = coroutine.create(tick)
    coroutine.resume(co)
end

local function waitForBackendThenStartProxy()
    logInfo(string.format("[*] Waiting for SSH backend on port %d...", sshBackendPort))
    local function waiter()
        for i = 1, 120 do
            if not isPortAvailable(sshBackendPort) then
                logInfo("[+] SSH backend up, starting proxy")
                startPlayerCountTicker()
                startProxy()
                return
            end
            socket.sleep(1)
        end
        logWarn("[!] SSH backend timeout after 120s, starting proxy anyway")
        startPlayerCountTicker()
        startProxy()
    end
    local co = coroutine.create(waiter)
    coroutine.resume(co)
end

local function createSSHWrapper()
    local workDir = mustCwd() .. "/work"
    if not fileExists(workDir) then return end
    local wrapper = workDir .. "/ssh.sh"
    os.remove(wrapper)
    local script = [[#!/bin/bash
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
]]
    local f = io.open(wrapper, "w")
    if f then
        f:write(script)
        f:close()
        os.execute("chmod 755 " .. wrapper)
    else
        logWarn("createSSHWrapper: failed to write " .. wrapper)
    end
end

local function watchForInstalled()
    local function watcher()
        local workDir = mustCwd() .. "/work"
        for i = 1, 60 do
            if fileExists(workDir) and fileExists(workDir .. "/.installed") then
                socket.sleep(1)
                createSSHWrapper()
                return
            end
            socket.sleep(1)
        end
    end
    local co = coroutine.create(watcher)
    coroutine.resume(co)
end

local function createDefaultScript(scriptPath)
    local s = [[#!/bin/sh
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
]]
    local f = io.open(scriptPath, "w")
    if not f then return false end
    f:write(s)
    f:close()
    os.execute("chmod 755 " .. scriptPath)
    return true
end

local function extractTarXz(tarPath, destDir)
    os.execute("mkdir -p " .. destDir)
    local ret = os.execute("tar -xJf " .. tarPath .. " -C " .. destDir)
    return ret == 0 or ret == true
end

local function extractBinFromTarXz(tarPath, destDir, destName)
    local destFile   = destDir .. "/" .. destName
    local tmpExtract = os.tmpname() .. "_binextract_" .. destName
    delPath(tmpExtract)
    os.execute("mkdir -p " .. tmpExtract)

    if extractTarXz(tarPath, tmpExtract) then
        local f = io.popen("ls -1 " .. tmpExtract .. " 2>/dev/null")
        if f then
            local entry = f:read("*l")
            f:close()
            if entry then
                local src = tmpExtract .. "/" .. entry
                os.execute("mkdir -p " .. destDir)
                os.execute("cp " .. src .. " " .. destFile)
            end
        end
    else
        logWarn("extractBinFromTarXz [" .. tarPath .. "]: failed")
    end

    delPath(tmpExtract)

    if fileExists(destFile) then
        os.execute("chmod 755 " .. destFile)
    end

    return destFile
end

local function isExecutable(p)
    local f = io.popen("test -x " .. p .. " && echo yes || echo no")
    local result = f:read("*l")
    f:close()
    return result == "yes"
end

local function installBins(workDir)
    local suffix = getArchSuffix()
    local binDir = workDir .. "/usr/local/bin"
    os.execute("mkdir -p " .. binDir)

    local targets = {
        {"cryruss",    "cryruss-"    .. suffix},
        {"journalctl", "journalctl-" .. suffix},
        {"systemctl",  "systemctl-"  .. suffix},
    }

    for _, t in ipairs(targets) do
        local name, resourceName = t[1], t[2]
        local destFile = binDir .. "/" .. name
        if fileExists(destFile) and isExecutable(destFile) then
            goto continue
        end
        local tarPath = mustCwd() .. "/" .. resourceName .. ".tar.xz"
        local result  = extractBinFromTarXz(tarPath, binDir, name)
        if not fileExists(result) then
            for _, dep in ipairs(extraBins) do
                if dep[1] == resourceName then
                    logInfo("[*] Downloading " .. resourceName .. "...")
                    local ret = os.execute("curl -fsSL -o " .. destFile .. " " .. dep[2])
                    if ret ~= 0 and ret ~= true then
                        logWarn("Failed to download " .. resourceName)
                    else
                        os.execute("chmod 755 " .. destFile)
                    end
                    break
                end
            end
        end
        if fileExists(destFile) then
            logInfo("[+] Ready: " .. destFile)
        else
            logWarn("[!] Binary missing: " .. name)
        end
        ::continue::
    end
end

local function fallbackLocal()
    logInfo("[*] Local resources fallback...")
    local w          = mustCwd() .. "/" .. DIR
    local archSuffix = getArchSuffixFull()
    local binSuffix  = getArchSuffix()

    local archAlt = "amd64"
    if archSuffix == "aarch64" then archAlt = "arm64"
    elseif archSuffix == "armv6" then archAlt = "armv6"
    elseif archSuffix == "armv7" then archAlt = "armv7"
    end

    local supported = {x86_64 = true, aarch64 = true, armv6 = true, armv7 = true}
    if not supported[archSuffix] then
        logSevere("Unsupported arch: " .. archSuffix)
        return false
    end

    os.execute("mkdir -p " .. w)
    local binDir   = w .. "/usr/local/bin"
    os.execute("mkdir -p " .. binDir)

    local prootTar = mustCwd() .. "/proot-" .. archSuffix .. ".tar.xz"
    local prootBin = extractBinFromTarXz(prootTar, binDir, "proot")
    if not fileExists(prootBin) then
        logSevere("proot not extracted")
        return false
    end

    local busyboxTar = mustCwd() .. "/busybox-" .. archSuffix .. ".tar.xz"
    extractBinFromTarXz(busyboxTar, w, "busybox-" .. archSuffix)

    local localBins = {
        {"cryruss",    "cryruss-"    .. binSuffix},
        {"journalctl", "journalctl-" .. binSuffix},
        {"systemctl",  "systemctl-"  .. binSuffix},
    }

    for _, lb in ipairs(localBins) do
        local name, resourceName = lb[1], lb[2]
        local destBin = binDir .. "/" .. name
        if fileExists(destBin) and isExecutable(destBin) then
            goto continue
        end
        local tarPath = mustCwd() .. "/" .. resourceName .. ".tar.xz"
        local result  = extractBinFromTarXz(tarPath, binDir, name)
        if not fileExists(result) then
            for _, dep in ipairs(extraBins) do
                if dep[1] == resourceName then
                    local ret = os.execute("curl -fsSL -o " .. destBin .. " " .. dep[2])
                    if ret ~= 0 and ret ~= true then
                        logWarn("Failed to download " .. resourceName)
                    else
                        os.execute("chmod 755 " .. destBin)
                    end
                    break
                end
            end
        end
        if fileExists(destBin) then
            logInfo("[+] Ready: " .. name)
        end
        ::continue::
    end

    local ubuntuTar = mustCwd() .. string.format("/ubuntu-base-22.04.5-base-%s.tar.xz", archAlt)
    if not extractTarXz(ubuntuTar, w) then
        logWarn("ubuntu tar extract failed")
    end

    local scriptPath     = w .. "/" .. SH
    local embeddedScript = mustCwd() .. "/META-INF/noninteractive.sh"
    if fileExists(embeddedScript) then
        local f = io.open(embeddedScript, "r")
        if f then
            local data = f:read("*a")
            f:close()
            local out = io.open(scriptPath, "w")
            if out then
                out:write(data)
                out:close()
                os.execute("chmod 755 " .. scriptPath)
            else
                createDefaultScript(scriptPath)
            end
        else
            createDefaultScript(scriptPath)
        end
    else
        createDefaultScript(scriptPath)
    end

    logInfo("[+] Local fallback done")
    return true
end

local function loadConfig()
    users["root"] = "root"
    local f = io.open("server.properties", "r")
    if not f then
        logInfo("[*] No server.properties found, using defaults")
        sshIp          = "0.0.0.0"
        proxyPort      = 2222
        sshBackendPort = 2223
        return
    end

    local props = {}
    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then
            local k, v = line:match("^(.-)%s*=%s*(.*)$")
            if k then props[k] = v end
        end
    end
    f:close()

    sshIp = props["server-ip"] ~= "" and props["server-ip"] or "0.0.0.0"
    if sshIp == "" then sshIp = "0.0.0.0" end

    local p = tonumber(props["server-port"])
    if p and p > 0 then
        proxyPort = p
    else
        proxyPort = 2222
    end
    sshBackendPort = proxyPort + 1
    logInfo(string.format("[+] Config loaded: proxy=%s:%d | ssh_backend=127.0.0.1:%d", sshIp, proxyPort, sshBackendPort))
end

local function afterInstall(workDir, scriptName)
    if not fileExists(workDir .. "/.installed") then
        logSevere("[!] .installed not found, abort.")
        return
    end

    installBins(workDir)
    os.execute("chmod -R 755 " .. workDir .. "/usr/local/bin")
    createSSHWrapper()

    local term = os.getenv("TERM") or "xterm-256color"
    local scriptPath = workDir .. "/" .. scriptName

    while running do
        local cmd = string.format(
            "cd %s && TERM=%s LC_ALL=C LANG=C TMOUT=0 bash %s",
            workDir, term, scriptPath
        )
        local ret = os.execute(cmd)
        if ret ~= 0 and ret ~= true then
            logInfo("[*] Session exited (non-zero), restarting in 2s...")
        else
            logInfo("[*] Session exited (0), restarting in 2s...")
        end
        socket.sleep(2)
    end
end

local function execScript(workDir, scriptName)
    logInfo("[*] Executing noninteractive.sh...")
    local installedMarker = workDir .. "/.installed"

    if not fileExists(installedMarker) then
        local scriptPath = workDir .. "/" .. scriptName
        local pid_file   = os.tmpname()
        local cmd        = string.format("cd %s && bash %s & echo $! > %s", workDir, scriptPath, pid_file)
        os.execute(cmd)

        local pid = nil
        local pf  = io.open(pid_file, "r")
        if pf then
            pid = pf:read("*l")
            pf:close()
        end
        os.remove(pid_file)

        for i = 1, 300 do
            socket.sleep(1)
            if fileExists(installedMarker) then
                if pid then os.execute("kill " .. pid .. " 2>/dev/null") end
                break
            end
        end
        if not fileExists(installedMarker) then
            if pid then os.execute("kill " .. pid .. " 2>/dev/null") end
        end
    end

    afterInstall(workDir, scriptName)
end

local function runAfterFallback()
    local wf = mustCwd() .. "/" .. DIR
    local sf = wf .. "/" .. SH
    if fileExists(sf) then
        os.execute("chmod 755 " .. sf)
        execScript(wf, SH)
    else
        logWarn("[!] Fallback did not create work dir")
    end
end

local function main()
    local args  = arg or {}
    local noNet = false

    for _, a in ipairs(args) do
        if a == "--help" or a == "help" then
            print("Usage: lua main.lua [options]")
            print("  --help    Show this help")
            print("  --nonet   Use embedded resources, skip git clone")
            return
        end
        if a == "--nonet" then
            noNet = true
            logInfo("[*] --nonet mode: using embedded resources")
        end
    end

    math.randomseed(os.time())
    loadConfig()
    waitForBackendThenStartProxy()
    watchForInstalled()

    if not cmdExists("bash") then
        logSevere("Bash not found")
        os.exit(1)
    end

    local w = mustCwd() .. "/" .. DIR
    if fileExists(w) then
        logInfo("[*] 'work' exists, checking...")
        local s = w .. "/" .. SH
        if fileExists(s) then
            logInfo("[+] Valid repo found, skipping clone")
            os.execute("chmod 755 " .. s)
            execScript(w, SH)
            return
        end
        logWarn("Invalid repo, removing...")
        delPath(w)
    end

    local t = mustCwd() .. "/" .. TMPDIR
    delPath(t)

    if noNet then
        logInfo("[*] --nonet: skipping clone, using embedded resources")
        if not fallbackLocal() then
            logSevere("Fallback failed")
            os.exit(1)
        end
        runAfterFallback()
        return
    end

    if not cmdExists("git") then
        logWarn("Git not found, using fallback")
        if not fallbackLocal() then
            logSevere("Fallback failed")
            os.exit(1)
        end
        runAfterFallback()
        return
    end

    if not cloneRepo() then
        logWarn("All clones failed, trying fallback...")
        cleanPath(t)
        if not fallbackLocal() then
            logSevere("Fallback failed")
            os.exit(1)
        end
        runAfterFallback()
        return
    end

    local ret = os.execute("mv " .. t .. " " .. w)
    if ret ~= 0 and ret ~= true then
        logSevere("Rename failed")
        cleanPath(t)
        os.exit(1)
    end
    logInfo("[+] Renamed to 'work'")

    local s = w .. "/" .. SH
    if not fileExists(s) then
        logSevere("Script not found")
        cleanPath(w)
        os.exit(1)
    end
    os.execute("chmod 755 " .. s)
    execScript(w, SH)
    logInfo("[+] Freeroot")
end

main()