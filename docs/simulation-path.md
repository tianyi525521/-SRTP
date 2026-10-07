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
## 2. 固件加载与输出
## 3. 波形生成
## 4. 故障注入第一版方案
## 5. 待确认问题

