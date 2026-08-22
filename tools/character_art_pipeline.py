#!/usr/bin/env python3
"""Validate and review standardized Samurai Cop production sprite artwork.

The implementation intentionally uses only Python's standard library so it works
on a clean Ubuntu development machine. It understands non-interlaced 8-bit RGBA
PNG files, which is the project's required production format.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import struct
import sys
import tempfile
import zlib
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "data" / "character_art_manifest.json"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


@dataclass
class PngImage:
    width: int
    height: int
    color_type: int
    rgba: bytes
    alpha_bounds: tuple[int, int, int, int] | None
    transparent_pixels: int
    semitransparent_pixels: int
    edge_alpha_pixels: int

    @property
    def visible_width(self) -> int:
        return 0 if self.alpha_bounds is None else self.alpha_bounds[2] - self.alpha_bounds[0] + 1

    @property
    def visible_height(self) -> int:
        return 0 if self.alpha_bounds is None else self.alpha_bounds[3] - self.alpha_bounds[1] + 1

    @property
    def scale_metric(self) -> float:
        return math.sqrt(self.visible_width * self.visible_height)

    @property
    def long_axis(self) -> int:
        return max(self.visible_width, self.visible_height)

    @property
    def visible_alpha_pixels(self) -> int:
        return self.width * self.height - self.transparent_pixels


@dataclass(frozen=True)
class ScaleAssessment:
    status: str
    metric_name: str
    measured: float
    target: float
    ratio: float


@dataclass(frozen=True)
class BaselineAssessment:
    status: str
    measured: float
    target: float
    delta: float


@dataclass(frozen=True)
class NeutralAnchorAssessment:
    status: str
    multiplier: float
    height_ratio: float
    width_ratio: float
    alpha_area_ratio: float


class Report:
    def __init__(self) -> None:
        self.passes = 0
        self.warnings = 0
        self.errors = 0

    def pass_file(self, subject: str) -> None:
        self.passes += 1
        print(f"PASS {subject}")

    def warning(self, subject: str, message: str) -> None:
        self.warnings += 1
        print(f"WARNING {subject}:\n  {message}")

    def error(self, subject: str, message: str) -> None:
        self.errors += 1
        print(f"ERROR {subject}:\n  {message}")

    def summary(self, label: str = "TOTAL") -> None:
        state = "FAIL" if self.errors else ("WARNING" if self.warnings else "PASS")
        print(f"\n{state} {label}: {self.passes} passed, {self.warnings} warning(s), {self.errors} error(s)")


def load_manifest() -> dict:
    with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_manifest(manifest: dict) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=".character_art_manifest.", suffix=".json", dir=MANIFEST_PATH.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, MANIFEST_PATH)
    finally:
        temporary_path.unlink(missing_ok=True)


def animation_config(manifest: dict, character_id: str, animation: str) -> dict:
    result = dict(manifest["animations"][animation])
    result.update(manifest["characters"][character_id].get("animations", {}).get(animation, {}))
    return result


def expected_frame_paths(manifest: dict, character_id: str, animation: str) -> list[Path]:
    frame_count = int(animation_config(manifest, character_id, animation)["frame_count"])
    folder = PROJECT_ROOT / "assets" / "characters" / character_id / "sprites" / animation
    return [folder / f"{animation}_{number:03d}.png" for number in range(1, frame_count + 1)]


def generated_batch_root(manifest: dict, character_id: str) -> Path:
    relative_root = manifest["batch_contract"]["source_root"].format(character_id=character_id)
    return PROJECT_ROOT / relative_root


def initialize_character_directories(manifest: dict, character_id: str) -> tuple[int, int]:
    """Create the manifest-defined production tree without touching existing files."""
    character_root = PROJECT_ROOT / "assets" / "characters" / character_id
    expected_directories = [character_root, character_root / "design", character_root / "sprites", generated_batch_root(manifest, character_id)]
    expected_directories.extend(character_root / "sprites" / animation for animation in manifest["animation_order"])
    created = existing = 0
    for directory in expected_directories:
        if directory.is_dir():
            existing += 1
            continue
        directory.mkdir(parents=True, exist_ok=True)
        created += 1
        print(f"CREATE {directory.relative_to(PROJECT_ROOT)}/")
    print(f"INIT {character_id}: {created} created, {existing} already present")
    return created, existing


def paeth_predictor(left: int, above: int, upper_left: int) -> int:
    prediction = left + above - upper_left
    left_distance = abs(prediction - left)
    above_distance = abs(prediction - above)
    upper_left_distance = abs(prediction - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    return above if above_distance <= upper_left_distance else upper_left


_PNG_CACHE: dict[Path, PngImage] = {}


def read_png(path: Path) -> PngImage:
    cache_key = path.resolve()
    cached = _PNG_CACHE.get(cache_key)
    if cached is not None:
        return cached
    image = _read_png_uncached(path)
    _PNG_CACHE[cache_key] = image
    return image


def _read_png_uncached(path: Path) -> PngImage:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG file")
    position = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = interlace = -1
    compressed = bytearray()
    while position + 12 <= len(data):
        length = struct.unpack_from(">I", data, position)[0]
        chunk_type = data[position + 4 : position + 8]
        chunk_data = data[position + 8 : position + 8 + length]
        expected_crc = struct.unpack_from(">I", data, position + 8 + length)[0]
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError(f"invalid {chunk_type.decode('ascii', 'replace')} CRC")
        position += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _compression, _filter, interlace = struct.unpack(">IIBBBBB", chunk_data)
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break
    if width <= 0 or height <= 0:
        raise ValueError("missing IHDR")
    if bit_depth != 8 or interlace != 0:
        raise ValueError("only non-interlaced 8-bit PNG files are supported")
    channels_by_type = {0: 1, 2: 3, 4: 2, 6: 4}
    if color_type not in channels_by_type:
        raise ValueError(f"unsupported PNG color type {color_type}")
    channels = channels_by_type[color_type]
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))
    if len(raw) != height * (stride + 1):
        raise ValueError("unexpected decompressed data size")

    rows: list[bytearray] = []
    cursor = 0
    previous = bytearray(stride)
    for _row_number in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor : cursor + stride]
        cursor += stride
        decoded = bytearray(stride)
        for index, value in enumerate(encoded):
            left = decoded[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                decoded[index] = value
            elif filter_type == 1:
                decoded[index] = (value + left) & 0xFF
            elif filter_type == 2:
                decoded[index] = (value + above) & 0xFF
            elif filter_type == 3:
                decoded[index] = (value + ((left + above) // 2)) & 0xFF
            elif filter_type == 4:
                decoded[index] = (value + paeth_predictor(left, above, upper_left)) & 0xFF
            else:
                raise ValueError(f"unknown PNG filter {filter_type}")
        rows.append(decoded)
        previous = decoded

    rgba = bytearray(width * height * 4)
    min_x, min_y, max_x, max_y = width, height, -1, -1
    transparent = semitransparent = edge_alpha = 0
    for y, row in enumerate(rows):
        for x in range(width):
            source = x * channels
            if color_type == 6:
                red, green, blue, alpha = row[source : source + 4]
            elif color_type == 4:
                red = green = blue = row[source]
                alpha = row[source + 1]
            elif color_type == 2:
                red, green, blue = row[source : source + 3]
                alpha = 255
            else:
                red = green = blue = row[source]
                alpha = 255
            target = (y * width + x) * 4
            rgba[target : target + 4] = bytes((red, green, blue, alpha))
            if alpha == 0:
                transparent += 1
                continue
            min_x, min_y = min(min_x, x), min(min_y, y)
            max_x, max_y = max(max_x, x), max(max_y, y)
            if alpha < 255:
                semitransparent += 1
            if x < 2 or x >= width - 2 or y < 2 or y >= height - 2:
                edge_alpha += 1
    bounds = None if max_x < 0 else (min_x, min_y, max_x, max_y)
    return PngImage(width, height, color_type, bytes(rgba), bounds, transparent, semitransparent, edge_alpha)


def reference_statistics(manifest: dict, animations: Iterable[str]) -> dict[str, dict[str, float]]:
    reference_id = manifest["reference_character"]
    result: dict[str, dict[str, float]] = {}
    for animation in animations:
        images: list[PngImage] = []
        for path in expected_frame_paths(manifest, reference_id, animation):
            if not path.is_file():
                continue
            try:
                images.append(read_png(path))
            except ValueError:
                pass
        images = [image for image in images if image.alpha_bounds is not None]
        if images:
            result[animation] = {
                "width": median(image.visible_width for image in images),
                "height": median(image.visible_height for image in images),
                "long_axis": median(image.long_axis for image in images),
                "baseline": median(image.alpha_bounds[3] for image in images if image.alpha_bounds),
            }
    return result


def scale_profile(manifest: dict, character_id: str) -> dict | None:
    profile = manifest["characters"][character_id].get("scale_profile")
    return profile if isinstance(profile, dict) else None


def classify_ratio(manifest: dict, ratio: float) -> str:
    calibration = manifest["scale_calibration"]
    deviation = abs(ratio - 1.0)
    if deviation <= float(calibration["pass_tolerance"]):
        return "PASS"
    if deviation <= float(calibration["warning_tolerance"]):
        return "WARNING"
    return "ERROR"


def assess_animation_scale(
    manifest: dict,
    character_id: str,
    animation: str,
    images: list[PngImage],
    references: dict[str, dict[str, float]],
) -> ScaleAssessment | None:
    profile = scale_profile(manifest, character_id)
    reference = references.get(animation)
    if not profile or not images or not reference:
        return None
    height_ratio = float(profile["height_ratio_to_reference"])
    if animation == "ko":
        metric_name = "long axis"
        measured = float(median(image.long_axis for image in images))
        target = float(reference["long_axis"]) * height_ratio
    else:
        metric_name = "height"
        measured = float(median(image.visible_height for image in images))
        target = float(reference["height"]) * height_ratio
    ratio = measured / target if target > 0.0 else 0.0
    return ScaleAssessment(classify_ratio(manifest, ratio), metric_name, measured, target, ratio)


def assess_animation_baseline(
    manifest: dict,
    character_id: str,
    animation: str,
    images: list[PngImage],
) -> BaselineAssessment | None:
    profile = scale_profile(manifest, character_id)
    if not profile or not images or not bool(animation_config(manifest, character_id, animation)["grounded"]):
        return None
    measured = float(median(image.alpha_bounds[3] for image in images if image.alpha_bounds))
    target = float(profile["target_baseline_y"])
    delta = measured - target
    calibration = manifest["scale_calibration"]
    if abs(delta) <= float(calibration["baseline_pass_pixels"]):
        status = "PASS"
    elif abs(delta) <= float(calibration["baseline_warning_pixels"]):
        status = "WARNING"
    else:
        status = "ERROR"
    return BaselineAssessment(status, measured, target, delta)


def calibrate_character_scale(manifest: dict, character_id: str) -> bool:
    reference_id = manifest["reference_character"]
    existing_profile = scale_profile(manifest, character_id) or {}
    reference_animation = str(existing_profile.get("reference_animation", "idle"))
    character_images: list[PngImage] = []
    reference_images: list[PngImage] = []
    try:
        for path in expected_frame_paths(manifest, character_id, reference_animation):
            if path.is_file():
                character_images.append(read_png(path))
        for path in expected_frame_paths(manifest, reference_id, reference_animation):
            if path.is_file():
                reference_images.append(read_png(path))
    except (OSError, ValueError, zlib.error) as error:
        print(f"CALIBRATION ERROR {character_id}: {error}", file=sys.stderr)
        return False
    expected_count = int(animation_config(manifest, character_id, reference_animation)["frame_count"])
    if len(character_images) != expected_count or not character_images or not reference_images:
        print(f"CALIBRATION ERROR {character_id}: complete approved {reference_animation} art is required", file=sys.stderr)
        return False
    character_height = float(median(image.visible_height for image in character_images))
    character_width = float(median(image.visible_width for image in character_images))
    character_alpha_area = float(median(image.visible_alpha_pixels for image in character_images))
    reference_height = float(median(image.visible_height for image in reference_images))
    ratio = character_height / reference_height
    baseline = int(round(median(image.alpha_bounds[3] for image in character_images if image.alpha_bounds)))
    manifest["characters"][character_id]["scale_profile"] = {
        "reference_animation": reference_animation,
        "height_ratio_to_reference": round(ratio, 6),
        "target_baseline_y": baseline,
        "approved_neutral_metrics": {
            "median_visible_height": round(character_height, 6),
            "median_visible_width": round(character_width, 6),
            "median_alpha_area": round(character_alpha_area, 6),
        },
    }
    print(
        f"CALIBRATED {character_id}: {reference_animation} median {character_height:.1f}px / "
        f"{reference_id} {reference_height:.1f}px = {ratio:.3%}; baseline y={baseline}"
    )
    return True


def production_batch_for_animation(manifest: dict, character_id: str, animation: str) -> tuple[str, dict] | None:
    for batch_name, batch in manifest["characters"][character_id].get("production_batches", {}).items():
        if animation in batch.get("animations", []):
            return batch_name, batch
    return None


def animation_digest(paths: Iterable[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.name.encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def batch_consistency_error(batch: dict) -> str | None:
    if batch.get("status") not in {"approved", "reference"}:
        return (
            "generation group has no approved neutral-anchor calibration "
            f"(status={batch.get('status', 'missing')})"
        )
    multiplier = float(batch.get("batch_multiplier", 0.0))
    if multiplier <= 0.0:
        return "production batch multiplier is missing or invalid"
    animation_multipliers = batch.get("animation_multipliers", {})
    for animation in batch.get("animations", []):
        if animation not in animation_multipliers:
            return f"normalization multiplier is missing for {animation}"
        if not math.isclose(float(animation_multipliers[animation]), multiplier, rel_tol=0.0, abs_tol=1e-6):
            return (
                f"inconsistent body scale inside production batch: {animation} uses "
                f"{float(animation_multipliers[animation]):.6f}, batch uses {multiplier:.6f}"
            )
    return None


def _metric_status(ratio: float, pass_tolerance: float, warning_tolerance: float) -> str:
    deviation = abs(ratio - 1.0)
    if deviation <= pass_tolerance:
        return "PASS"
    if deviation <= warning_tolerance:
        return "WARNING"
    return "ERROR"


def assess_neutral_anchor(
    manifest: dict,
    anchor: PngImage,
    approved_idle: list[PngImage],
    approved_metrics: dict | None = None,
) -> NeutralAnchorAssessment:
    """Compare neutral anatomy after height calibration, never an action pose."""
    approved_metrics = approved_metrics or {}
    reference_height = float(approved_metrics.get("median_visible_height", median(image.visible_height for image in approved_idle)))
    reference_width = float(approved_metrics.get("median_visible_width", median(image.visible_width for image in approved_idle)))
    reference_area = float(approved_metrics.get("median_alpha_area", median(image.visible_alpha_pixels for image in approved_idle)))
    multiplier = reference_height / float(anchor.visible_height)
    height_ratio = float(anchor.visible_height) / reference_height
    width_ratio = float(anchor.visible_width) * multiplier / reference_width
    alpha_area_ratio = float(anchor.visible_alpha_pixels) * multiplier * multiplier / reference_area
    calibration = manifest["scale_calibration"]
    statuses = (
        _metric_status(
            height_ratio,
            float(calibration["neutral_anchor_height_pass_tolerance"]),
            float(calibration["neutral_anchor_height_warning_tolerance"]),
        ),
        _metric_status(
            width_ratio,
            float(calibration["neutral_anchor_width_pass_tolerance"]),
            float(calibration["neutral_anchor_width_warning_tolerance"]),
        ),
        _metric_status(
            alpha_area_ratio,
            float(calibration["neutral_anchor_area_pass_tolerance"]),
            float(calibration["neutral_anchor_area_warning_tolerance"]),
        ),
    )
    status = "ERROR" if "ERROR" in statuses else ("WARNING" if "WARNING" in statuses else "PASS")
    return NeutralAnchorAssessment(status, multiplier, height_ratio, width_ratio, alpha_area_ratio)


def report_neutral_anchor(batch_name: str, assessment: NeutralAnchorAssessment, report: Report) -> None:
    message = (
        f"height={assessment.height_ratio:.1%}, height-normalized width={assessment.width_ratio:.1%}, "
        f"height-normalized alpha area={assessment.alpha_area_ratio:.1%}, "
        f"multiplier={assessment.multiplier:.6f}"
    )
    if assessment.status == "ERROR":
        report.error(f"{batch_name} neutral anchor", message)
    elif assessment.status == "WARNING":
        report.warning(f"{batch_name} neutral anchor", message)
    else:
        print(f"NEUTRAL ANCHOR PASS {batch_name}: {message}")


def inspect_visual_quality(
    image: PngImage,
    subject: str,
    report: Report,
    animation_median_height: float | None,
    animation_median_bounds_scale: float | None,
    baseline_median: float | None,
    grounded: bool,
    animation: str,
) -> None:
    total = image.width * image.height
    visible = total - image.transparent_pixels
    if image.color_type != 6:
        report.error(subject, "PNG must be saved in true RGBA color mode (PNG color type 6).")
    if image.transparent_pixels == 0:
        report.error(subject, "no transparent pixels found; an opaque background is likely baked in")
    if image.alpha_bounds is None:
        report.error(subject, "frame contains no visible pixels")
        return
    min_x, min_y, max_x, max_y = image.alpha_bounds
    edge_total = image.width * 4 + image.height * 4 - 16
    visible_ratio = visible / total
    edge_ratio = image.edge_alpha_pixels / max(1, edge_total)
    semitransparent_ratio = image.semitransparent_pixels / total
    if visible_ratio > 0.68 or edge_ratio > 0.30 or (visible_ratio > 0.55 and semitransparent_ratio > 0.35):
        report.error(subject, f"background contamination suspected (visible={visible_ratio:.0%}, edge alpha={edge_ratio:.0%})")
    elif visible_ratio > 0.52 or edge_ratio > 0.10:
        report.warning(subject, f"large alpha coverage may be an intentional effect; inspect background (visible={visible_ratio:.0%}, edge alpha={edge_ratio:.0%})")
    if min_x == 0 or min_y == 0 or max_x == image.width - 1 or max_y == image.height - 1:
        report.warning(subject, f"visible artwork touches a canvas edge; alpha bounds={image.alpha_bounds}")
    if animation == "ko":
        if animation_median_bounds_scale and animation_median_bounds_scale > 0:
            ratio = image.scale_metric / animation_median_bounds_scale
            if ratio < 0.55 or ratio > 1.80:
                report.warning(subject, f"KO visible bounds differ substantially from this animation's median ({ratio:.0%})")
    elif animation_median_height and animation_median_height > 0:
        ratio = image.visible_height / animation_median_height
        if ratio < 0.70 or ratio > 1.30:
            report.warning(subject, f"visible height differs substantially from this animation's median ({ratio:.0%})")
    if grounded and baseline_median is not None:
        delta = max_y - baseline_median
        if abs(delta) > 30:
            report.error(subject, f"ground baseline differs from animation median by {delta:+.0f}px")
        elif abs(delta) > 14:
            report.warning(subject, f"ground baseline differs from animation median by {delta:+.0f}px")


def report_batch_scale(
    manifest: dict,
    character_id: str,
    animation: str,
    images: list[PngImage],
    report: Report,
) -> None:
    batch_entry = production_batch_for_animation(manifest, character_id, animation)
    if batch_entry is None:
        if images:
            report.error(animation, "production animation is not assigned to a calibrated batch")
        return
    batch_name, batch = batch_entry
    error = batch_consistency_error(batch)
    if error:
        report.error(f"{animation} batch scale", f"{batch_name}: {error}")
        return
    expected_digest = batch.get("output_digests", {}).get(animation)
    if expected_digest:
        paths = expected_frame_paths(manifest, character_id, animation)
        if animation_digest(path for path in paths if path.is_file()) != expected_digest:
            report.error(f"{animation} batch scale", f"{batch_name}: production files differ from calibrated batch output")
            return
    print(f"BATCH SCALE PASS {animation}: {character_id}/{batch_name} multiplier={float(batch['batch_multiplier']):.6f} SAME SCALE")

    baseline = assess_animation_baseline(manifest, character_id, animation, images)
    if baseline is None:
        return
    baseline_message = f"median y={baseline.measured:.1f}, target y={baseline.target:.1f}, delta={baseline.delta:+.1f}px"
    if baseline.status == "ERROR":
        report.error(f"{animation} baseline", baseline_message)
    elif baseline.status == "WARNING":
        report.warning(f"{animation} baseline", baseline_message)
    else:
        print(f"BASELINE PASS {animation}: {baseline_message}")


def validate_character(
    manifest: dict,
    character_id: str,
    references: dict,
    report: Report,
    animations: list[str],
    partial: bool,
    normalizing: bool = False,
) -> dict[str, list[PngImage]]:
    print(f"\n=== {character_id} ===")
    sprite_root = PROJECT_ROOT / "assets" / "characters" / character_id / "sprites"
    decoded: dict[str, list[PngImage]] = {}
    if not sprite_root.is_dir():
        report.error(character_id, f"expected production sprite directory is missing: {sprite_root.relative_to(PROJECT_ROOT)}")
        return decoded
    hashes: dict[str, list[str]] = {}
    if partial:
        selected = set(animations)
        for animation in manifest["animation_order"]:
            if animation not in selected:
                print(f"NOT CHECKED {animation}")
    for animation in animations:
        paths = expected_frame_paths(manifest, character_id, animation)
        folder = paths[0].parent
        if not folder.is_dir():
            report.error(animation, f"expected folder is missing: {folder.relative_to(PROJECT_ROOT)}")
            continue
        missing = [path.name for path in paths if not path.is_file()]
        existing_pngs = sorted(folder.glob("*.png"))
        expected_names = {path.name for path in paths}
        extras = [path.name for path in existing_pngs if path.name not in expected_names]
        if missing:
            report.error(animation, f"expected {len(paths)} frames, found {len(paths) - len(missing)}; missing: {', '.join(missing)}")
        if extras:
            report.warning(animation, f"unexpected PNG frame(s): {', '.join(extras)}")
        images_by_path: list[tuple[Path, PngImage]] = []
        for path in paths:
            if not path.is_file():
                continue
            before = report.errors + report.warnings
            try:
                image = read_png(path)
            except (OSError, ValueError, zlib.error) as error:
                report.error(path.name, str(error))
                continue
            if (image.width, image.height) != (manifest["canvas"]["width"], manifest["canvas"]["height"]):
                report.error(path.name, f"expected 512x512, found {image.width}x{image.height}")
            images_by_path.append((path, image))
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            hashes.setdefault(digest, []).append(f"{animation}/{path.name}")
            if report.errors + report.warnings == before and image.alpha_bounds is not None:
                pass  # Quality-dependent PASS is printed after median checks below.
        valid_images = [image for _path, image in images_by_path if image.alpha_bounds is not None]
        decoded[animation] = valid_images
        animation_height_median = median(image.visible_height for image in valid_images) if valid_images else None
        animation_bounds_scale_median = median(image.scale_metric for image in valid_images) if valid_images else None
        animation_baseline_median = median(image.alpha_bounds[3] for image in valid_images if image.alpha_bounds) if valid_images else None
        report_batch_scale(manifest, character_id, animation, valid_images, report)
        config = animation_config(manifest, character_id, animation)
        for path, image in images_by_path:
            before = report.errors + report.warnings
            inspect_visual_quality(
                image,
                f"{animation}/{path.name}",
                report,
                animation_height_median,
                animation_bounds_scale_median,
                animation_baseline_median,
                bool(config["grounded"]),
                animation,
            )
            if report.errors + report.warnings == before:
                report.pass_file(f"{animation}/{path.name}")
    for duplicate_paths in hashes.values():
        if len(duplicate_paths) > 1:
            report.warning(character_id, f"exact duplicate-looking files: {', '.join(duplicate_paths)}")
    return decoded


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)


def write_rgba_png(path: Path, width: int, height: int, pixels: bytes | bytearray) -> None:
    scanlines = bytearray()
    stride = width * 4
    for y in range(height):
        scanlines.append(0)
        scanlines.extend(pixels[y * stride : (y + 1) * stride])
    payload = PNG_SIGNATURE
    payload += png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    payload += png_chunk(b"IDAT", zlib.compress(bytes(scanlines), 9))
    payload += png_chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


FONT = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"), "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01111", "10000", "10000", "10000", "10000", "10000", "01111"), "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"), "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01111", "10000", "10000", "10111", "10001", "10001", "01111"), "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"), "J": ("00111", "00010", "00010", "00010", "10010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"), "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"), "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"), "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"), "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"), "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"), "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "11011", "10001"), "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"), "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"), "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"), "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"), "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110"), "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"), "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "_": ("00000", "00000", "00000", "00000", "00000", "00000", "11111"), "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    ":": ("00000", "00100", "00100", "00000", "00100", "00100", "00000"), ".": ("00000", "00000", "00000", "00000", "00000", "00110", "00110"),
    " ": ("00000",) * 7,
}


def fill_rect(canvas: bytearray, width: int, x: int, y: int, rect_width: int, rect_height: int, color: tuple[int, int, int, int]) -> None:
    for row in range(max(0, y), min(y + rect_height, len(canvas) // (width * 4))):
        for column in range(max(0, x), min(x + rect_width, width)):
            index = (row * width + column) * 4
            canvas[index : index + 4] = bytes(color)


def draw_text(canvas: bytearray, width: int, x: int, y: int, text: str, scale: int = 2) -> None:
    cursor = x
    for character in text.upper():
        glyph = FONT.get(character, FONT[" "])
        for row, pattern in enumerate(glyph):
            for column, bit in enumerate(pattern):
                if bit == "1":
                    fill_rect(canvas, width, cursor + column * scale, y + row * scale, scale, scale, (238, 242, 248, 255))
        cursor += 6 * scale


def composite_thumbnail(canvas: bytearray, canvas_width: int, image: PngImage, x: int, y: int, size: int) -> None:
    for row in range(size):
        for column in range(size):
            checker = 70 if ((row // 8) + (column // 8)) % 2 else 92
            target = ((y + row) * canvas_width + x + column) * 4
            canvas[target : target + 4] = bytes((checker, checker, checker, 255))
    scale = min(size / image.width, size / image.height)
    draw_width, draw_height = max(1, int(image.width * scale)), max(1, int(image.height * scale))
    offset_x, offset_y = x + (size - draw_width) // 2, y + (size - draw_height) // 2
    for target_y in range(draw_height):
        source_y = min(image.height - 1, int(target_y / scale))
        for target_x in range(draw_width):
            source_x = min(image.width - 1, int(target_x / scale))
            source = (source_y * image.width + source_x) * 4
            alpha = image.rgba[source + 3]
            if alpha == 0:
                continue
            target = ((offset_y + target_y) * canvas_width + offset_x + target_x) * 4
            inverse = 255 - alpha
            for channel in range(3):
                canvas[target + channel] = (image.rgba[source + channel] * alpha + canvas[target + channel] * inverse) // 255
            canvas[target + 3] = 255


def create_contact_sheet(manifest: dict, character_id: str, animations: list[str]) -> Path | None:
    if not animations:
        return None
    label_width, tile_size, gap, row_height, margin, header = 190, 112, 8, 138, 16, 34
    max_frames = max(int(animation_config(manifest, character_id, name)["frame_count"]) for name in animations)
    width = margin * 2 + label_width + max_frames * (tile_size + gap)
    height = header + margin + len(animations) * row_height
    canvas = bytearray(bytes((25, 29, 36, 255)) * (width * height))
    draw_text(canvas, width, margin, 10, f"{character_id} CHARACTER ART", 2)
    for row_index, animation in enumerate(animations):
        y = header + margin + row_index * row_height
        draw_text(canvas, width, margin, y + 48, animation, 2)
        for frame_index, path in enumerate(expected_frame_paths(manifest, character_id, animation)):
            x = margin + label_width + frame_index * (tile_size + gap)
            if path.is_file():
                try:
                    composite_thumbnail(canvas, width, read_png(path), x, y, tile_size)
                except (ValueError, zlib.error):
                    fill_rect(canvas, width, x, y, tile_size, tile_size, (110, 28, 32, 255))
            else:
                fill_rect(canvas, width, x, y, tile_size, tile_size, (62, 27, 30, 255))
            draw_text(canvas, width, x + 43, y + tile_size + 5, f"{frame_index + 1:02d}", 1)
    output = PROJECT_ROOT / "artifacts" / "character_art" / f"{character_id}_contact_sheet.png"
    write_rgba_png(output, width, height, canvas)
    return output


def _resample_frame(image: PngImage, multiplier: float, grounded: bool, baseline: int) -> bytearray | None:
    min_x, min_y, max_x, max_y = image.alpha_bounds
    source_center_x = (min_x + max_x) / 2.0
    source_anchor_y = max_y if grounded else (min_y + max_y) / 2.0
    target_anchor_y = baseline if grounded else image.height / 2.0
    target_min_x = math.floor((min_x - source_center_x) * multiplier + image.width / 2.0)
    target_max_x = math.ceil((max_x - source_center_x) * multiplier + image.width / 2.0)
    target_min_y = math.floor((min_y - source_anchor_y) * multiplier + target_anchor_y)
    target_max_y = math.ceil((max_y - source_anchor_y) * multiplier + target_anchor_y)
    if target_min_x < 0 or target_min_y < 0 or target_max_x >= image.width or target_max_y >= image.height:
        return None
    output = bytearray(image.width * image.height * 4)
    for target_y in range(target_min_y, target_max_y + 1):
        source_y = round((target_y - target_anchor_y) / multiplier + source_anchor_y)
        for target_x in range(target_min_x, target_max_x + 1):
            source_x = round((target_x - image.width / 2.0) / multiplier + source_center_x)
            if 0 <= source_x < image.width and 0 <= source_y < image.height:
                source = (source_y * image.width + source_x) * 4
                target = (target_y * image.width + target_x) * 4
                output[target : target + 4] = image.rgba[source : source + 4]
    return output


def normalize_batch(manifest: dict, character_id: str, batch_name: str, report: Report) -> Path:
    character = manifest["characters"][character_id]
    batch = character.get("production_batches", {}).get(batch_name)
    output_root = PROJECT_ROOT / "artifacts" / "character_art" / f"{character_id}_{batch_name}_normalized"
    if batch is None:
        report.error(batch_name, "batch metadata is missing")
        return output_root
    if batch.get("status") == "requires_regeneration":
        report.error(batch_name, batch.get("invalid_reason", "generation group requires regenerated source art"))
        return output_root
    source_root = generated_batch_root(manifest, character_id) / batch_name
    if not source_root.is_dir():
        report.error(batch_name, f"original batch source is missing: {source_root.relative_to(PROJECT_ROOT)}")
        return output_root
    animations = list(batch["animations"])
    anchor = batch.get("anchor", {"type": "scale_anchor"})
    approved_idle = [read_png(path) for path in expected_frame_paths(manifest, character_id, "idle") if path.is_file()]
    if not approved_idle or any(image.alpha_bounds is None for image in approved_idle):
        report.error(batch_name, "complete approved idle reference art is required")
        return output_root
    approved_metrics = (scale_profile(manifest, character_id) or {}).get("approved_neutral_metrics", {})
    approved_height = float(approved_metrics.get("median_visible_height", median(image.visible_height for image in approved_idle)))
    anchor_assessment: NeutralAnchorAssessment | None = None
    if anchor["type"] in {"scale_anchor", "neutral_standing"}:
        if batch.get("generation_group") and anchor["type"] != "neutral_standing":
            report.error(batch_name, "generation group must declare a neutral_standing scale anchor")
            return output_root
        anchor_path = source_root / anchor.get("filename", manifest["batch_contract"]["anchor_filename"])
        if not anchor_path.is_file():
            report.error(batch_name, f"batch scale anchor is missing: {anchor_path.relative_to(PROJECT_ROOT)}")
            return output_root
        anchor_image = read_png(anchor_path)
        if anchor_image.alpha_bounds is None:
            report.error(batch_name, "neutral scale anchor contains no visible artwork")
            return output_root
        anchor_assessment = assess_neutral_anchor(manifest, anchor_image, approved_idle, approved_metrics)
        report_neutral_anchor(batch_name, anchor_assessment, report)
        if anchor_assessment.status == "ERROR":
            print("BATCH NORMALIZATION ABORTED: neutral anchor does not match approved anatomy")
            return output_root
        incoming_height = float(anchor_image.visible_height)
        reference_height = approved_height
        anchor_source = anchor_path.relative_to(PROJECT_ROOT).as_posix()
    elif anchor["type"] == "pose_ratio":
        anchor_animation = str(anchor["animation"])
        source_anchor_paths = [source_root / anchor_animation / path.name for path in expected_frame_paths(manifest, character_id, anchor_animation)]
        if not all(path.is_file() for path in source_anchor_paths):
            report.error(batch_name, f"original migration anchor frames are missing under {source_root.relative_to(PROJECT_ROOT)}")
            return output_root
        incoming_height = float(median(read_png(path).visible_height for path in source_anchor_paths))
        references = reference_statistics(manifest, ["idle", anchor_animation])
        reference_height = approved_height * references[anchor_animation]["height"] / references["idle"]["height"]
        anchor_source = f"{anchor_animation} migration anchor"
    else:
        report.error(batch_name, f"unsupported anchor type: {anchor['type']}")
        return output_root
    multiplier = reference_height / incoming_height
    baseline = int(scale_profile(manifest, character_id)["target_baseline_y"])
    print(f"BATCH SCALE {character_id}/{batch_name}: anchor={anchor_source}, {incoming_height:.1f}px -> {reference_height:.1f}px, multiplier={multiplier:.6f}, baseline={baseline}")
    if output_root.exists():
        shutil.rmtree(output_root)
    staged: dict[str, list[Path]] = {}
    for animation in animations:
        config = animation_config(manifest, character_id, animation)
        source_paths = [source_root / animation / path.name for path in expected_frame_paths(manifest, character_id, animation)]
        if not all(path.is_file() for path in source_paths):
            report.error(animation, f"complete original animation is required under {source_root.relative_to(PROJECT_ROOT)}")
            continue
        for source_path in source_paths:
            image = read_png(source_path)
            output = _resample_frame(image, multiplier, bool(config["grounded"]), baseline)
            if output is None:
                report.error(source_path.name, "uniform batch scale would clip artwork; regenerate or reposition it")
                continue
            target_path = output_root / animation / source_path.name
            write_rgba_png(target_path, image.width, image.height, output)
            staged.setdefault(animation, []).append(target_path)
    if report.errors or any(len(staged.get(animation, [])) != len(expected_frame_paths(manifest, character_id, animation)) for animation in animations):
        print("BATCH NORMALIZATION ABORTED: production PNGs were not modified")
        return output_root
    output_digests: dict[str, str] = {}
    for animation, paths in staged.items():
        production_folder = PROJECT_ROOT / "assets" / "characters" / character_id / "sprites" / animation
        production_folder.mkdir(parents=True, exist_ok=True)
        for path in paths:
            shutil.copy2(path, production_folder / path.name)
        output_digests[animation] = animation_digest(production_folder / path.name for path in paths)
    batch.update({
        "status": "approved",
        "anchor_source": anchor_source,
        "anchor_measured_height": round(incoming_height, 6),
        "reference_measured_height": round(reference_height, 6),
        "batch_multiplier": round(multiplier, 6),
        "baseline": baseline,
        "normalization_version": int(manifest["batch_contract"]["normalization_version"]),
        "animation_multipliers": {animation: round(multiplier, 6) for animation in animations},
        "output_digests": output_digests,
    })
    if anchor_assessment is not None:
        batch["anchor_metrics"] = {
            "height_ratio": round(anchor_assessment.height_ratio, 6),
            "height_normalized_width_ratio": round(anchor_assessment.width_ratio, 6),
            "height_normalized_alpha_area_ratio": round(anchor_assessment.alpha_area_ratio, 6),
            "assessment": anchor_assessment.status.lower(),
        }
    save_manifest(manifest)
    return output_root


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("character_id", nargs="?", help="stable CharacterData id to process")
    target.add_argument("--all", action="store_true", help="validate all roster characters")
    parser.add_argument("--contact-sheet", action="store_true", help="write ignored visual-QA contact sheet(s)")
    parser.add_argument(
        "--normalize",
        action="store_true",
        help="normalize one manifest batch from preserved source originals",
    )
    parser.add_argument("--batch", help="manifest production batch to normalize with one anchor-derived multiplier")
    parser.add_argument("--init", action="store_true", help="create manifest-defined design/sprite directories without touching existing art")
    parser.add_argument("--calibrate-scale", action="store_true", help="calibrate persistent character scale from approved reference art")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--animations", help="comma-separated animation names to validate strictly; all others are not checked")
    selection.add_argument("--available", action="store_true", help="validate only animation directories that currently contain PNG files")
    return parser.parse_args()


def parse_requested_animations(manifest: dict, value: str | None) -> list[str] | None:
    if value is None:
        return None
    requested = [item.strip() for item in value.split(",") if item.strip()]
    if not requested:
        raise ValueError("--animations requires at least one animation name")
    unknown = [animation for animation in requested if animation not in manifest["animation_order"]]
    if unknown:
        raise ValueError(f"unknown animation name(s): {', '.join(unknown)}")
    requested_set = set(requested)
    return [animation for animation in manifest["animation_order"] if animation in requested_set]


def available_animations(manifest: dict, character_id: str) -> list[str]:
    sprite_root = PROJECT_ROOT / "assets" / "characters" / character_id / "sprites"
    return [
        animation
        for animation in manifest["animation_order"]
        if any((sprite_root / animation).glob("*.png"))
    ]


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
    if arguments.normalize and not arguments.batch:
        print("--normalize requires --batch; independent per-animation normalization is disabled", file=sys.stderr)
        return 2
    if arguments.batch and not arguments.normalize:
        print("--batch is currently used with --normalize", file=sys.stderr)
        return 2
    if arguments.batch and (arguments.animations or arguments.available):
        print("--batch uses its manifest animation list; do not combine it with --animations/--available", file=sys.stderr)
        return 2
    try:
        requested_animations = parse_requested_animations(manifest, arguments.animations)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    if arguments.init:
        total_created = total_existing = 0
        for character_id in targets:
            created, existing = initialize_character_directories(manifest, character_id)
            total_created += created
            total_existing += existing
        print(f"\nINIT COMPLETE: {total_created} directories created, {total_existing} already present")
        if not arguments.contact_sheet and not arguments.normalize and not arguments.calibrate_scale:
            return 0
    if arguments.calibrate_scale:
        calibration_ok = all(calibrate_character_scale(manifest, character_id) for character_id in targets)
        if not calibration_ok:
            return 1
        save_manifest(manifest)
        if not arguments.contact_sheet and not arguments.normalize and requested_animations is None and not arguments.available:
            return 0
    if arguments.normalize and arguments.batch:
        report = Report()
        for character_id in targets:
            errors_before = report.errors
            output = normalize_batch(manifest, character_id, arguments.batch, report)
            if report.errors == errors_before:
                print(f"NORMALIZED BATCH OUTPUT {output.relative_to(PROJECT_ROOT)}")
        report.summary("BATCH NORMALIZATION")
        return 1 if report.errors else 0
    selected_by_character: dict[str, list[str]] = {}
    for character_id in targets:
        if requested_animations is not None:
            selected_by_character[character_id] = requested_animations
        elif arguments.available:
            selected_by_character[character_id] = available_animations(manifest, character_id)
        else:
            selected_by_character[character_id] = list(manifest["animation_order"])
    reference_animation_set = {
        animation
        for animations in selected_by_character.values()
        for animation in animations
    }
    reference_animations = [animation for animation in manifest["animation_order"] if animation in reference_animation_set]
    references = reference_statistics(manifest, reference_animations)
    report = Report()
    for character_id in targets:
        animations = selected_by_character[character_id]
        partial = requested_animations is not None or arguments.available
        if arguments.available and not animations:
            print(f"\n=== {character_id} ===")
            print("NOT CHECKED: no animation directories currently contain PNG files")
        else:
            validate_character(manifest, character_id, references, report, animations, partial, arguments.normalize)
        if arguments.contact_sheet:
            output = create_contact_sheet(manifest, character_id, animations)
            if output is None:
                print(f"CONTACT SHEET SKIPPED {character_id}: no animations selected")
            else:
                print(f"CONTACT SHEET {output.relative_to(PROJECT_ROOT)}")
    report.summary("ALL CHARACTERS" if arguments.all else targets[0])
    return 1 if report.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
