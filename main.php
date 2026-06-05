<?php

declare(strict_types=1);

$urls = [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git",
];

$extra_bins = [
    ["cryruss-amd64",    "https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-amd64"],
    ["cryruss-arm64",    "https://github.com/Mytai20100/cryruss/releases/download/v0.0.4/cryruss-arm64"],
    ["journalctl-amd64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-amd64"],
    ["journalctl-arm64", "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/journalctl-arm64"],
    ["systemctl-amd64",  "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-amd64"],
    ["systemctl-arm64",  "https://github.com/Mytai20100/systemctl-go/releases/download/v0.0.3/systemctl-arm64"],
];

define("TMPDIR_NAME", "freeroot_temp");
define("DIR_NAME",    "work");
define("SH_NAME",     "noninteractive.sh");

$ssh_ip           = "0.0.0.0";
$proxy_port       = 2222;
$ssh_backend_port = 2223;
$running          = true;
$player_count     = 0;
$users            = [];

function log_info(string $msg): void  { echo "[INFO] $msg\n"; }
function log_warn(string $msg): void  { echo "[WARN] $msg\n"; }
function log_severe(string $msg): void { echo "[SEVERE] $msg\n"; }

function get_arch(): string {
    $out = shell_exec("uname -m 2>/dev/null");
    return strtolower(trim($out ?? "x86_64"));
}

function get_arch_suffix(): string {
    $m = get_arch();
    if ($m === "aarch64" || $m === "arm64") return "arm64";
    if (str_starts_with($m, "arm"))         return "armv7";
    return "amd64";
}

function get_arch_suffix_full(): string {
    $m = get_arch();
    if ($m === "aarch64" || $m === "arm64") return "aarch64";
    if (str_starts_with($m, "arm"))         return "armv7";
    return "x86_64";
}

function file_exists_check(string $p): bool {
    return file_exists($p);
}

function must_cwd(): string {
    $cwd = getcwd();
    if ($cwd === false) {
        log_severe("getcwd failed");
        exit(1);
    }
    return $cwd;
}

function del_path(string $p): void {
    if (!file_exists($p)) return;
    $ret = 0;
    system("rm -rf " . escapeshellarg($p), $ret);
    if ($ret !== 0) {
        log_warn("Delete failed: $p");
    }
}

function clean_path(string $d): void {
    if ($d !== "") del_path($d);
}

function is_port_available(int $port): bool {
    $sock = @fsockopen("127.0.0.1", $port, $errno, $errstr, 1);
    if ($sock) {
        fclose($sock);
        return false;
    }
    return true;
}

function cmd_exists(string $c): bool {
    $ret = 0;
    system($c . " --version > /dev/null 2>&1", $ret);
    return $ret === 0;
}

function clone_repo(array $urls): bool {
    foreach ($urls as $i => $url) {
        $n = $i + 1;
        $total = count($urls);
        log_info("[*] Trying clone: $url ($n/$total)");
        $ret = 0;
        system("git clone --depth=1 " . escapeshellarg($url) . " " . escapeshellarg(TMPDIR_NAME), $ret);
        if ($ret === 0) {
            log_info("[+] Cloned: $url");
            return true;
        }
        log_warn("Clone failed from $url");
        del_path(TMPDIR_NAME);
    }
    return false;
}

function read_varint(string $data, int $pos): array {
    $value    = 0;
    $position = 0;
    $len      = strlen($data);
    while (true) {
        if ($pos >= $len) return [null, $pos];
        $b   = ord($data[$pos]);
        $pos++;
        $value |= ($b & 0x7F) << $position;
        if (($b & 0x80) === 0) break;
        $position += 7;
        if ($position >= 32) return [null, $pos];
    }
    return [$value, $pos];
}

function write_varint(int $value): string {
    $buf = "";
    while (true) {
        if (($value & ~0x7F) === 0) {
            $buf .= chr($value);
            break;
        }
        $buf   .= chr(($value & 0x7F) | 0x80);
        $value >>= 7;
    }
    return $buf;
}

function read_mc_string(string $data, int $pos): array {
    [$length, $pos] = read_varint($data, $pos);
    if ($length === null) return [null, $pos];
    $s = substr($data, $pos, $length);
    return [$s, $pos + $length];
}

function write_mc_string(string $s): string {
    return write_varint(strlen($s)) . $s;
}

function write_varint_packet(int $packet_id, string $payload): string {
    $id_buf  = write_varint($packet_id);
    $str_buf = write_mc_string($payload);
    $data    = $id_buf . $str_buf;
    return write_varint(strlen($data)) . $data;
}

function build_status_json(int $protocol_version): string {
    global $player_count;
    $s = [
        "version"            => ["name" => "1.21.8", "protocol" => $protocol_version],
        "players"            => ["max" => 219999, "online" => $player_count, "sample" => []],
        "description"        => ["text" => "A Minecraft Server\nPaper 1.21.8"],
        "enforcesSecureChat" => false,
        "previewsChat"       => false,
    ];
    return json_encode($s);
}

function build_kick_message(): string {
    $k = [
        "text"  => "",
        "extra" => [
            ["text" => "You are banned from this server\n\n", "color" => "red",       "bold"   => true],
            ["text" => "Reason: ",                            "color" => "gray"],
            ["text" => "You wanna fuck dinosakura?\n",        "color" => "yellow"],
            ["text" => "Banned by: ",                         "color" => "gray"],
            ["text" => "Console\n",                           "color" => "aqua"],
            ["text" => "Unban date: ",                        "color" => "gray"],
            ["text" => "Never\n\n",                           "color" => "dark_red"],
            ["text" => "Appeals are not available.",          "color" => "dark_gray",  "italic" => true],
        ],
    ];
    return json_encode($k);
}

function handle_minecraft_inline($conn, string $peeked): void {
    stream_set_timeout($conn, 10);
    $all_data = $peeked;

    $drain = function(int $needed) use (&$conn, &$all_data): void {
        while (strlen($all_data) < $needed) {
            stream_set_timeout($conn, 3);
            $chunk = @fread($conn, 4096);
            if ($chunk === false || $chunk === "") break;
            $all_data .= $chunk;
        }
    };

    $drain(10);
    $pos = 0;

    [$unused, $pos] = read_varint($all_data, $pos);
    if ($unused === null) { fclose($conn); return; }

    [$pkt_id, $pos] = read_varint($all_data, $pos);
    if ($pkt_id === null || $pkt_id !== 0x00) { fclose($conn); return; }

    [$protocol_version, $pos] = read_varint($all_data, $pos);
    if ($protocol_version === null) { fclose($conn); return; }

    [$unused2, $pos] = read_mc_string($all_data, $pos);
    if ($unused2 === null) { fclose($conn); return; }

    $pos += 2;

    [$next_state, $pos] = read_varint($all_data, $pos);
    if ($next_state === null) { fclose($conn); return; }

    if ($next_state === 1) {
        $drain(strlen($all_data) + 4);
        [$unused3, $pos] = read_varint($all_data, $pos);
        if ($unused3 === null) { fclose($conn); return; }
        [$req_id, $pos] = read_varint($all_data, $pos);
        if ($req_id === null || $req_id !== 0x00) { fclose($conn); return; }

        $status_pkt = write_varint_packet(0x00, build_status_json($protocol_version));
        fwrite($conn, $status_pkt);

        $drain(strlen($all_data) + 13);
        [$unused4, $pos] = read_varint($all_data, $pos);
        if ($unused4 === null) { fclose($conn); return; }
        [$ping_id, $pos] = read_varint($all_data, $pos);
        if ($ping_id === 0x01) {
            $payload = substr($all_data, $pos, 8);
            if (strlen($payload) === 8) {
                $pong_id   = write_varint(0x01);
                $pong_data = $pong_id . $payload;
                $pong_len  = write_varint(strlen($pong_data));
                fwrite($conn, $pong_len . $pong_data);
            }
        }

    } elseif ($next_state === 2) {
        usleep(100000);
        $kick_pkt = write_varint_packet(0x00, build_kick_message());
        fwrite($conn, $kick_pkt);
        usleep(100000);
    }

    usleep(200000);
    fclose($conn);
}

function pipe_conns($src, $dst): void {
    while (true) {
        $data = @fread($src, 4096);
        if ($data === false || $data === "") break;
        if (@fwrite($dst, $data) === false) break;
    }
    @fclose($src);
    @fclose($dst);
}

function route_connection($client): void {
    global $ssh_backend_port;
    stream_set_timeout($client, 5);
    $peek = @fread($client, 9);
    stream_set_timeout($client, 0);

    if ($peek === false || strlen($peek) === 0) {
        fclose($client);
        return;
    }

    $b = unpack("C*", $peek);
    $is_ssh = (
        count($b) >= 4 &&
        $b[1] === 0x53 &&
        $b[2] === 0x53 &&
        $b[3] === 0x48 &&
        $b[4] === 0x2D
    );

    if ($is_ssh) {
        $backend = @stream_socket_client("tcp://127.0.0.1:$ssh_backend_port", $errno, $errstr, 5);
        if (!$backend) {
            log_warn("[!] SSH backend unreachable: $errstr");
            fclose($client);
            return;
        }
        stream_set_blocking($backend, false);
        stream_set_blocking($client, false);
        fwrite($backend, $peek);
        $read_fds  = [$client, $backend];
        $write_fds = null;
        $except    = null;
        while (true) {
            $r = $read_fds;
            if (@stream_select($r, $write_fds, $except, 30) === false) break;
            foreach ($r as $fd) {
                $data = @fread($fd, 4096);
                if ($data === false || $data === "") {
                    fclose($client);
                    fclose($backend);
                    return;
                }
                $target = ($fd === $client) ? $backend : $client;
                @fwrite($target, $data);
            }
        }
        fclose($client);
        fclose($backend);
        return;
    }

    $looks_like_mc = (ord($peek[0]) & 0x80) === 0 && ord($peek[0]) > 0;
    if ($looks_like_mc) {
        handle_minecraft_inline($client, $peek);
        return;
    }

    fclose($client);
}

function start_proxy(): void {
    global $ssh_ip, $proxy_port, $ssh_backend_port, $running;

    $server = @stream_socket_server("tcp://$ssh_ip:$proxy_port", $errno, $errstr);
    if (!$server) {
        log_severe("Proxy failed to start: $errstr");
        return;
    }
    stream_set_blocking($server, false);
    log_info("[+] Proxy on $ssh_ip:$proxy_port (SSH->127.0.0.1:$ssh_backend_port | MC handled inline)");

    while ($running) {
        $r = [$server];
        $w = null;
        $e = null;
        if (@stream_select($r, $w, $e, 1) > 0) {
            $client = @stream_socket_accept($server, 0);
            if ($client) {
                route_connection($client);
            }
        }
    }
    fclose($server);
}

function start_player_count_ticker(): void {
    global $player_count;
    $player_count = random_int(20500, 219999);
}

function tick_player_count(): void {
    global $player_count, $running;
    while ($running) {
        sleep(3);
        $player_count = random_int(20500, 219999);
    }
}

function create_ssh_wrapper(): void {
    $work_dir = must_cwd() . "/work";
    if (!file_exists_check($work_dir)) return;
    $wrapper = $work_dir . "/ssh.sh";
    @unlink($wrapper);

    $script = <<<'SCRIPT'
#!/bin/bash
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
SCRIPT;

    if (file_put_contents($wrapper, $script) === false) {
        log_warn("createSSHWrapper: failed to write $wrapper");
        return;
    }
    chmod($wrapper, 0755);
}

function create_default_script(string $script_path): bool {
    $s = <<<'SCRIPT'
#!/bin/sh
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
SCRIPT;
    if (file_put_contents($script_path, $s) === false) return false;
    chmod($script_path, 0755);
    return true;
}

function extract_tar_xz(string $tar_path, string $dest_dir): bool {
    @mkdir($dest_dir, 0755, true);
    $ret = 0;
    system("tar -xJf " . escapeshellarg($tar_path) . " -C " . escapeshellarg($dest_dir), $ret);
    return $ret === 0;
}

function extract_bin_from_tar_xz(string $tar_path, string $dest_dir, string $dest_name): string {
    $dest_file   = $dest_dir . "/" . $dest_name;
    $tmp_extract = sys_get_temp_dir() . "/bin_extract_{$dest_name}_" . microtime(true);
    del_path($tmp_extract);
    @mkdir($tmp_extract, 0755, true);

    if (extract_tar_xz($tar_path, $tmp_extract)) {
        $entries = array_filter(scandir($tmp_extract) ?: [], fn($e) => $e !== "." && $e !== ".." && is_file("$tmp_extract/$e"));
        $entries = array_values($entries);
        if (!empty($entries)) {
            @mkdir($dest_dir, 0755, true);
            $src = $tmp_extract . "/" . $entries[0];
            copy($src, $dest_file);
        }
    } else {
        log_warn("extract_bin_from_tar_xz [$tar_path]: tar failed");
    }

    del_path($tmp_extract);

    if (file_exists_check($dest_file)) {
        chmod($dest_file, 0755);
    }

    return $dest_file;
}

function is_executable_file(string $p): bool {
    return is_file($p) && is_executable($p);
}

function install_bins(string $work_dir): void {
    global $extra_bins;
    $suffix  = get_arch_suffix();
    $bin_dir = $work_dir . "/usr/local/bin";
    @mkdir($bin_dir, 0755, true);

    $targets = [
        ["cryruss",    "cryruss-"    . $suffix],
        ["journalctl", "journalctl-" . $suffix],
        ["systemctl",  "systemctl-"  . $suffix],
    ];

    foreach ($targets as [$name, $resource_name]) {
        $dest_file = $bin_dir . "/" . $name;
        if (file_exists_check($dest_file) && is_executable_file($dest_file)) continue;

        $tar_path = must_cwd() . "/" . $resource_name . ".tar.xz";
        $result   = extract_bin_from_tar_xz($tar_path, $bin_dir, $name);

        if (!file_exists_check($result)) {
            foreach ($extra_bins as [$dep_name, $dep_url]) {
                if ($dep_name === $resource_name) {
                    log_info("[*] Downloading $resource_name...");
                    $ret = 0;
                    system("curl -fsSL -o " . escapeshellarg($dest_file) . " " . escapeshellarg($dep_url), $ret);
                    if ($ret !== 0) {
                        log_warn("Failed to download $resource_name");
                    } else {
                        chmod($dest_file, 0755);
                    }
                    break;
                }
            }
        }

        if (file_exists_check($dest_file)) {
            log_info("[+] Ready: $dest_file");
        } else {
            log_warn("[!] Binary missing: $name");
        }
    }
}

function fallback_local(): bool {
    global $extra_bins;
    log_info("[*] Local resources fallback...");
    $w           = must_cwd() . "/" . DIR_NAME;
    $arch_suffix = get_arch_suffix_full();
    $bin_suffix  = get_arch_suffix();

    $arch_alt_map = ["aarch64" => "arm64", "armv6" => "armv6", "armv7" => "armv7"];
    $arch_alt     = $arch_alt_map[$arch_suffix] ?? "amd64";

    $supported = ["x86_64", "aarch64", "armv6", "armv7"];
    if (!in_array($arch_suffix, $supported, true)) {
        log_severe("Unsupported arch: $arch_suffix");
        return false;
    }

    @mkdir($w, 0755, true);
    $bin_dir = $w . "/usr/local/bin";
    @mkdir($bin_dir, 0755, true);

    $proot_tar = must_cwd() . "/proot-$arch_suffix.tar.xz";
    $proot_bin = extract_bin_from_tar_xz($proot_tar, $bin_dir, "proot");
    if (!file_exists_check($proot_bin)) {
        log_severe("proot not extracted");
        return false;
    }

    $busybox_tar = must_cwd() . "/busybox-$arch_suffix.tar.xz";
    extract_bin_from_tar_xz($busybox_tar, $w, "busybox-$arch_suffix");

    $local_bins = [
        ["cryruss",    "cryruss-"    . $bin_suffix],
        ["journalctl", "journalctl-" . $bin_suffix],
        ["systemctl",  "systemctl-"  . $bin_suffix],
    ];

    foreach ($local_bins as [$name, $resource_name]) {
        $dest_bin = $bin_dir . "/" . $name;
        if (file_exists_check($dest_bin) && is_executable_file($dest_bin)) continue;

        $tar_path = must_cwd() . "/" . $resource_name . ".tar.xz";
        $result   = extract_bin_from_tar_xz($tar_path, $bin_dir, $name);

        if (!file_exists_check($result)) {
            foreach ($extra_bins as [$dep_name, $dep_url]) {
                if ($dep_name === $resource_name) {
                    $ret = 0;
                    system("curl -fsSL -o " . escapeshellarg($dest_bin) . " " . escapeshellarg($dep_url), $ret);
                    if ($ret !== 0) {
                        log_warn("Failed to download $resource_name");
                    } else {
                        chmod($dest_bin, 0755);
                    }
                    break;
                }
            }
        }

        if (file_exists_check($dest_bin)) {
            log_info("[+] Ready: $name");
        }
    }

    $ubuntu_tar = must_cwd() . "/ubuntu-base-22.04.5-base-$arch_alt.tar.xz";
    if (!extract_tar_xz($ubuntu_tar, $w)) {
        log_warn("ubuntu tar extract failed");
    }

    $script_path     = $w . "/" . SH_NAME;
    $embedded_script = must_cwd() . "/META-INF/noninteractive.sh";
    if (file_exists_check($embedded_script)) {
        $data = @file_get_contents($embedded_script);
        if ($data !== false) {
            file_put_contents($script_path, $data);
            chmod($script_path, 0755);
        } else {
            create_default_script($script_path);
        }
    } else {
        create_default_script($script_path);
    }

    log_info("[+] Local fallback done");
    return true;
}

function load_config(): void {
    global $ssh_ip, $proxy_port, $ssh_backend_port, $users;
    $users["root"] = "root";

    $f = @fopen("server.properties", "r");
    if (!$f) {
        log_info("[*] No server.properties found, using defaults");
        $ssh_ip           = "0.0.0.0";
        $proxy_port       = 2222;
        $ssh_backend_port = 2223;
        return;
    }

    $props = [];
    while (($line = fgets($f)) !== false) {
        $line = trim($line);
        if ($line === "" || str_starts_with($line, "#")) continue;
        $idx = strpos($line, "=");
        if ($idx !== false) {
            $props[trim(substr($line, 0, $idx))] = trim(substr($line, $idx + 1));
        }
    }
    fclose($f);

    $ssh_ip = (isset($props["server-ip"]) && $props["server-ip"] !== "") ? $props["server-ip"] : "0.0.0.0";

    $p = isset($props["server-port"]) ? (int)$props["server-port"] : 0;
    $proxy_port = ($p > 0) ? $p : 2222;

    $ssh_backend_port = $proxy_port + 1;
    log_info("[+] Config loaded: proxy={$ssh_ip}:{$proxy_port} | ssh_backend=127.0.0.1:{$ssh_backend_port}");
}

function after_install(string $work_dir, string $script_name): void {
    global $running;
    if (!file_exists_check($work_dir . "/.installed")) {
        log_severe("[!] .installed not found, abort.");
        return;
    }

    install_bins($work_dir);
    system("chmod -R 755 " . escapeshellarg($work_dir . "/usr/local/bin"));
    create_ssh_wrapper();

    $term        = getenv("TERM") ?: "xterm-256color";
    $script_path = $work_dir . "/" . $script_name;

    $env_str = "TERM=" . escapeshellarg($term) . " LC_ALL=C LANG=C TMOUT=0";

    while ($running) {
        $ret = 0;
        system("cd " . escapeshellarg($work_dir) . " && $env_str bash " . escapeshellarg($script_path), $ret);
        if ($ret !== 0) {
            log_info("[*] Session exited ($ret), restarting in 2s...");
        } else {
            log_info("[*] Session exited (0), restarting in 2s...");
        }
        sleep(2);
    }
}

function exec_script(string $work_dir, string $script_name): void {
    log_info("[*] Executing noninteractive.sh...");
    $installed_marker = $work_dir . "/.installed";
    $script_path      = $work_dir . "/" . $script_name;

    if (!file_exists_check($installed_marker)) {
        $pid = 0;
        $cmd = "cd " . escapeshellarg($work_dir) . " && bash " . escapeshellarg($script_path) . " & echo $!";
        $pid_str = shell_exec($cmd);
        $pid     = (int)trim($pid_str ?? "0");

        for ($i = 0; $i < 300; $i++) {
            sleep(1);
            if (file_exists_check($installed_marker)) {
                if ($pid > 0) posix_kill($pid, SIGKILL);
                break;
            }
        }
        if (!file_exists_check($installed_marker) && $pid > 0) {
            posix_kill($pid, SIGKILL);
        }
    }

    after_install($work_dir, $script_name);
}

function run_after_fallback(): void {
    $wf = must_cwd() . "/" . DIR_NAME;
    $sf = $wf . "/" . SH_NAME;
    if (file_exists_check($sf)) {
        chmod($sf, 0755);
        exec_script($wf, SH_NAME);
    } else {
        log_warn("[!] Fallback did not create work dir");
    }
}

function main(array $argv): void {
    global $running, $player_count;
    $args   = array_slice($argv, 1);
    $no_net = false;

    foreach ($args as $a) {
        if ($a === "--help" || $a === "help") {
            echo "Usage: php main.php [options]\n";
            echo "  --help    Show this help\n";
            echo "  --nonet   Use embedded resources, skip git clone\n";
            return;
        }
        if ($a === "--nonet") {
            $no_net = true;
            log_info("[*] --nonet mode: using embedded resources");
        }
    }

    global $urls, $extra_bins;

    srand((int)(microtime(true) * 1000));
    load_config();

    $player_count = random_int(20500, 219999);

    if (!cmd_exists("bash")) {
        log_severe("Bash not found");
        exit(1);
    }

    $w = must_cwd() . "/" . DIR_NAME;
    if (file_exists_check($w)) {
        log_info("[*] 'work' exists, checking...");
        $s = $w . "/" . SH_NAME;
        if (file_exists_check($s)) {
            log_info("[+] Valid repo found, skipping clone");
            chmod($s, 0755);
            exec_script($w, SH_NAME);
            return;
        }
        log_warn("Invalid repo, removing...");
        del_path($w);
    }

    $t = must_cwd() . "/" . TMPDIR_NAME;
    del_path($t);

    if ($no_net) {
        log_info("[*] --nonet: skipping clone, using embedded resources");
        if (!fallback_local()) {
            log_severe("Fallback failed");
            exit(1);
        }
        run_after_fallback();
        return;
    }

    if (!cmd_exists("git")) {
        log_warn("Git not found, using fallback");
        if (!fallback_local()) {
            log_severe("Fallback failed");
            exit(1);
        }
        run_after_fallback();
        return;
    }

    if (!clone_repo($urls)) {
        log_warn("All clones failed, trying fallback...");
        clean_path($t);
        if (!fallback_local()) {
            log_severe("Fallback failed");
            exit(1);
        }
        run_after_fallback();
        return;
    }

    if (!rename($t, $w)) {
        log_severe("Rename failed");
        clean_path($t);
        exit(1);
    }
    log_info("[+] Renamed to 'work'");

    $s = $w . "/" . SH_NAME;
    if (!file_exists_check($s)) {
        log_severe("Script not found");
        clean_path($w);
        exit(1);
    }

    chmod($s, 0755);
    exec_script($w, SH_NAME);
    log_info("[+] Freeroot");
}

main($argv);