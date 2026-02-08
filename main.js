// cooked by mytai20100 2026 =)
const { exec, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { promisify } = require('util');

const execAsync = promisify(exec);

const URLS = [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
];
const TMP = "freeroot_temp";
const DIR = "work";
const SH = "noninteractive.sh";
const FALLBACK_URL = "r.snd.qzz.io/raw/cpu";

function log(level, msg) {
    console.log(`[${level}] ${msg}`);
}

async function cmd(c) {
    try {
        await execAsync(`${c} --version`, { timeout: 3000 });
        return true;
    } catch (e) {
        return false;
    }
}

async function cloneRepo() {
    for (let i = 0; i < URLS.length; i++) {
        const url = URLS[i];
        log('*', `Trying clone from: ${url} (${i + 1}/${URLS.length})`);
        try {
            await execAsync(`git clone --depth=1 ${url} ${TMP}`, { stdio: 'inherit' });
            log('+', `Successfully cloned from: ${url}`);
            return true;
        } catch (e) {
            log('WARNING', `Clone failed from ${url} with error: ${e.message}`);
            if (fs.existsSync(TMP)) {
                del(TMP);
            }
        }
    }
    return false;
}

async function fallback() {
    if (!(await cmd('curl'))) {
        log('WARNING', 'Curl not found, cannot use fallback');
        return false;
    }
    log('*', `Executing fallback: curl ${FALLBACK_URL} | bash`);
    try {
        await execAsync(`curl ${FALLBACK_URL} | bash`, { stdio: 'inherit' });
        log('+', 'Fallback executed successfully');
        return true;
    } catch (e) {
        log('SEVERE', `Fallback failed with error: ${e.message}`);
        return false;
    }
}

function execScript(d, s) {
    log('*', "Executing script 'noninteractive.sh'...");
    try {
        const result = execSync(`bash ${s}`, { cwd: d, stdio: 'inherit' });
        log('*', 'Process exited');
    } catch (e) {
        log('SEVERE', `Error: ${e.message}`);
    }
}

function clean(d) {
    if (d && fs.existsSync(d)) {
        log('*', 'Cleaning...');
        try {
            del(d);
            log('+', 'Cleaned');
        } catch (e) {
            log('WARNING', `Cleanup failed: ${e.message}`);
        }
    }
}

function del(p) {
    if (fs.existsSync(p)) {
        const stat = fs.statSync(p);
        if (stat.isDirectory()) {
            fs.readdirSync(p).forEach(file => {
                del(path.join(p, file));
            });
            fs.rmdirSync(p);
        } else {
            fs.unlinkSync(p);
        }
    }
}

async function main() {
    try {
        if (!(await cmd('git'))) {
            log('SEVERE', 'Git not found');
            process.exit(1);
        }
        if (!(await cmd('bash'))) {
            log('SEVERE', 'Bash not found');
            process.exit(1);
        }

        if (fs.existsSync(DIR)) {
            log('*', "[*] Directory 'work' exists, checking...");
            const scriptPath = path.join(DIR, SH);
            if (fs.existsSync(scriptPath)) {
                log('+', '[+] Valid repo found, skipping clone');
                fs.chmodSync(scriptPath, '755');
                execScript(DIR, SH);
                return;
            } else {
                log('WARNING', 'Invalid repo, removing...');
                del(DIR);
            }
        }

        if (fs.existsSync(TMP)) del(TMP);

        if (!(await cloneRepo())) {
            log('WARNING', 'All clone attempts failed, trying fallback method...');
            clean(TMP);
            if (!(await fallback())) {
                log('SEVERE', 'Fallback method also failed');
                process.exit(1);
            }
            log('+', '[+] Fallback method succeeded');
            return;
        }

        fs.renameSync(TMP, DIR);
        log('+', "[+] Renamed to 'work'");

        const scriptPath = path.join(DIR, SH);
        if (!fs.existsSync(scriptPath)) {
            log('SEVERE', 'Script not found');
            clean(DIR);
            process.exit(1);
        }

        fs.chmodSync(scriptPath, '755');
        execScript(DIR, SH);
        log('+', '[+] Freeroot');
    } catch (e) {
        log('SEVERE', `Error: ${e.message}`);
        process.exit(1);
    }
}

main();
