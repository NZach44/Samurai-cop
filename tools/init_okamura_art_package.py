#!/usr/bin/env python3
"""Create Okamura's standard five-group character art package descriptor."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT_ROOT / "reference" / "okamura" / "generated_batches"
PACKAGE_PATH = SOURCE_ROOT / "character_package.json"
ANCHOR_FILENAME = "scale_anchor.png"

GROUPS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("batch_a", ("idle", "walk", "punch", "kick")),
    ("batch_b", ("crouch", "crouch_punch", "crouch_kick", "block", "crouch_block")),
    ("batch_c", ("jump", "hurt", "ko")),
    ("batch_d", ("special_1",)),
    ("batch_e", ("special_2",)),
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--generation-tag",
        default="v1",
        help="lowercase identifier appended to each independent generation group (default: v1)",
    )
    parser.add_argument("--force", action="store_true", help="replace an existing descriptor")
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()
    tag = args.generation_tag.strip().lower()
    if not tag or not tag.replace("_", "").isalnum():
        raise SystemExit("generation tag must contain only lowercase letters, digits, and underscores")
    if PACKAGE_PATH.exists() and not args.force:
        raise SystemExit(f"descriptor already exists: {PACKAGE_PATH.relative_to(PROJECT_ROOT)} (use --force to replace)")

    groups: dict[str, dict[str, object]] = {}
    problems: list[str] = []
    for group_name, animations in GROUPS:
        group_root = SOURCE_ROOT / group_name
        anchor = group_root / ANCHOR_FILENAME
        if not group_root.is_dir():
            problems.append(f"missing group directory: {group_root.relative_to(PROJECT_ROOT)}")
        if not anchor.is_file():
            problems.append(f"missing same-generation neutral anchor: {anchor.relative_to(PROJECT_ROOT)}")
        for animation in animations:
            animation_root = group_root / animation
            if not animation_root.is_dir():
                problems.append(f"missing animation directory: {animation_root.relative_to(PROJECT_ROOT)}")
        groups[group_name] = {
            "animations": list(animations),
            "anchor": ANCHOR_FILENAME,
            "source_generation": f"okamura_{group_name}_{tag}",
        }

    if problems:
        print("PACKAGE NOT CREATED")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    descriptor = {
        "character_id": "okamura",
        "groups": groups,
    }
    PACKAGE_PATH.parent.mkdir(parents=True, exist_ok=True)
    PACKAGE_PATH.write_text(json.dumps(descriptor, indent=2) + "\n", encoding="utf-8")
    print(f"PASS wrote {PACKAGE_PATH.relative_to(PROJECT_ROOT)}")
    for group_name, animations in GROUPS:
        print(f"  {group_name}: {', '.join(animations)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
