# Character Art Guide

## 1. Purpose

This document defines the visual production standard for all fighter sprite artwork. Joe Marshall is currently the technical reference implementation. It governs game-ready files under `assets/`; private screenshots and other source references remain under the Git-ignored `reference/` tree.

## 2. Canvas Standard

Every production sprite frame must be:

- PNG;
- 512x512;
- RGBA;
- transparent background;
- free of baked checkerboards, UI, labels, frame numbers, and borders;
- free of glow or matte around the whole character unless it is an intentional local effect.

## 3. Facing Convention

All source artwork faces right. Left-facing gameplay uses `AnimatedSprite2D.flip_h`; do not create duplicate left-facing frames.

## 4. Visual Scale

Characters use a consistent apparent scale and must remain readable on small Android screens. Joe Marshall's completed production art is the current technical reference. A 512x512 canvas does not imply that visible artwork should fill the canvas: visible alpha bounds determine apparent scale.

A per-character `visual_scale` may normalize genuine body-proportion differences, but sprite scale remains independent from gameplay collision, hurtboxes, pushboxes, and attack hitboxes. Each character also has one persistent production-art scale profile calibrated from approved idle art. Every later generated batch receives one anchor-derived multiplier shared by every pose in that batch; crouch and other short poses are never enlarged merely to match a reference bounding-box height.

### Batch scale anchor

Every newly generated batch must include one development-only `scale_anchor.png` made in the same generation batch as its animations. The anchor shows the same canonical character standing upright in a neutral pose, facing right, without FX, on a transparent background. Its apparent head, torso, hands, clothes, and overall anatomy establish that batch's intrinsic scale.

Store incoming originals under `reference/<character_id>/generated_batches/<batch_name>/`, with `scale_anchor.png` beside animation subdirectories. This ignored, `.gdignore`-protected tree is local development material. The anchor is never copied into `sprites/` or imported into `SpriteFrames`.

## 5. Ground Baseline

Grounded animations share the character baseline stored in the art manifest: idle, walk, punch, kick, crouch, block, hurt, grounded portions of specials, and the KO final pose. Batch normalization applies one uniform scale first, then translates each grounded frame vertically to the baseline without changing its dimensions. Changing animation must not make the fighter float or sink.

## 6. Animation Names

Standard production animation names are:

`idle`, `walk`, `punch`, `kick`, `crouch`, `crouch_punch`, `crouch_kick`, `block`, `crouch_block`, `jump`, `hurt`, `special_1`, `special_2`, and `ko`.

## 7. Recommended Frame Counts

| Animation | Frames |
|---|---:|
| idle | 4 |
| walk | 6 |
| punch | 5 |
| kick | 6 |
| crouch | 3 |
| crouch_punch | 5 |
| crouch_kick | 6 |
| block | 3 |
| crouch_block | 3 |
| jump | 5 |
| hurt | 3 |
| special_1 | 6–8 |
| special_2 | 6–8 |
| ko | 6–8 |

Per-character manifest overrides are allowed when justified. Joe's completed four-frame standing block, for example, is recorded as an override rather than changing the shared default.

## 8. Recommended Animation Speeds

| Animation | FPS | Playback |
|---|---:|---|
| idle | 6 | loop |
| walk | 9 | loop |
| punch | 12 | non-looping |
| kick | 12 | non-looping |
| crouch | 8 | settle and hold final pose |
| crouch_punch | 12 | non-looping |
| crouch_kick | 12 | non-looping |
| block | 8 | settle and hold final pose |
| crouch_block | 8 | settle and hold final pose |
| jump | 10 | non-looping |
| hurt | 10 | non-looping; hold final when required |
| special_1 | 12 | non-looping default |
| special_2 | 12 | non-looping default |
| ko | 10 | non-looping; hold final pose |

Gameplay state decides how long held states remain visible. Sprite FPS never redefines attack, stun, movement, or round timing.

## 9. Folder Structure

```text
assets/characters/<character_id>/
├── design/
│   └── <character_id>_canonical_design.png
└── sprites/
    ├── idle/
    ├── walk/
    ├── punch/
    ├── kick/
    ├── crouch/
    ├── crouch_punch/
    ├── crouch_kick/
    ├── block/
    ├── crouch_block/
    ├── jump/
    ├── hurt/
    ├── special_1/
    ├── special_2/
    └── ko/
```

Private source/reference material belongs in `reference/<character_id>/`, never in `assets/`.

## 10. Filename Convention

Use `<animation>_001.png`, `<animation>_002.png`, and so on. Examples: `walk_001.png`, `crouch_kick_004.png`, `special_1_006.png`, and `ko_008.png`. Numbers are three-digit zero-padded so filename sorting is deterministic.

## 11. Canonical Character Design

Before generating animation frames, create and approve one canonical design image. It defines face, hair, body proportions, clothing, colors, accessories, silhouette, and overall cartoon style. Use that approved image as the primary consistency reference for every animation; private screenshots become secondary references.

## 12. Transparency Rules

Reject artwork with gray or white halos, a blue glow around the entire body, a baked checkerboard, opaque rectangular backgrounds, or semi-transparent panel backgrounds. Intentional local sword slashes, muzzle flashes, dust, blood, and projectile trails may use partial alpha. Background-like partial alpha spanning large portions of the canvas is an error.

## 13. Animation vs Gameplay

Artwork is visual only. Sprite dimensions must not automatically alter `CharacterBody2D` collision, HurtBox, PushBox, attack hitboxes, movement speed, jump physics, damage, or attack timing. Gameplay remains authoritative.

## 14. Special Moves

Each fighter has exactly two special-art slots, `special_1` and `special_2`. Special titles are UI text and must not be baked into sprite artwork. Do not bake move titles, speech bubbles, or HUD elements into sprite PNGs.

## 15. Intro Quotes

Intro quote text and optional audio are separate from sprite artwork. Never embed quote text in a character frame.

## 16. KO Artwork

KO frames require extra QA because fallen poses are wider than standing poses. Check for oversized content, gray/white matte, a final pose that rests on the floor, and readability at the normal fighter scale. Apply one coherent visual normalization across the animation, not arbitrary per-frame gameplay transforms.

## 17. Mobile Readability

Always test landscape mobile sizes. Faces, limbs, attack poses, and weapon silhouettes must remain legible on smaller Android phones without overlapping the health HUD, touch-control zone, or arena boundaries.

## 18. QA Checklist

Before integration verify:

- 512x512 RGBA with real transparent pixels;
- no baked background or unexpected alpha halo;
- expected frame count and deterministic filenames;
- consistent apparent scale and grounded baseline;
- no accidental crop, missing limbs, or neighboring sprite fragments;
- no labels, header text, borders, or UI;
- animation/contact poses read clearly at mobile size.

Run the automated validator and inspect its contact sheet; neither replaces human visual review.

## 19. Joe Marshall Reference

Joe Marshall's completed production sprite set is the current reference for technical scale, baseline, naming, animation organization, and transparency quality. Future characters follow the same technical standards while retaining their own body proportions and visual identity. The validator reads Joe without modifying his PNGs.
