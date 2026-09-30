import math
import unittest

from serial_monitor.protocol import (
    FrameParser,
    angle_raw_to_degrees,
    encode_extended_frame,
    frame_checksum,
)


class ProtocolTests(unittest.TestCase):
    def test_q321_angle_conversion(self):
        raw = int((math.pi / 2) * (1 << 21))
        self.assertAlmostEqual(angle_raw_to_degrees(raw), 90.0, places=4)

    def test_legacy_frame_in_chunks(self):
        parser = FrameParser()
        raw = int((-math.pi / 4) * (1 << 21)) & 0xFFFFFF
        frame = bytes([0xA5, raw >> 16, (raw >> 8) & 0xFF, raw & 0xFF])
        self.assertEqual(parser.feed(frame[:2]), [])
        samples = parser.feed(frame[2:])
        self.assertEqual(len(samples), 1)
        self.assertEqual(samples[0].protocol, "legacy")
        self.assertAlmostEqual(samples[0].angle_deg, -45.0, places=3)
        self.assertIsNone(samples[0].strength_raw)

    def test_extended_frame(self):
        parser = FrameParser()
        raw = int(math.radians(123.4) * (1 << 21))
        samples = parser.feed(encode_extended_frame(raw, 0x123456))
        self.assertEqual(len(samples), 1)
        self.assertEqual(samples[0].protocol, "extended")
        self.assertAlmostEqual(samples[0].angle_deg, 123.4, places=3)
        self.assertEqual(samples[0].strength_raw, 0x123456)

    def test_noise_and_multiple_frames(self):
        parser = FrameParser()
        stream = b"noise" + encode_extended_frame(0, 10) + encode_extended_frame(1, 20)
        samples = parser.feed(stream)
        self.assertEqual(len(samples), 2)
        self.assertEqual(parser.discarded_bytes, 5)

    def test_bad_checksum_resynchronizes(self):
        parser = FrameParser()
        bad = bytearray(encode_extended_frame(123, 456))
        bad[-1] ^= 0x01
        good = encode_extended_frame(789, 321)
        samples = parser.feed(bytes(bad) + good)
        self.assertEqual(len(samples), 1)
        self.assertEqual(samples[0].raw_angle, 789)
        self.assertEqual(parser.bad_checksums, 1)

    def test_checksum_is_xor(self):
        frame = encode_extended_frame(0x010203, 0x040506)
        self.assertEqual(frame[-1], frame_checksum(frame[:-1]))


if __name__ == "__main__":
    unittest.main()
