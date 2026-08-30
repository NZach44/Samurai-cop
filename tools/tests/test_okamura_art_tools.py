#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import init_okamura_art_package as package_tool
import process_okamura_art as process_tool


EXPECTED_ANIMATIONS = {
    "idle",
    "walk",
    "punch",
    "kick",
    "crouch",
    "crouch_punch",
    "crouch_kick",
    "block",
    "crouch_block",
    "jump",
    "hurt",
    "special_1",
    "special_2",
    "ko",
}

FRAME_COUNTS = {
    "idle": 4,
    "walk": 6,
    "punch": 5,
    "kick": 6,
    "crouch": 3,
    "crouch_punch": 5,
    "crouch_kick": 6,
    "block": 3,
    "crouch_block": 3,
    "jump": 5,
    "hurt": 3,
    "special_1": 8,
    "special_2": 8,
    "ko": 8,
}


class OkamuraArtToolsTest(unittest.TestCase):
    def test_groups_cover_production_contract_exactly_once(self) -> None:
        animations = [animation for _group, group_animations in package_tool.GROUPS for animation in group_animations]
        self.assertEqual(len(animations), len(set(animations)))
        self.assertEqual(set(animations), EXPECTED_ANIMATIONS)
        self.assertEqual(sum(FRAME_COUNTS[animation] for animation in animations), 73)

    def test_groups_match_milestone_batch_order(self) -> None:
        self.assertEqual(package_tool.GROUPS[0], ("batch_a", ("idle", "walk", "punch", "kick")))
        self.assertEqual(package_tool.GROUPS[3], ("batch_d", ("special_1",)))
        self.assertEqual(package_tool.GROUPS[4], ("batch_e", ("special_2",)))

    def test_bootstrap_targets_okamura_resource(self) -> None:
        metadata = process_tool.OKAMURA_BOOTSTRAP
        self.assertEqual(metadata["sprite_frames"], "res://assets/characters/okamura/okamura_frames.tres")
        self.assertEqual(metadata["target_height_ratio_to_reference"], 1.0)
        self.assertEqual(metadata["production_batches"], {})


if __name__ == "__main__":
    unittest.main()
