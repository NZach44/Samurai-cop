#!/usr/bin/env python3
"""Import complete production animation folders into Godot SpriteFrames resources."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from character_art_pipeline import (
    animation_digest,
    assess_animation_baseline,
    batch_consistency_error,
    production_batch_for_animation,
    read_png,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "data" / "character_art_manifest.json"
GODOT_IMPORTER = PROJECT_ROOT / "tools" / "update_character_spriteframes.gd"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ANIMATION_NAME_PATTERN = re.compile(r'"name":\s*&"([^"]+)"')


@dataclass
class ImportPlan:
    character_id: str
    resource_path: Path
    replacements: dict[str, list[Path]]
    preserved: list[str]
    skipped: dict[str, str]
    errors: list[str]


def load_manifest() -> dict:
    with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def animation_config(manifest: dict, character_id: str, animation: str) -> dict:
    config = dict(manifest["animations"][animation])
    config.update(manifest["characters"][character_id].get("animations", {}).get(animation, {}))
    return config


def project_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise ValueError(f"resource path must use res://: {resource_path}")
    resolved = (PROJECT_ROOT / resource_path.removeprefix("res://")).resolve()
    if PROJECT_ROOT.resolve() not in resolved.parents:
        raise ValueError(f"resource path escapes the project: {resource_path}")
    return resolved


def batch_import_failure(manifest: dict, character_id: str, animation: str, paths: list[Path]) -> str | None:
    entry = production_batch_for_animation(manifest, character_id, animation)
    if entry is None:
        return "production animation is not assigned to a calibrated batch"
    batch_name, batch = entry
    error = batch_consistency_error(batch)
    if error:
        return f"{batch_name}: {error}"
    expected_digest = batch.get("output_digests", {}).get(animation)
    if expected_digest and animation_digest(paths) != expected_digest:
        return f"{batch_name}: production files differ from calibrated batch output"
    return None


def build_plan(manifest: dict, character_id: str) -> ImportPlan:
    character = manifest["characters"][character_id]
    errors: list[str] = []
    replacements: dict[str, list[Path]] = {}
    preserved: list[str] = []
    skipped: dict[str, str] = {}
    try:
        resource_path = project_path(character["sprite_frames"])
    except ValueError as error:
        return ImportPlan(character_id, PROJECT_ROOT, replacements, preserved, skipped, [str(error)])
    if not resource_path.is_file():
        errors.append(f"SpriteFrames resource does not exist: {resource_path.relative_to(PROJECT_ROOT)}")
    else:
        try:
            resource_text = resource_path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"cannot read SpriteFrames resource: {error}")
        else:
            if not resource_text.startswith('[gd_resource type="SpriteFrames"'):
                errors.append(f"resource is not a Godot SpriteFrames .tres: {resource_path.relative_to(PROJECT_ROOT)}")

    sprite_root = PROJECT_ROOT / "assets" / "characters" / character_id / "sprites"
    for animation in manifest["animation_order"]:
        config = animation_config(manifest, character_id, animation)
        frame_count = int(config["frame_count"])
        folder = sprite_root / animation
        present_pngs = sorted(folder.glob("*.png")) if folder.is_dir() else []
        if not present_pngs:
            preserved.append(animation)
            continue
        expected = [folder / f"{animation}_{number:03d}.png" for number in range(1, frame_count + 1)]
        expected_names = {path.name for path in expected}
        missing = [path.name for path in expected if not path.is_file()]
        extras = [path.name for path in present_pngs if path.name not in expected_names]
        if missing:
            errors.append(f"{animation}: incomplete production set; missing {', '.join(missing)}")
        if extras:
            errors.append(f"{animation}: unexpected PNG file(s): {', '.join(extras)}")
        invalid_pngs = [path.name for path in expected if path.is_file() and path.read_bytes()[:8] != PNG_SIGNATURE]
        if invalid_pngs:
            errors.append(f"{animation}: invalid PNG signature: {', '.join(invalid_pngs)}")
        if not missing and not extras and not invalid_pngs:
            try:
                images = [read_png(path) for path in expected]
            except (OSError, ValueError) as error:
                skipped[animation] = f"production art could not be decoded: {error}"
                continue
            invalid_visual = next(
                (
                    path.name
                    for path, image in zip(expected, images)
                    if (image.width, image.height) != (512, 512)
                    or image.color_type != 6
                    or image.transparent_pixels == 0
                    or image.alpha_bounds is None
                ),
                None,
            )
            if invalid_visual:
                skipped[animation] = f"production art failed PNG/transparency validation ({invalid_visual})"
                continue
            batch_failure = batch_import_failure(manifest, character_id, animation, expected)
            if batch_failure is not None:
                skipped[animation] = batch_failure
                continue
            baseline = assess_animation_baseline(manifest, character_id, animation, images)
            if baseline is not None and baseline.status == "ERROR":
                skipped[animation] = (
                    f"production art failed baseline calibration: y={baseline.measured:.1f}, "
                    f"target={baseline.target:.1f} ({baseline.delta:+.1f}px)"
                )
                continue
            replacements[animation] = expected
    return ImportPlan(character_id, resource_path, replacements, preserved, skipped, errors)


def print_plan(manifest: dict, plan: ImportPlan) -> None:
    print(f"\n=== {plan.character_id} ===")
    if plan.resource_path != PROJECT_ROOT:
        print(f"RESOURCE {plan.resource_path.relative_to(PROJECT_ROOT)}")
    for animation in manifest["animation_order"]:
        if animation in plan.replacements:
            print(f"REPLACE {animation} with {len(plan.replacements[animation])} production frames")
        elif animation in plan.skipped:
            print(f"SKIP {animation}: {plan.skipped[animation]}")
        else:
            print(f"PRESERVE {animation} placeholder/fallback (no production PNGs)")
    for error in plan.errors:
        print(f"ERROR {error}")


def atomic_restore(path: Path, original: bytes, original_mode: int) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".restore", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(original)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_path, stat.S_IMODE(original_mode))
        os.replace(temporary_path, path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def verify_saved_resource(plan: ImportPlan, previous_names: set[str]) -> list[str]:
    try:
        text = plan.resource_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        return [f"cannot read saved resource: {error}"]
    current_names = set(ANIMATION_NAME_PATTERN.findall(text))
    missing_names = sorted(previous_names - current_names)
    errors = [f"saved resource lost existing animation(s): {', '.join(missing_names)}"] if missing_names else []
    for animation, paths in plan.replacements.items():
        if animation not in current_names:
            errors.append(f"saved resource is missing replaced animation: {animation}")
        for path in paths:
            resource_path = "res://" + path.relative_to(PROJECT_ROOT).as_posix()
            if resource_path not in text:
                errors.append(f"saved resource is missing frame reference: {resource_path}")
    return errors


def run_godot(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    descriptor, log_name = tempfile.mkstemp(prefix="samurai_cop_spriteframes_", suffix=".log")
    os.close(descriptor)
    log_path = Path(log_name)
    command = [arguments[0], "--log-file", str(log_path), *arguments[1:]]
    try:
        return subprocess.run(command, cwd=PROJECT_ROOT, text=True, capture_output=True, check=False)
    finally:
        log_path.unlink(missing_ok=True)


def enforce_runtime_texture_limit(plans: list[ImportPlan], size_limit: int) -> tuple[int, list[str]]:
    changed = 0
    errors: list[str] = []
    for plan in plans:
        for paths in plan.replacements.values():
            for path in paths:
                import_path = path.with_name(path.name + ".import")
                try:
                    text = import_path.read_text(encoding="utf-8")
                except OSError as error:
                    errors.append(f"{import_path.relative_to(PROJECT_ROOT)}: {error}")
                    continue
                replacement, count = re.subn(r"process/size_limit=\d+", f"process/size_limit={size_limit}", text, count=1)
                if count != 1:
                    errors.append(f"{import_path.relative_to(PROJECT_ROOT)}: process/size_limit setting is missing")
                    continue
                if replacement != text:
                    import_path.write_text(replacement, encoding="utf-8")
                    changed += 1
    return changed, errors


def runtime_texture_limit_mismatches(plan: ImportPlan, size_limit: int) -> int:
    mismatches = 0
    for paths in plan.replacements.values():
        for path in paths:
            import_path = path.with_name(path.name + ".import")
            try:
                text = import_path.read_text(encoding="utf-8")
            except OSError:
                mismatches += 1
                continue
            match = re.search(r"process/size_limit=(\d+)", text)
            if match is None or int(match.group(1)) != size_limit:
                mismatches += 1
    return mismatches


def import_plan(plan: ImportPlan, godot_command: str) -> bool:
    if not plan.replacements:
        print(f"NO CHANGES {plan.character_id}: no complete production animations found")
        return True
    original = plan.resource_path.read_bytes()
    original_mode = plan.resource_path.stat().st_mode
    previous_names = set(ANIMATION_NAME_PATTERN.findall(original.decode("utf-8")))
    command = [
        godot_command,
        "--headless",
        "--path",
        str(PROJECT_ROOT),
        "--script",
        str(GODOT_IMPORTER),
        "--",
        plan.character_id,
        "--animations=" + ",".join(plan.replacements),
    ]
    result = run_godot(command)
    if result.stdout.strip():
        print(result.stdout.rstrip())
    if result.returncode != 0:
        if result.stderr.strip():
            print(result.stderr.rstrip(), file=sys.stderr)
        atomic_restore(plan.resource_path, original, original_mode)
        print(f"ERROR {plan.character_id}: Godot import failed; original resource restored", file=sys.stderr)
        return False
    verification_errors = verify_saved_resource(plan, previous_names)
    if verification_errors:
        atomic_restore(plan.resource_path, original, original_mode)
        for error in verification_errors:
            print(f"ERROR {plan.character_id}: {error}", file=sys.stderr)
        print(f"ERROR {plan.character_id}: verification failed; original resource restored", file=sys.stderr)
        return False
    print(f"IMPORTED {plan.character_id}: {len(plan.replacements)} animation(s) updated")
    return True


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("character_id", nargs="?", help="stable CharacterData id to import")
    target.add_argument("--all", action="store_true", help="import every roster character")
    parser.add_argument("--dry-run", action="store_true", help="show the replacement plan without writing resources")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    manifest = load_manifest()
    character_ids = list(manifest["characters"])
    targets = character_ids if arguments.all else [arguments.character_id]
    unknown = [character_id for character_id in targets if character_id not in manifest["characters"]]
    if unknown:
        print(f"Unknown character id: {', '.join(unknown)}", file=sys.stderr)
        print(f"Known ids: {', '.join(character_ids)}", file=sys.stderr)
        return 2

    plans = [build_plan(manifest, character_id) for character_id in targets]
    for plan in plans:
        print_plan(manifest, plan)
    if any(plan.errors for plan in plans):
        print("\nIMPORT ABORTED: fix the reported production/resource errors before importing.", file=sys.stderr)
        return 1
    if arguments.dry_run:
        size_limit = int(manifest["canvas"]["runtime_texture_size_limit"])
        for plan in plans:
            mismatches = runtime_texture_limit_mismatches(plan, size_limit)
            if mismatches:
                print(f"IMPORT SETTINGS {plan.character_id}: would normalize {mismatches} texture import(s) to size_limit={size_limit}")
        print("\nDRY RUN COMPLETE: no resources were modified.")
        return 0

    godot_command = shutil.which("godot")
    if godot_command is None:
        print("Godot executable not found in PATH.", file=sys.stderr)
        return 1
    if not GODOT_IMPORTER.is_file():
        print(f"Godot importer helper is missing: {GODOT_IMPORTER.relative_to(PROJECT_ROOT)}", file=sys.stderr)
        return 1

    import_scan = run_godot([godot_command, "--headless", "--editor", "--quit", "--path", str(PROJECT_ROOT)])
    if import_scan.returncode != 0:
        if import_scan.stdout.strip():
            print(import_scan.stdout.rstrip())
        if import_scan.stderr.strip():
            print(import_scan.stderr.rstrip(), file=sys.stderr)
        print("Asset import scan failed; no SpriteFrames resources were modified.", file=sys.stderr)
        return 1

    size_limit = int(manifest["canvas"]["runtime_texture_size_limit"])
    changed_imports, import_setting_errors = enforce_runtime_texture_limit(plans, size_limit)
    if import_setting_errors:
        for error in import_setting_errors:
            print(f"ERROR {error}", file=sys.stderr)
        print("Texture import calibration failed; no SpriteFrames resources were modified.", file=sys.stderr)
        return 1
    if changed_imports:
        print(f"IMPORT SETTINGS: normalized {changed_imports} texture import(s) to size_limit={size_limit}")
        import_scan = run_godot([godot_command, "--headless", "--editor", "--quit", "--path", str(PROJECT_ROOT)])
        if import_scan.returncode != 0:
            print("Calibrated texture reimport failed; no SpriteFrames resources were modified.", file=sys.stderr)
            return 1

    success = all(import_plan(plan, godot_command) for plan in plans)
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
