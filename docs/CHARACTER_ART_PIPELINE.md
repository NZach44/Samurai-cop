# Character Art Pipeline

This is a development-time pipeline for converting approved character designs into ordinary Godot `SpriteFrames` resources. It never runs during gameplay and contains no combat metadata.

## Preferred deterministic-rig workflow

For a character supplied as one coherent body-parts package under `reference/<character_id>/rig_parts/`, render and inspect the deterministic preview first:

```bash
python3 tools/render_character_sprites.py CHARACTER
python3 tools/render_character_sprites.py CHARACTER --dry-run --production
```

The renderer uses one character body scale and the shared translation/rotation-only animation library to produce the complete 14-animation, 73-frame contract. It writes preview PNGs, a full contact sheet, anatomy measurements, prop exports, and `render_manifest.json` under `artifacts/character_rig/CHARACTER/`. Different pose canvases receive proportional texture size limits (`canvas maximum * 0.25`), so extra transparent room never changes apparent body scale.

After visual approval, promote transactionally and reuse the existing validator and SpriteFrames importer:

```bash
python3 tools/render_character_sprites.py CHARACTER --production
```

Default preview and dry-run modes never modify `assets/`. The generated-art package workflow below remains supported for existing source-frame packages and troubleshooting.

For production-rig acceptance, preserve the proof rig and pass the candidate descriptor explicitly:

```bash
python3 tools/render_character_sprites.py fujiyama --rig \
  reference/fujiyama/rig_parts_production/character_rig.json
```

This path validates the descriptor, required body components, RGBA source files, one-component alpha, anatomical pivots, separate props, and the character appearance contract. It renders and validates the neutral assembly before attempting the full preview. A passing run writes `production_neutral.png`, `production_parts_contact_sheet.png`, `production_full_contact_sheet.png`, `production_anatomy_report.json`, and `production_render_manifest.json` under `artifacts/character_rig/fujiyama/`; rendered frames remain in the ignored `production_preview/` QA subtree. The anatomy report records per-animation top/bottom/left/right clearance and proportional canvas size limits. Alternate-rig acceptance never promotes or imports assets.

## Preferred complete-package workflow

Future character deliveries should be complete packages. After extracting the ZIP in the project root, preflight the package and then process it:

```bash
python3 tools/process_character_art.py CHARACTER --dry-run
python3 tools/process_character_art.py CHARACTER
```

The dry run discovers and validates every declared generation group, reports missing manifest registrations, calculates group multipliers, stages normalization, validates the staged frames, and reports the SpriteFrames import plan. It does not change the manifest, production PNGs, SpriteFrames, or Godot resources.

The normal command performs the same preflight, registers missing groups, promotes all package animations, runs strict validation, creates `artifacts/character_art/CHARACTER_full_contact_sheet.png`, imports SpriteFrames, and runs Godot headless validation. Promotion and import happen only after every group passes. If a later validation or import step fails, the previous character assets, manifest, and SpriteFrames resource are restored.

Each package must include `reference/<character_id>/generated_batches/character_package.json`. Its group names match directories beside the descriptor:

```json
{
  "character_id": "yamashita",
  "groups": {
    "core": {
      "source_generation": "yamashita_core_v1",
      "animations": ["idle", "walk", "punch", "kick"],
      "anchor": "scale_anchor.png"
    },
    "defense_low": {
      "source_generation": "yamashita_defense_low_v2",
      "animations": ["crouch", "crouch_punch", "crouch_kick", "block", "crouch_block"],
      "anchor": "scale_anchor.png"
    },
    "jump": {
      "source_generation": "yamashita_jump_v2",
      "animations": ["jump"],
      "anchor": "scale_anchor.png"
    },
    "hurt": {
      "source_generation": "yamashita_hurt_v1",
      "animations": ["hurt"],
      "anchor": "scale_anchor.png"
    },
    "ko": {
      "source_generation": "yamashita_ko_v1",
      "animations": ["ko"],
      "anchor": "scale_anchor.png"
    },
    "special_1": {
      "source_generation": "yamashita_special_1_v1",
      "animations": ["special_1"],
      "anchor": "scale_anchor.png"
    },
    "special_2": {
      "source_generation": "yamashita_special_2_v1",
      "animations": ["special_2"],
      "anchor": "scale_anchor.png"
    }
  }
}
```

An animation may appear in only one group. Every group requires `source_generation`, `anchor`, and `animations`. The anchor must come from the same generation operation as the declared frames. Identical anchor SHA256 content across different `source_generation` values is a hard error; groups may share anchor bytes only when they explicitly share one source generation. Missing groups are registered using this provenance-aware neutral-standing schema. Matching approved metadata is preserved; conflicting approved metadata stops processing instead of being overwritten. If the character has no master scale profile, the package must contain one group with complete `idle` art. The processor reads the character-level `target_height_ratio_to_reference` (default `1.0`), calculates `(Joe idle height * target ratio) / source idle height`, uniformly normalizes the complete core group, and only then records the master profile. Raw source dimensions never become physical character height.

Implicit/default physical ratios must remain within `0.80`–`1.20`; an intentional unusual height outside that range must be explicitly recorded in the character manifest. This sanity gate applies to physical target height, not source scale. A 140px or 500px source fighter is valid and is scaled toward the configured target. Weapon, limb, effect, and fallen-pose width never changes the multiplier. When correct body scale cannot fit the default canvas, a character may declare a larger transparent `production_canvas`; the runtime texture limit must preserve the same canvas-to-import ratio as the roster reference.

After a successful command, inspect the full contact sheet and playtest the character. The manual per-batch commands below remain available for troubleshooting and deliberate recalibration, but manual batch registration is no longer part of the preferred workflow.

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

Files use `<animation>_<three-digit frame>.png`, starting at 001. Every production frame must be a non-interlaced, 8-bit RGBA PNG with actual transparent pixels. The default canvas is 512x512. A manifest-approved per-character canvas may be larger; deterministic rig output may instead declare one canvas per animation. All frames within an animation share its canvas, and every canvas uses a proportional import limit so pixel scale remains identical. Artwork faces right; Godot supplies left-facing visuals with `flip_h`.

## 5. Persistent scale calibration

Joe's completed production set is the global technical reference. Every production character has one persistent `scale_profile` in [`data/character_art_manifest.json`](../data/character_art_manifest.json). After the character's approved idle batch exists, calibrate it once:

```bash
python3 tools/character_art_pipeline.py frank_washington --calibrate-scale
```

Calibration does not modify PNGs. It stores the normalized approved idle animation, its target/measured median-height ratio to Joe idle, the character's approved grounded baseline, and approved neutral median height, width, and occupied-alpha area. Repeating the command with unchanged art is idempotent. Package processing performs source-to-target normalization before this calibration; manual calibration is for already normalized production art.

Character calibration establishes the approved master body scale. It does not assign target heights to later poses. A crouching person's alpha bounds are naturally shorter and must remain shorter without enlarging the head, torso, hands, or clothing.

Every subsequent generation group includes `scale_anchor.png` under `reference/<character_id>/generated_batches/<group_name>/`. This local tree is excluded from Git and Godot imports. The anchor must be generated with that group's frames and show a full-body, upright, grounded neutral pose—not hurt, block, crouch, jump, attack, or KO. The pipeline records its SHA256 and source-generation provenance, compares it with the character's approved idle reference, and calculates one multiplier for the group. Every animation and frame in the group records and uses exactly that multiplier.

Use separate groups when animations were independently generated, even if they originated from one visual sheet. For example, `batch_c_jump`, `batch_c_hurt`, and `batch_c_ko` each require their own neutral anchor. This guards against image-generation scale drift between rows.

Neutral anchors are checked against approved character idle using height-normalized anatomy:

- raw visible height: informational source scale that determines the multiplier;
- height-normalized visible width: ±12% pass, 12–20% warning, over 20% error;
- height-normalized occupied alpha area: ±25% pass, 25–40% warning, over 40% error.

Width and alpha area are secondary anatomy checks. They reject a purported neutral anchor whose head, torso, or limbs have drifted even when its overall height looks plausible. They are never calculated from jump, hurt, crouch, attack, or KO frames.

Grounded animation baselines pass within 8 pixels of the persistent character baseline, warn through 15 pixels, and error beyond 15 pixels. Individual frames are still compared loosely with their own animation median to catch sudden frame-to-frame growth.

Pose bounding height is not used as proof of body scale. Once its batch anchor is valid, an animation is checked for shared batch metadata, internal frame consistency, transparency, clipping, and baseline. Width is used only for clipping/edge QA, so extended limbs, weapons, and FX never determine body scale.

Action frames receive a secondary morphology check against their same-generation neutral anchor. The check combines pose-normalized alpha mass, local horizontal/vertical alpha-run thickness, and upper-body mass width. It detects obvious global anatomy shrinkage without requiring crouch, jump, KO, or attack bounds to match idle. Failure rejects the whole source group; it never creates per-animation or per-frame scale values.

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

## 8. Generation-group neutral-anchor normalization

```bash
python3 tools/character_art_pipeline.py frank_washington --batch batch_c_jump --normalize
python3 tools/character_art_pipeline.py frank_washington --batch batch_c_hurt --normalize
python3 tools/character_art_pipeline.py frank_washington --batch batch_c_ko --normalize
```

Original generated PNGs remain under `reference/<character_id>/generated_batches/<group_name>/`. The tool first validates that group's neutral anchor against approved idle height, width, and alpha-area anatomy. It then calculates `approved idle height / incoming anchor height` and applies that one multiplier to every animation/frame listed for the group. It stages normalized output under `artifacts/character_art/` and promotes it only after the complete group succeeds. The manifest records anchor source/measurements, multiplier, baseline, normalization version, animation membership, per-animation multiplier audit values, and output digests.

The old broken method compared an action pose with a corresponding pose target and gave each animation its own multiplier. That enlarged crouches and distorted anatomy. The current method uses only a neutral anchor generated with the source frames; action-pose height and KO width never drive scaling.

Grounded output is centered on the character's clean RGBA production canvas and translated to its persistent baseline after scaling. Translation never changes body size. Width never controls scale merely because a limb, sword, or effect extends. If the uniform batch scale would clip an extended pose even on the approved canvas, normalization aborts promotion and requests art correction.

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

The Python importer validates complete filename sets and generation-group metadata before replacement. It rejects a generation group unless its status is `approved`, its source generation and same-generation anchor SHA256 are valid, anatomical QA passed, and every member records exactly the same multiplier; when output digests exist, production PNGs must match them. An error is reported as `SKIP`, preserving the existing animation and last-known-good SpriteFrames. The default 512px canvas imports at a 128px texture limit. Larger per-character or deterministic per-animation canvases use proportional limits (for example, 576px at 144px), preserving the same 0.25 import factor and therefore comparable display scale.

The importer snapshots the existing `.tres`, asks headless Godot to load/save the approved animation subset through `ResourceSaver`, and verifies that old animation names plus new `res://` texture references survived. If saving or verification fails, it atomically restores the original resource.

Frames load in deterministic manifest order and use manifest FPS/loop settings. Only complete production animations are replaced. Animations with no production PNGs preserve their existing placeholder or shared Fighter fallback. A partially populated animation folder is an error and prevents that import, so a valid placeholder is never replaced by an incomplete or empty animation.

Manual troubleshooting workflow:

1. Run `--init`.
2. Create the canonical design.
3. Generate core art including approved idle.
4. Calibrate character scale with `--calibrate-scale`.
5. For every independently generated animation group, include a true neutral-standing `scale_anchor.png` with its source frames.
6. Add one manifest generation group per independently generated source.
7. Calculate and apply one multiplier: `python3 tools/character_art_pipeline.py CHARACTER --batch GENERATION_GROUP --normalize`.
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

## Experimental deterministic cutout renderer

`tools/render_character_sprites.py` renders a reusable body-part rig into the same filename/frame-count contract used by production SpriteFrames. Character inputs live under `reference/<character_id>/rig_parts/`: RGBA part textures plus `character_rig.json`, which records the generic bone hierarchy, part parent, pivot, local position, one static part scale, z order, one character `body_scale`, and prop attachment slots.

Shared keyframed poses are defined in `data/character_rig_animations.json`. They may animate bone position and rotation only. Animated scale keys are rejected. The current proof set covers `idle`, `walk`, `punch`, `kick`, `crouch`, and `jump` using manifest frame counts.

```bash
python3 tools/render_character_sprites.py fujiyama
```

The command writes transparent comparison frames, `render_manifest.json`, and a contact sheet beneath `artifacts/character_rig/fujiyama/`. It chooses one canvas large enough for every rendered pose without changing rig scale. The recorded runtime texture limit preserves the standard 0.25 canvas-to-import factor even when the canvas exceeds 512 pixels. Experimental output is not promoted or imported automatically.

## 12. Troubleshooting

- **Gray/white halos:** regenerate or correctly unmatte the source; the normalizer must not erase it automatically.
- **Baked checkerboard:** export real RGBA transparency again.
- **Oversized art:** use the batch's neutral scale anchor and one batch multiplier. Never fit individual pose bounds, add runtime per-animation scale, or change collisions.
- **Inconsistent baselines:** align grounded feet in the source canvas, not by moving the physics body.
- **Frame splitting errors:** remove neighboring-frame fragments, labels, borders, and crop edges.
- **Unexpected missing frame:** compare folder names/counts to the manifest and use three-digit numbering from 001.
- **Intentional effects trigger warnings:** inspect the contact sheet. Large background-like alpha must still be corrected.
