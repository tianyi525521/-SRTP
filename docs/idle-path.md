# X-HEEP / CV32E20 WFI 与 Idle Path 分析

## 1. 软件侧 WFI 入口

当前 X-HEEP 工程中存在多个 WFI 使用位置。

与 Power Manager 深度休眠路径最直接相关的是：

`sw/device/lib/drivers/power_manager/power_manager_cpu_store.S`

该函数首先保存 CPU 上下文，然后执行 `wfi`：

- 设置 `POWER_GATE_CORE`
- 设置 `WAKEUP_STATE`
- 保存 `gp`
- 保存 CPU 通用寄存器
- 保存 CSR 状态
- 设置恢复地址
- 最后执行 `wfi`

此外，`sw/device/lib/runtime/hart.h` 中提供了：

```c
static inline void wait_for_interrupt(void) {
    asm volatile("wfi");
}
