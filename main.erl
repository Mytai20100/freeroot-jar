%% Cooked by mytai | 2026
%% Run: escript main.erl
%% Or:  erlc main.erl && erl -noshell -s main main -s init stop

-module(main).
-export([main/0, main/1]).

-define(URLS, [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
]).

-define(TMP_DIR,  "freeroot_temp").
-define(WORK_DIR, "work").
-define(SCRIPT,   "noninteractive.sh").
-define(SSH_IP,   "0.0.0.0").
-define(SSH_PORT, 25565).

-define(SSH_WRAPPER, "#!/bin/bash\n"
    "export LC_ALL=C\nexport LANG=C\n"
    "ROOTFS_DIR=$(pwd)\nexport PATH=$PATH:~/.local/usr/bin\n\n"
    "if [ ! -e $ROOTFS_DIR/.installed ]; then\n"
    "    echo 'Proot environment not installed yet.'\n    exit 1\nfi\n\n"
    "G=\"\\033[0;32m\"; Y=\"\\033[0;33m\"; C=\"\\033[0;36m\"\n"
    "W=\"\\033[0;37m\"; X=\"\\033[0m\"\n"
    "OS=$(lsb_release -ds 2>/dev/null||echo 'Unknown')\n"
    "CPU=$(lscpu|awk -F: '/Model name:/{print $2}'|sed 's/^ //')\n"
    "ARCH_D=$(uname -m)\n"
    "IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||hostname -I 2>/dev/null|awk '{print $1}'||echo N/A)\n"
    "clear\n"
    "echo -e \"${C}OS:${X}   $OS\"\n"
    "echo -e \"${C}CPU:${X}  $CPU [$ARCH_D]\"\n"
    "echo -e \"${C}IP:${X}   $IP\"\n"
    "echo -e \"${W}___________________________________________________${X}\"\n"
    "echo -e \"           ${C}-----> Mission Completed ! <-----${X}\"\n"
    "echo -e \"${W}___________________________________________________${X}\"\n\n"
    "echo 'furryisbest' > $ROOTFS_DIR/etc/hostname\n"
    "cat > $ROOTFS_DIR/etc/hosts << 'HOSTS_EOF'\n"
    "127.0.0.1   localhost\n127.0.1.1   furryisbest\nHOSTS_EOF\n\n"
    "cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'\n"
    "export HOSTNAME=furryisbest\nexport PS1='root@furryisbest:\\w\\$ '\n"
    "export TMOUT=0; unset TMOUT\nBASHRC_EOF\n\n"
    "( while true; do sleep 15; echo -ne '\\0' 2>/dev/null||true; done ) &\n"
    "KEEPALIVE_PID=$!\ntrap \"kill $KEEPALIVE_PID 2>/dev/null; exit\" EXIT INT TERM\n\n"
    "while true; do\n"
    "  $ROOTFS_DIR/usr/local/bin/proot --rootfs=\"${ROOTFS_DIR}\" -0 -w /root\\\n"
    "    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf\\\n"
    "    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i\n"
    "  EC=$?; [ $EC -eq 0 ]||[ $EC -eq 130 ] && break\n"
    "  echo 'Restarting in 2s...'; sleep 2\ndone\nkill $KEEPALIVE_PID 2>/dev/null\n").

%%  escript entry     

main(_Args) -> main().

main() ->
    check_and_install_deps(),
    {Ip, Port} = load_config(),
    spawn(fun() -> server_loop(Ip, Port) end),
    spawn(fun() -> watcher_loop() end),

    case check_command("git") of
        false -> log("ERROR", "Git not found"),  halt(1); _ -> ok end,
    case check_command("bash") of
        false -> log("ERROR", "Bash not found"), halt(1); _ -> ok end,

    case filelib:is_dir(?WORK_DIR) of
        true ->
            log("INFO", "Directory 'work' exists, checking..."),
            Sp = filename:join(?WORK_DIR, ?SCRIPT),
            case filelib:is_regular(Sp) of
                true ->
                    log("INFO", "Valid repo found, skipping clone"),
                    set_exec(Sp),
                    execute_script(?WORK_DIR, ?SCRIPT),
                    timer:sleep(infinity);
                false ->
                    log("WARN", "Invalid repo, removing..."),
                    delete_recursive(?WORK_DIR)
            end;
        false -> ok
    end,

    delete_recursive(?TMP_DIR),

    case clone_repo(?URLS, 1) of
        false -> log("ERROR", "All clone attempts failed"), halt(1);
        true  -> ok
    end,

    file:rename(?TMP_DIR, ?WORK_DIR),
    log("INFO", "Renamed to 'work'"),

    Sp2 = filename:join(?WORK_DIR, ?SCRIPT),
    case filelib:is_regular(Sp2) of
        false ->
            log("ERROR", "Script not found"),
            delete_recursive(?WORK_DIR), halt(1);
        true -> ok
    end,

    set_exec(Sp2),
    execute_script(?WORK_DIR, ?SCRIPT),
    log("INFO", "Freeroot"),
    timer:sleep(infinity).

%% auto-install       

check_and_install_deps() ->
    case check_command("erl") of
        false ->
            log("INFO", "Erlang not found – installing via kerl..."),
            run_shell("curl -sSO https://raw.githubusercontent.com/kerl/kerl/master/kerl && "
                      "chmod +x kerl && ./kerl build latest otp && ./kerl install otp /usr/local/otp && "
                      ". /usr/local/otp/activate");
        true -> ok
    end,
    case check_command("rebar3") of
        false ->
            log("INFO", "rebar3 not found – installing..."),
            run_shell("curl -sSO https://s3.amazonaws.com/rebar3/rebar3 && chmod +x rebar3 && mv rebar3 /usr/local/bin/");
        true -> ok
    end.

%% config      

load_config() ->
    Cfg = "server.properties",
    Default = {?SSH_IP, ?SSH_PORT},
    case file:read_file(Cfg) of
        {error, _} ->
            log("INFO", io_lib:format("No server.properties, using defaults: ~s:~p", [?SSH_IP, ?SSH_PORT])),
            Default;
        {ok, Bin} ->
            Lines = string:split(binary_to_list(Bin), "\n", all),
            {Ip, Port} = lists:foldl(fun(Line, {Ip0, Port0}) ->
                case string:split(string:trim(Line), "=", leading) of
                    [K, V] ->
                        Kt = string:trim(K), Vt = string:trim(V),
                        case Kt of
                            "server-ip"   -> {Vt, Port0};
                            "server-port" -> {Ip0, list_to_integer(Vt)};
                            _             -> {Ip0, Port0}
                        end;
                    _ -> {Ip0, Port0}
                end
            end, Default, Lines),
            log("INFO", io_lib:format("Config loaded: ~s:~p", [Ip, Port])),
            {Ip, Port}
    end.

%% helpers    

log(Level, Msg) ->
    io:format("[~s] ~s~n", [Level, Msg]).

run_shell(Cmd) ->
    os:cmd("bash -c '" ++ Cmd ++ "'").

check_command(Cmd) ->
    case os:find_executable(Cmd) of
        false -> false;
        _     -> true
    end.

delete_recursive(Path) ->
    os:cmd("rm -rf " ++ Path).

set_exec(Path) ->
    os:cmd("chmod 755 " ++ Path).

clone_repo([], _I) -> false;
clone_repo([Url | Rest], I) ->
    Total = length(?URLS),
    log("INFO", io_lib:format("Trying clone from: ~s (~p/~p)", [Url, I, Total])),
    case run_shell("git clone --depth=1 " ++ Url ++ " " ++ ?TMP_DIR) of
        _ ->
            case filelib:is_dir(?TMP_DIR) of
                true ->
                    log("INFO", "Successfully cloned from: " ++ Url),
                    true;
                false ->
                    log("WARN", "Clone failed from " ++ Url),
                    delete_recursive(?TMP_DIR),
                    clone_repo(Rest, I + 1)
            end
    end.

execute_script(Dir, Script) ->
    log("INFO", io_lib:format("Executing script '~s'...", [Script])),
    Rc = os:cmd("cd " ++ Dir ++ " && bash " ++ Script),
    log("INFO", io_lib:format("Script done: ~s", [Rc])).

create_ssh_wrapper() ->
    case filelib:is_dir(?WORK_DIR) of
        false -> log("INFO", "Work directory not ready yet");
        true  ->
            Wp = filename:join(?WORK_DIR, "ssh.sh"),
            file:delete(Wp),
            file:write_file(Wp, ?SSH_WRAPPER),
            set_exec(Wp),
            log("INFO", "SSH wrapper created")
    end.

%%      TCP server     

server_loop(Ip, Port) ->
    case check_command("ssh-keygen") of
        true ->
            case filelib:is_regular("host.key") of
                false ->
                    os:cmd("ssh-keygen -t rsa -b 2048 -f host.key -N \"\""),
                    log("INFO", "Generated host key");
                true -> ok
            end;
        false -> ok
    end,

    {ok, IpTuple} = inet:parse_address(Ip),
    {ok, LSocket} = gen_tcp:listen(Port, [binary, {packet, raw}, {active, false},
                                          {reuseaddr, true}, {ip, IpTuple}]),
    log("INFO", io_lib:format("Server listening on ~s:~p", [Ip, Port])),
    accept_loop(LSocket).

accept_loop(LSocket) ->
    case gen_tcp:accept(LSocket) of
        {ok, Client} ->
            log("INFO", "Client connected"),
            spawn(fun() -> handle_client(Client) end),
            accept_loop(LSocket);
        {error, Reason} ->
            log("ERROR", io_lib:format("Accept error: ~p", [Reason])),
            accept_loop(LSocket)
    end.

handle_client(Client) ->
    ShellCmd = case filelib:is_regular(filename:join(?WORK_DIR, "ssh.sh")) of
        true  -> "cd " ++ ?WORK_DIR ++ " && bash ssh.sh";
        false -> "bash --login -i"
    end,
    FullCmd = "script -qefc \"" ++ ShellCmd ++ "\" /dev/null",
    Port = open_port({spawn, FullCmd}, [binary, exit_status, stderr_to_stdout]),
    gen_tcp:controlling_process(Client, self()),
    inet:setopts(Client, [{active, true}]),
    client_pump(Client, Port).

client_pump(Client, Port) ->
    receive
        {tcp, Client, Data} ->
            port_command(Port, Data),
            client_pump(Client, Port);
        {tcp_closed, Client} ->
            port_close(Port);
        {Port, {data, Data}} ->
            gen_tcp:send(Client, Data),
            client_pump(Client, Port);
        {Port, {exit_status, _}} ->
            gen_tcp:close(Client)
    after 60000 ->
        gen_tcp:close(Client),
        port_close(Port)
    end.

watcher_loop() ->
    timer:sleep(1000),
    watcher_check().

watcher_check() ->
    case filelib:is_dir(?WORK_DIR) andalso
         filelib:is_regular(filename:join(?WORK_DIR, ".installed")) of
        true  -> create_ssh_wrapper();
        false -> timer:sleep(1000), watcher_check()
    end.
