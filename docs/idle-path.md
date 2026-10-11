# WFI、core_sleep 与唤醒路径分析
## 摘要
本阶段主要针对 X-HEEP + CV32E20 中 CPU 的 WFI、睡眠状态以及唤醒路径进行源码分析，目标是回答“软件如何执行 WFI、CPU 如何进入睡眠、`core_sleep` 如何产生和传递、Power Manager 如何使用该信号，以及中断如何唤醒 CPU”等问题，为后续 Idle Monitor、Dirty Tracker 和低功耗决策逻辑的设计提供接口依据。

通过对 X-HEEP 源码的检索，可以确认：软件侧通过 `wait_for_interrupt()` 执行 RISC-V 的 `wfi` 指令。WFI 在 CV32E20 的 ID stage 中被译码为 `wfi_insn_dec`，随后传递给 `cve2_controller` 的 `wfi_insn_i`。Controller 将有效的 WFI 识别为一种 `special request`，CPU 控制器依次经过 `FLUSH`、`WAIT_SLEEP`，最终进入 `SLEEP`。

进入 `SLEEP` 后，CPU 在没有唤醒事件时保持睡眠；当检测到 `irq_pending_i`、`irq_nm_i` 或调试请求等条件时，Controller 从 `SLEEP` 转向 `FIRST_FETCH`，CPU 恢复取指。同时，CV32E20 的 `cve2_top` 根据 CPU 当前工作状态产生 `core_sleep_o`，该信号经过 CPU 子系统向 SoC 上层传递为 `core_sleep`，并被低功耗相关模块使用。

本阶段还确认，当前工程中没有直接搜索到 `idle_enter` 和 `idle_exit` 信号。因此，在不修改 CV32E20 CPU 内核的前提下，可以考虑在 CPU 子系统外部根据 `core_sleep` 的边沿生成这两个事件信号。
### 对任务要求的 6 个问题的简要回答
1. **软件怎样执行 WFI，调用位置在哪里？**
   软件侧在 `sw/device/lib/runtime/hart.h` 中定义了 `wait_for_interrupt()`，函数内部通过 `asm volatile("wfi")` 执行 WFI 指令。此外，`sw/device/lib/drivers/power_manager/power_manager_cpu_store.S` 中还存在与深度低功耗相关的 WFI 路径，该路径会在执行 WFI 前保存 CPU 上下文。

2. **CPU 哪个端口产生睡眠状态？**
   CV32E20 的 `cve2_top.sv` 中产生 `core_sleep_o`。其逻辑与 `fetch_enable_q`、`core_busy_q`、`debug_req_i`、`irq_pending` 和 `irq_nm_i` 等信号有关。

3. **`core_sleep` 在哪一层定义和传递？**
   CPU 子系统输出 `core_sleep_o`，然后在 SoC 顶层形成 `core_sleep`，再向上层模块传递。主要路径可以表示为：`cpu_subsystem.core_sleep_o → core_sleep → ao_peripheral_subsystem.core_sleep_i`。Power Manager 中也存在 `core_sleep_i` 输入。

4. **`power_manager` 如何使用 `core_sleep`？**
   `power_manager.sv` 中存在 `core_sleep_i`，并将其与 `power_gate_core` 等控制条件结合，用于低功耗状态控制。因此，`core_sleep` 可以作为 CPU 已经处于空闲/睡眠状态的重要状态输入，但它本身并不等同于“立即关电”。

5. **中断到来后如何退出睡眠？**
   Controller 在 `SLEEP` 状态下检测 `irq_nm_i`、`irq_pending_i`、`debug_req_i`、`debug_mode_q` 和 `debug_single_step_i` 等条件。如果检测到相关唤醒事件，状态机会从 `SLEEP` 转向 `FIRST_FETCH`，CPU 随后恢复取指。

6. **`idle_enter`、`idle_exit` 应怎样生成？**
   当前工程中没有直接找到这两个信号。因此，在第一阶段不修改 CPU 内核的前提下，可以在 CPU 子系统外部保存上一拍的 `core_sleep`，通过边沿检测生成：`idle_enter = core_sleep & ~core_sleep_d`，`idle_exit = ~core_sleep & core_sleep_d`。这样 `core_sleep` 从 0 变为 1 时产生 `idle_enter`，从 1 变为 0 时产生 `idle_exit`。

---

## 1. 软件怎样执行 WFI

### 1.1 `wait_for_interrupt()` 函数

文件：

`sw/device/lib/runtime/hart.h`

其中可以找到：

```
static inline void wait_for_interrupt(void) { asm volatile("wfi"); }
```

因此，软件侧通过 `wait_for_interrupt()` 执行 RISC-V 的 WFI 指令。

整体过程可以简单表示为：

```
软件调用 wait_for_interrupt()
        ↓
asm volatile("wfi")
        ↓
CPU 执行 WFI 指令
        ↓
CPU 进入等待状态
```

---

## 2. 与 Power Manager 相关的软件 WFI 路径

文件：

`sw/device/lib/drivers/power_manager/power_manager_cpu_store.S`

该文件中存在与 CPU 低功耗相关的保存和恢复路径。

在执行 WFI 之前，该路径会进行 CPU 上下文保存，包括：

* 设置 `POWER_GATE_CORE`
* 设置 `WAKEUP_STATE`
* 保存 `gp`
* 保存 x1-x31（非 RV32E）
* 保存相关 CSR 状态
* 保存恢复地址 `power_manager_cpu_restore`
* 最后执行 `wfi`

因此需要特别注意：

> WFI 指令本身并不负责保存 CPU 上下文。如果进入更深层的低功耗状态后需要恢复 CPU 执行现场，则需要在执行 WFI 前通过相应机制保存上下文。

整体过程可以理解为：

```
准备进入深度低功耗
        ↓
保存 CPU 上下文
        ↓
设置 Power Manager 状态
        ↓
执行 WFI
        ↓
CPU 等待唤醒
        ↓
发生唤醒事件
        ↓
恢复 CPU 上下文
        ↓
继续执行
```

---

## 3. WFI 在 CV32E20 中的译码和控制路径

### 3.1 WFI 译码

文件：

`hw/vendor/openhwgroup/cv32e20/rtl/cve2_id_stage.sv`

WFI 指令首先在 ID stage 中被识别，形成：

`wfi_insn_dec`

随后该信号传递给 Controller：

`wfi_insn_dec → cve2_controller.wfi_insn_i`

因此，WFI 从指令进入 CPU 控制逻辑后的第一个关键路径为：

```
WFI 指令
    ↓
wfi_insn_dec
    ↓
wfi_insn_i
```

### 3.2 Controller 接收 WFI

文件：

`hw/vendor/openhwgroup/cv32e20/rtl/cve2_controller.sv`

Controller 中存在：

`wfi_insn_i`

并进一步形成：

`assign wfi_insn = wfi_insn_i & instr_valid_i;`

随后：

`assign special_req_flush_only = wfi_insn | csr_pipe_flush;`

因此，Controller 会将有效的 WFI 识别为一种 `special request`。

完整路径可以表示为：

```
WFI 指令
   ↓
wfi_insn_dec
   ↓
wfi_insn_i
   ↓
wfi_insn
   ↓
special_req_flush_only
   ↓
FLUSH
   ↓
WAIT_SLEEP
   ↓
SLEEP
```

这里特别需要注意文字表述：

**WFI 被译码为 `wfi_insn_dec`，之后传递给 `cve2_controller` 的 `wfi_insn_i`。Controller 将 WFI 识别为 `special request`，CPU 控制器依次经过 `FLUSH`、`WAIT_SLEEP`，最终进入 `SLEEP`。**

---

## 4. Controller 的具体状态变化

在 Controller 中，WFI 经过以下几个主要阶段。

### 4.1 FLUSH

检测到 WFI 后，Controller 首先进入 `FLUSH` 状态。

这一阶段主要用于处理流水线中的相关状态，为进入睡眠状态做准备。

### 4.2 WAIT_SLEEP

随后进入：

`WAIT_SLEEP`

该状态中存在：

`ctrl_busy_o = 1'b0;`

`instr_req_o = 1'b0;`

`halt_if = 1'b1;`

`flush_id = 1'b1;`

`ctrl_fsm_ns = SLEEP;`

可以简单理解为：

```
停止继续取指
    ↓
暂停相关流水线操作
    ↓
准备进入 SLEEP
```

### 4.3 SLEEP

进入 `SLEEP` 后：

`instr_req_o = 1'b0;`

`halt_if = 1'b1;`

`flush_id = 1'b1;`

在没有唤醒事件的情况下：

`ctrl_busy_o = 1'b0;`

CPU 保持睡眠状态。

如果检测到以下事件之一：

* `irq_nm_i`
* `irq_pending_i`
* `debug_req_i`
* `debug_mode_q`
* `debug_single_step_i`

Controller 则会：

```
SLEEP
  ↓
FIRST_FETCH
```

从而退出睡眠并重新开始取指。

---

## 5. CV32E20 如何产生 `core_sleep_o`

文件：

`hw/vendor/openhwgroup/cv32e20/rtl/cve2_top.sv`

其中存在：

`assign clock_en = fetch_enable_q & (core_busy_q | debug_req_i | irq_pending | irq_nm_i);`

`assign core_sleep_o = fetch_enable_q & !clock_en;`

因此，`core_sleep_o` 是由 CPU 当前的运行状态产生的睡眠指示信号。

可以简单理解为：

```
CPU 允许运行
+
当前没有需要继续执行的工作
+
没有需要立即处理的中断/调试请求
        ↓
core_sleep_o 有效
```

需要特别注意：

> `core_sleep_o` 不是简单的“WFI 指令检测信号”。

WFI 是使 CPU 进入等待状态的一种指令，而 `core_sleep_o` 是 CPU 根据自身当前状态产生的睡眠指示信号。

因此：

`WFI`

和：

`core_sleep_o`

不是同一个信号。

---

## 6. `core_busy_o` 的来源

文件：

`hw/vendor/openhwgroup/cv32e20/rtl/cve2_core.sv`

可以看到：

`assign core_busy_o = ctrl_busy | if_busy | lsu_busy;`

因此：

`core_busy_o = ctrl_busy OR if_busy OR lsu_busy`

可以简单理解为：

* `ctrl_busy`：控制器相关工作
* `if_busy`：取指相关工作
* `lsu_busy`：Load/Store Unit 相关工作

当这些模块都没有工作时，CPU 更容易满足进入 sleep 状态的条件。

---

## 7. `core_sleep_o` 在 SoC 中的传递路径

### 7.1 CPU 子系统

文件：

`hw/core-v-mini-mcu/cpu_subsystem.sv`

CPU 子系统存在：

`core_sleep_o`

并连接到 CV32E20 Wrapper。

### 7.2 XIF Wrapper

文件：

`hw/core-v-mini-mcu/cve2_xif_wrapper.sv`

Wrapper 内部实例化 CV32E20，并将 CV32E20 的 `core_sleep_o` 向外传递。

因此主要路径为：

```
CV32E20
   ↓
cve2_xif_wrapper
   ↓
cpu_subsystem
```

### 7.3 SoC 顶层

文件：

`hw/core-v-mini-mcu/core_v_mini_mcu.sv`

其中存在：

`logic core_sleep`

并形成类似：

```
cpu_subsystem_i.core_sleep_o
        ↓
    core_sleep
        ↓
ao_peripheral_subsystem_i.core_sleep_i
```

因此整体传递路径可以表示为：

```
CV32E20
   │
   │ core_sleep_o
   ↓
cpu_subsystem
   │
   ↓
core_sleep
   │
   ↓
ao_peripheral_subsystem
```

---

## 8. Power Manager 如何使用 `core_sleep`

文件：

`hw/ip/power_manager/rtl/power_manager.sv`

Power Manager 中存在：

`input logic core_sleep_i`

其低功耗控制逻辑会将 `core_sleep_i` 与自身的控制条件结合。

例如源码中存在类似：

`(reg2hw.power_gate_core.q && core_sleep_i)`

这样的判断条件。

因此可以确认：

`core_sleep`

会被 Power Manager 用于判断 CPU 是否已经进入适合进一步执行低功耗控制的状态。

但是：

> `core_sleep` 本身并不意味着 CPU 只要变成 1 就立即关电。真正进入更深层低功耗状态还需要结合 Power Manager 自身的控制寄存器和状态机。

因此，对于后续项目设计，可以把 `core_sleep` 理解为：

> **CPU 当前已经进入空闲/睡眠状态的一个重要硬件状态信号。**

---

## 9. 中断如何唤醒 CPU

在 Controller 的 `SLEEP` 状态中，可以看到：

`if (irq_nm_i || irq_pending_i || debug_req_i || debug_mode_q || debug_single_step_i) begin`

`    ctrl_fsm_ns = FIRST_FETCH;`

`end`

因此可以表示为：

```
SLEEP
  │
  ├── 没有唤醒事件
  │       ↓
  │     继续 SLEEP
  │
  └── irq_pending / NMI / debug request
          ↓
       FIRST_FETCH
          ↓
       CPU 恢复取指
```

这里需要注意：

> `irq_pending_i` 表示存在待处理的中断请求，是 CPU 从 SLEEP 状态退出的重要条件之一；它不能简单等同于“已经开始执行中断服务程序”。

真正的中断处理还涉及 CPU 的中断使能状态以及后续的中断处理流程。

---

## 10. `idle_enter` 与 `idle_exit` 建议

在第一阶段的要求下，不修改 CV32E20 CPU 内核。

当前源码搜索中没有直接发现：

`idle_enter`

`idle_exit`

因此，可以考虑在 CPU 子系统外部根据：

`core_sleep`

生成进入和退出睡眠的事件脉冲。

假设：

`logic core_sleep_d;`

`always_ff @(posedge clk) begin`

`    core_sleep_d <= core_sleep;`

`end`

则：

`assign idle_enter = core_sleep & ~core_sleep_d;`

`assign idle_exit  = ~core_sleep & core_sleep_d;`

其含义为：

### 进入睡眠

```
上一拍 core_sleep = 0
当前 core_sleep = 1
        ↓
idle_enter = 1
```

### 退出睡眠

```
上一拍 core_sleep = 1
当前 core_sleep = 0
        ↓
idle_exit = 1
```

因此：

```
core_sleep：0 → 1
        ↓
    idle_enter

core_sleep：1 → 0
        ↓
    idle_exit
```

这两个信号可以作为后续 Idle Monitor 的接口。

---

## 11. 本阶段最终确认的完整路径

综合源码搜索结果，可以得到以下主要路径。

### 11.1 WFI → SLEEP

```
软件
  ↓
wait_for_interrupt()
  ↓
asm volatile("wfi")
  ↓
WFI 指令
  ↓
wfi_insn_dec
  ↓
wfi_insn_i
  ↓
Controller
  ↓
special request
  ↓
FLUSH
  ↓
WAIT_SLEEP
  ↓
SLEEP
```

### 11.2 SLEEP → 唤醒

```
SLEEP
  ↓
检测 irq_pending / NMI / debug request
  ↓
FIRST_FETCH
  ↓
CPU 恢复取指
```

### 11.3 CPU → SoC

```
CV32E20
  ↓
core_sleep_o
  ↓
cpu_subsystem
  ↓
core_sleep
  ↓
ao_peripheral_subsystem / power_manager
```

### 11.4 后续 Idle Monitor 接口

```
core_sleep
    ↓
边沿检测
    ├── 0 → 1：idle_enter
    └── 1 → 0：idle_exit
```

---

## 12. 对后续项目设计的意义

本阶段的源码分析为后续项目提供了一个比较明确的接口基础。

后续如果需要实现 Idle Monitor，可以优先关注：

`core_sleep`

并在 CPU 子系统外部产生：

`idle_enter`

`idle_exit`

之后可以进一步在此基础上连接：

```
Idle Monitor
      ↓
Dirty Tracker
      ↓
Cost Estimator
      ↓
Mode Selector
      ↓
Checkpoint Controller
```

这样可以把“CPU 是否进入空闲状态”与后续的 Checkpoint、LIGHT sleep / DEEP-OFF 决策逻辑连接起来。

---

## 13. 本阶段工作边界

### 已完成
* [x] 软件 WFI 调用位置确认
* [x] WFI 到 CV32E20 Controller 的路径确认
* [x] `FLUSH → WAIT_SLEEP → SLEEP` 状态路径确认
* [x] `core_sleep_o` 产生位置确认
* [x] `core_busy_o` 来源确认
* [x] `core_sleep_o → core_sleep` 的 SoC 传递路径确认
* [x] Power Manager 对 `core_sleep` 的使用方式确认
* [x] SLEEP 状态下的中断/调试唤醒条件确认
* [x] `idle_enter` / `idle_exit` 生成方案提出
### 本阶段暂不完成
* [ ] Idle Monitor RTL 实现
* [ ] Dirty Tracker RTL 实现
* [ ] 修改 CV32E20 CPU 内核
* [ ] 完整的中断来源分类
* [ ] 完整的 WFI → SLEEP → WAKEUP 波形验证
* [ ] 深度低功耗状态机重新设计
---
## 14. 最终结论

本阶段已经从源码层面确认了 X-HEEP + CV32E20 中 WFI、CPU Sleep 和唤醒的主要路径：

```
wait_for_interrupt()
        ↓
WFI
        ↓
wfi_insn_dec
        ↓
wfi_insn_i
        ↓
special request
        ↓
FLUSH
        ↓
WAIT_SLEEP
        ↓
SLEEP
```

CPU 在睡眠状态下检测到中断、NMI 或调试请求后，可以从：
`SLEEP`
转向：
`FIRST_FETCH`
并恢复取指。
同时，CPU 根据自身运行状态产生：
`core_sleep_o`
该信号经过 SoC 向上层传递为：
`core_sleep`
并被 Power Manager 等低功耗相关模块使用。
因此，后续设计可以在不修改 CV32E20 CPU 内核的前提下，以 `core_sleep` 作为 CPU 空闲状态的重要观察信号，并进一步生成：
`idle_enter`
`idle_exit`
作为后续 Idle Monitor、Dirty Tracker 和低功耗模式决策模块的接口。

> **本阶段结论主要来自 X-HEEP 源码路径分析，尚未通过完整 RTL 波形仿真验证。后续可以通过 Verilator 仿真进一步验证 WFI → SLEEP → WAKEUP 的实际时序。**
