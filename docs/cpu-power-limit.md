# CPU 持续功耗墙（25W）排查记录 / Sustained CPU power limit (25W) investigation

> 2026-11-23。最终结论：**PL1 25W 由 EC 固件强制，macOS 侧软件无解**；短时 PL2 45W 正常。
> Final conclusion: **the 25 W PL1 is enforced by the EC firmware and cannot be overridden from macOS**; the 45 W PL2 burst works normally.

## 现象 / Symptom

| 场景 | 结果 |
|---|---|
| 单线程 | ~3.3 GHz（可能是 E 核上限） |
| 4 线程 | 前 ~25 s 37W/3.1GHz，之后 25W/1.1GHz |
| 16 线程 | 25W / 1.2GHz（PL1） |
| Windows「野兽模式」 | **45W 持续** |

- MSR 0x610 读数为 PL1 72W / PL2 80W（后来手动改为 45W），但实际 package 功耗 25W。
- 温度仅 67–69°C，不是热降频。
- BIOS「系统性能模式 = 野兽模式」对 macOS 无效。

## 排查过程 / What was tried

| 方法 | 结果 |
|---|---|
| VoltageShift 写 MSR 0x610（PL1/PL2=45W） | 写入成功，EC 仍限 25W |
| MSR 0x64B cTDP 切 LEVEL2 | 写入成功，无持续效果 |
| MSR 0x638 / 0x65C / 0x64F | 均非限制源 |
| YogaSMC DYTC（`DYTCMode` = p / 0x12B001 / 0x12C001 / RESET） | 返回成功，PL1 不变 |
| DSDT DPTF 门槛补丁（`And(DPTF,One)`→`And(ZZZZ,One)`） | 补丁加载，PL1 不变 |
| 读取 EC（YogaSMC UserClient + SSDT-ECRW） | 成功；0x15=0x13、0x18=0x8B（已是野兽模式） |
| Windows EC dump 对比（均衡 vs 野兽） | 只有 0x15/0x18 是模式位，0x8A–0x92 是电池遥测 |
| 每秒重写 MSR | 无效 |
| MCHBAR kext（写 0x59A0） | kext 无法注入（OC 对自定义 kext 的 C++ 构造支持问题） |
| ACPI `_WAK` 包装 + SystemMemory 写 MCHBAR+0x59A0 | ACPI 写未生效 |

## 根因 / Root cause

```
MSR 0x648 (CONFIG_TDP_NOMINAL) = 25   ← 标称 TDP 被固件定为 25W
Windows: Lenovo 驱动 + Intel DPTF → 通过未知 EC/PECI 握手 → 45W
macOS: 无 DPTF 驱动 → EC 固件按 25W 执行，忽略 MSR/ACPI 写入
```

- EC 模式寄存器（0x15/0x18）已是野兽模式，说明模式切换本身有效，但 **PL1 不由这些寄存器控制**。
- MCHBAR/ACPI 写入未生效，说明 EC 可能通过 PECI 或内部策略直接限制 package power。

## 结论 / Conclusion

- **软件层无解**：所有公开接口（MSR、EC、WMI、ACPI）都已尝试。
- 继续需要：硬件级 EC/SMBus 抓包、移植 Intel DPTF 驱动、或逆向 EC 固件——均超出合理投入。
- 日常使用：短时 45W（打开程序、切应用流畅），持续全核 25W（编译/渲染受限）。

## 参考 / References

- YogaSMC issue #223（本机报告）：https://github.com/zhen-zen/YogaSMC/issues/223
- throttled（Linux 固件功耗墙工具）：https://github.com/erpalma/throttled
- Linux ideapad-laptop DYTC 实现：`drivers/platform/x86/lenovo/ideapad-laptop.c`
- 同款机型评测（Windows 55W）：https://m.ithome.com/html/650870.htm

## 当前状态 / Current state

- 实验性改动已全部回退（`_WAK` 改名、SSDT-PL45、SSDT-ZZZZ、SSDT-ECRW、MCHBARPoke 均移除）。
- 保留 YogaSMC（可用于 DYTC/EC 诊断）。
- 归档日期：2026-11-23。
