// Cooked by mytai | 2026
// Run: groovy main.groovy

@Grab(group='org.codehaus.groovy', module='groovy-all', version='4.0.0', transitive=false)

import java.net.ServerSocket
import java.net.InetAddress
import groovy.transform.CompileStatic

// constants       

final List<String> URLS = [
    'https://github.com/Mytai20100/freeroot.git',
    'https://github.servernotdie.workers.dev/Mytai20100/freeroot.git',
    'https://gitlab.com/Mytai20100/freeroot.git',
    'https://gitlab.snd.qzz.io/mytai20100/freeroot.git',
    'https://git.snd.qzz.io/mytai20100/freeroot.git'
]

final String TMP_DIR  = 'freeroot_temp'
final String WORK_DIR = 'work'
final String SCRIPT   = 'noninteractive.sh'

final String SSH_WRAPPER = '''\
#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G="\\033[0;32m"; Y="\\033[0;33m"; C="\\033[0;36m"; W="\\033[0;37m"; X="\\033[0m"
OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d\'"\\\''"\\\''\' -f2||echo "Unknown")
CPU=$(lscpu | awk -F: \'/Model name:/{print $2}\' | sed \'s/^ *//' + "'" + '/)
ARCH_D=$(uname -m)
IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||hostname -I 2>/dev/null|awk \'{print $1}\'||echo "N/A")
clear
echo -e "${C}OS:${X}   $OS"
echo -e "${C}CPU:${X}  $CPU [$ARCH_D]"
echo -e "${C}IP:${X}   $IP"
echo -e "${W}___________________________________________________${X}"
echo -e "           ${C}-----> Mission Completed ! <-----${X}"
echo -e "${W}___________________________________________________${X}"
echo ""

echo \'furryisbest\' > $ROOTFS_DIR/etc/hostname
cat > $ROOTFS_DIR/etc/hosts << \'HOSTS_EOF\'
127.0.0.1   localhost
127.0.1.1   furryisbest
::1         localhost ip6-localhost ip6-loopback
HOSTS_EOF

cat > $ROOTFS_DIR/root/.bashrc << \'BASHRC_EOF\'
export HOSTNAME=furryisbest
export PS1=\'root@furryisbest:\\w\\$ \'
export TMOUT=0; unset TMOUT
BASHRC_EOF

( while true; do sleep 15; echo -ne \'\\0\' 2>/dev/null||true; done ) &
KEEPALIVE_PID=$!
trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  $ROOTFS_DIR/usr/local/bin/proot --rootfs="${ROOTFS_DIR}" -0 -w /root \\
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi
  echo \'Restarting in 2s...\'; sleep 2
done
kill $KEEPALIVE_PID 2>/dev/null
'''

String sshIp   = '0.0.0.0'
int    sshPort = 25565

// logging    

def logMsg(String level, String msg) {
    println "[${level}] ${msg}"
}

// auto-install       

def runShell(String cmd) {
    def pb = new ProcessBuilder('bash', '-c', cmd).inheritIO()
    pb.start().waitFor()
}

def checkAndInstallDeps() {
    if (runShell('groovy --version > /dev/null 2>&1') != 0) {
        logMsg('INFO', 'groovy not found – installing via SDKMAN...')
        runShell('curl -s https://get.sdkman.io | bash')
        runShell('bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && sdk install groovy"')
        def home = System.getenv('HOME') ?: '/root'
        def path = System.getenv('PATH') ?: ''
        System.setProperty('PATH', "${path}:${home}/.sdkman/candidates/groovy/current/bin")
    }

    // Grape/Ivy dependencies – add @Grab annotations above or list them here
    def needed = []  // e.g. ['org.apache.commons:commons-lang3:3.12.0']
    needed.each { dep ->
        logMsg('INFO', "Dependency ${dep} – ensure @Grab annotation is present")
    }
}

// config      

def loadConfig() {
    def cfg = new File('server.properties')
    if (!cfg.exists()) {
        logMsg('INFO', "No server.properties, using defaults: ${sshIp}:${sshPort}")
        return
    }
    try {
        cfg.eachLine { line ->
            def parts = line.split('=', 2)
            if (parts.size() == 2) {
                def k = parts[0].trim()
                def v = parts[1].trim()
                switch (k) {
                    case 'server-ip':   sshIp   = v; break
                    case 'server-port': sshPort  = v.toInteger(); break
                }
            }
        }
        logMsg('INFO', "Config loaded: ${sshIp}:${sshPort}")
    } catch (Exception e) {
        logMsg('WARN', "Config error: ${e.message}")
    }
}

// helpers    

def checkCommand(String cmd) {
    runShell("${cmd} --version > /dev/null 2>&1") == 0
}

def deleteRecursive(String path) {
    runShell("rm -rf ${path}")
}

def setExec(String path) {
    runShell("chmod 755 ${path}")
}

def cloneRepo() {
    URLS.eachWithIndex { url, i ->
        logMsg('INFO', "Trying clone from: ${url} (${i+1}/${URLS.size()})")
        if (runShell("git clone --depth=1 ${url} ${TMP_DIR}") == 0) {
            logMsg('INFO', "Successfully cloned from: ${url}")
            return true
        }
        logMsg('WARN', "Clone failed from ${url}")
        deleteRecursive(TMP_DIR)
    }
    false
}

def executeScript(String directory, String script) {
    logMsg('INFO', "Executing script '${script}'...")
    def rc = runShell("cd ${directory} && bash ${script}")
    logMsg('INFO', "Process exited with code: ${rc}")
}

def createSSHWrapper() {
    def wd = new File(WORK_DIR)
    if (!wd.isDirectory()) { logMsg('INFO', 'Work directory not ready yet'); return }
    def wp = new File(WORK_DIR, 'ssh.sh')
    if (wp.exists()) wp.delete()
    wp.text = SSH_WRAPPER
    setExec(wp.absolutePath)
    logMsg('INFO', 'SSH wrapper created')
}

// TCP server     

def handleClient(socket) {
    Thread.start {
        try {
            def shellCmd = new File("${WORK_DIR}/ssh.sh").exists()
                ? "cd ${WORK_DIR} && bash ssh.sh"
                : 'bash --login -i'

            def pb   = new ProcessBuilder('script', '-qefc', shellCmd, '/dev/null')
                .redirectErrorStream(true)
            def proc = pb.start()
            def cs   = socket.inputStream
            def co   = socket.outputStream

            Thread.start {
                try { cs.transferTo(proc.outputStream); proc.outputStream.close() }
                catch (Exception ignored) {}
            }

            try { proc.inputStream.transferTo(co) }
            catch (Exception ignored) {}
            proc.waitFor()
        } catch (Exception e) {
            logMsg('ERROR', "Client error: ${e.message}")
        } finally {
            try { socket.close() } catch (Exception ignored) {}
        }
    }
}

def startServer() {
    Thread.start {
        if (!new File('host.key').exists()) {
            runShell('ssh-keygen -t rsa -b 2048 -f host.key -N ""')
            logMsg('INFO', 'Generated host key')
        }
        def srv = new ServerSocket(sshPort, 128, InetAddress.getByName(sshIp))
        logMsg('INFO', "Server listening on ${sshIp}:${sshPort}")
        while (true) {
            try {
                def client = srv.accept()
                logMsg('INFO', 'Client connected')
                handleClient(client)
            } catch (Exception e) {
                logMsg('ERROR', "Accept error: ${e.message}")
            }
        }
    }
}

def watcherLoop() {
    Thread.start {
        Thread.sleep(1000)
        while (true) {
            if (new File(WORK_DIR).isDirectory() && new File("${WORK_DIR}/.installed").exists()) {
                createSSHWrapper(); break
            }
            Thread.sleep(1000)
        }
    }
}

// main  

checkAndInstallDeps()
loadConfig()
startServer()
watcherLoop()

if (!checkCommand('git'))  { logMsg('ERROR', 'Git not found');  System.exit(1) }
if (!checkCommand('bash')) { logMsg('ERROR', 'Bash not found'); System.exit(1) }

def wd = new File(WORK_DIR)
if (wd.isDirectory()) {
    logMsg('INFO', "Directory 'work' exists, checking...")
    def sp = new File(WORK_DIR, SCRIPT)
    if (sp.exists()) {
        logMsg('INFO', 'Valid repo found, skipping clone')
        setExec(sp.absolutePath)
        executeScript(WORK_DIR, SCRIPT)
        while (true) Thread.sleep(1000)
    } else {
        logMsg('WARN', 'Invalid repo, removing...')
        deleteRecursive(WORK_DIR)
    }
}

deleteRecursive(TMP_DIR)

if (!cloneRepo()) {
    logMsg('ERROR', 'All clone attempts failed')
    System.exit(1)
}

runShell("mv ${TMP_DIR} ${WORK_DIR}")
logMsg('INFO', "Renamed to 'work'")

def sp = new File(WORK_DIR, SCRIPT)
if (!sp.exists()) {
    logMsg('ERROR', 'Script not found')
    deleteRecursive(WORK_DIR); System.exit(1)
}

setExec(sp.absolutePath)
executeScript(WORK_DIR, SCRIPT)
logMsg('INFO', 'Freeroot')
while (true) Thread.sleep(1000)
