// Cooked by mytai | 2026
// Build: haxe --main Main --interp   (quick test)
//        haxe build.hxml             (compile to target)
// build.hxml example:
//   -cp .
//   -main Main
//   -neko main.n
//   Then run: neko main.n

import sys.io.*;
import sys.net.*;
import sys.*;
import haxe.io.*;

class Main {
    static final URLS = [
        "https://github.com/Mytai20100/freeroot.git",
        "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
        "https://gitlab.com/Mytai20100/freeroot.git",
        "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
        "https://git.snd.qzz.io/mytai20100/freeroot.git"
    ];

    static final TMP_DIR  = "freeroot_temp";
    static final WORK_DIR = "work";
    static final SCRIPT   = "noninteractive.sh";

    static final SSH_WRAPPER = "#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=\$(pwd)
export PATH=\$PATH:~/.local/usr/bin

if [ ! -e \$ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G=\"\\033[0;32m\"; Y=\"\\033[0;33m\"; R=\"\\033[0;31m\"
C=\"\\033[0;36m\"; W=\"\\033[0;37m\"; X=\"\\033[0m\"
OS=\$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'\"' -f2||echo \"Unknown\")
CPU=\$(lscpu | awk -F: '/Model name:/{print \$2}' | sed 's/^ //')
ARCH_D=\$(uname -m)
CPU_U=\$(top -bn1 2>/dev/null | awk '/Cpu\\(s\\)/{print \$2+\$4}' || echo 0)
TRAM=\$(free -h --si 2>/dev/null | awk '/^Mem:/{print \$2}' || echo 'N/A')
URAM=\$(free -h --si 2>/dev/null | awk '/^Mem:/{print \$3}' || echo 'N/A')
RAM_PERCENT=\$(free 2>/dev/null | awk '/^Mem:/{printf \"%.1f\", \$3/\$2 * 100}' || echo 0)
DISK=\$(df -h /|awk 'NR==2{print \$2}')
UDISK=\$(df -h /|awk 'NR==2{print \$3}')
DISK_PERCENT=\$(df -h /|awk 'NR==2{print \$5}'|sed 's/%//')
IP=\$(curl -s --max-time 2 ifconfig.me 2>/dev/null||curl -s --max-time 2 icanhazip.com 2>/dev/null||hostname -I 2>/dev/null|awk '{print \$1}'||echo \"N/A\")
clear
echo -e \"\${C}OS:\${X}   \$OS\"
echo -e \"\${C}CPU:\${X}  \$CPU [\$ARCH_D]  Usage: \${CPU_U}%\"
echo -e \"\${G}RAM:\${X}  \${URAM} / \${TRAM} (\${RAM_PERCENT}%)\"
echo -e \"\${Y}Disk:\${X} \${UDISK} / \${DISK} (\${DISK_PERCENT}%)\"
echo -e \"\${C}IP:\${X}   \$IP\"
echo -e \"\${W}___________________________________________________\${X}\"
echo -e \"           \${C}-----> Mission Completed ! <-----\${X}\"
echo -e \"\${W}___________________________________________________\${X}\"
echo \"\"

echo 'furryisbest' > \$ROOTFS_DIR/etc/hostname
cat > \$ROOTFS_DIR/etc/hosts << 'HOSTS_EOF'
127.0.0.1   localhost
127.0.1.1   furryisbest
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS_EOF

cat > \$ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'
export HOSTNAME=furryisbest
export PS1='root@furryisbest:\\w\\$ '
export LC_ALL=C; export LANG=C
export TMOUT=0; unset TMOUT
set +o history 2>/dev/null; PROMPT_COMMAND=''
alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'
BASHRC_EOF

( while true; do sleep 15; echo -ne '\\0' 2>/dev/null || true; done ) &
KEEPALIVE_PID=\$!
trap \"kill \$KEEPALIVE_PID 2>/dev/null; exit\" EXIT INT TERM

while true; do
  \$ROOTFS_DIR/usr/local/bin/proot \\
    --rootfs=\"\${ROOTFS_DIR}\" -0 -w \"/root\" \\
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=\$?
  if [ \$EXIT_CODE -eq 0 ] || [ \$EXIT_CODE -eq 130 ]; then break; fi
  echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2
done
kill \$KEEPALIVE_PID 2>/dev/null
";

    static var sshIp   = "0.0.0.0";
    static var sshPort = 25565;

    // logging       

    static function logMsg(level: String, msg: String) {
        Sys.println('[$level] $msg');
    }

    // auto-install   

    static function runShell(cmd: String): Int {
        return Sys.command("bash", ["-c", cmd]);
    }

    static function checkAndInstallDeps() {
        // Install Haxe if missing
        if (runShell("haxe --version > /dev/null 2>&1") != 0) {
            logMsg("INFO", "haxe not found – installing via apt/snap...");
            runShell("apt-get install -y haxe 2>/dev/null || snap install haxe --classic 2>/dev/null || true");
        }
        // Install haxelib packages; add names to this array as needed
        var needed: Array<String> = [];
        for (lib in needed) {
            if (runShell('haxelib path $lib > /dev/null 2>&1') != 0) {
                logMsg("INFO", 'Installing haxelib: $lib');
                runShell('haxelib install $lib');
            }
        }
    }

    // config     

    static function loadConfig() {
        var cfg = "server.properties";
        if (!sys.FileSystem.exists(cfg)) {
            logMsg("INFO", 'No server.properties, using defaults: $sshIp:$sshPort');
            return;
        }
        try {
            var content = File.getContent(cfg);
            for (line in content.split("\n")) {
                var parts = line.split("=");
                if (parts.length < 2) continue;
                var k = StringTools.trim(parts[0]);
                var v = StringTools.trim(parts.slice(1).join("="));
                switch (k) {
                    case "server-ip":   sshIp   = v;
                    case "server-port": sshPort  = Std.parseInt(v) ?? sshPort;
                }
            }
            logMsg("INFO", 'Config loaded: $sshIp:$sshPort');
        } catch (e) {
            logMsg("WARN", 'Config error: $e');
        }
    }

    // helpers         

    static function checkCommand(cmd: String): Bool {
        return runShell('$cmd --version > /dev/null 2>&1') == 0;
    }

    static function deleteRecursive(path: String) {
        runShell('rm -rf $path');
    }

    static function setExec(path: String) {
        runShell('chmod 755 $path');
    }

    static function cloneRepo(): Bool {
        for (i in 0...URLS.length) {
            var url = URLS[i];
            logMsg("INFO", 'Trying clone from: $url (${i+1}/${URLS.length})');
            if (Sys.command("git", ["clone", "--depth=1", url, TMP_DIR]) == 0) {
                logMsg("INFO", 'Successfully cloned from: $url');
                return true;
            }
            logMsg("WARN", 'Clone failed from $url');
            deleteRecursive(TMP_DIR);
        }
        return false;
    }

    static function executeScript(dir: String, script: String) {
        logMsg("INFO", 'Executing script \'$script\'...');
        var old = Sys.getCwd();
        Sys.setCwd(dir);
        var rc = Sys.command("bash", [script]);
        Sys.setCwd(old);
        logMsg("INFO", 'Process exited with code: $rc');
    }

    static function createSSHWrapper() {
        if (!sys.FileSystem.isDirectory(WORK_DIR)) {
            logMsg("INFO", "Work directory not ready yet");
            return;
        }
        var wp = '$WORK_DIR/ssh.sh';
        if (sys.FileSystem.exists(wp)) sys.FileSystem.deleteFile(wp);
        File.saveContent(wp, SSH_WRAPPER);
        setExec(wp);
        logMsg("INFO", "SSH wrapper created");
    }

    // TCP server       

    static function handleClient(client: sys.net.Socket) {
        // Haxe sys.net is single-threaded on most targets;
        // we use sys.thread if available (cpp/hl targets), else sequential.
        var shellCmd = sys.FileSystem.exists('$WORK_DIR/ssh.sh')
            ? 'cd $WORK_DIR && bash ssh.sh'
            : 'bash --login -i';

        #if (cpp || hl)
        sys.thread.Thread.create(() -> {
            try {
                var proc = new sys.io.Process("script", ["-qefc", shellCmd, "/dev/null"]);
                // pump client → proc
                sys.thread.Thread.create(() -> {
                    try {
                        var buf = Bytes.alloc(4096);
                        while (true) {
                            var n = client.input.readBytes(buf, 0, 4096);
                            if (n == 0) break;
                            proc.stdin.writeBytes(buf, 0, n);
                            proc.stdin.flush();
                        }
                    } catch (_) {}
                    proc.stdin.close();
                });
                // pump proc → client
                try {
                    var buf = Bytes.alloc(4096);
                    while (true) {
                        var n = proc.stdout.readBytes(buf, 0, 4096);
                        if (n == 0) break;
                        client.output.writeBytes(buf, 0, n);
                        client.output.flush();
                    }
                } catch (_) {}
                proc.exitCode();
            } catch (e) { logMsg("ERROR", 'Client error: $e'); }
            client.close();
        });
        #else
        // interp/neko: simple sequential proxy
        runShell('script -qefc "$shellCmd" /dev/null');
        client.close();
        #end
    }

    static function startServer() {
        if (!sys.FileSystem.exists("host.key"))
            runShell('ssh-keygen -t rsa -b 2048 -f host.key -N ""');

        #if (cpp || hl)
        sys.thread.Thread.create(() -> {
            var srv = new sys.net.Socket();
            srv.setBlocking(true);
            srv.bind(new sys.net.Host(sshIp), sshPort);
            srv.listen(128);
            logMsg("INFO", 'Server listening on $sshIp:$sshPort');
            while (true) {
                try {
                    var cl = srv.accept();
                    logMsg("INFO", "Client connected");
                    handleClient(cl);
                } catch (e) { logMsg("ERROR", 'Accept: $e'); }
            }
        });
        #else
        logMsg("INFO", 'Server (interp mode): using socat on $sshIp:$sshPort');
        var shellCmd = sys.FileSystem.exists('$WORK_DIR/ssh.sh')
            ? 'cd $WORK_DIR && bash ssh.sh' : 'bash --login -i';
        runShell('socat TCP-LISTEN:$sshPort,bind=$sshIp,reuseaddr,fork EXEC:"script -qefc \'$shellCmd\' /dev/null",pty,setsid,ctty &');
        #end
    }

    static function watcherLoop() {
        #if (cpp || hl)
        sys.thread.Thread.create(() -> {
            Sys.sleep(1);
            while (true) {
                if (sys.FileSystem.isDirectory(WORK_DIR) &&
                    sys.FileSystem.exists('$WORK_DIR/.installed')) {
                    createSSHWrapper(); break;
                }
                Sys.sleep(1);
            }
        });
        #else
        // neko/interp: watcher via background process
        runShell('(while true; do sleep 1; [ -f $WORK_DIR/.installed ] && break; done; chmod 755 $WORK_DIR/ssh.sh 2>/dev/null) &');
        #end
    }

    // main  

    static function main() {
        checkAndInstallDeps();
        loadConfig();
        startServer();
        watcherLoop();

        if (!checkCommand("git"))  { logMsg("ERROR", "Git not found");  Sys.exit(1); }
        if (!checkCommand("bash")) { logMsg("ERROR", "Bash not found"); Sys.exit(1); }

        if (sys.FileSystem.isDirectory(WORK_DIR)) {
            logMsg("INFO", "Directory 'work' exists, checking...");
            var sp = '$WORK_DIR/$SCRIPT';
            if (sys.FileSystem.exists(sp)) {
                logMsg("INFO", "Valid repo found, skipping clone");
                setExec(sp);
                executeScript(WORK_DIR, SCRIPT);
                while (true) Sys.sleep(1);
            } else {
                logMsg("WARN", "Invalid repo, removing...");
                deleteRecursive(WORK_DIR);
            }
        }

        deleteRecursive(TMP_DIR);

        if (!cloneRepo()) { logMsg("ERROR", "All clone attempts failed"); Sys.exit(1); }

        runShell('mv $TMP_DIR $WORK_DIR');
        logMsg("INFO", "Renamed to 'work'");

        var sp = '$WORK_DIR/$SCRIPT';
        if (!sys.FileSystem.exists(sp)) {
            logMsg("ERROR", "Script not found");
            deleteRecursive(WORK_DIR); Sys.exit(1);
        }

        setExec(sp);
        executeScript(WORK_DIR, SCRIPT);
        logMsg("INFO", "Freeroot");
        while (true) Sys.sleep(1);
    }
}
