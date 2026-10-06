# X-HEEP SRAM Write Path

## 1. 本文目的

本文记录第一阶段已经确认的 SRAM 写入入口，为后续 Dirty Tracker 集成提供可复现的代码位置。

本阶段只确认路径和观察信号，不修改 X-HEEP RTL，也不实现 Dirty Tracker。

## 2. 当前版本

- X-HEEP 本地分支：`srtp/checkpoint-mvp`
- X-HEEP 本地快照提交：`acb14ab996a3975f4ae14904e75bef107c65c8e0`
- 该快照说明中记录的上游版本：`69ef4dd537ed2ab9dc118be7c6c15fcee924ff18`
- Docker 工具链：`ghcr.io/x-heep/x-heep/x-heep-toolchain:v1.0.6`

## 3. 已确认的数据通路

```text
CPU / DMA
    |
system_bus
    |
ram_slave_req
    |
memory_subsystem
    |
4 个 SRAM banks
```

SRAM 子系统文件：

```text
hw/core-v-mini-mcu/memory_subsystem.sv
```

生成模板：

```text
hw/core-v-mini-mcu/memory_subsystem.sv.tpl
```

## 4. SRAM 结构

生成后的 `memory_subsystem.sv` 包含 4 个 `sram_wrapper` 实例：

- `ram0_i`
- `ram1_i`
- `ram2_i`
- `ram3_i`

每个实例的参数为：

```systemverilog
.NumWords (8192),
.DataWidth(32'd32)
```

因此：

- 每个 bank：8192 × 32 bit = 32 KiB
- bank 数量：4
- 总 SRAM 容量：128 KiB

证据位置：

- Bank 0：`memory_subsystem.sv:69-84`
- Bank 1：`memory_subsystem.sv:86-101`
- Bank 2：`memory_subsystem.sv:103-118`
- Bank 3：`memory_subsystem.sv:120-135`

## 5. SRAM 请求接口

`memory_subsystem` 在第 21 至 22 行声明请求和响应：

```systemverilog
input  obi_req_t [NUM_BANKS-1:0] ram_req_i,
output obi_rsp_t [NUM_BANKS-1:0] ram_resp_o
```

每个 bank 的写入相关字段为：

```systemverilog
ram_req_i[i].req
ram_req_i[i].we
ram_req_i[i].addr
ram_req_i[i].wdata
ram_req_i[i].be
```

各字段的作用：

| 字段 | 第一阶段解释 |
| --- | --- |
| `req` | 当前请求有效 |
| `we` | 当前请求为写操作 |
| `addr` | 字节地址 |
| `wdata` | 写入数据 |
| `be` | 字节使能 |

## 6. 地址与响应

生成文件第 40 至 46 行将字节地址转换为 SRAM 字地址：

```systemverilog
ram_req_addr_0 = ram_req_i[0].addr[14:2];
```

其他 bank 使用相同的地址位。

第 65 行确认当前 grant 固定有效：

```systemverilog
assign ram_resp_o[i].gnt = 1'b1;
```

## 7. 有效写入条件

第一版 Dirty Tracker 可以使用下面的有效写入条件：

```systemverilog
write_fire[i] =
    ram_req_i[i].req &&
    ram_req_i[i].we &&
    (|ram_req_i[i].be);
```

加入 `|be` 可以排除没有任何有效字节的写请求。

## 8. 建议观察位置

后续 Dirty Tracker 建议在 `memory_subsystem` 内部观察 `ram_req_i`，位置应位于各个 `sram_wrapper` 实例之前。

这样可以同时获得：

- bank 编号 `i`
- 写请求有效信号
- 写地址
- 写数据
- 字节使能

## 9. 模板注意事项

仓库同时存在：

```text
memory_subsystem.sv
memory_subsystem.sv.tpl
```

模板中也包含 `ram_req_i`、固定 grant 和 `sram_wrapper` 生成逻辑。

因此，后续正式集成前必须确认 X-HEEP 的生成流程。若 `memory_subsystem.sv` 由模板生成，长期修改应落在模板或受生成流程保护的独立模块中，否则重新生成 MCU 后修改可能丢失。

## 10. 第一阶段结论

SRAM 写入入口已经确认：

```text
文件：hw/core-v-mini-mcu/memory_subsystem.sv
观察对象：ram_req_i[i]
有效写入：req && we && |be
建议位置：sram_wrapper 实例之前
```

第一阶段到此结束。以下工作留到后续阶段：

- Dirty Tracker RTL
- dirty block 粒度选择
- clear/commit 时机
- 面积和时序开销比较
