## Overview
freeroot with .jar (bypass hosting minecraft)
hi =) 
## Prerequisites

- Bash shell environment
- Internet connectivity
- Wget installed
- Supported CPU architecture: x86_64 (amd64) or aarch64 (arm64)

## Installation

step 1. Download file server.jar [here](https://github.com/Mytai20100/freeroot-jar/raw/refs/heads/main/server.jar)    
step 2. Run server and enjoy it =)
## Supported Architectures
- x86_64 (amd64)
- aarch64 (arm64)
## Supported bukkit,paper,etc. 
Download plugin here : [freeroot](https://github.com/Mytai20100/freeroot-jar/raw/refs/heads/main/freeroot.jar)
## How to Use It

## Step 1: Download
Download the file from the link above.

## Step 2: Install
Place it in the `plugins` folder of your Minecraft server.

## Step 3: First Run
Run your server for the first time. There will be an error, but this is intentional. Simply stop the server and start it again for the second time.

## How to Hide Output

- Use `/root disable-log` to hide the log output.  
- If you want to show the log output again, use `/root enable-log`.

## How to Set Up Automatic Commands on Plugin Load

- Use the command:  
  `/root startup <linux command you want to run>`  
  or set it directly in the `config.yml` file.
## Optional Dealing with restricted hosts (e.g. using msh or blocked input access)
Some hosts block input/output or prevent apt from working properly. In these cases, you can modify the root.sh file inside freeroot and append the following snippet at the end:
>`$ROOTFS_DIR/usr/local/bin/proot \
  --rootfs="${ROOTFS_DIR}" \
  -0 -w /root -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
  /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive;
    apt update -y && apt upgrade -y ;
 #apt install neofetch -y 
  '
`
## Example for miner =) with hellminer
[example](https://github.com/Mytai20100/freeroot-jar/blob/main/example.sh).
## Credits
freeroot by [foxytouxxx/freeroot](https://github.com/foxytouxxx/freeroot).
freeroot by [Mytai20100/freeroot](https://github.com/Mytai20100/freeroot).
## License
(c) 2025 -2026 ????? and ??? . All rights reserved. Licensed under the MIT License.
