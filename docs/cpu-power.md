# CPU 功耗墙（25W → 45W）

> 2026-11-20。i5-12500H 在 macOS 下持续全核只有约 1.2GHz，Windows 性能模式可到 4GHz。定位为 EC/固件层功耗限制，用 MSR 写入解决。

## 现象

| 负载 | macOS（修复前） | Windows 性能模式 |
|---|---|---|
| 单核睿频 | ✅ 3.4–4.2GHz | 4.5GHz |
| 全核持续 | ❌ ~1.2GHz @ 25W | ~3GHz+ |

XCPM 正常（`machdep.xcpm.mode=1`、频率向量已加载），温度也不高（65°C），排除热降频。

## 排查过程

1. **Intel Power Gadget / PowerLog**：全核 Req≈2.9GHz、Avg≈1.1GHz、Package 25W → 请求高、实际低
2. **XCPM 检查**：模式与向量正常，不是电源管理驱动问题
3. **Fn+Q 性能模式**：macOS 下无效（EC 需要 Windows 侧工具配合）
4. **DSDT 反编译**（RWEverything 导出 + iasl）：
   - 找到 `\_SB.PC00.LPCB.H_EC.VPC0.DYTC`（Lenovo VPC2004）
   - 性能模式 = `ECCC(0x60, 0xA0)` + `ECWT(4, ITSM)`
   - 安静模式 = `ECCC(0x60, 0xA4)` + `ECWT(2, ITSM)`
5. **SSDT `_INI` 尝试**：EC 在 `_INI` 阶段未就绪，命令无效，且导致触控板失效 → 放弃，SSDT 已禁用

## 最终方案：VoltageShift 改 MSR 功耗墙

VoltageShift 通过 MSR 直接写 PL1/PL2：

```bash
sudo voltageshift power 45 45
```

但 MSR 值会被 EC 周期性重置，因此用 LaunchDaemon 每 60 秒重新应用：

```bash
sudo bash tools/install-vs-daemon.sh
sudo launchctl bootstrap system /Library/LaunchDaemons/local.voltageshift-power.plist
```

## 结果

| 指标 | 修复前 | 修复后 |
|---|---|---|
| Package 功耗 | 25W | 45–50W |
| 全核平均频率 | ~1.1GHz | **~2.6GHz** |
| 温度 | 65°C | 84°C（未降频） |

## 注意

- VoltageShift.kext 已通过 OpenCore 注入（`Kernel → Add`），不需要系统批准
- 调回默认：`sudo voltageshift power 72 80`
- 想更凉：把 daemon 里的 `45 45` 改成 `35 35`
- MSR 写入有风险，但 PL 调节（不碰电压）相对安全
