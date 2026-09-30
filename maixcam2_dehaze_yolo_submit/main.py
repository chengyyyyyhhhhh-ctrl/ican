"""MaixCAM2: camera -> optional dehaze -> YOLOv5 -> plate OCR."""

import cv2
import os
import re

from maix import app, camera, display, image, nn

from dehaze import fast_dehaze, low_visibility_score, needs_dehaze


# The MUD and its two AXModel files must stay in /root/models/.
MODEL_PATH = "/root/models/model_249078.mud"
OCR_MODEL_PATH = "/root/models/pp_ocr.mud"

CONFIDENCE_THRESHOLD = 0.45
IOU_THRESHOLD = 0.45
DEHAZE_MODE = "auto"  # "auto", "on" or "off"
ENABLE_OCR = True

# Dehazing strength. Increase OMEGA for thicker fog; do not normally exceed 0.95.
DEHAZE_SCALE = 0.35
DEHAZE_OMEGA = 0.90
DEHAZE_MIN_TRANSMISSION = 0.18
DEHAZE_RADIUS = 5
DEHAZE_AUTO_THRESHOLD = 0.52


def normalize_plate_text(value: str) -> str:
    parts = re.findall(r"[\u4e00-\u9fa5A-Za-z0-9]+", value.upper())
    return "".join(parts)


def is_chinese_plate(value: str) -> bool:
    if len(value) not in (7, 8):
        return False
    if not ("\u4e00" <= value[0] <= "\u9fff"):
        return False
    return value[1].isalpha() and value[1].isascii()


def create_ocr():
    if not ENABLE_OCR or not os.path.exists(OCR_MODEL_PATH):
        return None
    return nn.PP_OCR(OCR_MODEL_PATH)


def recognize_plate(ocr, frame, x: int, y: int, width: int, height: int) -> str:
    if ocr is None:
        return ""
    margin_x = max(2, round(width * 0.04))
    margin_y = max(2, round(height * 0.08))
    left = max(0, x - margin_x)
    top = max(0, y - margin_y)
    right = min(frame.width(), x + width + margin_x)
    bottom = min(frame.height(), y + height + margin_y)
    roi = frame.crop(left, top, right - left, bottom - top)
    roi = roi.to_format(image.Format.FMT_BGR888)
    candidates = []
    for result in ocr.detect(roi):
        text = normalize_plate_text(result.char_str())
        if text:
            candidates.append(text)
    for text in candidates:
        if is_chinese_plate(text):
            return text
    return max(candidates, key=len) if candidates else ""


def main() -> None:
    # Disable dual buffering so each box belongs to the frame being displayed.
    detector = nn.YOLOv5(model=MODEL_PATH, dual_buff=False)
    ocr = create_ocr()
    cam = camera.Camera(
        detector.input_width(),
        detector.input_height(),
        detector.input_format(),
        buff_num=2,
    )
    disp = display.Display()

    while not app.need_exit():
        frame = cam.read()

        bgr = image.image2cv(frame, ensure_bgr=True, copy=True)
        visibility_score = low_visibility_score(bgr)
        apply_dehaze = DEHAZE_MODE == "on" or (
            DEHAZE_MODE == "auto"
            and needs_dehaze(bgr, threshold=DEHAZE_AUTO_THRESHOLD)
        )

        if apply_dehaze:
            bgr = fast_dehaze(
                bgr,
                estimate_scale=DEHAZE_SCALE,
                omega=DEHAZE_OMEGA,
                min_transmission=DEHAZE_MIN_TRANSMISSION,
                radius=DEHAZE_RADIUS,
            )
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            frame = image.cv2image(rgb, bgr=False, copy=True)

        objects = detector.detect(
            frame,
            conf_th=CONFIDENCE_THRESHOLD,
            iou_th=IOU_THRESHOLD,
        )

        for obj in objects:
            x = max(0, obj.x)
            y = max(0, obj.y)
            width = min(obj.w, frame.width() - x)
            height = min(obj.h, frame.height() - y)
            if width <= 0 or height <= 0:
                continue

            plate_text = recognize_plate(ocr, frame, x, y, width, height)
            frame.draw_rect(x, y, width, height, image.COLOR_GREEN, thickness=2)
            text_y = max(0, y - 24)
            label = f"车牌 {obj.score:.2f}"
            if plate_text:
                label = f"{label} {plate_text}"
            frame.draw_string(
                x,
                text_y,
                label,
                color=image.COLOR_GREEN,
                scale=1.0,
            )

        frame.draw_string(
            8,
            8,
            f"低能见度 {visibility_score:.2f} 去雾 {'开' if apply_dehaze else '关'}",
            color=image.COLOR_BLUE,
            scale=0.8,
        )

        disp.show(frame)


if __name__ == "__main__":
    main()
