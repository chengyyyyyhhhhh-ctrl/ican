"""Generate label-safe extreme-weather images with trained CycleGAN generators."""

import argparse
import csv
import importlib
import random
import sys
from pathlib import Path

import cv2
import numpy as np
import torch


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
WEATHER_TYPES = {"fog", "rain", "snow", "sand"}


def parse_model(value: str) -> tuple[str, Path]:
    try:
        weather, checkpoint = value.split("=", 1)
    except ValueError as error:
        raise argparse.ArgumentTypeError("模型参数格式必须是 WEATHER=CHECKPOINT") from error
    if weather not in WEATHER_TYPES:
        raise argparse.ArgumentTypeError(f"不支持的天气类型：{weather}")
    return weather, Path(checkpoint).expanduser().resolve()


def list_images(root: Path) -> list[Path]:
    return sorted(
        path for path in root.rglob("*") if path.suffix.lower() in IMAGE_EXTENSIONS
    )


def load_generator(repo: Path, checkpoint: Path, device: torch.device) -> torch.nn.Module:
    sys.path.insert(0, str(repo))
    try:
        networks = importlib.import_module("models.networks")
    finally:
        sys.path.pop(0)

    generator = networks.define_G(
        3,
        3,
        64,
        "resnet_9blocks",
        "instance",
        False,
        "normal",
        0.02,
        [],
    )
    try:
        state = torch.load(checkpoint, map_location=device, weights_only=True)
    except TypeError:
        state = torch.load(checkpoint, map_location=device)
    if state and next(iter(state)).startswith("module."):
        state = {key.removeprefix("module."): value for key, value in state.items()}
    generator.load_state_dict(state)
    return generator.to(device).eval()


def resize_for_inference(image: np.ndarray, max_side: int) -> np.ndarray:
    height, width = image.shape[:2]
    scale = min(1.0, max_side / max(height, width)) if max_side > 0 else 1.0
    if scale == 1.0:
        return image
    return cv2.resize(
        image,
        (round(width * scale), round(height * scale)),
        interpolation=cv2.INTER_AREA,
    )


def run_generator(
    generator: torch.nn.Module,
    bgr: np.ndarray,
    device: torch.device,
    max_side: int,
) -> np.ndarray:
    original_height, original_width = bgr.shape[:2]
    resized = resize_for_inference(bgr, max_side)
    rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
    height, width = rgb.shape[:2]
    pad_bottom = (-height) % 4
    pad_right = (-width) % 4
    rgb = cv2.copyMakeBorder(
        rgb, 0, pad_bottom, 0, pad_right, cv2.BORDER_REFLECT_101
    )

    tensor = torch.from_numpy(rgb).permute(2, 0, 1).float().div(127.5).sub(1.0)
    tensor = tensor.unsqueeze(0).to(device)
    with torch.inference_mode():
        generated = generator(tensor)[0].clamp(-1, 1)
    generated = (
        generated.add(1.0)
        .mul(127.5)
        .byte()
        .permute(1, 2, 0)
        .cpu()
        .numpy()
    )
    generated = generated[:height, :width]
    generated = cv2.cvtColor(generated, cv2.COLOR_RGB2BGR)
    if generated.shape[:2] != (original_height, original_width):
        generated = cv2.resize(
            generated,
            (original_width, original_height),
            interpolation=cv2.INTER_CUBIC,
        )
    return generated


def read_yolo_boxes(label_path: Path, width: int, height: int) -> list[tuple[int, int, int, int]]:
    if not label_path.exists():
        return []
    boxes = []
    for line in label_path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) != 5:
            continue
        _, center_x, center_y, box_width, box_height = fields
        cx = float(center_x) * width
        cy = float(center_y) * height
        bw = float(box_width) * width
        bh = float(box_height) * height
        x1 = max(0, round(cx - bw / 2))
        y1 = max(0, round(cy - bh / 2))
        x2 = min(width, round(cx + bw / 2))
        y2 = min(height, round(cy + bh / 2))
        if x2 > x1 and y2 > y1:
            boxes.append((x1, y1, x2, y2))
    return boxes


def degrade_plate(
    plate: np.ndarray,
    weather: str,
    strength: float,
    rng: np.random.Generator,
) -> np.ndarray:
    """Apply weather degradation without inventing new plate characters."""
    if strength <= 0:
        return plate.copy()
    output = plate.copy()
    blur_sigma = 0.35 + 1.2 * strength
    output = cv2.GaussianBlur(output, (0, 0), blur_sigma)

    if weather == "fog":
        veil = np.full_like(output, 225)
        output = cv2.addWeighted(output, 1.0 - 0.35 * strength, veil, 0.35 * strength, 0)
    elif weather == "rain":
        overlay = output.copy()
        count = max(1, round(output.shape[1] * strength / 16))
        for _ in range(count):
            x = int(rng.integers(0, max(1, output.shape[1])))
            length = max(2, round(output.shape[0] * 0.45))
            cv2.line(overlay, (x, 0), (x - length // 3, length), (205, 205, 205), 1)
        output = cv2.addWeighted(output, 0.82, overlay, 0.18, 0)
    elif weather == "snow":
        veil = np.full_like(output, 235)
        output = cv2.addWeighted(output, 1.0 - 0.25 * strength, veil, 0.25 * strength, 0)
        count = max(1, round(output.shape[1] * output.shape[0] * strength / 220))
        for _ in range(count):
            x = int(rng.integers(0, max(1, output.shape[1])))
            y = int(rng.integers(0, max(1, output.shape[0])))
            cv2.circle(output, (x, y), 1, (245, 245, 245), -1)
    elif weather == "sand":
        sand_color = np.full_like(output, (80, 155, 220))
        output = cv2.addWeighted(
            output, 1.0 - 0.32 * strength, sand_color, 0.32 * strength, 0
        )
        noise = rng.normal(0, 7.0 * strength, output.shape).astype(np.float32)
        output = np.clip(output.astype(np.float32) + noise, 0, 255).astype(np.uint8)
    return output


def paste_label_safe_plates(
    source: np.ndarray,
    generated: np.ndarray,
    boxes: list[tuple[int, int, int, int]],
    weather: str,
    strength: float,
    rng: np.random.Generator,
) -> np.ndarray:
    result = generated.copy()
    for x1, y1, x2, y2 in boxes:
        plate = source[y1:y2, x1:x2]
        degraded = degrade_plate(plate, weather, strength, rng)
        height, width = plate.shape[:2]
        feather = max(1, min(5, min(height, width) // 6))
        mask = np.zeros((height, width), np.float32)
        if width > feather * 2 and height > feather * 2:
            mask[feather:-feather, feather:-feather] = 1.0
            mask = cv2.GaussianBlur(mask, (0, 0), max(0.8, feather / 2))
        else:
            mask.fill(1.0)
        roi = result[y1:y2, x1:x2].astype(np.float32)
        mixed = degraded.astype(np.float32) * mask[..., None] + roi * (1 - mask[..., None])
        result[y1:y2, x1:x2] = np.clip(mixed, 0, 255).astype(np.uint8)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cyclegan-repo", type=Path, required=True)
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--labels", type=Path, required=True)
    parser.add_argument(
        "--model",
        action="append",
        type=parse_model,
        required=True,
        metavar="WEATHER=CHECKPOINT",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--max-side", type=int, default=1280)
    parser.add_argument("--strength", type=float, default=0.75)
    parser.add_argument(
        "--plate-mode",
        choices=("degrade", "preserve", "generated"),
        default="degrade",
        help="degrade 保留真实字符后加天气退化；preserve 原样保留；generated 完全采用模型结果",
    )
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    if not 0 <= args.strength <= 1:
        parser.error("--strength 必须位于 [0, 1]")
    repo = args.cyclegan_repo.expanduser().resolve()
    if not (repo / "models" / "networks.py").exists():
        parser.error(f"不是有效的官方 CycleGAN 仓库：{repo}")

    image_root = args.images.expanduser().resolve()
    label_root = args.labels.expanduser().resolve()
    output_root = args.output.expanduser().resolve()
    output_images = output_root / "images"
    output_labels = output_root / "labels"
    output_images.mkdir(parents=True, exist_ok=True)
    output_labels.mkdir(parents=True, exist_ok=True)

    images = list_images(image_root)
    if not images:
        parser.error(f"没有找到输入图片：{image_root}")

    device = torch.device(args.device)
    metadata_path = output_root / "generation_metadata.csv"
    with metadata_path.open("w", newline="", encoding="utf-8-sig") as metadata_file:
        writer = csv.writer(metadata_file)
        writer.writerow(
            ["synthetic_image", "source_image", "weather", "checkpoint", "strength", "seed"]
        )

        for model_index, (weather, checkpoint) in enumerate(args.model):
            if not checkpoint.exists():
                parser.error(f"模型权重不存在：{checkpoint}")
            generator = load_generator(repo, checkpoint, device)

            for image_index, source_path in enumerate(images):
                relative = source_path.relative_to(image_root)
                label_path = (label_root / relative).with_suffix(".txt")
                source = cv2.imread(str(source_path), cv2.IMREAD_COLOR)
                if source is None:
                    print(f"跳过无法读取的图片：{source_path}")
                    continue

                generated = run_generator(generator, source, device, args.max_side)
                boxes = read_yolo_boxes(label_path, source.shape[1], source.shape[0])
                sample_seed = args.seed + model_index * 1_000_000 + image_index
                rng = np.random.default_rng(sample_seed)
                if args.plate_mode == "degrade":
                    generated = paste_label_safe_plates(
                        source, generated, boxes, weather, args.strength, rng
                    )
                elif args.plate_mode == "preserve":
                    generated = paste_label_safe_plates(
                        source, generated, boxes, weather, 0.0, rng
                    )

                source_id = relative.with_suffix("").as_posix().replace("/", "__")
                output_name = f"{source_id}__{weather}.jpg"
                output_image = output_images / output_name
                output_label = output_labels / f"{Path(output_name).stem}.txt"
                cv2.imwrite(str(output_image), generated, [cv2.IMWRITE_JPEG_QUALITY, 95])
                if label_path.exists():
                    output_label.write_text(label_path.read_text(encoding="utf-8"), encoding="utf-8")
                else:
                    output_label.write_text("", encoding="utf-8")
                writer.writerow(
                    [output_image.name, str(source_path), weather, str(checkpoint), args.strength, sample_seed]
                )

            del generator
            if device.type == "cuda":
                torch.cuda.empty_cache()

    print(f"生成完成：{output_root}")


if __name__ == "__main__":
    main()
