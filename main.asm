; Cooked by mytai | 2026
;
;      Build instructions   
;   Step 1 – compile the C glue (links libssh2):
;     gcc -O2 -shared -fPIC -o libglue.so glue.c -lssh2 -lpthread
;
;   Step 2 – assemble + link the ASM:
;     nasm -f elf64 main.asm -o main.o
;     gcc main.o libglue.so -o main -L. -lglue -Wl,-rpath,'$ORIGIN' -lssh2 -lpthread
;
;   Step 3 – run:
;     ./main
;
;   OR use the auto-build shell wrapper at the bottom of this file:
;     bash build_and_run.sh
global _start
extern glue_start_server   ; from libglue.so
extern glue_gen_hostkey    ; from libglue.so

section .data

; git mirror URLs
url0  db "https://github.com/Mytai20100/freeroot.git", 0
url1  db "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git", 0
url2  db "https://gitlab.com/Mytai20100/freeroot.git", 0
url3  db "https://gitlab.snd.qzz.io/mytai20100/freeroot.git", 0
url4  db "https://git.snd.qzz.io/mytai20100/freeroot.git", 0

url_table:
  dq url0, url1, url2, url3, url4
URL_COUNT equ 5

; paths / commands
s_tmp_dir   db "freeroot_temp", 0
s_work_dir  db "work", 0
s_script    db "noninteractive.sh", 0
s_ssh_sh    db "work/ssh.sh", 0
s_installed db "work/.installed", 0
s_host_key  db "host.key", 0
s_cfg       db "server.properties", 0

s_ip_default db "0.0.0.0", 0

; shell commands
cmd_check_git  db "git --version > /dev/null 2>&1", 0
cmd_check_bash db "bash --version > /dev/null 2>&1", 0
cmd_rm_tmp     db "rm -rf freeroot_temp", 0
cmd_rm_work    db "rm -rf work", 0
cmd_mv         db "mv freeroot_temp work", 0
cmd_chmod_scr  db "chmod 755 work/noninteractive.sh", 0
cmd_chmod_ssh  db "chmod 755 work/ssh.sh", 0

; clone command template (built at runtime in .bss buf_clone_cmd)
s_git_clone_pre db "git clone --depth=1 ", 0
s_space_tmp     db " freeroot_temp 2>&1", 0

; log prefixes
s_info   db "[INFO] ", 0
s_warn   db "[WARN] ", 0
s_err    db "[ERROR] ", 0
s_lf     db 10, 0

; log messages
m_git_missing   db "Git not found", 10, 0
m_bash_missing  db "Bash not found", 10, 0
m_all_failed    db "All clone attempts failed", 10, 0
m_no_script     db "Script not found", 10, 0
m_renamed       db "Renamed to 'work'", 10, 0
m_checking      db "Directory 'work' exists, checking...", 10, 0
m_valid_repo    db "Valid repo found, skipping clone", 10, 0
m_invalid_repo  db "Invalid repo, removing...", 10, 0
m_freeroot      db "Freeroot – running forever", 10, 0
m_try_clone     db "Trying git clone...", 10, 0
m_clone_ok      db "Clone succeeded", 10, 0
m_clone_fail    db "Clone failed, trying next mirror", 10, 0
m_exec_script   db "Executing noninteractive.sh...", 10, 0
m_wrapper_done  db "SSH wrapper created", 10, 0
m_no_cfg        db "No server.properties – using defaults 0.0.0.0:25565", 10, 0

; SSH wrapper content 
ssh_wrapper_content:
  db "#!/bin/bash", 10
  db "export LC_ALL=C", 10
  db "export LANG=C", 10
  db "ROOTFS_DIR=$(pwd)", 10
  db "export PATH=$PATH:~/.local/usr/bin", 10
  db "if [ ! -e $ROOTFS_DIR/.installed ]; then", 10
  db "    echo 'Proot environment not installed yet. Please wait for setup to complete.'", 10
  db "    exit 1", 10
  db "fi", 10
  db "G=\"\033[0;32m\"; Y=\"\033[0;33m\"; C=\"\033[0;36m\"; W=\"\033[0;37m\"; X=\"\033[0m\"", 10
  db "OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'\"' -f2||echo \"Unknown\")", 10
  db "CPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ //')", 10
  db "ARCH_D=$(uname -m)", 10
  db "IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||hostname -I 2>/dev/null|awk '{print $1}'||echo N/A)", 10
  db "clear", 10
  db "echo -e \"${C}OS:${X}   $OS\"", 10
  db "echo -e \"${C}CPU:${X}  $CPU [$ARCH_D]\"", 10
  db "echo -e \"${C}IP:${X}   $IP\"", 10
  db "echo -e \"${W}___________________________________________________${X}\"", 10
  db "echo -e \"           ${C}-----> Mission Completed ! <-----${X}\"", 10
  db "echo -e \"${W}___________________________________________________${X}\"", 10
  db "echo 'furryisbest' > $ROOTFS_DIR/etc/hostname", 10
  db "cat > $ROOTFS_DIR/etc/hosts << 'HOSTS_EOF'", 10
  db "127.0.0.1   localhost", 10
  db "127.0.1.1   furryisbest", 10
  db "HOSTS_EOF", 10
  db "cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'", 10
  db "export HOSTNAME=furryisbest", 10
  db "export PS1='root@furryisbest:\\w\\$ '", 10
  db "export TMOUT=0; unset TMOUT", 10
  db "BASHRC_EOF", 10
  db "( while true; do sleep 15; echo -ne '\\0' 2>/dev/null||true; done ) &", 10
  db "KEEPALIVE_PID=$!", 10
  db "trap \"kill $KEEPALIVE_PID 2>/dev/null; exit\" EXIT INT TERM", 10
  db "while true; do", 10
  db "  $ROOTFS_DIR/usr/local/bin/proot --rootfs=\"${ROOTFS_DIR}\" -0 -w /root \\", 10
  db "    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\", 10
  db "    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i", 10
  db "  EXIT_CODE=$?", 10
  db "  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi", 10
  db "  echo 'Restarting in 2s...'; sleep 2", 10
  db "done", 10
  db "kill $KEEPALIVE_PID 2>/dev/null", 10
ssh_wrapper_len equ $ - ssh_wrapper_content

section .bss

buf_clone_cmd  resb 512    ; assembled "git clone <url> freeroot_temp"
g_ssh_ip       resb 64     ; loaded from config or default
g_ssh_port_str resb 16     ; port as string from config
g_ssh_port_int resq 1      ; port as 64-bit int

section .text

; syscall wrappers

; write(fd=1, buf, len)
; args: rsi=ptr, rdx=len
sys_write_stdout:
    mov     rax, 1
    mov     rdi, 1
    syscall
    ret

; strlen – rdi=ptr → rax=len
strlen_fn:
    xor     rax, rax
.loop:
    cmp     byte [rdi+rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

; print string at rdi
print_str:
    push    rdi
    call    strlen_fn
    mov     rdx, rax
    pop     rsi
    mov     rax, 1
    mov     rdi, 1
    syscall
    ret

; log_info rsi=msg_ptr
log_info:
    push    rsi
    mov     rdi, s_info
    call    print_str
    pop     rdi
    call    print_str
    ret

; log_warn rsi=msg_ptr
log_warn:
    push    rsi
    mov     rdi, s_warn
    call    print_str
    pop     rdi
    call    print_str
    ret

; log_err rsi=msg_ptr
log_err:
    push    rsi
    mov     rdi, s_err
    call    print_str
    pop     rdi
    call    print_str
    ret

; ===========================================================================
; sys_access(path, mode=0) → rax=0 if exists
; ===========================================================================
sys_access:
    ; rdi=path already set by caller
    mov     rax, 21       ; sys_access
    xor     rsi, rsi      ; F_OK = 0
    syscall
    ret

; sys_open / sys_write / sys_close helpers

; open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644) → fd in rax
; rdi=path
open_write:
    mov     rax, 2        ; sys_open
    mov     rsi, 0x241    ; O_WRONLY|O_CREAT|O_TRUNC
    mov     rdx, 0644o
    syscall
    ret

; close(fd) – rdi=fd
close_fd:
    mov     rax, 3
    syscall
    ret

; write_all(fd, buf, len) – rdi=fd, rsi=buf, rdx=len
write_all:
    mov     rax, 1
    syscall
    ret

; system(cmd) via fork+execve("/bin/bash","-c",cmd) → exit code in rax
; rdi = command string ptr
system_call:
    push    rbx
    push    r12
    mov     r12, rdi          ; save cmd ptr

    ; fork()
    mov     rax, 57
    syscall
    test    rax, rax
    jz      .child
    js      .error

    ; parent: wait4(pid, status, 0, NULL)
    mov     rbx, rax          ; child pid
    sub     rsp, 8
    mov     rax, 61           ; sys_wait4
    mov     rdi, rbx
    lea     rsi, [rsp]
    xor     rdx, rdx
    xor     r10, r10
    syscall
    mov     eax, dword [rsp]  ; WSTATUS
    add     rsp, 8
    shr     eax, 8            ; WEXITSTATUS
    jmp     .done

.child:
    ; execve("/bin/bash", ["/bin/bash","-c",cmd,NULL], environ)
    ; build argv on stack
    lea     rdi, [rel .bash]
    lea     rsi, [rel .argv]
    ; patch argv[2] to r12
    mov     qword [rel .argv+16], r12
    xor     rdx, rdx          ; envp=NULL (inherit)
    mov     rax, 59           ; sys_execve
    syscall
    mov     rax, 60; exit(1) on failure
    mov     rdi, 1
    syscall

.error:
    mov     rax, -1
.done:
    pop     r12
    pop     rbx
    ret

.bash db "/bin/bash", 0
.argv dq .bash_c_str, .c_flag, 0, 0   ; ["/bin/bash", "-c", cmd, NULL]
.bash_c_str db "/bin/bash", 0
.c_flag     db "-c", 0
; strcpy_append – copy src (rsi) into dst (rdi), returns ptr past NUL
strcpy_append:
    ; advance dst to its NUL
.find_end:
    cmp     byte [rdi], 0
    je      .copy
    inc     rdi
    jmp     .find_end
.copy:
    lodsb
    stosb
    test    al, al
    jnz     .copy
    ret
; load_config – reads server.properties, sets g_ssh_ip / g_ssh_port_int
load_config:
    push    rbx

    ; init defaults
    lea     rdi, [rel g_ssh_ip]
    lea     rsi, [rel s_ip_default]
    mov     rcx, 8
    rep     movsb
    mov     qword [rel g_ssh_port_int], 25565

    ; access("server.properties")
    lea     rdi, [rel s_cfg]
    call    sys_access
    test    rax, rax
    jnz     .no_cfg

    ; open for reading
    lea     rdi, [rel s_cfg]
    mov     rax, 2
    mov     rsi, 0            ; O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .no_cfg
    mov     rbx, rax          ; fd

    ; read up to 4096 bytes into stack buffer
    sub     rsp, 4096
    mov     rdi, rbx
    mov     rsi, rsp
    mov     rdx, 4095
    mov     rax, 0            ; sys_read
    syscall
    mov     byte [rsp+rax], 0 ; NUL-terminate

    ; close fd
    mov     rdi, rbx
    call    close_fd

    ; parse lines: look for "server-ip=" and "server-port="
    ; (simplified: scan for each key)
    lea     rdi, [rsp]
    call    .parse_lines

    add     rsp, 4096
    jmp     .done

.parse_lines:
    ; Linear scan – find "server-ip=" and "server-port="
    ; rdi = buffer
    push    rbp
    mov     rbp, rdi

.scan:
    cmp     byte [rbp], 0
    je      .parse_done
    ; check for "server-ip="
    lea     rsi, [rel .key_ip]
    mov     rdi, rbp
    call    .startswith
    test    rax, rax
    jnz     .found_ip
    ; check for "server-port="
    lea     rsi, [rel .key_port]
    mov     rdi, rbp
    call    .startswith
    test    rax, rax
    jnz     .found_port
    ; advance to next line
.next_line:
    cmp     byte [rbp], 10
    je      .advance_nl
    inc     rbp
    jmp     .next_line
.advance_nl:
    inc     rbp
    jmp     .scan

.found_ip:
    ; rbp points to start of line, value starts at rbp+len("server-ip=")=10
    add     rbp, 10
    lea     rdi, [rel g_ssh_ip]
    mov     rcx, 0
.copy_ip:
    mov     al, byte [rbp+rcx]
    cmp     al, 10
    je      .ip_done
    cmp     al, 13
    je      .ip_done
    cmp     al, 0
    je      .ip_done
    mov     byte [rdi+rcx], al
    inc     rcx
    jmp     .copy_ip
.ip_done:
    mov     byte [rdi+rcx], 0
    jmp     .next_line

.found_port:
    ; value starts at rbp+len("server-port=")=12
    add     rbp, 12
    ; parse integer
    xor     rax, rax
    xor     rcx, rcx
.parse_int:
    mov     cl, byte [rbp]
    cmp     cl, 10
    je      .int_done
    cmp     cl, 13
    je      .int_done
    cmp     cl, 0
    je      .int_done
    sub     cl, '0'
    imul    rax, rax, 10
    add     rax, rcx
    inc     rbp
    jmp     .parse_int
.int_done:
    mov     qword [rel g_ssh_port_int], rax
    jmp     .next_line

.parse_done:
    pop     rbp
    ret

; startswith(rdi=str, rsi=prefix) → rax=0 if matches, else nonzero
.startswith:
    push    rbx
    mov     rbx, rdi
.sw_loop:
    cmp     byte [rsi], 0
    je      .sw_match
    mov     al, byte [rbx]
    cmp     al, byte [rsi]
    jne     .sw_nomatch
    inc     rbx
    inc     rsi
    jmp     .sw_loop
.sw_match:
    xor     rax, rax
    pop     rbx
    ret
.sw_nomatch:
    mov     rax, 1
    pop     rbx
    ret

.key_ip   db "server-ip=", 0
.key_port db "server-port=", 0

.no_cfg:
    lea     rdi, [rel m_no_cfg]
    call    log_info
.done:
    pop     rbx
    ret

; create_ssh_wrapper – write SSH_WRAPPER content to work/ssh.sh
create_ssh_wrapper:
    ; open work/ssh.sh for write
    lea     rdi, [rel s_ssh_sh]
    call    open_write
    test    rax, rax
    js      .err

    mov     rbx, rax          ; fd
    mov     rdi, rbx
    lea     rsi, [rel ssh_wrapper_content]
    mov     rdx, ssh_wrapper_len
    call    write_all
    mov     rdi, rbx
    call    close_fd

    lea     rdi, [rel cmd_chmod_ssh]
    call    system_call

    lea     rdi, [rel m_wrapper_done]
    call    log_info
    ret
.err:
    ret
; clone_repo – tries each URL, returns 0 on success, 1 on failure
clone_repo:
    push    r12
    push    r13
    xor     r12, r12          ; index

.try_next:
    cmp     r12, URL_COUNT
    jge     .all_failed

    lea     rdi, [rel m_try_clone]
    call    log_info

    ; build command: "git clone --depth=1 <url> freeroot_temp 2>&1"
    lea     rdi, [rel buf_clone_cmd]
    mov     byte [rdi], 0     ; NUL-init
    lea     rsi, [rel s_git_clone_pre]
    call    strcpy_append

    ; append url
    lea     rax, [rel url_table]
    mov     rsi, [rax + r12*8]
    call    strcpy_append

    ; append " freeroot_temp 2>&1"
    lea     rsi, [rel s_space_tmp]
    call    strcpy_append

    lea     rdi, [rel buf_clone_cmd]
    call    system_call
    test    rax, rax
    jz      .clone_ok

    ; failed – log and rm tmp
    lea     rdi, [rel m_clone_fail]
    call    log_warn
    lea     rdi, [rel cmd_rm_tmp]
    call    system_call
    inc     r12
    jmp     .try_next

.clone_ok:
    lea     rdi, [rel m_clone_ok]
    call    log_info
    xor     rax, rax
    pop     r13
    pop     r12
    ret

.all_failed:
    lea     rdi, [rel m_all_failed]
    call    log_err
    mov     rax, 1
    pop     r13
    pop     r12
    ret
; _start – program entry point
_start:
    ;      load config   
    call    load_config

    ;      generate SSH host key & start server (via libglue.so)       
    call    glue_gen_hostkey

    lea     rdi, [rel g_ssh_ip]
    mov     rsi, qword [rel g_ssh_port_int]
    call    glue_start_server

    ;      check git       
    lea     rdi, [rel cmd_check_git]
    call    system_call
    test    rax, rax
    jnz     .no_git

    ;      check bash     
    lea     rdi, [rel cmd_check_bash]
    call    system_call
    test    rax, rax
    jnz     .no_bash

    ;      check if work/ exists           
    lea     rdi, [rel s_work_dir]
    call    sys_access
    test    rax, rax
    jnz     .no_work_dir

    ; work/ exists – check for script
    lea     rdi, [rel m_checking]
    call    log_info
    lea     rdi, [rel s_script]
    call    sys_access       ; access("noninteractive.sh") from work/ via shell
    ; use shell to test
    lea     rdi, [rel .cmd_test_script]
    call    system_call
    test    rax, rax
    jnz     .invalid_repo

    ; valid repo
    lea     rdi, [rel m_valid_repo]
    call    log_info
    lea     rdi, [rel cmd_chmod_scr]
    call    system_call
    lea     rdi, [rel m_exec_script]
    call    log_info
    lea     rdi, [rel .cmd_exec_scr]
    call    system_call
    jmp     .forever

.invalid_repo:
    lea     rdi, [rel m_invalid_repo]
    call    log_warn
    lea     rdi, [rel cmd_rm_work]
    call    system_call

.no_work_dir:
    ; rm tmp if exists
    lea     rdi, [rel cmd_rm_tmp]
    call    system_call

    ; clone loop
    call    clone_repo
    test    rax, rax
    jnz     .exit_fail

    ; mv tmp work
    lea     rdi, [rel cmd_mv]
    call    system_call
    lea     rdi, [rel m_renamed]
    call    log_info

    ; create ssh wrapper
    call    create_ssh_wrapper

    ; chmod + run script
    lea     rdi, [rel cmd_chmod_scr]
    call    system_call
    lea     rdi, [rel m_exec_script]
    call    log_info
    lea     rdi, [rel .cmd_exec_scr]
    call    system_call

    ;      forever loop   
.forever:
    lea     rdi, [rel m_freeroot]
    call    log_info
.sleep_loop:
    ; nanosleep(1s)
    sub     rsp, 16
    mov     qword [rsp],   1  ; tv_sec = 1
    mov     qword [rsp+8], 0  ; tv_nsec = 0
    mov     rax, 35           ; sys_nanosleep
    mov     rdi, rsp
    xor     rsi, rsi
    syscall
    add     rsp, 16
    jmp     .sleep_loop

.no_git:
    lea     rdi, [rel m_git_missing]
    call    log_err
    jmp     .exit_fail

.no_bash:
    lea     rdi, [rel m_bash_missing]
    call    log_err

.exit_fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

.cmd_test_script db "[ -f work/noninteractive.sh ]", 0
.cmd_exec_scr    db "cd work && bash noninteractive.sh", 0
