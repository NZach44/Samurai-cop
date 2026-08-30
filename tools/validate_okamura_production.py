#!/usr/bin/env python3
"""Strict acceptance check for Okamura's final production sprite set."""

from __future__ import annotations

import sys
from pathlib import Path

from character_art_pipeline import PROJECT_ROOT, read_png


CHARACTER_ID = "okamura"
SPRITE_ROOT = PROJECT_ROOT / "assets" / "characters" / CHARACTER_ID / "sprites"
CANVAS_SIZE = (512, 512)
TARGET_BASELINE = 495
BASELINE_TOLERANCE = 8
MIN_CLEARANCE = 16

ANIMATIONS: dict[str, tuple[int, bool]] = {
    "idle": (4, True),
    "walk": (6, True),
    "punch": (5, True),
    "kick": (6, True),
    "crouch": (3, True),
    "crouch_punch": (5, True),
    "crouch_kick": (6, True),
    "block": (3, True),
    "crouch_block": (3, True),
    "jump": (5, False),
    "hurt": (3, True),
    "special_1": (8, True),
    "special_2": (8, False),
    "ko": (8, True),
}


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)
    print(f"ERROR {message}")


def main() -> int:
    failures: list[str] = []
    total = 0
    minimum_clearance: int | None = None

    for animation, (expected_count, grounded) in ANIMATIONS.items():
        folder = SPRITE_ROOT / animation
        expected = [folder / f"{animation}_{index:03d}.png" for index in range(1, expected_count + 1)]
        missing = [path for path in expected if not path.is_file()]
        if missing:
            fail(
                f"{animation}: missing {len(missing)}/{expected_count} expected frame(s): "
                + ", ".join(path.name for path in missing),
                failures,
            )
            continue

        extras = sorted(path.name for path in folder.glob("*.png") if path not in expected)
        if extras:
            fail(f"{animation}: unexpected PNG frame(s): {', '.join(extras)}", failures)

        baselines: list[int] = []
        for path in expected:
            try:
                image = read_png(path)
            except Exception as error:  # noqa: BLE001 - report malformed production assets verbatim.
                fail(f"{animation}/{path.name}: {error}", failures)
                continue

            total += 1
            if (image.width, image.height) != CANVAS_SIZE:
                fail(
                    f"{animation}/{path.name}: expected 512x512, found {image.width}x{image.height}",
                    failures,
                )
            if image.color_type != 6:
                fail(f"{animation}/{path.name}: PNG must be true RGBA color type 6", failures)
            if image.transparent_pixels == 0:
                fail(f"{animation}/{path.name}: frame has no transparent pixels", failures)
            if image.alpha_bounds is None:
                fail(f"{animation}/{path.name}: frame contains no visible artwork", failures)
                continue

            min_x, min_y, max_x, max_y = image.alpha_bounds
            clearance = min(min_x, min_y, image.width - 1 - max_x, image.height - 1 - max_y)
            minimum_clearance = clearance if minimum_clearance is None else min(minimum_clearance, clearance)
            if clearance < MIN_CLEARANCE:
                fail(
                    f"{animation}/{path.name}: crop clearance {clearance}px is below {MIN_CLEARANCE}px; "
                    f"bounds={image.alpha_bounds}",
                    failures,
                )
            if grounded:
                baselines.append(max_y)

        if grounded and baselines:
            baseline_min = min(baselines)
            baseline_max = max(baselines)
            if baseline_min < TARGET_BASELINE - BASELINE_TOLERANCE or baseline_max > TARGET_BASELINE + BASELINE_TOLERANCE:
                fail(
                    f"{animation}: grounded baseline range {baseline_min}..{baseline_max} is outside "
                    f"{TARGET_BASELINE}±{BASELINE_TOLERANCE}px",
                    failures,
                )

    if total != 73:
        fail(f"production contract must decode exactly 73 expected PNGs; decoded {total}", failures)

    if failures:
        print(f"FAIL Okamura production sprite acceptance: {len(failures)} problem(s)")
        return 1

    print(
        "PASS Okamura production sprite acceptance: "
        f"73/73 RGBA frames, 512x512, minimum crop clearance {minimum_clearance}px"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
