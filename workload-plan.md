# X-HEEP Workload Plan

## 1. 本文目的

本文定义第一版软件负载的三个场景（少量 / 中等 / 大量分散写入），
说明每个场景测什么、怎样切换、实测结果如何，
作为 1 号 Dirty Tracker 观察与后续掉电恢复实验的输入。

配套文档：`docs/software-path.md`（应用入口、构建运行、写入方式、结果检查）。

## 2. 负载程序

负载程序即本阶段交付的测试应用：

```text
sw/applications/sram_write_test/main.c
```

可调参数（`main.c` 顶部宏）：

| 宏 | 含义 | 可取值 | 默认 |
| --- | --- | --- | --- |
| `BANK_NUM` | 写入的 bank 数量 | 1~4 | 4 |
| `N_WORDS` | 每个 bank 写入的字数（32 bit/字） | 1~8192 | 32 |
| `OFFSET` | bank 内起始字节偏移 | 需避开代码区与栈区 | `0x4000` |

写入地址通式：

```text
addr = bank_base + OFFSET + 4 * i        （i = 0 .. N_WORDS-1）
bank_base = 0x00000000 / 0x00008000 / 0x00010000 / 0x00018000
```

写入数据图案：`0xA5A50000 | (bank << 8) | i`，便于在波形与内存 dump 中定位每个字的来源。

写入全部为 32 位对齐整字，字节使能 `be = 4'b1111`，
满足 sram-path.md 定义的有效写条件 `req && we && |be`。

## 3. 三个场景

### 场景 A：少量脏块（1~4 blocks）

- 配置：`BANK_NUM=1`，`N_WORDS=1`（最小）或 `4`
- 写入地址：`0x00004000` 起连续 1~4 个字（4~16 字节）
- 测什么：Dirty Tracker 能否捕捉到**最少粒度**的写事件；
  这是掉电恢复必须保住的数据量的下界
- 实测：`PASS 1 banks x 1 words, bank0=0x00004000`，`Program Finished with value 0`

### 场景 B：中等脏块（约 32 blocks）

- 配置：`BANK_NUM=1`，`N_WORDS=32`
- 写入地址：`0x00004000`–`0x0000407F`（128 字节连续区间）
- 测什么：单 bank 内**连续区间**写入时，dirty block 计数与地址连续性；
  模拟"一段缓冲区被整体更新"的典型情况
- 实测：`PASS 1 banks x 32 words, bank0=0x00004000`，`Program Finished with value 0`

### 场景 C：大量分散写入（跨 bank）

- 配置：`BANK_NUM=4`，`N_WORDS=32`
- 写入地址：四个 bank 各 `基址 + 0x4000` 起 128 字节，
  即 `0x4000` / `0xC000` / `0x14000` / `0x1C000`
- 测什么：写事件**同时分布到 4 个 bank**时，`ram_req_i[0..3]` 是否全部可观测；
  模拟"脏数据分散在整个 SRAM"的最坏情况
- 实测：`PASS 4 banks x 32 words, bank0=0x00004000`，`Program Finished with value 0`

## 4. 场景切换方法

改 `main.c` 顶部两个宏后重新编译运行：

```bash
# 例：切到场景 B
#   main.c: BANK_NUM=1, N_WORDS=32
~/xheep-run.sh sram_write_test "make app PROJECT=sram_write_test"
~/xheep-run.sh sram_write_test "make verilator-run"
```

本阶段三个场景均已实测通过，随后已将 `main.c` 恢复为默认配置
（`BANK_NUM=4`，`N_WORDS=32`，即场景 C）。

## 5. 与 Dirty Tracker 的对齐（待办）

以下两点等 1 号确定 dirty block 粒度后回填：

- **粒度对齐**：dirty block 若以大于 4 字节为单位（如 64 bit / cache line），
  `N_WORDS` 与 `OFFSET` 需对齐到该边界，避免一个写操作跨两个统计单元
- **负载放大**：第一阶段场景最大写入 4 × 128 B = 512 B；
  后续掉电实验若需要更大脏区，按 `N_WORDS` 上探至 256/1024 字，
  并重新检查与代码区、栈区的地址冲突

## 6. 第一阶段结论

- 三个场景设计完成、全部实测通过，写入事件可被 `ram_req_i[i]` 观测
- 场景切换只需改两个宏，无需改动工程结构
- 地址分布避开代码区（`0x0000`–`0x2600`）与栈堆区（`0x20000` 附近），全部安全
