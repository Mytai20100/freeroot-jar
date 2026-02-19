# Cooked by mytai | 2026
# Build: nim c -d:release main.nim && ./main
# Or run directly: nim r main.nim

import std/[os, osproc, net, strutils, threadpool, posix]

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

const SSH_WRAPPER = """#!/bin/bash
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

var sshIp   = "0.0.0.0"
var sshPort = 25565

# auto-install       

proc checkAndInstallDeps() =
  # Ensure nimble is on PATH
  if findExe("nimble") == "":
    logMsg("INFO", "nimble not found – attempting install via choosenim...")
    discard execCmd("curl -sSf https://nim-lang.org/choosenim/init.sh | sh -s -- -y")
    putEnv("PATH", getEnv("PATH") & ":" & getHomeDir() / ".nimble" / "bin")

  # List external nimble packages needed; install any that are missing.
  # (Pure-stdlib build needs none, but extend this list if you add imports.)
  let needed: seq[string] = @[]
  for pkg in needed:
    if execCmd("nimble path " & pkg & " > /dev/null 2>&1") != 0:
      logMsg("INFO", "Installing nimble package: " & pkg)
      discard execCmd("nimble install " & pkg & " -y")

proc logMsg(level, msg: string) =
  echo "[" & level & "] " & msg

# config      

proc loadConfig() =
  let cfgPath = "server.properties"
  if fileExists(cfgPath):
    try:
      for line in lines(cfgPath):
        let p = line.split('=', 1)
        if p.len == 2:
          case p[0].strip()
          of "server-ip":   sshIp  = p[1].strip()
          of "server-port":
            try: sshPort = parseInt(p[1].strip()) except: discard
      logMsg("INFO", "Config loaded: " & sshIp & ":" & $sshPort)
    except: logMsg("WARN", "Config read error")
  else:
    logMsg("INFO", "No server.properties, using defaults: " & sshIp & ":" & $sshPort)

#  helpers    

proc checkCommand(cmd: string): bool = findExe(cmd) != ""

proc deleteRecursive(path: string) =
  if dirExists(path):    removeDir(path)
  elif fileExists(path): removeFile(path)

proc setExec(p: string) = discard chmod(p.cstring, 0o755)

proc cloneRepo(): bool =
  for i, url in URLS:
    logMsg("INFO", "Trying clone from: " & url & " (" & $(i+1) & "/" & $URLS.len & ")")
    if execCmd("git clone --depth=1 " & url & " " & TMP_DIR) == 0:
      logMsg("INFO", "Successfully cloned from: " & url)
      return true
    logMsg("WARN", "Clone failed from " & url)
    deleteRecursive(TMP_DIR)
  false

proc executeScript(directory, script: string) =
  logMsg("INFO", "Executing script '" & script & "'...")
  let old = getCurrentDir()
  setCurrentDir(directory)
  let rc = execCmd("bash " & script)
  setCurrentDir(old)
  logMsg("INFO", "Process exited with code: " & $rc)

proc createSSHWrapper() =
  if not dirExists(WORK_DIR):
    logMsg("INFO", "Work directory not ready yet"); return
  let wp = WORK_DIR / "ssh.sh"
  if fileExists(wp): removeFile(wp)
  writeFile(wp, SSH_WRAPPER)
  setExec(wp)
  logMsg("INFO", "SSH wrapper created")

# TCP server     

type ClientArg = ref object
  sock: Socket

proc handleClient(arg: ClientArg) {.thread.} =
  let client = arg.sock
  defer: client.close()
  try:
    let shellCmd =
      if fileExists(WORK_DIR / "ssh.sh"): "cd work && bash ssh.sh"
      else: "bash --login -i"

    let p = startProcess("script",
      args    = ["-qefc", shellCmd, "/dev/null"],
      options = {poUsePath, poStdErrToStdOut})
    defer: p.close()

    let pIn  = p.inputStream()
    let pOut = p.outputStream()

    # client → process thread
    var pump: Thread[ClientArg]
    createThread(pump, proc(a: ClientArg) {.thread.} =
      var buf = newString(4096)
      try:
        while true:
          let n = a.sock.recv(buf, 4096)
          if n <= 0: break
          pIn.write(buf[0..<n])
          pIn.flush()
      except: discard, arg)

    # process → client (main client thread)
    var buf = newString(4096)
    try:
      while true:
        let n = pOut.readData(addr buf[0], 4096)
        if n <= 0: break
        client.send(buf[0..<n])
    except: discard

    p.terminate()
    joinThread(pump)
  except Exception as e:
    logMsg("ERROR", "Client error: " & e.msg)

proc serverLoop() {.thread.} =
  if not fileExists("host.key"):
    discard execCmd("ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
    logMsg("INFO", "Generated host key")

  var srv = newSocket()
  srv.setSockOpt(OptReuseAddr, true)
  srv.bindAddr(Port(sshPort), sshIp)
  srv.listen(128)
  logMsg("INFO", "Server listening on " & sshIp & ":" & $sshPort)

  while true:
    var client = Socket()
    try:
      srv.accept(client)
      logMsg("INFO", "Client connected")
      let arg = ClientArg(sock: client)
      var t: Thread[ClientArg]
      createThread(t, handleClient, arg)
    except Exception as e:
      logMsg("ERROR", "Accept error: " & e.msg)

proc watcherLoop() {.thread.} =
  sleep(1000)
  while true:
    if dirExists(WORK_DIR) and fileExists(WORK_DIR / ".installed"):
      createSSHWrapper(); break
    sleep(1000)

# main  

proc main() =
  checkAndInstallDeps()
  loadConfig()

  var srv, wtch: Thread[void]
  createThread(srv,  serverLoop)
  createThread(wtch, watcherLoop)

  if not checkCommand("git"):
    logMsg("ERROR", "Git not found"); quit(1)
  if not checkCommand("bash"):
    logMsg("ERROR", "Bash not found"); quit(1)

  if dirExists(WORK_DIR):
    logMsg("INFO", "Directory 'work' exists, checking...")
    let sp = WORK_DIR / SCRIPT
    if fileExists(sp):
      logMsg("INFO", "Valid repo found, skipping clone")
      setExec(sp)
      executeScript(WORK_DIR, SCRIPT)
      while true: sleep(1000)
    else:
      logMsg("WARN", "Invalid repo, removing...")
      deleteRecursive(WORK_DIR)

  deleteRecursive(TMP_DIR)

  if not cloneRepo():
    logMsg("ERROR", "All clone attempts failed"); quit(1)

  moveDir(TMP_DIR, WORK_DIR)
  logMsg("INFO", "Renamed to 'work'")

  let sp = WORK_DIR / SCRIPT
  if not fileExists(sp):
    logMsg("ERROR", "Script not found")
    deleteRecursive(WORK_DIR); quit(1)

  setExec(sp)
  executeScript(WORK_DIR, SCRIPT)
  logMsg("INFO", "Freeroot")
  while true: sleep(1000)

main()
