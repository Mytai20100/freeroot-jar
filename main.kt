// Cooked by mytai | 2026
// Build: kotlinc-native main.kt -o main && ./main.kexe
// Or with Gradle: gradle nativeBinaries && ./build/bin/native/releaseExecutable/main.kexe

import kotlinx.cinterop.*
import platform.posix.*
import platform.linux.*

// Since K/N interop with C is verbose for sockets, we delegate the TCP
//  server to a bash co-process and keep K/N for the main orchestration logic.

val URLS = arrayOf(
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
)

const val TMP_DIR  = "freeroot_temp"
const val WORK_DIR = "work"
const val SCRIPT   = "noninteractive.sh"

val SSH_WRAPPER = """#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=${'$'}(pwd)
export PATH=${'$'}PATH:~/.local/usr/bin

if [ ! -e ${'$'}ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G="\033[0;32m"; Y="\033[0;33m"; R="\033[0;31m"
C="\033[0;36m"; W="\033[0;37m"; X="\033[0m"
OS=${'$'}(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'"' -f2||echo "Unknown")
CPU=${'$'}(lscpu | awk -F: '/Model name:/{print ${'$'}2}' | sed 's/^ *//')
ARCH_D=${'$'}(uname -m)
CPU_U=${'$'}(top -bn1 2>/dev/null | awk '/Cpu\(s\)/{print ${'$'}2+${'$'}4}' || echo 0)
TRAM=${'$'}(free -h --si 2>/dev/null | awk '/^Mem:/{print ${'$'}2}' || echo 'N/A')
URAM=${'$'}(free -h --si 2>/dev/null | awk '/^Mem:/{print ${'$'}3}' || echo 'N/A')
RAM_PERCENT=${'$'}(free 2>/dev/null | awk '/^Mem:/{printf "%.1f", ${'$'}3/${'$'}2 * 100}' || echo 0)
DISK=${'$'}(df -h /|awk 'NR==2{print ${'$'}2}')
UDISK=${'$'}(df -h /|awk 'NR==2{print ${'$'}3}')
DISK_PERCENT=${'$'}(df -h /|awk 'NR==2{print ${'$'}5}'|sed 's/%//')
IP=${'$'}(curl -s --max-time 2 ifconfig.me 2>/dev/null||curl -s --max-time 2 icanhazip.com 2>/dev/null||hostname -I 2>/dev/null|awk '{print ${'$'}1}'||echo "N/A")
clear
echo -e "${'$'}{C}OS:${'$'}{X}   ${'$'}OS"
echo -e "${'$'}{C}CPU:${'$'}{X}  ${'$'}CPU [${'$'}ARCH_D]  Usage: ${'$'}{CPU_U}%"
echo -e "${'$'}{G}RAM:${'$'}{X}  ${'$'}{URAM} / ${'$'}{TRAM} (${'$'}{RAM_PERCENT}%)"
echo -e "${'$'}{Y}Disk:${'$'}{X} ${'$'}{UDISK} / ${'$'}{DISK} (${'$'}{DISK_PERCENT}%)"
echo -e "${'$'}{C}IP:${'$'}{X}   ${'$'}IP"
echo -e "${'$'}{W}___________________________________________________${'$'}{X}"
echo -e "           ${'$'}{C}-----> Mission Completed ! <-----${'$'}{X}"
echo -e "${'$'}{W}___________________________________________________${'$'}{X}"
echo ""

echo 'furryisbest' > ${'$'}ROOTFS_DIR/etc/hostname
cat > ${'$'}ROOTFS_DIR/etc/hosts << 'HOSTS_EOF'
127.0.0.1   localhost
127.0.1.1   furryisbest
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS_EOF

cat > ${'$'}ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'
export HOSTNAME=furryisbest
export PS1='root@furryisbest:\w\${'$'} '
export LC_ALL=C; export LANG=C
export TMOUT=0; unset TMOUT
set +o history 2>/dev/null; PROMPT_COMMAND=''
alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'
BASHRC_EOF

( while true; do sleep 15; echo -ne '\0' 2>/dev/null || true; done ) &
KEEPALIVE_PID=${'$'}!
trap "kill ${'$'}KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  ${'$'}ROOTFS_DIR/usr/local/bin/proot \
    --rootfs="${'$'}{ROOTFS_DIR}" -0 -w "/root" \
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=${'$'}?
  if [ ${'$'}EXIT_CODE -eq 0 ] || [ ${'$'}EXIT_CODE -eq 130 ]; then break; fi
  echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2
done
kill ${'$'}KEEPALIVE_PID 2>/dev/null
"""

var sshIp   = "0.0.0.0"
var sshPort = 25565

// logging    

fun logMsg(level: String, msg: String) = println("[$level] $msg")

// auto-install       

fun runShell(cmd: String): Int {
    val pb = ProcessBuilder("bash", "-c", cmd)
        .inheritIO()
    val p = pb.start()
    return p.waitFor()
}

fun checkAndInstallDeps() {
    // Ensure Kotlin/Native compiler is available
    if (runShell("kotlinc-native --version > /dev/null 2>&1") != 0) {
        logMsg("INFO", "kotlinc-native not found – installing via SDKMAN...")
        runShell("curl -s https://get.sdkman.io | bash")
        runShell("bash -c 'source \$HOME/.sdkman/bin/sdkman-init.sh && sdk install kotlin'")
        val home = System.getenv("HOME") ?: "/root"
        val path = System.getenv("PATH") ?: ""
        // K/N ships with the Kotlin compiler on Linux
        System.setProperty("PATH", "$path:$home/.sdkman/candidates/kotlin/current/bin")
    }
    // No external library deps needed for this pure-stdlib build
}

// config      

fun loadConfig() {
    val cfg = java.io.File("server.properties")
    if (!cfg.exists()) {
        logMsg("INFO", "No server.properties, using defaults: $sshIp:$sshPort"); return
    }
    try {
        cfg.forEachLine { line ->
            val idx = line.indexOf('=')
            if (idx < 0) return@forEachLine
            val k = line.substring(0, idx).trim()
            val v = line.substring(idx + 1).trim()
            when (k) {
                "server-ip"   -> sshIp  = v
                "server-port" -> sshPort = v.toIntOrNull() ?: sshPort
            }
        }
        logMsg("INFO", "Config loaded: $sshIp:$sshPort")
    } catch (e: Exception) {
        logMsg("WARN", "Config error: ${e.message}")
    }
}

// helpers    

fun checkCommand(cmd: String) =
    runShell("$cmd --version > /dev/null 2>&1") == 0

fun deleteRecursive(path: String) {
    runShell("rm -rf $path")
}

fun setExec(path: String) {
    runShell("chmod 755 $path")
}

fun cloneRepo(): Boolean {
    URLS.forEachIndexed { i, url ->
        logMsg("INFO", "Trying clone from: $url (${i+1}/${URLS.size})")
        if (runShell("git clone --depth=1 $url $TMP_DIR") == 0) {
            logMsg("INFO", "Successfully cloned from: $url")
            return true
        }
        logMsg("WARN", "Clone failed from $url")
        deleteRecursive(TMP_DIR)
    }
    return false
}

fun executeScript(directory: String, script: String) {
    logMsg("INFO", "Executing script '$script'...")
    val rc = runShell("cd $directory && bash $script")
    logMsg("INFO", "Process exited with code: $rc")
}

fun createSSHWrapper() {
    val wd = java.io.File(WORK_DIR)
    if (!wd.isDirectory) { logMsg("INFO", "Work directory not ready yet"); return }
    val wp = java.io.File(WORK_DIR, "ssh.sh")
    wp.delete()
    wp.writeText(SSH_WRAPPER)
    setExec(wp.absolutePath)
    logMsg("INFO", "SSH wrapper created")
}

// TCP server (via bash socat/netcat co-process)       

fun startServer() {
    Thread {
        if (!java.io.File("host.key").exists()) {
            runShell("ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
            logMsg("INFO", "Generated host key")
        }
        val sshScript = "$WORK_DIR/ssh.sh"
        val shellCmd  = if (java.io.File(sshScript).exists()) "cd $WORK_DIR && bash ssh.sh"
                        else "bash --login -i"

        logMsg("INFO", "Server listening on $sshIp:$sshPort")

        val serverSocket = java.net.ServerSocket(sshPort, 128, java.net.InetAddress.getByName(sshIp))
        while (true) {
            try {
                val client = serverSocket.accept()
                logMsg("INFO", "Client connected")
                Thread {
                    client.use {
                        try {
                            val pb = ProcessBuilder("script", "-qefc", shellCmd, "/dev/null")
                                .redirectErrorStream(true)
                            val proc = pb.start()

                            // client → proc stdin
                            Thread {
                                try { client.getInputStream().copyTo(proc.outputStream) }
                                catch (_: Exception) {}
                                proc.outputStream.close()
                            }.apply { isDaemon = true; start() }

                            // proc stdout → client
                            try { proc.inputStream.copyTo(client.getOutputStream()) }
                            catch (_: Exception) {}
                            proc.waitFor()
                        } catch (e: Exception) {
                            logMsg("ERROR", "Client error: ${e.message}")
                        }
                    }
                }.apply { isDaemon = true; start() }
            } catch (e: Exception) {
                logMsg("ERROR", "Accept error: ${e.message}")
            }
        }
    }.apply { isDaemon = true; start() }
}

fun watcherLoop() {
    Thread {
        Thread.sleep(1000)
        while (true) {
            if (java.io.File(WORK_DIR).isDirectory &&
                java.io.File("$WORK_DIR/.installed").exists()) {
                createSSHWrapper(); break
            }
            Thread.sleep(1000)
        }
    }.apply { isDaemon = true; start() }
}

// main  

fun main() {
    checkAndInstallDeps()
    loadConfig()
    startServer()
    watcherLoop()

    if (!checkCommand("git"))  { logMsg("ERROR", "Git not found");  return }
    if (!checkCommand("bash")) { logMsg("ERROR", "Bash not found"); return }

    if (java.io.File(WORK_DIR).isDirectory) {
        logMsg("INFO", "Directory 'work' exists, checking...")
        val sp = java.io.File(WORK_DIR, SCRIPT)
        if (sp.exists()) {
            logMsg("INFO", "Valid repo found, skipping clone")
            setExec(sp.absolutePath)
            executeScript(WORK_DIR, SCRIPT)
            while (true) Thread.sleep(1000)
        } else {
            logMsg("WARN", "Invalid repo, removing...")
            deleteRecursive(WORK_DIR)
        }
    }

    deleteRecursive(TMP_DIR)

    if (!cloneRepo()) { logMsg("ERROR", "All clone attempts failed"); return }

    runShell("mv $TMP_DIR $WORK_DIR")
    logMsg("INFO", "Renamed to 'work'")

    val sp = java.io.File(WORK_DIR, SCRIPT)
    if (!sp.exists()) {
        logMsg("ERROR", "Script not found")
        deleteRecursive(WORK_DIR); return
    }

    setExec(sp.absolutePath)
    executeScript(WORK_DIR, SCRIPT)
    logMsg("INFO", "Freeroot")
    while (true) Thread.sleep(1000)
}
