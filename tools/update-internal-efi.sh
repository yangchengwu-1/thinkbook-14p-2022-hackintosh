#!/bin/bash
set -e
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行：sudo bash ~/Desktop/update-internal-efi.sh"; exit 1; }

SRC="/Volumes/KINGSTON/EFI"
[ -d "$SRC/OC" ] || { echo "错误：U 盘 EFI 不在 $SRC（U 盘插好了吗？）"; exit 1; }

# 自动识别三星 980 PRO 的 ESP：标签为 "EFI"（Windows 的 ESP 标签是 SYSTEM_DRV）
DISK=$(diskutil list 2>/dev/null | awk '/EFI +EFI/ {print $NF; exit}')
[ -n "$DISK" ] || { echo "错误：找不到标签为 EFI 的分区"; diskutil list; exit 1; }
echo "目标分区: $DISK"

INFO=$(diskutil info "$DISK" 2>/dev/null)
echo "$INFO" | grep -q 'NTFS' && { echo "错误：$DISK 是 NTFS，中止"; exit 1; }

diskutil mount "$DISK" >/dev/null 2>&1 || true
DST=$(echo "$INFO" | awk -F': *' '/Mount Point:/{print $2}' | tr -d ' ')
if [ -z "$DST" ] || [ ! -d "$DST" ]; then
  INFO=$(diskutil info "$DISK" 2>/dev/null)
  DST=$(echo "$INFO" | awk -F': *' '/Mount Point:/{print $2}' | tr -d ' ')
fi
[ -n "$DST" ] && [ -d "$DST" ] || { echo "错误：无法挂载 $DISK"; exit 1; }
echo "挂载点: $DST"

if [ -d "$DST/EFI" ]; then
  BAK="$DST/EFI-backup-$(date +%Y%m%d-%H%M%S)"
  mv "$DST/EFI" "$BAK"
  echo "旧 EFI 已备份到: $BAK"
fi

cp -R "$SRC" "$DST/EFI"
sync
echo ""
echo "=== 同步完成 ==="
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DST/EFI/OC/Kexts/WhateverXe.kext/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DST/EFI/OC/Kexts/SimpleHDA.kext/Contents/Info.plist" 2>/dev/null && echo "SimpleHDA OK"
python3 -c "
import plistlib
d=plistlib.load(open('$DST/EFI/OC/config.plist','rb'))
print('S3 disabled:', [x['Enabled'] for x in d['ACPI']['Patch'] if x.get('Comment','').startswith('_S3')])
print('boot-args:', d['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']['boot-args'][:90])
"
echo ""
echo "完成。重启 F12 选三星盘；确认后拔掉 U 盘。"
