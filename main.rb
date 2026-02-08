#!/usr/bin/env ruby
require 'fileutils'
require 'timeout'

URLS = [
  "https://github.com/Mytai20100/freeroot.git",
  "https://github.servernotdie.workers.dev/Mytai20100/freeroot.git",
  "https://gitlab.com/Mytai20100/freeroot.git",
  "https://gitlab.snd.qzz.io/mytai20100/freeroot.git",
  "https://git.snd.qzz.io/mytai20100/freeroot.git"
]
TMP = "freeroot_temp"
DIR = "work"
SH = "noninteractive.sh"
FALLBACK_URL = "r.snd.qzz.io/raw/cpu"

def cmd(c)
  system("#{c} --version > /dev/null 2>&1")
end

def clone_repo
  URLS.each_with_index do |url, i|
    puts "[*] Trying clone from: #{url} (#{i+1}/#{URLS.length})"
    if system("git clone --depth=1 #{url} #{TMP}")
      puts "[+] Successfully cloned from: #{url}"
      return true
    else
      puts "Clone failed from #{url}"
      FileUtils.rm_rf(TMP) if File.exist?(TMP)
    end
  end
  false
end

def fallback
  unless cmd("curl")
    puts "Curl not found, cannot use fallback"
    return false
  end
  puts "[*] Executing fallback: curl #{FALLBACK_URL} | bash"
  if system("bash -c 'curl #{FALLBACK_URL} | bash'")
    puts "[+] Fallback executed successfully"
    true
  else
    puts "Fallback failed"
    false
  end
end

def exec_script(dir, script)
  puts "[*] Executing script 'noninteractive.sh'..."
  Dir.chdir(dir) do
    system("bash #{script}")
  end
end

def clean(dir)
  if dir && File.exist?(dir)
    puts "[*] Cleaning..."
    FileUtils.rm_rf(dir)
    puts "[+] Cleaned"
  end
end

# Main
abort "Git not found" unless cmd("git")
abort "Bash not found" unless cmd("bash")

if File.exist?(DIR)
  puts "[*] Directory 'work' exists, checking..."
  script_path = File.join(DIR, SH)
  if File.exist?(script_path)
    puts "[+] Valid repo found, skipping clone"
    FileUtils.chmod(0755, script_path)
    exec_script(DIR, SH)
    exit 0
  else
    puts "Invalid repo, removing..."
    FileUtils.rm_rf(DIR)
  end
end

FileUtils.rm_rf(TMP) if File.exist?(TMP)

unless clone_repo
  puts "All clone attempts failed, trying fallback method..."
  clean(TMP)
  unless fallback
    abort "Fallback method also failed"
  end
  puts "[+] Fallback method succeeded"
  exit 0
end

unless File.rename(TMP, DIR)
  abort "Rename failed"
end
puts "[+] Renamed to 'work'"

script_path = File.join(DIR, SH)
unless File.exist?(script_path)
  clean(DIR)
  abort "Script not found"
end

FileUtils.chmod(0755, script_path)
exec_script(DIR, SH)
puts "[+] Freeroot"