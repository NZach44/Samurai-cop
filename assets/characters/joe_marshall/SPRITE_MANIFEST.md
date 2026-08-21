# Joe production animation manifest

This manifest tracks Joe's AI-generated production batches. The game does not
require future files to exist: Joe's current `SpriteFrames` retains placeholder
textures until an approved, complete set is assigned animation by animation.

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

- [x] `sprites/walk/walk_001.png`
- [x] `sprites/walk/walk_002.png`
- [x] `sprites/walk/walk_003.png`
- [x] `sprites/walk/walk_004.png`
- [x] `sprites/walk/walk_005.png`
- [x] `sprites/walk/walk_006.png`

### Punch — 5 frames

- [x] `sprites/punch/punch_001.png`
- [x] `sprites/punch/punch_002.png`
- [x] `sprites/punch/punch_003.png`
- [x] `sprites/punch/punch_004.png`
- [x] `sprites/punch/punch_005.png`

### Kick — 6 frames

- [x] `sprites/kick/kick_001.png`
- [x] `sprites/kick/kick_002.png`
- [x] `sprites/kick/kick_003.png`
- [x] `sprites/kick/kick_004.png`
- [x] `sprites/kick/kick_005.png`
- [x] `sprites/kick/kick_006.png`

### Crouch — 3 frames

- [x] `sprites/crouch/crouch_001.png`
- [x] `sprites/crouch/crouch_002.png`
- [x] `sprites/crouch/crouch_003.png`

### Block — 4 frames

- [x] `sprites/block/block_001.png`
- [x] `sprites/block/block_002.png`
- [x] `sprites/block/block_003.png`
- [x] `sprites/block/block_004.png`

### Crouch punch — 5 frames

- [x] `sprites/crouch_punch/crouch_punch_001.png`
- [x] `sprites/crouch_punch/crouch_punch_002.png`
- [x] `sprites/crouch_punch/crouch_punch_003.png`
- [x] `sprites/crouch_punch/crouch_punch_004.png`
- [x] `sprites/crouch_punch/crouch_punch_005.png`

### Crouch kick — 6 frames

- [x] `sprites/crouch_kick/crouch_kick_001.png`
- [x] `sprites/crouch_kick/crouch_kick_002.png`
- [x] `sprites/crouch_kick/crouch_kick_003.png`
- [x] `sprites/crouch_kick/crouch_kick_004.png`
- [x] `sprites/crouch_kick/crouch_kick_005.png`
- [x] `sprites/crouch_kick/crouch_kick_006.png`

### Crouch block — 3 frames

- [x] `sprites/crouch_block/crouch_block_001.png`
- [x] `sprites/crouch_block/crouch_block_002.png`
- [x] `sprites/crouch_block/crouch_block_003.png`

### Jump — 5 frames

- [x] `sprites/jump/jump_001.png`
- [x] `sprites/jump/jump_002.png`
- [x] `sprites/jump/jump_003.png`
- [x] `sprites/jump/jump_004.png`
- [x] `sprites/jump/jump_005.png`

### Hurt — 3 frames

- [x] `sprites/hurt/hurt_001.png`
- [x] `sprites/hurt/hurt_002.png`
- [x] `sprites/hurt/hurt_003.png`

### Special 1 — 8 frames

- [x] `sprites/special_1/special_1_001.png`
- [x] `sprites/special_1/special_1_002.png`
- [x] `sprites/special_1/special_1_003.png`
- [x] `sprites/special_1/special_1_004.png`
- [x] `sprites/special_1/special_1_005.png`
- [x] `sprites/special_1/special_1_006.png`
- [x] `sprites/special_1/special_1_007.png`
- [x] `sprites/special_1/special_1_008.png`

### Special 2 — 8 frames

- [x] `sprites/special_2/special_2_001.png`
- [x] `sprites/special_2/special_2_002.png`
- [x] `sprites/special_2/special_2_003.png`
- [x] `sprites/special_2/special_2_004.png`
- [x] `sprites/special_2/special_2_005.png`
- [x] `sprites/special_2/special_2_006.png`
- [x] `sprites/special_2/special_2_007.png`
- [x] `sprites/special_2/special_2_008.png`

### KO — 8 frames

- [x] `sprites/ko/ko_001.png`
- [x] `sprites/ko/ko_002.png`
- [x] `sprites/ko/ko_003.png`
- [x] `sprites/ko/ko_004.png`
- [x] `sprites/ko/ko_005.png`
- [x] `sprites/ko/ko_006.png`
- [x] `sprites/ko/ko_007.png`
- [x] `sprites/ko/ko_008.png`

Total expected frames currently listed: **74**. The defense/air/hurt batch
(`crouch`, `crouch_punch`, `crouch_kick`, `crouch_block`, `jump`, and `hurt`)
contains **25** frames, and the final special batch contains **16** frames.

## Batch acceptance checklist

- [ ] Every expected filename exists with continuous zero-padded numbering.
- [ ] No extra PNG or wrong-prefix file exists in the listed production directories.
- [ ] Every PNG is 512x512 RGBA with a transparent background.
- [ ] Identity, outfit, hairstyle, proportions, outline, and shading match the
      approved `design/joe_canonical_design.png`.
- [ ] Feet stay on the common baseline without visible frame-to-frame bouncing.
- [ ] Neutral body scale and center remain consistent between animations.
- [ ] Godot import uses lossless compression, disabled mipmaps, and the agreed
      initial Size Limit of 128.
- [ ] Only the completed animation is replaced in `joe_marshall_frames.tres`;
      incomplete animations retain their placeholder frames.

Unexpected files are any PNGs in the listed animation directories that are not
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
| `walk` | 6 | 9 | yes | Weight shift, lead step, passing pose, trail step, recovery, loop closure |
| `punch` | 5 | 12 | no | Full extension is frame 3 |
| `kick` | 6 | 12 | no | Full extension is frame 4 |
| `block` | 4 | 10 | no | Final frame is the held standing guard |
| `crouch` | 3 | 8 | no | Final frame is the held crouching guard |
| `crouch_punch` | 5 | 12 | no | Low extension/contact is frame 3 |
| `crouch_kick` | 6 | 12 | no | Low extension/contact is frame 4 |
| `crouch_block` | 3 | 8 | no | Final frame is the held defensive pose |
| `jump` | 5 | 10 | no | Frames selected from vertical velocity; physics controls motion |
| `hurt` | 3 | 12 | no | Visual reaction only; hit stun controls duration |
| `special_1` | 8 | 12 | no | Katana contact pose is frame 5; melee hitbox timing remains authoritative |
| `special_2` | 8 | 12 | no | Flying-kick contact pose is frame 5; Fighter movement remains authoritative |
| `ko` | 8 | 10 | no | Final fallen pose remains held while Fighter stays defeated |

These frame rates are visual starting points only. Fighter startup, active, and
recovery timers remain authoritative, and artwork integration must not change
movement speed, damage, knockback, or hitbox timing. All sets reuse Joe's
single `CharacterData.visual_scale` and the shared right-facing artwork plus
`AnimatedSprite2D.flip_h`; do not introduce animation-specific scaling or
left-facing duplicates.

For `crouch`, `crouch_block`, and other persistent postures, a non-looping
animation naturally remains on its final frame while gameplay holds the state.
All low-attack frames must remain visibly crouched and use the shared normalized
canvas; artwork must never compensate by moving the Fighter body or resizing a
HurtBox or hitbox.
