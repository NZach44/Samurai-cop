#!/usr/bin/env python3
"""Process one complete character-art package as a validated transaction."""

from __future__ import annotations

import argparse
import copy
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from statistics import median

from character_art_pipeline import (
    MANIFEST_PATH,
    PROJECT_ROOT,
    Report,
    animation_config,
    calibrate_character_scale_from_images,
    canvas_config,
    create_contact_sheet,
    expected_frame_paths,
    file_sha256,
    normalize_batch,
    read_png,
    reference_statistics,
    save_manifest,
    scale_profile,
    validate_character,
)


GROUP_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_]*$")
PACKAGE_FILENAME = "character_package.json"
DEFAULT_TARGET_HEIGHT_RATIO = 1.0
MIN_IMPLICIT_HEIGHT_RATIO = 0.80
MAX_IMPLICIT_HEIGHT_RATIO = 1.20


@dataclass(frozen=True)
class PackageGroup:
    name: str
    animations: tuple[str, ...]
    anchor: str
    source_generation: str
    anchor_sha256: str


@dataclass(frozen=True)
class CharacterPackage:
    character_id: str
    groups: tuple[PackageGroup, ...]
    path: Path

    @property
    def animations(self) -> list[str]:
        return [animation for group in self.groups for animation in group.animations]


@dataclass(frozen=True)
class CoreScalePlan:
    group: PackageGroup
    source_images: tuple
    source_idle_height: float
    reference_idle_height: float
    target_height_ratio: float
    target_idle_height: float
    multiplier: float


def load_manifest() -> dict:
    with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_target_height_ratio(character: dict) -> tuple[float, bool]:
    explicit = "target_height_ratio_to_reference" in character
    value = character.get("target_height_ratio_to_reference", DEFAULT_TARGET_HEIGHT_RATIO)
    try:
        ratio = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError("target_height_ratio_to_reference must be numeric") from error
    if ratio <= 0.0:
        raise ValueError("target_height_ratio_to_reference must be greater than zero")
    if not explicit and not MIN_IMPLICIT_HEIGHT_RATIO <= ratio <= MAX_IMPLICIT_HEIGHT_RATIO:
        raise ValueError(
            f"implicit physical height ratio {ratio:.3f} is outside "
            f"{MIN_IMPLICIT_HEIGHT_RATIO:.2f}..{MAX_IMPLICIT_HEIGHT_RATIO:.2f}; "
            "an explicit unusual-height override is required"
        )
    return ratio, explicit


def source_to_target_scale(reference_height: float, target_ratio: float, source_height: float) -> float:
    if reference_height <= 0.0 or source_height <= 0.0:
        raise ValueError("reference and source idle heights must be greater than zero")
    return reference_height * target_ratio / source_height


def parse_character_package(
    data: object,
    requested_character_id: str,
    manifest: dict,
    package_path: Path,
    source_root: Path,
) -> CharacterPackage:
    if not isinstance(data, dict):
        raise ValueError("descriptor root must be a JSON object")
    character_id = data.get("character_id")
    if character_id != requested_character_id:
        raise ValueError(
            f"descriptor character_id must be {requested_character_id!r}, found {character_id!r}"
        )
    if character_id not in manifest["characters"]:
        raise ValueError(f"unsupported character_id: {character_id}")
    groups_data = data.get("groups")
    if not isinstance(groups_data, dict) or not groups_data:
        raise ValueError("descriptor groups must be a non-empty JSON object")

    known_animations = set(manifest["animation_order"])
    claimed_animations: dict[str, str] = {}
    groups: list[PackageGroup] = []
    for group_name, group_data in groups_data.items():
        if not isinstance(group_name, str) or GROUP_NAME_PATTERN.fullmatch(group_name) is None:
            raise ValueError(f"invalid generation-group name: {group_name!r}")
        if not isinstance(group_data, dict):
            raise ValueError(f"group {group_name}: metadata must be a JSON object")
        animations = group_data.get("animations")
        if not isinstance(animations, list) or not animations or not all(isinstance(item, str) for item in animations):
            raise ValueError(f"group {group_name}: animations must be a non-empty string array")
        if len(set(animations)) != len(animations):
            raise ValueError(f"group {group_name}: animations contains duplicates")
        unknown = [animation for animation in animations if animation not in known_animations]
        if unknown:
            raise ValueError(f"group {group_name}: unknown animation(s): {', '.join(unknown)}")
        for animation in animations:
            previous = claimed_animations.get(animation)
            if previous is not None:
                raise ValueError(f"animation {animation} is assigned to both {previous} and {group_name}")
            claimed_animations[animation] = group_name
        anchor = group_data.get("anchor")
        if not isinstance(anchor, str) or not anchor or Path(anchor).name != anchor:
            raise ValueError(f"group {group_name}: anchor must be a filename within the group directory")
        group_root = source_root / group_name
        if not group_root.is_dir():
            raise ValueError(f"group {group_name}: source directory is missing")
        if not (group_root / anchor).is_file():
            raise ValueError(f"group {group_name}: anchor is missing: {anchor}")
        source_generation = group_data.get("source_generation")
        if (
            not isinstance(source_generation, str)
            or GROUP_NAME_PATTERN.fullmatch(source_generation) is None
        ):
            raise ValueError(
                f"group {group_name}: source_generation must be a non-empty lowercase identifier"
            )
        groups.append(
            PackageGroup(
                group_name,
                tuple(animations),
                anchor,
                source_generation,
                file_sha256(group_root / anchor),
            )
        )
    package = CharacterPackage(character_id, tuple(groups), package_path)
    validate_package_anchor_provenance(package)
    return package


def validate_package_anchor_provenance(package: CharacterPackage) -> None:
    groups_by_hash: dict[str, list[PackageGroup]] = {}
    for group in package.groups:
        groups_by_hash.setdefault(group.anchor_sha256, []).append(group)
    for anchor_hash, groups in groups_by_hash.items():
        source_generations = {group.source_generation for group in groups}
        if len(source_generations) <= 1:
            continue
        details = ", ".join(
            f"{group.name}={group.source_generation}" for group in groups
        )
        raise ValueError(
            f"anchor SHA256 {anchor_hash} is copied across unrelated source generations: {details}"
        )


def load_character_package(character_id: str, manifest: dict) -> CharacterPackage:
    source_root = PROJECT_ROOT / "reference" / character_id / "generated_batches"
    package_path = source_root / PACKAGE_FILENAME
    try:
        with package_path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError as error:
        raise ValueError(f"package descriptor is missing: {package_path.relative_to(PROJECT_ROOT)}") from error
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read package descriptor: {error}") from error
    return parse_character_package(data, character_id, manifest, package_path, source_root)


def register_package_groups(manifest: dict, package: CharacterPackage) -> list[str]:
    character = manifest["characters"][package.character_id]
    batches = character.setdefault("production_batches", {})
    registered: list[str] = []
    package_names = {group.name for group in package.groups}
    for group in package.groups:
        existing = batches.get(group.name)
        expected_anchor = {"type": "neutral_standing", "filename": group.anchor}
        if existing is not None:
            if (
                existing.get("animations") != list(group.animations)
                or existing.get("anchor") != expected_anchor
                or existing.get("generation_group") is not True
            ):
                raise ValueError(
                    f"group {group.name}: descriptor conflicts with existing metadata; refusing to overwrite it"
                )
            existing_generation = existing.get("source_generation")
            replacement_allowed = (
                existing.get("status") == "requires_source_calibration"
                or existing.get("anchor_provenance", {}).get("status") == "invalid"
            )
            if existing_generation not in {None, group.source_generation} and not replacement_allowed:
                raise ValueError(
                    f"group {group.name}: source_generation conflicts with approved metadata; refusing to overwrite it"
                )
            if replacement_allowed and (
                existing_generation != group.source_generation
                or existing.get("anchor_sha256") != group.anchor_sha256
            ):
                batches[group.name] = {
                    "status": "pending_normalization",
                    "generation_group": True,
                    "source_generation": group.source_generation,
                    "anchor": expected_anchor,
                    "anchor_sha256": group.anchor_sha256,
                    "anchor_provenance": {
                        "status": "pending",
                        "source_generation": group.source_generation,
                        "sha256": group.anchor_sha256,
                    },
                    "animations": list(group.animations),
                }
                registered.append(group.name)
                continue
            if existing_generation is None:
                if existing.get("status") in {"approved", "reference"}:
                    raise ValueError(
                        f"group {group.name}: approved metadata lacks source_generation; explicit migration is required"
                    )
                existing["source_generation"] = group.source_generation
            continue
        for batch_name, batch in batches.items():
            if batch_name in package_names:
                continue
            overlap = sorted(set(group.animations) & set(batch.get("animations", [])))
            if overlap:
                raise ValueError(
                    f"group {group.name}: animation(s) already owned by {batch_name}: {', '.join(overlap)}"
                )
        batches[group.name] = {
            "status": "pending_normalization",
            "generation_group": True,
            "source_generation": group.source_generation,
            "anchor": expected_anchor,
            "anchor_sha256": group.anchor_sha256,
            "anchor_provenance": {
                "status": "pending",
                "source_generation": group.source_generation,
                "sha256": group.anchor_sha256,
            },
            "animations": list(group.animations),
        }
        registered.append(group.name)
    return registered


def source_animation_paths(manifest: dict, package: CharacterPackage, group: PackageGroup, animation: str) -> list[Path]:
    frame_count = int(animation_config(manifest, package.character_id, animation)["frame_count"])
    folder = package.path.parent / group.name / animation
    return [folder / f"{animation}_{number:03d}.png" for number in range(1, frame_count + 1)]


def validate_source_layout(manifest: dict, package: CharacterPackage) -> None:
    for group in package.groups:
        for animation in group.animations:
            expected = source_animation_paths(manifest, package, group, animation)
            folder = expected[0].parent
            if not folder.is_dir():
                raise ValueError(f"group {group.name}: animation directory is missing: {animation}")
            present = sorted(folder.glob("*.png"))
            expected_names = {path.name for path in expected}
            missing = [path.name for path in expected if not path.is_file()]
            extras = [path.name for path in present if path.name not in expected_names]
            if missing:
                raise ValueError(
                    f"group {group.name}/{animation}: missing frame(s): {', '.join(missing)}"
                )
            if extras:
                raise ValueError(
                    f"group {group.name}/{animation}: unexpected PNG file(s): {', '.join(extras)}"
                )


def bootstrap_scale_profile(
    manifest: dict,
    package: CharacterPackage,
    target_height_ratio: float,
) -> CoreScalePlan:
    idle_groups = [group for group in package.groups if "idle" in group.animations]
    if len(idle_groups) != 1:
        raise ValueError("a character without a scale profile requires exactly one package group containing idle")
    core_group = idle_groups[0]
    paths = source_animation_paths(manifest, package, core_group, "idle")
    missing = [path.name for path in paths if not path.is_file()]
    if missing:
        raise ValueError(f"core/idle source is incomplete; missing: {', '.join(missing)}")
    try:
        images = [read_png(path) for path in paths]
    except (OSError, ValueError) as error:
        raise ValueError(f"core/idle source cannot be decoded: {error}") from error
    reference_id = manifest["reference_character"]
    reference_images = [
        read_png(path)
        for path in expected_frame_paths(manifest, reference_id, "idle")
        if path.is_file()
    ]
    if not reference_images or any(image.alpha_bounds is None for image in reference_images + images):
        raise ValueError("complete visible reference and core idle art is required")
    source_height = float(median(image.visible_height for image in images))
    reference_height = float(median(image.visible_height for image in reference_images))
    target_height = reference_height * target_height_ratio
    multiplier = source_to_target_scale(reference_height, target_height_ratio, source_height)
    manifest["characters"][package.character_id]["scale_profile"] = {
        "reference_animation": "idle",
        "height_ratio_to_reference": round(target_height_ratio, 6),
        "target_height_ratio_to_reference": round(target_height_ratio, 6),
        "target_baseline_y": int(canvas_config(manifest, package.character_id)["target_ground_baseline"]),
    }
    return CoreScalePlan(
        core_group,
        tuple(images),
        source_height,
        reference_height,
        target_height_ratio,
        target_height,
        multiplier,
    )


def ordered_groups(package: CharacterPackage, core_group: PackageGroup | None) -> list[PackageGroup]:
    if core_group is None:
        return list(package.groups)
    return [core_group, *(group for group in package.groups if group != core_group)]


def validate_staged_group(manifest: dict, package: CharacterPackage, group: PackageGroup, root: Path) -> bool:
    references = reference_statistics(manifest, group.animations)
    report = Report()
    validate_character(
        manifest,
        package.character_id,
        references,
        report,
        list(group.animations),
        True,
        sprite_root=root,
    )
    report.summary(f"GROUP {group.name}")
    return report.errors == 0


def promote_staged_groups(package: CharacterPackage, staged_roots: dict[str, Path]) -> None:
    sprite_root = PROJECT_ROOT / "assets" / "characters" / package.character_id / "sprites"
    for group in package.groups:
        for animation in group.animations:
            source_folder = staged_roots[group.name] / animation
            production_folder = sprite_root / animation
            production_folder.mkdir(parents=True, exist_ok=True)
            for existing_png in production_folder.glob("*.png"):
                existing_png.unlink()
            for source_path in sorted(source_folder.glob("*.png")):
                shutil.copy2(source_path, production_folder / source_path.name)


def restore_snapshot(manifest_bytes: bytes, character_root: Path, backup_root: Path, existed: bool) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=".character_art_manifest.", suffix=".restore", dir=MANIFEST_PATH.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(manifest_bytes)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, MANIFEST_PATH)
    finally:
        temporary_path.unlink(missing_ok=True)
    if character_root.exists():
        shutil.rmtree(character_root)
    if existed:
        shutil.copytree(backup_root, character_root)


def run_command(command: list[str]) -> bool:
    result = subprocess.run(command, cwd=PROJECT_ROOT, text=True, capture_output=True, check=False)
    if result.stdout.strip():
        print(result.stdout.rstrip())
    if result.stderr.strip():
        print(result.stderr.rstrip(), file=sys.stderr)
    return result.returncode == 0


def process_package(character_id: str, dry_run: bool) -> int:
    manifest = load_manifest()
    if character_id not in manifest["characters"]:
        print(f"ERROR unsupported character_id: {character_id}", file=sys.stderr)
        return 2
    print(f"CHARACTER: {character_id}\n")
    try:
        package = load_character_package(character_id, manifest)
        validate_source_layout(manifest, package)
        print(f"PACKAGE\n  PASS descriptor: {package.path.relative_to(PROJECT_ROOT)}")
        original_batches = copy.deepcopy(manifest["characters"][character_id].get("production_batches", {}))
        registrations = register_package_groups(manifest, package)
    except ValueError as error:
        print(f"PACKAGE\n  FAIL {error}\n\nRESULT\n  CHARACTER ART FAILED", file=sys.stderr)
        return 1

    print("  GROUPS " + ", ".join(group.name for group in package.groups))
    print("  REGISTER " + (", ".join(registrations) if registrations else "none (metadata already present)"))

    character = manifest["characters"][character_id]
    try:
        target_height_ratio, target_is_explicit = resolve_target_height_ratio(character)
    except ValueError as error:
        print(f"\nPHYSICAL HEIGHT\n  FAIL {error}\n\nRESULT\n  CHARACTER ART FAILED", file=sys.stderr)
        return 1
    existing_profile = scale_profile(manifest, character_id)
    existing_ratio = (
        float(existing_profile.get("height_ratio_to_reference", 0.0))
        if existing_profile is not None
        else 0.0
    )
    profile_requires_rebuild = existing_profile is None or not math.isclose(
        existing_ratio,
        target_height_ratio,
        rel_tol=0.0,
        abs_tol=0.02,
    )
    core_group: PackageGroup | None = None
    approved_idle = None
    core_plan: CoreScalePlan | None = None
    try:
        print(
            "\nPHYSICAL HEIGHT\n"
            f"  PASS target ratio={target_height_ratio:.6f} "
            f"({'explicit' if target_is_explicit else 'default'})"
        )
        if profile_requires_rebuild:
            core_plan = bootstrap_scale_profile(manifest, package, target_height_ratio)
            core_group = core_plan.group
            approved_idle = list(core_plan.source_images)
            print(
                "\nCORE\n"
                f"  SOURCE idle median={core_plan.source_idle_height:.1f}px "
                f"({core_plan.source_idle_height / core_plan.reference_idle_height:.6f} of reference; source scale only)\n"
                f"  TARGET reference={core_plan.reference_idle_height:.1f}px, "
                f"ratio={core_plan.target_height_ratio:.6f}, idle={core_plan.target_idle_height:.1f}px\n"
                f"  PASS core normalization multiplier={core_plan.multiplier:.6f}"
            )
        else:
            print(
                "\nCORE\n"
                f"  PASS existing normalized calibration preserved: height ratio={existing_ratio:.6f}, "
                f"baseline={int(existing_profile['target_baseline_y'])}"
            )
    except ValueError as error:
        print(f"\nCORE\n  FAIL {error}\n\nRESULT\n  CHARACTER ART FAILED", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix=f"samurai_cop_{character_id}_package_") as temporary_name:
        staging_base = Path(temporary_name)
        staged_roots: dict[str, Path] = {}
        for group in ordered_groups(package, core_group):
            print(f"\nGROUP {group.name}")
            group_report = Report()
            group_root = staging_base / group.name
            previous_batch = original_batches.get(group.name)
            try:
                normalize_batch(
                    manifest,
                    character_id,
                    group.name,
                    group_report,
                    promote=False,
                    save_metadata=False,
                    output_root=group_root,
                    approved_idle=approved_idle,
                    target_height=(core_plan.target_idle_height if core_plan is not None and group == core_group else None),
                    scale_source_height=(core_plan.source_idle_height if core_plan is not None and group == core_group else None),
                )
            except (OSError, ValueError) as error:
                group_report.error(group.name, str(error))
            if group_report.errors:
                group_report.summary(f"GROUP {group.name} NORMALIZE")
                print("\nRESULT\n  CHARACTER ART FAILED; production and SpriteFrames were not modified")
                return 1
            if (
                not profile_requires_rebuild
                and previous_batch
                and previous_batch.get("status") in {"approved", "reference"}
            ):
                generated_batch = manifest["characters"][character_id]["production_batches"][group.name]
                protected_fields = (
                    "batch_multiplier",
                    "animation_multipliers",
                    "output_digests",
                    "anchor_metrics",
                    "baseline",
                    "normalization_version",
                )
                if any(generated_batch.get(field) != previous_batch.get(field) for field in protected_fields):
                    print(
                        "  FAIL source output differs from existing approved metadata; "
                        "explicit review/re-registration is required"
                    )
                    print("\nRESULT\n  CHARACTER ART FAILED; approved metadata was preserved")
                    return 1
                manifest["characters"][character_id]["production_batches"][group.name] = previous_batch
            staged_roots[group.name] = group_root
            if profile_requires_rebuild and group == core_group:
                staged_idle = [
                    read_png(path)
                    for path in expected_frame_paths(manifest, character_id, "idle", group_root)
                ]
                if not calibrate_character_scale_from_images(
                    manifest,
                    character_id,
                    staged_idle,
                    target_height_ratio,
                ):
                    print("  FAIL normalized core calibration")
                    print("\nRESULT\n  CHARACTER ART FAILED; production and SpriteFrames were not modified")
                    return 1
                manifest["characters"][character_id]["scale_profile"]["target_baseline_y"] = int(
                    canvas_config(manifest, character_id)["target_ground_baseline"]
                )
                manifest["characters"][character_id]["scale_profile"].update({
                    "source_idle_median_height": round(core_plan.source_idle_height, 6),
                    "reference_idle_median_height": round(core_plan.reference_idle_height, 6),
                    "target_idle_height": round(core_plan.target_idle_height, 6),
                    "core_source_to_target_multiplier": round(core_plan.multiplier, 6),
                })
                approved_idle = staged_idle
            multiplier = float(manifest["characters"][character_id]["production_batches"][group.name]["batch_multiplier"])
            file_count = sum(len(expected_frame_paths(manifest, character_id, animation, group_root)) for animation in group.animations)
            print(f"  PASS normalize: multiplier={multiplier:.6f}, files={file_count}")
            if dry_run:
                for animation in group.animations:
                    source_paths = source_animation_paths(manifest, package, group, animation)
                    relative_folder = source_paths[0].parent.relative_to(PROJECT_ROOT)
                    print(
                        f"  FILES {relative_folder}/: "
                        + ", ".join(path.name for path in source_paths)
                    )
            if not validate_staged_group(manifest, package, group, group_root):
                print("\nRESULT\n  CHARACTER ART FAILED; production and SpriteFrames were not modified")
                return 1
            print("  PASS validate")

        animations = package.animations
        print("\nSPRITEFRAMES")
        print("  WOULD IMPORT " + ", ".join(animations))
        if dry_run:
            profile = scale_profile(manifest, character_id)
            print(
                "\nDRY RUN\n"
                f"  scale profile: height ratio={float(profile['height_ratio_to_reference']):.6f}, "
                f"baseline={int(profile['target_baseline_y'])}\n"
                f"  contact sheet: artifacts/character_art/{character_id}_full_contact_sheet.png\n"
                "  no manifest, production PNG, SpriteFrames, or Godot resource was modified\n\n"
                "RESULT\n  DRY RUN PASS"
            )
            return 0

        character_root = PROJECT_ROOT / "assets" / "characters" / character_id
        character_existed = character_root.exists()
        manifest_bytes = MANIFEST_PATH.read_bytes()
        with tempfile.TemporaryDirectory(prefix=f"samurai_cop_{character_id}_backup_") as backup_name:
            backup_root = Path(backup_name) / "character"
            if character_existed:
                shutil.copytree(character_root, backup_root)
            try:
                promote_staged_groups(package, staged_roots)
                save_manifest(manifest)
                references = reference_statistics(manifest, animations)
                validation_report = Report()
                validate_character(manifest, character_id, references, validation_report, animations, True)
                validation_report.summary("PACKAGE VALIDATION")
                if validation_report.errors:
                    raise RuntimeError("strict package validation failed")
                contact_sheet = create_contact_sheet(
                    manifest,
                    character_id,
                    animations,
                    f"{character_id}_full_contact_sheet.png",
                )
                print(f"\nCONTACT SHEET\n  PASS {contact_sheet.relative_to(PROJECT_ROOT)}")
                importer = [sys.executable, str(PROJECT_ROOT / "tools" / "spriteframes_importer.py"), character_id]
                if not run_command(importer):
                    raise RuntimeError("SpriteFrames import failed")
                print("\nSPRITEFRAMES\n  PASS import")
                godot = shutil.which("godot")
                if godot is None:
                    raise RuntimeError("Godot executable not found in PATH")
                if not run_command([godot, "--headless", "--editor", "--quit", "--path", str(PROJECT_ROOT)]):
                    raise RuntimeError("Godot headless validation failed")
                print("\nGODOT\n  PASS validation\n\nRESULT\n  CHARACTER ART COMPLETE")
                return 0
            except (OSError, RuntimeError) as error:
                restore_snapshot(manifest_bytes, character_root, backup_root, character_existed)
                print(f"\nROLLBACK\n  PASS previous character assets, manifest, and SpriteFrames restored")
                print(f"\nRESULT\n  CHARACTER ART FAILED: {error}", file=sys.stderr)
                return 1


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("character_id", help="stable CharacterData id to process")
    parser.add_argument("--dry-run", action="store_true", help="preflight the complete package without changing production resources")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    return process_package(arguments.character_id, arguments.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
