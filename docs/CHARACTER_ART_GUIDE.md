# Character art guide

This guide keeps externally-created, game-ready character artwork consistent
across the shared Fighter scene. It describes production constraints, not any
specific actor likeness. Character-specific observations should be recorded in
`docs/characters/` only after reviewing authorized local references.

## Visual direction

- Use a readable, stylized/cartoon 2D fighting-game treatment rather than raw
  screenshots or photorealistic cutouts.
- Preserve a coherent drawing language across the roster: comparable body
  proportions, line weight, shading complexity, perspective, and color value.
- Use strong silhouettes that remain legible at the small in-game display size.
- Keep facial and clothing details simplified enough for inexpensive mobile and
  Web targets.

## Reference material

Raw video, extracted screenshots, temporary crops, and art/reference inputs are
local development material under `reference/`. They must not be copied into
`assets/` or shipped. The reference directory is excluded from Git and Godot's
import/export scan.

Each character has a local directory:

```text
reference/
├── joe_marshall/
├── frank_washington/
├── fujiyama/
├── yamashita/
├── okamura/
├── jennifer/
├── peggy/
└── nurse/
```

Existing reference filenames are intentionally left unchanged. For new files,
prefer category-based, zero-padded names:

```text
face_01.png
face_02.png
body_01.png
body_02.png
clothing_01.png
action_01.png
```

Add a more specific suffix only when it improves clarity, for example
`body_3quarter_01.png`. References guide a coherent design; they do not map
directly to animation frames.

## Canvas, scale, and baseline

- Game-ready source frames are RGBA PNGs on a `512x512` transparent canvas.
- Use a side-on fighting-game camera with a consistent, mild three-quarter view
  of the torso and face. Avoid changing camera elevation or perspective between
  animations.
- Author the default pose facing right. The shared Fighter mirrors it with
  `AnimatedSprite2D.flip_h` when facing left.
- Center neutral poses near `x = 256`.
- Place the soles on the common ground baseline at approximately `y = 488`,
  leaving a small transparent safety margin below.
- As a starting roster scale, keep a normal standing character roughly 410-450
  source pixels tall. Body-build differences may alter width and height modestly,
  but should not imply different gameplay collision.
- Align every frame by the feet and intended body center, not by each frame's
  nontransparent bounding box.
- Remove avoidable whitespace while preserving the fixed canvas and room needed
  by limbs or effects.

For the current placeholder-scale arena, initially import 512-pixel frames with
Godot **Process > Size Limit = 128**. Apply the same import convention to a full
animation set. Retune visual scale centrally later rather than moving individual
Fighter physics bodies.

## Transparency and rendering

- Background pixels must be genuinely transparent, not a checkerboard or solid
  matte baked into the image.
- Avoid bright fringe pixels left from background removal.
- Use consistent outline color and line weight across frames and characters.
- Keep shading simple and consistent, such as one main light direction and a
  small number of value bands.
- Check readability against both bright and dark arena backgrounds.
- Import sprite PNGs losslessly with mipmaps disabled for the initial 2D setup.

## Required animation names

The shared Fighter expects these names exactly:

```text
idle
walk
jump
crouch
block
punch
kick
hurt
special_1
special_2
ko
```

Use matching, zero-padded frame names such as `walk_001.png` and
`special_2_003.png`. Only `idle` and `walk` normally loop. Other animations are
state/combat presentations and normally do not loop.

Animations may be replaced incrementally because one `SpriteFrames` resource can
contain a mixture of real PNG textures and placeholder atlas textures. Missing
animation names continue to use the Fighter's existing safe `idle` fallback.

## Gameplay separation

Sprite animation represents gameplay state but does not control it. Do not alter
attack startup, active, recovery, hitbox timing, `CharacterBody2D` collision,
HurtBox, push/spacing behavior, or attack hitboxes to compensate for artwork.
Correct visual scale, centering, and feet alignment in the art/import pipeline.

## Character note checklist

Record only confirmed visual-development decisions in each file under
`docs/characters/`:

- body build and proportion adjustments;
- clothing shapes and palette;
- hair shape and palette;
- simplified facial traits;
- primary silhouette cues;
- neutral fighting stance ideas;
- notable accessories and whether they remain readable in motion.

Use `TODO` rather than inventing details that are not clear in the local
references.
