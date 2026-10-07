# X-HEEP Software Test Path

## 1. 本文目的

本文记录第一阶段已经确认的软件侧入口：测试程序放在哪里、怎样编译、软件如何执行 WFI、
向 SRAM 写入的地址分布，以及运行结果怎样判断。

## 2. 当前版本

- X-HEEP 本地分支：`srtp/checkpoint-mvp`
- X-HEEP 本地快照提交：`acb14ab996a3975f4ae14904e75bef107c65c8e0`
- 该快照说明中记录的上游版本：`69ef4dd537ed2ab9dc118be7c6c15fcee924ff18`
- Docker 工具链：`ghcr.io/x-heep/x-heep/x-heep-toolchain:v1.0.6`
- 容器封装脚本：`~/xheep-run.sh`

## 3. 软件入口

应用目录：

```text
sw/applications/sram_write_test/
```

目录内容：

```text
main.c      测试程序
README.md   使用说明
```

应用选择方式：`sw/applications/` 下的目录名即应用名，通过 `PROJECT=` 变量选择，
**不需要在 CMake 或 Makefile 中注册**（hello_world 同样只含 `main.c`）。

复位入口：

```text
sw/linker/link.ld : ENTRY(_start)
sw/device/lib/crt/crt0.S : 启动后调用 main
```

退出方式：`main` 的返回值经 `exit` 交给 testbench。

## 4. 构建与运行

容器内命令：

```bash
make app PROJECT=sram_write_test TARGET=sim COMPILER=gcc
make verilator-run
```

宿主机一键执行（推荐）：

```bash
~/xheep-run.sh sram_write_test "make app PROJECT=sram_write_test"
~/xheep-run.sh sram_write_test "make verilator-run"
```

`make verilator-run` 实际展开为：

```bash
fusesoc run --target=sim --tool=verilator openhwgroup.org:systems:core-v-mini-mcu \
  --run_options="+firmware=../../../sw/build/main.hex"
```

链接脚本由 `TARGET` 与 `CPU_ARCH` 等变量间接选择（`sw/linker/link.ld`，
`ENTRY(_start)`），本项目测试未额外指定链接脚本，使用默认值即可。

实测输出：

```text
[TESTBENCH]: loading firmware  ../../../sw/build/main.hex
Simulation finished after 26602 clock cycles
Program Finished with value 0
uart0.log: PASS 4 banks x 32 words, bank0=0x00004000
```

## 5. WFI 调用（现状调查）

工程内已有统一封装：

```c
/* sw/device/lib/runtime/hart.h:30 */
static inline void wait_for_interrupt(void) { asm volatile("wfi"); }
```

现有调用位置（grep `wfi` 与 `wait_for_interrupt` 的结果）：

| 位置 | 用法 |
| --- | --- |
| `sw/device/lib/runtime/hart.h:30` | 封装函数本体 |
| `sw/applications/example_timer_sdk/main.c:85` | 等待定时器中断 |
| `sw/device/lib/sdk/timer/timer_sdk.c:121` | 定时器 SDK 内部等待 |
| `sw/applications/example_dlc/main.c:150, 209` | DMA 等待完成中断 |
| `sw/applications/example_dma_2d/main.c:204` 等 | DMA 场景批量调用 |
| `sw/device/lib/drivers/w25q128jw_controller/w25q128jw_controller.c:150` | Flash 控制器等待 |
| `sw/device/lib/runtime/syscalls.c:116` | 系统调用内兜底等待 |

典型使用模式：配置并使能外设中断 → 调用 `wait_for_interrupt()` → CPU 停止取指，
直到中断到来后继续执行。

本测试程序（sram_write_test）为纯写入-读回校验，不使用 WFI；
掉电场景下的 WFI 等待策略由 2 号在 `docs/idle-path.md` 中定义，本文不展开。

## 6. SRAM 地址与写入方式

bank 基址定义位于 `hw/core-v-mini-mcu/include/core_v_mini_mcu_pkg.sv:74-86`：

```systemverilog
localparam logic [31:0] RAM0_START_ADDRESS = 32'h00000000;
localparam logic [31:0] RAM1_START_ADDRESS = 32'h00008000;
localparam logic [31:0] RAM2_START_ADDRESS = 32'h00010000;
localparam logic [31:0] RAM3_START_ADDRESS = 32'h00018000;
```

因此：

- 每个 bank：32 KiB
- bank 数量：4
- 总 SRAM 容量：128 KiB
- 软件地址与硬件物理地址一致

测试程序写入地址：bank 基址 + `0x4000`：

```text
0x00004000   bank0
0x0000C000   bank1
0x00014000   bank2
0x0001C000   bank3
```

写入方式：

```c
volatile uint32_t *p = (volatile uint32_t *)(bank_base + 0x4000);
p[i] = 0xA5A50000u | (bank << 8) | i;
```

因为是 32 位对齐的整字写入，字节使能 `be = 4'b1111`，
与 sram-path.md 的有效写入条件 `req && we && |be` 一致，写事件必然被记录。

偏移 `0x4000` 的选取依据：构建报告显示代码与只读数据占用 9.5 KiB（bank0 使用率 29.7%）、
数据占用 5 KiB，栈自 `0x20000` 向下增长；`0x4000` 位于代码区之上、数据区之下，四个 bank 均安全。

## 7. 软件负载设计

详细设计见 `docs/workload-plan.md`，此处为摘要。

可调参数位于 `main.c` 顶部：

| 宏 | 含义 | 默认值 |
| --- | --- | --- |
| `BANK_NUM` | 写入 bank 数量（1~4） | 4 |
| `N_WORDS` | 每个 bank 写入字数 | 32 |
| `OFFSET` | bank 内起始偏移 | `0x4000` |

三个场景：

| 场景 | BANK_NUM | N_WORDS | 写入范围 | 目的 |
| --- | --- | --- | --- | --- |
| A 少量 | 1 | 1~4 | `0x00004000` 起 | 最小可观测写入 |
| B 中等 | 1 | 32 | `0x00004000`–`0x0000407F` | 单 bank 连续写入 |
| C 跨 bank | 4 | 32 | `0x4000`/`0xC000`/`0x14000`/`0x1C000` 各 128 B | 四个 bank 同时产生写事件 |

实测结果（三个场景全部通过）：

```text
A: PASS 1 banks x 1 words,  bank0=0x00004000   Program Finished with value 0
B: PASS 1 banks x 32 words, bank0=0x00004000   Program Finished with value 0
C: PASS 4 banks x 32 words, bank0=0x00004000   Program Finished with value 0
```

数据图案为 `0xA5A50000 | (bank << 8) | index`；写入完成后逐字读回比对，
不一致打印 `FAIL bank b word i` 并返回 1，全部一致打印 `PASS` 并返回 0。

## 8. 结果检查

| 方式 | 判据 |
| --- | --- |
| UART 输出 | `uart0.log` 打印 `PASS` 或 `FAIL bank b word i` |
| 程序返回值 | 仿真打印 `Program Finished with value 0` 为通过 |
| 波形 | `build/openhwgroup.org_systems_core-v-mini-mcu_1.0.6/sim-verilator/waveform.fst` |

## 9. 与其他成员的接口

- **1 号**：写入地址与写入方式见第 6 节，对应 `memory_subsystem.sv` 的 `ram_req_i[i]`，
  可直接复现四个 bank 的写事件；本文是 `interface-v0.1.md` 的输入
- **2 号**：WFI 现状见第 5 节；睡眠功耗与唤醒时序的深入分析见 `docs/idle-path.md`
- **3 号（待补）**：仿真顶层、复位与结束信号以 `docs/simulation-path.md` 为准；
  第 4 节的命令为实测可用值，若与 3 号文档冲突以 3 号为准

## 10. 第一阶段结论

软件侧入口已经确认：

```text
应用目录：sw/applications/sram_write_test/
构建命令：make app PROJECT=sram_write_test TARGET=sim COMPILER=gcc
运行命令：make verilator-run
WFI 调用：wait_for_interrupt()，sw/device/lib/runtime/hart.h:30
写入地址：0x00000000 / 0x00008000 / 0x00010000 / 0x00018000 各加 0x4000
写入粒度：32 位对齐整字，be = 4'b1111
结果判断：UART 打印 PASS 且 Program Finished with value 0
```

第一阶段到此结束。以下工作留到后续阶段：

- 按 dirty block 粒度重新对齐写入区间
- WFI 与睡眠流程（归 2 号）
- 掉电与恢复时序验证

## 11. 注意事项

- 不要写在 `0x0000`–`0x2600` 附近（向量表与代码区），也不要写在 `0x20000` 附近（栈与堆）
- 必须是 32 位对齐写，否则 `be` 不是全 1，1 号侧可能统计不到
- 程序体积变大后需重新查看构建报告的 bank 使用率再定 `OFFSET`
- `sw/build`、`build` 曾为 root 属主，若报 `Permission denied`，
  先执行 `sudo chown -R gaocanyang:gaocanyang` 对应目录
- dirty block 粒度由 1 号确定后，需把 `N_WORDS` 与 `OFFSET` 对齐到 block 边界
