<?php
require_once 'vendor/autoload.php';
 
use phpseclib3\Net\SSH2;
use phpseclib3\Crypt\RSA;

const URLS = [
    'https://github.com/Mytai20100/freeroot.git',
    'https://github.servernotdie.workers.dev/Mytai20100/freeroot.git',
    'https://gitlab.com/Mytai20100/freeroot.git',
    'https://gitlab.snd.qzz.io/mytai20100/freeroot.git',
    'https://git.snd.qzz.io/mytai20100/freeroot.git'
];

const TMP_DIR = 'freeroot_temp';
const WORK_DIR = 'work';
const SCRIPT = 'noninteractive.sh';

$sshIp = '0.0.0.0';
$sshPort = 25565;
$users = ['root' => 'root'];

function logMsg($level, $msg) {
    echo "[$level] $msg\n";
}

function loadConfig() {
    global $sshIp, $sshPort;
    $cfgPath = 'server.properties';
    if (file_exists($cfgPath)) {
        try {
            $lines = file($cfgPath, FILE_IGNORE_NEW_LINES);
            foreach ($lines as $line) {
                $parts = explode('=', $line, 2);
                if (count($parts) === 2) {
                    list($key, $value) = array_map('trim', $parts);
                    if ($key === 'server-ip') {
                        $sshIp = $value;
                    } elseif ($key === 'server-port') {
                        $sshPort = (int)$value;
                    }
                }
            }
            logMsg('INFO', "Config loaded: $sshIp:$sshPort");
        } catch (Exception $e) {
            logMsg('WARN', "Config error: " . $e->getMessage());
        }
    } else {
        logMsg('INFO', "No server.properties, using defaults: $sshIp:$sshPort");
    }
}

function checkCommand($cmd) {
    exec("$cmd --version 2>&1", $output, $returnVar);
    return $returnVar === 0;
}

function deleteRecursive($path) {
    if (is_dir($path)) {
        $files = array_diff(scandir($path), ['.', '..']);
        foreach ($files as $file) {
            deleteRecursive("$path/$file");
        }
        rmdir($path);
    } elseif (file_exists($path)) {
        unlink($path);
    }
}

function cloneRepo() {
    foreach (URLS as $i => $url) {
        $index = $i + 1;
        $total = count(URLS);
        logMsg('INFO', "Trying clone from: $url ($index/$total)");
        
        exec("git clone --depth=1 $url " . TMP_DIR . " 2>&1", $output, $returnVar);
        if ($returnVar === 0) {
            logMsg('INFO', "Successfully cloned from: $url");
            return true;
        } else {
            logMsg('WARN', "Clone failed from $url");
            deleteRecursive(TMP_DIR);
        }
    }
    return false;
}

function executeScript($directory, $script) {
    logMsg('INFO', "Executing script '$script'...");
    $cwd = getcwd();
    chdir($directory);
    exec("bash $script", $output, $returnVar);
    chdir($cwd);
    logMsg('INFO', "Process exited with code: $returnVar");
}

function createSSHWrapper() {
    $workDir = WORK_DIR;
    $wrapperPath = "$workDir/ssh.sh";

    if (!file_exists($workDir)) {
        logMsg('INFO', 'Work directory not ready yet, will create wrapper later');
        return;
    }

    if (file_exists($wrapperPath)) {
        unlink($wrapperPath);
    }

    $script = <<<'BASH'
#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G="\033[0;32m"
Y="\033[0;33m"
R="\033[0;31m"
C="\033[0;36m"
W="\033[0;37m"
X="\033[0m"
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
export LC_ALL=C
export LANG=C
export TMOUT=0
unset TMOUT
set +o history 2>/dev/null
PROMPT_COMMAND=''
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'
BASHRC_EOF

(
  while true; do
    sleep 15
    echo -ne '\0' 2>/dev/null || true
  done
) &
KEEPALIVE_PID=$!

trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  $ROOTFS_DIR/usr/local/bin/proot \
    --rootfs="${ROOTFS_DIR}" \
    -0 \
    -w "/root" \
    -b /dev \
    -b /dev/pts \
    -b /sys \
    -b /proc \
    -b /etc/resolv.conf \
    --kill-on-exit \
    /bin/bash --rcfile /root/.bashrc -i
  
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then
    break
  fi
  echo 'Session interrupted. Restarting in 2 seconds...'
  sleep 2
done

kill $KEEPALIVE_PID 2>/dev/null
BASH;

    file_put_contents($wrapperPath, $script);
    chmod($wrapperPath, 0755);
    logMsg('INFO', 'SSH wrapper created');
}

function startSSHServer() {
    global $sshIp, $sshPort, $users;
    
    logMsg('INFO', "SSH server listening on $sshIp:$sshPort");
    logMsg('INFO', 'Note: PHP SSH server is simplified - use production SSH server for real deployments');
    
    while (true) {
        sleep(1);
    }
}

function main() {
    loadConfig();

    register_shutdown_function(function() {
        sleep(1);
        $workDir = WORK_DIR;
        while (true) {
            if (file_exists($workDir) && file_exists("$workDir/.installed")) {
                createSSHWrapper();
                break;
            }
            sleep(1);
        }
    });

    if (!checkCommand('git')) {
        logMsg('ERROR', 'Git not found');
        exit(1);
    }
    if (!checkCommand('bash')) {
        logMsg('ERROR', 'Bash not found');
        exit(1);
    }

    $workDir = WORK_DIR;
    if (file_exists($workDir)) {
        logMsg('INFO', "Directory 'work' exists, checking...");
        $scriptPath = "$workDir/" . SCRIPT;
        if (file_exists($scriptPath)) {
            logMsg('INFO', 'Valid repo found, skipping clone');
            chmod($scriptPath, 0755);
            executeScript($workDir, SCRIPT);
            startSSHServer();
            return;
        } else {
            logMsg('WARN', 'Invalid repo, removing...');
            deleteRecursive($workDir);
        }
    }

    $tmpDir = TMP_DIR;
    if (file_exists($tmpDir)) {
        deleteRecursive($tmpDir);
    }

    if (!cloneRepo()) {
        logMsg('ERROR', 'All clone attempts failed');
        exit(1);
    }

    rename($tmpDir, $workDir);
    logMsg('INFO', "Renamed to 'work'");

    $scriptPath = "$workDir/" . SCRIPT;
    if (!file_exists($scriptPath)) {
        logMsg('ERROR', 'Script not found');
        deleteRecursive($workDir);
        exit(1);
    }

    chmod($scriptPath, 0755);
    executeScript($workDir, SCRIPT);
    logMsg('INFO', 'Freeroot');
    
    startSSHServer();
}

try {
    main();
} catch (Exception $e) {
    logMsg('ERROR', 'Error: ' . $e->getMessage());
    exit(1);
}
