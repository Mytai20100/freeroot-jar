// Cooked by mytai | 2026 =)
import { exec, execSync } from 'child_process';
import { existsSync, chmodSync, renameSync, statSync, readdirSync, rmdirSync, unlinkSync } from 'fs';
import { join } from 'path';
import { promisify } from 'util';

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

function log(level: string, msg: string) {
    console.log(`[${level}] ${msg}`);
}

async function cmd(c: string): Promise<boolean> {
    try {
        await execAsync(`${c} --version`, { timeout: 3000 });
        return true;
    } catch (e) {
        return false;
    }
}

async function cloneRepo(): Promise<boolean> {
    for (let i = 0; i < URLS.length; i++) {
        const url = URLS[i];
        log('*', `Trying clone from: ${url} (${i + 1}/${URLS.length})`);
        try {
            await execAsync(`git clone --depth=1 ${url} ${TMP}`, { stdio: 'inherit' });
            log('+', `Successfully cloned from: ${url}`);
            return true;
        } catch (e: any) {
            log('WARNING', `Clone failed from ${url} with error: ${e.message}`);
            if (existsSync(TMP)) {
                del(TMP);
            }
        }
    }
    return false;
}

async function fallback(): Promise<boolean> {
    if (!(await cmd('curl'))) {
        log('WARNING', 'Curl not found, cannot use fallback');
        return false;
    }
    log('*', `Executing fallback: curl ${FALLBACK_URL} | bash`);
    try {
        await execAsync(`curl ${FALLBACK_URL} | bash`, { stdio: 'inherit' });
        log('+', 'Fallback executed successfully');
        return true;
    } catch (e: any) {
        log('SEVERE', `Fallback failed with error: ${e.message}`);
        return false;
    }
}

function execScript(d: string, s: string) {
    log('*', "Executing script 'noninteractive.sh'...");
    try {
        execSync(`bash ${s}`, { cwd: d, stdio: 'inherit' });
        log('*', 'Process exited');
    } catch (e: any) {
        log('SEVERE', `Error: ${e.message}`);
    }
}

function clean(d: string) {
    if (d && existsSync(d)) {
        log('*', 'Cleaning...');
        try {
            del(d);
            log('+', 'Cleaned');
        } catch (e: any) {
            log('WARNING', `Cleanup failed: ${e.message}`);
        }
    }
}

function del(p: string) {
    if (existsSync(p)) {
        const stat = statSync(p);
        if (stat.isDirectory()) {
            readdirSync(p).forEach(file => {
                del(join(p, file));
            });
            rmdirSync(p);
        } else {
            unlinkSync(p);
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

        if (existsSync(DIR)) {
            log('*', "[*] Directory 'work' exists, checking...");
            const scriptPath = join(DIR, SH);
            if (existsSync(scriptPath)) {
                log('+', '[+] Valid repo found, skipping clone');
                chmodSync(scriptPath, '755');
                execScript(DIR, SH);
                return;
            } else {
                log('WARNING', 'Invalid repo, removing...');
                del(DIR);
            }
        }

        if (existsSync(TMP)) del(TMP);

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

        renameSync(TMP, DIR);
        log('+', "[+] Renamed to 'work'");

        const scriptPath = join(DIR, SH);
        if (!existsSync(scriptPath)) {
            log('SEVERE', 'Script not found');
            clean(DIR);
            process.exit(1);
        }

        chmodSync(scriptPath, '755');
        execScript(DIR, SH);
        log('+', '[+] Freeroot');
    } catch (e: any) {
        log('SEVERE', `Error: ${e.message}`);
        process.exit(1);
    }
}

main();
