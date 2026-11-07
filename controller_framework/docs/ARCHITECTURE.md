# 最小系统架构

## 数据通路

```text
X-HEEP CPU / DMA
        |
        | SRAM有效写请求
        v
modified_region_tracker
        |
        | modified_count
        v
checkpoint_cost_estimator
        |
        | checkpoint_cycles
        v
sleep_mode_selector <--- predicted_idle_cycles
        |
        +-- KEEP
        +-- LIGHT
        +-- DEEP_OFF
```

## 模块职责

### modified_region_tracker

按固定大小划分易失性存储区域。某区域自上次有效检查点后第一次被写入时，置位对应位图并增加计数。

### checkpoint_cost_estimator

第一版采用线性周期模型：

```text
T_checkpoint = T_fixed + N_modified * T_region
```

后续用仿真或实测数据校准参数，不在当前阶段宣称该模型已经准确反映真实NVM。

### sleep_mode_selector

比较预计空闲周期与两级阈值：短空闲保持运行，中等空闲进入轻度休眠，只有预计空闲时间超过检查点及深度休眠切换开销时才选择深度关断。

## 与X-HEEP的边界

核心控制器不直接依赖X-HEEP内部结构。适配层负责把X-HEEP的多个SRAM bank写请求转换为统一事件：

```text
mem_write_valid
mem_write_addr
```

这样模块级验证和X-HEEP系统集成可以分开进行。

