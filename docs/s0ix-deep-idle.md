# S0ix（Deep Idle）替代 S3：实测记录

> 2026-11-13。S3 在固件层无法恢复（`EFI/Bootrom Failure after last point of entry to sleep`），改用
> [S0ixStandby](https://github.com/labrouss/S0ixStandby) 让 macOS 睡眠在 XNU Deep Idle（S0ix）里。

## 安装

| 组件 | 来源 |
|---|---|
| `SSDT-DEEPIDLE.aml` | S0ixStandby release |
| `S0ixStandby.kext` 0.5.4 | S0ixStandby release（无 Lilu 依赖，匹配 `PNP0D80`） |
| boot-args | `-s0ixgpureset -s0ixacnortc` |
| pmset | `hibernatemode 0 standby 0 powernap 0 tcpkeepalive 0 disablesleep 0` |

S3 保持 ACPI 屏蔽（`_S3` 改名 + `SSDT-NameS3-disable`），确保走 Deep Idle。

## 结果

| 配置 | 睡眠 | 唤醒 |
|---|---|---|
| WEX 加速 + `-s0ixgpureset` | ✅ 进入 Deep Idle（LED 呼吸） | ❌ 显示回来但 UI 冻结；重启后 `IOAcceleratorFamily2` ticket spinlock panic |
| WEX 加速 + 无 `-s0ixgpureset` | ✅ | ❌ 背光亮、无图像；WEX `EL-null ... wakeRefs=0xFFFF...` panic |
| **WEX 无加速（`-wex-noaccel`）** | ✅ | ✅ 干净唤醒，桌面可用（软件渲染） |

内核日志（无加速那次）：

```
18:07:32 Entering Sleep state due to 'Software Sleep' ... 16 secs
18:07:48 Wake from Deep Idle [CDNVA] : due to PWRB/UserActivity Assertion
```

## 结论

- **S0ixStandby 在 ADL-P 上可用**：Deep Idle 睡眠/唤醒链路是通的
- 卡点是 **WEX 加速器无法跨 Deep Idle 恢复**（GT reset 后 accelerator workloop 死锁）
- 无加速模式牺牲性能（19MB 帧缓冲、无 Metal），但换来真正的睡眠

## 已报上游

- S0ixStandby issue #4（ADL-P 测试报告）
- WhateverXe issue #117（Deep Idle 唤醒 IOAcceleratorFamily2 死锁）

## 当前选择

日常使用保留加速 + 合盖锁屏/关机（`disablesleep=1`）。若要真睡眠，切 `-wex-noaccel` 并恢复 S0ix 配置。
