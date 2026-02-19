// Cooked by mytai | 2026
// Run: dotnet fsi main.fsx  OR  dotnet run (with .fsproj)


open System
open System.IO
open System.Net
open System.Net.Sockets
open System.Diagnostics
open System.Threading

let urls = [|
    "https://github.com/Mytai20100/freeroot.git"
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git"
    "https://gitlab.com/Mytai20100/freeroot.git"
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git"
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
|]

let [<Literal>] TMP_DIR  = "freeroot_temp"
let [<Literal>] WORK_DIR = "work"
let [<Literal>] SCRIPT   = "noninteractive.sh"

let SSH_WRAPPER = """#!/bin/bash
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
"""

let mutable sshIp   = "0.0.0.0"
let mutable sshPort = 25565

// logging  

let logMsg (level: string) (msg: string) =
    printfn "[%s] %s" level msg

// auto-install       

let runShell cmd =
    use p = new Process()
    p.StartInfo <- ProcessStartInfo("bash", sprintf "-c \"%s\"" cmd,
                     UseShellExecute = false, RedirectStandardOutput = false)
    p.Start() |> ignore
    p.WaitForExit()
    p.ExitCode

let checkAndInstallDeps () =
    // Ensure dotnet SDK is available
    if runShell "dotnet --version > /dev/null 2>&1" <> 0 then
        logMsg "INFO" "dotnet not found – installing via Microsoft script..."
        runShell "curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS" |> ignore
        let home = Environment.GetEnvironmentVariable("HOME") |> Option.ofObj |> Option.defaultValue "/root"
        let path = Environment.GetEnvironmentVariable("PATH") |> Option.ofObj |> Option.defaultValue ""
        Environment.SetEnvironmentVariable("PATH", path + ":" + home + "/.dotnet")

    // Add NuGet package names here if you extend imports beyond BCL
    let needed: string list = []
    needed |> List.iter (fun pkg ->
        if runShell (sprintf "dotnet list package 2>/dev/null | grep -q %s" pkg) <> 0 then
            logMsg "INFO" (sprintf "Adding NuGet package: %s" pkg)
            runShell (sprintf "dotnet add package %s" pkg) |> ignore
    )

// config      

let loadConfig () =
    let cfg = "server.properties"
    if File.Exists cfg then
        try
            File.ReadAllLines(cfg)
            |> Array.iter (fun line ->
                let parts = line.Split('=', 2)
                if parts.Length = 2 then
                    let k = parts.[0].Trim()
                    let v = parts.[1].Trim()
                    match k with
                    | "server-ip"   -> sshIp  <- v
                    | "server-port" -> match Int32.TryParse v with
                                       | true, p -> sshPort <- p
                                       | _ -> ()
                    | _ -> ())
            logMsg "INFO" (sprintf "Config loaded: %s:%d" sshIp sshPort)
        with e ->
            logMsg "WARN" (sprintf "Config error: %s" e.Message)
    else
        logMsg "INFO" (sprintf "No server.properties, using defaults: %s:%d" sshIp sshPort)

// helpers    

let checkCommand cmd =
    runShell (sprintf "%s --version > /dev/null 2>&1" cmd) = 0

let deleteRecursive path =
    runShell (sprintf "rm -rf %s" path) |> ignore

let setExec path =
    runShell (sprintf "chmod 755 %s" path) |> ignore

let cloneRepo () =
    urls |> Array.exists (fun url ->
        let i = Array.findIndex ((=) url) urls
        logMsg "INFO" (sprintf "Trying clone from: %s (%d/%d)" url (i+1) urls.Length)
        if runShell (sprintf "git clone --depth=1 %s %s" url TMP_DIR) = 0 then
            logMsg "INFO" (sprintf "Successfully cloned from: %s" url); true
        else
            logMsg "WARN" (sprintf "Clone failed from %s" url)
            deleteRecursive TMP_DIR; false)

let executeScript directory script =
    logMsg "INFO" (sprintf "Executing script '%s'..." script)
    let rc = runShell (sprintf "cd %s && bash %s" directory script)
    logMsg "INFO" (sprintf "Process exited with code: %d" rc)

let createSSHWrapper () =
    if Directory.Exists WORK_DIR then
        let wp = Path.Combine(WORK_DIR, "ssh.sh")
        if File.Exists wp then File.Delete wp
        File.WriteAllText(wp, SSH_WRAPPER)
        setExec wp
        logMsg "INFO" "SSH wrapper created"
    else
        logMsg "INFO" "Work directory not ready yet"

// TCP server     

let handleClient (client: TcpClient) =
    async {
        use client = client
        use stream = client.GetStream()
        try
            let shellCmd =
                if File.Exists(Path.Combine(WORK_DIR, "ssh.sh"))
                then "cd work && bash ssh.sh"
                else "bash --login -i"

            use proc = new Process()
            proc.StartInfo <- ProcessStartInfo(
                "script", sprintf "-qefc \"%s\" /dev/null" shellCmd,
                UseShellExecute        = false,
                RedirectStandardInput  = true,
                RedirectStandardOutput = true,
                RedirectStandardError  = true)
            proc.Start() |> ignore

            // client → process
            let pumpIn = async {
                let buf = Array.zeroCreate<byte> 4096
                try
                    while true do
                        let n = stream.Read(buf, 0, buf.Length)
                        if n = 0 then failwith "done"
                        proc.StandardInput.BaseStream.Write(buf, 0, n)
                        proc.StandardInput.BaseStream.Flush()
                with _ -> ()
            }
            Async.Start pumpIn

            // process → client
            let buf = Array.zeroCreate<byte> 4096
            try
                while true do
                    let n = proc.StandardOutput.BaseStream.Read(buf, 0, buf.Length)
                    if n = 0 then failwith "done"
                    stream.Write(buf, 0, n)
                    stream.Flush()
            with _ -> ()

            proc.WaitForExit()
        with e ->
            logMsg "ERROR" (sprintf "Client error: %s" e.Message)
    }

let startServer () =
    if not (File.Exists "host.key") then
        runShell "ssh-keygen -t rsa -b 2048 -f host.key -N \"\"" |> ignore
        logMsg "INFO" "Generated host key"

    let listener = new TcpListener(IPAddress.Parse(sshIp), sshPort)
    listener.Start()
    logMsg "INFO" (sprintf "Server listening on %s:%d" sshIp sshPort)

    async {
        while true do
            let! client = listener.AcceptTcpClientAsync() |> Async.AwaitTask
            logMsg "INFO" "Client connected"
            Async.Start (handleClient client)
    } |> Async.Start

let watcherLoop () =
    Thread.Sleep 1000
    let rec loop () =
        if Directory.Exists WORK_DIR && File.Exists(Path.Combine(WORK_DIR, ".installed"))
        then createSSHWrapper ()
        else Thread.Sleep 1000; loop ()
    loop ()

// main  

[<EntryPoint>]
let main _ =
    checkAndInstallDeps ()
    loadConfig ()

    startServer ()
    Thread(watcherLoop, IsBackground = true).Start()

    if not (checkCommand "git")  then logMsg "ERROR" "Git not found";  Environment.Exit 1
    if not (checkCommand "bash") then logMsg "ERROR" "Bash not found"; Environment.Exit 1

    if Directory.Exists WORK_DIR then
        logMsg "INFO" "Directory 'work' exists, checking..."
        let sp = Path.Combine(WORK_DIR, SCRIPT)
        if File.Exists sp then
            logMsg "INFO" "Valid repo found, skipping clone"
            setExec sp
            executeScript WORK_DIR SCRIPT
            while true do Thread.Sleep 1000
        else
            logMsg "WARN" "Invalid repo, removing..."
            deleteRecursive WORK_DIR

    deleteRecursive TMP_DIR

    if not (cloneRepo ()) then
        logMsg "ERROR" "All clone attempts failed"
        Environment.Exit 1

    runShell (sprintf "mv %s %s" TMP_DIR WORK_DIR) |> ignore
    logMsg "INFO" "Renamed to 'work'"

    let sp = Path.Combine(WORK_DIR, SCRIPT)
    if not (File.Exists sp) then
        logMsg "ERROR" "Script not found"
        deleteRecursive WORK_DIR
        Environment.Exit 1

    setExec sp
    executeScript WORK_DIR SCRIPT
    logMsg "INFO" "Freeroot"
    while true do Thread.Sleep 1000
    0
