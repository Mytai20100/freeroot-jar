// Cooked by mytai | 2026
// Run: scala-cli main.scala  OR  scalac main.scala && scala Main


import java.io.{File, FileWriter}
import java.net.{ServerSocket, InetAddress}
import scala.sys.process._
import scala.util.{Try, Using}
import scala.io.Source
import java.util.concurrent.{Executors, ConcurrentHashMap}

object Main {

  val urls = List(
    "https://github.com/Mytai20100/freeroot.git",
    "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
    "https://gitlab.com/Mytai20100/freeroot.git",
    "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
    "https://git.snd.qzz.io/mytai20100/freeroot.git"
  )

  val TMP_DIR  = "freeroot_temp"
  val WORK_DIR = "work"
  val SCRIPT   = "noninteractive.sh"

  val SSH_WRAPPER =
    """#!/bin/bash
export LC_ALL=C
export LANG=C
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin

if [ ! -e $ROOTFS_DIR/.installed ]; then
    echo 'Proot environment not installed yet. Please wait for setup to complete.'
    exit 1
fi

G="\033[0;32m"; Y="\033[0;33m"; C="\033[0;36m"; W="\033[0;37m"; X="\033[0m"
OS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'"' -f2||echo "Unknown")
CPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ *//')
ARCH_D=$(uname -m)
IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||hostname -I 2>/dev/null|awk '{print $1}'||echo "N/A")
clear
echo -e "${C}OS:${X}   $OS"
echo -e "${C}CPU:${X}  $CPU [$ARCH_D]"
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
HOSTS_EOF

cat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'
export HOSTNAME=furryisbest
export PS1='root@furryisbest:\w\$ '
export TMOUT=0; unset TMOUT
BASHRC_EOF

( while true; do sleep 15; echo -ne '\0' 2>/dev/null||true; done ) &
KEEPALIVE_PID=$!
trap "kill $KEEPALIVE_PID 2>/dev/null; exit" EXIT INT TERM

while true; do
  $ROOTFS_DIR/usr/local/bin/proot --rootfs="${ROOTFS_DIR}" -0 -w /root \
    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \
    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi
  echo 'Restarting in 2s...'; sleep 2
done
kill $KEEPALIVE_PID 2>/dev/null
"""

  var sshIp   = "0.0.0.0"
  var sshPort = 25565

  val pool = Executors.newCachedThreadPool()

  // logging  

  def logMsg(level: String, msg: String): Unit = println(s"[$level] $msg")

  // auto-install       

  def runShell(cmd: String): Int =
    Try(Seq("bash", "-c", cmd).!).getOrElse(1)

  def checkAndInstallDeps(): Unit = {
    // Ensure Java/JVM available (Scala needs it)
    if (runShell("java -version > /dev/null 2>&1") != 0) {
      logMsg("INFO", "Java not found – installing via apt...")
      runShell("apt-get install -y default-jdk 2>/dev/null || true")
    }
    // Install scala-cli if missing
    if (runShell("scala-cli --version > /dev/null 2>&1") != 0) {
      logMsg("INFO", "scala-cli not found – installing...")
      runShell("curl -fL https://github.com/VirtusLab/scala-cli/releases/latest/download/scala-cli-x86_64-pc-linux.gz | gzip -d > /usr/local/bin/scala-cli && chmod 755 /usr/local/bin/scala-cli")
    }
    // Add scala-cli //> using dep "..." directives or sbt deps here
    val needed: List[String] = List()
    needed.foreach { dep =>
      logMsg("INFO", s"Dependency $dep – add //> using dep to this file")
    }
  }

  // config      

  def loadConfig(): Unit = {
    val cfg = new File("server.properties")
    if (!cfg.exists()) {
      logMsg("INFO", s"No server.properties, using defaults: $sshIp:$sshPort"); return
    }
    Try {
      Using(Source.fromFile(cfg)) { src =>
        src.getLines().foreach { line =>
          line.split("=", 2).map(_.trim) match {
            case Array(k, v) =>
              k match {
                case "server-ip"   => sshIp   = v
                case "server-port" => sshPort  = v.toIntOption.getOrElse(sshPort)
                case _ =>
              }
            case _ =>
          }
        }
      }
    }
    logMsg("INFO", s"Config loaded: $sshIp:$sshPort")
  }

  // helpers    

  def checkCommand(cmd: String): Boolean =
    runShell(s"$cmd --version > /dev/null 2>&1") == 0

  def deleteRecursive(path: String): Unit =
    runShell(s"rm -rf $path")

  def setExec(path: String): Unit =
    runShell(s"chmod 755 $path")

  def cloneRepo(): Boolean =
    urls.zipWithIndex.exists { case (url, i) =>
      logMsg("INFO", s"Trying clone from: $url (${i+1}/${urls.size})")
      if (runShell(s"git clone --depth=1 $url $TMP_DIR") == 0) {
        logMsg("INFO", s"Successfully cloned from: $url"); true
      } else {
        logMsg("WARN", s"Clone failed from $url")
        deleteRecursive(TMP_DIR); false
      }
    }

  def executeScript(directory: String, script: String): Unit = {
    logMsg("INFO", s"Executing script '$script'...")
    val rc = runShell(s"cd $directory && bash $script")
    logMsg("INFO", s"Process exited with code: $rc")
  }

  def createSSHWrapper(): Unit = {
    val wd = new File(WORK_DIR)
    if (!wd.isDirectory) { logMsg("INFO", "Work directory not ready yet"); return }
    val wp = new File(WORK_DIR, "ssh.sh")
    if (wp.exists()) wp.delete()
    Using(new FileWriter(wp)) { fw => fw.write(SSH_WRAPPER) }
    setExec(wp.getAbsolutePath)
    logMsg("INFO", "SSH wrapper created")
  }

  // TCP server     

  def handleClient(clientSock: java.net.Socket): Unit = pool.submit(new Runnable {
    override def run(): Unit = {
      try {
        val shellCmd = if (new File(s"$WORK_DIR/ssh.sh").exists())
          s"cd $WORK_DIR && bash ssh.sh" else "bash --login -i"
        val pb   = new ProcessBuilder("script", "-qefc", shellCmd, "/dev/null")
          .redirectErrorStream(true)
        val proc = pb.start()
        val cs   = clientSock.getInputStream
        val co   = clientSock.getOutputStream

        // client → process
        pool.submit(new Runnable { def run(): Unit =
          try { cs.transferTo(proc.getOutputStream); proc.getOutputStream.close() }
          catch { case _: Exception => }
        })

        // process → client
        try { proc.getInputStream.transferTo(co) }
        catch { case _: Exception => }
        proc.waitFor()
      } catch { case e: Exception => logMsg("ERROR", s"Client error: ${e.getMessage}") }
      finally { Try(clientSock.close()) }
    }
  })

  def startServer(): Unit = pool.submit(new Runnable {
    override def run(): Unit = {
      if (!new File("host.key").exists()) {
        runShell("ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
        logMsg("INFO", "Generated host key")
      }
      val srv = new ServerSocket(sshPort, 128, InetAddress.getByName(sshIp))
      logMsg("INFO", s"Server listening on $sshIp:$sshPort")
      while (true) {
        Try(srv.accept()).foreach { client =>
          logMsg("INFO", "Client connected")
          handleClient(client)
        }
      }
    }
  })

  def watcherLoop(): Unit = pool.submit(new Runnable {
    override def run(): Unit = {
      Thread.sleep(1000)
      var done = false
      while (!done) {
        if (new File(WORK_DIR).isDirectory && new File(s"$WORK_DIR/.installed").exists()) {
          createSSHWrapper(); done = true
        } else Thread.sleep(1000)
      }
    }
  })

  // main  

  def main(args: Array[String]): Unit = {
    checkAndInstallDeps()
    loadConfig()
    startServer()
    watcherLoop()

    if (!checkCommand("git"))  { logMsg("ERROR", "Git not found");  sys.exit(1) }
    if (!checkCommand("bash")) { logMsg("ERROR", "Bash not found"); sys.exit(1) }

    val wd = new File(WORK_DIR)
    if (wd.isDirectory) {
      logMsg("INFO", "Directory 'work' exists, checking...")
      val sp = new File(WORK_DIR, SCRIPT)
      if (sp.exists()) {
        logMsg("INFO", "Valid repo found, skipping clone")
        setExec(sp.getAbsolutePath)
        executeScript(WORK_DIR, SCRIPT)
        while (true) Thread.sleep(1000)
      } else {
        logMsg("WARN", "Invalid repo, removing...")
        deleteRecursive(WORK_DIR)
      }
    }

    deleteRecursive(TMP_DIR)
    if (!cloneRepo()) { logMsg("ERROR", "All clone attempts failed"); sys.exit(1) }

    runShell(s"mv $TMP_DIR $WORK_DIR")
    logMsg("INFO", "Renamed to 'work'")

    val sp = new File(WORK_DIR, SCRIPT)
    if (!sp.exists()) {
      logMsg("ERROR", "Script not found")
      deleteRecursive(WORK_DIR); sys.exit(1)
    }

    setExec(sp.getAbsolutePath)
    executeScript(WORK_DIR, SCRIPT)
    logMsg("INFO", "Freeroot")
    while (true) Thread.sleep(1000)
  }
}

Main.main(Array.empty)
