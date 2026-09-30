"""Build unpaired CycleGAN folders from normal and extreme-weather images."""

import argparse
import random
import shutil
from pathlib import Path


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def image_files(root: Path) -> list[Path]:
    return sorted(
        path for path in root.rglob("*") if path.suffix.lower() in IMAGE_EXTENSIONS
    )


def split_files(files: list[Path], test_ratio: float, seed: int) -> tuple[list[Path], list[Path]]:
    shuffled = files.copy()
    random.Random(seed).shuffle(shuffled)
    if len(shuffled) < 2 or test_ratio == 0:
        return shuffled, []
    test_count = max(1, round(len(shuffled) * test_ratio))
    test_count = min(test_count, len(shuffled) - 1)
    return shuffled[test_count:], shuffled[:test_count]


def copy_split(files: list[Path], source_root: Path, target_root: Path) -> None:
    for source in files:
        relative = source.relative_to(source_root)
        target = target_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def parse_weather(value: str) -> tuple[str, Path]:
    try:
        name, directory = value.split("=", 1)
    except ValueError as error:
        raise argparse.ArgumentTypeError("天气参数格式必须是 NAME=DIR") from error
    if name not in {"fog", "rain", "snow", "sand"}:
        raise argparse.ArgumentTypeError(f"不支持的天气类型：{name}")
    return name, Path(directory).expanduser().resolve()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--normal", type=Path, required=True, help="正常天气图片目录")
    parser.add_argument(
        "--weather",
        type=parse_weather,
        action="append",
        required=True,
        metavar="NAME=DIR",
        help="极端天气图片，格式为 NAME=DIR；该参数支持重复传入",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--test-ratio", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    normal_root = args.normal.expanduser().resolve()
    output_root = args.output.expanduser().resolve()
    if not 0 <= args.test_ratio < 1:
        parser.error("--test-ratio 必须位于 [0, 1) 范围")

    normal = image_files(normal_root)
    if not normal:
        parser.error(f"正常天气目录中没有图片：{normal_root}")

    for weather_index, (weather_name, extreme_root) in enumerate(args.weather):
        extreme = image_files(extreme_root)
        if not extreme:
            parser.error(f"极端天气目录中没有图片：{extreme_root}")

        normal_train, normal_test = split_files(
            normal, args.test_ratio, args.seed + weather_index
        )
        extreme_train, extreme_test = split_files(
            extreme, args.test_ratio, args.seed + 100 + weather_index
        )
        weather_output = output_root / weather_name
        copy_split(normal_train, normal_root, weather_output / "trainA")
        copy_split(normal_test, normal_root, weather_output / "testA")
        copy_split(extreme_train, extreme_root, weather_output / "trainB")
        copy_split(extreme_test, extreme_root, weather_output / "testB")

        print(
            f"{weather_name}: trainA={len(normal_train)}, trainB={len(extreme_train)}, "
            f"testA={len(normal_test)}, testB={len(extreme_test)}"
        )


if __name__ == "__main__":
    main()
