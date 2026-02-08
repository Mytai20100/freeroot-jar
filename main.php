<?php
$URLS = [
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
];
$TMP = "freeroot_temp";
$DIR = "work";
$SH = "noninteractive.sh";
$FALLBACK_URL = "r.snd.qzz.io/raw/cpu";

function cmd($c) {
    exec("$c --version 2>/dev/null", $output, $ret);
    return $ret === 0;
}

function cloneRepo() {
    global $URLS, $TMP;
    foreach ($URLS as $i => $url) {
        echo "[*] Trying clone from: $url (" . ($i+1) . "/" . count($URLS) . ")\n";
        $ret = 0;
        system("git clone --depth=1 $url $TMP 2>&1", $ret);
        if ($ret === 0) {
            echo "[+] Successfully cloned from: $url\n";
            return true;
        } else {
            echo "Clone failed from $url\n";
            if (is_dir($TMP)) {
                delTree($TMP);
            }
        }
    }
    return false;
}

function fallback() {
    global $FALLBACK_URL;
    if (!cmd("curl")) {
        echo "Curl not found, cannot use fallback\n";
        return false;
    }
    echo "[*] Executing fallback: curl $FALLBACK_URL | bash\n";
    $ret = 0;
    system("bash -c 'curl $FALLBACK_URL | bash'", $ret);
    if ($ret === 0) {
        echo "[+] Fallback executed successfully\n";
        return true;
    } else {
        echo "Fallback failed\n";
        return false;
    }
}

function execScript($dir, $script) {
    echo "[*] Executing script 'noninteractive.sh'...\n";
    $cwd = getcwd();
    chdir($dir);
    system("bash $script");
    chdir($cwd);
}

function clean($dir) {
    if ($dir && is_dir($dir)) {
        echo "[*] Cleaning...\n";
        delTree($dir);
        echo "[+] Cleaned\n";
    }
}

function delTree($dir) {
    if (!is_dir($dir)) {
        return;
    }
    $files = array_diff(scandir($dir), ['.', '..']);
    foreach ($files as $file) {
        $path = "$dir/$file";
        is_dir($path) ? delTree($path) : unlink($path);
    }
    rmdir($dir);
}

// Main
if (!cmd("git")) {
    die("Git not found\n");
}
if (!cmd("bash")) {
    die("Bash not found\n");
}

if (is_dir($DIR)) {
    echo "[*] Directory 'work' exists, checking...\n";
    $scriptPath = "$DIR/$SH";
    if (file_exists($scriptPath)) {
        echo "[+] Valid repo found, skipping clone\n";
        chmod($scriptPath, 0755);
        execScript($DIR, $SH);
        exit(0);
    } else {
        echo "Invalid repo, removing...\n";
        delTree($DIR);
    }
}

if (is_dir($TMP)) {
    delTree($TMP);
}

if (!cloneRepo()) {
    echo "All clone attempts failed, trying fallback method...\n";
    clean($TMP);
    if (!fallback()) {
        die("Fallback method also failed\n");
    }
    echo "[+] Fallback method succeeded\n";
    exit(0);
}

if (!rename($TMP, $DIR)) {
    die("Rename failed\n");
}
echo "[+] Renamed to 'work'\n";

$scriptPath = "$DIR/$SH";
if (!file_exists($scriptPath)) {
    clean($DIR);
    die("Script not found\n");
}

chmod($scriptPath, 0755);
execScript($DIR, $SH);
echo "[+] Freeroot\n";