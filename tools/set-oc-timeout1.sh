#!/bin/bash
set -e
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行：sudo bash ~/Desktop/set-oc-timeout1.sh"; exit 1; }
DISK=$(diskutil list 2>/dev/null | awk '/EFI +EFI/ {print $NF; exit}')
[ -n "$DISK" ] || { echo "找不到 EFI 分区"; exit 1; }
diskutil mount "$DISK" >/dev/null 2>&1 || true
DST=$(diskutil info "$DISK" | awk -F': *' '/Mount Point:/{print $2}' | tr -d ' ')
[ -n "$DST" ] && [ -d "$DST/EFI" ] || { echo "挂载失败"; exit 1; }
CFG="$DST/EFI/OC/config.plist"
cp "$CFG" "$CFG.bak-timeout1"
python3 - "$CFG" <<'PY'
import plistlib,sys
p=sys.argv[1]
d=plistlib.load(open(p,'rb'))
b=d['Misc']['Boot']
b['ShowPicker']=True
b['Timeout']=1
open(p,'wb').write(plistlib.dumps(d))
print("ShowPicker:",b['ShowPicker'],"Timeout:",b['Timeout'],"HideAuxiliary:",b['HideAuxiliary'])
PY
sync
echo "完成：菜单显示 1 秒后自动启动默认项（MAC）"
