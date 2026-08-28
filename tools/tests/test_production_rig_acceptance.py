from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
TOOLS_ROOT = PROJECT_ROOT / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

from character_art_pipeline import write_rgba_png
from cutout_rig import REQUIRED_BODY_PARTS, load_json, validate_rig, validate_rig_textures
from render_character_sprites import (
    PRODUCTION_RIG_RELATIVE_PATH,
    PRODUCTION_PIVOT_JOINTS,
    PRODUCTION_TEXTURE_FILENAMES,
    frame_clearance,
    missing_production_package_files,
    recommended_size_limit,
    resolve_rig_path,
    validate_production_rig_contract,
)


def fixture_rgba(path: Path, width: int = 32, height: int = 32) -> None:
    pixels = bytearray(width * height * 4)
    for y in range(4, height - 4):
        for x in range(4, width - 4):
            index = (y * width + x) * 4
            pixels[index:index + 4] = bytes((40, 52, 70, 255))
    write_rgba_png(path, width, height, bytes(pixels))


class ProductionRigAcceptanceTests(unittest.TestCase):
    def fixture_rig(self) -> dict:
        rig = copy.deepcopy(load_json(PROJECT_ROOT / "reference/fujiyama/rig_parts/character_rig.json"))
        rig.pop("procedural_parts", None)
        for part in rig["parts"]:
            part["texture"] = "body.png"
            part["pivot"] = [16, 16]
        rig["props"][0]["texture"] = "props/piano.png"
        rig["props"][0]["pivot"] = [16, 16]
        return rig

    def test_production_rig_path_resolves_inside_project(self) -> None:
        path, alternate = resolve_rig_path("fujiyama", PRODUCTION_RIG_RELATIVE_PATH)
        self.assertTrue(alternate)
        self.assertEqual(path, (PROJECT_ROOT / PRODUCTION_RIG_RELATIVE_PATH).resolve())

    def test_missing_package_report_is_exact(self) -> None:
        path = PROJECT_ROOT / PRODUCTION_RIG_RELATIVE_PATH
        if path.is_file():
            self.skipTest("real production rig package is installed")
        self.assertEqual(
            missing_production_package_files(path),
            ["character_rig.json", *PRODUCTION_TEXTURE_FILENAMES],
        )

    def test_required_body_components_are_enforced(self) -> None:
        rig = self.fixture_rig()
        self.assertEqual(set(REQUIRED_BODY_PARTS), {part["name"] for part in rig["parts"]})
        rig["parts"] = [part for part in rig["parts"] if part["name"] != "head"]
        with self.assertRaisesRegex(ValueError, "missing required body parts: head"):
            validate_rig(rig)

    def test_production_appearance_contract_and_separate_piano_are_required(self) -> None:
        rig = self.fixture_rig()
        with self.assertRaisesRegex(ValueError, "appearance_contract"):
            validate_production_rig_contract(rig, "fujiyama")
        rig["appearance_contract"] = {
            "heritage": "Japanese-American man",
            "age": "adult",
            "hair": "black dark mullet-style hair",
            "facial_hair": "thick dark moustache",
            "expression": "calm and deadly",
            "clothing": "gray navy business suit",
            "shirt": "white dress shirt",
            "tie": "dark tie",
            "belt": "dark belt",
            "shoes": "dark dress shoes",
            "proportions": "sturdy realistic proportions",
            "rendering_style": "fighting-game cartoon consistent with the existing game",
            "exclusions": ["glasses", "exaggerated superhero musculature"],
        }
        for part in rig["parts"]:
            if part["name"] in PRODUCTION_PIVOT_JOINTS:
                part["pivot_joint"] = PRODUCTION_PIVOT_JOINTS[part["name"]]
        validate_production_rig_contract(rig, "fujiyama")
        rig["props"] = []
        with self.assertRaisesRegex(ValueError, "piano"):
            validate_production_rig_contract(rig, "fujiyama")

    def test_rgba_paths_and_shared_limb_textures_are_valid(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name)
            (root / "props").mkdir()
            fixture_rgba(root / "body.png")
            fixture_rgba(root / "props/piano.png")
            textures = validate_rig_textures(self.fixture_rig(), root, production=True)
            self.assertEqual(set(textures), {"body.png", "props/piano.png"})
            self.assertTrue(all(image.color_type == 6 for image in textures.values()))

    def test_pivot_outside_texture_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name)
            (root / "props").mkdir()
            fixture_rgba(root / "body.png")
            fixture_rgba(root / "props/piano.png")
            rig = self.fixture_rig()
            rig["parts"][0]["pivot"] = [32, 16]
            with self.assertRaisesRegex(ValueError, "pivot.*outside"):
                validate_rig_textures(rig, root, production=True)

    def test_runtime_ratio_includes_896_canvas(self) -> None:
        expected = {512: 128, 576: 144, 640: 160, 704: 176, 768: 192, 896: 224}
        for canvas, size_limit in expected.items():
            self.assertEqual(recommended_size_limit(canvas, canvas), size_limit)

    def test_clearance_reports_all_edges(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_name:
            path = Path(temporary_name) / "frame.png"
            pixels = bytearray(64 * 64 * 4)
            for y in range(7, 54):
                for x in range(5, 58):
                    pixels[(y * 64 + x) * 4 + 3] = 255
            write_rgba_png(path, 64, 64, bytes(pixels))
            from character_art_pipeline import read_png
            self.assertEqual(
                frame_clearance(read_png(path)),
                {"top": 7, "bottom": 10, "left": 5, "right": 6},
            )


if __name__ == "__main__":
    unittest.main()
