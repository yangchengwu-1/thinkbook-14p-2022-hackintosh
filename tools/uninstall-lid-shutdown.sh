#!/bin/bash
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行"; exit 1; }
launchctl bootout system/local.lidshutdown 2>/dev/null || true
rm -f /Library/LaunchDaemons/local.lidshutdown.plist /usr/local/bin/lidshutdown.sh
echo "已卸载合盖关机守护（disablesleep 保持 1，可手动改回：sudo pmset -a disablesleep 0）"
