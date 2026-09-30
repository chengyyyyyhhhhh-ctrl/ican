"""Tkinter desktop monitor for FPGA acoustic direction telemetry."""

from __future__ import annotations

from collections import deque
import math
import queue
import threading
import time
import tkinter as tk
from tkinter import messagebox, ttk

try:
    import serial
    from serial.tools import list_ports
except ImportError:  # Friendly error shown when launched without pyserial.
    serial = None
    list_ports = None

try:
    from .protocol import FrameParser, TelemetrySample
except ImportError:
    from protocol import FrameParser, TelemetrySample


BG = "#08111f"
PANEL = "#101d2e"
PANEL_ALT = "#0c1726"
TEXT = "#e7f3ff"
MUTED = "#7f9bb5"
CYAN = "#35d4ff"
GREEN = "#46e6a4"
YELLOW = "#ffd166"
RED = "#ff6178"
GRID = "#21364b"
FONT = "Microsoft YaHei UI"

# Direction-stability calibration. Small frame-to-frame changes are treated
# as measurement noise; only sustained jitter outside the stable band lowers
# the displayed score.
JITTER_DEADBAND_DEG = 1.5
JITTER_STABLE_DEG = 2.0
JITTER_UNSTABLE_DEG = 25.0
JITTER_EMA_ALPHA = 0.08


class DirectionDial(tk.Canvas):
    def __init__(self, master: tk.Misc, **kwargs) -> None:
        super().__init__(master, bg=PANEL, highlightthickness=0, **kwargs)
        self.angle = 0.0
        self.bind("<Configure>", lambda _event: self.redraw())

    def set_angle(self, angle: float) -> None:
        self.angle = angle
        self.redraw()

    def redraw(self) -> None:
        self.delete("all")
        width = max(self.winfo_width(), 10)
        height = max(self.winfo_height(), 10)
        cx, cy = width / 2, height / 2
        radius = max(min(width, height) / 2 - 30, 20)

        self.create_oval(cx - radius, cy - radius, cx + radius, cy + radius,
                         fill=PANEL_ALT, outline=GRID, width=3)
        for deg in range(0, 360, 10):
            major = deg % 30 == 0
            # FPGA/CORDIC convention: +X is 0 degrees and positive angles
            # rotate counter-clockwise.  Canvas Y grows downward, hence -deg.
            rad = math.radians(-deg)
            outer = radius - 5
            inner = radius - (17 if major else 10)
            x1, y1 = cx + inner * math.cos(rad), cy + inner * math.sin(rad)
            x2, y2 = cx + outer * math.cos(rad), cy + outer * math.sin(rad)
            self.create_line(x1, y1, x2, y2, fill=MUTED if major else GRID,
                             width=2 if major else 1)
            if major:
                label_radius = radius - 31
                label = str(deg)
                self.create_text(
                    cx + label_radius * math.cos(rad),
                    cy + label_radius * math.sin(rad),
                    text=label,
                    fill=MUTED,
                    font=(FONT, 9),
                )

        for label, deg in (("+X", 0), ("+Y", 90), ("-X", 180), ("-Y", 270)):
            rad = math.radians(-deg)
            label_radius = radius + 15
            self.create_text(cx + label_radius * math.cos(rad),
                             cy + label_radius * math.sin(rad),
                             text=label, fill=TEXT, font=(FONT, 10, "bold"))

        pointer_rad = math.radians(-self.angle)
        tip_x = cx + (radius - 43) * math.cos(pointer_rad)
        tip_y = cy + (radius - 43) * math.sin(pointer_rad)
        tail_x = cx - 24 * math.cos(pointer_rad)
        tail_y = cy - 24 * math.sin(pointer_rad)
        self.create_line(tail_x, tail_y, tip_x, tip_y, fill=CYAN, width=5,
                         arrow=tk.LAST, arrowshape=(14, 18, 7), capstyle=tk.ROUND)
        self.create_oval(cx - 8, cy - 8, cx + 8, cy + 8, fill=CYAN, outline="#a8efff")


class LevelMeter(tk.Canvas):
    def __init__(self, master: tk.Misc, **kwargs) -> None:
        super().__init__(master, bg=PANEL, height=42, highlightthickness=0, **kwargs)
        self.level = 0.0
        self.bind("<Configure>", lambda _event: self.redraw())

    def set_level(self, level: float) -> None:
        self.level = max(0.0, min(100.0, level))
        self.redraw()

    def redraw(self) -> None:
        self.delete("all")
        width = max(self.winfo_width(), 10)
        height = max(self.winfo_height(), 10)
        margin = 5
        self.create_rectangle(margin, margin, width - margin, height - margin,
                              fill=PANEL_ALT, outline=GRID, width=1)
        fill_width = margin + (width - 2 * margin) * self.level / 100.0
        color = GREEN if self.level < 70 else YELLOW if self.level < 90 else RED
        if fill_width > margin:
            self.create_rectangle(margin, margin, fill_width, height - margin,
                                  fill=color, outline="")
        for ratio in (0.25, 0.5, 0.75):
            x = margin + (width - 2 * margin) * ratio
            self.create_line(x, margin, x, height - margin, fill=GRID)


class HistoryPlot(tk.Canvas):
    def __init__(self, master: tk.Misc, seconds: float = 10.0, **kwargs) -> None:
        super().__init__(master, bg=PANEL_ALT, highlightthickness=0, **kwargs)
        self.seconds = seconds
        self.points: deque[tuple[float, float, float]] = deque(maxlen=2000)
        self.bind("<Configure>", lambda _event: self.redraw())

    def add(self, timestamp: float, angle: float, strength_level: float) -> None:
        self.points.append((timestamp, angle, strength_level))
        cutoff = timestamp - self.seconds
        while self.points and self.points[0][0] < cutoff:
            self.points.popleft()

    def clear(self) -> None:
        self.points.clear()
        self.redraw()

    def redraw(self) -> None:
        self.delete("all")
        width = max(self.winfo_width(), 10)
        height = max(self.winfo_height(), 10)
        left, right, top, bottom = 42, width - 12, 18, height - 26
        if right <= left or bottom <= top:
            return

        for ratio in (0.0, 0.25, 0.5, 0.75, 1.0):
            y = top + (bottom - top) * ratio
            self.create_line(left, y, right, y, fill=GRID)
        for ratio in (0.0, 0.25, 0.5, 0.75, 1.0):
            x = left + (right - left) * ratio
            self.create_line(x, top, x, bottom, fill=GRID)

        self.create_text(8, top, text="+180", anchor="w", fill=MUTED, font=(FONT, 8))
        self.create_text(15, (top + bottom) / 2, text="0", anchor="w", fill=MUTED, font=(FONT, 8))
        self.create_text(8, bottom, text="-180", anchor="w", fill=MUTED, font=(FONT, 8))
        self.create_text(left, height - 9, text=f"-{self.seconds:g}s", fill=MUTED, font=(FONT, 8))
        self.create_text(right, height - 9, text="现在", fill=MUTED, font=(FONT, 8))
        self.create_text(left + 8, top + 9, text="方位角", anchor="w", fill=CYAN, font=(FONT, 9, "bold"))
        self.create_text(left + 68, top + 9, text="相对强度", anchor="w", fill=GREEN, font=(FONT, 9, "bold"))

        if len(self.points) < 2:
            return
        now = self.points[-1][0]
        angle_coords: list[float] = []
        strength_coords: list[float] = []
        for timestamp, angle, strength in self.points:
            x = right - (now - timestamp) / self.seconds * (right - left)
            y_angle = top + (180.0 - angle) / 360.0 * (bottom - top)
            y_strength = bottom - strength / 100.0 * (bottom - top)
            angle_coords.extend((x, y_angle))
            strength_coords.extend((x, y_strength))
        if len(angle_coords) >= 4:
            self.create_line(*angle_coords, fill=CYAN, width=2, smooth=True)
            self.create_line(*strength_coords, fill=GREEN, width=2, smooth=True)


class SerialReader(threading.Thread):
    def __init__(self, port: str, baud: int, output: queue.Queue) -> None:
        super().__init__(daemon=True)
        self.port = port
        self.baud = baud
        self.output = output
        self.stop_event = threading.Event()
        self.connection = None

    def run(self) -> None:
        try:
            self.connection = serial.Serial(self.port, self.baud, timeout=0.1)
            self.output.put(("connected", self.port))
            while not self.stop_event.is_set():
                data = self.connection.read(self.connection.in_waiting or 1)
                if data:
                    self.output.put(("bytes", data))
        except Exception as exc:  # Serial errors need to reach the UI thread.
            self.output.put(("error", str(exc)))
        finally:
            if self.connection is not None:
                try:
                    self.connection.close()
                except Exception:
                    pass
            self.output.put(("stopped", None))

    def stop(self) -> None:
        self.stop_event.set()


class TelemetryApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("声源方位监视器")
        self.root.geometry("1120x760")
        self.root.minsize(920, 650)
        self.root.configure(bg=BG)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        self.parser = FrameParser()
        self.message_queue: queue.Queue = queue.Queue()
        self.reader: SerialReader | None = None
        self.demo_running = False
        self.demo_phase = 0.0

        self.rx_timestamps: deque[float] = deque(maxlen=512)
        self.last_rx_time = 0.0
        self.last_angle: float | None = None
        self.last_sample_time: float | None = None
        self.angular_speed_ema = 0.0
        self.angle_jitter_ema = 0.0
        self.frame_count = 0

        self.port_var = tk.StringVar()
        self.baud_var = tk.StringVar(value="115200")
        self.status_var = tk.StringVar(value="未连接")
        self.angle_var = tk.StringVar(value="--.-°")
        self.angle_sub_var = tk.StringVar(value="等待数据")
        self.strength_var = tk.StringVar(value="--.-%")
        self.strength_sub_var = tk.StringVar(value="等待角度数据")
        self.rate_var = tk.StringVar(value="--.- Hz")
        self.rate_sub_var = tk.StringVar(value="帧间隔 -- ms")
        self.speed_var = tk.StringVar(value="角速度 -- °/s")
        self.protocol_var = tk.StringVar(value="协议：自动识别")

        self._configure_styles()
        self._build_ui()
        self.refresh_ports()
        self.root.after(30, self._poll_messages)
        self.root.after(100, self._refresh_status)

    def _configure_styles(self) -> None:
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TCombobox", fieldbackground=PANEL_ALT, background=PANEL,
                        foreground=TEXT, arrowcolor=TEXT, bordercolor=GRID)
        style.map("TCombobox", fieldbackground=[("readonly", PANEL_ALT)],
                  selectbackground=[("readonly", PANEL_ALT)],
                  selectforeground=[("readonly", TEXT)])

    def _build_ui(self) -> None:
        header = tk.Frame(self.root, bg=BG)
        header.pack(fill="x", padx=24, pady=(18, 12))
        tk.Label(header, text="声源方位监视器", bg=BG, fg=TEXT,
                 font=(FONT, 22, "bold")).pack(side="left")
        tk.Label(header, text="FPGA UART 实时遥测", bg=BG, fg=MUTED,
                 font=(FONT, 10)).pack(side="left", padx=(14, 0), pady=(9, 0))

        connection = tk.Frame(header, bg=BG)
        connection.pack(side="right")
        self.port_combo = ttk.Combobox(connection, textvariable=self.port_var,
                                       width=13, state="readonly")
        self.port_combo.pack(side="left", padx=4)
        ttk.Combobox(connection, textvariable=self.baud_var, width=9, state="readonly",
                     values=("9600", "57600", "115200", "230400", "460800", "921600")).pack(side="left", padx=4)
        self._button(connection, "刷新", self.refresh_ports, PANEL).pack(side="left", padx=4)
        self.connect_button = self._button(connection, "连接", self.toggle_connection, CYAN, dark_text=True)
        self.connect_button.pack(side="left", padx=4)
        self.demo_button = self._button(connection, "演示", self.toggle_demo, PANEL)
        self.demo_button.pack(side="left", padx=4)

        status_line = tk.Frame(self.root, bg=PANEL_ALT, height=38)
        status_line.pack(fill="x", padx=24, pady=(0, 12))
        status_line.pack_propagate(False)
        self.status_dot = tk.Canvas(status_line, width=24, height=24, bg=PANEL_ALT, highlightthickness=0)
        self.status_dot.pack(side="left", padx=(10, 0), pady=7)
        self.status_dot.create_oval(7, 7, 17, 17, fill=MUTED, outline="", tags="dot")
        tk.Label(status_line, textvariable=self.status_var, bg=PANEL_ALT, fg=TEXT,
                 font=(FONT, 10)).pack(side="left", padx=(2, 18))
        tk.Label(status_line, textvariable=self.protocol_var, bg=PANEL_ALT, fg=MUTED,
                 font=(FONT, 9)).pack(side="left")
        self.packet_label = tk.Label(status_line, text="接收 0 帧", bg=PANEL_ALT, fg=MUTED,
                                     font=(FONT, 9))
        self.packet_label.pack(side="right", padx=14)

        body = tk.Frame(self.root, bg=BG)
        body.pack(fill="both", expand=True, padx=24)
        body.grid_columnconfigure(0, weight=5)
        body.grid_columnconfigure(1, weight=4)
        body.grid_rowconfigure(0, weight=1)

        dial_panel = self._panel(body)
        dial_panel.grid(row=0, column=0, sticky="nsew", padx=(0, 7))
        tk.Label(dial_panel, text="方位角", bg=PANEL, fg=MUTED,
                 font=(FONT, 11, "bold")).pack(anchor="w", padx=18, pady=(14, 0))
        self.dial = DirectionDial(dial_panel)
        self.dial.pack(fill="both", expand=True, padx=18, pady=(0, 2))
        tk.Label(dial_panel, textvariable=self.angle_var, bg=PANEL, fg=CYAN,
                 font=(FONT, 34, "bold")).pack()
        tk.Label(dial_panel, textvariable=self.angle_sub_var, bg=PANEL, fg=MUTED,
                 font=(FONT, 9)).pack(pady=(0, 14))

        right = tk.Frame(body, bg=BG)
        right.grid(row=0, column=1, sticky="nsew", padx=(7, 0))
        right.grid_columnconfigure(0, weight=1)
        right.grid_rowconfigure(0, weight=1)
        right.grid_rowconfigure(1, weight=1)

        strength_panel = self._panel(right)
        strength_panel.grid(row=0, column=0, sticky="nsew", pady=(0, 7))
        tk.Label(strength_panel, text="方向稳定度", bg=PANEL, fg=MUTED,
                 font=(FONT, 11, "bold")).pack(anchor="w", padx=18, pady=(14, 0))
        tk.Label(strength_panel, textvariable=self.strength_var, bg=PANEL, fg=GREEN,
                 font=(FONT, 28, "bold")).pack(anchor="w", padx=18, pady=(12, 2))
        tk.Label(strength_panel, textvariable=self.strength_sub_var, bg=PANEL, fg=MUTED,
                 font=(FONT, 9)).pack(anchor="w", padx=18)
        self.level_meter = LevelMeter(strength_panel)
        self.level_meter.pack(fill="x", padx=18, pady=(14, 16))

        rate_panel = self._panel(right)
        rate_panel.grid(row=1, column=0, sticky="nsew", pady=(7, 0))
        tk.Label(rate_panel, text="反应速率", bg=PANEL, fg=MUTED,
                 font=(FONT, 11, "bold")).pack(anchor="w", padx=18, pady=(14, 0))
        tk.Label(rate_panel, textvariable=self.rate_var, bg=PANEL, fg=YELLOW,
                 font=(FONT, 28, "bold")).pack(anchor="w", padx=18, pady=(12, 2))
        tk.Label(rate_panel, textvariable=self.rate_sub_var, bg=PANEL, fg=MUTED,
                 font=(FONT, 9)).pack(anchor="w", padx=18)
        tk.Label(rate_panel, textvariable=self.speed_var, bg=PANEL, fg=MUTED,
                 font=(FONT, 9)).pack(anchor="w", padx=18, pady=(4, 12))

        history_panel = self._panel(self.root)
        history_panel.pack(fill="both", expand=False, padx=24, pady=(14, 20))
        history_header = tk.Frame(history_panel, bg=PANEL)
        history_header.pack(fill="x")
        tk.Label(history_header, text="最近 10 秒", bg=PANEL, fg=MUTED,
                 font=(FONT, 10, "bold")).pack(side="left", padx=16, pady=(10, 0))
        self._button(history_header, "清空", self.clear_history, PANEL_ALT).pack(side="right", padx=12, pady=(7, 0))
        self.history = HistoryPlot(history_panel, height=170)
        self.history.pack(fill="both", expand=True, padx=10, pady=(0, 10))

    @staticmethod
    def _panel(master: tk.Misc) -> tk.Frame:
        return tk.Frame(master, bg=PANEL, highlightbackground=GRID, highlightthickness=1)

    @staticmethod
    def _button(master: tk.Misc, text: str, command, color: str, dark_text: bool = False) -> tk.Button:
        return tk.Button(master, text=text, command=command, bg=color,
                         activebackground=color, fg=BG if dark_text else TEXT,
                         activeforeground=BG if dark_text else TEXT,
                         relief="flat", borderwidth=0, padx=12, pady=5,
                         font=(FONT, 9, "bold"), cursor="hand2")

    def refresh_ports(self) -> None:
        if list_ports is None:
            return
        ports = [port.device for port in list_ports.comports()]
        self.port_combo["values"] = ports
        if ports and self.port_var.get() not in ports:
            self.port_var.set(ports[0])
        elif not ports:
            self.port_var.set("")

    def toggle_connection(self) -> None:
        if self.reader is not None:
            self.disconnect()
            return
        if serial is None:
            messagebox.showerror("缺少依赖", "未安装 pyserial，请执行：pip install pyserial")
            return
        port = self.port_var.get()
        if not port:
            messagebox.showwarning("未选择串口", "没有检测到串口，请连接 USB 串口后点击“刷新”。")
            return
        self.stop_demo()
        self.parser.reset()
        self.status_var.set(f"正在连接 {port} ...")
        self._set_status_color(YELLOW)
        self.reader = SerialReader(port, int(self.baud_var.get()), self.message_queue)
        self.reader.start()
        self.connect_button.configure(text="断开")

    def disconnect(self) -> None:
        if self.reader is not None:
            self.reader.stop()
            self.reader = None
        self.connect_button.configure(text="连接")
        self.status_var.set("未连接")
        self._set_status_color(MUTED)

    def toggle_demo(self) -> None:
        if self.demo_running:
            self.stop_demo()
        else:
            self.disconnect()
            self.demo_running = True
            self.demo_button.configure(text="停止演示")
            self.status_var.set("演示模式 · 20 Hz")
            self.protocol_var.set("协议：模拟扩展帧")
            self._set_status_color(GREEN)
            self._demo_tick()

    def stop_demo(self) -> None:
        self.demo_running = False
        self.demo_button.configure(text="演示")

    def _demo_tick(self) -> None:
        if not self.demo_running:
            return
        self.demo_phase += 0.055
        angle = 115.0 * math.sin(self.demo_phase) + 25.0 * math.sin(self.demo_phase * 0.31)
        strength_ratio = 0.03 + 0.55 * (0.5 + 0.5 * math.sin(self.demo_phase * 1.7)) ** 2
        raw_radians = int(math.radians(angle) * (1 << 21))
        sample = TelemetrySample(raw_radians, angle, int(strength_ratio * STRENGTH_FULL_SCALE), "demo")
        self._handle_sample(sample)
        self.root.after(50, self._demo_tick)

    def _poll_messages(self) -> None:
        try:
            while True:
                kind, payload = self.message_queue.get_nowait()
                if kind == "bytes":
                    for sample in self.parser.feed(payload):
                        self._handle_sample(sample)
                elif kind == "connected":
                    self.status_var.set(f"已连接 {payload} · {self.baud_var.get()} 8N1")
                    self._set_status_color(GREEN)
                elif kind == "error":
                    self.status_var.set(f"串口错误：{payload}")
                    self._set_status_color(RED)
                    self.connect_button.configure(text="连接")
                    self.reader = None
                elif kind == "stopped" and self.reader is not None and not self.reader.is_alive():
                    self.reader = None
        except queue.Empty:
            pass
        self.root.after(30, self._poll_messages)

    def _handle_sample(self, sample: TelemetrySample) -> None:
        now = time.perf_counter()
        self.frame_count += 1
        self.last_rx_time = now
        self.rx_timestamps.append(now)
        cutoff = now - 2.0
        while self.rx_timestamps and self.rx_timestamps[0] < cutoff:
            self.rx_timestamps.popleft()

        interval_ms = None
        if self.last_sample_time is not None:
            dt = now - self.last_sample_time
            if dt > 0:
                interval_ms = dt * 1000.0
                if self.last_angle is not None:
                    delta = (sample.angle_deg - self.last_angle + 180.0) % 360.0 - 180.0
                    speed = delta / dt
                    self.angular_speed_ema = 0.25 * speed + 0.75 * self.angular_speed_ema
                    calibrated_jitter = max(0.0, abs(delta) - JITTER_DEADBAND_DEG)
                    self.angle_jitter_ema = (
                        JITTER_EMA_ALPHA * calibrated_jitter
                        + (1.0 - JITTER_EMA_ALPHA) * self.angle_jitter_ema
                    )
        self.last_sample_time = now
        self.last_angle = sample.angle_deg

        fps = 0.0
        if len(self.rx_timestamps) >= 2:
            span = self.rx_timestamps[-1] - self.rx_timestamps[0]
            if span > 0:
                fps = (len(self.rx_timestamps) - 1) / span

        # Keep the meter pinned at 100% inside the stable band, then map the
        # calibrated jitter to 0% only after it reaches the unstable limit.
        if self.angle_jitter_ema <= JITTER_STABLE_DEG:
            strength_level = 100.0
        elif self.angle_jitter_ema >= JITTER_UNSTABLE_DEG:
            strength_level = 0.0
        else:
            strength_level = 100.0 * (
                JITTER_UNSTABLE_DEG - self.angle_jitter_ema
            ) / (JITTER_UNSTABLE_DEG - JITTER_STABLE_DEG)
        self.strength_var.set(f"{strength_level:4.1f}%")
        self.strength_sub_var.set(f"角度平均抖动 {self.angle_jitter_ema:.1f}°")
        self.level_meter.set_level(strength_level)

        # Keep the displayed value identical to the FPGA/motor convention:
        # signed absolute azimuth in [-180, +180) degrees.
        self.angle_var.set(f"{sample.angle_deg:+06.1f}°")
        self.angle_sub_var.set(f"有符号角 {sample.angle_deg:+.2f}° · 原始值 {sample.raw_angle} (Q3.21)")
        self.rate_var.set(f"{fps:5.1f} Hz")
        self.rate_sub_var.set(f"帧间隔 {interval_ms:.1f} ms" if interval_ms is not None else "帧间隔 -- ms")
        self.speed_var.set(f"角速度 {self.angular_speed_ema:+.1f} °/s")
        protocol_name = {"extended": "扩展9字节", "legacy": "旧版4字节", "demo": "模拟扩展帧"}.get(sample.protocol, sample.protocol)
        self.protocol_var.set(f"协议：{protocol_name}")
        self.packet_label.configure(text=f"接收 {self.frame_count:,} 帧 · 校验错 {self.parser.bad_checksums}")
        self.dial.set_angle(sample.angle_deg)
        self.history.add(now, sample.angle_deg, strength_level)
        self.history.redraw()

    def _refresh_status(self) -> None:
        if self.last_rx_time and not self.demo_running and time.perf_counter() - self.last_rx_time > 1.0:
            if self.reader is not None:
                self._set_status_color(YELLOW)
                self.status_var.set(f"已连接 {self.port_var.get()}，但超过1秒未收到有效帧")
        self.root.after(100, self._refresh_status)

    def _set_status_color(self, color: str) -> None:
        self.status_dot.itemconfigure("dot", fill=color)

    def clear_history(self) -> None:
        self.history.clear()
        self.frame_count = 0
        self.packet_label.configure(text="接收 0 帧")
        self.rx_timestamps.clear()

    def on_close(self) -> None:
        self.stop_demo()
        if self.reader is not None:
            self.reader.stop()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    TelemetryApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
