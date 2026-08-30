#!/usr/bin/env python3
"""Run the shared character-art transaction for Okamura with bootstrap metadata."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import process_character_art
from character_art_pipeline import MANIFEST_PATH


OKAMURA_BOOTSTRAP = {
    "sprite_frames": "res://assets/characters/okamura/okamura_frames.tres",
    "visual_scale_override": 1.0,
    "target_height_ratio_to_reference": 1.0,
    "production_batches": {},
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="preflight without keeping manifest or production changes")
    return parser.parse_args()


def write_manifest(data: dict) -> None:
    temporary = MANIFEST_PATH.with_suffix(".json.okamura_tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    temporary.replace(MANIFEST_PATH)


def main() -> int:
    args = parse_arguments()
    original_bytes = MANIFEST_PATH.read_bytes()
    injected = False
    try:
        manifest = json.loads(original_bytes.decode("utf-8"))
        characters = manifest.setdefault("characters", {})
        if "okamura" not in characters:
            characters["okamura"] = dict(OKAMURA_BOOTSTRAP)
            write_manifest(manifest)
            injected = True
            print("BOOTSTRAP added provisional Okamura art metadata")
        result = process_character_art.process_package("okamura", args.dry_run)
        if args.dry_run or result != 0:
            MANIFEST_PATH.write_bytes(original_bytes)
            if injected:
                print("BOOTSTRAP restored shared manifest")
        return result
    except Exception:
        MANIFEST_PATH.write_bytes(original_bytes)
        raise


if __name__ == "__main__":
    raise SystemExit(main())
