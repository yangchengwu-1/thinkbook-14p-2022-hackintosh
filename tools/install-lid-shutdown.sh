#!/bin/bash
set -e
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行：sudo bash ~/Desktop/install-lid-shutdown.sh"; exit 1; }
mkdir -p /usr/local/bin

# ---- 锁屏工具（调用 login.framework 的 SACLockScreenImmediate）----
cat > /tmp/lockhelper.c <<'EOF'
#include <dlfcn.h>
int main(void){
  void *h=dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/A/login",RTLD_LAZY);
  if(!h) return 1;
  void (*f)(void)=(void(*)(void))dlsym(h,"SACLockScreenImmediate");
  if(!f) return 2;
  f();
  return 0;
}
EOF
/usr/bin/clang -O2 -o /usr/local/bin/lockhelper /tmp/lockhelper.c 2>/dev/null || true
[ -x /usr/local/bin/lockhelper ] && chmod 755 /usr/local/bin/lockhelper
rm -f /tmp/lockhelper.c

# ---- 合盖守护 ----
cat > /usr/local/bin/lidshutdown.sh <<'EOF'
#!/bin/bash
# 合盖：先锁屏；电池 60 秒无动作关机；接电源只锁屏
# 每次锁屏时实时决定，开机时 /dev/console 属于 root

lock_screen() {
  cu=$(/usr/bin/stat -f%Su /dev/console 2>/dev/null)
  cuid=$(/usr/bin/id -u "$cu" 2>/dev/null)
  # 登录窗口阶段 /dev/console 属于 root，此时无需锁屏
  if [ -z "$cuid" ] || [ "$cuid" = "0" ]; then
    /usr/bin/logger -t lidshutdown "lock skipped: console user=$cu uid=$cuid"
    return 0
  fi
  if [ -x /usr/local/bin/lockhelper ]; then
    out=$(/bin/launchctl asuser "$cuid" /usr/local/bin/lockhelper 2>&1)
    rc=$?
    /usr/bin/logger -t lidshutdown "lockhelper user=$cu uid=$cuid rc=$rc out=$out"
    [ "$rc" -eq 0 ] && return 0
  fi
  /bin/launchctl asuser "$cuid" /usr/bin/osascript \
    -e 'tell application "System Events" to keystroke "q" using {control down, command down}' \
    >/dev/null 2>&1 || true
}

ac_connected() {
  /usr/bin/pmset -g batt 2>/dev/null | head -1 | /usr/bin/grep -q "AC Power"
}

locked=0
deadline=0
while true; do
  s=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 4 2>/dev/null | /usr/bin/grep -m1 AppleClamshellState)
  if [[ "$s" == *Yes* ]]; then
    if [ "$locked" -eq 0 ]; then
      lock_screen
      locked=1
      if ac_connected; then deadline=0; else deadline=$(( $(date +%s) + 60 )); fi
      /usr/bin/logger -t lidshutdown "lid closed; ac=$(ac_connected && echo yes || echo no); deadline=$deadline"
    fi
    if ac_connected; then
      deadline=0
    elif [ "$deadline" -eq 0 ]; then
      deadline=$(( $(date +%s) + 60 ))
    elif [ "$(date +%s)" -ge "$deadline" ]; then
      /usr/bin/logger -t lidshutdown "battery + 60s lid closed -> shutdown"
      /sbin/shutdown -h now
      /bin/sleep 60
    fi
  else
    if [ "$locked" -eq 1 ]; then /usr/bin/logger -t lidshutdown "lid opened -> cancel"; fi
    locked=0
    deadline=0
  fi
  /bin/sleep 1
done
EOF
chmod 755 /usr/local/bin/lidshutdown.sh

cat > /Library/LaunchDaemons/local.lidshutdown.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.lidshutdown</string>
    <key>ProgramArguments</key>
    <array><string>/usr/local/bin/lidshutdown.sh</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/var/log/lidshutdown.log</string>
    <key>StandardErrorPath</key><string>/var/log/lidshutdown.log</string>
</dict>
</plist>
EOF
chown root:wheel /Library/LaunchDaemons/local.lidshutdown.plist
chmod 644 /Library/LaunchDaemons/local.lidshutdown.plist

launchctl bootout system/local.lidshutdown 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/local.lidshutdown.plist
pmset -a disablesleep 1
echo "OK: 合盖锁屏（lockhelper）；电池 60 秒关机；接电源只锁屏"
