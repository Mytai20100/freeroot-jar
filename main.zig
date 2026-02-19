// Cooked by mytai | 2026
// Build: zig build-exe main.zig  OR  zig run main.zig

const std = @import("std");
const net = std.net;
const fs  = std.fs;
const mem = std.mem;
const os  = std.os;

const URLS = [_][]const u8{
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git",
};

const TMP_DIR  = "freeroot_temp";
const WORK_DIR = "work";
const SCRIPT   = "noninteractive.sh";

const SSH_WRAPPER =
    \\#!/bin/bash
    \\export LC_ALL=C
    \\export LANG=C
    \\ROOTFS_DIR=$(pwd)
    \\export PATH=$PATH:~/.local/usr/bin
    \\
    \\if [ ! -e $ROOTFS_DIR/.installed ]; then
    \\    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    \\    exit 1
    \\fi
    \\
    \\G="\033[0;32m"; Y="\033[0;33m"; R="\033[0;31m"
    \\C="\033[0;36m"; W="\033[0;37m"; X="\033[0m"
    \\OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'"' -f2||echo "Unknown")
    \\CPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ *//')
    \\ARCH_D=$(uname -m)
    \\CPU_U=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/{print $2+$4}' || echo 0)
    \\TRAM=$(free -h --si 2>/dev/null | awk '/^Mem:/{print $2}' || echo 'N/A')
    \\URAM=$(free -h --si 2>/dev/null | awk '/^Mem:/{print $3}' || echo 'N/A')
    \\RAM_PERCENT=$(free 2>/dev/null | awk '/^Mem:/{printf "%.1f", $3/$2 * 100}' || echo 0)
    \\DISK=$(df -h /|awk 'NR==2{print $2}')
    \\UDISK=$(df -h /|awk 'NR==2{print $3}')
    \\DISK_PERCENT=$(df -h /|awk 'NR==2{print $5}'|sed 's/%//')
    \\IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||curl -s --max-time 2 icanhazip.com 2>/dev/null||hostname -I 2>/dev/null|awk '{print $1}'||echo "N/A")
    \\clear
    \\echo -e "${C}OS:${X}   $OS"
    \\echo -e "${C}CPU:${X}  $CPU [$ARCH_D]  Usage: ${CPU_U}%"
    \\echo -e "${G}RAM:${X}  ${URAM} / ${TRAM} (${RAM_PERCENT}%)"
    \\echo -e "${Y}Disk:${X} ${UDISK} / ${DISK} (${DISK_PERCENT}%)"
    \\echo -e "${C}IP:${X}   $IP"
    \\echo -e "${W}___________________________________________________${X}"
    \\echo -e "           ${C}-----> Mission Completed ! <-----${X}"
    \\echo -e "${W}___________________________________________________${X}"
    \\echo ""
    \\
    \\echo 'furryisbest' > $ROOTFS_DIR/etc/hostname
    \\cat > $ROOTFS_DIR/etc/hosts << 'HOSTS_EOF'
    \\127.0.0.1   localhost
    \\127.0.1.1   furryisbest
    \\::1         localhost ip6-localhost ip6-loopback
    \\ff02::1     ip6-allnodes
    \\ff02::2     ip6-allrouters
    \\HOSTS_EOF
    \\
    \\cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'
    \\export HOSTNAME=furryisbest
    \\export PS1='root@furryisbest:\w\$ '
    \\export LC_ALL=C; export LANG=C
    \\export TMOUT=0; unset TMOUT
    \\set +o history 2>/dev/null; PROMPT_COMMAND=''
    \\alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'
    \\BASHRC_EOF
    \\
    \\( while true; do sleep 15; echo -ne '\0' 2>/dev/null || true; done ) &
    \\KEEPALIVE_PID=$!
    \\trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM
    \\
    \\while true; do
    \\  $ROOTFS_DIR/usr/local/bin/proot \
    \\    --rootfs="${ROOTFS_DIR}" -0 -w "/root" \
    \\    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \
    \\    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
    \\  EXIT_CODE=$?
    \\  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi
    \\  echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2
    \\done
    \\kill $KEEPALIVE_PID 2>/dev/null
;

var g_ssh_ip:   []const u8 = "0.0.0.0";
var g_ssh_port: u16        = 25565;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

fn alloc() std.mem.Allocator { return gpa.allocator(); }

// logging

fn logMsg(level: []const u8, msg: []const u8) void {
    std.debug.print("[{s}] {s}\n", .{ level, msg });
}

// auto-install 

fn checkAndInstallDeps() void {
    // Check if zig is new enough; auto-install zig if missing via snap/apt.
    var res = std.process.Child.run(.{
        .allocator = alloc(),
        .argv      = &[_][]const u8{ "zig", "version" },
    }) catch {
        logMsg("INFO", "zig not in PATH – trying to install via snap...");
        _ = std.process.Child.run(.{
            .allocator = alloc(),
            .argv      = &[_][]const u8{ "bash", "-c",
                "snap install zig --classic --beta 2>/dev/null || " ++
                "apt-get install -y zig 2>/dev/null || true" },
        }) catch {};
        return;
    };
    _ = res;

    // If a build.zig.zon exists, run `zig fetch` to pull declared dependencies.
    const cwd = fs.cwd();
    if (cwd.access("build.zig.zon", .{}) catch null != null) {
        logMsg("INFO", "Running zig fetch to resolve build.zig.zon dependencies...");
        _ = std.process.Child.run(.{
            .allocator = alloc(),
            .argv      = &[_][]const u8{ "zig", "fetch" },
        }) catch {};
    }
}

// config

fn loadConfig() void {
    const cfg = fs.cwd().readFileAlloc(alloc(), "server.properties", 1 << 20) catch {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "No server.properties, using defaults: {s}:{d}",
            .{ g_ssh_ip, g_ssh_port }) catch "";
        logMsg("INFO", s);
        return;
    };
    defer alloc().free(cfg);

    var lines = mem.split(u8, cfg, "\n");
    while (lines.next()) |line| {
        const idx = mem.indexOf(u8, line, "=") orelse continue;
        const k = mem.trim(u8, line[0..idx], " \t\r");
        const v = mem.trim(u8, line[idx+1..], " \t\r");
        if (mem.eql(u8, k, "server-ip")) {
            g_ssh_ip = alloc().dupe(u8, v) catch v;
        } else if (mem.eql(u8, k, "server-port")) {
            g_ssh_port = std.fmt.parseInt(u16, v, 10) catch g_ssh_port;
        }
    }
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "Config loaded: {s}:{d}", .{ g_ssh_ip, g_ssh_port }) catch "";
    logMsg("INFO", s);
}

// helpers

fn checkCommand(cmd: []const u8) bool {
    const r = std.process.Child.run(.{
        .allocator = alloc(),
        .argv      = &[_][]const u8{ cmd, "--version" },
    }) catch return false;
    _ = r;
    return true;
}

fn deleteRecursive(path: []const u8) void {
    fs.cwd().deleteTree(path) catch {};
}

fn setExec(path: []const u8) void {
    fs.cwd().chmod(path, 0o755) catch {};
}

fn cloneRepo() bool {
    var buf: [512]u8 = undefined;
    for (URLS, 0..) |url, i| {
        const msg = std.fmt.bufPrint(&buf, "Trying clone from: {s} ({d}/{d})",
            .{ url, i + 1, URLS.len }) catch "";
        logMsg("INFO", msg);

        const r = std.process.Child.run(.{
            .allocator = alloc(),
            .argv      = &[_][]const u8{ "git", "clone", "--depth=1", url, TMP_DIR },
        }) catch { deleteRecursive(TMP_DIR); continue; };

        if (r.term == .Exited and r.term.Exited == 0) {
            logMsg("INFO", "Successfully cloned");
            return true;
        }
        const w = std.fmt.bufPrint(&buf, "Clone failed from {s}", .{url}) catch "";
        logMsg("WARN", w);
        deleteRecursive(TMP_DIR);
    }
    return false;
}

fn executeScript(directory: []const u8, script: []const u8) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "Executing script '{s}'...", .{script}) catch "";
    logMsg("INFO", msg);

    var child = std.process.Child.init(
        &[_][]const u8{ "bash", script }, alloc());
    child.cwd = directory;
    child.spawn() catch return;
    const term = child.wait() catch return;
    _ = term;
    logMsg("INFO", "Script completed");
}

fn createSSHWrapper() void {
    fs.cwd().access(WORK_DIR, .{}) catch {
        logMsg("INFO", "Work directory not ready yet"); return;
    };
    const wp = WORK_DIR ++ "/ssh.sh";
    fs.cwd().deleteFile(wp) catch {};
    const f = fs.cwd().createFile(wp, .{ .mode = 0o755 }) catch return;
    defer f.close();
    f.writeAll(SSH_WRAPPER) catch {};
    logMsg("INFO", "SSH wrapper created");
}

// TCP server 

fn pumpToProcess(args: struct { stream: std.net.Stream, stdin: fs.File }) void {
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = args.stream.read(&buf) catch break;
        if (n == 0) break;
        args.stdin.writeAll(buf[0..n]) catch break;
    }
}

fn handleClient(stream: std.net.Stream) void {
    defer stream.close();

    const shell_cmd = blk: {
        fs.cwd().access(WORK_DIR ++ "/ssh.sh", .{}) catch
            break :blk "bash --login -i";
        break :blk "cd work && bash ssh.sh";
    };

    var child = std.process.Child.init(
        &[_][]const u8{ "script", "-qefc", shell_cmd, "/dev/null" }, alloc());
    child.stdin_behavior  = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.spawn() catch return;
    defer _ = child.wait() catch {};

    const stdin  = child.stdin.?;
    const stdout = child.stdout.?;

    // pump client → child stdin in a thread
    const pump_args = .{ .stream = stream, .stdin = stdin };
    const t = std.Thread.spawn(.{}, pumpToProcess, .{pump_args}) catch {
        _ = child.kill() catch {};
        return;
    };
    defer t.join();

    // pump child stdout → client
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = stdout.read(&buf) catch break;
        if (n == 0) break;
        stream.writeAll(buf[0..n]) catch break;
    }
    _ = child.kill() catch {};
}

fn serverLoop(_: void) void {
    if (fs.cwd().access("host.key", .{}) catch null == null) {
        _ = std.process.Child.run(.{
            .allocator = alloc(),
            .argv = &[_][]const u8{
                "ssh-keygen", "-t", "rsa", "-b", "2048", "-f", "host.key", "-N", "",
            },
        }) catch {};
        logMsg("INFO", "Generated host key");
    }

    const addr   = net.Address.parseIp(g_ssh_ip, g_ssh_port) catch unreachable;
    var   server = addr.listen(.{ .reuse_address = true }) catch |err| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Listen error: {}", .{err}) catch "";
        logMsg("ERROR", msg);
        return;
    };
    defer server.deinit();

    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "Server listening on {s}:{d}",
        .{ g_ssh_ip, g_ssh_port }) catch "";
    logMsg("INFO", msg);

    while (true) {
        const conn = server.accept() catch continue;
        logMsg("INFO", "Client connected");
        const t = std.Thread.spawn(.{}, handleClient, .{conn.stream}) catch continue;
        t.detach();
    }
}

fn watcherLoop(_: void) void {
    std.time.sleep(1 * std.time.ns_per_s);
    while (true) {
        const ok = blk: {
            fs.cwd().access(WORK_DIR, .{})           catch break :blk false;
            fs.cwd().access(WORK_DIR ++ "/.installed", .{}) catch break :blk false;
            break :blk true;
        };
        if (ok) { createSSHWrapper(); break; }
        std.time.sleep(1 * std.time.ns_per_s);
    }
}

//      main  

pub fn main() !void {
    checkAndInstallDeps();
    loadConfig();

    const srv  = try std.Thread.spawn(.{}, serverLoop,  .{{}});  srv.detach();
    const wtch = try std.Thread.spawn(.{}, watcherLoop, .{{}});  wtch.detach();

    if (!checkCommand("git"))  { logMsg("ERROR", "Git not found");  return; }
    if (!checkCommand("bash")) { logMsg("ERROR", "Bash not found"); return; }

    if (fs.cwd().access(WORK_DIR, .{}) catch null != null) {
        logMsg("INFO", "Directory 'work' exists, checking...");
        if (fs.cwd().access(WORK_DIR ++ "/" ++ SCRIPT, .{}) catch null != null) {
            logMsg("INFO", "Valid repo found, skipping clone");
            setExec(WORK_DIR ++ "/" ++ SCRIPT);
            executeScript(WORK_DIR, SCRIPT);
            while (true) std.time.sleep(1 * std.time.ns_per_s);
        } else {
            logMsg("WARN", "Invalid repo, removing...");
            deleteRecursive(WORK_DIR);
        }
    }

    deleteRecursive(TMP_DIR);

    if (!cloneRepo()) { logMsg("ERROR", "All clone attempts failed"); return; }

    try fs.cwd().rename(TMP_DIR, WORK_DIR);
    logMsg("INFO", "Renamed to 'work'");

    if (fs.cwd().access(WORK_DIR ++ "/" ++ SCRIPT, .{}) catch null == null) {
        logMsg("ERROR", "Script not found");
        deleteRecursive(WORK_DIR); return;
    }

    setExec(WORK_DIR ++ "/" ++ SCRIPT);
    executeScript(WORK_DIR, SCRIPT);
    logMsg("INFO", "Freeroot");
    while (true) std.time.sleep(1 * std.time.ns_per_s);
}
