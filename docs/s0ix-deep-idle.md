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

## 追加测试（2026-11-13 晚）

在 `-wex-noaccel` 验证可行后，又试了两种试图保留加速的组合：

| 配置 | 结果 |
|---|---|
| 加速 + `-s0ixgpureset` + `-s0ixnodsm`（跳过显示 DSM） | 睡眠进入 ✅，唤醒 panic：`thread_invoke: preemption_level 1 @sched_prim.c:3033` |
| 加速 + 自编译 WEX（去掉 host 睡眠钩子 `systemWakeRecovery=false`，保留 #22 唤醒修复） | 睡眠进入 ✅，唤醒冻结/无响应，强制重启 |
| 加速 + 休眠（`hibernatemode 25` + HibernationFixup 1.5.4 + OC `HibernateMode=Auto`） | 休眠入口死锁，panic 在 `IOAcceleratorFamily2`；未写盘、未恢复（`Hibernation exit count: 0`） |

最终结论：**只要 WEX 加速器参与，ADL-P 的 Deep Idle / 休眠转场就会死锁**，与 DSM、host 睡眠钩子无关；无加速路径则完全稳定。需要上游修改 WEX 加速器的睡眠转场处理。

上游：WhateverXe issue #117（含三组 panic 栈）、S0ixStandby issue #4。

