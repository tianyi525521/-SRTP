# X-HEEP 检查点开销感知动态休眠控制器

本目录是 SRTP 项目的**第一版可运行代码骨架**，用于向指导教师说明研究对象、模块边界和验证方法。

当前版本只实现最小闭环：

```text
SRAM 写请求
    -> 修改区域跟踪
    -> 待保存区域数量
    -> 检查点周期估计
    -> KEEP / LIGHT / DEEP_OFF 选择
```

## 当前能证明什么

- 写入新的存储区域后，待保存区域计数增加；
- 同一区域重复写入不会重复计数；
- 完成一次有效检查点后，跟踪状态可清零；
- 检查点开销会随待保存区域数量变化；
- 预计空闲时间不同时，控制器输出不同休眠模式。

## 当前不能证明什么

- 尚未接入 X-HEEP 的真实总线信号；
- 尚未保存完整 CPU 上下文或外设状态；
- 尚未建立真实 NVM 能耗模型；
- 尚未完成检查点写入和恢复数据通路；
- 尚未完成 FPGA 验证。

## 目录

```text
rtl/        可综合 SystemVerilog 模块
tb/         独立单元测试
docs/       架构、接口和完成状态说明
scripts/    仿真入口
xheep/      X-HEEP 适配层占位目录
```

## 运行

在X-HEEP Docker工具链中执行：

```bash
bash scripts/run_verilator_docker.sh
```

也可以安装 Icarus Verilog 后执行：

```bash
make test
```

或：

```bash
bash scripts/run_unit.sh
```

通过时应显示：

```text
[PASS] SRTP controller framework smoke test passed.
```

## 后续接入 X-HEEP

第一阶段不直接修改 X-HEEP 上游文件。先在 `xheep/` 中实现适配层，把
`ram_req_i[i].req && ram_req_i[i].we && |ram_req_i[i].be` 转换成统一的
`mem_write_valid` 和 `mem_write_addr`，再连接本目录中的控制器。

