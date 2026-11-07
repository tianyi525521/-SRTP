# 接口 v0.1

| 信号 | 方向 | 含义 |
|---|---|---|
| `clk_i` | 输入 | 控制器时钟 |
| `rst_ni` | 输入 | 低有效复位 |
| `mem_write_valid_i` | 输入 | 本周期发生一次有效SRAM写入 |
| `mem_write_addr_i` | 输入 | 有效写入的字节地址 |
| `checkpoint_done_i` | 输入 | 一次检查点已经完整完成，可清除修改记录 |
| `predicted_idle_cycles_i` | 输入 | 预计空闲周期；当前由testbench提供，来源尚待确定 |
| `modified_count_o` | 输出 | 自上次有效检查点以来被修改的区域数量 |
| `checkpoint_cycles_o` | 输出 | 估计的检查点执行周期 |
| `deep_threshold_o` | 输出 | 当前深度休眠阈值 |
| `sleep_mode_o` | 输出 | KEEP、LIGHT或DEEP_OFF |

## X-HEEP写事件映射

已确认的候选有效写入条件：

```systemverilog
write_fire[i] = ram_req_i[i].req
              && ram_req_i[i].we
              && (|ram_req_i[i].be);
```

多bank同时写入如何编码为单一事件仍需在X-HEEP适配层中确认，当前核心模块每周期接收一个写地址。

