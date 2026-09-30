# ican 项目代码

本仓库收录三个独立目录：MaixCAM2 车牌检测识别、Artix-7 FPGA 声源定位工程，以及读取 FPGA 串口方位角的 Windows 监视器。三个目录来自各自的原始工程，按用途整理后公开。

| 目录 | 内容 | 入口 |
| --- | --- | --- |
| [`maixcam2_dehaze_yolo_submit/`](maixcam2_dehaze_yolo_submit/) | 低能见度判断、去雾、车牌检测与识别；含离线训练和数据生成脚本 | `main.py`、`pc_pipeline.py` |
| [`project_2/`](project_2/) | Vivado 2022.2 工程、Verilog RTL、XDC 约束、COE 初始化文件和 IP 配置 | `project_2.xpr` |
| [`serial_monitor/`](serial_monitor/) | FPGA 方位角串口监视器及协议解析测试 | `app.py`、`tests/test_protocol.py` |

## 快速开始

**FPGA：** 用 Vivado 2022.2 打开 `project_2/project_2.xpr`。工程目标器件是 `xc7a50tfgg484-1`（Artix-7 XC7A50T）。首次打开后请重新生成 IP 输出文件，再综合/实现；具体见 [`project_2/README.md`](project_2/README.md)。

**串口监视器：** 在 Windows 上进入 `serial_monitor`，安装 `requirements.txt` 后运行 `python app.py`。默认串口协议为 115200、8N1；接线和帧格式见 [`serial_monitor/README.md`](serial_monitor/README.md)。界面的声音强度曲线由软件模拟，FPGA 只提供方位角数据。

**MaixCAM2：** 使用说明见 [`maixcam2_dehaze_yolo_submit/README.md`](maixcam2_dehaze_yolo_submit/README.md)。部分大模型、数据集和演示视频没有放进仓库；模型来源见 [`models/MODEL_DOWNLOADS.md`](maixcam2_dehaze_yolo_submit/models/MODEL_DOWNLOADS.md)。

仓库只收录源码和必要配置，不含 Vivado 运行缓存、综合/实现结果、Python 虚拟环境或本地临时文件。当前没有随仓库提供开源许可证。
