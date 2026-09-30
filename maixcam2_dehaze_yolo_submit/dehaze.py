"""Fast dark-channel dehazing for MaixCAM2 camera frames."""

import cv2
import numpy as np


def low_visibility_score(bgr: np.ndarray) -> float:
    """Return a lightweight haze/low-contrast score in the range [0, 1]."""
    if bgr.dtype != np.uint8 or bgr.ndim != 3 or bgr.shape[2] != 3:
        raise ValueError("bgr must be an HxWx3 uint8 image")
    sample = cv2.resize(bgr, (160, 96), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(sample, cv2.COLOR_BGR2GRAY)
    contrast_term = 1.0 - min(float(gray.std()) / 64.0, 1.0)
    dark_channel_mean = float(np.min(sample, axis=2).mean()) / 255.0
    return float(np.clip(0.65 * contrast_term + 0.35 * dark_channel_mean, 0.0, 1.0))


def needs_dehaze(bgr: np.ndarray, threshold: float = 0.52) -> bool:
    """Decide whether the frame should enter the optional dehazing branch."""
    return low_visibility_score(bgr) >= threshold


def fast_dehaze(
    bgr: np.ndarray,
    estimate_scale: float = 0.35,
    omega: float = 0.90,
    min_transmission: float = 0.18,
    radius: int = 5,
) -> np.ndarray:
    """Dehaze one BGR uint8 frame with a lightweight dark-channel prior.

    The atmospheric light and transmission map are estimated on a smaller
    image, then the original-resolution frame is restored. This keeps the
    CPU work practical while YOLO runs on the MaixCAM2 NPU.
    """
    if bgr.dtype != np.uint8 or bgr.ndim != 3 or bgr.shape[2] != 3:
        raise ValueError("bgr must be an HxWx3 uint8 image")

    height, width = bgr.shape[:2]
    small_width = max(32, int(width * estimate_scale))
    small_height = max(32, int(height * estimate_scale))
    small = cv2.resize(bgr, (small_width, small_height), interpolation=cv2.INTER_AREA)
    small_float = small.astype(np.float32) / 255.0

    kernel_size = radius * 2 + 1
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (kernel_size, kernel_size))

    dark = np.min(small_float, axis=2)
    dark = cv2.erode(dark, kernel)

    top_count = max(1, dark.size // 1000)
    top_indices = np.argpartition(dark.reshape(-1), -top_count)[-top_count:]
    candidates = small_float.reshape(-1, 3)[top_indices]
    atmosphere = candidates[np.argmax(np.sum(candidates, axis=1))]
    atmosphere = np.maximum(atmosphere, 0.20)

    normalized = small_float / atmosphere.reshape(1, 1, 3)
    normalized_dark = cv2.erode(np.min(normalized, axis=2), kernel)
    transmission = 1.0 - omega * normalized_dark
    transmission = cv2.GaussianBlur(transmission, (0, 0), 1.2)
    transmission = cv2.resize(
        transmission, (width, height), interpolation=cv2.INTER_LINEAR
    )
    transmission = np.maximum(transmission, min_transmission)[..., None]

    source = bgr.astype(np.float32) / 255.0
    restored = (source - atmosphere) / transmission + atmosphere
    return np.clip(restored * 255.0, 0, 255).astype(np.uint8)
