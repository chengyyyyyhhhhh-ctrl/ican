"""PC verification pipeline: optional dehaze -> YOLOv8 -> LPRNet -> video output."""

import argparse
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont

from dehaze import fast_dehaze, low_visibility_score, needs_dehaze
from lprnet import LPRNetRecognizer


ROOT = Path(__file__).resolve().parent


def letterbox(bgr: np.ndarray, size: int = 640):
    height, width = bgr.shape[:2]
    scale = min(size / width, size / height)
    new_width = round(width * scale)
    new_height = round(height * scale)
    resized = cv2.resize(bgr, (new_width, new_height), interpolation=cv2.INTER_LINEAR)
    pad_x = (size - new_width) // 2
    pad_y = (size - new_height) // 2
    canvas = np.full((size, size, 3), 114, dtype=np.uint8)
    canvas[pad_y:pad_y + new_height, pad_x:pad_x + new_width] = resized
    return canvas, scale, pad_x, pad_y


class PlateDetector:
    def __init__(self, model_path: Path, conf: float = 0.45, iou: float = 0.45):
        self.session = ort.InferenceSession(
            str(model_path), providers=["CPUExecutionProvider"]
        )
        self.input_name = self.session.get_inputs()[0].name
        self.conf = conf
        self.iou = iou

    def detect(self, bgr: np.ndarray):
        model_image, scale, pad_x, pad_y = letterbox(bgr)
        rgb = cv2.cvtColor(model_image, cv2.COLOR_BGR2RGB)
        tensor = np.transpose(rgb.astype(np.float32) / 255.0, (2, 0, 1))[None]
        predictions = self.session.run(None, {self.input_name: tensor})[0][0].T
        predictions = predictions[predictions[:, 4] >= self.conf]
        if len(predictions) == 0:
            return []

        xywh = predictions[:, :4]
        scores = predictions[:, 4]
        boxes = []
        for center_x, center_y, width, height in xywh:
            x = (center_x - width / 2 - pad_x) / scale
            y = (center_y - height / 2 - pad_y) / scale
            boxes.append([float(x), float(y), float(width / scale), float(height / scale)])
        indices = cv2.dnn.NMSBoxes(boxes, scores.tolist(), self.conf, self.iou)
        output = []
        image_height, image_width = bgr.shape[:2]
        for index in np.array(indices).reshape(-1).tolist():
            x, y, width, height = boxes[index]
            x1 = max(0, round(x))
            y1 = max(0, round(y))
            x2 = min(image_width, round(x + width))
            y2 = min(image_height, round(y + height))
            if x2 > x1 and y2 > y1:
                output.append((x1, y1, x2, y2, float(scores[index])))
        return output


def find_chinese_font(size: int = 20):
    candidates = [
        Path("assets/SourceHanSansCN-Regular.otf"),
        Path("/System/Library/Fonts/PingFang.ttc"),
        Path("/System/Library/Fonts/STHeiti Light.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf"),
        Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


LABEL_FONT = find_chinese_font()


def draw_label(frame: np.ndarray, x: int, y: int, text: str) -> None:
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    canvas = Image.fromarray(rgb)
    draw = ImageDraw.Draw(canvas)
    text_box = draw.textbbox((0, 0), text, font=LABEL_FONT)
    text_width = text_box[2] - text_box[0]
    text_height = text_box[3] - text_box[1]
    top = max(0, y - text_height - 10)
    draw.rectangle((x, top, x + text_width + 10, y), fill=(0, 110, 0))
    draw.text((x + 5, top + 3), text, font=LABEL_FONT, fill=(255, 255, 255))
    frame[:] = cv2.cvtColor(np.asarray(canvas), cv2.COLOR_RGB2BGR)


def process_frame(frame, detector, recognizer, dehaze_mode: str):
    visibility = low_visibility_score(frame)
    use_dehaze = dehaze_mode == "on" or (
        dehaze_mode == "auto" and needs_dehaze(frame)
    )
    working = fast_dehaze(frame) if use_dehaze else frame.copy()

    for x1, y1, x2, y2, detection_score in detector.detect(working):
        plate = working[y1:y2, x1:x2]
        text, recognition_score = recognizer.recognize(plate)
        cv2.rectangle(working, (x1, y1), (x2, y2), (0, 255, 0), 2)
        label = f"车牌 {detection_score:.2f}  {text}  识别 {recognition_score:.2f}"
        draw_label(working, x1, y1, label)
    cv2.putText(
        working,
        f"low_visibility={visibility:.2f} dehaze={'on' if use_dehaze else 'off'}",
        (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 80, 0), 2, cv2.LINE_AA,
    )
    return working


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="image/video path or camera index")
    parser.add_argument("--output", required=True)
    parser.add_argument("--detector", default=str(ROOT / "models/license_plate_yolov8.onnx"))
    parser.add_argument("--recognizer", default=str(ROOT / "models/lprnet_chinese_plate.onnx"))
    parser.add_argument("--dehaze", choices=("auto", "on", "off"), default="auto")
    args = parser.parse_args()

    detector = PlateDetector(Path(args.detector))
    recognizer = LPRNetRecognizer(Path(args.recognizer))
    source_path = Path(args.source)
    output_path = Path(args.output)

    image = cv2.imread(str(source_path)) if source_path.is_file() else None
    if image is not None:
        result = process_frame(image, detector, recognizer, args.dehaze)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        if not cv2.imwrite(str(output_path), result):
            raise RuntimeError(f"cannot write {output_path}")
        return

    capture_source = int(args.source) if args.source.isdigit() else args.source
    capture = cv2.VideoCapture(capture_source)
    if not capture.isOpened():
        raise RuntimeError(f"cannot open source: {args.source}")
    fps = capture.get(cv2.CAP_PROP_FPS) or 25.0
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(
        str(output_path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height)
    )
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        writer.write(process_frame(frame, detector, recognizer, args.dehaze))
    capture.release()
    writer.release()


if __name__ == "__main__":
    main()
