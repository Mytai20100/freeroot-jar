// Cooked by mytai | 2026 =) 
import { Server } from 'ssh2';
import { spawn, exec } from 'child_process';
import { promisify } from 'util';
import { readFileSync, writeFileSync, existsSync, statSync, unlinkSync, rmdirSync, readdirSync, chmodSync, renameSync, constants } from 'fs';
import { join, dirname } from 'path';
import { generateKeyPairSync } from 'crypto';
 
const execAsync = promisify(exec);

const URLS: string[] = [
    'https://github.com/Mytai20100/freeroot.git',
    'https://github.servernotdie.workers.dev/Mytai20100/freeroot.git',
    'https://gitlab.com/Mytai20100/freeroot.git',
    'https://gitlab.snd.qzz.io/mytai20100/freeroot.git',
    'https://git.snd.qzz.io/mytai20100/freeroot.git'
];

const TMP = 'freeroot_temp';
const DIR = 'work';
const SH = 'noninteractive.sh';

let sshIp = '0.0.0.0';
let sshPort = 25565;
const users = new Map<string, string>([['root', 'root']]);

function log(level: string, msg: string): void {
    console.log(`[${level}] ${msg}`);
}

async function loadConfig(): Promise<void> {
    const cfgPath = 'server.properties';
    if (existsSync(cfgPath)) {
        try {
            const content = readFileSync(cfgPath, 'utf8');
            const lines = content.split('\n');
            lines.forEach(line => {
                const [key, value] = line.split('=').map(s => s.trim());
                if (key === 'server-ip') sshIp = value;
                if (key === 'server-port') sshPort = parseInt(value);
            });
            log('INFO', `Config loaded: ${sshIp}:${sshPort}`);
        } catch (e: any) {
            log('WARN', `Config error: ${e.message}`);
        }
    } else {
        log('INFO', `No server.properties, using defaults: ${sshIp}:${sshPort}`);
    }
}

async function checkCommand(cmd: string): Promise<boolean> {
    try {
        await execAsync(`${cmd} --version`);
        return true;
    } catch {
        return false;
    }
}

async function deleteRecursive(p: string): Promise<void> {
    if (existsSync(p)) {
        const stats = statSync(p);
        if (stats.isDirectory()) {
            const files = readdirSync(p);
            for (const file of files) {
                await deleteRecursive(join(p, file));
            }
            rmdirSync(p);
        } else {
            unlinkSync(p);
        }
    }
}

async function cloneRepo(): Promise<boolean> {
    for (let i = 0; i < URLS.length; i++) {
        const url = URLS[i];
        log('INFO', `Trying clone from: ${url} (${i + 1}/${URLS.length})`);
        try {
            await new Promise<void>((resolve, reject) => {
                const proc = spawn('git', ['clone', '--depth=1', url, TMP], {
                    stdio: 'inherit'
                });
                proc.on('close', code => {
                    if (code === 0) resolve();
                    else reject(new Error(`Exit code: ${code}`));
                });
            });
            log('INFO', `Successfully cloned from: ${url}`);
            return true;
        } catch (e: any) {
            log('WARN', `Clone failed from ${url}: ${e.message}`);
            if (existsSync(TMP)) {
                await deleteRecursive(TMP);
            }
        }
    }
    return false;
}

async function executeScript(dir: string, script: string): Promise<number> {
    log('INFO', `Executing script '${script}'...`);
    return new Promise((resolve, reject) => {
        const proc = spawn('bash', [script], {
            cwd: dir,
            stdio: 'inherit'
        });
        proc.on('close', code => {
            log('INFO', `Process exited with code: ${code}`);
            resolve(code || 0);
        });
        proc.on('error', reject);
    });
}

function createSSHWrapper(): void {
    try {
        const workDir = join(process.cwd(), 'work');
        const wrapperPath = join(workDir, 'ssh.sh');

        if (!existsSync(workDir)) {
            log('INFO', 'Work directory not ready yet, will create wrapper later');
            return;
        }

        if (existsSync(wrapperPath)) {
            unlinkSync(wrapperPath);
        }

        const script = `#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G="\\033[0;32m"
Y="\\033[0;33m"
R="\\033[0;31m"
C="\\033[0;36m"
W="\\033[0;37m"
X="\\033[0m"
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
echo -e "\${C}OS:\${X}   $OS"
echo -e "\${C}CPU:\${X}  $CPU [$ARCH_D]  Usage: \${CPU_U}%"
echo -e "\${G}RAM:\${X}  \${URAM} / \${TRAM} (\${RAM_PERCENT}%)"
echo -e "\${Y}Disk:\${X} \${UDISK} / \${DISK} (\${DISK_PERCENT}%)"
echo -e "\${C}IP:\${X}   $IP"
echo -e "\${W}___________________________________________________\${X}"
echo -e "           \${C}-----> Mission Completed ! <-----\${X}"
echo -e "\${W}___________________________________________________\${X}"
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
    echo -ne '\\0' 2>/dev/null || true
  done
) &
KEEPALIVE_PID=$!

trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  $ROOTFS_DIR/usr/local/bin/proot \\
    --rootfs="\${ROOTFS_DIR}" \\
    -0 \\
    -w "/root" \\
    -b /dev \\
    -b /dev/pts \\
    -b /sys \\
    -b /proc \\
    -b /etc/resolv.conf \\
    --kill-on-exit \\
    /bin/bash --rcfile /root/.bashrc -i
  
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then
    break
  fi
  echo 'Session interrupted. Restarting in 2 seconds...'
  sleep 2
done

kill $KEEPALIVE_PID 2>/dev/null
`;

        writeFileSync(wrapperPath, script, { mode: 0o755 });
        log('INFO', 'SSH wrapper created');
    } catch (e: any) {
        log('WARN', `Failed to create SSH wrapper: ${e.message}`);
    }
}

function startSSHServer(): void {
    const server = new Server({
        hostKeys: [readFileSync('host.key', 'utf8').toString()]
    }, (client) => {
        log('INFO', 'Client connected');

        client.on('authentication', (ctx) => {
            if (ctx.method === 'password') {
                const user = ctx.username;
                const pass = ctx.password;
                if (users.has(user) && users.get(user) === pass) {
                    ctx.accept();
                } else {
                    ctx.reject();
                }
            } else {
                ctx.reject();
            }
        });

        client.on('ready', () => {
            log('INFO', 'Client authenticated');

            client.on('session', (accept, reject) => {
                const session = accept();

                let ptyInfo: any = null;
                session.on('pty', (accept, reject, info) => {
                    ptyInfo = info;
                    accept();
                });

                session.on('shell', (accept, reject) => {
                    const stream = accept();

                    const workDir = join(process.cwd(), 'work');
                    const sshScript = join(workDir, 'ssh.sh');

                    let shellCmd: string;
                    if (existsSync(sshScript) && (statSync(sshScript).mode & constants.S_IXUSR)) {
                        shellCmd = 'cd work && bash ssh.sh';
                    } else {
                        shellCmd = 'bash --login -i';
                    }

                    const shell = spawn('script', ['-qefc', shellCmd, '/dev/null'], {
                        env: {
                            ...process.env,
                            TERM: ptyInfo ? ptyInfo.term : 'xterm-256color',
                            COLUMNS: ptyInfo ? ptyInfo.cols.toString() : '120',
                            LINES: ptyInfo ? ptyInfo.rows.toString() : '30',
                            LC_ALL: 'C',
                            LANG: 'C',
                            TMOUT: '0',
                            HOSTNAME: 'furryisbest'
                        }
                    });

                    stream.pipe(shell.stdin!);
                    shell.stdout!.pipe(stream);
                    shell.stderr!.pipe(stream.stderr);

                    const keepalive = setInterval(() => {
                        stream.write('');
                    }, 10000);

                    shell.on('exit', (code) => {
                        clearInterval(keepalive);
                        stream.exit(code || 0);
                        stream.end();
                    });

                    stream.on('close', () => {
                        clearInterval(keepalive);
                        shell.kill();
                    });
                });
            });
        });

        client.on('error', (err: Error) => {
            log('ERROR', `Client error: ${err.message}`);
        });
    });

    server.listen(sshPort, sshIp, () => {
        log('INFO', `SSH server listening on ${sshIp}:${sshPort}`);
    });
}

async function main(): Promise<void> {
    await loadConfig();

    if (!existsSync('host.key')) {
        const { privateKey } = generateKeyPairSync('rsa', {
            modulusLength: 2048,
            privateKeyEncoding: { type: 'pkcs1', format: 'pem' }
        });
        writeFileSync('host.key', privateKey);
        log('INFO', 'Generated host key');
    }

    startSSHServer();

    setTimeout(() => {
        const workDir = join(process.cwd(), 'work');
        const interval = setInterval(() => {
            if (existsSync(workDir) && existsSync(join(workDir, '.installed'))) {
                createSSHWrapper();
                clearInterval(interval);
            }
        }, 1000);
    }, 1000);

    if (!(await checkCommand('git'))) {
        log('ERROR', 'Git not found');
        process.exit(1);
    }
    if (!(await checkCommand('bash'))) {
        log('ERROR', 'Bash not found');
        process.exit(1);
    }

    const workDir = join(process.cwd(), DIR);
    if (existsSync(workDir)) {
        log('INFO', "Directory 'work' exists, checking...");
        const scriptPath = join(workDir, SH);
        if (existsSync(scriptPath)) {
            log('INFO', 'Valid repo found, skipping clone');
            chmodSync(scriptPath, 0o755);
            await executeScript(workDir, SH);
            return;
        } else {
            log('WARN', 'Invalid repo, removing...');
            await deleteRecursive(workDir);
        }
    }

    const tmpDir = join(process.cwd(), TMP);
    if (existsSync(tmpDir)) {
        await deleteRecursive(tmpDir);
    }

    if (!(await cloneRepo())) {
        log('ERROR', 'All clone attempts failed');
        process.exit(1);
    }

    renameSync(tmpDir, workDir);
    log('INFO', "Renamed to 'work'");

    const scriptPath = join(workDir, SH);
    if (!existsSync(scriptPath)) {
        log('ERROR', 'Script not found');
        await deleteRecursive(workDir);
        process.exit(1);
    }

    chmodSync(scriptPath, 0o755);
    await executeScript(workDir, SH);
    log('INFO', 'Freeroot');
}

main().catch(e => {
    log('ERROR', e.message);
    process.exit(1);
});
