# 声源方位串口监视器

Windows 小应用，实时显示：

- 方位角罗盘和角度数值；
- 声音强弱模拟曲线；
- 接收速率、帧间隔和角速度；
- 最近 10 秒趋势曲线。

## 重要说明

声音强度现在由 App 内部生成，是一条平滑、持续上下浮动的模拟曲线，**不读取 FPGA 的声音强度数据**。

因此 FPGA 源代码和串口输出协议都不需要为了声音强度进行修改，只要继续输出原来的方位角即可。

## 启动

```powershell
cd serial_monitor
python -m pip install -r requirements.txt
python app.py
```

也可以直接双击：

```text
serial_monitor\run.bat
```

## 串口连接

1. FPGA `o_uart_tx` 连接 USB-UART 的 RX。
2. FPGA 与 USB-UART 共地。
3. App 中选择对应 COM 口。
4. 波特率选择 `115200`。
5. 点击“连接”。

串口格式：`115200, 8N1`。

> 当前约束中的 `o_uart_tx` 是 `LVCMOS18`（1.8 V），请使用支持 1.8 V 的 USB-UART 或增加电平转换。

## 方位角协议

App 兼容工程原来的 4 字节方位角帧：

```text
A5 ANGLE[23:16] ANGLE[15:8] ANGLE[7:0]
```

方位角为 24 位有符号 Q3.21 弧度：

```text
angle_deg = signed24(raw) / 2^21 * 180 / pi
```

App 也保留了对 9 字节扩展帧的解析兼容，但显示时会忽略其中的声音强度字段。

## 模拟声音强度

模拟强度每 50 ms 更新一次，由几条不同频率的正弦曲线叠加产生，显示范围限制在 18%～88%。

相关代码位于 `app.py` 的 `_fake_strength_tick()`。如果想改变波动范围或速度，可修改：

```python
56.0                         # 中心强度
17.0, 6.0, 3.0              # 波动幅度
1.35, 3.70, 7.10            # 波动速度
```

## 测试

```powershell
python -m unittest discover -s serial_monitor\tests -v
```

## 打包 EXE

```powershell
cd serial_monitor
python -m pip install pyinstaller
.\build_exe.bat
```

生成文件：

```text
serial_monitor\dist\DirectionMonitor.exe
```
