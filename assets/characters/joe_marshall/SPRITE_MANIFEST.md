# Joe core animation manifest

This manifest defines the first AI-generated production batch. The game does not
require these files to exist: Joe's current `SpriteFrames` retains placeholder
textures until an approved batch is assigned animation by animation.

Expected source specification for every listed file:

- PNG with real alpha transparency;
- exactly 512x512 pixels;
- right-facing source pose;
- approved canonical Joe identity, outfit, proportions, palette, and style;
- soles aligned near the shared `y = 488` baseline;
- comparable character scale and body center across the sequence.

## Expected files

### Idle — 4 frames

- [x] `sprites/idle/idle_001.png`
- [x] `sprites/idle/idle_002.png`
- [x] `sprites/idle/idle_003.png`
- [x] `sprites/idle/idle_004.png`

### Walk — 6 frames

- [ ] `sprites/walk/walk_001.png`
- [ ] `sprites/walk/walk_002.png`
- [ ] `sprites/walk/walk_003.png`
- [ ] `sprites/walk/walk_004.png`
- [ ] `sprites/walk/walk_005.png`
- [ ] `sprites/walk/walk_006.png`

### Punch — 5 frames

- [ ] `sprites/punch/punch_001.png`
- [ ] `sprites/punch/punch_002.png`
- [ ] `sprites/punch/punch_003.png`
- [ ] `sprites/punch/punch_004.png`
- [ ] `sprites/punch/punch_005.png`

### Kick — 6 frames

- [ ] `sprites/kick/kick_001.png`
- [ ] `sprites/kick/kick_002.png`
- [ ] `sprites/kick/kick_003.png`
- [ ] `sprites/kick/kick_004.png`
- [ ] `sprites/kick/kick_005.png`
- [ ] `sprites/kick/kick_006.png`

### Crouch — 2 frames

- [ ] `sprites/crouch/crouch_001.png`
- [ ] `sprites/crouch/crouch_002.png`

### Block — 2 frames

- [ ] `sprites/block/block_001.png`
- [ ] `sprites/block/block_002.png`

Total expected core-batch frames: **25**.

## Batch acceptance checklist

- [ ] Every expected filename exists with continuous zero-padded numbering.
- [ ] No extra PNG or wrong-prefix file exists in the six core directories.
- [ ] Every PNG is 512x512 RGBA with a transparent background.
- [ ] Identity, outfit, hairstyle, proportions, outline, and shading match the
      approved `design/joe_canonical_design.png`.
- [ ] Feet stay on the common baseline without visible frame-to-frame bouncing.
- [ ] Neutral body scale and center remain consistent between animations.
- [ ] Godot import uses lossless compression, disabled mipmaps, and the agreed
      initial Size Limit of 128.
- [ ] Only the completed animation is replaced in `joe_marshall_frames.tres`;
      incomplete animations retain their placeholder frames.

Unexpected files are any PNGs in these six animation directories that are not
listed above. Missing files are unchecked manifest entries. Dimension or alpha
problems should be fixed in the source frame before SpriteFrames integration,
not compensated for with Fighter transforms or collision changes.

## Core animation integration settings

Integrate each animation as one complete set. If any file in a set is missing,
leave that animation's existing placeholder frame in
`joe_marshall_frames.tres`; do not add broken texture references or mix an
incomplete production sequence with its placeholder.

| Animation | Required frames | FPS | Loop | Contact-pose guide |
|---|---:|---:|:---:|---|
| `walk` | 6 | 8 | yes | Weight shift, lead step, passing pose, trail step, recovery, loop closure |
| `punch` | 5 | 10 | no | Full extension is frame 3 |
| `kick` | 6 | 10 | no | Full extension is frame 4 |

These frame rates are visual starting points only. Fighter startup, active, and
recovery timers remain authoritative, and artwork integration must not change
movement speed, damage, knockback, or hitbox timing. All three sets reuse Joe's
single `CharacterData.visual_scale` and the shared right-facing artwork plus
`AnimatedSprite2D.flip_h`; do not introduce animation-specific scaling or
left-facing duplicates.
