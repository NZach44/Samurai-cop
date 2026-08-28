#!/usr/bin/env python3
"""Render deterministic cutout rigs to preview or staged production sprites."""

from __future__ import annotations

import argparse
import copy
import json
import math
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
    REQUIRED_BODY_PARTS,
    bone_world_transforms,
    choose_canvas,
    load_json,
    materialize_procedural_parts,
    pose_bounds,
    render_pose,
    resolved_parts,
    sample_animation,
    validate_animation_library,
    validate_rig,
    validate_rig_textures,
)


ANIMATIONS = (
    "idle", "walk", "punch", "kick", "crouch", "crouch_punch",
    "crouch_kick", "block", "crouch_block", "jump", "hurt", "ko",
    "special_1", "special_2",
)
ANATOMY_REPORT_ANIMATIONS = (
    "idle", "crouch", "crouch_punch", "crouch_kick", "block",
    "crouch_block", "jump", "hurt", "ko", "special_1", "special_2",
)
RUNTIME_PIXEL_SCALE = 0.25
PRODUCTION_RIG_RELATIVE_PATH = Path("reference/fujiyama/rig_parts_production/character_rig.json")
PRODUCTION_TEXTURE_FILENAMES = (
    "head.png", "torso.png", "pelvis.png",
    "front_upper_arm.png", "front_forearm.png", "front_hand.png",
    "back_upper_arm.png", "back_forearm.png", "back_hand.png",
    "front_thigh.png", "front_shin.png", "front_foot.png",
    "back_thigh.png", "back_shin.png", "back_foot.png",
    "props/piano.png",
)
PRODUCTION_APPEARANCE_FIELDS = (
    "heritage", "age", "hair", "facial_hair", "expression", "clothing",
    "shirt", "tie", "belt", "shoes", "proportions", "rendering_style", "exclusions",
)
PRODUCTION_PIVOT_JOINTS = {
    "head": "neck",
    "front_upper_arm": "shoulder", "back_upper_arm": "shoulder",
    "front_forearm": "elbow", "back_forearm": "elbow",
    "front_hand": "wrist", "back_hand": "wrist",
    "front_thigh": "hip", "back_thigh": "hip",
    "front_shin": "knee", "back_shin": "knee",
    "front_foot": "ankle", "back_foot": "ankle",
}


def recommended_size_limit(width: int, height: int) -> int:
    """Keep a fixed source-pixel-to-runtime-pixel ratio for every canvas."""
    return int(round(max(width, height) * RUNTIME_PIXEL_SCALE))


def resolve_rig_path(character_id: str, requested_path: Path | None = None) -> tuple[Path, bool]:
    if requested_path is None:
        return PROJECT_ROOT / "reference" / character_id / "rig_parts" / "character_rig.json", False
    path = requested_path if requested_path.is_absolute() else PROJECT_ROOT / requested_path
    resolved = path.resolve()
    if PROJECT_ROOT.resolve() not in resolved.parents:
        raise ValueError("--rig must resolve inside the project")
    return resolved, True


def missing_production_package_files(rig_path: Path) -> list[str]:
    if rig_path.is_file():
        return []
    root = rig_path.parent
    expected = ["character_rig.json", *PRODUCTION_TEXTURE_FILENAMES]
    return [relative for relative in expected if not (root / relative).is_file()]


def validate_production_rig_contract(rig: dict, character_id: str) -> None:
    if rig.get("character_id") != character_id:
        raise ValueError("production rig character_id does not match the command")
    if rig.get("procedural_parts"):
        raise ValueError("production rigs may not declare procedural placeholder textures")
    appearance = rig.get("appearance_contract")
    if not isinstance(appearance, dict):
        raise ValueError("production rig must define appearance_contract")
    missing_fields = [field for field in PRODUCTION_APPEARANCE_FIELDS if not appearance.get(field)]
    if missing_fields:
        raise ValueError("appearance_contract is missing: " + ", ".join(missing_fields))
    exclusions = {str(value).lower() for value in appearance.get("exclusions", [])}
    if not {"glasses", "exaggerated superhero musculature"}.issubset(exclusions):
        raise ValueError(
            "appearance_contract exclusions must include glasses and exaggerated superhero musculature"
        )
    prop_ids = {str(prop.get("id")) for prop in rig.get("props", [])}
    if "piano" not in prop_ids:
        raise ValueError("production Fujiyama rig must define piano as a separate prop")
    parts = {str(part.get("name")): part for part in rig.get("parts", [])}
    invalid_joints = [
        f"{name} -> {joint}"
        for name, joint in PRODUCTION_PIVOT_JOINTS.items()
        if parts.get(name, {}).get("pivot_joint") != joint
    ]
    if invalid_joints:
        raise ValueError(
            "production rig pivot_joint metadata is missing or incorrect: "
            + ", ".join(invalid_joints)
        )


def frame_clearance(image: object) -> dict[str, int]:
    if image.alpha_bounds is None:
        raise ValueError("cannot calculate clearance for an empty image")
    min_x, min_y, max_x, max_y = image.alpha_bounds
    return {
        "top": min_y,
        "bottom": image.height - 1 - max_y,
        "left": min_x,
        "right": image.width - 1 - max_x,
    }


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


def _blit_thumbnail(
    canvas: bytearray,
    canvas_width: int,
    canvas_height: int,
    image: object,
    x: int,
    y: int,
    box_width: int,
    box_height: int,
) -> tuple[float, int, int]:
    scale = min(box_width / image.width, box_height / image.height, 1.0)
    draw_width = max(1, round(image.width * scale))
    draw_height = max(1, round(image.height * scale))
    offset_x = x + (box_width - draw_width) // 2
    offset_y = y + (box_height - draw_height) // 2
    for target_y in range(draw_height):
        source_y = min(image.height - 1, int(target_y / scale))
        for target_x in range(draw_width):
            source_x = min(image.width - 1, int(target_x / scale))
            source_index = (source_y * image.width + source_x) * 4
            alpha = image.rgba[source_index + 3]
            if alpha == 0:
                continue
            canvas_x, canvas_y = offset_x + target_x, offset_y + target_y
            if not (0 <= canvas_x < canvas_width and 0 <= canvas_y < canvas_height):
                continue
            destination = (canvas_y * canvas_width + canvas_x) * 4
            canvas[destination:destination + 4] = image.rgba[source_index:source_index + 4]
    return scale, offset_x, offset_y


def _mark_pivot(canvas: bytearray, width: int, height: int, x: int, y: int) -> None:
    for offset in range(-5, 6):
        for point_x, point_y in ((x + offset, y), (x, y + offset)):
            if 0 <= point_x < width and 0 <= point_y < height:
                index = (point_y * width + point_x) * 4
                canvas[index:index + 4] = bytes((255, 62, 62, 255))


def _parts_contact_sheet(
    output_path: Path,
    rig: dict,
    textures: dict[str, object],
    neutral_path: Path,
) -> None:
    entries = [*rig["parts"], *rig.get("props", [])]
    columns, cell_width, cell_height = 4, 250, 235
    rows = math.ceil((len(entries) + 1) / columns)
    width, height = columns * cell_width, rows * cell_height
    pixels = bytearray(width * height * 4)
    for index, item in enumerate(entries):
        column, row = index % columns, index // columns
        cell_x, cell_y = column * cell_width, row * cell_height
        image = textures[str(item["texture"])]
        name = str(item.get("name", item.get("id", "part")))
        draw_text(pixels, width, cell_x + 8, cell_y + 8, name, 1)
        draw_text(pixels, width, cell_x + 8, cell_y + 20, f"{image.width}x{image.height}", 1)
        pivot = item["pivot"]
        draw_text(
            pixels,
            width,
            cell_x + 8,
            cell_y + 32,
            f"PIVOT {float(pivot[0]):.0f},{float(pivot[1]):.0f}",
            1,
        )
        scale, image_x, image_y = _blit_thumbnail(
            pixels, width, height, image, cell_x + 8, cell_y + 54, cell_width - 16, cell_height - 62
        )
        _mark_pivot(
            pixels,
            width,
            height,
            round(image_x + float(pivot[0]) * scale),
            round(image_y + float(pivot[1]) * scale),
        )

    neutral_index = len(entries)
    cell_x = (neutral_index % columns) * cell_width
    cell_y = (neutral_index // columns) * cell_height
    neutral = read_png(neutral_path)
    draw_text(pixels, width, cell_x + 8, cell_y + 8, "ASSEMBLED NEUTRAL", 1)
    draw_text(pixels, width, cell_x + 8, cell_y + 20, f"{neutral.width}x{neutral.height}", 1)
    _blit_thumbnail(
        pixels, width, height, neutral, cell_x + 8, cell_y + 42, cell_width - 16, cell_height - 50
    )
    write_rgba_png(output_path, width, height, bytes(pixels))


def _render_and_validate_neutral(
    rig: dict,
    textures: dict[str, object],
    library: dict,
    output_path: Path,
) -> dict:
    pose = sample_animation(library["animations"]["idle"], 0, 4)
    pose["__attachments__"] = {"visible": []}
    bounds = pose_bounds(rig, pose, textures)
    canvas = rig.get("canvas", {})
    floor_offset = int(canvas.get("floor_offset_from_center", 239))
    width, height, origin_x, origin_y = choose_canvas(
        [bounds],
        margin=int(canvas.get("margin", 20)),
        minimum=int(canvas.get("minimum", 512)),
        step=int(canvas.get("step", canvas.get("dimension_step", 64))),
        floor_offset_from_center=floor_offset,
        neutral_floor=bounds[3],
    )
    pixels, parts_audit = render_pose(rig, pose, textures, width, height, origin_x, origin_y)
    write_rgba_png(output_path, width, height, pixels)
    image = read_png(output_path)
    if image.alpha_bounds is None:
        raise ValueError("production neutral assembly rendered empty")
    clearance = frame_clearance(image)
    if min(clearance.values()) <= 0:
        raise ValueError(f"production neutral assembly clips the canvas: {clearance}")

    target_height = int(rig.get("neutral_target_height", rig["target_neutral_height"]))
    tolerance = max(8, round(target_height * 0.03))
    if abs(image.visible_height - target_height) > tolerance:
        raise ValueError(
            f"production neutral height {image.visible_height}px is outside "
            f"{target_height}px +/- {tolerance}px"
        )
    target_floor = height // 2 + floor_offset
    if abs(image.alpha_bounds[3] - target_floor) > 3:
        raise ValueError(
            f"production neutral shoes do not meet the baseline: "
            f"y={image.alpha_bounds[3]}, target={target_floor}"
        )

    parts = {part["name"]: part for part in rig["parts"]}
    body_scale = float(rig["body_scale"])
    head = textures[parts["head"]["texture"]]
    torso = textures[parts["torso"]["texture"]]
    head_scale = parts["head"].get("scale", [1.0, 1.0])
    torso_scale = parts["torso"].get("scale", [1.0, 1.0])
    head_height = head.visible_height * body_scale * float(head_scale[1])
    torso_height = torso.visible_height * body_scale * float(torso_scale[1])
    if not 0.35 <= head_height / torso_height <= 0.85:
        raise ValueError("production neutral head-to-torso proportion is outside the acceptance range")
    for hand_name in ("front_hand", "back_hand"):
        hand = textures[parts[hand_name]["texture"]]
        hand_scale = parts[hand_name].get("scale", [1.0, 1.0])
        hand_size = max(hand.visible_width, hand.visible_height) * body_scale * max(map(float, hand_scale))
        if hand_size > max(head.visible_width, head.visible_height) * body_scale * 0.75:
            raise ValueError(f"production neutral {hand_name} is oversized relative to the head")

    bones = bone_world_transforms(rig, pose)
    for side in ("front", "back"):
        hand_y = bones[f"{side}_hand"].ty
        hip_y = bones[f"{side}_thigh"].ty
        knee_y = bones[f"{side}_shin"].ty
        foot_y = bones[f"{side}_foot"].ty
        if not hip_y - target_height * 0.08 <= hand_y <= knee_y + target_height * 0.12:
            raise ValueError(f"production neutral {side} arm does not reach the upper-thigh region")
        if foot_y - hip_y < target_height * 0.35:
            raise ValueError(f"production neutral {side} leg is too short")

    return {
        "file": _display_path(output_path),
        "canvas": [width, height],
        "apparent_height": image.visible_height,
        "target_height": target_height,
        "height_tolerance": tolerance,
        "baseline_y": image.alpha_bounds[3],
        "clearance": clearance,
        "parts": parts_audit,
        "manual_visual_review": [
            "head and hair are not clipped",
            "torso and pelvis seam is acceptable",
            "shoulder, elbow, wrist, hip, knee, and ankle joins have no major gaps",
            "business-suit silhouette and facial identity match the appearance contract",
        ],
    }


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


def render_character(
    character_id: str,
    output_root: Path | None = None,
    rig_path: Path | None = None,
) -> dict:
    rig_path, alternate_rig = resolve_rig_path(character_id, rig_path)
    rig_root = rig_path.parent
    library_path = PROJECT_ROOT / "data" / "character_rig_animations.json"
    if not rig_path.is_file():
        if alternate_rig:
            missing = missing_production_package_files(rig_path)
            if missing:
                raise ValueError(
                    "production rig package is incomplete; missing:\n  "
                    + "\n  ".join(missing)
                )
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
    if alternate_rig:
        validate_production_rig_contract(rig, character_id)
    if not alternate_rig:
        materialize_procedural_parts(rig, rig_root)
    textures = validate_rig_textures(rig, rig_root, production=alternate_rig)

    output_root = output_root or PROJECT_ROOT / "artifacts" / "character_rig" / character_id
    output_root.mkdir(parents=True, exist_ok=True)
    frame_root = output_root / "production_preview" if alternate_rig else output_root
    neutral_report: dict | None = None
    if alternate_rig:
        neutral_path = output_root / "production_neutral.png"
        neutral_report = _render_and_validate_neutral(rig, textures, library, neutral_path)
        _parts_contact_sheet(
            output_root / "production_parts_contact_sheet.png",
            rig,
            textures,
            neutral_path,
        )

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

    rendered: dict[str, list[Path]] = {}
    frame_audit: dict[str, list[dict]] = {}
    animation_metadata: dict[str, dict] = {}

    for animation in ANIMATIONS:
        animation_dir = frame_root / animation
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
                "clearance": frame_clearance(rendered_image),
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

    props_dir = frame_root / "props"
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
            "export_texture": _display_path(destination),
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
    crop_clearance = {
        animation: {
            edge: min(frame["clearance"][edge] for frame in frames)
            for edge in ("top", "bottom", "left", "right")
        }
        for animation, frames in frame_audit.items()
    }
    report = {
        "schema_version": 2,
        "character_id": character_id,
        "rig": _display_path(rig_path),
        "animation_library": _display_path(library_path),
        "neutral_target_height": int(rig.get("neutral_target_height", rig["target_neutral_height"])),
        "rendered_idle_median_height": float(median(idle_heights)),
        "body_scale": float(rig["body_scale"]),
        "runtime_pixel_scale": RUNTIME_PIXEL_SCALE,
        "alternate_rig": alternate_rig,
        "frame_count_total": sum(frame_counts.values()),
        "frame_counts": frame_counts,
        "animations": animation_metadata,
        "attachment_slots": copy.deepcopy(rig.get("attachment_slots", {})),
        "props": prop_metadata,
        "body_calibration_excludes_props": True,
        "anatomy_measurements": anatomy,
        "crop_clearance": crop_clearance,
        "neutral_validation": neutral_report,
        "frames": frame_audit,
    }
    prefix = "production_" if alternate_rig else ""
    contact_sheet_path = output_root / (
        "production_full_contact_sheet.png"
        if alternate_rig else f"{character_id}_full_contact_sheet.png"
    )
    _contact_sheet(contact_sheet_path, rendered, animation_metadata)
    anatomy_report = (
        {
            "idle_apparent_height": report["rendered_idle_median_height"],
            "body_scale": report["body_scale"],
            "runtime_pixel_scale": RUNTIME_PIXEL_SCALE,
            "measurements": anatomy,
            "crop_clearance": crop_clearance,
        }
        if alternate_rig else anatomy
    )
    (output_root / f"{prefix}anatomy_report.json").write_text(
        json.dumps(anatomy_report, indent=2) + "\n", encoding="utf-8"
    )
    (output_root / f"{prefix}render_manifest.json").write_text(
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
    frame_root = root / "production_preview" if report.get("alternate_rig") else root
    for animation in ANIMATIONS:
        metadata = report["animations"][animation]
        if abs(float(metadata["canvas_to_runtime_scale"]) - RUNTIME_PIXEL_SCALE) > 1e-9:
            raise ValueError(f"{animation}: inconsistent runtime pixel scale")
        if metadata["size_limit"] != recommended_size_limit(*metadata["canvas"]):
            raise ValueError(f"{animation}: incorrect size_limit")
        animation_dir = frame_root / animation
        paths = sorted(animation_dir.glob(f"{animation}_*.png"))
        if len(paths) != expected[animation]:
            raise ValueError(f"{animation}: expected {expected[animation]} files, found {len(paths)}")
        for path in paths:
            image = read_png(path)
            if image.color_type != 6 or image.alpha_bounds is None:
                raise ValueError(f"{path}: output must be non-empty RGBA")
            clearance = frame_clearance(image)
            if min(clearance.values()) <= 0:
                raise ValueError(f"{path}: visible pixels touch the canvas edge: {clearance}")
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
        if report.get("alternate_rig"):
            clearance = report["crop_clearance"][animation]
            print(
                " " * 16
                + "clearance "
                + " ".join(f"{edge}={clearance[edge]}" for edge in ("top", "bottom", "left", "right"))
            )
    print(f"TOTAL: {report['frame_count_total']} frames")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("character_id")
    parser.add_argument("--production", action="store_true", help="stage and promote production sprites")
    parser.add_argument("--dry-run", action="store_true", help="validate a temporary render without writing outputs")
    parser.add_argument("--rig", type=Path, help="use an alternate character_rig.json for preview acceptance")
    args = parser.parse_args()

    try:
        if args.rig is not None and args.production:
            raise ValueError("--rig acceptance previews cannot be combined with --production")
        if args.dry_run or args.production:
            with tempfile.TemporaryDirectory(prefix=f"{args.character_id}_rig_stage_") as stage_name:
                stage = Path(stage_name)
                report = render_character(args.character_id, stage, args.rig)
                validate_complete_render(report, stage)
                if args.production and not args.dry_run:
                    promote_production(args.character_id, stage, report)
                    print_report(report, "PRODUCTION PROMOTED")
                else:
                    print_report(report, "PRODUCTION DRY RUN" if args.production else "DRY RUN")
                    print("NO FILES PROMOTED")
        else:
            output = PROJECT_ROOT / "artifacts" / "character_rig" / args.character_id
            report = render_character(args.character_id, output, args.rig)
            validate_complete_render(report, output)
            print_report(report, "PREVIEW")
            print(f"OUTPUT: {_display_path(output)}")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
