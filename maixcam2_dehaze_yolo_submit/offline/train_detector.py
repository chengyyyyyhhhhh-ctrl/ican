"""Train and export the 640x640 single-class YOLO detector."""

import argparse
from pathlib import Path

from ultralytics import YOLO


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=Path("configs/license_plate.yaml"))
    parser.add_argument("--weights", default="yolov8n.pt")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--batch", type=int, default=16)
    parser.add_argument("--device", default="0")
    parser.add_argument("--project", default="runs/extreme_weather_plate")
    args = parser.parse_args()

    model = YOLO(args.weights)
    model.train(
        data=str(args.data),
        imgsz=640,
        epochs=args.epochs,
        batch=args.batch,
        device=args.device,
        project=args.project,
        name="yolo_plate",
        patience=30,
        close_mosaic=10,
        degrees=3.0,
        translate=0.08,
        scale=0.35,
        fliplr=0.5,
        flipud=0.0,
    )
    model.export(format="onnx", imgsz=640, dynamic=False, simplify=True, opset=12)


if __name__ == "__main__":
    main()
