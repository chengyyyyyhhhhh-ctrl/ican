# Artix-7 声源定位 FPGA 工程

- 工具版本：Vivado 2022.2
- 目标器件：`xc7a50tfgg484-1`（Artix-7 XC7A50T）
- 工程文件：`project_2.xpr`
- 顶层模块：`project_2.srcs/sources_1/new/top.v`
- 引脚与时序约束：`project_2.srcs/constrs_1/new/xdc.xdc`

用 Vivado 打开 `project_2.xpr`，检查工程源文件和 IP 状态，重新生成 IP 输出文件，然后再综合和实现。仓库保留了 RTL、XDC、COE、XCI 与 MIG 配置文件；`.Xil`、`project_2.cache`、`project_2.gen`、`project_2.runs` 等由 Vivado 生成的目录未收录。若 Vivado 提示缺少 IP 产物，请在 IP Sources 中执行 Generate Output Products。

本目录没有复制原工程内嵌的 `serial_monitor`。仓库根目录的 [`serial_monitor/`](../serial_monitor/) 是独立的原始顶层目录，串口方位角协议及接线说明见其 README。
