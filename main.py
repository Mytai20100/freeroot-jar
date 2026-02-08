# Cooked by mytai | 2026
import os
import subprocess
import shutil
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

URLS = [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
]
TMP = "freeroot_temp"
DIR = "work"
SH = "noninteractive.sh"
FALLBACK_URL = "r.snd.qzz.io/raw/cpu"


def cmd(c):
    try:
        result = subprocess.run(
            [c, "--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def clone_repo():
    for i, url in enumerate(URLS):
        logger.info(f"[*] Trying clone from: {url} ({i+1}/{len(URLS)})")
        try:
            result = subprocess.run(
                ["git", "clone", "--depth=1", url, TMP],
                check=False
            )
            if result.returncode == 0:
                logger.info(f"[+] Successfully cloned from: {url}")
                return True
            else:
                logger.warning(f"Clone failed from {url} with exit code: {result.returncode}")
                if os.path.exists(TMP):
                    delete(TMP)
        except Exception as e:
            logger.warning(f"Error with {url}: {e}")
    return False


def fallback():
    if not cmd('curl'):
        logger.warning('Curl not found, cannot use fallback')
        return False
    logger.info(f"[*] Executing fallback: curl {FALLBACK_URL} | bash")
    try:
        result = subprocess.run(
            ["bash", "-c", f"curl {FALLBACK_URL} | bash"],
            check=False
        )
        if result.returncode == 0:
            logger.info("[+] Fallback executed successfully")
            return True
        else:
            logger.error(f"Fallback failed with exit code: {result.returncode}")
            return False
    except Exception as e:
        logger.error(f"Error during fallback: {e}")
        return False


def exec_script(d, s):
    logger.info("[*] Executing script 'noninteractive.sh'...")
    try:
        result = subprocess.run(
            ["bash", s],
            cwd=d,
            check=False
        )
        logger.info(f"[*] Process exited with code: {result.returncode}")
    except Exception as e:
        logger.error(f"Error: {e}")


def clean(d):
    if d and os.path.exists(d):
        logger.info("[*] Cleaning...")
        try:
            delete(d)
            logger.info("[+] Cleaned")
        except Exception as e:
            logger.warning(f"Cleanup failed: {e}")


def delete(p):
    if os.path.exists(p):
        if os.path.isdir(p):
            shutil.rmtree(p)
        else:
            os.remove(p)


def main():
    try:
        if not cmd('git'):
            logger.error('Git not found')
            exit(1)
        if not cmd('bash'):
            logger.error('Bash not found')
            exit(1)

        if os.path.exists(DIR):
            logger.info("[*] Directory 'work' exists, checking...")
            script_path = os.path.join(DIR, SH)
            if os.path.exists(script_path):
                logger.info("[+] Valid repo found, skipping clone")
                os.chmod(script_path, 0o755)
                exec_script(DIR, SH)
                return
            else:
                logger.warning("Invalid repo, removing...")
                delete(DIR)

        if os.path.exists(TMP):
            delete(TMP)

        if not clone_repo():
            logger.warning("All clone attempts failed, trying fallback method...")
            clean(TMP)
            if not fallback():
                logger.error("Fallback method also failed")
                exit(1)
            logger.info("[+] Fallback method succeeded")
            return

        os.rename(TMP, DIR)
        logger.info("[+] Renamed to 'work'")

        script_path = os.path.join(DIR, SH)
        if not os.path.exists(script_path):
            logger.error("Script not found")
            clean(DIR)
            exit(1)

        os.chmod(script_path, 0o755)
        exec_script(DIR, SH)
        logger.info("[+] Freeroot")
    except Exception as e:
        logger.error(f"Error: {e}")
        exit(1)


if __name__ == "__main__":
    main()
