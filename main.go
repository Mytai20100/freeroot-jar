package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

var (
	URLS = []string{
		"https://github.com/Mytai20100/freeroot.git",
		"https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
		"https://gitlab.com/Mytai20100/freeroot.git",
		"https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
		"https://git.snd.qzz.io/mytai20100/freeroot.git",
	}
	TMP          = "freeroot_temp"
	DIR          = "work"
	SH           = "noninteractive.sh"
	FALLBACK_URL = "r.snd.qzz.io/raw/cpu"
)

func main() {
	if !cmd("git") {
		log.Fatal("Git not found")
	}
	if !cmd("bash") {
		log.Fatal("Bash not found")
	}

	if _, err := os.Stat(DIR); err == nil {
		log.Println("[*] Directory 'work' exists, checking...")
		scriptPath := filepath.Join(DIR, SH)
		if _, err := os.Stat(scriptPath); err == nil {
			log.Println("[+] Valid repo found, skipping clone")
			os.Chmod(scriptPath, 0755)
			execScript(DIR, SH)
			return
		} else {
			log.Println("Invalid repo, removing...")
			os.RemoveAll(DIR)
		}
	}

	if _, err := os.Stat(TMP); err == nil {
		os.RemoveAll(TMP)
	}

	if !cloneRepo() {
		log.Println("All clone attempts failed, trying fallback method...")
		clean(TMP)
		if !fallback() {
			log.Fatal("Fallback method also failed")
		}
		log.Println("[+] Fallback method succeeded")
		return
	}

	if err := os.Rename(TMP, DIR); err != nil {
		log.Fatal("Rename failed")
	}
	log.Println("[+] Renamed to 'work'")

	scriptPath := filepath.Join(DIR, SH)
	if _, err := os.Stat(scriptPath); err != nil {
		log.Fatal("Script not found")
	}

	os.Chmod(scriptPath, 0755)
	execScript(DIR, SH)
	log.Println("[+] Freeroot")
}

func cmd(c string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, c, "--version")
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run() == nil
}

func cloneRepo() bool {
	for i, url := range URLS {
		log.Printf("[*] Trying clone from: %s (%d/%d)\n", url, i+1, len(URLS))
		cmd := exec.Command("git", "clone", "--depth=1", url, TMP)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err == nil {
			log.Printf("[+] Successfully cloned from: %s\n", url)
			return true
		} else {
			log.Printf("Clone failed from %s\n", url)
			os.RemoveAll(TMP)
		}
	}
	return false
}

func fallback() bool {
	if !cmd("curl") {
		log.Println("Curl not found, cannot use fallback")
		return false
	}
	log.Printf("[*] Executing fallback: curl %s | bash\n", FALLBACK_URL)
	cmd := exec.Command("bash", "-c", "curl "+FALLBACK_URL+" | bash")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err == nil {
		log.Println("[+] Fallback executed successfully")
		return true
	} else {
		log.Println("Fallback failed")
		return false
	}
}

func execScript(dir, script string) {
	log.Println("[*] Executing script 'noninteractive.sh'...")
	cmd := exec.Command("bash", script)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()
}

func clean(dir string) {
	if dir != "" {
		if _, err := os.Stat(dir); err == nil {
			log.Println("[*] Cleaning...")
			os.RemoveAll(dir)
			log.Println("[+] Cleaned")
		}
	}
}