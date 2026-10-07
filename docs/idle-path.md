
X-HEEP / CV32E20 WFI 与 Idle 路径搜索记录

记录日期：2026-10-06

工程路径：

~/projects/x-heep

本文件用于记录第一阶段成员 #2 对 X-HEEP 中 WFI、CPU Sleep、core_sleep
以及 Wake-up 路径进行源码搜索的过程。

============================================================
一、当前 CPU 配置

当前工程使用：

CPU：
CV32E20

RV32E：
false

RV32M：
RV32MSlow

CPU 子系统文件：

hw/core-v-mini-mcu/cpu_subsystem.sv

============================================================
二、搜索软件中的 WFI

使用的命令：

grep -RniE "WFI|wfi|wait_for_interrupt" sw hw tb --exclude-dir=vendor --exclude-dir=.git | head -100

这个命令的目的：

寻找软件代码中执行 WFI 的位置。

重点结果包括：

sw/device/lib/runtime/hart.h

sw/device/lib/drivers/power_manager/power_manager_cpu_store.S

sw/device/lib/drivers/w25q128jw_controller/w25q128jw_controller.c

sw/device/lib/runtime/syscalls.c

============================================================
三、确认普通软件 WFI 封装

文件：

sw/device/lib/runtime/hart.h

关键代码：

static inline void wait_for_interrupt(void) {
asm volatile("wfi");
}

含义：

软件调用 wait_for_interrupt() 后，最终会执行 RISC-V 的 WFI 指令。

WFI 的基本含义：

Wait For Interrupt

也就是：

等待中断。

============================================================
四、确认 Power Manager 深度休眠路径

文件：

sw/device/lib/drivers/power_manager/power_manager_cpu_store.S

该文件的注释明确说明：

这个函数会保存 CPU 上下文，然后通过 WFI 进入较深的睡眠状态。

确认该函数在 WFI 前完成：

设置 POWER_GATE_CORE。
设置 WAKEUP_STATE。
保存 GP。
保存 CPU 通用寄存器。
保存 CSR 状态。
保存恢复地址。
最后执行 WFI。

重要结论：

WFI 本身不负责保存 CPU 上下文。

CPU 上下文是在执行 WFI 之前由软件保存的。

============================================================
五、确认 CV32E20 CPU 实例

文件：

hw/core-v-mini-mcu/cpu_subsystem.sv

确认：

cve2_xif_wrapper 中实例化了 CV32E20。

同时，CPU 的 sleep 信号通过：

core_sleep_o

输出。

============================================================
六、确认 WFI 的硬件处理过程

相关文件：

hw/vendor/openhwgroup/cv32e20/rtl/cve2_id_stage.sv

hw/vendor/openhwgroup/cv32e20/rtl/cve2_controller.sv

确认：

WFI 被译码为 wfi_insn_dec。
之后传递给 cve2_controller 的 wfi_insn_i。
controller 将 WFI 识别为 special request。
CPU 控制器依次经过 FLUSH、WAIT_SLEEP。
最终进入 SLEEP。
============================================================
七、确认 SLEEP 状态下的行为

文件：

hw/vendor/openhwgroup/cv32e20/rtl/cve2_controller.sv

SLEEP 状态中：

如果没有中断或调试事件：

ctrl_busy_o = 0

CPU 保持睡眠状态。

如果发生：

irq_nm_i
irq_pending_i
debug_req_i
debug_mode_q
debug_single_step_i

中的相关事件：

控制器可以从 SLEEP 转移到 FIRST_FETCH。

也就是说：

SLEEP
→ 发生唤醒事件
→ FIRST_FETCH
→ CPU 重新开始取指。

============================================================
八、确认 core_busy_o

文件：

hw/vendor/openhwgroup/cv32e20/rtl/cve2_core.sv

关键代码：

assign core_busy_o = ctrl_busy | if_busy | lsu_busy;

简单理解：

CPU 是否忙，需要同时考虑：

ctrl_busy：
控制器是否忙。

if_busy：
Instruction Fetch，取指部分是否忙。

lsu_busy：
Load/Store Unit，数据读写部分是否忙。

只要其中一个为 1：

core_busy_o = 1

说明 CPU 还有工作。

============================================================
九、确认 core_sleep_o 的产生

文件：

hw/vendor/openhwgroup/cv32e20/rtl/cve2_top.sv

关键代码：

assign clock_en = fetch_enable_q &
(core_busy_q | debug_req_i | irq_pending | irq_nm_i);

assign core_sleep_o = fetch_enable_q & !clock_en;

含义：

clock_en 可以理解为：

CPU 时钟当前是否需要继续运行。

当 CPU 不忙，并且没有需要继续运行的事件时：

clock_en 可能变成 0。

此时：

core_sleep_o = 1

因此 core_sleep_o 是 CPU 睡眠/时钟门控状态的派生信号。

重要：

core_sleep_o 不是 WFI 指令本身的直接输出。

============================================================
十、确认 SoC 中的信号传播

相关文件：

hw/core-v-mini-mcu/cpu_subsystem.sv

hw/core-v-mini-mcu/core_v_mini_mcu.sv

确认路径：

CV32E20
→ core_sleep_o
→ CPU Subsystem
→ core_sleep
→ Always-On / Power Manager
→ core_sleep_i

============================================================
十一、确认 Power Manager 的使用方式

文件：

hw/ip/power_manager/rtl/power_manager.sv

确认：

core_sleep_i 会参与 power-off sequence 的启动条件。

相关条件中可以看到：

(reg2hw.power_gate_core.q && core_sleep_i)

因此：

core_sleep = 1

并不意味着：

CPU 电源立即关闭。

Power Manager 还需要结合：

power_gate_core

以及其他 force 控制信号决定具体的电源操作。

============================================================
十二、搜索 idle_enter / idle_exit

使用命令：

grep -RniE "idle_enter|idle_exit" hw sw tb --exclude-dir=vendor --exclude-dir=.git | head -100

结果：

没有找到现成的 idle_enter 信号。

没有找到现成的 idle_exit 信号。

============================================================
十三、第一阶段接口建议

建议暂时不要修改 CV32E20 CPU 内核。

可以在 CPU 外部观察：

core_sleep

并保存上一周期的：

core_sleep_d

推荐：

idle_enter = core_sleep & ~core_sleep_d

idle_exit = ~core_sleep & core_sleep_d

含义：

core_sleep：

当前 CPU 是否处于 sleep 状态。

core_sleep_d：

上一周期 CPU 是否处于 sleep 状态。

当：

上一周期 = 0
当前周期 = 1

表示 CPU 刚刚进入 idle：

idle_enter = 1

当：

上一周期 = 1
当前周期 = 0

表示 CPU 刚刚退出 idle：

idle_exit = 1

============================================================
十四、第一阶段结论

已经确认：

WFI
→ WFI Decode
→ cve2_controller
→ FLUSH
→ WAIT_SLEEP
→ SLEEP
→ core_busy 下降
→ clock_en 下降
→ core_sleep_o = 1
→ core_sleep
→ Power Manager

Wake-up：

SLEEP
→ 中断/调试事件
→ FIRST_FETCH
→ 重新取指
→ core_sleep 下降

============================================================
十五、当前工作边界

本阶段完成：

WFI 软件入口搜索。
WFI 硬件处理路径搜索。
core_sleep_o 产生位置确认。
core_sleep SoC 传播路径确认。
Wake-up 路径确认。
idle_enter / idle_exit 是否存在的搜索。
后续接口定义建议。

本阶段暂时不做：

修改 CV32E20。
修改 CPU 内部 RTL。
实现 Idle Monitor。
实现 Dirty Tracker。
实现 Checkpoint Controller。
实现动态睡眠决策。

注意：

本阶段主要通过源码分析确认路径。

目前不能把这些结果表述为“已经完成波形仿真验证”。

如果后续需要，可以再通过 Verilator 仿真观察：

core_sleep

以及：

idle_enter
idle_exit

的实际波形变化。

============================================================
十六、后续第二阶段衔接

后续可以基于：

idle_enter
idle_exit

记录 CPU 每次空闲持续的时间：

idle_enter
→ 开始计数
→ idle_exit
→ 得到 idle_duration

然后将：

idle_duration

交给后续的：

Cost Estimator
Mode Selector
Checkpoint Controller

等模块使用。
