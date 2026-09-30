# MaixCAM2极端天气车牌检测识别工程（轻量提交版）

本工程对应已提交报告，包含以下代码：

- 条件扩散/ControlNet与CycleGAN极端天气数据扩充；
- 车牌区域保护、YOLO标签继承和生成记录；
- 低能见度判断与暗通道去雾；
- YOLO车牌检测；
- LPRNet车牌字符识别与CTC解码；
- MaixCAM2在线推理与结果叠加。

## 目录

```text
main.py                    MaixCAM2入口
dehaze.py                  去雾与低能见度评分
pc_pipeline.py             PC图片/视频处理
lprnet.py                  LPRNet字符识别
configs/                   全流程配置
offline/                   数据生成和YOLO训练代码
models/                    LPRNet ONNX和MaixCAM2 MUD
```

为满足上传大小限制，本提交包不附带数据集、视频、检测ONNX和两个AXModel大文件。大模型的公开来源、文件名和校验值记录在 `models/MODEL_DOWNLOADS.md`，源码与配置保持完整。

MaixCAM2数据流：

```text
摄像头 → 低能见度判断 → 按需去雾 → YOLO车牌检测
      → 车牌ROI → OCR识别 → 规则过滤 → 画框与结果输出
```

PC处理命令：

```bash
python pc_pipeline.py --source input.mp4 --output output.mp4 --dehaze auto
```

MaixCAM2运行前，将 `model_249078.mud` 及其两个AXModel上传到 `/root/models/`，再运行 `main.py`。
