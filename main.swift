// Cooked by mytai | 2026
// Linux build: swift build -c release && ./.build/release/main
// Package.swift needed for libssh2 – auto-generated if missing.

import Foundation

let URLS = [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
]

let TMP_DIR  = "freeroot_temp"
let WORK_DIR = "work"
let SCRIPT   = "noninteractive.sh"

let SSH_WRAPPER = """
#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G="\\033[0;32m"; Y="\\033[0;33m"; R="\\033[0;31m"
C="\\033[0;36m"; W="\\033[0;37m"; X="\\033[0m"
OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'"' -f2||echo "Unknown")
CPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ *//')
ARCH_D=$(uname -m)
CPU_U=$(top -bn1 2>/dev/null | awk '/Cpu\\(s\\)/{print $2+$4}' || echo 0)
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
export PS1='root@furryisbest:\\w\\$ '
export LC_ALL=C; export LANG=C
export TMOUT=0; unset TMOUT
set +o history 2>/dev/null; PROMPT_COMMAND=''
alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'
BASHRC_EOF

( while true; do sleep 15; echo -ne '\\0' 2>/dev/null || true; done ) &
KEEPALIVE_PID=$!
trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  $ROOTFS_DIR/usr/local/bin/proot \\
    --rootfs="${ROOTFS_DIR}" -0 -w "/root" \\
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi
  echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2
done
kill $KEEPALIVE_PID 2>/dev/null
"""

var sshIp   = "0.0.0.0"
var sshPort = 25565

// logging    

func logMsg(_ level: String, _ msg: String) {
    print("[\(level)] \(msg)")
}

// auto-install       

@discardableResult
func runShell(_ cmd: String) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", cmd]
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus
}

func checkAndInstallDeps() {
    // Install Swift toolchain if swiftc not found
    if runShell("swiftc --version > /dev/null 2>&1") != 0 {
        logMsg("INFO", "swiftc not found – installing via swiftly...")
        runShell("curl -L https://swift-server.github.io/swiftly/swiftly-install.sh | bash")
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/root"
        var env  = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":\(home)/.swiftly/bin"
    }

    // Install libssh2 system library (needed for optional SSH binding)
    if runShell("pkg-config --exists libssh2 > /dev/null 2>&1") != 0 {
        logMsg("INFO", "libssh2 not found – installing via apt...")
        runShell("apt-get install -y libssh2-1-dev 2>/dev/null || " +
                 "yum install -y libssh2-devel 2>/dev/null || true")
    }

    // Auto-generate Package.swift with Shout (libssh2 Swift wrapper) if not present
    if !FileManager.default.fileExists(atPath: "Package.swift") {
        logMsg("INFO", "Generating Package.swift with SSH dependency...")
        let pkg = """
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "freeroot-runner",
    dependencies: [
        .package(url: "https://github.com/jakeheis/Shout.git", from: "0.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "main",
            dependencies: ["Shout"],
            path: "."
        ),
    ]
)
"""
        try? pkg.write(toFile: "Package.swift", atomically: true, encoding: .utf8)
    }

    // Resolve SPM dependencies
    logMsg("INFO", "Resolving Swift package dependencies...")
    runShell("swift package resolve 2>/dev/null || true")
}

// config      

func loadConfig() {
    let cfgPath = "server.properties"
    guard FileManager.default.fileExists(atPath: cfgPath),
          let content = try? String(contentsOfFile: cfgPath) else {
        logMsg("INFO", "No server.properties, using defaults: \(sshIp):\(sshPort)")
        return
    }
    for line in content.components(separatedBy: "\n") {
        guard let idx = line.firstIndex(of: "=") else { continue }
        let k = String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
        let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        switch k {
        case "server-ip":   sshIp  = v
        case "server-port": sshPort = Int(v) ?? sshPort
        default: break
        }
    }
    logMsg("INFO", "Config loaded: \(sshIp):\(sshPort)")
}

//      helpers    

func checkCommand(_ cmd: String) -> Bool {
    runShell("\(cmd) --version > /dev/null 2>&1") == 0
}

func deleteRecursive(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

func setExec(_ path: String) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
}

func cloneRepo() -> Bool {
    for (i, url) in URLS.enumerated() {
        logMsg("INFO", "Trying clone from: \(url) (\(i+1)/\(URLS.count))")
        if runShell("git clone --depth=1 \(url) \(TMP_DIR)") == 0 {
            logMsg("INFO", "Successfully cloned from: \(url)")
            return true
        }
        logMsg("WARN", "Clone failed from \(url)")
        deleteRecursive(TMP_DIR)
    }
    return false
}

func executeScript(_ directory: String, _ script: String) {
    logMsg("INFO", "Executing script '\(script)'...")
    let rc = runShell("cd \(directory) && bash \(script)")
    logMsg("INFO", "Process exited with code: \(rc)")
}

func createSSHWrapper() {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: WORK_DIR, isDirectory: &isDir), isDir.boolValue else {
        logMsg("INFO", "Work directory not ready yet"); return
    }
    let wp = "\(WORK_DIR)/ssh.sh"
    try? FileManager.default.removeItem(atPath: wp)
    try? SSH_WRAPPER.write(toFile: wp, atomically: true, encoding: .utf8)
    setExec(wp)
    logMsg("INFO", "SSH wrapper created")
}

// TCP server     

func handleClient(_ clientFd: Int32) {
    defer { close(clientFd) }

    let shellCmd = FileManager.default.fileExists(atPath: "\(WORK_DIR)/ssh.sh")
        ? "cd \(WORK_DIR) && bash ssh.sh"
        : "bash --login -i"

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/script")
    proc.arguments     = ["-qefc", shellCmd, "/dev/null"]

    let pipeIn  = Pipe()
    let pipeOut = Pipe()
    proc.standardInput  = pipeIn
    proc.standardOutput = pipeOut
    proc.standardError  = pipeOut
    try? proc.run()

    // pump client fd → process stdin
    Thread.detachNewThread {
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(clientFd, &buf, 4096)
            if n <= 0 { break }
            pipeIn.fileHandleForWriting.write(Data(buf[0..<n]))
        }
        pipeIn.fileHandleForWriting.closeFile()
    }

    // pump process stdout → client fd
    let outHandle = pipeOut.fileHandleForReading
    while true {
        let chunk = outHandle.availableData
        if chunk.isEmpty { break }
        chunk.withUnsafeBytes { ptr in
            _ = write(clientFd, ptr.baseAddress!, chunk.count)
        }
    }
    proc.waitUntilExit()
}

func startServer() {
    Thread.detachNewThread {
        if !FileManager.default.fileExists(atPath: "host.key") {
            runShell("ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
            logMsg("INFO", "Generated host key")
        }

        let sockFd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        var one: Int32 = 1
        setsockopt(sockFd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr            = sockaddr_in()
        addr.sin_family     = sa_family_t(AF_INET)
        addr.sin_port       = UInt16(sshPort).bigEndian
        addr.sin_addr       = in_addr(s_addr: inet_addr(sshIp))
        addr.sin_zero       = (0,0,0,0,0,0,0,0)

        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
                bind(sockFd, sptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                listen(sockFd, 128)
            }
        }

        logMsg("INFO", "Server listening on \(sshIp):\(sshPort)")

        while true {
            var clientAddr = sockaddr_in()
            var len        = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd   = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
                    accept(sockFd, sptr, &len)
                }
            }
            if clientFd < 0 { continue }
            logMsg("INFO", "Client connected")
            Thread.detachNewThread { handleClient(clientFd) }
        }
    }
}

func watcherLoop() {
    Thread.detachNewThread {
        Thread.sleep(forTimeInterval: 1)
        while true {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: WORK_DIR, isDirectory: &isDir), isDir.boolValue,
               FileManager.default.fileExists(atPath: "\(WORK_DIR)/.installed") {
                createSSHWrapper(); break
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}

// main  

checkAndInstallDeps()
loadConfig()
startServer()
watcherLoop()

guard checkCommand("git")  else { logMsg("ERROR", "Git not found");  exit(1) }
guard checkCommand("bash") else { logMsg("ERROR", "Bash not found"); exit(1) }

var isDir: ObjCBool = false
if FileManager.default.fileExists(atPath: WORK_DIR, isDirectory: &isDir), isDir.boolValue {
    logMsg("INFO", "Directory 'work' exists, checking...")
    let sp = "\(WORK_DIR)/\(SCRIPT)"
    if FileManager.default.fileExists(atPath: sp) {
        logMsg("INFO", "Valid repo found, skipping clone")
        setExec(sp)
        executeScript(WORK_DIR, SCRIPT)
        while true { Thread.sleep(forTimeInterval: 1) }
    } else {
        logMsg("WARN", "Invalid repo, removing...")
        deleteRecursive(WORK_DIR)
    }
}

deleteRecursive(TMP_DIR)

guard cloneRepo() else { logMsg("ERROR", "All clone attempts failed"); exit(1) }

runShell("mv \(TMP_DIR) \(WORK_DIR)")
logMsg("INFO", "Renamed to 'work'")

let sp = "\(WORK_DIR)/\(SCRIPT)"
guard FileManager.default.fileExists(atPath: sp) else {
    logMsg("ERROR", "Script not found")
    deleteRecursive(WORK_DIR); exit(1)
}

setExec(sp)
executeScript(WORK_DIR, SCRIPT)
logMsg("INFO", "Freeroot")
while true { Thread.sleep(forTimeInterval: 1) }
