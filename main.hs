-- Cooked by mytai | 2026
-- Run:  runghc main.hs       (auto-installs deps via cabal first)
-- Or:   cabal run            (with a project cabal file)

module Main where

import System.IO
import System.Exit
import System.Process
import System.Directory
import System.Environment
import System.Posix.Files    (setFileMode, unionFileModes, ownerExecuteMode,
                               groupExecuteMode, otherReadMode, ownerReadMode,
                               ownerWriteMode, groupReadMode)
import System.Posix.IO       (fdToHandle)
import Control.Concurrent    (forkIO, threadDelay, MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Exception     (catch, SomeException, try)
import Data.List             (isPrefixOf, isInfixOf)
import Data.Maybe            (fromMaybe)
import Network.Socket
import Network.Socket.ByteString (recv, sendAll)
import qualified Data.ByteString as BS

urls :: [String]
urls =
    [ "https://github.com/Mytai20100/freeroot.git"
    , "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git"
    , "https://gitlab.com/Mytai20100/freeroot.git"
    , "https://gitlab.snd.qzz.io/mytai20100/freeroot.git"
    , "https://git.snd.qzz.io/mytai20100/freeroot.git"
    ]

tmpDir, workDir, scriptName :: String
tmpDir     = "freeroot_temp"
workDir    = "work"
scriptName = "noninteractive.sh"

sshWrapper :: String
sshWrapper = unlines
    [ "#!/bin/bash"
    , "export LC_ALL=C"
    , "export LANG=C"
    , "ROOTFS_DIR=$(pwd)"
    , "export PATH=$PATH:~/.local/usr/bin"
    , ""
    , "if [ ! -e $ROOTFS_DIR/.installed ]; then"
    , "    echo 'Proot environment not installed yet. Please wait for setup to complete.'"
    , "    exit 1"
    , "fi"
    , ""
    , "G=\"\\033[0;32m\"; Y=\"\\033[0;33m\"; R=\"\\033[0;31m\""
    , "C=\"\\033[0;36m\"; W=\"\\033[0;37m\"; X=\"\\033[0m\""
    , "OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'\"' -f2||echo \"Unknown\")"
    , "CPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ *//')"
    , "ARCH_D=$(uname -m)"
    , "CPU_U=$(top -bn1 2>/dev/null | awk '/Cpu\\(s\\)/{print $2+$4}' || echo 0)"
    , "TRAM=$(free -h --si 2>/dev/null | awk '/^Mem:/{print $2}' || echo 'N/A')"
    , "URAM=$(free -h --si 2>/dev/null | awk '/^Mem:/{print $3}' || echo 'N/A')"
    , "RAM_PERCENT=$(free 2>/dev/null | awk '/^Mem:/{printf \"%.1f\", $3/$2 * 100}' || echo 0)"
    , "DISK=$(df -h /|awk 'NR==2{print $2}')"
    , "UDISK=$(df -h /|awk 'NR==2{print $3}')"
    , "DISK_PERCENT=$(df -h /|awk 'NR==2{print $5}'|sed 's/%//')"
    , "IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||curl -s --max-time 2 icanhazip.com 2>/dev/null||hostname -I 2>/dev/null|awk '{print $1}'||echo \"N/A\")"
    , "clear"
    , "echo -e \"${C}OS:${X}   $OS\""
    , "echo -e \"${C}CPU:${X}  $CPU [$ARCH_D]  Usage: ${CPU_U}%\""
    , "echo -e \"${G}RAM:${X}  ${URAM} / ${TRAM} (${RAM_PERCENT}%)\""
    , "echo -e \"${Y}Disk:${X} ${UDISK} / ${DISK} (${DISK_PERCENT}%)\""
    , "echo -e \"${C}IP:${X}   $IP\""
    , "echo -e \"${W}___________________________________________________${X}\""
    , "echo -e \"           ${C}-----> Mission Completed ! <-----${X}\""
    , "echo -e \"${W}___________________________________________________${X}\""
    , "echo \"\""
    , ""
    , "echo 'furryisbest' > $ROOTFS_DIR/etc/hostname"
    , "cat > $ROOTFS_DIR/etc/hosts << 'HOSTS_EOF'"
    , "127.0.0.1   localhost"
    , "127.0.1.1   furryisbest"
    , "::1         localhost ip6-localhost ip6-loopback"
    , "ff02::1     ip6-allnodes"
    , "ff02::2     ip6-allrouters"
    , "HOSTS_EOF"
    , ""
    , "cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'"
    , "export HOSTNAME=furryisbest"
    , "export PS1='root@furryisbest:\\w\\$ '"
    , "export LC_ALL=C; export LANG=C"
    , "export TMOUT=0; unset TMOUT"
    , "set +o history 2>/dev/null; PROMPT_COMMAND=''"
    , "alias ls='ls --color=auto'; alias ll='ls -lah'; alias grep='grep --color=auto'"
    , "BASHRC_EOF"
    , ""
    , "( while true; do sleep 15; echo -ne '\\0' 2>/dev/null || true; done ) &"
    , "KEEPALIVE_PID=$!"
    , "trap \"kill $KEEPALIVE_PID 2>/dev/null; exit\" EXIT INT TERM"
    , ""
    , "while true; do"
    , "  $ROOTFS_DIR/usr/local/bin/proot \\"
    , "    --rootfs=\"${ROOTFS_DIR}\" -0 -w \"/root\" \\"
    , "    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\"
    , "    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i"
    , "  EXIT_CODE=$?"
    , "  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi"
    , "  echo 'Session interrupted. Restarting in 2 seconds...'; sleep 2"
    , "done"
    , "kill $KEEPALIVE_PID 2>/dev/null"
    ]

--  auto-install       

-- Packages this file imports that are NOT in base/prelude.
-- cabal will install them if missing.
neededPackages :: [String]
neededPackages = ["network"]

checkAndInstallDeps :: IO ()
checkAndInstallDeps = do
    -- Ensure GHC is available
    ghcOk <- checkCommand "ghc"
    if not ghcOk then do
        logMsg "INFO" "ghc not found – trying to install via ghcup..."
        _ <- system "curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh"
        home <- getHomeDir
        let ghcupBin = home ++ "/.ghcup/bin"
        path <- getEnv "PATH"
        setEnv "PATH" (path ++ ":" ++ ghcupBin)
    else return ()

    -- Ensure cabal is available
    cabalOk <- checkCommand "cabal"
    if cabalOk then do
        logMsg "INFO" "Checking cabal packages..."
        _ <- system "cabal update > /dev/null 2>&1"
        mapM_ installIfMissing neededPackages
    else
        logMsg "WARN" "cabal not found – some packages may be missing"

installIfMissing :: String -> IO ()
installIfMissing pkg = do
    rc <- system $ "ghc-pkg list " ++ pkg ++ " 2>/dev/null | grep -q " ++ pkg
    case rc of
        ExitSuccess -> return ()
        _           -> do
            logMsg "INFO" $ "Installing cabal package: " ++ pkg
            _ <- system $ "cabal install " ++ pkg ++ " --lib --overwrite-policy=always"
            return ()

-- logging    

logMsg :: String -> String -> IO ()
logMsg level msg = putStrLn $ "[" ++ level ++ "] " ++ msg

-- config      

data Config = Config { cfgIp :: String, cfgPort :: Int }

defaultConfig :: Config
defaultConfig = Config { cfgIp = "0.0.0.0", cfgPort = 25565 }

loadConfig :: IO Config
loadConfig = do
    exists <- doesFileExist "server.properties"
    if not exists then do
        logMsg "INFO" $ "No server.properties, using defaults: " ++
            cfgIp defaultConfig ++ ":" ++ show (cfgPort defaultConfig)
        return defaultConfig
    else do
        content <- readFile "server.properties"
        let pairs = [ break (== '=') l | l <- lines content, '=' `elem` l ]
        let kvs   = [ (trim k, trim (drop 1 v)) | (k, v) <- pairs ]
        let ip    = fromMaybe (cfgIp defaultConfig)   $ lookup "server-ip"   kvs
        let port  = maybe (cfgPort defaultConfig) read $ lookup "server-port" kvs
        logMsg "INFO" $ "Config loaded: " ++ ip ++ ":" ++ show port
        return Config { cfgIp = ip, cfgPort = port }
  where
    trim = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

-- helpers    

checkCommand :: String -> IO Bool
checkCommand cmd = do
    rc <- system $ cmd ++ " --version > /dev/null 2>&1"
    return $ rc == ExitSuccess

deleteRecursive :: FilePath -> IO ()
deleteRecursive path = do
    isD <- doesDirectoryExist path
    isF <- doesFileExist path
    if isD then removeDirectoryRecursive path
    else if isF then removeFile path
    else return ()

setExec :: FilePath -> IO ()
setExec path = setFileMode path mode
  where
    mode = ownerReadMode `unionFileModes` ownerWriteMode
        `unionFileModes` ownerExecuteMode
        `unionFileModes` groupReadMode
        `unionFileModes` groupExecuteMode
        `unionFileModes` otherReadMode

runShell :: String -> IO ExitCode
runShell cmd = system cmd

cloneRepo :: IO Bool
cloneRepo = go urls 1
  where
    go [] _ = return False
    go (url:rest) i = do
        logMsg "INFO" $ "Trying clone from: " ++ url ++
            " (" ++ show i ++ "/" ++ show (length urls) ++ ")"
        rc <- runShell $ "git clone --depth=1 " ++ url ++ " " ++ tmpDir
        case rc of
            ExitSuccess -> do
                logMsg "INFO" $ "Successfully cloned from: " ++ url
                return True
            _ -> do
                logMsg "WARN" $ "Clone failed from " ++ url
                deleteRecursive tmpDir
                go rest (i + 1)

executeScript :: FilePath -> String -> IO ()
executeScript directory scr = do
    logMsg "INFO" $ "Executing script '" ++ scr ++ "'..."
    rc <- runShell $ "cd " ++ directory ++ " && bash " ++ scr
    logMsg "INFO" $ "Process exited with code: " ++ show rc

createSSHWrapper :: IO ()
createSSHWrapper = do
    exists <- doesDirectoryExist workDir
    if not exists then logMsg "INFO" "Work directory not ready yet"
    else do
        let wp = workDir ++ "/ssh.sh"
        writeFile wp sshWrapper
        setExec wp
        logMsg "INFO" "SSH wrapper created"

-- TCP server     

handleClient :: Socket -> IO ()
handleClient conn = do
    sshScriptExists <- doesFileExist $ workDir ++ "/ssh.sh"
    let shellCmd = if sshScriptExists
                   then "cd work && bash ssh.sh"
                   else "bash --login -i"

    let procSpec = (shell $ "script -qefc \"" ++ shellCmd ++ "\" /dev/null")
                   { std_in  = CreatePipe
                   , std_out = CreatePipe
                   , std_err = CreatePipe
                   }

    (Just pIn, Just pOut, Just pErr, ph) <- createProcess procSpec

    -- pump client → process stdin
    _ <- forkIO $ do
        let loop = do
                chunk <- recv conn 4096
                if BS.null chunk then return ()
                else do
                    BS.hPut pIn chunk
                    hFlush pIn
                    loop
        catch loop (\(_ :: SomeException) -> return ())
        hClose pIn

    -- pump process stderr → client
    _ <- forkIO $ do
        let loop = do
                chunk <- BS.hGetSome pErr 4096
                if BS.null chunk then return ()
                else sendAll conn chunk >> loop
        catch loop (\(_ :: SomeException) -> return ())

    -- pump process stdout → client (main)
    let loop = do
            chunk <- BS.hGetSome pOut 4096
            if BS.null chunk then return ()
            else sendAll conn chunk >> loop
    catch loop (\(_ :: SomeException) -> return ())

    _ <- waitForProcess ph
    close conn

startServer :: Config -> IO ()
startServer cfg = do
    keyExists <- doesFileExist "host.key"
    if not keyExists then do
        _ <- runShell "ssh-keygen -t rsa -b 2048 -f host.key -N \"\""
        logMsg "INFO" "Generated host key"
    else return ()

    addr <- resolve (cfgIp cfg) (show $ cfgPort cfg)
    sock <- socket (addrFamily addr) Stream defaultProtocol
    setSocketOption sock ReuseAddr 1
    bind sock (addrAddress addr)
    listen sock 128
    logMsg "INFO" $ "Server listening on " ++ cfgIp cfg ++ ":" ++ show (cfgPort cfg)

    acceptLoop sock
  where
    resolve host port = do
        let hints = defaultHints { addrSocketType = Stream }
        head <$> getAddrInfo (Just hints) (Just host) (Just port)

    acceptLoop sock = do
        (conn, _) <- accept sock
        logMsg "INFO" "Client connected"
        _ <- forkIO $ handleClient conn
        acceptLoop sock

watcherLoop :: IO ()
watcherLoop = do
    threadDelay 1000000
    loop
  where
    loop = do
        wdExists  <- doesDirectoryExist workDir
        dotExists <- doesFileExist $ workDir ++ "/.installed"
        if wdExists && dotExists
        then createSSHWrapper
        else do
            threadDelay 1000000
            loop

--  main  

main :: IO ()
main = do
    hSetBuffering stdout LineBuffering
    checkAndInstallDeps
    cfg <- loadConfig

    _ <- forkIO $ startServer cfg
    _ <- forkIO watcherLoop

    gitOk  <- checkCommand "git"
    bashOk <- checkCommand "bash"
    if not gitOk  then logMsg "ERROR" "Git not found"  >> exitFailure else return ()
    if not bashOk then logMsg "ERROR" "Bash not found" >> exitFailure else return ()

    wdExists <- doesDirectoryExist workDir
    if wdExists then do
        logMsg "INFO" "Directory 'work' exists, checking..."
        let sp = workDir ++ "/" ++ scriptName
        spExists <- doesFileExist sp
        if spExists then do
            logMsg "INFO" "Valid repo found, skipping clone"
            setExec sp
            executeScript workDir scriptName
            sleepForever
        else do
            logMsg "WARN" "Invalid repo, removing..."
            deleteRecursive workDir
    else return ()

    deleteRecursive tmpDir

    cloned <- cloneRepo
    if not cloned then do
        logMsg "ERROR" "All clone attempts failed"
        exitFailure
    else return ()

    _ <- runShell $ "mv " ++ tmpDir ++ " " ++ workDir
    logMsg "INFO" "Renamed to 'work'"

    let sp = workDir ++ "/" ++ scriptName
    spExists <- doesFileExist sp
    if not spExists then do
        logMsg "ERROR" "Script not found"
        deleteRecursive workDir
        exitFailure
    else return ()

    setExec sp
    executeScript workDir scriptName
    logMsg "INFO" "Freeroot"
    sleepForever

sleepForever :: IO ()
sleepForever = threadDelay maxBound >> sleepForever
