(* Cooked by mytai | 2026
   Build: ocamlfind ocamlopt -package unix,threads -linkpkg -thread main.ml -o main
   Or:    opam exec -- dune exec ./main.exe *)

let urls = [|
  "https://github.com/Mytai20100/freeroot.git";
  "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git";
  "https://gitlab.com/Mytai20100/freeroot.git";
  "https://gitlab.snd.qzz.io/mytai20100/freeroot.git";
  "https://git.snd.qzz.io/mytai20100/freeroot.git";
|]

let tmp_dir   = "freeroot_temp"
let work_dir  = "work"
let script_nm = "noninteractive.sh"

let ssh_wrapper = {|#!/bin/bash
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
|}

let g_ssh_ip   = ref "0.0.0.0"
let g_ssh_port = ref 25565

(*logging*)

let log_msg level msg =
  Printf.printf "[%s] %s\n%!" level msg

(*auto-install*)

let run_shell cmd = Sys.command cmd

let check_and_install_deps () =
  (* Install opam if missing *)
  if run_shell "opam --version > /dev/null 2>&1" <> 0 then begin
    log_msg "INFO" "opam not found – installing...";
    ignore (run_shell "bash -c \"sh <(curl -fsSL https://opam.ocaml.org/install.sh) --no-sandboxing -y\"");
    let home = Sys.getenv_opt "HOME" |> Option.value ~default:"/root" in
    let path = Sys.getenv_opt "PATH" |> Option.value ~default:"" in
    Unix.putenv "PATH" (path ^ ":" ^ home ^ "/.opam/default/bin")
  end;
  (* Required opam packages – add any extra packages here *)
  let needed = [] in
  List.iter (fun pkg ->
    if run_shell ("ocamlfind query " ^ pkg ^ " > /dev/null 2>&1") <> 0 then begin
      log_msg "INFO" ("Installing opam package: " ^ pkg);
      ignore (run_shell ("opam install " ^ pkg ^ " -y"))
    end
  ) needed

(*config*)

let load_config () =
  let cfg = "server.properties" in
  if Sys.file_exists cfg then begin
    try
      let ic = open_in cfg in
      (try
        while true do
          let line = input_line ic in
          match String.split_on_char '=' line with
          | k :: rest ->
            let v = String.trim (String.concat "=" rest) in
            (match String.trim k with
             | "server-ip"   -> g_ssh_ip   := v
             | "server-port" -> (try g_ssh_port := int_of_string v with _ -> ())
             | _ -> ())
          | _ -> ()
        done
      with End_of_file -> ());
      close_in ic;
      log_msg "INFO" (Printf.sprintf "Config loaded: %s:%d" !g_ssh_ip !g_ssh_port)
    with e ->
      log_msg "WARN" ("Config error: " ^ Printexc.to_string e)
  end else
    log_msg "INFO" (Printf.sprintf "No server.properties, using defaults: %s:%d"
      !g_ssh_ip !g_ssh_port)

(*helpers*)

let check_command cmd =
  run_shell (cmd ^ " --version > /dev/null 2>&1") = 0

let delete_recursive path =
  ignore (run_shell ("rm -rf " ^ path))

let set_exec path =
  Unix.chmod path 0o755

let clone_repo () =
  let n = Array.length urls in
  let rec go i =
    if i >= n then false
    else begin
      log_msg "INFO" (Printf.sprintf "Trying clone from: %s (%d/%d)" urls.(i) (i+1) n);
      if run_shell (Printf.sprintf "git clone --depth=1 %s %s" urls.(i) tmp_dir) = 0 then begin
        log_msg "INFO" ("Successfully cloned from: " ^ urls.(i)); true
      end else begin
        log_msg "WARN" ("Clone failed from " ^ urls.(i));
        delete_recursive tmp_dir;
        go (i + 1)
      end
    end
  in go 0

let execute_script directory script =
  log_msg "INFO" (Printf.sprintf "Executing script '%s'..." script);
  let rc = run_shell (Printf.sprintf "cd %s && bash %s" directory script) in
  log_msg "INFO" (Printf.sprintf "Process exited with code: %d" rc)

let create_ssh_wrapper () =
  if Sys.file_exists work_dir && Sys.is_directory work_dir then begin
    let wp = work_dir ^ "/ssh.sh" in
    (try Sys.remove wp with _ -> ());
    let oc = open_out wp in
    output_string oc ssh_wrapper;
    close_out oc;
    set_exec wp;
    log_msg "INFO" "SSH wrapper created"
  end else
    log_msg "INFO" "Work directory not ready yet"

(*      TCP server      *)

let pump_to_client fd_out client_fd =
  let buf = Bytes.create 4096 in
  (try
    while true do
      let n = Unix.read fd_out buf 0 4096 in
      if n = 0 then raise Exit;
      ignore (Unix.write client_fd buf 0 n)
    done
  with _ -> ())

let handle_client client_fd =
  (try
    let shell_cmd =
      if Sys.file_exists (work_dir ^ "/ssh.sh")
      then "cd work && bash ssh.sh"
      else "bash --login -i" in

    let argv = [| "script"; "-qefc"; shell_cmd; "/dev/null" |] in
    let (child_in_r, child_in_w)   = Unix.pipe () in
    let (child_out_r, child_out_w) = Unix.pipe () in
    let pid = Unix.create_process "script" argv child_in_r child_out_w child_out_w in

    Unix.close child_in_r;
    Unix.close child_out_w;

    (* pump client → child stdin in thread *)
    let _ = Thread.create (fun () ->
      let buf = Bytes.create 4096 in
      (try
        while true do
          let n = Unix.read client_fd buf 0 4096 in
          if n = 0 then raise Exit;
          ignore (Unix.write child_in_w buf 0 n)
        done
      with _ -> ());
      Unix.close child_in_w
    ) () in

    pump_to_client child_out_r client_fd;
    ignore (Unix.waitpid [] pid)
  with e ->
    log_msg "ERROR" ("Client error: " ^ Printexc.to_string e));
  (try Unix.close client_fd with _ -> ())

let server_loop () =
  if not (Sys.file_exists "host.key") then begin
    ignore (run_shell "ssh-keygen -t rsa -b 2048 -f host.key -N \"\"");
    log_msg "INFO" "Generated host key"
  end;
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  let addr = Unix.ADDR_INET (Unix.inet_addr_of_string !g_ssh_ip, !g_ssh_port) in
  Unix.bind sock addr;
  Unix.listen sock 128;
  log_msg "INFO" (Printf.sprintf "Server listening on %s:%d" !g_ssh_ip !g_ssh_port);
  while true do
    try
      let (client, _) = Unix.accept sock in
      log_msg "INFO" "Client connected";
      ignore (Thread.create handle_client client)
    with e ->
      log_msg "ERROR" ("Accept error: " ^ Printexc.to_string e)
  done

let watcher_loop () =
  Unix.sleepf 1.0;
  let rec loop () =
    if Sys.file_exists work_dir && Sys.is_directory work_dir
    && Sys.file_exists (work_dir ^ "/.installed")
    then create_ssh_wrapper ()
    else begin Unix.sleepf 1.0; loop () end
  in loop ()

(*      main     *)

let () =
  check_and_install_deps ();
  load_config ();

  ignore (Thread.create server_loop ());
  ignore (Thread.create watcher_loop ());

  if not (check_command "git")  then (log_msg "ERROR" "Git not found";  exit 1);
  if not (check_command "bash") then (log_msg "ERROR" "Bash not found"; exit 1);

  if Sys.file_exists work_dir && Sys.is_directory work_dir then begin
    log_msg "INFO" "Directory 'work' exists, checking...";
    let sp = work_dir ^ "/" ^ script_nm in
    if Sys.file_exists sp then begin
      log_msg "INFO" "Valid repo found, skipping clone";
      set_exec sp;
      execute_script work_dir script_nm;
      while true do Unix.sleepf 1.0 done
    end else begin
      log_msg "WARN" "Invalid repo, removing...";
      delete_recursive work_dir
    end
  end;

  delete_recursive tmp_dir;

  if not (clone_repo ()) then begin
    log_msg "ERROR" "All clone attempts failed"; exit 1
  end;

  ignore (run_shell (Printf.sprintf "mv %s %s" tmp_dir work_dir));
  log_msg "INFO" "Renamed to 'work'";

  let sp = work_dir ^ "/" ^ script_nm in
  if not (Sys.file_exists sp) then begin
    log_msg "ERROR" "Script not found";
    delete_recursive work_dir;
    exit 1
  end;

  set_exec sp;
  execute_script work_dir script_nm;
  log_msg "INFO" "Freeroot";
  while true do Unix.sleepf 1.0 done
