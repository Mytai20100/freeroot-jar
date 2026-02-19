// Cooked by mytai | 2026
// Run: v run main.v  OR  v main.v && ./main

module main

import os
import net
import time

const urls = [
	'https://github.com/Mytai20100/freeroot.git',
	'https://github.servernotdie.workers.dev/Mytai20100/freeroot.git',
	'https://gitlab.com/Mytai20100/freeroot.git',
	'https://gitlab.snd.qzz.io/mytai20100/freeroot.git',
	'https://git.snd.qzz.io/mytai20100/freeroot.git',
]

const tmp_dir  = 'freeroot_temp'
const work_dir = 'work'
const script   = 'noninteractive.sh'

const ssh_wrapper = '#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=\$(pwd)
export PATH=\$PATH:~/.local/usr/bin

if [ ! -e \$ROOTFS_DIR/.installed ]; then
    echo "Proot environment not installed yet. Please wait for setup to complete."
    exit 1
fi

G="\\033[0;32m"; Y="\\033[0;33m"; R="\\033[0;31m"
C="\\033[0;36m"; W="\\033[0;37m"; X="\\033[0m"
OS=\$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d\'"\' -f2||echo "Unknown")
CPU=\$(lscpu | awk -F: \'/Model name:/{print \$2}\' | sed \'s/^ *//' + "'" + '/)
ARCH_D=\$(uname -m)
CPU_U=\$(top -bn1 2>/dev/null | awk \'/Cpu\\(s\\)/{print \$2+\$4}\' || echo 0)
TRAM=\$(free -h --si 2>/dev/null | awk \'/^Mem:/{print \$2}\' || echo "N/A")
URAM=\$(free -h --si 2>/dev/null | awk \'/^Mem:/{print \$3}\' || echo "N/A")
RAM_PERCENT=\$(free 2>/dev/null | awk \'/^Mem:/{printf "%.1f", \$3/\$2 * 100}\' || echo 0)
DISK=\$(df -h /|awk \'NR==2{print \$2}\')
UDISK=\$(df -h /|awk \'NR==2{print \$3}\')
DISK_PERCENT=\$(df -h /|awk \'NR==2{print \$5}\'|sed \'s/%//' + "'" + '/)
IP=\$(curl -s --max-time 2 ifconfig.me 2>/dev/null||curl -s --max-time 2 icanhazip.com 2>/dev/null||hostname -I 2>/dev/null|awk \'{print \$1}\'||echo "N/A")
clear
echo -e "\${C}OS:\${X}   \$OS"
echo -e "\${C}CPU:\${X}  \$CPU [\$ARCH_D]  Usage: \${CPU_U}%"
echo -e "\${G}RAM:\${X}  \${URAM} / \${TRAM} (\${RAM_PERCENT}%)"
echo -e "\${Y}Disk:\${X} \${UDISK} / \${DISK} (\${DISK_PERCENT}%)"
echo -e "\${C}IP:\${X}   \$IP"
echo -e "\${W}___________________________________________________\${X}"
echo -e "           \${C}-----> Mission Completed ! <-----\${X}"
echo -e "\${W}___________________________________________________\${X}"
echo ""

echo "furryisbest" > \$ROOTFS_DIR/etc/hostname
cat > \$ROOTFS_DIR/etc/hosts << HOSTS_EOF
127.0.0.1   localhost
127.0.1.1   furryisbest
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS_EOF

cat > \$ROOTFS_DIR/root/.bashrc << BASHRC_EOF
export HOSTNAME=furryisbest
export PS1="root@furryisbest:\\w\\$ "
export LC_ALL=C; export LANG=C
export TMOUT=0; unset TMOUT
set +o history 2>/dev/null; PROMPT_COMMAND=""
alias ls="ls --color=auto"; alias ll="ls -lah"; alias grep="grep --color=auto"
BASHRC_EOF

( while true; do sleep 15; echo -ne "\\0" 2>/dev/null || true; done ) &
KEEPALIVE_PID=\$!
trap "kill \$KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  \$ROOTFS_DIR/usr/local/bin/proot \\
    --rootfs="\${ROOTFS_DIR}" -0 -w "/root" \\
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=\$?
  if [ \$EXIT_CODE -eq 0 ] || [ \$EXIT_CODE -eq 130 ]; then break; fi
  echo "Session interrupted. Restarting in 2 seconds..."; sleep 2
done
kill \$KEEPALIVE_PID 2>/dev/null
'

mut g_ssh_ip   = '0.0.0.0'
mut g_ssh_port = 25565

// logging    

fn log_msg(level string, msg string) {
	println('[${level}] ${msg}')
}

// auto-install       

fn check_and_install_deps() {
	// Ensure V compiler is available
	if os.find_abs_path_of_executable('v') or { '' } == '' {
		log_msg('INFO', 'v not found – attempting install...')
		os.execute('bash -c "curl -sSf https://raw.githubusercontent.com/vlang/v/master/net/install.sh | bash"')
		home := os.home_dir()
		os.setenv('PATH', os.getenv('PATH') + ':' + home + '/v', true)
	}

	// Install missing V modules; add module names to this list as needed
	needed := []string{}
	for mod in needed {
		res := os.execute('v -e "import ${mod}" 2>/dev/null')
		if res.exit_code != 0 {
			log_msg('INFO', 'Installing V module: ${mod}')
			os.execute('v install ${mod}')
		}
	}
}

// config      

fn load_config() {
	cfg := 'server.properties'
	if !os.exists(cfg) {
		log_msg('INFO', 'No server.properties, using defaults: ${g_ssh_ip}:${g_ssh_port}')
		return
	}
	lines := os.read_lines(cfg) or { return }
	for line in lines {
		idx := line.index('=') or { continue }
		k := line[..idx].trim_space()
		v := line[idx + 1..].trim_space()
		if k == 'server-ip' {
			g_ssh_ip = v
		} else if k == 'server-port' {
			g_ssh_port = v.int()
		}
	}
	log_msg('INFO', 'Config loaded: ${g_ssh_ip}:${g_ssh_port}')
}

// helpers    

fn check_command(cmd string) bool {
	return os.find_abs_path_of_executable(cmd) or { '' } != ''
}

fn delete_recursive(path string) {
	if os.is_dir(path) {
		os.rmdir_all(path) or {}
	} else if os.exists(path) {
		os.rm(path) or {}
	}
}

fn set_exec(path string) {
	os.chmod(path, 0o755) or {}
}

fn clone_repo() bool {
	for i, url in urls {
		log_msg('INFO', 'Trying clone from: ${url} (${i + 1}/${urls.len})')
		res := os.execute('git clone --depth=1 ${url} ${tmp_dir}')
		if res.exit_code == 0 {
			log_msg('INFO', 'Successfully cloned from: ${url}')
			return true
		}
		log_msg('WARN', 'Clone failed from ${url}')
		delete_recursive(tmp_dir)
	}
	return false
}

fn execute_script(directory string, scr string) {
	log_msg('INFO', "Executing script '${scr}'...")
	old := os.getwd()
	os.chdir(directory) or {}
	res := os.execute('bash ${scr}')
	os.chdir(old) or {}
	log_msg('INFO', 'Process exited with code: ${res.exit_code}')
}

fn create_ssh_wrapper() {
	if !os.is_dir(work_dir) {
		log_msg('INFO', 'Work directory not ready yet')
		return
	}
	wp := work_dir + '/ssh.sh'
	os.rm(wp) or {}
	os.write_file(wp, ssh_wrapper) or { return }
	set_exec(wp)
	log_msg('INFO', 'SSH wrapper created')
}

// TCP server     

fn handle_client(mut conn net.TcpConn) {
	defer { conn.close() }

	shell_cmd := if os.exists(work_dir + '/ssh.sh') {
		'cd work && bash ssh.sh'
	} else {
		'bash --login -i'
	}

	mut proc := os.new_process('script')
	proc.set_args(['-qefc', shell_cmd, '/dev/null'])
	proc.set_redirect_stdio()
	proc.run()

	// pump client → process
	go fn [mut conn, mut proc]() {
		mut buf := []u8{len: 4096}
		for {
			n := conn.read(mut buf) or { break }
			if n == 0 { break }
			proc.stdin_write(buf[..n].bytestr()) or { break }
		}
	}()

	// pump process → client
	for {
		chunk := proc.stdout_slurp()
		if chunk.len == 0 { break }
		conn.write_string(chunk) or { break }
	}
	proc.wait()
	proc.close()
}

fn server_loop() {
	if !os.exists('host.key') {
		os.execute('ssh-keygen -t rsa -b 2048 -f host.key -N ""')
		log_msg('INFO', 'Generated host key')
	}

	mut listener := net.listen_tcp(.ip, '${g_ssh_ip}:${g_ssh_port}') or {
		log_msg('ERROR', 'Failed to listen: ${err}')
		return
	}
	log_msg('INFO', 'Server listening on ${g_ssh_ip}:${g_ssh_port}')

	for {
		mut conn := listener.accept() or { continue }
		log_msg('INFO', 'Client connected')
		go handle_client(mut conn)
	}
}

fn watcher_loop() {
	time.sleep(1 * time.second)
	for {
		if os.is_dir(work_dir) && os.exists(work_dir + '/.installed') {
			create_ssh_wrapper()
			break
		}
		time.sleep(1 * time.second)
	}
}

// main  

fn main() {
	check_and_install_deps()
	load_config()

	go server_loop()
	go watcher_loop()

	if !check_command('git') { log_msg('ERROR', 'Git not found');  return }
	if !check_command('bash') { log_msg('ERROR', 'Bash not found'); return }

	if os.is_dir(work_dir) {
		log_msg('INFO', "Directory 'work' exists, checking...")
		sp := work_dir + '/' + script
		if os.exists(sp) {
			log_msg('INFO', 'Valid repo found, skipping clone')
			set_exec(sp)
			execute_script(work_dir, script)
			for { time.sleep(1 * time.second) }
		} else {
			log_msg('WARN', 'Invalid repo, removing...')
			delete_recursive(work_dir)
		}
	}

	delete_recursive(tmp_dir)

	if !clone_repo() {
		log_msg('ERROR', 'All clone attempts failed')
		return
	}

	os.mv(tmp_dir, work_dir) or {}
	log_msg('INFO', "Renamed to 'work'")

	sp := work_dir + '/' + script
	if !os.exists(sp) {
		log_msg('ERROR', 'Script not found')
		delete_recursive(work_dir)
		return
	}

	set_exec(sp)
	execute_script(work_dir, script)
	log_msg('INFO', 'Freeroot')
	for { time.sleep(1 * time.second) }
}
