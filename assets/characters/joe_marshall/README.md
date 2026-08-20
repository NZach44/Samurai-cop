# Joe Marshall sprite pipeline

This directory contains **game-ready** Joe Marshall assets. Raw video, extracted
screenshots, temporary crops, and artwork-generation reference inputs belong in
`reference/joe_marshall/` (or `reference/source/` for source media), never here.
The repository ignores `reference/`, and its `.gdignore` marker prevents Godot
from importing or exporting those local files. Only use source material you have
permission to use.

## Directory layout

```text
assets/characters/joe_marshall/
├── README.md
├── SPRITE_MANIFEST.md
├── design/
│   └── README.md
├── joe_marshall_frames.tres
├── placeholder_sheet.svg
└── sprites/
    ├── idle/
    ├── walk/
    ├── jump/
    ├── crouch/
    ├── block/
    ├── punch/
    ├── kick/
    ├── hurt/
    ├── special_1/
    ├── special_2/
    └── ko/
```

Future game-ready voice/audio may live in
`assets/audio/characters/joe_marshall/`, and future game-ready outcome videos
may live in `assets/videos/outcomes/`. Gameplay does not depend on either path.

## Source versus game assets

Source/reference material is local development input: authorized source video,
extracted frames, face/clothing/body references, temporary crops, and AI or
artist reference inputs. These files are not animation frames and must not ship.

Game-ready assets are cleaned, stylized/cartoon sprite frames with transparent
backgrounds plus the final `SpriteFrames` resource. These belong under `assets/`
and may be committed.

## AI-assisted production stages

Use this staged workflow; do not generate all animations directly from the movie
references:

```text
PRIVATE REFERENCE IMAGES
reference/joe_marshall/
        ↓
APPROVED CANONICAL DESIGN
assets/characters/joe_marshall/design/joe_canonical_design.png
        ↓
ANIMATION POSE CANDIDATES
local development work under reference/joe_marshall/
        ↓
FINAL NORMALIZED SPRITE FRAMES
assets/characters/joe_marshall/sprites/<animation>/
        ↓
GODOT SPRITEFRAMES
assets/characters/joe_marshall/joe_marshall_frames.tres
```

The movie screenshots are private/local source references. Once the canonical
cartoon design is approved, it becomes the primary consistency reference for
every generation request. Use source screenshots only as secondary references
for details that the canonical sheet does not resolve.

Save the one approved full-body canonical design at:

```text
assets/characters/joe_marshall/design/joe_canonical_design.png
```

Do not save exploratory generations or rejected pose candidates in `assets/`.
Keep those under the ignored `reference/joe_marshall/` workspace. Only approved
design artwork and normalized game-ready PNGs belong in shipped assets.

The canonical design must show a stylized/cartoon fighting-game character with:

- the full body visible in a neutral, right-facing fighting stance;
- one internally consistent identity, outfit, hairstyle, and set of proportions;
- a clear silhouette that remains readable at game scale;
- a transparent or cleanly removable background;
- enough resolution and margin to normalize poses onto the 512x512 frame canvas.

Every animation request should include this approved design as its primary image
reference. Generate one small pose batch at a time so identity, outfit, scale,
and baseline drift can be corrected before the next animation.

Useful reference coverage includes:

- a clear frontal or near-frontal full-body view;
- a side or three-quarter body view;
- a clear face view;
- clothing and footwear details;
- an action or fighting pose;
- a few lighting conditions when they help distinguish actual design details.

Reference screenshots guide a consistent character design. They are not expected
to map one-to-one to animation frames.

## Frame standard

- Format: PNG with alpha transparency (RGBA).
- Source canvas: exactly `512x512` pixels for every frame.
- Horizontal center: keep Joe centered around `x = 256` unless the action needs
  intentional reach.
- Ground baseline: place the soles consistently at approximately `y = 488`.
  The remaining 24 pixels are a small safety margin for effects/antialiasing.
- Keep Joe at a consistent visual scale and avoid avoidable empty space around
  the pose.
- Never compensate for a drifting crop by moving `CharacterBody2D`. Correct the
  frame canvas and feet alignment instead.

The current placeholder is roughly 128 pixels tall in gameplay. For initial
512-pixel source frames, use Godot's texture import **Size Limit = 128** so the
new art fits the existing arena without changing physics or shared Fighter code.
This is a temporary presentation setting and can be retuned later as one visual
scale decision for the roster.

Use zero-padded filenames inside the matching animation directory:

```text
idle/idle_001.png
idle/idle_002.png
punch/punch_001.png
special_1/special_1_001.png
```

## Animation conventions

Do not rename these animations; `Fighter` requests them directly.

| Animation | Initial frames | Loop | Temporary FPS |
|---|---:|:---:|---:|
| `idle` | 4-6 | yes | 6 |
| `walk` | 6-8 | yes | 8 |
| `jump` | 3-5 | no | 6 |
| `crouch` | 2-3 | no | 5 |
| `block` | 2-3 | no | 5 |
| `punch` | 4-6 | no | 10 |
| `kick` | 5-7 | no | 10 |
| `hurt` | 2-4 | no | 8 |
| `special_1` | 6-10 | no | 10 |
| `special_2` | 6-10 | no | 10 |
| `ko` | 5-8 | no | 6 |

These values are development guidelines. Combat startup, active, and recovery
timers remain authoritative; animation duration does not change hitbox timing.

Animations can be replaced incrementally. For example, replace only `idle` in
`joe_marshall_frames.tres` with PNG frames and leave every other animation using
the placeholder atlas. Missing animations still use the Fighter's existing safe
fallback to `idle`.

## Production checklist

Approve the canonical design first. Then produce the initial AI-assisted batch
in this order:

1. `idle` — 4 frames;
2. `punch` — 5 frames;
3. `kick` — 6 frames;
4. `walk` — 6 frames;
5. `crouch` — 2 frames;
6. `block` — 2 frames.

`jump`, `hurt`, `ko`, `special_1`, and `special_2` are explicitly outside this
first batch and remain placeholder-backed.

For the first delivery, provide only `idle_001.png` through `idle_004.png`.
Review the design, source scale, alpha edges, baseline stability, import settings,
and in-game readability before applying the same design to other animations.

Replacing `idle` does not require rebuilding the resource: open the existing
`idle` animation, remove its one placeholder frame, and add the approved idle
PNGs. Do not remove or alter the placeholder frames in the other ten animations.

The exact first-batch filenames and acceptance checks are listed in
`SPRITE_MANIFEST.md`.

## Local reference extraction example

The project does not download source media. Given a local, authorized input file,
conceptual `ffmpeg` commands for development are:

```bash
ffmpeg -ss HH:MM:SS -i /path/to/authorized_source.ext -frames:v 1 \
  reference/joe_marshall/joe_candidate_001.png

ffmpeg -i /path/to/authorized_source.ext -vf "fps=1/2" \
  reference/joe_marshall/joe_candidate_%03d.png
```

Select only useful references rather than treating every extracted image as an
animation frame. Keep all generated reference files under `reference/`.

## Production workflow

1. Extract candidate references locally from authorized source video.
2. Select useful body, face, clothing, and action references.
3. Establish one consistent stylized/cartoon Joe design.
4. Create the small animation frame set.
5. remove the background and verify real alpha transparency.
6. Normalize every frame to the 512x512 canvas and shared foot baseline.
7. Save PNGs in their named animation directories.
8. In Godot, import the PNGs losslessly, disable mipmaps, and initially set
   **Process > Size Limit** to `128`.
9. Open `joe_marshall_frames.tres` and assign frames to the matching animation.
10. Test scale, baseline stability, facing, state transitions, and combat timing.

`AnimatedSprite2D` is visual-only. The Fighter's body collision, hurtbox,
push/spacing behavior, and attack hitboxes remain separate scene nodes. Do not
resize those physics shapes merely because the artwork is larger. Left-facing
presentation continues to use the existing `flip_h`; do not duplicate artwork.
