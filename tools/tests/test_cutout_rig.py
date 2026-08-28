from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from statistics import median


PROJECT_ROOT = Path(__file__).resolve().parents[2]
TOOLS_ROOT = PROJECT_ROOT / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

from character_art_pipeline import read_png
from cutout_rig import REQUIRED_BONES, load_json, sample_animation, validate_animation_library, validate_rig
from render_character_sprites import (
    ANIMATIONS,
    recommended_size_limit,
    render_character,
    transactional_promote,
)


def digest_tree(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


class CutoutRigRendererTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        production = PROJECT_ROOT / "assets" / "characters" / "fujiyama"
        before = digest_tree(production)
        cls.report = render_character("fujiyama")
        cls.production_unchanged = before == digest_tree(production)
        cls.rig = load_json(PROJECT_ROOT / cls.report["rig"])
        cls.library = load_json(PROJECT_ROOT / cls.report["animation_library"])

    def all_frames(self):
        return [frame for frames in self.report["frames"].values() for frame in frames]

    def test_exactly_73_frames_are_produced(self) -> None:
        self.assertEqual(self.report["frame_count_total"], 73)
        self.assertEqual(sum(len(frames) for frames in self.report["frames"].values()), 73)

    def test_generic_skeleton_and_rig_schema_are_valid(self) -> None:
        validate_rig(self.rig)
        self.assertTrue(set(REQUIRED_BONES).issubset(self.rig["bones"]))
        self.assertEqual(set(self.rig["attachment_slots"]), {"weapon_hand", "projectile_origin", "waist"})

    def test_no_animation_contains_a_bone_scale_key(self) -> None:
        validate_animation_library(self.library, self.report["frame_counts"])
        self.assertNotIn('"scale"', json.dumps(self.library["animations"]))

    def test_head_and_torso_scales_are_identical(self) -> None:
        for part in ("head", "torso"):
            scales = {
                tuple(frame["parts"][part]["transform_scale"])
                for frame in self.all_frames()
            }
            self.assertEqual(scales, {(0.8, 0.8)})

    def test_neutral_height_matches_target(self) -> None:
        heights = [frame["visible_size"][1] for frame in self.report["frames"]["idle"]]
        self.assertAlmostEqual(median(heights), self.rig["target_neutral_height"], delta=5)

    def test_crouch_uses_posture_not_scale(self) -> None:
        idle = self.report["frames"]["idle"][0]
        crouch = self.report["frames"]["crouch"][-1]
        self.assertNotEqual(idle["bones"], crouch["bones"])
        self.assertEqual(idle["parts"]["head"], crouch["parts"]["head"])
        self.assertLess(crouch["visible_size"][1], idle["visible_size"][1])

    def test_low_attacks_remain_crouched(self) -> None:
        for animation in ("crouch_punch", "crouch_kick"):
            count = self.report["frame_counts"][animation]
            for index in range(count):
                pose = sample_animation(self.library["animations"][animation], index, count)
                self.assertGreaterEqual(pose["pelvis"]["position"][1], 70)
            self.assertNotEqual(
                self.report["frames"][animation][0]["bones"],
                self.report["frames"][animation][count // 2]["bones"],
            )

    def test_jump_preserves_anatomy(self) -> None:
        idle = self.report["frames"]["idle"][0]
        jump = self.report["frames"]["jump"][2]
        self.assertNotEqual(idle["bones"], jump["bones"])
        self.assertEqual(idle["parts"]["head"], jump["parts"]["head"])

    def test_ko_preserves_anatomy_on_wider_canvas(self) -> None:
        self.assertGreater(self.report["animations"]["ko"]["canvas"][0], 512)
        self.assertEqual(
            self.report["frames"]["idle"][0]["parts"]["head"],
            self.report["frames"]["ko"][-1]["parts"]["head"],
        )

    def test_flying_kick_preserves_anatomy(self) -> None:
        self.assertEqual(
            self.report["frames"]["idle"][0]["parts"]["torso"],
            self.report["frames"]["special_2"][4]["parts"]["torso"],
        )

    def test_piano_is_separate_and_does_not_calibrate_body(self) -> None:
        self.assertEqual([prop["id"] for prop in self.report["props"]], ["piano"])
        self.assertNotIn("piano", self.report["frames"]["idle"][0]["parts"])
        self.assertIn("piano", self.report["frames"]["special_1"][1]["parts"])
        self.assertEqual(self.report["body_scale"], 0.8)
        self.assertEqual(
            self.report["animations"]["special_1"]["events"][0]["type"], "spawn_prop"
        )

    def test_variable_canvases_preserve_runtime_pixel_scale(self) -> None:
        expected = {512: 128, 576: 144, 640: 160, 704: 176, 768: 192}
        for dimension, size_limit in expected.items():
            self.assertEqual(recommended_size_limit(dimension, dimension), size_limit)
        for metadata in self.report["animations"].values():
            self.assertEqual(metadata["canvas_to_runtime_scale"], 0.25)
            self.assertEqual(metadata["size_limit"], recommended_size_limit(*metadata["canvas"]))

    def test_outputs_are_rgba_transparent_and_not_clipped(self) -> None:
        for animation, frames in self.report["frames"].items():
            width, height = self.report["animations"][animation]["canvas"]
            for frame in frames:
                image = read_png(PROJECT_ROOT / frame["file"])
                self.assertEqual((image.width, image.height, image.color_type), (width, height, 6))
                self.assertGreater(image.transparent_pixels, 0)
                min_x, min_y, max_x, max_y = image.alpha_bounds
                self.assertGreater(min_x, 0)
                self.assertGreater(min_y, 0)
                self.assertLess(max_x, width - 1)
                self.assertLess(max_y, height - 1)

    def test_anatomy_report_covers_high_risk_animations(self) -> None:
        expected = {
            "idle", "crouch", "crouch_punch", "crouch_kick", "block",
            "crouch_block", "jump", "hurt", "ko", "special_1", "special_2",
        }
        self.assertEqual(set(self.report["anatomy_measurements"]), expected)

    def test_default_preview_does_not_write_assets(self) -> None:
        self.assertTrue(self.production_unchanged)

    def test_transactional_promotion_restores_previous_character(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name)
            staged = root / "staged"
            character = root / "character"
            (staged / "idle").mkdir(parents=True)
            (character / "sprites" / "idle").mkdir(parents=True)
            (staged / "idle" / "idle_001.png").write_bytes(b"new")
            old = character / "sprites" / "idle" / "idle_001.png"
            old.write_bytes(b"old")

            def fail() -> None:
                raise RuntimeError("validation failed")

            with self.assertRaises(RuntimeError):
                transactional_promote(staged, character, ("idle",), fail)
            self.assertEqual(old.read_bytes(), b"old")


if __name__ == "__main__":
    unittest.main()
