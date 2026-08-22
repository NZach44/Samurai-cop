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

## 5. Persistent scale calibration

Joe's completed production set is the global technical reference. Every production character has one persistent `scale_profile` in [`data/character_art_manifest.json`](../data/character_art_manifest.json). After the character's approved idle batch exists, calibrate it once:

```bash
python3 tools/character_art_pipeline.py frank_washington --calibrate-scale
```

Calibration does not modify PNGs. It stores the approved idle animation, its measured median-height ratio to Joe idle, and the character's approved grounded baseline. Repeating the command with unchanged art is idempotent.

Character calibration establishes the approved master body scale. It does not assign target heights to later poses. A crouching person's alpha bounds are naturally shorter and must remain shorter without enlarging the head, torso, hands, or clothing.

Every subsequent generation batch includes `scale_anchor.png` under `reference/<character_id>/generated_batches/<batch_name>/`. This local tree is excluded from Git and Godot imports. The pipeline compares that upright neutral anchor with the character's approved idle reference and calculates one multiplier for the entire batch. Every animation and frame in the batch records and uses exactly that multiplier.

The calibrated target thresholds are:

- within ±8%: pass;
- more than 8% through 15%: warning;
- more than 15%: error.

Grounded animation baselines pass within 8 pixels of the persistent character baseline, warn through 15 pixels, and error beyond 15 pixels. Individual frames are still compared loosely with their own animation median to catch sudden frame-to-frame growth.

Pose bounding height is not used as proof of body scale. Once its batch anchor is valid, an animation is checked for shared batch metadata, internal frame consistency, transparency, clipping, and baseline. Width is used only for clipping/edge QA, so extended limbs, weapons, and FX never determine body scale.

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

## 8. Batch-anchored normalization

```bash
python3 tools/character_art_pipeline.py frank_washington --batch batch_c --normalize
```

Original generated PNGs remain under `reference/<character_id>/generated_batches/<batch_name>/`. The tool measures `scale_anchor.png`, calculates `approved idle height / incoming anchor height`, and applies that one multiplier to every animation/frame listed for the batch in the manifest. It stages normalized output under `artifacts/character_art/` and promotes it only after the complete batch succeeds. The manifest records anchor source/height, reference height, multiplier, baseline, normalization version, animation membership, per-animation multiplier audit values, and output digests.

Grounded output is centered on a clean 512x512 RGBA canvas and translated to the persistent baseline after scaling. Translation never changes body size. Width never controls scale merely because a limb, sword, or effect extends. If the uniform batch scale would clip an extended pose, normalization aborts promotion and requests art correction.

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

The Python importer validates complete filename sets and batch metadata before replacement. It rejects a batch unless its status is ready/reference and every member records exactly the same multiplier; when output digests exist, production PNGs must match them. An error is reported as `SKIP`, preserving the existing animation. The importer also enforces the shared 128-pixel runtime texture limit; this uniform technical setting is not pose scaling.

The importer snapshots the existing `.tres`, asks headless Godot to load/save the approved animation subset through `ResourceSaver`, and verifies that old animation names plus new `res://` texture references survived. If saving or verification fails, it atomically restores the original resource.

Frames load in deterministic manifest order and use manifest FPS/loop settings. Only complete production animations are replaced. Animations with no production PNGs preserve their existing placeholder or shared Fighter fallback. A partially populated animation folder is an error and prevents that import, so a valid placeholder is never replaced by an incomplete or empty animation.

Recommended workflow for every roster character:

1. Run `--init`.
2. Create the canonical design.
3. Generate core art including approved idle.
4. Calibrate character scale with `--calibrate-scale`.
5. For every later batch, include `scale_anchor.png` with the original generated animation folders.
6. Add the batch animation list to the manifest.
7. Calculate and apply one multiplier: `python3 tools/character_art_pipeline.py CHARACTER --batch BATCH --normalize`.
8. Translate grounded frames to the stored baseline (performed by the same command without resizing again).
9. Validate the production animations.
10. Generate/review a contact sheet.
11. Run importer dry-run.
12. Import.
13. Run Godot headless validation.
14. Playtest transitions, facing, anatomy, baseline, and mobile-safe-area alignment.

This sequence applies unchanged to `joe_marshall`, `frank_washington`, `yamashita`, `fujiyama`, `jennifer`, `peggy`, `okamura`, and `nurse`.

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
- **Oversized art:** use the batch's neutral scale anchor and one batch multiplier. Never fit individual pose bounds, add runtime per-animation scale, or change collisions.
- **Inconsistent baselines:** align grounded feet in the source canvas, not by moving the physics body.
- **Frame splitting errors:** remove neighboring-frame fragments, labels, borders, and crop edges.
- **Unexpected missing frame:** compare folder names/counts to the manifest and use three-digit numbering from 001.
- **Intentional effects trigger warnings:** inspect the contact sheet. Large background-like alpha must still be corrected.
