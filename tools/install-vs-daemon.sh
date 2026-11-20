#!/bin/bash
set -e
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行"; exit 1; }
cp /Users/yangwucheng/Desktop/voltageshift/voltageshift /usr/local/bin/voltageshift
chmod +x /usr/local/bin/voltageshift
cat > /usr/local/bin/vs-apply-power.sh <<'EOF'
#!/bin/bash
/usr/local/bin/voltageshift power 45 45 >/var/log/vs-power.log 2>&1
EOF
chmod +x /usr/local/bin/vs-apply-power.sh
cat > /Library/LaunchDaemons/local.voltageshift-power.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.voltageshift-power</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/vs-apply-power.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>60</integer>
</dict>
</plist>
