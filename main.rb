# Cooked by mytai
#!/usr/bin/env ruby
require 'net/ssh'
require 'fileutils'
require 'socket'
require 'open3'
 
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

$ssh_ip = '0.0.0.0'
$ssh_port = 25565
$users = { 'root' => 'root' }

def log(level, msg)
  puts "[#{level}] #{msg}"
end

def load_config
  cfg_path = 'server.properties'
  if File.exist?(cfg_path)
    begin
      File.readlines(cfg_path).each do |line|
        key, value = line.strip.split('=', 2)
        next unless value
        case key
        when 'server-ip'
          $ssh_ip = value
        when 'server-port'
          $ssh_port = value.to_i
        end
      end
      log('INFO', "Config loaded: #{$ssh_ip}:#{$ssh_port}")
    rescue => e
      log('WARN', "Config error: #{e.message}")
    end
  else
    log('INFO', "No server.properties, using defaults: #{$ssh_ip}:#{$ssh_port}")
  end
end

def check_command(cmd)
  system("#{cmd} --version > /dev/null 2>&1")
end

def delete_recursive(path)
  FileUtils.rm_rf(path) if File.exist?(path)
end

def clone_repo
  URLS.each_with_index do |url, i|
    log('INFO', "Trying clone from: #{url} (#{i + 1}/#{URLS.length})")
    begin
      system('git', 'clone', '--depth=1', url, TMP)
      if $?.success?
        log('INFO', "Successfully cloned from: #{url}")
        return true
      else
        log('WARN', "Clone failed from #{url}")
        delete_recursive(TMP)
      end
    rescue => e
      log('WARN', "Clone error from #{url}: #{e.message}")
      delete_recursive(TMP)
    end
  end
  false
end

def execute_script(directory, script)
  log('INFO', "Executing script '#{script}'...")
  Dir.chdir(directory) do
    system('bash', script)
    log('INFO', "Process exited with code: #{$?.exitstatus}")
  end
end

def create_ssh_wrapper
  work_dir = 'work'
  wrapper_path = File.join(work_dir, 'ssh.sh')

  unless File.exist?(work_dir)
    log('INFO', 'Work directory not ready yet, will create wrapper later')
    return
  end

  File.delete(wrapper_path) if File.exist?(wrapper_path)

  script = <<~'BASH'
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
  BASH

  File.write(wrapper_path, script)
  File.chmod(0755, wrapper_path)
  log('INFO', 'SSH wrapper created')
rescue => e
  log('WARN', "Failed to create SSH wrapper: #{e.message}")
end

def start_ssh_server
  unless File.exist?('host.key')
    system('ssh-keygen -t rsa -b 2048 -f host.key -N ""')
    log('INFO', 'Generated host key')
  end

  server = TCPServer.new($ssh_ip, $ssh_port)
  log('INFO', "SSH server listening on #{$ssh_ip}:#{$ssh_port}")

  loop do
    Thread.start(server.accept) do |client|
      begin
        log('INFO', 'Client connected')
        
        work_dir = 'work'
        ssh_script = File.join(work_dir, 'ssh.sh')

        shell_cmd = if File.exist?(ssh_script) && File.executable?(ssh_script)
                      'cd work && bash ssh.sh'
                    else
                      'bash --login -i'
                    end

        Open3.popen3('script', '-qefc', shell_cmd, '/dev/null') do |stdin, stdout, stderr, wait_thr|
          Thread.new do
            loop do
              data = client.recv(1024)
              break if data.empty?
              stdin.write(data)
              stdin.flush
            end
          rescue
            nil
          end

          Thread.new do
            loop do
              data = stdout.read(1024)
              break unless data
              client.write(data)
            end
          rescue
            nil
          end

          Thread.new do
            loop do
              data = stderr.read(1024)
              break unless data
              client.write(data)
            end
          rescue
            nil
          end

          wait_thr.join
        end
      rescue => e
        log('ERROR', "Client error: #{e.message}")
      ensure
        client.close rescue nil
      end
    end
  end
rescue => e
  log('ERROR', "Server error: #{e.message}")
end

def main
  load_config

  Thread.new { start_ssh_server }

  Thread.new do
    sleep 1
    work_dir = 'work'
    loop do
      if File.exist?(work_dir) && File.exist?(File.join(work_dir, '.installed'))
        create_ssh_wrapper
        break
      end
      sleep 1
    end
  end

  unless check_command('git')
    log('ERROR', 'Git not found')
    exit 1
  end
  unless check_command('bash')
    log('ERROR', 'Bash not found')
    exit 1
  end

  work_dir = DIR
  if File.exist?(work_dir)
    log('INFO', "Directory 'work' exists, checking...")
    script_path = File.join(work_dir, SH)
    if File.exist?(script_path)
      log('INFO', 'Valid repo found, skipping clone')
      File.chmod(0755, script_path)
      execute_script(work_dir, SH)
      sleep
      return
    else
      log('WARN', 'Invalid repo, removing...')
      delete_recursive(work_dir)
    end
  end

  tmp_dir = TMP
  delete_recursive(tmp_dir) if File.exist?(tmp_dir)

  unless clone_repo
    log('ERROR', 'All clone attempts failed')
    exit 1
  end

  FileUtils.mv(tmp_dir, work_dir)
  log('INFO', "Renamed to 'work'")

  script_path = File.join(work_dir, SH)
  unless File.exist?(script_path)
    log('ERROR', 'Script not found')
    delete_recursive(work_dir)
    exit 1
  end

  File.chmod(0755, script_path)
  execute_script(work_dir, SH)
  log('INFO', 'Freeroot')
  
  sleep
end

begin
  main
rescue Interrupt
  log('INFO', 'Shutting down...')
  exit 0
rescue => e
  log('ERROR', "Error: #{e.message}")
  exit 1
end
