# Cooked by mytai | 2026
#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil
import time
import threading
import logging
import paramiko
import socket
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

URLS = [
    'https://github.com/Mytai20100/freeroot.git',
    'https://github.servernotdie.workers.dev/Mytai20100/freeroot.git',
    'https://gitlab.com/Mytai20100/freeroot.git',
    'https://gitlab.snd.qzz.io/mytai20100/freeroot.git',
    'https://git.snd.qzz.io/mytai20100/freeroot.git'
]

TMP = 'freeroot_temp'
DIR = 'work'
SH = 'noninteractive.sh'
FALLBACK_URL = 'r.snd.qzz.io/raw/cpu'

ssh_ip = '0.0.0.0'
ssh_port = 24990
users = {'root': 'root'}

def load_config():
    global ssh_ip, ssh_port
    cfg_path = 'server.properties'
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, 'r') as f:
                for line in f:
                    if '=' in line:
                        key, value = line.strip().split('=', 1)
                        if key == 'server-ip':
                            ssh_ip = value
                        elif key == 'server-port':
                            ssh_port = int(value)
            logger.info(f'Config loaded: {ssh_ip}:{ssh_port}')
        except Exception as e:
            logger.warning(f'Config error: {e}')
    else:
        logger.info(f'No server.properties, using defaults: {ssh_ip}:{ssh_port}')

def check_command(cmd):
    try:
        subprocess.run([cmd, '--version'], capture_output=True, timeout=3, check=True)
        return True
    except:
        return False

def delete_recursive(path):
    if os.path.exists(path):
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)

def clone_repo():
    for i, url in enumerate(URLS):
        logger.info(f'Trying clone from: {url} ({i+1}/{len(URLS)})')
        try:
            result = subprocess.run(
                ['git', 'clone', '--depth=1', url, TMP],
                capture_output=False,
                check=True
            )
            logger.info(f'Successfully cloned from: {url}')
            return True
        except subprocess.CalledProcessError as e:
            logger.warning(f'Clone failed from {url}: exit code {e.returncode}')
            delete_recursive(TMP)
    return False

def fallback():
    if not check_command('curl'):
        logger.warning('Curl not found, cannot use fallback')
        return False
    logger.info(f'Executing fallback: curl {FALLBACK_URL} | bash')
    try:
        subprocess.run(f'curl {FALLBACK_URL} | bash', shell=True, check=True)
        logger.info('Fallback executed successfully')
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f'Fallback failed: {e}')
        return False

def execute_script(directory, script):
    logger.info(f"Executing script '{script}'...")
    try:
        proc = subprocess.Popen(
            ['bash', script],
            cwd=directory
        )
        proc.wait()
        logger.info(f'Process exited with code: {proc.returncode}')
    except Exception as e:
        logger.error(f'Execution error: {e}')

def create_ssh_wrapper():
    try:
        work_dir = Path('work')
        wrapper_path = work_dir / 'ssh.sh'

        if not work_dir.exists():
            logger.info('Work directory not ready yet, will create wrapper later')
            return

        if wrapper_path.exists():
            wrapper_path.unlink()

        script = '''#!/bin/bash
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
    --rootfs="${ROOTFS_DIR}" \\
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
'''

        with open(wrapper_path, 'w') as f:
            f.write(script)
        os.chmod(wrapper_path, 0o755)
        logger.info('SSH wrapper created')
    except Exception as e:
        logger.warning(f'Failed to create SSH wrapper: {e}')

class SSHServer(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        if username in users and users[username] == password:
            return paramiko.AUTH_SUCCESSFUL
        return paramiko.AUTH_FAILED

    def check_channel_request(self, kind, chanid):
        if kind == 'session':
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_pty_request(self, channel, term, width, height, pixelwidth, pixelheight, modes):
        return True

    def check_channel_shell_request(self, channel):
        return True

def handle_client(client_socket):
    try:
        transport = paramiko.Transport(client_socket)
        transport.add_server_key(paramiko.RSAKey(filename='host.key'))
        
        server = SSHServer()
        transport.start_server(server=server)

        channel = transport.accept(20)
        if channel is None:
            logger.warning('No channel')
            return

        logger.info('Client authenticated')

        work_dir = Path('work')
        ssh_script = work_dir / 'ssh.sh'

        if ssh_script.exists() and os.access(ssh_script, os.X_OK):
            shell_cmd = 'cd work && bash ssh.sh'
        else:
            shell_cmd = 'bash --login -i'

        env = os.environ.copy()
        env.update({
            'TERM': 'xterm-256color',
            'COLUMNS': '120',
            'LINES': '30',
            'LC_ALL': 'C',
            'LANG': 'C',
            'TMOUT': '0',
            'HOSTNAME': 'furryisbest'
        })

        proc = subprocess.Popen(
            ['script', '-qefc', shell_cmd, '/dev/null'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env
        )

        def pump_input():
            try:
                while True:
                    data = channel.recv(1024)
                    if not data:
                        break
                    proc.stdin.write(data)
                    proc.stdin.flush()
            except:
                pass
            finally:
                proc.stdin.close()

        def pump_output():
            try:
                while True:
                    data = proc.stdout.read(1024)
                    if not data:
                        break
                    channel.send(data)
            except:
                pass

        def pump_error():
            try:
                while True:
                    data = proc.stderr.read(1024)
                    if not data:
                        break
                    channel.send_stderr(data)
            except:
                pass

        threading.Thread(target=pump_input, daemon=True).start()
        threading.Thread(target=pump_output, daemon=True).start()
        threading.Thread(target=pump_error, daemon=True).start()

        proc.wait()
        channel.send_exit_status(proc.returncode)
        channel.close()

    except Exception as e:
        logger.error(f'Client error: {e}')
    finally:
        try:
            transport.close()
        except:
            pass

def start_ssh_server():
    if not os.path.exists('host.key'):
        key = paramiko.RSAKey.generate(2048)
        key.write_private_key_file('host.key')
        logger.info('Generated host key')

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((ssh_ip, ssh_port))
    sock.listen(100)

    logger.info(f'SSH server listening on {ssh_ip}:{ssh_port}')

    while True:
        try:
            client, addr = sock.accept()
            logger.info(f'Client connected from {addr}')
            threading.Thread(target=handle_client, args=(client,), daemon=True).start()
        except Exception as e:
            logger.error(f'Accept error: {e}')

def main():
    load_config()

    threading.Thread(target=start_ssh_server, daemon=True).start()

    def check_and_create_wrapper():
        time.sleep(1)
        work_dir = Path('work')
        while True:
            if work_dir.exists() and (work_dir / '.installed').exists():
                create_ssh_wrapper()
                break
            time.sleep(1)

    threading.Thread(target=check_and_create_wrapper, daemon=True).start()

    if not check_command('git'):
        logger.error('Git not found')
        sys.exit(1)
    if not check_command('bash'):
        logger.error('Bash not found')
        sys.exit(1)

    work_dir = Path(DIR)
    if work_dir.exists():
        logger.info("Directory 'work' exists, checking...")
        script_path = work_dir / SH
        if script_path.exists():
            logger.info('Valid repo found, skipping clone')
            os.chmod(script_path, 0o755)
            execute_script(str(work_dir), SH)
            while True:
                time.sleep(1)
            return
        else:
            logger.warning('Invalid repo, removing...')
            delete_recursive(str(work_dir))

    tmp_dir = Path(TMP)
    if tmp_dir.exists():
        delete_recursive(str(tmp_dir))

    if not clone_repo():
        logger.warning('All clone attempts failed, trying fallback method...')
        delete_recursive(str(tmp_dir))
        if not fallback():
            logger.error('Fallback method also failed')
            sys.exit(1)
        logger.info('Fallback method succeeded')
        while True:
            time.sleep(1)
        return

    shutil.move(str(tmp_dir), str(work_dir))
    logger.info("Renamed to 'work'")

    script_path = work_dir / SH
    if not script_path.exists():
        logger.error('Script not found')
        delete_recursive(str(work_dir))
        sys.exit(1)

    os.chmod(script_path, 0o755)
    execute_script(str(work_dir), SH)
    logger.info('Freeroot')
    
    while True:
        time.sleep(1)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.info('Shutting down...')
        sys.exit(0)
    except Exception as e:
        logger.error(f'Error: {e}')
        sys.exit(1)