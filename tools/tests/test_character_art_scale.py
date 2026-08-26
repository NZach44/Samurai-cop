from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_ROOT))

from character_art_pipeline import (
    PngImage,
    _resample_frame,
    assess_action_anatomy,
    assess_neutral_anchor,
    batch_consistency_error,
    production_batch_for_animation,
)
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
                        "status": "approved",
                        "batch_multiplier": multiplier,
                        "animations": ["crouch", "kick"],
                        "animation_multipliers": {"crouch": crouch_multiplier, "kick": multiplier},
                    }
                }
            }
        },
    }


class BatchAnchoredScaleTests(unittest.TestCase):
    def test_neutral_anchor_calibrates_generation_scale(self) -> None:
        assessment = assess_neutral_anchor(anchor_manifest(), image(100, 400), [image(100, 400)])
        self.assertEqual(assessment.status, "PASS")
        self.assertEqual(assessment.multiplier, 1.0)

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

    def test_crouch_pose_height_cannot_drive_scale(self) -> None:
        anchor = assess_neutral_anchor(anchor_manifest(), image(100, 400), [image(100, 400)])
        self.assertEqual(anchor.multiplier, 1.0)
        self.assertEqual(image(80, 200).visible_height, 200)

    def test_jump_pose_height_cannot_drive_scale(self) -> None:
        anchor = assess_neutral_anchor(anchor_manifest(), image(100, 400), [image(100, 400)])
        self.assertEqual(anchor.multiplier, 1.0)
        self.assertEqual(image(90, 240).visible_height, 240)

    def test_ko_width_cannot_drive_scale(self) -> None:
        anchor = assess_neutral_anchor(anchor_manifest(), image(100, 400), [image(100, 400)])
        self.assertEqual(anchor.multiplier, 1.0)
        self.assertEqual(image(420, 90).visible_width, 420)

    def test_hurt_recoil_height_cannot_drive_scale(self) -> None:
        anchor = assess_neutral_anchor(anchor_manifest(), image(100, 400), [image(100, 400)])
        self.assertEqual(anchor.multiplier, 1.0)
        self.assertEqual(image(140, 330).visible_height, 330)

    def test_non_neutral_anchor_is_rejected_by_anatomy(self) -> None:
        assessment = assess_neutral_anchor(anchor_manifest(), image(200, 380), [image(100, 400)])
        self.assertEqual(assessment.status, "ERROR")
        self.assertGreater(assessment.width_ratio, 2.0)

    def test_generation_height_is_source_scale_not_physical_height(self) -> None:
        assessment = assess_neutral_anchor(anchor_manifest(), image(120, 480), [image(100, 400)])
        self.assertEqual(assessment.status, "PASS")
        self.assertAlmostEqual(assessment.multiplier, 400.0 / 480.0)

    def test_copied_anchor_cannot_hide_seventy_percent_action_anatomy(self) -> None:
        copied_core_anchor = image(60, 150)
        undersized_jump_frames = [image(42, 105) for _index in range(5)]
        assessment = assess_action_anatomy(
            anchor_manifest(),
            copied_core_anchor,
            undersized_jump_frames,
        )
        self.assertEqual(assessment.status, "ERROR")
        self.assertAlmostEqual(assessment.alpha_mass_ratio, 0.70, delta=0.02)

    def test_same_generation_crouch_keeps_anchor_multiplier_and_passes_anatomy(self) -> None:
        same_generation_anchor = image(40, 100)
        crouch_frames = [image(100, 40) for _index in range(3)]
        assessment = assess_action_anatomy(anchor_manifest(), same_generation_anchor, crouch_frames)
        self.assertEqual(assessment.status, "PASS")
        multiplier = 470.0 / same_generation_anchor.visible_height
        output = _resample_frame(crouch_frames[0], multiplier, True, 527, 576, 576)
        self.assertIsNotNone(output)
        visible = [
            (x, y)
            for y in range(576)
            for x in range(576)
            if output[(y * 576 + x) * 4 + 3]
        ]
        self.assertAlmostEqual(max(x for x, _y in visible) - min(x for x, _y in visible) + 1, 470, delta=4)
        self.assertAlmostEqual(max(y for _x, y in visible) - min(y for _x, y in visible) + 1, 188, delta=4)

    def test_unapproved_generation_group_cannot_be_imported(self) -> None:
        pending = manifest()
        pending["characters"]["fighter"]["production_batches"]["batch"]["status"] = "requires_source"
        failure = batch_import_failure(pending, "fighter", "crouch", [])
        self.assertIn("no approved neutral-anchor calibration", failure)

    def test_importer_rejects_generation_group_without_provenance(self) -> None:
        missing = manifest()
        batch = missing["characters"]["fighter"]["production_batches"]["batch"]
        batch["generation_group"] = True
        batch["source_generation"] = "fighter_jump_v1"
        failure = batch_import_failure(missing, "fighter", "crouch", [])
        self.assertIn("anchor provenance is not valid", failure)


def anchor_manifest() -> dict:
    return {
        "scale_calibration": {
            "neutral_anchor_height_pass_tolerance": 0.08,
            "neutral_anchor_height_warning_tolerance": 0.12,
            "neutral_anchor_width_pass_tolerance": 0.12,
            "neutral_anchor_width_warning_tolerance": 0.20,
            "neutral_anchor_area_pass_tolerance": 0.25,
            "neutral_anchor_area_warning_tolerance": 0.40,
        }
    }


if __name__ == "__main__":
    unittest.main()
