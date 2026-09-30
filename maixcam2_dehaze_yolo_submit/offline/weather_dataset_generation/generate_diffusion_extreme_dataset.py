"""Generate label-safe extreme-weather YOLO data with diffusion + ControlNet."""

import argparse
import csv
import shutil
from pathlib import Path

import cv2
import numpy as np
import torch
from diffusers import ControlNetModel, StableDiffusionControlNetImg2ImgPipeline
from PIL import Image

from generate_extreme_yolo_dataset import (
    list_images,
    paste_label_safe_plates,
    read_yolo_boxes,
)


PROMPTS = {
    "fog": "Chinese road traffic, extremely dense fog, very low visibility, realistic dashcam",
    "rain": "Chinese road traffic, torrential rain, water spray, wet reflections, realistic dashcam",
    "snow": "Chinese road traffic, severe blizzard, wind driven snow, low visibility, realistic dashcam",
    "sand": "Chinese road traffic, severe sandstorm, airborne dust, orange haze, realistic dashcam",
}
NEGATIVE_PROMPT = "changed vehicle, changed license plate, distorted text, extra car, illustration, watermark"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--labels", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--weather", choices=tuple(PROMPTS), nargs="+", default=list(PROMPTS))
    parser.add_argument("--base-model", required=True)
    parser.add_argument("--controlnet", required=True)
    parser.add_argument("--strength", type=float, default=0.72)
    parser.add_argument("--guidance-scale", type=float, default=7.0)
    parser.add_argument("--steps", type=int, default=24)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if device == "cuda" else torch.float32
    controlnet = ControlNetModel.from_pretrained(args.controlnet, torch_dtype=dtype)
    pipeline = StableDiffusionControlNetImg2ImgPipeline.from_pretrained(
        args.base_model,
        controlnet=controlnet,
        torch_dtype=dtype,
        safety_checker=None,
    ).to(device)
    if device == "cuda":
        pipeline.enable_model_cpu_offload()

    output_images = args.output / "images"
    output_labels = args.output / "labels"
    output_images.mkdir(parents=True, exist_ok=True)
    output_labels.mkdir(parents=True, exist_ok=True)
    metadata_path = args.output / "generation_metadata.csv"
    sources = list_images(args.images)

    with metadata_path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.writer(stream)
        writer.writerow(
            ["synthetic_image", "source_image", "weather", "base_model", "controlnet", "strength", "seed"]
        )
        for source_index, source_path in enumerate(sources):
            relative = source_path.relative_to(args.images)
            label_path = (args.labels / relative).with_suffix(".txt")
            source = cv2.imread(str(source_path))
            if source is None:
                continue
            height, width = source.shape[:2]
            boxes = read_yolo_boxes(label_path, width, height)
            rgb = cv2.cvtColor(source, cv2.COLOR_BGR2RGB)
            canny = cv2.Canny(source, 90, 180)
            control_rgb = cv2.cvtColor(canny, cv2.COLOR_GRAY2RGB)

            for weather_index, weather in enumerate(args.weather):
                seed = args.seed + source_index * 100 + weather_index
                generator = torch.Generator(device=device).manual_seed(seed)
                result = pipeline(
                    prompt=PROMPTS[weather],
                    negative_prompt=NEGATIVE_PROMPT,
                    image=Image.fromarray(rgb),
                    control_image=Image.fromarray(control_rgb),
                    strength=args.strength,
                    guidance_scale=args.guidance_scale,
                    num_inference_steps=args.steps,
                    generator=generator,
                ).images[0]
                generated = cv2.cvtColor(np.asarray(result), cv2.COLOR_RGB2BGR)
                generated = cv2.resize(generated, (width, height), interpolation=cv2.INTER_CUBIC)
                rng = np.random.default_rng(seed)
                generated = paste_label_safe_plates(
                    source, generated, boxes, weather, args.strength, rng
                )

                output_name = f"{relative.stem}__{weather}{relative.suffix.lower()}"
                output_image = output_images / output_name
                output_label = output_labels / f"{Path(output_name).stem}.txt"
                cv2.imwrite(str(output_image), generated)
                if label_path.exists():
                    shutil.copy2(label_path, output_label)
                writer.writerow(
                    [output_name, str(source_path), weather, args.base_model, args.controlnet, args.strength, seed]
                )


if __name__ == "__main__":
    main()
