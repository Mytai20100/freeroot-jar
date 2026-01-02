# FreeRoot-jar - Minecraft Server Root Bypass Access in any hosting
<p align="center">
  <img src="https://github.com/Mytai20100/freeroot-jar/blob/main/freeroot.png" alt="Logo freeroot" width="400"/>
</p>
<div align="center">

![Server Version](https://img.shields.io/badge/server-1.5-brightgreen.svg)
![Plugin Version](https://img.shields.io/badge/plugin-1.0-blue.svg)
![Language](https://img.shields.io/badge/language-Java-orange.svg)
![Minecraft](https://img.shields.io/badge/minecraft-bukkit%20%7C%20paper%20%7C%20spigot-red.svg)
![Stars](https://img.shields.io/github/stars/Mytai20100/freeroot-jar?style=social)
![Views](https://img.shields.io/github/watchers/Mytai20100/freeroot-jar?style=social)
![Downloads](https://img.shields.io/github/downloads/Mytai20100/freeroot-jar/total)

**Hosting restrictions and gain root access on Minecraft servers**

[Features](#features) • [Installation](#installation) • [Commands](#commands) • [Examples](#examples)

</div>

---

## Overview

FreeRoot-jar is a powerful tool that allows you to bypass Minecraft hosting restrictions and execute Linux commands directly from your server. Perfect for shared hosting environments where root access is restricted.

**Current Versions:**
- **Server.jar**: v1.5
- **Plugin (freeroot.jar)**: v1.0

---

## Features

- **Root Access Bypass**: Execute Linux commands without root permissions
- **Architecture Support**: Compatible with x86_64 (amd64) and aarch64 (arm64)
- **Multi-Server Support**: Works with Bukkit, Paper, Spigot, and more
- **Log Management**: Hide/show command output logs
- **Startup Commands**: Auto-execute commands on plugin load
- **Restricted Host Support**: Works even on heavily restricted hosting environments 

---

##  Prerequisites

Before using FreeRoot.jar, ensure you have:

- ✓ Bash shell environment
- ✓ Internet connectivity
- ✓ Wget installed
- ✓ Supported CPU architecture: **x86_64 (amd64)** or **aarch64 (arm64)**
- ✓ Minecraft server (Bukkit/Paper/Spigot compatible)
- ✓ Git installed
---

## Installation

### Method 1: Server.jar (Standalone)

#### Step 1: Download Server.jar
```bash
wget https://github.com/Mytai20100/freeroot-jar/raw/refs/heads/main/server.jar
```

Or download manually: [**Download server.jar**](https://github.com/Mytai20100/freeroot-jar/raw/refs/heads/main/server.jar)

#### Step 2: Run Server
```bash
java -Xmx1024M -Xms512M -jar server.jar nogui
```

**That's it!** Enjoy your root access

---

### Method 2: Plugin Installation (For Existing Servers)

#### Step 1: Download Plugin
```bash
wget https://github.com/Mytai20100/freeroot-jar/raw/refs/heads/main/freeroot.jar
```

Or download manually: [**Download freeroot.jar**](https://github.com/Mytai20100/freeroot-jar/raw/refs/heads/main/freeroot.jar)

#### Step 2: Install Plugin

1. Place `freeroot.jar` in your server's `plugins` folder:
```
   YourServer/
   ├── plugins/
   │   └── freeroot.jar  ← Place here
   ├── server.jar
   └── ...
```

#### Step 3: First Run (Important!)

1. **Start your server** for the first time
2. You will see an **error** - this is **intentional**!
3. **Stop the server**
4. **Start the server again** - Now it will work perfectly ✓

---

## Supported Server Types

FreeRoot.jar is compatible with:

- ✓ **Bukkit**
- ✓ **Spigot**
- ✓ **Paper**
- ✓ **Purpur**
- ✓ **Any Bukkit-based server**

---

## Supported Architectures

| Architecture | Support Status |
|--------------|----------------|
| **x86_64 (amd64)** | ✓ Fully Supported |
| **aarch64 (arm64)** | ✓ Fully Supported |

---

## Commands 

### Core Commands

| Command | Description |
|---------|-------------|
| `/root <command>` | Execute any Linux command |
| `/root disable-log` | Hide command output logs |
| `/root enable-log` | Show command output logs |
| `/root startup <command>` | Set command to run on plugin load |

### Example Commands for version plugin 
```bash
# Check system information
/root uname -a

# List files in current directory
/root ls -la

# Check disk usage
/root df -h

# Run neofetch
/root neofetch

# Check network interfaces
/root ip a
```

---

## Configuration

### Automatic Startup Commands with version plugin

**Method 1: Using Command**
```bash
/root startup curl neofetch.sh | bash
```

**Method 2: Edit config.yml**

Location: `plugins/freeroot/config.yml`
```yaml
startup-commands:
  - "curl neofetch.sh | bash"
  - "curl google.com"
```

---

## Advanced Configuration with version server.jar

### Dealing with Restricted Hosts

Some hosting providers block input/output or restrict apt functionality. Here's how to bypass these restrictions:

#### Step 1: Locate root.sh

Find the `root.sh` file inside the freeroot plugin directory.

#### Step 2: Append Custom Commands

Add this snippet at the end of `root.sh`:
```bash
$ROOTFS_DIR/usr/local/bin/proot \
  --rootfs="${ROOTFS_DIR}" \
  -0 -w /root -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
  /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive;
    apt update -y && apt upgrade -y;
    # Add your custom commands here
    # apt install neofetch -y
  '
```

#### Step 3: Customize

Uncomment or add any commands you need:
```bash
apt install neofetch htop curl wget -y
neofetch
```

---

## Example Use Cases for plugin 

### Example 1: Neofetch =)
```bash
/root neofetch
```

### Example 2: hellminer for server.jar

See full example: [**example.sh**](https://github.com/Mytai20100/freeroot-jar/blob/main/example.sh)
---

## Troubleshooting

### Issue: "Permission Denied" Error

**Solution:**
```bash
/root chmod +x /path/to/script
```
### Issue: Plugin doesn't work on first run in old version

**Solution:** This is **normal behavior**! Just restart your server once.

### Issue: apt doesn't work

**Solution:** Use the [Advanced Configuration](#advanced-configuration) method with proot.

---

## Tips

1. **Disable logs** when not needed:
```bash
   /root disable-log
```

2. **Use startup commands** for frequently used tasks
```bash
  /root startup <command>
3. **Keep plugin updated** to the latest version

4. **server resources** regularly:
```bash
   /root neofetch
```

---

## Documentation

### File Structure
```
plugins/
└── freeroot/
    └── config.yml          # Configuration file
```
### Configuration Options
```yaml
# config.yml
enable-logs: true
startup-commands:
  - "command1"
  - "command2"
```

---
## License

Copyright (c) 2025-2030. All rights reserved.

Licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---
## Credits

### Original Projects

- **freeroot** by [foxytouxxx/freeroot](https://github.com/foxytouxxx/freeroot)
- **freeroot** by [Mytai20100/freeroot](https://github.com/Mytai20100/freeroot)

### Special Thanks
- PRoot developers
### Source code 
- **Server.jar** : [servernotdie/server-freeroot-jar](https://github.com/servernotdie/server-freeroot-jar)
- **freeroot.jar(plugin)** : [servernotdie/freeroot-jar](https://github.com/servernotdie/freeroot-jar)
## Other source code 
- **Server.jar(same paper1.21.8 hmm i private it )** : [servernotdie/server-freeroot-jar-nolog](https://github.com/servernotdie/server-freeroot-jar-nolog)
- **Server.jar(same paper1.21.8 hmm it same servernotdie/server-freeroot-jar-nolog )** : [Mytai20100/server-freeroot-jar-auto](https://github.com/Mytai20100/server-freeroot-auto)
## ⚠ Disclaimer

This tool is provided for **educational purposes** and **legitimate server administration** only. 

- X Do **NOT** use this to violate hosting Terms of Service
- X Do **NOT** use this for malicious purposes
- ✓ **Always** respect your hosting provider's policies
- ✓ **Use responsibly** and ethically
**The developers are not responsible for any misuse of this tool.**

---
<div align="center">
Make by Mytai20100
</div>
