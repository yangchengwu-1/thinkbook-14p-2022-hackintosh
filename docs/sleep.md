# 睡眠：S3 → Deep Idle（S0ix）完整方案

> 2026-11-21 解决。最终配置：合盖 → Deep Idle 睡眠；开盖 → LID0 唤醒并亮屏；唤醒后 Metal 加速仍在。

## 背景

- **S3**：能进入，但固件永远无法恢复（`EFI/Bootrom Failure after last point of entry to sleep`），平台不支持。
- **Deep Idle（S0ix）**：用 [S0ixStandby](https://github.com/labrouss/S0ixStandby) 让 macOS 睡在 XNU Deep Idle 里。但加速开启时，唤醒会在 `IOAcceleratorFamily2` / `IOSurface` 自旋锁死锁。

## 关键修复

来自 **@brandonedley** 的 opt-in 补丁 [`-wex-s0-csb-resync`](https://github.com/b00t0x/WhateverXe/issues/117)（基于 WEX 0.8.3）：

- 不做 GT 重置（**不需要** `-s0ixgpureset`）
- 睡眠前保留 CSB，唤醒后重同步（移植自 #80）
- Display13 唤醒守卫

补丁在 `patches/WhateverXe-0.8.3-s0ix-csb-resync.patch`，叠加在我们的 P1/P2/P4 + gamma 曲线之上。

## 完整配置

| 组件 | 设置 |
|---|---|
| WEX | 0.8.3 + s0ix-csb-resync + P1/P2/P4 + gamma 1.8 |
| boot-args | `-wex-s0-csb-resync -s0ixacnortc` |
| S0ixStandby | 0.5.4（kext 启用） |
| ACPI | `SSDT-DEEPIDLE.aml`（Deep Idle 支持） |
| ACPI | `SSDT-LIDWAKE.aml`（给 LID0 补 `_PRW`，GPE 0x6e） |
| ACPI | S3 屏蔽（`_S3` 改名 + `SSDT-NameS3-disable`） |
| pmset | `sleep 10 displaysleep 10 disablesleep 0 lidwake 1` |

### 为什么需要 SSDT-LIDWAKE

DSDT 里 `LID0`（PNP0C0D）**没有 `_PRW`**，macOS 不把盖子注册为唤醒源：

- 合盖能睡（Clamshell Sleep），但开盖后只有 EC 事件（`_Q0C`），系统暗唤醒、屏幕不亮
- 补 `_PRW` 指向 EC GPE 0x6e 后，日志出现 `Wake from Deep Idle ... due to LID0/UserActivity`，屏幕自动点亮

补上 `_PRW` 之后 **不再需要 `-s0ixecwake`**：macOS 会自己从 `_PRW` 武装 EC GPE（实测去掉该参数后开盖仍正常唤醒，日志为 `Wake from Deep Idle ... due to LID0/Lid Open`）。

## 验证日志

```
11:59:58  Entering Sleep state due to 'Clamshell Sleep'   ← 合盖进入 Deep Idle
12:00:07  Display is turned on                            ← 开盖亮屏
12:00:16  Wake from Deep Idle [CDNVA] : due to LID0/UserActivity Assertion
```

唤醒后 `system_profiler` 仍显示 Metal 2 / 1536MB，无 panic。

## 历史尝试（已放弃）

- S3：固件无法恢复
- 休眠（hibernatemode 25 + HibernationFixup）：OpenCore 不认 macOS 26 的镜像
- `-s0ixgpureset`：GT 重置后加速器仍死锁（IOAcceleratorFamily2 / IOSurface）
- `-s0ixnodsm`：换一种死锁
- 改 WEX host 睡眠钩子：无效
- 禁用 mediaanalysisd：只对 TGL-H 的 VCS0 有效，对 ADL-P 唤醒死锁无效
- 合盖关机守护：旧方案，已移除
