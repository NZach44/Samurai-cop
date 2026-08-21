# Character Art Pipeline

This is a development-time pipeline for converting approved character designs into ordinary Godot `SpriteFrames` resources. It never runs during gameplay and contains no combat metadata.

## 1. Canonical-design workflow

1. Keep private screenshots and source media in `reference/<character_id>/`.
2. Create and approve one consistent, right-facing canonical cartoon design.
3. Save approved game-production design art under `assets/characters/<character_id>/design/`.
4. Generate one animation at a time from that canonical design.
5. Normalize transparent frames to the common canvas and baseline.
6. Validate PNGs and review a contact sheet.
7. Update the character's `SpriteFrames` resource.
8. Test animation transitions, facing, mobile readability, and gameplay alignment in Godot.

Source images are references, not animation frames. Do not move private reference files into `assets/`.

## 2. Expected folder layout

Each stable CharacterData ID has `assets/characters/<character_id>/sprites/<animation>/`. Supported IDs are `joe_marshall`, `frank_washington`, `yamashita`, `fujiyama`, `jennifer`, `peggy`, `okamura`, and `nurse`.

Wild Nurse keeps the stable directory/CharacterData ID `nurse`. The complete animation directory layout is in [CHARACTER_ART_GUIDE.md](CHARACTER_ART_GUIDE.md).

Create the complete manifest-defined production directory tree for one character:

```bash
python3 tools/character_art_pipeline.py frank_washington --init
```

Initialize all eight characters:

```bash
python3 tools/character_art_pipeline.py --all --init
```

Initialization creates only `design/`, `sprites/`, and the animation directories listed by the manifest. It creates no placeholder PNGs and is idempotent: existing designs, frames, resources, and directories are never overwritten or removed.

## 3. Frame contract and overrides

[`data/character_art_manifest.json`](../data/character_art_manifest.json) is the centralized, visual-only contract. It defines default frame count, FPS, loop behavior, final-frame hold intent, grounded-baseline checking, roster resource path, and optional per-character overrides.

`special_1`, `special_2`, and `ko` normally contain 6–8 frames and are overridden per character when required. Do not put gameplay startup, active time, recovery, damage, hitboxes, or movement in this manifest.

## 4. Filenames and PNG standard

Files use `<animation>_<three-digit frame>.png`, starting at 001. Every production frame must be a non-interlaced 512x512, 8-bit RGBA PNG with actual transparent pixels. Artwork faces right; Godot supplies left-facing visuals with `flip_h`.

## 5. Baseline and apparent scale

The validator derives a reference height and baseline per animation from Joe's completed production set. Cross-character apparent size uses the median visible alpha-bound **height**, not opaque area, width, or bounding-box area. This lets a slim fighter and a heavy fighter share a believable stature without forcing equal body width.

For each non-KO animation, the character median height is compared with the corresponding Joe animation median:

- 85%–115%: pass;
- 75%–85% or 115%–125%: warning;
- below 75% or above 125%: error.

Crouch uses Joe's crouch median rather than standing height. KO skips cross-character height comparison because a fallen pose is naturally wide and short; it retains alpha-coverage, edge, and loose within-animation bounds checks. Individual frames are compared mainly with their own animation median using height, so punch/kick limb extension does not count as body-scale growth merely because width changes.

Grounded animations are also checked against their own baseline median. Human review remains necessary for intentional effects and unusual poses.

## 6. Validator usage

The dependency-free validator checks directories, filenames, dimensions, RGBA mode, real transparency, suspicious large background alpha, edge contact, alpha-bound height, grounded baselines, missing/extra files, and exact byte duplicates. Errors produce a non-zero exit status; warnings request review but do not fail the command. Placeholder-only characters intentionally fail with clear missing-production-directory messages until their art is supplied.

Full validation remains strict and requires all manifest animations:

```bash
python3 tools/character_art_pipeline.py frank_washington
```

During incremental production, validate a named batch strictly while leaving future animations unchecked:

```bash
python3 tools/character_art_pipeline.py frank_washington \
  --animations idle,walk,punch,kick
```

Alternatively, validate every animation directory that currently contains at least one PNG:

```bash
python3 tools/character_art_pipeline.py frank_washington --available
```

An available directory is still checked strictly against its expected manifest frame count. Unselected animations print `NOT CHECKED` and do not affect the exit status.

## 7. Contact sheets

```bash
python3 tools/character_art_pipeline.py frank_washington --contact-sheet
```

Partial contact sheets contain only the selected rows:

```bash
python3 tools/character_art_pipeline.py frank_washington \
  --animations idle,walk,punch,kick \
  --contact-sheet
```

This creates `artifacts/character_art/frank_washington_contact_sheet.png`, grouped and labeled by animation. That directory is ignored by Git. Use the sheet to spot identity drift, frame splitting errors, scale changes, baseline wobble, and unexpected fragments.

## 8. Conservative normalization

```bash
python3 tools/character_art_pipeline.py frank_washington --normalize
```

Normalization never overwrites source PNGs. It writes review copies under `artifacts/character_art/frank_washington_normalized/`, centers visible content, applies one explicit manifest character-level `normalization_scale`, and aligns grounded frames to the manifest baseline. It does not derive scale from alpha area and does not widen slim fighters. One coherent character scale is applied across every selected pose rather than independently resizing frames. A wide punch/kick that cannot fit is reported instead of silently shrinking the whole set.

It refuses invalid transparency, suspicious backgrounds, or output that would clip, and never removes backgrounds automatically. `--animations` and `--available` also limit normalization to the selected batch. Review copies before manually replacing production files.

## 9. SpriteFrames integration

Validate artwork first, then dry-run the importer:

```bash
python3 tools/character_art_pipeline.py frank_washington --available
python3 tools/spriteframes_importer.py frank_washington --dry-run
```

Apply after validation and visual review:

```bash
python3 tools/spriteframes_importer.py frank_washington
python3 tools/spriteframes_importer.py --all
```

The Python importer validates complete filename sets, snapshots the existing `.tres`, asks headless Godot to load/save the SpriteFrames through `ResourceSaver`, and verifies that old animation names plus new `res://` texture references survived. If saving or verification fails, it atomically restores the original resource.

Frames load in deterministic manifest order and use manifest FPS/loop settings. Only complete production animations are replaced. Animations with no production PNGs preserve their existing placeholder or shared Fighter fallback. A partially populated animation folder is an error and prevents that import, so a valid placeholder is never replaced by an incomplete or empty animation.

Recommended workflow:

1. validate the current art batch;
2. run `spriteframes_importer.py --dry-run`;
3. import the SpriteFrames resource;
4. run Godot headless validation;
5. playtest transitions, facing, scale, and gameplay alignment.

The lower-level `update_character_spriteframes.gd` helper is invoked by the Python importer and is not used by the running game.

`hold_final` documents runtime animation policy; looping remains false. Existing Fighter state logic retains the final crouch, block, hurt, or KO pose.

## 10. Bulk operations

```bash
python3 tools/character_art_pipeline.py --all
python3 tools/spriteframes_importer.py --all --dry-run
python3 tools/spriteframes_importer.py --all
```

Bulk update remains safe during incremental production: incomplete sets are explicitly skipped and do not destroy placeholders.

## 11. Runtime behavior

The game loads normal `.tres` resources referenced by CharacterData. It does not scan art directories, parse JSON, validate PNGs, or rebuild animations at startup. Contact sheets and normalized copies remain outside runtime assets.

## 12. Troubleshooting

- **Gray/white halos:** regenerate or correctly unmatte the source; the normalizer must not erase it automatically.
- **Baked checkerboard:** export real RGBA transparency again.
- **Oversized art:** compare visible alpha bounds to Joe; normalize consistently or use one justified per-character visual scale, never collision changes.
- **Inconsistent baselines:** align grounded feet in the source canvas, not by moving the physics body.
- **Frame splitting errors:** remove neighboring-frame fragments, labels, borders, and crop edges.
- **Unexpected missing frame:** compare folder names/counts to the manifest and use three-digit numbering from 001.
- **Intentional effects trigger warnings:** inspect the contact sheet. Large background-like alpha must still be corrected.
