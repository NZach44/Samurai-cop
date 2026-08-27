#!/usr/bin/env python3
"""Render deterministic cutout rigs to preview or staged production sprites."""

from __future__ import annotations

import argparse
import copy
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from statistics import median
from typing import Callable

from character_art_pipeline import (
    MANIFEST_PATH,
    PROJECT_ROOT,
    animation_config,
    animation_digest,
    composite_thumbnail,
    draw_text,
    load_manifest,
    read_png,
    save_manifest,
    write_rgba_png,
)
from cutout_rig import (
    choose_canvas,
    load_json,
    materialize_procedural_parts,
    pose_bounds,
    render_pose,
    resolved_parts,
    sample_animation,
    validate_animation_library,
    validate_rig,
)


ANIMATIONS = (
    "idle", "walk", "punch", "kick", "crouch", "crouch_punch",
    "crouch_kick", "block", "crouch_block", "jump", "hurt", "ko",
    "special_1", "special_2",
)
ANATOMY_REPORT_ANIMATIONS = (
    "idle", "crouch", "crouch_punch", "crouch_kick", "jump", "hurt",
    "ko", "special_1", "special_2",
)
RUNTIME_PIXEL_SCALE = 0.25


def recommended_size_limit(width: int, height: int) -> int:
    """Keep a fixed source-pixel-to-runtime-pixel ratio for every canvas."""
    return int(round(max(width, height) * RUNTIME_PIXEL_SCALE))


def _display_path(path: Path) -> str:
    try:
        return path.relative_to(PROJECT_ROOT).as_posix()
    except ValueError:
        return str(path)


def _contact_sheet(
    output_path: Path,
    rendered: dict[str, list[Path]],
    animation_metadata: dict[str, dict],
) -> None:
    thumb_w = 128
    thumb_h = 154
    label_h = 24
    margin = 12
    columns = max(len(rendered[name]) for name in ANIMATIONS)
    sheet_w = margin * 2 + columns * (thumb_w + margin)
    sheet_h = margin + len(ANIMATIONS) * (thumb_h + label_h + margin)
    pixels = bytearray(sheet_w * sheet_h * 4)
    for index in range(0, len(pixels), 4):
        pixels[index:index + 4] = bytes((28, 31, 38, 255))

    for row, animation in enumerate(ANIMATIONS):
        y = margin + row * (thumb_h + label_h + margin)
        meta = animation_metadata[animation]
        draw_text(
            pixels,
            sheet_w,
            margin,
            y,
            f"{animation} {meta['canvas'][0]}x{meta['canvas'][1]} / {meta['size_limit']}",
            2,
        )
        for column, frame_path in enumerate(rendered[animation]):
            frame = read_png(frame_path)
            x = margin + column * (thumb_w + margin)
            top = y + label_h
            composite_thumbnail(pixels, sheet_w, frame, x, top, thumb_w)
    write_rgba_png(output_path, sheet_w, sheet_h, bytes(pixels))


def _anatomy_measurement(
    rig: dict,
    textures: dict[str, object],
    pose: dict,
    canvas: tuple[int, int],
) -> dict:
    parts = {part.get("id", part["name"]): part for part in resolved_parts(rig, set(pose["__attachments__"]["visible"]))}
    result: dict[str, object] = {
        "body_scale": float(rig["body_scale"]),
        "canvas": list(canvas),
        "size_limit": recommended_size_limit(*canvas),
        "canvas_to_runtime_scale": RUNTIME_PIXEL_SCALE,
    }
    for name in ("head", "torso"):
        part = parts[name]
        texture = textures[part["texture"]]
        transform_scale = [
            float(rig["body_scale"]) * float(part["scale"][0]),
            float(rig["body_scale"]) * float(part["scale"][1]),
        ]
        result[name] = {
            "texture_dimensions": [texture.width, texture.height],
            "transform_scale": transform_scale,
            "effective_dimensions": [
                round(texture.width * transform_scale[0], 3),
                round(texture.height * transform_scale[1], 3),
            ],
        }
    return result


def render_character(character_id: str, output_root: Path | None = None) -> dict:
    rig_root = PROJECT_ROOT / "reference" / character_id / "rig_parts"
    rig_path = rig_root / "character_rig.json"
    library_path = PROJECT_ROOT / "data" / "character_rig_animations.json"
    if not rig_path.is_file():
        raise ValueError(f"missing rig definition: {_display_path(rig_path)}")

    rig = load_json(rig_path)
    library = load_json(library_path)
    manifest = load_manifest()
    if character_id not in manifest.get("characters", {}):
        raise ValueError(f"unknown character_id {character_id!r}")
    if rig.get("character_id") != character_id:
        raise ValueError("character_rig.json character_id does not match the command")

    frame_counts = {
        animation: int(animation_config(manifest, character_id, animation)["frame_count"])
        for animation in ANIMATIONS
    }
    validate_rig(rig)
    validate_animation_library(library, frame_counts)
    materialize_procedural_parts(rig, rig_root)

    texture_paths = {
        part["texture"] for part in rig["parts"]
    } | {
        prop["texture"] for prop in rig.get("props", [])
    }
    textures = {texture_path: read_png(rig_root / texture_path) for texture_path in texture_paths}

    poses = {
        animation: [
            sample_animation(library["animations"][animation], index, frame_counts[animation])
            for index in range(frame_counts[animation])
        ]
        for animation in ANIMATIONS
    }
    idle_bounds = [pose_bounds(rig, pose, textures) for pose in poses["idle"]]
    neutral_floor = float(median(bounds[3] for bounds in idle_bounds))
    for animation in ANIMATIONS:
        config = animation_config(manifest, character_id, animation)
        source_animation = library["animations"][animation]
        if animation == "idle" or not bool(config["grounded"]) or not source_animation.get("floor_lock", True):
            continue
        for pose in poses[animation]:
            body_pose = copy.deepcopy(pose)
            body_pose["__attachments__"] = {"visible": []}
            bottom = pose_bounds(rig, body_pose, textures)[3]
            root = pose.setdefault("root", {"position": [0.0, 0.0], "rotation": 0.0})
            position = root.setdefault("position", [0.0, 0.0])
            position[1] = float(position[1]) + neutral_floor - bottom
    animation_bounds = {
        animation: [pose_bounds(rig, pose, textures) for pose in poses[animation]]
        for animation in ANIMATIONS
    }
    canvas_config = rig.get("canvas", {})
    floor_offset = int(canvas_config.get("floor_offset_from_center", 239))
    canvas_layouts = {
        animation: choose_canvas(
            animation_bounds[animation],
            margin=int(canvas_config.get("margin", 20)),
            minimum=int(canvas_config.get("minimum", 512)),
            step=int(canvas_config.get("step", canvas_config.get("dimension_step", 64))),
            floor_offset_from_center=floor_offset,
            neutral_floor=neutral_floor,
        )
        for animation in ANIMATIONS
    }

    output_root = output_root or PROJECT_ROOT / "artifacts" / "character_rig" / character_id
    output_root.mkdir(parents=True, exist_ok=True)
    rendered: dict[str, list[Path]] = {}
    frame_audit: dict[str, list[dict]] = {}
    animation_metadata: dict[str, dict] = {}

    for animation in ANIMATIONS:
        animation_dir = output_root / animation
        animation_dir.mkdir(parents=True, exist_ok=True)
        rendered[animation] = []
        frame_audit[animation] = []
        width, height, origin_x, origin_y = canvas_layouts[animation]
        for frame_index, pose in enumerate(poses[animation], start=1):
            pixels, parts_audit = render_pose(
                rig, pose, textures, width, height, origin_x, origin_y
            )
            frame_path = animation_dir / f"{animation}_{frame_index:03d}.png"
            write_rgba_png(frame_path, width, height, pixels)
            rendered_image = read_png(frame_path)
            if not rendered_image.alpha_bounds:
                raise ValueError(f"{animation} frame {frame_index} rendered empty")
            x0, y0, x1, y1 = rendered_image.alpha_bounds
            if x0 <= 0 or y0 <= 0 or x1 >= width - 1 or y1 >= height - 1:
                raise ValueError(f"{animation} frame {frame_index} clips {width}x{height}")
            audit = {
                "file": _display_path(frame_path),
                "alpha_bbox": list(rendered_image.alpha_bounds),
                "visible_size": [rendered_image.visible_width, rendered_image.visible_height],
                "bones": pose,
                "parts": parts_audit,
            }
            rendered[animation].append(frame_path)
            frame_audit[animation].append(audit)

        config = animation_config(manifest, character_id, animation)
        source_animation = library["animations"][animation]
        animation_metadata[animation] = {
            "frames": frame_counts[animation],
            "fps": float(config["fps"]),
            "loop": bool(config["loop"]),
            "grounded": bool(config["grounded"]) and source_animation.get("floor_lock", True),
            "canvas": [width, height],
            "target_ground_baseline": height // 2 + floor_offset,
            "size_limit": recommended_size_limit(width, height),
            "canvas_to_runtime_scale": RUNTIME_PIXEL_SCALE,
            "events": copy.deepcopy(source_animation.get("events", [])),
        }
        for metadata_key in (
            "title", "projectile_prop", "projectile_spawn_frame", "projectile_origin"
        ):
            if metadata_key in source_animation:
                animation_metadata[animation][metadata_key] = copy.deepcopy(source_animation[metadata_key])

    props_dir = output_root / "props"
    prop_metadata: list[dict] = []
    for prop in rig.get("props", []):
        source = rig_root / prop["texture"]
        destination = props_dir / Path(prop["texture"]).name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        events = [
            event
            for animation in animation_metadata.values()
            for event in animation["events"]
            if event.get("prop") == prop["id"]
        ]
        prop_metadata.append({
            "id": prop["id"],
            "source_texture": _display_path(source),
            "export_texture": f"artifacts/character_rig/{character_id}/props/{destination.name}",
            "attachment_slot": prop["attachment_slot"],
            "suggested_activation_frame": events[0]["frame"] if events else None,
        })

    anatomy = {
        animation: _anatomy_measurement(
            rig, textures, poses[animation][0], canvas_layouts[animation][:2]
        )
        for animation in ANATOMY_REPORT_ANIMATIONS
    }
    idle_heights = [audit["alpha_bbox"][3] - audit["alpha_bbox"][1] + 1 for audit in frame_audit["idle"]]
    report = {
        "schema_version": 2,
        "character_id": character_id,
        "rig": _display_path(rig_path),
        "animation_library": _display_path(library_path),
        "neutral_target_height": int(rig.get("neutral_target_height", rig["target_neutral_height"])),
        "rendered_idle_median_height": float(median(idle_heights)),
        "body_scale": float(rig["body_scale"]),
        "runtime_pixel_scale": RUNTIME_PIXEL_SCALE,
        "frame_count_total": sum(frame_counts.values()),
        "frame_counts": frame_counts,
        "animations": animation_metadata,
        "attachment_slots": copy.deepcopy(rig.get("attachment_slots", {})),
        "props": prop_metadata,
        "anatomy_measurements": anatomy,
        "frames": frame_audit,
    }
    _contact_sheet(output_root / f"{character_id}_full_contact_sheet.png", rendered, animation_metadata)
    (output_root / "anatomy_report.json").write_text(
        json.dumps(anatomy, indent=2) + "\n", encoding="utf-8"
    )
    (output_root / "render_manifest.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    return report


def validate_complete_render(report: dict, root: Path) -> None:
    if report["frame_count_total"] != 73:
        raise ValueError(f"expected 73 frames, rendered {report['frame_count_total']}")
    expected = {name: report["frame_counts"][name] for name in ANIMATIONS}
    if sum(expected.values()) != 73:
        raise ValueError("animation contract does not total 73 frames")
    body_scale = float(report["body_scale"])
    for animation in ANIMATIONS:
        metadata = report["animations"][animation]
        if abs(float(metadata["canvas_to_runtime_scale"]) - RUNTIME_PIXEL_SCALE) > 1e-9:
            raise ValueError(f"{animation}: inconsistent runtime pixel scale")
        if metadata["size_limit"] != recommended_size_limit(*metadata["canvas"]):
            raise ValueError(f"{animation}: incorrect size_limit")
        animation_dir = root / animation
        paths = sorted(animation_dir.glob(f"{animation}_*.png"))
        if len(paths) != expected[animation]:
            raise ValueError(f"{animation}: expected {expected[animation]} files, found {len(paths)}")
        for path in paths:
            image = read_png(path)
            if image.color_type != 6 or image.alpha_bounds is None:
                raise ValueError(f"{path}: output must be non-empty RGBA")
    for animation, measurement in report["anatomy_measurements"].items():
        for part in ("head", "torso"):
            if measurement[part]["transform_scale"] != [body_scale, body_scale]:
                raise ValueError(f"{animation}: {part} scale changed")


def transactional_promote(
    staged_root: Path,
    character_root: Path,
    animations: tuple[str, ...],
    finalize: Callable[[], None],
) -> None:
    character_root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cutout_rig_backup_") as backup_name:
        backup_root = Path(backup_name) / character_root.name
        existed = character_root.exists()
        if existed:
            shutil.copytree(character_root, backup_root)
        try:
            sprites_root = character_root / "sprites"
            sprites_root.mkdir(parents=True, exist_ok=True)
            for animation in animations:
                destination = sprites_root / animation
                if destination.exists():
                    shutil.rmtree(destination)
                shutil.copytree(staged_root / animation, destination)
            finalize()
        except Exception:
            if character_root.exists():
                shutil.rmtree(character_root)
            if existed:
                shutil.copytree(backup_root, character_root)
            raise


def _configure_production_manifest(manifest: dict, character_id: str, report: dict) -> None:
    character = manifest["characters"][character_id]
    for animation in ANIMATIONS:
        meta = report["animations"][animation]
        character.setdefault("animations", {}).setdefault(animation, {})["production_canvas"] = {
            "width": meta["canvas"][0],
            "height": meta["canvas"][1],
            "target_ground_baseline": meta["target_ground_baseline"],
            "runtime_texture_size_limit": meta["size_limit"],
        }
        character["animations"][animation]["grounded"] = bool(meta["grounded"])
    output_root = PROJECT_ROOT / "assets" / "characters" / character_id / "sprites"
    output_digests = {
        animation: animation_digest(
            sorted((output_root / animation).glob(f"{animation}_*.png"))
        )
        for animation in ANIMATIONS
    }
    character["production_batches"] = {
        "cutout_rig_v1": {
            "status": "approved",
            "source_type": "deterministic_cutout_rig",
            "generation_group": False,
            "animations": list(ANIMATIONS),
            "batch_multiplier": float(report["body_scale"]),
            "animation_multipliers": {
                animation: float(report["body_scale"]) for animation in ANIMATIONS
            },
            "output_digests": output_digests,
            "render_manifest": f"artifacts/character_rig/{character_id}/render_manifest.json",
        }
    }
    character["rig_render_profile"] = {
        "neutral_target_height": report["neutral_target_height"],
        "body_scale": report["body_scale"],
        "runtime_pixel_scale": RUNTIME_PIXEL_SCALE,
    }


def promote_production(character_id: str, staged_root: Path, report: dict) -> None:
    manifest_before = MANIFEST_PATH.read_bytes()
    manifest = load_manifest()
    character_root = PROJECT_ROOT / "assets" / "characters" / character_id

    def finalize() -> None:
        _configure_production_manifest(manifest, character_id, report)
        save_manifest(manifest)
        subprocess.run(
            [
                sys.executable,
                str(PROJECT_ROOT / "tools" / "character_art_pipeline.py"),
                character_id,
                "--animations",
                ",".join(ANIMATIONS),
            ],
            cwd=PROJECT_ROOT,
            check=True,
        )
        subprocess.run(
            [sys.executable, str(PROJECT_ROOT / "tools" / "spriteframes_importer.py"), character_id],
            cwd=PROJECT_ROOT,
            check=True,
        )
        godot = shutil.which("godot")
        if godot is None:
            raise ValueError("Godot executable not found in PATH")
        subprocess.run(
            [godot, "--headless", "--editor", "--quit", "--path", str(PROJECT_ROOT)],
            cwd=PROJECT_ROOT,
            check=True,
        )
        qa_root = PROJECT_ROOT / "artifacts" / "character_rig" / character_id
        qa_root.mkdir(parents=True, exist_ok=True)
        for filename in (
            "render_manifest.json",
            "anatomy_report.json",
            f"{character_id}_full_contact_sheet.png",
        ):
            shutil.copy2(staged_root / filename, qa_root / filename)
        if (staged_root / "props").is_dir():
            if (qa_root / "props").exists():
                shutil.rmtree(qa_root / "props")
            shutil.copytree(staged_root / "props", qa_root / "props")

    try:
        transactional_promote(staged_root, character_root, ANIMATIONS, finalize)
    except Exception:
        MANIFEST_PATH.write_bytes(manifest_before)
        raise


def print_report(report: dict, mode: str) -> None:
    print(f"CHARACTER: {report['character_id']}")
    print(f"MODE: {mode}")
    print(f"BODY SCALE: {report['body_scale']:.6f}")
    print(f"NEUTRAL TARGET: {report['neutral_target_height']}px")
    for animation in ANIMATIONS:
        meta = report["animations"][animation]
        print(
            f"{animation:14} {meta['frames']:2d} frames  "
            f"{meta['canvas'][0]}x{meta['canvas'][1]}  size_limit={meta['size_limit']}"
        )
    print(f"TOTAL: {report['frame_count_total']} frames")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("character_id")
    parser.add_argument("--production", action="store_true", help="stage and promote production sprites")
    parser.add_argument("--dry-run", action="store_true", help="validate a temporary render without writing outputs")
    args = parser.parse_args()

    try:
        if args.dry_run or args.production:
            with tempfile.TemporaryDirectory(prefix=f"{args.character_id}_rig_stage_") as stage_name:
                stage = Path(stage_name)
                report = render_character(args.character_id, stage)
                validate_complete_render(report, stage)
                if args.production and not args.dry_run:
                    promote_production(args.character_id, stage, report)
                    print_report(report, "PRODUCTION PROMOTED")
                else:
                    print_report(report, "PRODUCTION DRY RUN" if args.production else "DRY RUN")
                    print("NO FILES PROMOTED")
        else:
            output = PROJECT_ROOT / "artifacts" / "character_rig" / args.character_id
            report = render_character(args.character_id, output)
            validate_complete_render(report, output)
            print_report(report, "PREVIEW")
            print(f"OUTPUT: {_display_path(output)}")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
