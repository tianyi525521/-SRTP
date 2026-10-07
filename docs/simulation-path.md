# 仿真路径与故障注入分析

- 负责人：3号- 分支：feature/verification
- X-HEEP 版本：本地快照 acb14ab；导入上游 69ef4dd
- 环境：Ubuntu 22.04，Docker Toolchain v1.0.6

## 0. 仿真环境跑通记录（证据）
- 跑通命令：`make verilator`
- 成功输出：
  - `[TESTBENCH]: loading firmware ../../../sw/build/main.hex`
  - `Reset Released`
  - `Memory Loaded`
  - `Simulation finished after 13002 clock cycles`
  - `Program Finished with value 0`
  - `hello world!`
- 结论：Verilator 环境可用，固件加载正常，UART 输出正常，仿真能正常退出。

## 1. 仿真顶层与实例化

- 入口文件：`tb/testharness.sv`（填你往上滚看到的真实路径）
- 顶层模块：`testharness` 或 `tb_top`
- 打印 `[TESTBENCH]` 信息的位置：`tb/testharness.sv:65`等
## 2. 固件加载与输出
- 固件加载：`hw/vendor/pulp_platform/riscv_dbg/tb/tb_top.sv:72`
- 仿真顶层入口：`tb/testharness.sv`
- 仿真结束信号 `exit_valid`：定义在 `tb/tb_top.sv:39`；在 `tb/tb_top.sv:156` 被检测；通过 `tb/testharness.sv:260` 输出给 C++ 仿真驱动。
- 退出值 `exit_value`：定义在 `tb/tb_top.sv:40`；在 `tb/tb_top.sv:157` 被判断；输出到 `tb/testharness.sv:177`。
- 仿真结束逻辑：C++ 驱动（`tb/tb_top.cpp:110`）在 `exit_valid` 变为 1 时结束仿真，并打印 `Program Finished with value 0`。
- UART 输出：
  - 信号声明：`tb/testharness.sv:87-88`
  - 连接 DUT：`tb/testharness.sv:295-296`
  - 仿真模型实例化：`tb/testharness.sv:407-415`，使用 `uartdpi` DPI 模型
  - 模型源码：`hw/vendor/lowrisc/opentitan/hw/dv/dpi/uartdpi/uartdpi.sv`
  - 实际输出：由 C++ Testbench 重定向到 `/dev/pts/0` 和 `uart0.log`


## 3. 波形生成


## 4. 故障注入第一版方案
### 4.1 注入位置
- 首推：C++ Testbench 层（`tb/tb_top.cpp`），直接操作 `dut->rst_ni` 信号。
- 备选：SystemVerilog 层（`tb/tb_top.sv`）的 `reset_gen` 逻辑。
- 不修改 X-HEEP 内部 RTL 逻辑。

### 4.2 注入方式
- 方式一（复位注入）：在 C++ 层 `tb/tb_top.cpp` 中增加计数器，当达到 `POWER_FAIL_CYCLE` 时，执行 `dut->rst_ni = 0;`，持续若干周期后再释放。
- 方式二（强制结束）：在 Testbench 计数器到达指定周期时，直接 `$finish;` 结束仿真。

### 4.3 触发周期
- 参数化设计：`parameter int POWER_FAIL_CYCLE = 1000;`
- 复位脉冲宽度参考 `tb/tb_sc_top.cpp:48` 的 `reset_cycles = 30`。

### 4.4 观察信号与判据
- 观察：`exit_valid`、`exit_value`、UART 输出（`uart0.log`）。
- 成功判据：仿真正常结束，UART 输出结果正确，`exit_valid` 在掉电前/后符合预期。
- 失败判据：仿真卡死、UART 乱码、`exit_valid` 一直为 0、状态恢复非法。






## 5. 待确认问题

