#!/usr/bin/env python3
"""Dependency-free deterministic cutout-rig renderer used by offline art tools."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from character_art_pipeline import PngImage, read_png, write_rgba_png


REQUIRED_BONES = (
    "root", "pelvis", "torso", "head",
    "front_upper_arm", "front_forearm", "front_hand",
    "back_upper_arm", "back_forearm", "back_hand",
    "front_thigh", "front_shin", "front_foot",
    "back_thigh", "back_shin", "back_foot",
)
REQUIRED_BODY_PARTS = tuple(name for name in REQUIRED_BONES if name != "root")


@dataclass(frozen=True)
class Transform:
    a: float = 1.0
    b: float = 0.0
    c: float = 0.0
    d: float = 1.0
    tx: float = 0.0
    ty: float = 0.0

    def compose(self, child: "Transform") -> "Transform":
        return Transform(
            self.a * child.a + self.c * child.b,
            self.b * child.a + self.d * child.b,
            self.a * child.c + self.c * child.d,
            self.b * child.c + self.d * child.d,
            self.a * child.tx + self.c * child.ty + self.tx,
            self.b * child.tx + self.d * child.ty + self.ty,
        )

    def point(self, x: float, y: float) -> tuple[float, float]:
        return self.a * x + self.c * y + self.tx, self.b * x + self.d * y + self.ty

    def inverse(self) -> "Transform":
        determinant = self.a * self.d - self.b * self.c
        if abs(determinant) < 1e-9:
            raise ValueError("non-invertible rig transform")
        a, b = self.d / determinant, -self.b / determinant
        c, d = -self.c / determinant, self.a / determinant
        return Transform(a, b, c, d, -(a * self.tx + c * self.ty), -(b * self.tx + d * self.ty))


def translation(x: float, y: float) -> Transform:
    return Transform(tx=x, ty=y)


def rotation(degrees: float) -> Transform:
    radians = math.radians(degrees)
    cosine, sine = math.cos(radians), math.sin(radians)
    return Transform(cosine, sine, -sine, cosine)


def uniform_scale(value: float) -> Transform:
    return Transform(value, 0.0, 0.0, value)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: root must be a JSON object")
    return data


def validate_rig(rig: dict) -> None:
    if float(rig.get("body_scale", 0.0)) <= 0.0:
        raise ValueError("body_scale must be one positive character-level value")
    bones = rig.get("bones")
    if not isinstance(bones, dict):
        raise ValueError("bones must be an object")
    missing = [name for name in REQUIRED_BONES if name not in bones]
    if missing:
        raise ValueError("missing required bones: " + ", ".join(missing))
    for name, bone in bones.items():
        if name == "root":
            if bone.get("parent") is not None:
                raise ValueError("root bone must not have a parent")
        elif bone.get("parent") not in bones:
            raise ValueError(f"bone {name}: unknown parent {bone.get('parent')!r}")
        if "scale" in bone and bone["scale"] != [1.0, 1.0]:
            raise ValueError(f"bone {name}: bone scale must remain [1.0, 1.0]")
    parts = rig.get("parts")
    if not isinstance(parts, list) or not parts:
        raise ValueError("parts must be a non-empty array")
    part_names = [part.get("name") for part in parts]
    missing_parts = [name for name in REQUIRED_BODY_PARTS if name not in part_names]
    if missing_parts:
        raise ValueError("missing required body parts: " + ", ".join(missing_parts))
    if len(part_names) != len(set(part_names)):
        raise ValueError("body part names must be unique")
    for part in parts:
        if part.get("parent_bone") not in bones:
            raise ValueError(f"part {part.get('name')}: unknown parent bone")
        scale = part.get("scale", [1.0, 1.0])
        if len(scale) != 2 or float(scale[0]) <= 0.0 or float(scale[1]) <= 0.0:
            raise ValueError(f"part {part.get('name')}: invalid static scale")
        pivot = part.get("pivot")
        if not isinstance(pivot, list) or len(pivot) != 2:
            raise ValueError(f"part {part.get('name')}: pivot must contain x and y")
    slots = rig.get("attachment_slots", {})
    for name, slot in slots.items():
        if slot.get("parent_bone") not in bones:
            raise ValueError(f"attachment slot {name}: unknown parent bone")
    for prop in rig.get("props", []):
        if prop.get("attachment_slot") not in slots:
            raise ValueError(f"prop {prop.get('name')}: unknown attachment slot")


def _significant_alpha_components(image: PngImage, alpha_threshold: int = 32) -> int:
    occupied = {
        (x, y)
        for y in range(image.height)
        for x in range(image.width)
        if image.rgba[(y * image.width + x) * 4 + 3] >= alpha_threshold
    }
    if not occupied:
        return 0
    minimum_size = max(4, round(len(occupied) * 0.002))
    significant = 0
    while occupied:
        start = occupied.pop()
        stack = [start]
        size = 1
        while stack:
            x, y = stack.pop()
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in occupied:
                    occupied.remove(neighbor)
                    stack.append(neighbor)
                    size += 1
        if size >= minimum_size:
            significant += 1
    return significant


def validate_rig_textures(
    rig: dict,
    rig_root: Path,
    production: bool = False,
) -> dict[str, PngImage]:
    """Validate source PNGs and anatomical pivots before any rig rendering."""
    validate_rig(rig)
    root = rig_root.resolve()
    texture_paths = {
        str(item["texture"])
        for item in [*rig["parts"], *rig.get("props", [])]
    }
    textures: dict[str, PngImage] = {}
    missing: list[str] = []
    for relative_path in sorted(texture_paths):
        path = (rig_root / relative_path).resolve()
        if root != path.parent and root not in path.parents:
            raise ValueError(f"texture path escapes rig directory: {relative_path}")
        if not path.is_file():
            missing.append(relative_path)
            continue
        if path.suffix.lower() != ".png":
            raise ValueError(f"{relative_path}: rig textures must be PNG files")
        image = read_png(path)
        if image.color_type != 6:
            raise ValueError(f"{relative_path}: expected RGBA PNG")
        if image.alpha_bounds is None:
            raise ValueError(f"{relative_path}: texture contains no visible component")
        if production and image.transparent_pixels == 0:
            raise ValueError(f"{relative_path}: production texture requires transparent padding")
        components = _significant_alpha_components(image)
        if components != 1:
            raise ValueError(
                f"{relative_path}: expected one intended component, found {components} significant alpha components"
            )
        textures[relative_path] = image
    if missing:
        raise ValueError("missing rig texture files:\n  " + "\n  ".join(missing))

    for item in [*rig["parts"], *rig.get("props", [])]:
        image = textures[str(item["texture"])]
        pivot = item.get("pivot")
        if not isinstance(pivot, list) or len(pivot) != 2:
            raise ValueError(f"{item.get('name', item.get('id'))}: pivot must contain x and y")
        pivot_x, pivot_y = float(pivot[0]), float(pivot[1])
        if not (0.0 <= pivot_x < image.width and 0.0 <= pivot_y < image.height):
            raise ValueError(
                f"{item.get('name', item.get('id'))}: pivot {pivot} is outside "
                f"{image.width}x{image.height} texture bounds"
            )
        nearest_alpha_distance = min(
            math.hypot(x - pivot_x, y - pivot_y)
            for y in range(image.height)
            for x in range(image.width)
            if image.rgba[(y * image.width + x) * 4 + 3] >= 32
        )
        pivot_tolerance = max(12.0, min(image.width, image.height) * 0.20)
        if nearest_alpha_distance > pivot_tolerance:
            raise ValueError(
                f"{item.get('name', item.get('id'))}: pivot is {nearest_alpha_distance:.1f}px "
                f"from visible artwork (maximum {pivot_tolerance:.1f}px)"
            )
    return textures


def resolved_parts(rig: dict, visible_attachments: set[str] | None = None) -> list[dict]:
    """Resolve optional props through named slots without involving body calibration."""
    parts = [dict(part) for part in rig["parts"]]
    for prop in rig.get("props", []):
        prop_id = str(prop.get("id", prop.get("name", "")))
        if visible_attachments is not None and prop_id not in visible_attachments:
            continue
        slot = rig["attachment_slots"][prop["attachment_slot"]]
        slot_position = slot.get("local_position", [0.0, 0.0])
        prop_position = prop.get("local_position", [0.0, 0.0])
        resolved = dict(prop)
        resolved.pop("attachment_slot", None)
        resolved["parent_bone"] = slot["parent_bone"]
        resolved["local_position"] = [
            float(slot_position[0]) + float(prop_position[0]),
            float(slot_position[1]) + float(prop_position[1]),
        ]
        resolved["rotation"] = float(slot.get("rotation", 0.0)) + float(prop.get("rotation", 0.0))
        parts.append(resolved)
    return parts


def validate_animation_library(library: dict, frame_counts: dict[str, int]) -> None:
    animations = library.get("animations")
    if not isinstance(animations, dict):
        raise ValueError("animation library must contain an animations object")
    for animation in frame_counts:
        if animation not in animations:
            raise ValueError(f"shared animation is missing: {animation}")
        if frame_counts.get(animation, 0) <= 0:
            raise ValueError(f"frame count is missing: {animation}")
        keyframes = animations[animation].get("keyframes")
        if not isinstance(keyframes, list) or len(keyframes) < 2:
            raise ValueError(f"animation {animation}: at least two keyframes are required")
        previous_time = -1.0
        for keyframe in keyframes:
            current_time = float(keyframe.get("time", -1.0))
            if current_time < previous_time or not 0.0 <= current_time <= 1.0:
                raise ValueError(f"animation {animation}: keyframe times must be ordered in 0..1")
            previous_time = current_time
            for bone_name, values in keyframe.get("bones", {}).items():
                if "scale" in values:
                    raise ValueError(f"animation {animation}/{bone_name}: animated bone scale is forbidden")


def _lerp(first: float, second: float, weight: float) -> float:
    return first + (second - first) * weight


def sample_animation(animation: dict, frame_index: int, frame_count: int) -> dict[str, dict]:
    time = 0.0 if frame_count == 1 else frame_index / (frame_count - 1)
    keyframes = animation["keyframes"]
    left, right = keyframes[0], keyframes[-1]
    for candidate_left, candidate_right in zip(keyframes, keyframes[1:]):
        if float(candidate_left["time"]) <= time <= float(candidate_right["time"]):
            left, right = candidate_left, candidate_right
            break
    span = float(right["time"]) - float(left["time"])
    weight = 0.0 if span <= 0.0 else (time - float(left["time"])) / span
    result: dict[str, dict] = {}
    bone_names = set(left.get("bones", {})) | set(right.get("bones", {}))
    for bone_name in bone_names:
        first = left.get("bones", {}).get(bone_name, {})
        second = right.get("bones", {}).get(bone_name, {})
        first_position = first.get("position", [0.0, 0.0])
        second_position = second.get("position", [0.0, 0.0])
        result[bone_name] = {
            "position": [
                _lerp(float(first_position[0]), float(second_position[0]), weight),
                _lerp(float(first_position[1]), float(second_position[1]), weight),
            ],
            "rotation": _lerp(float(first.get("rotation", 0.0)), float(second.get("rotation", 0.0)), weight),
        }
    visible_frames = animation.get("attachment_visibility", {})
    result["__attachments__"] = {
        "visible": [
            prop_id
            for prop_id, frames in visible_frames.items()
            if frame_index + 1 in [int(frame) for frame in frames]
        ]
    }
    return result


def bone_world_transforms(rig: dict, pose: dict[str, dict]) -> dict[str, Transform]:
    bones = rig["bones"]
    body_scale = float(rig["body_scale"])
    calculated: dict[str, Transform] = {}

    def calculate(name: str) -> Transform:
        if name in calculated:
            return calculated[name]
        bone = bones[name]
        base_position = bone.get("position", [0.0, 0.0])
        override = pose.get(name, {})
        offset = override.get("position", [0.0, 0.0])
        local = translation(
            float(base_position[0]) + float(offset[0]),
            float(base_position[1]) + float(offset[1]),
        ).compose(rotation(float(bone.get("rotation", 0.0)) + float(override.get("rotation", 0.0))))
        parent = bone.get("parent")
        world = local if parent is None else calculate(parent).compose(local)
        calculated[name] = uniform_scale(body_scale).compose(world) if parent is None else world
        return calculated[name]

    for bone_name in bones:
        calculate(bone_name)
    return calculated


def part_transform(part: dict, bone_transforms: dict[str, Transform]) -> Transform:
    position = part.get("local_position", [0.0, 0.0])
    scale = part.get("scale", [1.0, 1.0])
    pivot = part.get("pivot", [0.0, 0.0])
    static = translation(float(position[0]), float(position[1])).compose(
        rotation(float(part.get("rotation", 0.0)))
    ).compose(Transform(float(scale[0]), 0.0, 0.0, float(scale[1]), 0.0, 0.0)).compose(
        translation(-float(pivot[0]), -float(pivot[1]))
    )
    return bone_transforms[part["parent_bone"]].compose(static)


def transformed_bounds(transform: Transform, width: int, height: int) -> tuple[float, float, float, float]:
    corners = (
        transform.point(0.0, 0.0), transform.point(float(width), 0.0),
        transform.point(0.0, float(height)), transform.point(float(width), float(height)),
    )
    return (
        min(point[0] for point in corners), min(point[1] for point in corners),
        max(point[0] for point in corners), max(point[1] for point in corners),
    )


def pose_bounds(rig: dict, pose: dict[str, dict], textures: dict[str, PngImage]) -> tuple[float, float, float, float]:
    bones = bone_world_transforms(rig, pose)
    bounds = []
    visible = set(pose.get("__attachments__", {}).get("visible", []))
    for part in resolved_parts(rig, visible):
        image = textures[part["texture"]]
        bounds.append(transformed_bounds(part_transform(part, bones), image.width, image.height))
    return (
        min(item[0] for item in bounds), min(item[1] for item in bounds),
        max(item[2] for item in bounds), max(item[3] for item in bounds),
    )


def choose_canvas(
    all_bounds: Iterable[tuple[float, float, float, float]],
    margin: int,
    step: int,
    minimum: int = 512,
    floor_offset_from_center: float = 239.0,
    neutral_floor: float | None = None,
) -> tuple[int, int, float, float]:
    bounds = list(all_bounds)
    horizontal_radius = max(max(abs(item[0]), abs(item[2])) for item in bounds)
    min_y = min(item[1] for item in bounds)
    max_y = max(item[3] for item in bounds)
    width = max(minimum, math.ceil((horizontal_radius * 2.0 + margin * 2) / step) * step)
    if neutral_floor is None:
        height = max(minimum, math.ceil((max_y - min_y + margin * 2) / step) * step)
        origin_y = float(margin - min_y)
    else:
        top_requirement = 2.0 * (margin - floor_offset_from_center + neutral_floor - min_y)
        bottom_requirement = 2.0 * (margin + floor_offset_from_center - neutral_floor + max_y)
        height = max(minimum, math.ceil(max(top_requirement, bottom_requirement) / step) * step)
        origin_y = height / 2.0 + floor_offset_from_center - neutral_floor
    return int(width), int(height), width / 2.0, origin_y


def _blend(canvas: bytearray, index: int, red: int, green: int, blue: int, alpha: int) -> None:
    if alpha <= 0:
        return
    destination_alpha = canvas[index + 3]
    source_fraction = alpha / 255.0
    destination_fraction = destination_alpha / 255.0
    output_alpha = source_fraction + destination_fraction * (1.0 - source_fraction)
    if output_alpha <= 0.0:
        return
    for channel, value in enumerate((red, green, blue)):
        destination = canvas[index + channel] / 255.0
        output = (value / 255.0 * source_fraction + destination * destination_fraction * (1.0 - source_fraction)) / output_alpha
        canvas[index + channel] = max(0, min(255, round(output * 255.0)))
    canvas[index + 3] = max(0, min(255, round(output_alpha * 255.0)))


def composite_part(canvas: bytearray, canvas_width: int, canvas_height: int, image: PngImage, transform: Transform) -> None:
    min_x, min_y, max_x, max_y = transformed_bounds(transform, image.width, image.height)
    start_x, end_x = max(0, math.floor(min_x)), min(canvas_width - 1, math.ceil(max_x))
    start_y, end_y = max(0, math.floor(min_y)), min(canvas_height - 1, math.ceil(max_y))
    inverse = transform.inverse()
    for target_y in range(start_y, end_y + 1):
        for target_x in range(start_x, end_x + 1):
            source_x, source_y = inverse.point(target_x + 0.5, target_y + 0.5)
            pixel_x, pixel_y = math.floor(source_x), math.floor(source_y)
            if not (0 <= pixel_x < image.width and 0 <= pixel_y < image.height):
                continue
            source_index = (pixel_y * image.width + pixel_x) * 4
            target_index = (target_y * canvas_width + target_x) * 4
            _blend(canvas, target_index, *image.rgba[source_index : source_index + 4])


def render_pose(
    rig: dict,
    pose: dict[str, dict],
    textures: dict[str, PngImage],
    canvas_width: int,
    canvas_height: int,
    origin_x: float,
    origin_y: float,
) -> tuple[bytearray, dict[str, dict]]:
    canvas = bytearray(canvas_width * canvas_height * 4)
    bones = bone_world_transforms(rig, pose)
    canvas_transform = translation(origin_x, origin_y)
    audit: dict[str, dict] = {}
    visible = set(pose.get("__attachments__", {}).get("visible", []))
    for part in sorted(resolved_parts(rig, visible), key=lambda item: (int(item["z_order"]), item["name"])):
        image = textures[part["texture"]]
        transform = canvas_transform.compose(part_transform(part, bones))
        composite_part(canvas, canvas_width, canvas_height, image, transform)
        audit[part["name"]] = {
            "kind": "prop" if "id" in part else "body",
            "texture_dimensions": [image.width, image.height],
            "transform_scale": [
                round(math.hypot(transform.a, transform.b), 6),
                round(math.hypot(transform.c, transform.d), 6),
            ],
        }
    return canvas, audit


def _inside_ellipse(x: int, y: int, width: int, height: int, inset: int = 1) -> bool:
    radius_x, radius_y = max(1.0, (width - inset * 2) / 2.0), max(1.0, (height - inset * 2) / 2.0)
    return ((x - width / 2.0) / radius_x) ** 2 + ((y - height / 2.0) / radius_y) ** 2 <= 1.0


def materialize_procedural_parts(rig: dict, rig_root: Path) -> list[Path]:
    """Create only explicitly declared POC textures; normal character rigs supply PNGs."""
    created: list[Path] = []
    for relative_path, spec in rig.get("procedural_parts", {}).items():
        path = rig_root / relative_path
        if path.is_file():
            continue
        width, height = map(int, spec["size"])
        fill = tuple(map(int, spec["fill"]))
        outline = tuple(map(int, spec.get("outline", [20, 22, 30, 255])))
        shape = spec.get("shape", "ellipse")
        pixels = bytearray(width * height * 4)
        for y in range(height):
            for x in range(width):
                if shape == "ellipse":
                    inside = _inside_ellipse(x, y, width, height, 1)
                    inner = _inside_ellipse(x, y, width, height, int(spec.get("outline_width", 3)))
                elif shape == "tapered":
                    taper = int((1.0 - y / max(1, height - 1)) * float(spec.get("top_taper", 12)))
                    inside = taper <= x < width - taper
                    inner = taper + 3 <= x < width - taper - 3 and 3 <= y < height - 3
                elif shape == "rectangle":
                    inside = True
                    inner = 4 <= x < width - 4 and 4 <= y < height - 4
                else:
                    radius = int(spec.get("radius", min(width, height) // 3))
                    inside = (radius <= x < width - radius) or _inside_ellipse(x, y, radius * 2, height)
                    inside = inside or _inside_ellipse(x - (width - radius * 2), y, radius * 2, height)
                    inner = inside and 3 <= x < width - 3 and 3 <= y < height - 3
                if not inside:
                    continue
                color = fill if inner else outline
                index = (y * width + x) * 4
                pixels[index : index + 4] = bytes(color)
        write_rgba_png(path, width, height, pixels)
        created.append(path)
    return created
