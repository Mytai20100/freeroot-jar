# Cooked by mytai | 2026
# Run: raku main.raku

use v6.d;

constant URLS = <
    https://github.com/Mytai20100/freeroot.git
    https://github.servernotdie.workers.dev/Mytai20100/freeroot.git
    https://gitlab.com/Mytai20100/freeroot.git
    https://gitlab.snd.qzz.io/mytai20100/freeroot.git
    https://git.snd.qzz.io/mytai20100/freeroot.git
>;

constant TMP_DIR  = 'freeroot_temp';
constant WORK_DIR = 'work';
constant SCRIPT   = 'noninteractive.sh';

constant SSH_WRAPPER = q:to/WRAPPER_END/;
    #!/bin/bash
    export LC_ALL=C
    export LANG=C
    ROOTFS_DIR=$(pwd)
    export PATH=$PATH:~/.local/usr/bin

    if [ ! -e $ROOTFS_DIR/.installed ]; then
        echo 'Proot environment not installed yet. Please wait for setup to complete.'
        exit 1
    fi

    G="\033[0;32m"; Y="\033[0;33m"; R="\033[0;31m"
    C="\033[0;36m"; W="\033[0;37m"; X="\033[0m"
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
    export LC_ALL=C; export LANG=C
    export TMOUT=0; unset TMOUT
    set +o history 2>/dev/null; PROMPT_COMMAND=''
    alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'
    BASHRC_EOF

    ( while true; do sleep 15; echo -ne '\0' 2>/dev/null || true; done ) &
    KEEPALIVE_PID=$!
    trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

    while true; do
      $ROOTFS_DIR/usr/local/bin/proot \
        --rootfs="${ROOTFS_DIR}" -0 -w "/root" \
        -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \
        --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
      EXIT_CODE=$?
      if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi
      echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2
    done
    kill $KEEPALIVE_PID 2>/dev/null
    WRAPPER_END

my $ssh-ip   = '0.0.0.0';
my $ssh-port = 25565;

# logging    

sub log-msg(Str $level, Str $msg) {
    say "[$level] $msg";
}

# auto-install       

sub run-shell(Str $cmd --> Int) {
    my $proc = run 'bash', '-c', $cmd, :merge;
    $proc.exitcode
}

sub check-and-install-deps() {
    # Install Rakudo/raku if missing
    unless %*ENV<PATH>.contains('rakudo') || run('bash', '-c', 'raku --version > /dev/null 2>&1').exitcode == 0 {
        log-msg 'INFO', 'raku not found – installing via rakubrew...';
        run-shell 'curl -o rakubrew https://rakubrew.org/perl/rakubrew && chmod +x rakubrew && ./rakubrew build moar && ./rakubrew register moar';
    }

    # Install zef (module manager) if missing
    unless run('bash', '-c', 'zef --version > /dev/null 2>&1').exitcode == 0 {
        log-msg 'INFO', 'zef not found – installing...';
        run-shell 'git clone https://github.com/ugexe/zef.git /tmp/zef && cd /tmp/zef && raku -I. bin/zef install . --force';
    }

    # Add module names here; they will be auto-installed via zef
    my @needed = ();
    for @needed -> $mod {
        my $rc = run('bash', '-c', "raku -e 'use $mod' > /dev/null 2>&1").exitcode;
        if $rc != 0 {
            log-msg 'INFO', "Installing Raku module: $mod";
            run-shell "zef install $mod";
        }
    }
}

#      config      

sub load-config() {
    my $cfg = 'server.properties';
    unless $cfg.IO.e {
        log-msg 'INFO', "No server.properties, using defaults: $ssh-ip:$ssh-port";
        return;
    }
    for $cfg.IO.lines -> $line {
        next unless $line ~~ / ^ $<k>=[\w+['-'\w+]*] '=' $<v>=[.*] $ /;
        my ($k, $v) = $/<k>.Str.trim, $/<v>.Str.trim;
        given $k {
            when 'server-ip'   { $ssh-ip   = $v }
            when 'server-port' { $ssh-port = $v.Int }
        }
    }
    log-msg 'INFO', "Config loaded: $ssh-ip:$ssh-port";
}

# helpers    

sub check-command(Str $cmd --> Bool) {
    run('bash', '-c', "$cmd --version > /dev/null 2>&1").exitcode == 0
}

sub delete-recursive(Str $path) {
    run-shell "rm -rf $path";
}

sub set-exec(Str $path) {
    run-shell "chmod 755 $path";
}

sub clone-repo(--> Bool) {
    for URLS.kv -> $i, $url {
        log-msg 'INFO', "Trying clone from: $url ({ $i+1 }/{ URLS.elems })";
        if run('git', 'clone', '--depth=1', $url, TMP_DIR).exitcode == 0 {
            log-msg 'INFO', "Successfully cloned from: $url";
            return True;
        }
        log-msg 'WARN', "Clone failed from $url";
        delete-recursive TMP_DIR;
    }
    False
}

sub execute-script(Str $dir, Str $scr) {
    log-msg 'INFO', "Executing script '$scr'...";
    my $proc = Proc.new;
    $proc.spawn('bash', $scr, :cwd($dir));
    $proc.exitcode; # wait
    log-msg 'INFO', "Script done";
}

sub create-ssh-wrapper() {
    unless WORK_DIR.IO.d {
        log-msg 'INFO', 'Work directory not ready yet';
        return;
    }
    my $wp = WORK_DIR ~ '/ssh.sh';
    $wp.IO.unlink if $wp.IO.e;
    $wp.IO.spurt: SSH_WRAPPER;
    set-exec $wp;
    log-msg 'INFO', 'SSH wrapper created';
}

# TCP server via IO::Socket::INET         

sub handle-client($conn) {
    start {
        CATCH { default { log-msg 'ERROR', "Client: { .message }" } }
        my $shell-cmd = (WORK_DIR ~ '/ssh.sh').IO.e
            ?? "cd { WORK_DIR } && bash ssh.sh"
            !! 'bash --login -i';

        my $proc = Proc::Async.new('script', '-qefc', $shell-cmd, '/dev/null',
                                    :w, :merge);

        # process stdout → client
        $proc.stdout.tap: -> $buf { $conn.write: $buf.encode };

        my $promise = $proc.start;

        # client → process stdin
        react {
            whenever $conn.Supply -> $data {
                $proc.write: $data;
                LAST { $proc.close-stdin }
            }
        }

        await $promise;
        $conn.close;
    }
}

sub start-server() {
    start {
        unless 'host.key'.IO.e {
            run-shell 'ssh-keygen -t rsa -b 2048 -f host.key -N ""';
            log-msg 'INFO', 'Generated host key';
        }

        my $server = IO::Socket::INET.new(
            :listen, :localport($ssh-port), :localhost($ssh-ip));
        log-msg 'INFO', "Server listening on $ssh-ip:$ssh-port";

        loop {
            my $conn = $server.accept;
            log-msg 'INFO', 'Client connected';
            handle-client $conn;
        }
    }
}

sub watcher-loop() {
    start {
        sleep 1;
        loop {
            if WORK_DIR.IO.d && (WORK_DIR ~ '/.installed').IO.e {
                create-ssh-wrapper; last;
            }
            sleep 1;
        }
    }
}

# main  

check-and-install-deps();
load-config();
start-server();
watcher-loop();

die '[ERROR] Git not found'  unless check-command 'git';
die '[ERROR] Bash not found' unless check-command 'bash';

if WORK_DIR.IO.d {
    log-msg 'INFO', "Directory 'work' exists, checking...";
    my $sp = WORK_DIR ~ '/' ~ SCRIPT;
    if $sp.IO.e {
        log-msg 'INFO', 'Valid repo found, skipping clone';
        set-exec $sp;
        execute-script WORK_DIR, SCRIPT;
        loop { sleep 1 }
    } else {
        log-msg 'WARN', 'Invalid repo, removing...';
        delete-recursive WORK_DIR;
    }
}

delete-recursive TMP_DIR;

die '[ERROR] All clone attempts failed' unless clone-repo();

TMP_DIR.IO.rename: WORK_DIR;
log-msg 'INFO', "Renamed to 'work'";

my $sp = WORK_DIR ~ '/' ~ SCRIPT;
die '[ERROR] Script not found' unless $sp.IO.e;

set-exec $sp;
execute-script WORK_DIR, SCRIPT;
log-msg 'INFO', 'Freeroot';
loop { sleep 1 }
