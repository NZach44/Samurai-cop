from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_ROOT))

from process_character_art import (
    parse_character_package,
    register_package_groups,
    resolve_target_height_ratio,
    source_to_target_scale,
    validate_source_layout,
)
import character_art_pipeline as pipeline


def manifest() -> dict:
    return {
        "animation_order": ["idle", "walk", "jump"],
        "characters": {
            "yamashita": {
                "production_batches": {},
            }
        },
    }


def descriptor() -> dict:
    return {
        "character_id": "yamashita",
        "groups": {
            "core": {
                "source_generation": "yamashita_core_v1",
                "animations": ["idle", "walk"],
                "anchor": "scale_anchor.png",
            },
            "jump": {
                "source_generation": "yamashita_jump_v1",
                "animations": ["jump"],
                "anchor": "scale_anchor.png",
            },
        },
    }


def manifest_with_counts() -> dict:
    current = manifest()
    current["animations"] = {
        "idle": {"frame_count": 2},
        "walk": {"frame_count": 1},
        "jump": {"frame_count": 1},
    }
    current["characters"]["yamashita"]["animations"] = {}
    return current


class CharacterPackageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.source_root = Path(self.temporary.name)
        for group_name in ("core", "jump"):
            group_root = self.source_root / group_name
            group_root.mkdir()
            (group_root / "scale_anchor.png").write_bytes(group_name.encode("ascii"))
        self.package_path = self.source_root / "character_package.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def parse(self, data: dict | None = None):
        return parse_character_package(
            data or descriptor(),
            "yamashita",
            manifest(),
            self.package_path,
            self.source_root,
        )

    def test_valid_descriptor_discovers_all_groups(self) -> None:
        package = self.parse()
        self.assertEqual([group.name for group in package.groups], ["core", "jump"])
        self.assertEqual(package.animations, ["idle", "walk", "jump"])

    def test_descriptor_character_must_match_command(self) -> None:
        data = descriptor()
        data["character_id"] = "frank_washington"
        with self.assertRaisesRegex(ValueError, "descriptor character_id"):
            self.parse(data)

    def test_animation_may_only_belong_to_one_group(self) -> None:
        data = descriptor()
        data["groups"]["jump"]["animations"] = ["idle"]
        with self.assertRaisesRegex(ValueError, "assigned to both"):
            self.parse(data)

    def test_missing_groups_are_registered_with_neutral_anchors(self) -> None:
        current = manifest()
        registered = register_package_groups(current, self.parse())
        self.assertEqual(registered, ["core", "jump"])
        core = current["characters"]["yamashita"]["production_batches"]["core"]
        self.assertEqual(core["status"], "pending_normalization")
        self.assertEqual(core["source_generation"], "yamashita_core_v1")
        self.assertEqual(core["anchor"], {"type": "neutral_standing", "filename": "scale_anchor.png"})

    def test_copied_anchor_across_unrelated_source_generations_is_rejected(self) -> None:
        (self.source_root / "jump" / "scale_anchor.png").write_bytes(b"core")
        with self.assertRaisesRegex(ValueError, "copied across unrelated source generations"):
            self.parse()

    def test_source_generation_is_required(self) -> None:
        data = descriptor()
        del data["groups"]["jump"]["source_generation"]
        with self.assertRaisesRegex(ValueError, "source_generation"):
            self.parse(data)

    def test_groups_from_one_declared_source_generation_may_share_anchor(self) -> None:
        data = descriptor()
        data["groups"]["jump"]["source_generation"] = "yamashita_core_v1"
        (self.source_root / "jump" / "scale_anchor.png").write_bytes(b"core")
        package = self.parse(data)
        self.assertEqual(len(package.groups), 2)

    def test_invalid_provenance_can_be_replaced_without_overwriting_approved_group(self) -> None:
        current = manifest()
        old_package = self.parse()
        register_package_groups(current, old_package)
        jump = current["characters"]["yamashita"]["production_batches"]["jump"]
        jump["status"] = "requires_source_calibration"
        jump["anchor_provenance"]["status"] = "invalid"
        data = descriptor()
        data["groups"]["jump"]["source_generation"] = "yamashita_jump_v2"
        (self.source_root / "jump" / "scale_anchor.png").write_bytes(b"genuine jump v2")
        registered = register_package_groups(current, self.parse(data))
        replacement = current["characters"]["yamashita"]["production_batches"]["jump"]
        self.assertIn("jump", registered)
        self.assertEqual(replacement["status"], "pending_normalization")
        self.assertEqual(replacement["source_generation"], "yamashita_jump_v2")
        self.assertEqual(replacement["anchor_provenance"]["status"], "pending")

    def test_source_layout_rejects_unexpected_pngs(self) -> None:
        package = self.parse()
        for group in package.groups:
            for animation in group.animations:
                folder = self.source_root / group.name / animation
                folder.mkdir()
                frame_count = 2 if animation == "idle" else 1
                for number in range(1, frame_count + 1):
                    (folder / f"{animation}_{number:03d}.png").touch()
        (self.source_root / "jump" / "jump" / "jump_002.png").touch()
        with self.assertRaisesRegex(ValueError, "unexpected PNG"):
            validate_source_layout(manifest_with_counts(), package)

    def test_matching_approved_metadata_is_preserved_byte_for_byte(self) -> None:
        current = manifest()
        package = self.parse()
        register_package_groups(current, package)
        core = current["characters"]["yamashita"]["production_batches"]["core"]
        core.update({"status": "approved", "batch_multiplier": 0.95, "output_digests": {"idle": "abc"}})
        before = copy.deepcopy(core)
        self.assertEqual(register_package_groups(current, package), [])
        self.assertEqual(core, before)

    def test_conflicting_approved_metadata_is_not_overwritten(self) -> None:
        current = manifest()
        current["characters"]["yamashita"]["production_batches"]["core"] = {
            "status": "approved",
            "generation_group": True,
            "anchor": {"type": "neutral_standing", "filename": "different.png"},
            "animations": ["idle", "walk"],
        }
        before = copy.deepcopy(current)
        with self.assertRaisesRegex(ValueError, "refusing to overwrite"):
            register_package_groups(current, self.parse())
        self.assertEqual(current, before)

    def test_small_source_idle_scales_up_to_default_physical_height(self) -> None:
        ratio, explicit = resolve_target_height_ratio({})
        self.assertEqual((ratio, explicit), (1.0, False))
        self.assertAlmostEqual(source_to_target_scale(470.0, ratio, 150.0), 470.0 / 150.0)

    def test_large_source_idle_scales_down_to_default_physical_height(self) -> None:
        ratio, _explicit = resolve_target_height_ratio({})
        self.assertAlmostEqual(source_to_target_scale(470.0, ratio, 500.0), 0.94)

    def test_stale_source_derived_profile_cannot_define_physical_height(self) -> None:
        ratio, explicit = resolve_target_height_ratio({
            "scale_profile": {"height_ratio_to_reference": 0.31},
        })
        self.assertEqual((ratio, explicit), (1.0, False))

    def test_explicit_intentional_height_ratio_is_allowed(self) -> None:
        ratio, explicit = resolve_target_height_ratio({"target_height_ratio_to_reference": 0.85})
        self.assertEqual((ratio, explicit), (0.85, True))

    def test_wide_weapon_pose_does_not_change_body_multiplier(self) -> None:
        multiplier = source_to_target_scale(470.0, 1.0, 150.0)
        narrow_pose_width = 90.0 * multiplier
        katana_pose_width = 160.0 * multiplier
        self.assertAlmostEqual(multiplier, 470.0 / 150.0)
        self.assertGreater(katana_pose_width, narrow_pose_width)

    def test_package_normalizer_promotes_target_height_into_actual_production_png(self) -> None:
        project_root = self.source_root / "project"
        source_root = project_root / "reference" / "fighter" / "generated_batches" / "core"
        source_root.mkdir(parents=True)
        source_pixels = bytearray(512 * 512 * 4)
        for y in range(346, 496):
            for x in range(231, 281):
                index = (y * 512 + x) * 4
                source_pixels[index : index + 4] = bytes((80, 120, 180, 255))
        anchor_path = source_root / "scale_anchor.png"
        idle_path = source_root / "idle" / "idle_001.png"
        pipeline.write_rgba_png(anchor_path, 512, 512, source_pixels)
        pipeline.write_rgba_png(idle_path, 512, 512, source_pixels)
        test_manifest = {
            "canvas": {
                "width": 512,
                "height": 512,
                "target_ground_baseline": 495,
                "runtime_texture_size_limit": 128,
            },
            "scale_calibration": {
                "neutral_anchor_height_pass_tolerance": 0.08,
                "neutral_anchor_height_warning_tolerance": 0.12,
                "neutral_anchor_width_pass_tolerance": 0.12,
                "neutral_anchor_width_warning_tolerance": 0.20,
                "neutral_anchor_area_pass_tolerance": 0.25,
                "neutral_anchor_area_warning_tolerance": 0.40,
            },
            "batch_contract": {
                "normalization_version": 3,
                "source_root": "reference/{character_id}/generated_batches",
                "anchor_filename": "scale_anchor.png",
            },
            "animation_order": ["idle"],
            "animations": {
                "idle": {
                    "frame_count": 1,
                    "fps": 6.0,
                    "loop": True,
                    "hold_final": False,
                    "grounded": True,
                }
            },
            "characters": {
                "fighter": {
                    "scale_profile": {
                        "reference_animation": "idle",
                        "height_ratio_to_reference": 1.0,
                        "target_baseline_y": 495,
                    },
                    "animations": {},
                    "production_batches": {
                        "core": {
                            "status": "pending_normalization",
                            "generation_group": True,
                            "source_generation": "fighter_core_v1",
                            "anchor": {"type": "neutral_standing", "filename": "scale_anchor.png"},
                            "animations": ["idle"],
                        }
                    },
                }
            },
        }
        original_project_root = pipeline.PROJECT_ROOT
        pipeline.PROJECT_ROOT = project_root
        try:
            report = pipeline.Report()
            output_root = project_root / "staged"
            pipeline.normalize_batch(
                test_manifest,
                "fighter",
                "core",
                report,
                promote=True,
                save_metadata=False,
                output_root=output_root,
                approved_idle=[pipeline.read_png(idle_path)],
                target_height=470.0,
                scale_source_height=150.0,
            )
            generated = pipeline.read_png(
                project_root / "assets" / "characters" / "fighter" / "sprites" / "idle" / "idle_001.png"
            )
        finally:
            pipeline.PROJECT_ROOT = original_project_root
        self.assertEqual(report.errors, 0)
        self.assertNotEqual(generated.visible_height, 150)
        self.assertAlmostEqual(generated.visible_height, 470.0, delta=5.0)


if __name__ == "__main__":
    unittest.main()
