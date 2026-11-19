# ThinkBook 14+ 2022（i5-12500H）黑苹果记录 — macOS 26 Tahoe + WhateverXe

> 记录日期：2026-11-13
> 结果：**可用**（内屏 2880×1800@90Hz + Metal 2 + 亮度 + 声音 + Wi-Fi + 合盖锁屏/关机）
> 不可用：蓝牙、S3 睡眠

---

## 0. 机器

| 项目 | 内容 |
|---|---|
| 机型 | 联想 ThinkBook 14+ 2022（i5-12500H 核显版） |
| CPU | Intel Core i5-12500H（4P+8E，12 核 16 线程） |
| 核显 | Intel Iris Xe 80EU，`8086:46A6`，rev `0x0C` |
| 内存 | 16 GB DDR5-4800 |
| 屏幕 | 2880×1800 eDP，90 Hz（DDI A / AUX A） |
| 声卡 | `8086:51C8`（Alder Lake-P HDA） |
| 网卡 | Realtek **RTL8852BE**（Wi-Fi 6 + BT 5.2，M.2 2230） |
| 硬盘 | Samsung 980 PRO 500GB（macOS）+ Kingston 1TB（Windows/Data） |
| 系统 | macOS 26.7.3 (25G342) / Darwin 25.6.0 |
| 引导 | OpenCore + SMBIOS `MacBookPro16,1` |

---

## 1. 最终结果

| 功能 | 状态 | 实现 |
|---|---|---|
| 内屏 2880×1800 @ 90Hz | ✅ | WhateverXe **0.8.3** + 3 个本地补丁 + Graphics 0.4.4 |
| Metal 2 / 1536 MB | ✅ | 同上 |
| 亮度（键盘 16 级） | ✅ | SSDT-PNLF（`_UID=19`）+ BrightnessKeys 1.0.3 |
| 声音（扬声器/耳机/麦克风） | ✅ | SimpleHDA 1.0.1 + AppleALC 1.9.8 |
| Wi-Fi（2.4G/5G，802.11ax） | ✅ | AirportRTW 2.3.1 |
| 合盖锁屏 | ✅ | 自定义 LaunchDaemon + login.framework 私有 API |
| 显示器睡眠/唤醒 | ✅ | WEX issue #22 修复 6（`wrapDisplay13FBIRQ` 唤醒分支） |
| 电池合盖 60 秒自动关机 | ✅ | 同上 |
| 蓝牙 | ❌ | Realtek 无驱动 |
| S3 睡眠 | ❌ | WEX 驱动缺陷（见 §6） |
| HDMI / USB-C 视频 | ❌ | `-wex-panel-only` 只保留内屏 |

---

## 2. 软件栈

| 组件 | 版本 |
|---|---|
| WhateverXe | **0.8.3** + 3 处本地补丁（P1/P2/P4，P3 已并入上游）+ gamma 1.8 背光曲线（自编译） |
| WhateverXe Graphics | **0.4.4**（内含 `AppleIntelTGLCompat` 0.8.1） |
| AirportRTW | **2.3.1** |
| AppleALC | **1.9.8** |
| SimpleHDA | **1.0.1** |
| BrightnessKeys | 1.0.3 |
| Lilu | 1.7.2 |
| AMFIPass | 1.4.1 **Mod**（不能换成上游版） |
| RestrictEvents | 1.1.3 |
| SSDT-PNLF | 自建 90 字节（`APP0002` / `_CID="backlight"` / `_UID=0x13`） |

---

## 3. config.plist 关键项

```
boot-args: alcid=99 -vi2c-force-polling -allow3d -disablegfxfirmware
           -igfxdvmt -wex-panel-only
           revpatch=cpuname revcpu=1 revcpuname=i5-12500H

csr-active-config = 03080000 (0x803)
SMBIOS            = MacBookPro16,1

Kernel → Quirks
  DisableLinkeditJettison = true      ← SimpleHDA 必需
  DisableRtcChecksum      = true
  AppleXcpmCfgLock        = true
  AppleCpuPmCfgLock       = true

Misc → Boot
  ShowPicker     = false              ← 不显示菜单，直接进默认项
  Timeout        = 0
  HideAuxiliary  = true
  HibernateMode  = None
  ConsoleAttributes = 15              ← 黑底白字

DeviceProperties  PciRoot(0x0)/Pci(0x2,0x0)
  framebuffer-patch-enable = 01000000
  framebuffer-stolenmem    = 0000C003   (60 MB DVMT)

ACPI
  SSDT-PNLF.aml            ← 亮度
  SSDT-NameS3-disable.aml  ← 禁 S3（配套合盖方案）
  Patch: _S3_ → XS3_
```

**重要**：`Misc → Boot → Timeout = 0` 在 OpenCore 里的语义是「**不超时、一直等用户选择**」，不是「立即启动」。要「不显示菜单直接启动」，必须同时设 `ShowPicker = false`。

---

## 4. 安装流程概览

1. OpenCore 基础配置：Lilu、VirtualSMC、AMFIPass、USBMap、VoodooI2C/PS2、SMBIOS `MacBookPro16,1`、`csr-active-config=0x803`
2. 放入 WhateverXe 0.8.3（**需先打 3 个本地补丁** P1/P2/P4，见 §5），加入 `-wex-panel-only`
3. 启动进入系统后安装 `WhateverXe-Graphics-0.4.4.pkg`，重启
4. 打亮度：`SSDT-PNLF.aml` + BrightnessKeys
5. 声音：AppleALC + SimpleHDA（顺序 Lilu → AppleALC → SimpleHDA）+ `DisableLinkeditJettison=true`
6. Wi-Fi：AirportRTW 2.3.1
7. 合盖方案：`tools/install-lid-shutdown.sh`

---

## 5. 四个本地补丁（内屏能亮的关键）

基于 WhateverXe 0.8.3，仓库根目录 `patch -p1`。完整 diff 见 `patches/WhateverXe-0.8.3-adlp-edp.patch`（P3 已由上游内置，0.8.3 起只需 P1/P2/P4 + gamma 曲线）。

### 5.1 症状与证据

原生代码下 GPU 被接纳，但内屏黑屏、只有帧缓冲：

```
0x60400 TRANS_DDI_FUNC_CTL  = 0x8a000106   ddi=A proto=eDP width=0 enabled=1
0x60404 TRANS_DDI_FUNC_CTL2 = 0x00000008   bit3 (CMTG_SECONDARY_MODE) = 1
0x64000 DDI_BUF_CTL_A       = 0x80000006   4 lanes
0x70188 STRIDE_A            = 0x000000b4   -> 11520 = 2880*4
0x70190 SIZE_A              = 2880x1800

N97NativeBootSource = (1, 0, 2, 11, 0)     // linearPlan 11 = InvalidDPSource
WEXDisplay13BootReady = No
```

GOP 交接时 eDP transcoder 的 bit3 被置位，`dpSource()` 因 `ctl2 != 0` 拒绝。

### 5.2 补丁 1 — `kern_alderlake_n.hpp` `dpSource()`

```diff
-        !(trans&((1U<<15)|(1U<<9))) && !ctl2 &&
+        !(trans&((1U<<15)|(1U<<9))) && !(ctl2&~(panel?(1U<<3):0U)) &&
```

### 5.3 补丁 2 — `kern_display13_fb_memory.hpp` `apertureRange()`

2880×1800×4 = 20,736,000 B，是 64 的倍数但不是 4096 的倍数，原生要求页对齐 → 拒绝。

```diff
-    return bytes && !(base&4095) && !(bytes&4095) && base>=p.base &&
-        uint64_t(base)+bytes<=uint64_t(p.base)+p.bytes && uint64_t(base)+bytes<=apertureBytes;
+    const uint64_t end=uint64_t(base)+((uint64_t(bytes)+4095)&~4095ULL);
+    return bytes && !(bytes&63) && !(base&4095) && base>=p.base &&
+        end<=uint64_t(p.base)+p.bytes && end<=apertureBytes;
```

### 5.4 补丁 3 — `kern_xe.cpp` `display13SSTPort()`

启动交接时 `port+0x550` 还是 0（原生 `setPortMode()` 尚未执行），原生要求 Combo 端口必须等于 1。

```diff
- ... 0x550)!=(config[0]>=3?((s->adlnOutputWiring.typeC&(1U<<config[0]))?3U:4U):1U) ||
+ ... (config[0]>=3? ...!=... : 0x550>1U) ||
```

### 5.5 补丁 4 — `kern_xe.cpp` `display13BoardWiring()`

打完前三个补丁后 framebuffer 能挂上，但模式设置失败：

```
[IGFB][ERROR][DISPLAY] FB0: Hardware mode set failed, err = 0xe00002d8
N97FBFirstResourceFault line=9306 (adlnSetDualClock, clockFaulted)
N97FBClockWMAll: active=0, inGate=0, acquired=0, writes=0, status=NotReady
N97FBClockWMAll[27] = 50 (retries), [8] = 0 (never acquired)
```

`adlnSetDualClock()` 调 `adlnWorkLoopTryClose()` 失败——workloop 已被调用方的 modeset 持有，重试 50×1ms 也拿不到。根因是多输出接线（HDMI/Type-C）让 `multiOutputWiring()` 为 true，走了需要 workloop 的双时钟路径。

```diff
-    if(!property)board=XELP::VBT::display13Fixed(firmwarePorts,Display13OutputWiring::Physical,xeProfile.family);
+    if(!property) {
+        board=XELP::VBT::display13Fixed(firmwarePorts,Display13OutputWiring::Physical,xeProfile.family);
+        if(checkKernelArgument("-wex-panel-only") && board.panel) {
+            board.dp=0; board.typeC=0; board.hdmi=0;
+            for(auto &pin:board.ddc) pin=0;
+        }
+    }
```

**关键坑**：只清 `dp/typeC/hdmi` 不够。`Display13OutputWiring::described()` 要求所有未被 HDMI 选中的端口 `ddc[d] == 0`，否则 `described()` 为 false、`supportedWiring()` 失败，驱动完全不接管（`N97NativeRoutingUnavailable=Yes`，19MB 固件帧缓冲）。

四个补丁后：`selected = 1`、`multiOutputWiring()=false`、`N97FBClockChange: Complete, 12 writes`、Metal 2 / 1536 MB。

---

## 6. 睡眠：为什么最终用「合盖锁屏/关机」

### 6.1 实测矩阵

| 配置 | 显示器睡眠 | 系统睡眠 S3 |
|---|---|---|
| WEX 0.8.0 | panic（IOSurface 自旋锁） | panic（IOAccel 内存池） |
| WEX 0.8.1 | 硬卡死 | 固件恢复失败 → 重启 |
| WEX 0.8.1 + `-wex-noaccel` | ✅ 正常 | 固件恢复失败 → 重启 |
| **完全去掉 WEX** | ✅ | ✅ 能睡能醒（无加速） |
| WEX 去掉电源钩子（自编译） | — | GPU 中断 spinlock panic |
| **WEX 0.8.3（P1/P2/P4 + gamma）** | **✅ 正常** | ❌ 固件恢复失败 → 重启 |

关键证据：

```
12:08:45  Entering Sleep state due to 'Software Sleep'
12:10:39  Failure during sleep: 0x0000001F : EFI/Bootrom Failure after last point of entry to sleep
→ 机器重启
```

去掉 WEX 后同一操作：显示灭 → 唤醒成功、启动时间不变（没有重启），但只有 19MB 固件帧缓冲、无 Metal、背光不灭。

去掉 WEX 电源钩子（`systemWakeRecovery=false`）后：睡眠时 panic 在

```
AppleIntelFramebufferController::ProcessInterrupt
 → WhateverXe::wrapDisplay13FBProcessIRQ
 → spinlock timeout
```

说明钩子是中断安全所必需，但钩子又破坏固件 S3 恢复——**驱动层缺陷，无配置可解**。上游 README 也写明睡眠仅验证过 MiniBook X（MIPI DSI），ADL-H eDP 未验证。

### 6.1.1 2026-11-13 更新：显示器睡眠已修复

应用 WEX issue #22 的修复 6（`wrapDisplay13FBIRQ` 单输出分支）后：

```
17:20:38 Display is turned off
17:20:41 Display is turned on     ← 无卡死、无 panic
```

修复原理：唤醒时原生驱动在 `enablePipe` 设置 PIPECONF **之前**就开中断，完整的 `enable(…,1)` 看到 0 个活动 pipe → `fail(Topology)`、master 关闭 → 收不到 vblank → WindowServer 看门狗。补丁让唤醒时先保持 hotplug-only，等 transcoder 真正运行后由 VBL 回调重新使能 pipe A。

但 **S3 系统睡眠仍然失败**：

```
17:23:38 Entering Sleep state due to 'Software Sleep'
17:26:09 Failure: 0x1F EFI/Bootrom Failure after last point of entry to sleep
```

说明显示管线唤醒已修好，固件级 S3 恢复仍然无解。合盖方案继续保留。

### 6.1.2 S0ix（Deep Idle）尝试

S3 固件恢复无解后，测试了 [S0ixStandby](https://github.com/labrouss/S0ixStandby)：让 macOS 睡在 XNU Deep Idle（S0ix）里，而不是 S3。详见 [docs/s0ix-deep-idle.md](docs/s0ix-deep-idle.md)。

| 配置 | 睡眠 | 唤醒 |
|---|---|---|
| WEX 加速 + `-s0ixgpureset` | ✅ | ❌ 显示回来但 UI 冻结（`IOAcceleratorFamily2` spinlock panic） |
| WEX 加速 + 无 `-s0ixgpureset` | ✅ | ❌ 背光亮、无图像（WEX `EL-null` panic） |
| **WEX 无加速** | ✅ | ✅ 干净唤醒（软件渲染） |
| 加速 + `-s0ixnodsm`（跳过显示 DSM） | ✅ | ❌ `thread_invoke` 调度器 panic |
| 加速 + 自编译 WEX（去 host 睡眠钩子） | ✅ | ❌ 唤醒冻结 |
| 加速 + 休眠（HibernationFixup + OC Auto） | ❌ 入口死锁（`IOAcceleratorFamily2`） | — |

结论：**只要 WEX 加速器参与，ADL-P 的 Deep Idle / 休眠转场就会死锁**（与 DSM、host 睡眠钩子无关）；无加速路径完全稳定。需要上游修改 WEX 加速器睡眠转场。

已报上游：**S0ixStandby #4**、**WhateverXe #117**。

### 6.2 采用的方案

1. `pmset -a disablesleep 1`：合盖不睡眠
2. LaunchDaemon `local.lidshutdown` 每秒检测 `AppleClamshellState`
3. 合盖瞬间：`lockhelper` 锁屏
4. 电池供电：合盖持续 60 秒且期间未接电源 → `shutdown -h now`
5. 外接电源：只锁屏，不关机
6. 60 秒内开盖/插电 → 取消

### 6.3 两个必须踩过的坑

**坑 A：不要用 `pmset displaysleepnow` 锁屏**

WEX 下显示器睡眠会挂死。合盖本身关屏没问题，是这条命令触发挂死。

**坑 B：锁屏工具必须投递到「当前登录用户」的图形会话**

- `/System/Library/CoreServices/Menu Extras/User.menu/.../CGSession` 在 macOS 26 已移除
- 可用 `login.framework` 私有符号 `SACLockScreenImmediate`（`lockhelper` 就是调它）
- 但必须 `launchctl asuser <当前登录用户 uid>` 执行；LaunchDaemon 系统域直接调用是空操作
- **uid 必须在每次合盖时实时获取**（`stat -f%Su /dev/console`），不能在守护进程启动时固定——开机时 `/dev/console` 属于 root，会导致 `lockhelper uid=0` 静默失败

---

## 7. 其他踩坑记录

### 7.1 亮度

- 无 `SSDT-PNLF` 时 `AppleBacklight` 不加载，亮度键完全无效
- **`_UID` 必须是 19**：WEX 只在 UID=19 时向 `ApplePanels` 注入面板曲线；改成 14 后 AppleBacklight 找不到配置，亮度键直接失效（实测）
- macOS 固定 16 级，每按一次 ±64/1024；日志实测提交值严格 `0.0625` 步进
- 曲线对比（同一台机器）：
  - WhateverGreen 通用曲线：低亮度细腻，但整体感知不均匀
  - 线性曲线：16 级等分，但**最亮 2–3 格几乎无法感知**
  - **最终采用 gamma 1.8 曲线**（17 点表 `65403*(i/16)^1.8`，编译进 WEX `kern_backlight_profile.hpp`）：16 级感知均匀，高亮度段仍有变化
- OSD 亮度条"先降后回抬"：用 `screencapture` 逐帧测过——轨道 469px、一格 29px，轨迹 `204→234`，刻度正好在 202/229，即**动画过冲正好一格**，实际亮度值不受影响；Reduce Motion 关不掉
- 音量同为 16 级×6.25，OSD 也是连续滑块，只是动画不出过冲，所以观感不同

### 7.2 声音

- **AppleHDA.kext 从 macOS 26 Tahoe beta 2 起被 Apple 移除**（支持 Tahoe 的 Mac 都有 T2）
- 因此**重装系统无法恢复声音**，安装包里也没有这个 kext
- 解决：`SimpleHDA` 是 Lilu 插件，通过 OpenCore 注入恢复 AppleHDA 栈，不改系统卷
- 必须：Lilu → AppleALC → SimpleHDA 顺序 + `DisableLinkeditJettison=true` + 唯一的 layout（`alcid=99`）

### 7.3 Wi-Fi

- RTL8852BE 用第三方 AirportRTW
- 2.3.0 存在 `airportd` 卡死：spindump 显示线程卡在 `Apple80211CopyValue → IOConnectCallStructMethod`，其他线程 `waiting for airportd`，导致关机 stall / 全系统卡死
- 升级 **2.3.1** 后缓解

### 7.4 蓝牙

- RTL8852BE 的蓝牙是 USB 设备（`0BDA:4853`），macOS 只有协议栈（IOBluetoothFamily），没有 Realtek 传输驱动
- 系统显示占位控制器：`BCM_4350C2` / `State: Off` / `Address: NULL`
- BlueToolFixup 无法解决（缺固件下载驱动）
- 可行方案：换 **BCM94360NG**（M.2 2230，原生 Wi-Fi+BT）或 USB 蓝牙适配器（BCM20702）

### 7.5 HiDPI

- 内屏原生支持 1440×900 HiDPI（2880×1800 backing），这是默认也是唯一的大尺寸 2x 档
- 没有 1680×1050 / 1920×1200 HiDPI（2x 后超过面板分辨率）
- 尝试 one-key-hidpi 写 `/Library/Displays/.../Overrides` 的方案在 macOS 26 上**无效**
- 需要更多档位只能用 BetterDisplay 之类的运行时工具

### 7.6 摄像头（不支持）

- 硬件为 **Bison UVC**（Windows 硬件 ID `USB\VID_5986&PID_2146&MI_00`），ACPI 有 `IPU0@50000`（Intel IPU）与 `RCAM/RCIR` 节点
- USB 端口存在且已上电（port 10 / location 6，类型 255 内置），但 macOS **总线上枚举不出设备**，`SPCameraDataType` 为空
- 对照实验：禁用 USBMap 无效；安装 IOElectrify（USB 供电注入）无效（老 kext 在 macOS 26 不加载）
- 判断：摄像头模块的上电/数据路由由 Intel IPU/EC 控制，Windows 侧有驱动完成初始化，macOS 无对应驱动 → **不支持**
- 替代方案：USB 外接摄像头

### 7.6 启动速度

| 措施 | 效果 |
|---|---|
| 从 U 盘启动 → 三星 980 PRO ESP | 40s → 36s |
| 移除 `keepsyms=1 debug=0x100` | 少加载内核符号 |
| `Misc → Debug → Target 0`，关 AppleDebug/ApplePanic | 不再写 262KB 启动日志 |
| 删除失效的 Sensei Monitor 登录项 | 登录更快 |
| `ShowPicker=false` | 省掉菜单等待 |

- 内核到桌面约 21 秒；前面固件+OpenCore 约 14 秒；其中显卡驱动接管会让进度条停 10–16 秒（AuxKC 激活 + WEX 初始化），属正常
- **启动磁盘被改成 Windows ESP**（`bless --getBoot` = `disk0s1`）会让 OpenCore 默认项变成 Windows；用「系统设置 → 通用 → 启动磁盘」改回 MAC（`bless --setBoot` 会报 `0xe00002e2`，需走 GUI 授权路径）
- `Timeout=0` ≠ 立即启动，见 §3

### 7.7 WindowServer 高占用

- 1440×900 HiDPI 下 WindowServer 平均约 64% CPU，2048×1280 1x 约 54%
- GPU 利用率采样始终 0% —— 合成工作压在 CPU 上，分辨率只能小幅缓解
- 属 WEX 显示管线性能限制

### 7.8 CPU 名称

- 「关于本机」显示 Unknown；`machdep.cpu.brand_string` 正常
- RestrictEvents 的 `cpuname` 补丁按核心数匹配固定字符串（12 核 → `12-Core Intel Xeon W`），替换串放不下，未生效
- 纯显示问题，不影响功能

---

### 7.5 NVMe：三星 980 PRO 必须更新固件

随机死机，panic：

```
nvme: "3rd party NVMe controller. Command timeout. Read. fBuiltIn=1
MODEL=Samsung SSD 980 PRO 500GB FW=1B2QGXA7 ..." @IONVMeController.cpp:5848
```

原因：980 PRO 的出厂固件 `1B2QGXA7` 有已知缺陷（可能导致盘变只读/锁死），macOS 遇到读超时直接 panic。

修复：Windows 下用 **Samsung Magician** 把固件升到 **5B2QGXA7**（实测有效，更新后 `ioreg` 确认版本变化）。更新前务必备份数据、全程接电源。

## 8. 合盖锁屏/关机工具

`tools/install-lid-shutdown.sh` 会安装：

- `/usr/local/bin/lockhelper`（调用 `SACLockScreenImmediate`，安装时用 clang 编译）
- `/usr/local/bin/lidshutdown.sh`（守护脚本）
- `/Library/LaunchDaemons/local.lidshutdown.plist`
- `pmset -a disablesleep 1`

日志：`/var/log/lidshutdown.log` + 系统日志 `logger -t lidshutdown`

卸载：`tools/uninstall-lid-shutdown.sh`

---

## 9. 已知限制与建议

1. **蓝牙**：换 BCM94360NG 网卡（M.2 2230）可同时解决蓝牙和 Wi-Fi 稳定性，换完删掉 AirportRTW 即可
2. **睡眠**：目前只能靠合盖方案；等上游修 WEX 的电源钩子
3. **HDMI/USB-C 视频**：`-wex-panel-only` 的代价，需要外接显示时得改接线补丁
4. **重装系统后**：需重装 Graphics 0.4.4 pkg、重跑合盖脚本；EFI 不变

---

## 10. 参考

- WhateverXe: https://github.com/b00t0x/WhateverXe （issues #22 / #86 / #90 与本机同类）
- WhateverXe Graphics: https://github.com/b00t0x/WhateverXe-Graphics
- SimpleHDA: https://github.com/laobamac/SimpleHDA
- AirportRTW: https://github.com/souissiak1-maker/AirportRTW
- AppleALC: https://github.com/acidanthera/AppleALC
- OpenCore: https://github.com/acidanthera/OpenCorePkg
- one-key-hidpi（macOS 26 上无效，仅参考）: https://github.com/xzhih/one-key-hidpi

---

## 11. 文件清单

```
README.md                 本文
patches/                  WEX 四个内屏补丁（0.8.1 基线）
tools/                    合盖守护、EFI 同步、启动菜单切换脚本
logs/                     3 份睡眠相关 panic 日志
```

> 不包含 EFI 二进制和 SMBIOS 信息。EFI 备份单独保存在本地。
