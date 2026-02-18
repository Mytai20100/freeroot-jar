// Cooked by mytai
package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

var (
	urls = []string{
		"https://github.com/Mytai20100/freeroot.git",
		"https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
		"https://gitlab.com/Mytai20100/freeroot.git",
		"https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
		"https://git.snd.qzz.io/mytai20100/freeroot.git",
	}
	tmpDir     = "freeroot_temp"
	workDir    = "work"
	scriptName = "noninteractive.sh"

	sshIP   = "0.0.0.0"
	sshPort = 25565
	users   = map[string]string{"root": "root"}
)

func logMsg(level, msg string) {
	fmt.Printf("[%s] %s\n", level, msg)
}

func loadConfig() {
	cfgPath := "server.properties"
	if _, err := os.Stat(cfgPath); os.IsNotExist(err) {
		logMsg("INFO", fmt.Sprintf("No server.properties, using defaults: %s:%d", sshIP, sshPort))
		return
	}

	file, err := os.Open(cfgPath)
	if err != nil {
		logMsg("WARN", fmt.Sprintf("Config error: %v", err))
		return
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		switch key {
		case "server-ip":
			sshIP = value
		case "server-port":
			if port, err := strconv.Atoi(value); err == nil {
				sshPort = port
			}
		}
	}
	logMsg("INFO", fmt.Sprintf("Config loaded: %s:%d", sshIP, sshPort))
}

func checkCommand(cmd string) bool {
	_, err := exec.LookPath(cmd)
	if err != nil {
		return false
	}
	cmdExec := exec.Command(cmd, "--version")
	return cmdExec.Run() == nil
}

func deleteRecursive(path string) error {
	return os.RemoveAll(path)
}

func cloneRepo() bool {
	for i, url := range urls {
		logMsg("INFO", fmt.Sprintf("Trying clone from: %s (%d/%d)", url, i+1, len(urls)))
		cmd := exec.Command("git", "clone", "--depth=1", url, tmpDir)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err == nil {
			logMsg("INFO", fmt.Sprintf("Successfully cloned from: %s", url))
			return true
		}
		logMsg("WARN", fmt.Sprintf("Clone failed from %s", url))
		deleteRecursive(tmpDir)
	}
	return false
}

func executeScript(directory, script string) {
	logMsg("INFO", fmt.Sprintf("Executing script '%s'...", script))
	cmd := exec.Command("bash", script)
	cmd.Dir = directory
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		logMsg("ERROR", fmt.Sprintf("Execution error: %v", err))
	} else {
		logMsg("INFO", "Process completed")
	}
}

func createSSHWrapper() {
	wrapperPath := filepath.Join(workDir, "ssh.sh")

	if _, err := os.Stat(workDir); os.IsNotExist(err) {
		logMsg("INFO", "Work directory not ready yet, will create wrapper later")
		return
	}

	if _, err := os.Stat(wrapperPath); err == nil {
		os.Remove(wrapperPath)
	}

	script := `#!/bin/bash
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
`

	if err := os.WriteFile(wrapperPath, []byte(script), 0755); err != nil {
		logMsg("WARN", fmt.Sprintf("Failed to create SSH wrapper: %v", err))
		return
	}
	logMsg("INFO", "SSH wrapper created")
}

func handleSSHConnection(conn ssh.ConnMetadata, password []byte) (*ssh.Permissions, error) {
	if storedPass, exists := users[conn.User()]; exists {
		if string(password) == storedPass {
			return nil, nil
		}
	}
	return nil, fmt.Errorf("authentication failed")
}

func startSSHServer() {
	config := &ssh.ServerConfig{
		PasswordCallback: handleSSHConnection,
	}

	privateBytes, err := os.ReadFile("host.key")
	if err != nil {
		cmd := exec.Command("ssh-keygen", "-t", "rsa", "-b", "2048", "-f", "host.key", "-N", "")
		cmd.Run()
		privateBytes, _ = os.ReadFile("host.key")
		logMsg("INFO", "Generated host key")
	}

	private, err := ssh.ParsePrivateKey(privateBytes)
	if err != nil {
		log.Fatal("Failed to parse private key:", err)
	}
	config.AddHostKey(private)

	listener, err := ssh.Listen("tcp", fmt.Sprintf("%s:%d", sshIP, sshPort))
	if err != nil {
		log.Fatal("Failed to listen:", err)
	}
	logMsg("INFO", fmt.Sprintf("SSH server listening on %s:%d", sshIP, sshPort))

	for {
		conn, err := listener.Accept()
		if err != nil {
			logMsg("ERROR", fmt.Sprintf("Failed to accept: %v", err))
			continue
		}

		go func() {
			logMsg("INFO", "Client connected")
			sshConn, chans, reqs, err := ssh.NewServerConn(conn, config)
			if err != nil {
				logMsg("ERROR", fmt.Sprintf("Handshake failed: %v", err))
				return
			}
			defer sshConn.Close()

			go ssh.DiscardRequests(reqs)

			for newChannel := range chans {
				if newChannel.ChannelType() != "session" {
					newChannel.Reject(ssh.UnknownChannelType, "unknown channel type")
					continue
				}

				channel, requests, err := newChannel.Accept()
				if err != nil {
					logMsg("ERROR", fmt.Sprintf("Could not accept channel: %v", err))
					continue
				}

				go func(in <-chan *ssh.Request) {
					for req := range in {
						switch req.Type {
						case "shell", "exec":
							req.Reply(true, nil)

							sshScript := filepath.Join(workDir, "ssh.sh")
							shellCmd := "bash --login -i"
							if _, err := os.Stat(sshScript); err == nil {
								shellCmd = "cd work && bash ssh.sh"
							}

							cmd := exec.Command("script", "-qefc", shellCmd, "/dev/null")
							cmd.Env = append(os.Environ(),
								"TERM=xterm-256color",
								"LC_ALL=C",
								"LANG=C",
								"TMOUT=0",
								"HOSTNAME=furryisbest",
							)

							stdin, _ := cmd.StdinPipe()
							stdout, _ := cmd.StdoutPipe()
							stderr, _ := cmd.StderrPipe()

							go io.Copy(stdin, channel)
							go io.Copy(channel, stdout)
							go io.Copy(channel.Stderr(), stderr)

							cmd.Start()
							cmd.Wait()
							channel.Close()

						case "pty-req":
							req.Reply(true, nil)
						default:
							req.Reply(false, nil)
						}
					}
				}(requests)
			}
		}()
	}
}

func main() {
	loadConfig()

	go startSSHServer()

	go func() {
		time.Sleep(1 * time.Second)
		for {
			installedPath := filepath.Join(workDir, ".installed")
			if _, err := os.Stat(installedPath); err == nil {
				createSSHWrapper()
				break
			}
			time.Sleep(1 * time.Second)
		}
	}()

	if !checkCommand("git") {
		logMsg("ERROR", "Git not found")
		os.Exit(1)
	}
	if !checkCommand("bash") {
		logMsg("ERROR", "Bash not found")
		os.Exit(1)
	}

	if _, err := os.Stat(workDir); err == nil {
		logMsg("INFO", "Directory 'work' exists, checking...")
		scriptPath := filepath.Join(workDir, scriptName)
		if _, err := os.Stat(scriptPath); err == nil {
			logMsg("INFO", "Valid repo found, skipping clone")
			os.Chmod(scriptPath, 0755)
			executeScript(workDir, scriptName)
			select {}
		} else {
			logMsg("WARN", "Invalid repo, removing...")
			deleteRecursive(workDir)
		}
	}

	if _, err := os.Stat(tmpDir); err == nil {
		deleteRecursive(tmpDir)
	}

	if !cloneRepo() {
		logMsg("ERROR", "All clone attempts failed")
		os.Exit(1)
	}

	os.Rename(tmpDir, workDir)
	logMsg("INFO", "Renamed to 'work'")

	scriptPath := filepath.Join(workDir, scriptName)
	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		logMsg("ERROR", "Script not found")
		deleteRecursive(workDir)
		os.Exit(1)
	}

	os.Chmod(scriptPath, 0755)
	executeScript(workDir, scriptName)
	logMsg("INFO", "Freeroot")

	select {}
}
