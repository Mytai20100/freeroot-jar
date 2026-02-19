// Cooked by mytai | 2026
// Build: dub run  OR  rdmd main.d

import std.stdio, std.process, std.file, std.path, std.string,
       std.socket, std.conv, std.array, core.thread, core.time;

immutable string[] URLS = [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
];

enum TMP_DIR  = "freeroot_temp";
enum WORK_DIR = "work";
enum SCRIPT   = "noninteractive.sh";

enum SSH_WRAPPER = `#!/bin/bash
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
`;

string sshIp   = "0.0.0.0";
int    sshPort = 25565;

void logMsg(string level, string msg) {
    writefln("[%s] %s", level, msg);
    stdout.flush();
}

// auto-install       

void checkAndInstallDeps() {
    // Check dub
    if (executeShell("dub --version > /dev/null 2>&1").status != 0) {
        logMsg("INFO", "dub not found – installing D toolchain via dlang install script...");
        executeShell("curl -fsS https://dlang.org/install.sh | bash -s dmd");
        // Try to source the dlang env
        auto home = environment.get("HOME", "/root");
        auto res  = executeShell("ls " ~ home ~ "/dlang/ 2>/dev/null | grep dmd | tail -1");
        if (res.status == 0) {
            auto ver  = res.output.strip();
            auto bin  = home ~ "/dlang/" ~ ver ~ "/bin";
            environment["PATH"] = environment.get("PATH","") ~ ":" ~ bin;
        }
    }

    // Add any needed dub package names here; they'll be auto-fetched if absent
    immutable string[] needed = [];
    foreach (pkg; needed) {
        if (executeShell("dub describe " ~ pkg ~ " > /dev/null 2>&1").status != 0) {
            logMsg("INFO", "Fetching dub package: " ~ pkg);
            executeShell("dub fetch " ~ pkg);
        }
    }
}

// config      

void loadConfig() {
    if (!"server.properties".exists) {
        logMsg("INFO", "No server.properties, using defaults: " ~ sshIp ~ ":" ~ sshPort.to!string);
        return;
    }
    try {
        foreach (line; File("server.properties").byLine()) {
            auto s = (cast(string)line).strip();
            auto idx = s.indexOf('=');
            if (idx < 0) continue;
            auto k = s[0..idx].strip();
            auto v = s[idx+1..$].strip();
            if      (k == "server-ip")   sshIp  = v;
            else if (k == "server-port") sshPort = v.to!int;
        }
        logMsg("INFO", "Config loaded: " ~ sshIp ~ ":" ~ sshPort.to!string);
    } catch (Exception e) { logMsg("WARN", "Config error: " ~ e.msg); }
}

//      helpers    

bool checkCommand(string cmd) {
    return executeShell(cmd ~ " --version > /dev/null 2>&1").status == 0;
}

void deleteRecursive(string p) {
    if (p.isDir)      rmdirRecurse(p);
    else if (p.exists) remove(p);
}

void setExec(string p) {
    import core.sys.posix.sys.stat : chmod;
    chmod(p.toStringz, 0o755);
}

bool cloneRepo() {
    foreach (i, url; URLS) {
        logMsg("INFO", "Trying clone from: " ~ url ~
               " (" ~ (i+1).to!string ~ "/" ~ URLS.length.to!string ~ ")");
        if (executeShell("git clone --depth=1 " ~ url ~ " " ~ TMP_DIR).status == 0) {
            logMsg("INFO", "Successfully cloned from: " ~ url);
            return true;
        }
        logMsg("WARN", "Clone failed from " ~ url);
        deleteRecursive(TMP_DIR);
    }
    return false;
}

void executeScript(string directory, string script) {
    logMsg("INFO", "Executing script '" ~ script ~ "'...");
    auto old = getcwd();
    chdir(directory);
    auto rc = executeShell("bash " ~ script).status;
    chdir(old);
    logMsg("INFO", "Process exited with code: " ~ rc.to!string);
}

void createSSHWrapper() {
    if (!WORK_DIR.isDir) { logMsg("INFO", "Work directory not ready yet"); return; }
    auto wp = WORK_DIR ~ "/ssh.sh";
    if (wp.exists) remove(wp);
    std.file.write(wp, SSH_WRAPPER);
    setExec(wp);
    logMsg("INFO", "SSH wrapper created");
}

// TCP server     

void handleClient(Socket client) {
    scope(exit) client.close();
    try {
        auto shellCmd = (WORK_DIR ~ "/ssh.sh").exists
            ? "cd work && bash ssh.sh" : "bash --login -i";

        auto pi  = pipe();
        auto po  = pipe();
        auto pid = spawnShell(
            "script -qefc \"" ~ shellCmd ~ "\" /dev/null",
            pi.readEnd, po.writeEnd, po.writeEnd);

        // client → process thread
        auto t = new Thread(delegate void() {
            ubyte[4096] b;
            scope(exit) pi.writeEnd.close();
            try {
                while (true) {
                    auto n = client.receive(b);
                    if (n <= 0) break;
                    pi.writeEnd.rawWrite(b[0..n]);
                }
            } catch (Exception) {}
        });
        t.isDaemon = true; t.start();

        // process → client
        ubyte[4096] b;
        try {
            while (true) {
                auto chunk = po.readEnd.rawRead(b);
                if (chunk.length == 0) break;
                client.send(chunk);
            }
        } catch (Exception) {}

        pid.wait(); t.join();
    } catch (Exception e) { logMsg("ERROR", "Client error: " ~ e.msg); }
}

void serverLoop() {
    if (!"host.key".exists)
        executeShell(`ssh-keygen -t rsa -b 2048 -f host.key -N ""`);

    auto srv = new TcpSocket();
    srv.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    srv.bind(new InternetAddress(sshIp, cast(ushort)sshPort));
    srv.listen(128);
    logMsg("INFO", "Server listening on " ~ sshIp ~ ":" ~ sshPort.to!string);

    while (true) {
        try {
            auto cl = srv.accept();
            logMsg("INFO", "Client connected");
            auto t = new Thread(delegate void() { handleClient(cl); });
            t.isDaemon = true; t.start();
        } catch (Exception e) { logMsg("ERROR", "Accept: " ~ e.msg); }
    }
}

void watcherLoop() {
    Thread.sleep(1.seconds);
    while (true) {
        if (WORK_DIR.isDir && (WORK_DIR ~ "/.installed").exists) {
            createSSHWrapper(); break;
        }
        Thread.sleep(1.seconds);
    }
}

// main  

void main() {
    checkAndInstallDeps();
    loadConfig();

    auto srv  = new Thread(&serverLoop);  srv.isDaemon  = true; srv.start();
    auto wtch = new Thread(&watcherLoop); wtch.isDaemon = true; wtch.start();

    if (!checkCommand("git"))  { logMsg("ERROR", "Git not found");  return; }
    if (!checkCommand("bash")) { logMsg("ERROR", "Bash not found"); return; }

    if (WORK_DIR.isDir) {
        logMsg("INFO", "Directory 'work' exists, checking...");
        auto sp = WORK_DIR ~ "/" ~ SCRIPT;
        if (sp.exists) {
            logMsg("INFO", "Valid repo found, skipping clone");
            setExec(sp);
            executeScript(WORK_DIR, SCRIPT);
            while (true) Thread.sleep(1.seconds);
        } else {
            logMsg("WARN", "Invalid repo, removing...");
            deleteRecursive(WORK_DIR);
        }
    }

    deleteRecursive(TMP_DIR);

    if (!cloneRepo()) { logMsg("ERROR", "All clone attempts failed"); return; }

    rename(TMP_DIR, WORK_DIR);
    logMsg("INFO", "Renamed to 'work'");

    auto sp = WORK_DIR ~ "/" ~ SCRIPT;
    if (!sp.exists) {
        logMsg("ERROR", "Script not found");
        deleteRecursive(WORK_DIR); return;
    }

    setExec(sp);
    executeScript(WORK_DIR, SCRIPT);
    logMsg("INFO", "Freeroot");
    while (true) Thread.sleep(1.seconds);
}
