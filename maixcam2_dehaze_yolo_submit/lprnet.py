"""Chinese plate recognition with the 94x24 LPRNet ONNX model."""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort


CHARS = [
    "京", "沪", "津", "渝", "冀", "晋", "蒙", "辽", "吉", "黑",
    "苏", "浙", "皖", "闽", "赣", "鲁", "豫", "鄂", "湘", "粤",
    "桂", "琼", "川", "贵", "云", "藏", "陕", "甘", "青", "宁", "新",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "-",
]
BLANK_INDEX = len(CHARS) - 1


class LPRNetRecognizer:
    def __init__(self, model_path: str | Path) -> None:
        self.model_path = Path(model_path)
        self.session = ort.InferenceSession(
            str(self.model_path), providers=["CPUExecutionProvider"]
        )
        self.input_name = self.session.get_inputs()[0].name

    @staticmethod
    def preprocess(plate_bgr: np.ndarray) -> np.ndarray:
        plate = cv2.resize(plate_bgr, (94, 24), interpolation=cv2.INTER_LINEAR)
        plate = cv2.cvtColor(plate, cv2.COLOR_BGR2RGB).astype(np.float32)
        plate = (plate - 127.5) / 127.5
        return np.transpose(plate, (2, 0, 1))[None]

    @staticmethod
    def decode(logits: np.ndarray) -> tuple[str, float]:
        scores = logits[0]
        scores = scores - scores.max(axis=0, keepdims=True)
        probabilities = np.exp(scores)
        probabilities /= probabilities.sum(axis=0, keepdims=True)
        indices = probabilities.argmax(axis=0)

        decoded = []
        confidences = []
        previous = BLANK_INDEX
        for time_index, char_index in enumerate(indices.tolist()):
            if char_index != BLANK_INDEX and char_index != previous:
                decoded.append(CHARS[char_index])
                confidences.append(float(probabilities[char_index, time_index]))
            previous = char_index
        confidence = float(np.mean(confidences)) if confidences else 0.0
        return "".join(decoded), confidence

    def recognize(self, plate_bgr: np.ndarray) -> tuple[str, float]:
        tensor = self.preprocess(plate_bgr)
        output = self.session.run(None, {self.input_name: tensor})[0]
        return self.decode(output)
