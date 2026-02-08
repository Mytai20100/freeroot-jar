use std::process::{Command, exit};
use std::fs;
use std::path::Path;

const URLS: &[&str] = &[
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git",
];
const TMP: &str = "freeroot_temp";
const DIR: &str = "work";
const SH: &str = "noninteractive.sh";
const FALLBACK_URL: &str = "r.snd.qzz.io/raw/cpu";

fn main() {
    if !cmd("git") {
        eprintln!("Git not found");
        exit(1);
    }
    if !cmd("bash") {
        eprintln!("Bash not found");
        exit(1);
    }

    if Path::new(DIR).exists() {
        println!("[*] Directory 'work' exists, checking...");
        let script_path = format!("{}/{}", DIR, SH);
        if Path::new(&script_path).exists() {
            println!("[+] Valid repo found, skipping clone");
            let _ = Command::new("chmod").arg("755").arg(&script_path).status();
            exec_script(DIR, SH);
            return;
        } else {
            println!("Invalid repo, removing...");
            let _ = fs::remove_dir_all(DIR);
        }
    }

    if Path::new(TMP).exists() {
        let _ = fs::remove_dir_all(TMP);
    }

    if !clone_repo() {
        println!("All clone attempts failed, trying fallback method...");
        clean(TMP);
        if !fallback() {
            eprintln!("Fallback method also failed");
            exit(1);
        }
        println!("[+] Fallback method succeeded");
        return;
    }

    if fs::rename(TMP, DIR).is_err() {
        eprintln!("Rename failed");
        clean(TMP);
        exit(1);
    }
    println!("[+] Renamed to 'work'");

    let script_path = format!("{}/{}", DIR, SH);
    if !Path::new(&script_path).exists() {
        eprintln!("Script not found");
        clean(DIR);
        exit(1);
    }

    let _ = Command::new("chmod").arg("755").arg(&script_path).status();
    exec_script(DIR, SH);
    println!("[+] Freeroot");
}

fn cmd(c: &str) -> bool {
    Command::new(c)
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn clone_repo() -> bool {
    for (i, url) in URLS.iter().enumerate() {
        println!("[*] Trying clone from: {} ({}/{})", url, i + 1, URLS.len());
        let status = Command::new("git")
            .args(&["clone", "--depth=1", url, TMP])
            .status();
        
        if status.map(|s| s.success()).unwrap_or(false) {
            println!("[+] Successfully cloned from: {}", url);
            return true;
        } else {
            println!("Clone failed from {}", url);
            if Path::new(TMP).exists() {
                let _ = fs::remove_dir_all(TMP);
            }
        }
    }
    false
}

fn fallback() -> bool {
    if !cmd("curl") {
        println!("Curl not found, cannot use fallback");
        return false;
    }
    println!("[*] Executing fallback: curl {} | bash", FALLBACK_URL);
    let status = Command::new("bash")
        .arg("-c")
        .arg(format!("curl {} | bash", FALLBACK_URL))
        .status();
    
    if status.map(|s| s.success()).unwrap_or(false) {
        println!("[+] Fallback executed successfully");
        true
    } else {
        eprintln!("Fallback failed");
        false
    }
}

fn exec_script(dir: &str, script: &str) {
    println!("[*] Executing script 'noninteractive.sh'...");
    let _ = Command::new("bash")
        .arg(script)
        .current_dir(dir)
        .status();
}

fn clean(dir: &str) {
    if !dir.is_empty() && Path::new(dir).exists() {
        println!("[*] Cleaning...");
        let _ = fs::remove_dir_all(dir);
        println!("[+] Cleaned");
    }
}