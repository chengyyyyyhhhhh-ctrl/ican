# 模型文件清单

轻量提交包保留LPRNet ONNX与MUD描述文件，大体积检测模型记录如下。

## YOLO车牌检测ONNX

- 文件名：`license_plate_yolov8.onnx`
- 来源：https://huggingface.co/ml-debi/yolov8-license-plate-detection/blob/main/best.onnx
- 输入：`1×3×640×640`
- 输出：`1×5×8400`
- SHA-256：`85d236280a1301ad98907947d284951dd2b20c23a6786ff50f7e6a8ec515bd50`

## MaixCAM2车牌检测模型

- 来源：https://maixhub.com/model/zoo/1229
- 描述文件：`model_249078.mud`
- 实际权重：`model_249078_npu.axmodel`、`model_249078_vnpu.axmodel`
- 网络：YOLOv5s
- 输入：224×224 RGB
- 标签：`license_plate`

## LPRNet字符识别ONNX

- 包内文件：`lprnet_chinese_plate.onnx`
- 输入：`1×3×24×94`
- 输出：`1×68×18`
- SHA-256：`c78e54070d0e2b8a6f8d548feb52b75321d5f464bcaadb679ec7ee31433cffa4`
