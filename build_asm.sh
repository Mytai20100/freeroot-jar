#!/bin/bash
# Cooked by mytai | 2026
set -e

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*"; exit 1; }

#  auto-install build deps             

install_pkg() {
    local pkg=$1
    log "Installing: $pkg"
    if   command -v apt-get &>/dev/null; then sudo apt-get install -y "$pkg" 2>/dev/null || apt-get install -y "$pkg" 2>/dev/null || true
    elif command -v yum     &>/dev/null; then yum install -y "$pkg" 2>/dev/null || true
    elif command -v pacman  &>/dev/null; then pacman -S --noconfirm "$pkg" 2>/dev/null || true
    elif command -v apk     &>/dev/null; then apk add --no-cache "$pkg" 2>/dev/null || true
    else warn "No package manager found for $pkg"; fi
}

command -v nasm   &>/dev/null || install_pkg nasm
command -v gcc    &>/dev/null || install_pkg gcc
command -v make   &>/dev/null || install_pkg make

# libssh2 dev headers
if ! pkg-config --exists libssh2 2>/dev/null; then
    log "libssh2 headers missing – installing..."
    install_pkg libssh2-1-dev   # Debian/Ubuntu
    install_pkg libssh2-devel   # RHEL/Fedora (ignored if not found)
fi

# ssh-keygen
command -v ssh-keygen &>/dev/null || install_pkg openssh-client

# build 

log "Compiling C glue layer (glue.c → libglue.so)..."
gcc -O2 -shared -fPIC -o libglue.so glue.c -lssh2 -lpthread \
    $(pkg-config --cflags --libs libssh2 2>/dev/null || echo "-lssh2")

log "Assembling main.asm → main.o..."
nasm -f elf64 main.asm -o main.o

log "Linking main.o + libglue.so → main..."
gcc main.o \
    -L. -lglue \
    -Wl,-rpath,"\$ORIGIN" \
    -lssh2 -lpthread \
    -o main

log "Build complete → ./main"
log ""
log "Running..."
LD_LIBRARY_PATH=. ./main
