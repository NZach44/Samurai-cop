from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_ROOT))

from character_art_pipeline import PngImage, _resample_frame, batch_consistency_error, production_batch_for_animation
from spriteframes_importer import batch_import_failure


def image(width: int, height: int, bottom: int = 400) -> PngImage:
    top = bottom - height + 1
    bounds = (100, top, 100 + width - 1, bottom)
    rgba = bytearray(512 * 512 * 4)
    for y in range(top, bottom + 1):
        for x in range(100, 100 + width):
            rgba[(y * 512 + x) * 4 + 3] = 255
    return PngImage(512, 512, 6, bytes(rgba), bounds, 512 * 512 - width * height, 0, 0)


def manifest(multiplier: float = 0.86, crouch_multiplier: float | None = None) -> dict:
    crouch_multiplier = multiplier if crouch_multiplier is None else crouch_multiplier
    return {
        "animation_order": ["idle", "crouch", "kick"],
        "characters": {
            "fighter": {
                "production_batches": {
                    "batch": {
                        "status": "ready",
                        "batch_multiplier": multiplier,
                        "animations": ["crouch", "kick"],
                        "animation_multipliers": {"crouch": crouch_multiplier, "kick": multiplier},
                    }
                }
            }
        },
    }


class BatchAnchoredScaleTests(unittest.TestCase):
    def test_naturally_short_crouch_does_not_change_batch_scale(self) -> None:
        entry = production_batch_for_animation(manifest(), "fighter", "crouch")
        self.assertIsNone(batch_consistency_error(entry[1]))
        self.assertEqual(image(80, 45).visible_height, 45)

    def test_one_batch_uses_one_multiplier(self) -> None:
        batch = production_batch_for_animation(manifest(), "fighter", "kick")[1]
        self.assertEqual(set(batch["animation_multipliers"].values()), {0.86})

    def test_different_animation_multiplier_is_rejected(self) -> None:
        batch = production_batch_for_animation(manifest(crouch_multiplier=1.17), "fighter", "crouch")[1]
        self.assertIn("inconsistent body scale", batch_consistency_error(batch))

    def test_extended_kick_width_does_not_change_multiplier(self) -> None:
        self.assertEqual(image(400, 100).visible_width, 400)
        self.assertIsNone(batch_consistency_error(production_batch_for_animation(manifest(), "fighter", "kick")[1]))

    def test_baseline_translation_does_not_resize(self) -> None:
        output = _resample_frame(image(50, 80), 1.0, True, 495)
        visible = [
            (x, y)
            for y in range(512)
            for x in range(512)
            if output[(y * 512 + x) * 4 + 3]
        ]
        self.assertEqual(max(y for _x, y in visible), 495)
        self.assertEqual(max(y for _x, y in visible) - min(y for _x, y in visible) + 1, 80)
        self.assertEqual(max(x for x, _y in visible) - min(x for x, _y in visible) + 1, 50)

    def test_importer_rejects_inconsistent_batch(self) -> None:
        failure = batch_import_failure(manifest(crouch_multiplier=1.17), "fighter", "crouch", [])
        self.assertIn("inconsistent body scale", failure)

    def test_scale_anchor_is_not_a_gameplay_animation(self) -> None:
        self.assertNotIn("scale_anchor", manifest()["animation_order"])


if __name__ == "__main__":
    unittest.main()
