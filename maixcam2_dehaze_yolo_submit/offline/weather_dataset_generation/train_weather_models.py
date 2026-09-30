"""Train one official CycleGAN model for each extreme-weather domain."""

import argparse
import subprocess
import sys
from pathlib import Path


WEATHER_TYPES = ("fog", "rain", "snow", "sand")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cyclegan-repo", type=Path, required=True)
    parser.add_argument("--datasets", type=Path, required=True)
    parser.add_argument("--checkpoints", type=Path, required=True)
    parser.add_argument(
        "--weather", choices=(*WEATHER_TYPES, "all"), default="all"
    )
    parser.add_argument("--gpu-ids", default="0", help="CPU 使用 -1")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--decay-epochs", type=int, default=100)
    parser.add_argument("--load-size", type=int, default=286)
    parser.add_argument("--crop-size", type=int, default=256)
    parser.add_argument("--continue-train", action="store_true")
    args = parser.parse_args()

    repo = args.cyclegan_repo.expanduser().resolve()
    train_script = repo / "train.py"
    if not train_script.exists():
        parser.error(f"没有找到官方 CycleGAN train.py：{train_script}")

    selected = WEATHER_TYPES if args.weather == "all" else (args.weather,)
    for weather in selected:
        dataroot = args.datasets.expanduser().resolve() / weather
        if not (dataroot / "trainA").exists() or not (dataroot / "trainB").exists():
            parser.error(f"数据目录不完整：{dataroot}")

        command = [
            sys.executable,
            str(train_script),
            "--dataroot",
            str(dataroot),
            "--name",
            f"{weather}_cyclegan",
            "--model",
            "cycle_gan",
            "--direction",
            "AtoB",
            "--checkpoints_dir",
            str(args.checkpoints.expanduser().resolve()),
            "--gpu_ids",
            args.gpu_ids,
            "--display_id",
            "-1",
            "--preprocess",
            "resize_and_crop",
            "--load_size",
            str(args.load_size),
            "--crop_size",
            str(args.crop_size),
            "--batch_size",
            "1",
            "--n_epochs",
            str(args.epochs),
            "--n_epochs_decay",
            str(args.decay_epochs),
            "--save_epoch_freq",
            "10",
        ]
        if args.continue_train:
            command.append("--continue_train")

        print("运行：", " ".join(command), flush=True)
        subprocess.run(command, cwd=repo, check=True)


if __name__ == "__main__":
    main()
