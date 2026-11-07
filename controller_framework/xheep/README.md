# X-HEEP适配层

本目录暂不放置伪造的X-HEEP集成代码。

完成WFI、Verilator和软件路径分析后，在这里加入：

```text
xheep_write_adapter.sv
xheep_sleep_adapter.sv
```

其中写请求适配器负责：

1. 接收各SRAM bank的`ram_req_i[i]`；
2. 计算每个bank的`write_fire[i]`；
3. 处理同一周期多个bank同时写入的情况；
4. 生成核心控制器使用的统一地址或多端口写事件。

