// Cooked by mytai
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{Write, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio, Child};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::process::Command as TokioCommand;
use tokio::sync::RwLock;
use russh::server::{Server, Session, Handler};
use russh::{Channel, ChannelId};
use russh_keys::key::KeyPair;

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

struct Config {
    ssh_ip: String,
    ssh_port: u16,
    users: HashMap<String, String>,
}

impl Config {
    fn load() -> Self {
        let mut config = Config {
            ssh_ip: "0.0.0.0".to_string(),
            ssh_port: 24990,
            users: HashMap::new(),
        };
        config.users.insert("root".to_string(), "root".to_string());

        if let Ok(content) = fs::read_to_string("server.properties") {
            for line in content.lines() {
                if let Some((key, value)) = line.split_once('=') {
                    match key.trim() {
                        "server-ip" => config.ssh_ip = value.trim().to_string(),
                        "server-port" => {
                            if let Ok(port) = value.trim().parse() {
                                config.ssh_port = port;
                            }
                        }
                        _ => {}
                    }
                }
            }
            println!("[INFO] Config loaded: {}:{}", config.ssh_ip, config.ssh_port);
        } else {
            println!("[INFO] No server.properties, using defaults: {}:{}", config.ssh_ip, config.ssh_port);
        }
        config
    }
}

fn check_command(cmd: &str) -> bool {
    Command::new(cmd)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn delete_recursive(path: &Path) -> std::io::Result<()> {
    if path.exists() {
        if path.is_dir() {
            fs::remove_dir_all(path)?;
        } else {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

fn clone_repo() -> bool {
    for (i, url) in URLS.iter().enumerate() {
        println!("[INFO] Trying clone from: {} ({}/{})", url, i + 1, URLS.len());
        let status = Command::new("git")
            .args(&["clone", "--depth=1", url, TMP])
            .status();

        match status {
            Ok(s) if s.success() => {
                println!("[INFO] Successfully cloned from: {}", url);
                return true;
            }
            _ => {
                println!("[WARN] Clone failed from {}", url);
                let _ = delete_recursive(Path::new(TMP));
            }
        }
    }
    false
}

fn fallback() -> bool {
    if !check_command("curl") {
        println!("[WARN] Curl not found, cannot use fallback");
        return false;
    }
    println!("[INFO] Executing fallback: curl {} | bash", FALLBACK_URL);
    
    let status = Command::new("bash")
        .arg("-c")
        .arg(format!("curl {} | bash", FALLBACK_URL))
        .status();

    match status {
        Ok(s) if s.success() => {
            println!("[INFO] Fallback executed successfully");
            true
        }
        _ => {
            println!("[ERROR] Fallback failed");
            false
        }
    }
}

fn execute_script(dir: &Path, script: &str) {
    println!("[INFO] Executing script '{}'...", script);
    let status = Command::new("bash")
        .arg(script)
        .current_dir(dir)
        .status();

    if let Ok(s) = status {
        println!("[INFO] Process exited with code: {:?}", s.code());
    }
}

fn create_ssh_wrapper() {
    let work_dir = PathBuf::from("work");
    let wrapper_path = work_dir.join("ssh.sh");

    if !work_dir.exists() {
        println!("[INFO] Work directory not ready yet, will create wrapper later");
        return;
    }

    if wrapper_path.exists() {
        let _ = fs::remove_file(&wrapper_path);
    }

    let script = r#"#!/bin/bash
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
"#;

    if let Ok(mut file) = File::create(&wrapper_path) {
        let _ = file.write_all(script.as_bytes());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&wrapper_path, fs::Permissions::from_mode(0o755));
        }
        println!("[INFO] SSH wrapper created");
    }
}

struct SSHHandler {
    users: Arc<HashMap<String, String>>,
}

#[async_trait::async_trait]
impl Handler for SSHHandler {
    type Error = russh::Error;

    async fn auth_password(
        self,
        user: &str,
        password: &str,
    ) -> Result<(Self, russh::server::Auth), Self::Error> {
        if let Some(pass) = self.users.get(user) {
            if pass == password {
                return Ok((self, russh::server::Auth::Accept));
            }
        }
        Ok((self, russh::server::Auth::Reject))
    }

    async fn channel_open_session(
        self,
        channel: Channel<russh::server::Msg>,
        session: Session,
    ) -> Result<(Self, bool, Session), Self::Error> {
        Ok((self, true, session))
    }

    async fn pty_request(
        self,
        channel: ChannelId,
        term: &str,
        col_width: u32,
        row_height: u32,
        pix_width: u32,
        pix_height: u32,
        modes: &[(russh::Pty, u32)],
        session: Session,
    ) -> Result<(Self, Session), Self::Error> {
        Ok((self, session))
    }

    async fn shell_request(
        self,
        channel: ChannelId,
        mut session: Session,
    ) -> Result<(Self, Session), Self::Error> {
        let work_dir = PathBuf::from("work");
        let ssh_script = work_dir.join("ssh.sh");

        let shell_cmd = if ssh_script.exists() {
            "cd work && bash ssh.sh"
        } else {
            "bash --login -i"
        };

        tokio::spawn(async move {
            let mut child = TokioCommand::new("script")
                .args(&["-qefc", shell_cmd, "/dev/null"])
                .env("TERM", "xterm-256color")
                .env("LC_ALL", "C")
                .env("LANG", "C")
                .env("TMOUT", "0")
                .env("HOSTNAME", "furryisbest")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .ok();

            if let Some(ref mut proc) = child {
                let _ = proc.wait().await;
            }
        });

        Ok((self, session))
    }
}

#[tokio::main]
async fn main() {
    let config = Config::load();
    
    tokio::spawn(async {
        tokio::time::sleep(Duration::from_secs(1)).await;
        loop {
            let work_dir = PathBuf::from("work");
            if work_dir.exists() && work_dir.join(".installed").exists() {
                create_ssh_wrapper();
                break;
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    });

    let users = Arc::new(config.users.clone());
    let ssh_config = russh::server::Config {
        inactivity_timeout: None,
        auth_rejection_time: Duration::from_secs(3),
        keys: vec![],
        ..Default::default()
    };

    if !check_command("git") {
        eprintln!("[ERROR] Git not found");
        std::process::exit(1);
    }
    if !check_command("bash") {
        eprintln!("[ERROR] Bash not found");
        std::process::exit(1);
    }

    let work_dir = PathBuf::from(DIR);
    if work_dir.exists() {
        println!("[INFO] Directory 'work' exists, checking...");
        let script_path = work_dir.join(SH);
        if script_path.exists() {
            println!("[INFO] Valid repo found, skipping clone");
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755));
            }
            execute_script(&work_dir, SH);
            loop {
                std::thread::sleep(Duration::from_secs(1));
            }
        } else {
            println!("[WARN] Invalid repo, removing...");
            let _ = delete_recursive(&work_dir);
        }
    }

    let tmp_dir = PathBuf::from(TMP);
    if tmp_dir.exists() {
        let _ = delete_recursive(&tmp_dir);
    }

    if !clone_repo() {
        println!("[WARN] All clone attempts failed, trying fallback method...");
        let _ = delete_recursive(&tmp_dir);
        if !fallback() {
            eprintln!("[ERROR] Fallback method also failed");
            std::process::exit(1);
        }
        println!("[INFO] Fallback method succeeded");
        loop {
            std::thread::sleep(Duration::from_secs(1));
        }
    }

    let _ = fs::rename(&tmp_dir, &work_dir);
    println!("[INFO] Renamed to 'work'");

    let script_path = work_dir.join(SH);
    if !script_path.exists() {
        eprintln!("[ERROR] Script not found");
        let _ = delete_recursive(&work_dir);
        std::process::exit(1);
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755));
    }
    
    execute_script(&work_dir, SH);
    println!("[INFO] Freeroot");

    loop {
        std::thread::sleep(Duration::from_secs(1));
    }
}