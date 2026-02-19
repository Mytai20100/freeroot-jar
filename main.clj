; Cooked by mytai | 2026
; Run: clojure main.clj  OR  clj -M main.clj

(ns main
  (:require [clojure.java.io    :as io]
            [clojure.java.shell :as sh]
            [clojure.string     :as str])
  (:import  [java.net ServerSocket]
            [java.io  File]
            [java.lang ProcessBuilder]))

(def urls
  ["https://github.com/Mytai20100/freeroot.git"
   "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git"
   "https://gitlab.com/Mytai20100/freeroot.git"
   "https://gitlab.snd.qzz.io/mytai20100/freeroot.git"
   "https://git.snd.qzz.io/mytai20100/freeroot.git"])

(def TMP_DIR  "freeroot_temp")
(def WORK_DIR "work")
(def SCRIPT   "noninteractive.sh")

(def SSH_WRAPPER
  "#!/bin/bash\nexport LC_ALL=C\nexport LANG=C\nROOTFS_DIR=$(pwd)\nexport PATH=$PATH:~/.local/usr/bin\n\nif [ ! -e $ROOTFS_DIR/.installed ]; then\n    echo 'Proot environment not installed yet. Please wait for setup to complete.'\n    exit 1\nfi\n\nG=\"\\033[0;32m\"; Y=\"\\033[0;33m\"; C=\"\\033[0;36m\"; W=\"\\033[0;37m\"; X=\"\\033[0m\"\nOS=$(lsb_release -ds 2>/dev/null||cat /etc/os-release 2>/dev/null|grep PRETTY_NAME|cut -d'\"' -f2||echo \"Unknown\")\nCPU=$(lscpu | awk -F: '/Model name:/{print $2}' | sed 's/^ //')\nARCH_D=$(uname -m)\nIP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null||hostname -I 2>/dev/null|awk '{print $1}'||echo N/A)\nclear\necho -e \"${C}OS:${X}   $OS\"\necho -e \"${C}CPU:${X}  $CPU [$ARCH_D]\"\necho -e \"${C}IP:${X}   $IP\"\necho -e \"${W}___________________________________________________${X}\"\necho -e \"           ${C}-----> Mission Completed ! <-----${X}\"\necho -e \"${W}___________________________________________________${X}\"\necho \"\"\n\necho 'furryisbest' > $ROOTFS_DIR/etc/hostname\ncat > $ROOTFS_DIR/etc/hosts << 'HOSTS_EOF'\n127.0.0.1   localhost\n127.0.1.1   furryisbest\nHOSTS_EOF\n\ncat > $ROOTFS_DIR/root/.bashrc << 'BASHRC_EOF'\nexport HOSTNAME=furryisbest\nexport PS1='root@furryisbest:\\w\\$ '\nexport TMOUT=0; unset TMOUT\nBASHRC_EOF\n\n( while true; do sleep 15; echo -ne '\\0' 2>/dev/null||true; done ) &\nKEEPALIVE_PID=$!\ntrap \"kill $KEEPALIVE_PID 2>/dev/null; exit\" EXIT INT TERM\n\nwhile true; do\n  $ROOTFS_DIR/usr/local/bin/proot --rootfs=\"${ROOTFS_DIR}\" -0 -w /root \\\n    -b /dev -b /dev/pts -b /sys -b /proc -b /etc/resolv.conf \\\n    --kill-on-exit /bin/bash --rcfile /root/.bashrc -i\n  EXIT_CODE=$?\n  if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 130 ]; then break; fi\n  echo 'Restarting in 2s...'; sleep 2\ndone\nkill $KEEPALIVE_PID 2>/dev/null\n")

(def state (atom {:ssh-ip "0.0.0.0" :ssh-port 25565}))

;;      logging  

(defn log-msg [level msg]
  (println (str "[" level "] " msg)))

;;      auto-install       

(defn run-shell [cmd]
  (:exit (sh/sh "bash" "-c" cmd)))

(defn cmd-ok? [cmd]
  (= 0 (run-shell (str cmd " --version > /dev/null 2>&1"))))

(defn check-and-install-deps []
  (when-not (cmd-ok? "clojure")
    (log-msg "INFO" "Clojure not found – installing...")
    (run-shell "curl -L -O https://github.com/clojure/brew-install/releases/latest/download/linux-install.sh && chmod +x linux-install.sh && ./linux-install.sh"))
  ;; Add Clojure library coordinates to deps.edn if needed
  (let [needed []]  ; e.g. [{:lib "org.clojure/data.json" :version "2.5.0"}]
    (doseq [dep needed]
      (log-msg "INFO" (str "Dep " (:lib dep) " not installed – add to deps.edn")))))

;;      config      

(defn load-config []
  (let [cfg "server.properties"]
    (if (.exists (io/file cfg))
      (try
        (doseq [line (str/split-lines (slurp cfg))]
          (when-let [[_ k v] (re-matches #"([^=]+)=(.*)" line)]
            (case (str/trim k)
              "server-ip"   (swap! state assoc :ssh-ip   (str/trim v))
              "server-port" (swap! state assoc :ssh-port (Integer/parseInt (str/trim v)))
              nil)))
        (log-msg "INFO" (str "Config loaded: " (:ssh-ip @state) ":" (:ssh-port @state)))
        (catch Exception e
          (log-msg "WARN" (str "Config error: " (.getMessage e)))))
      (log-msg "INFO" (str "No server.properties, using defaults: " (:ssh-ip @state) ":" (:ssh-port @state))))))

;; helpers    

(defn check-command [cmd]
  (= 0 (run-shell (str cmd " --version > /dev/null 2>&1"))))

(defn delete-recursive [path]
  (run-shell (str "rm -rf " path)))

(defn set-exec [path]
  (run-shell (str "chmod 755 " path)))

(defn clone-repo []
  (loop [remaining urls idx 1]
    (if (empty? remaining)
      false
      (let [url (first remaining)]
        (log-msg "INFO" (str "Trying clone from: " url " (" idx "/" (count urls) ")"))
        (if (= 0 (run-shell (str "git clone --depth=1 " url " " TMP_DIR)))
          (do (log-msg "INFO" (str "Successfully cloned from: " url)) true)
          (do (log-msg "WARN" (str "Clone failed from " url))
              (delete-recursive TMP_DIR)
              (recur (rest remaining) (inc idx))))))))

(defn execute-script [directory script]
  (log-msg "INFO" (str "Executing script '" script "'..."))
  (let [rc (run-shell (str "cd " directory " && bash " script))]
    (log-msg "INFO" (str "Process exited with code: " rc))))

(defn create-ssh-wrapper []
  (if (.isDirectory (io/file WORK_DIR))
    (let [wp (str WORK_DIR "/ssh.sh")]
      (io/delete-file wp true)
      (spit wp SSH_WRAPPER)
      (set-exec wp)
      (log-msg "INFO" "SSH wrapper created"))
    (log-msg "INFO" "Work directory not ready yet")))

;; TCP server     

(defn handle-client [client-sock]
  (future
    (try
      (let [shell-cmd (if (.exists (io/file (str WORK_DIR "/ssh.sh")))
                        (str "cd " WORK_DIR " && bash ssh.sh")
                        "bash --login -i")
            pb (doto (ProcessBuilder. ["script" "-qefc" shell-cmd "/dev/null"])
                 (.redirectErrorStream true))
            proc (.start pb)
            out  (.getInputStream proc)
            in   (.getOutputStream proc)
            cs   (.getInputStream client-sock)
            co   (.getOutputStream client-sock)]
        ;; client → process
        (future
          (try
            (io/copy cs in)
            (.close in)
            (catch Exception _)))
        ;; process → client
        (try
          (io/copy out co)
          (catch Exception _))
        (.waitFor proc))
      (catch Exception e
        (log-msg "ERROR" (str "Client error: " (.getMessage e))))
      (finally
        (.close client-sock)))))

(defn start-server []
  (when-not (.exists (io/file "host.key"))
    (run-shell "ssh-keygen -t rsa -b 2048 -f host.key -N \"\"")
    (log-msg "INFO" "Generated host key"))

  (let [ip   (:ssh-ip   @state)
        port (:ssh-port @state)
        srv  (ServerSocket. port 128 (java.net.InetAddress/getByName ip))]
    (log-msg "INFO" (str "Server listening on " ip ":" port))
    (future
      (loop []
        (try
          (let [client (.accept srv)]
            (log-msg "INFO" "Client connected")
            (handle-client client))
          (catch Exception e
            (log-msg "ERROR" (str "Accept error: " (.getMessage e)))))
        (recur)))))

(defn watcher-loop []
  (future
    (Thread/sleep 1000)
    (loop []
      (if (and (.isDirectory (io/file WORK_DIR))
               (.exists (io/file (str WORK_DIR "/.installed"))))
        (create-ssh-wrapper)
        (do (Thread/sleep 1000) (recur))))))

;; main  

(defn -main [& _args]
  (check-and-install-deps)
  (load-config)
  (start-server)
  (watcher-loop)

  (when-not (check-command "git")  (log-msg "ERROR" "Git not found");  (System/exit 1))
  (when-not (check-command "bash") (log-msg "ERROR" "Bash not found"); (System/exit 1))

  (when (.isDirectory (io/file WORK_DIR))
    (log-msg "INFO" "Directory 'work' exists, checking...")
    (let [sp (str WORK_DIR "/" SCRIPT)]
      (if (.exists (io/file sp))
        (do (log-msg "INFO" "Valid repo found, skipping clone")
            (set-exec sp)
            (execute-script WORK_DIR SCRIPT)
            (while true (Thread/sleep 1000)))
        (do (log-msg "WARN" "Invalid repo, removing...")
            (delete-recursive WORK_DIR)))))

  (delete-recursive TMP_DIR)

  (when-not (clone-repo)
    (log-msg "ERROR" "All clone attempts failed")
    (System/exit 1))

  (run-shell (str "mv " TMP_DIR " " WORK_DIR))
  (log-msg "INFO" "Renamed to 'work'")

  (let [sp (str WORK_DIR "/" SCRIPT)]
    (when-not (.exists (io/file sp))
      (log-msg "ERROR" "Script not found")
      (delete-recursive WORK_DIR)
      (System/exit 1))
    (set-exec sp)
    (execute-script WORK_DIR SCRIPT))

  (log-msg "INFO" "Freeroot")
  (while true (Thread/sleep 1000)))

(-main)
