# 极端天气车牌合成数据集构建系统

## 1. 项目概述

本系统面向极端天气条件下的车牌检测任务，完成正常天气数据、真实极端天气数据、非配对图像生成模型与 YOLO 标注之间的全流程衔接。系统覆盖数据整理、天气域模型训练、极端天气图像生成、车牌区域保护、YOLO 标签继承及生成过程追溯。

系统针对浓雾、暴雨、暴雪和沙尘四类环境分别训练 CycleGAN 模型。各天气模型独立学习正常道路场景到目标天气域的映射，降低多天气特征相互干扰。CycleGAN 通过循环一致性约束处理非配对图像，不要求正常天气图片与极端天气图片来自同一地点或同一时刻。

## 2. 技术流程

```text
正常天气图像（Domain A） ─┐
                          ├─ CycleGAN 训练 ─→ 四类天气生成器
极端天气图像（Domain B） ─┘                         │
                                                    ↓
正常天气图像 + YOLO 标签 ─→ 极端天气图像生成 ─→ 车牌区域保护
                                                    │
                                                    ↓
                                  合成图像 + YOLO 标签 + 追溯元数据
```

系统输出可直接并入 YOLO 训练集的图像和标签，原始标签采用 YOLO 归一化格式：

```text
class_id center_x center_y width height
```

## 3. 工程文件

```text
weather_dataset_generation/
├── prepare_cyclegan_dataset.py
├── train_weather_models.py
├── generate_extreme_yolo_dataset.py
├── requirements.txt
└── README.md
```

| 文件 | 功能 |
|---|---|
| `prepare_cyclegan_dataset.py` | 将正常天气和四类极端天气图片整理为 CycleGAN 非配对目录 |
| `train_weather_models.py` | 调用官方 PyTorch CycleGAN 训练四类天气模型 |
| `generate_extreme_yolo_dataset.py` | 加载天气生成器，生成极端天气图像并继承 YOLO 标签 |
| `requirements.txt` | Python 运行环境依赖 |

## 4. 数据目录规范

```text
data/
├── source/
│   ├── normal/
│   │   ├── images/train/
│   │   └── labels/train/
│   └── extreme/
│       ├── fog/
│       ├── rain/
│       ├── snow/
│       └── sand/
├── cyclegan/
├── checkpoints/
└── synthetic_extreme_yolo/
```

正常天气图像具有对应的 YOLO 标签。极端天气图片用于学习天气域分布，CycleGAN 训练阶段不依赖其车牌标注。

## 5. 环境部署

安装本工程依赖：

```bash
pip install -r requirements.txt
```

获取并安装官方 CycleGAN 工程：

```bash
git clone https://github.com/junyanz/pytorch-CycleGAN-and-pix2pix.git
cd pytorch-CycleGAN-and-pix2pix
pip install -r requirements.txt
cd ..
```

本系统直接调用官方工程中的 `models/networks.py`，训练权重与官方 CycleGAN 保持兼容。

## 6. 数据集整理

在 `weather_dataset_generation` 目录执行：

```bash
python prepare_cyclegan_dataset.py \
  --normal ./data/source/normal/images/train \
  --weather fog=./data/source/extreme/fog \
  --weather rain=./data/source/extreme/rain \
  --weather snow=./data/source/extreme/snow \
  --weather sand=./data/source/extreme/sand \
  --output ./data/cyclegan \
  --test-ratio 0.1 \
  --seed 42
```

整理后的每类天气目录均包含：

```text
trainA/  正常天气训练图像
trainB/  极端天气训练图像
testA/   正常天气验证图像
testB/   极端天气验证图像
```

## 7. 天气生成模型训练

```bash
python train_weather_models.py \
  --cyclegan-repo ./pytorch-CycleGAN-and-pix2pix \
  --datasets ./data/cyclegan \
  --checkpoints ./data/checkpoints \
  --weather all \
  --gpu-ids 0 \
  --epochs 100 \
  --decay-epochs 100
```

四类生成器权重保存至：

```text
data/checkpoints/fog_cyclegan/latest_net_G_A.pth
data/checkpoints/rain_cyclegan/latest_net_G_A.pth
data/checkpoints/snow_cyclegan/latest_net_G_A.pth
data/checkpoints/sand_cyclegan/latest_net_G_A.pth
```

`G_A` 表示从正常天气域 A 到极端天气域 B 的映射生成器。

## 8. 极端天气 YOLO 数据生成

```bash
python generate_extreme_yolo_dataset.py \
  --cyclegan-repo ./pytorch-CycleGAN-and-pix2pix \
  --images ./data/source/normal/images/train \
  --labels ./data/source/normal/labels/train \
  --model fog=./data/checkpoints/fog_cyclegan/latest_net_G_A.pth \
  --model rain=./data/checkpoints/rain_cyclegan/latest_net_G_A.pth \
  --model snow=./data/checkpoints/snow_cyclegan/latest_net_G_A.pth \
  --model sand=./data/checkpoints/sand_cyclegan/latest_net_G_A.pth \
  --output ./data/synthetic_extreme_yolo \
  --plate-mode degrade \
  --strength 0.75 \
  --seed 42
```

生成结果：

```text
data/synthetic_extreme_yolo/
├── images/
├── labels/
└── generation_metadata.csv
```

`generation_metadata.csv` 记录合成图文件名、原始图路径、天气类别、生成器权重、退化强度和随机种子，保证数据来源可追踪、生成过程可复现。

## 9. 车牌标签安全机制

图像生成模型能够改变天气、光照和整体色调，也可能改写车牌纹理。为防止生成不存在的汉字和号码，系统默认采用 `degrade` 模式：

1. 根据原始 YOLO 标签确定车牌区域；
2. 保留原图中的真实车牌字符；
3. 在车牌区域施加与目标天气一致的退化；
4. 使用羽化掩膜融合边缘；
5. 复制原始 YOLO 标签至合成图像。

四类车牌退化方式：

| 天气 | 车牌区域处理 |
|---|---|
| 浓雾 | 低对比度雾幕、亮度抬升、轻度模糊 |
| 暴雨 | 雨线遮挡、散射增强、轻度模糊 |
| 暴雪 | 白色雾幕、雪点遮挡、轻度模糊 |
| 沙尘 | 暖色颗粒、对比度下降、噪声与模糊 |

该机制保证车牌类别、位置和字符身份不被生成模型篡改，同时保留极端天气造成的识别难度。

## 10. 数据使用规范

- 训练数据由真实正常天气、真实极端天气和合成极端天气共同组成；
- 验证集与测试集仅使用未参与生成训练的真实数据；
- 车牌检测评估记录 `Precision`、`Recall`、`mAP50` 和 `mAP50-95`；
- 极端天气子集单独统计漏检率；
- OCR 数据仅使用字符身份保持不变的 `degrade` 或 `preserve` 模式；
- 合成数据通过 `generation_metadata.csv` 完成版本追踪和审计。

## 11. 工程验证

工程已完成以下验证：

- 三个 Python 脚本通过静态语法检查；
- 正常天气和极端天气数据能够正确拆分至非配对目录；
- 四类天气训练参数能够完整传递至官方 CycleGAN；
- 生成图像保持原始宽高；
- 合成图与标签文件一一对应；
- YOLO 标签继承前后内容一致；
- 多级源目录转换为唯一输出文件名，避免同名覆盖；
- 生成过程元数据字段完整。

## 12. 参考文献

Zhu J Y, Park T, Isola P, et al. Unpaired Image-to-Image Translation Using Cycle-Consistent Adversarial Networks[C]//Proceedings of the IEEE International Conference on Computer Vision. 2017: 2223–2232.
