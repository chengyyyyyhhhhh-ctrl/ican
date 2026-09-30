"""Serial telemetry framing for the FPGA direction monitor."""

from __future__ import annotations

from dataclasses import dataclass
import math

HEADER = 0xA5
EXTENDED_MARKER = 0x7E
LEGACY_FRAME_SIZE = 4
EXTENDED_FRAME_SIZE = 9
ANGLE_FRACTION_BITS = 21
STRENGTH_FULL_SCALE = 0xFFFFFF


@dataclass(frozen=True, slots=True)
class TelemetrySample:
    """One decoded FPGA telemetry sample."""

    raw_angle: int
    angle_deg: float
    strength_raw: int | None
    protocol: str


def signed24(value: int) -> int:
    """Convert an unsigned 24-bit value to a Python signed integer."""
    value &= 0xFFFFFF
    return value - 0x1000000 if value & 0x800000 else value


def angle_raw_to_degrees(raw_angle: int) -> float:
    """Convert the CORDIC signed Q3.21-radian output to degrees."""
    return signed24(raw_angle) * 180.0 / (math.pi * (1 << ANGLE_FRACTION_BITS))


def wrap_degrees(angle: float) -> float:
    """Wrap an angle to [-180, 180)."""
    return (angle + 180.0) % 360.0 - 180.0


def frame_checksum(data: bytes | bytearray) -> int:
    """XOR checksum used by the extended telemetry frame."""
    checksum = 0
    for value in data:
        checksum ^= value
    return checksum


def encode_extended_frame(raw_angle: int, strength_raw: int) -> bytes:
    """Build an extended frame; useful for tests and demo data generation."""
    raw_angle &= 0xFFFFFF
    strength_raw &= 0xFFFFFF
    body = bytes(
        [
            HEADER,
            EXTENDED_MARKER,
            (raw_angle >> 16) & 0xFF,
            (raw_angle >> 8) & 0xFF,
            raw_angle & 0xFF,
            (strength_raw >> 16) & 0xFF,
            (strength_raw >> 8) & 0xFF,
            strength_raw & 0xFF,
        ]
    )
    return body + bytes([frame_checksum(body)])


class FrameParser:
    """Incremental parser supporting both the original and extended frames.

    Original frame: A5 + angle[23:16] + angle[15:8] + angle[7:0]
    Extended frame: A5 7E + angle(3 bytes) + strength(3 bytes) + XOR checksum
    """

    def __init__(self) -> None:
        self._buffer = bytearray()
        self.bad_checksums = 0
        self.discarded_bytes = 0

    def reset(self) -> None:
        self._buffer.clear()
        self.bad_checksums = 0
        self.discarded_bytes = 0

    def feed(self, data: bytes) -> list[TelemetrySample]:
        if data:
            self._buffer.extend(data)
        samples: list[TelemetrySample] = []

        while True:
            header_index = self._buffer.find(bytes([HEADER]))
            if header_index < 0:
                self.discarded_bytes += len(self._buffer)
                self._buffer.clear()
                break
            if header_index:
                self.discarded_bytes += header_index
                del self._buffer[:header_index]

            if len(self._buffer) < 2:
                break

            if self._buffer[1] == EXTENDED_MARKER:
                if len(self._buffer) < EXTENDED_FRAME_SIZE:
                    break
                packet = self._buffer[:EXTENDED_FRAME_SIZE]
                if frame_checksum(packet[:-1]) != packet[-1]:
                    self.bad_checksums += 1
                    self.discarded_bytes += 1
                    del self._buffer[0]
                    continue

                raw_angle = int.from_bytes(packet[2:5], "big")
                strength = int.from_bytes(packet[5:8], "big")
                samples.append(
                    TelemetrySample(
                        raw_angle=signed24(raw_angle),
                        angle_deg=wrap_degrees(angle_raw_to_degrees(raw_angle)),
                        strength_raw=strength,
                        protocol="extended",
                    )
                )
                del self._buffer[:EXTENDED_FRAME_SIZE]
                continue

            if len(self._buffer) < LEGACY_FRAME_SIZE:
                break
            packet = self._buffer[:LEGACY_FRAME_SIZE]
            raw_angle = int.from_bytes(packet[1:4], "big")
            samples.append(
                TelemetrySample(
                    raw_angle=signed24(raw_angle),
                    angle_deg=wrap_degrees(angle_raw_to_degrees(raw_angle)),
                    strength_raw=None,
                    protocol="legacy",
                )
            )
            del self._buffer[:LEGACY_FRAME_SIZE]

        return samples
