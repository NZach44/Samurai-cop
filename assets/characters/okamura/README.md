# Okamura production sprite pipeline

This directory contains game-ready Okamura assets. Film screenshots, exploratory generations, rejected pose sheets, temporary crops, and other production references do not belong here. Keep those in the ignored local `reference/okamura/` workspace. Tracked development source batches may live under `dev_art/okamura/generated_batches/`, which Godot ignores through `dev_art/.gdignore`.

## Production workflow

Use the same staged workflow that produced the finished Joe Marshall character:

```text
PRIVATE FILM REFERENCES
reference/okamura/
        ↓
APPROVED CANONICAL DESIGN
assets/characters/okamura/design/okamura_canonical_design.png
        ↓
SMALL ANIMATION POSE BATCHES
local/reference generation work
        ↓
FINAL NORMALIZED SPRITE FRAMES
assets/characters/okamura/sprites/<animation>/
        ↓
GODOT SPRITEFRAMES
assets/characters/okamura/okamura_frames.tres
```

Do not generate the complete 73-frame character as one contact sheet. First establish one approved canonical full-body design. Every animation batch must then use that design as the primary consistency reference, with film screenshots used only as secondary identity/clothing references.

Rejected generations never enter `assets/` and must never be used as production sources merely because they contain a usable-looking pose.

## Canonical visual contract

The approved design must preserve these reference-derived traits:

- older Japanese man;
- bald head;
- stocky, powerful build rather than a lean or bodybuilder silhouette;
- very thick, strongly arched dark eyebrows;
- dark moustache connected to a long pointed goatee;
- stern or ferocious expression;
- loose black V-neck martial-arts top with wide sleeves;
- black trousers;
- black belt;
- black footwear;
- readable fighting-game cartoon/comic/cel-shaded rendering rather than photoreal CG.

The canonical design must show the complete body in a neutral right-facing fighting stance with safe crop margin and a transparent or cleanly removable background. It must not contain labels, panels, alternate poses, props, or scenery.

## Frame standard

- PNG with RGBA transparency.
- Exactly `512x512` source pixels per frame.
- One uniform physical scale for a generation group; never scale individual frames independently.
- Grounded frames share one soles baseline, initially targeted near `y = 495` with safe bottom clearance.
- Center the neutral body around `x = 256`; wide attacks may extend naturally without shrinking the character.
- Grow/adjust canvas placement rather than shrinking wide poses.
- No clipped hair, hands, feet, clothing, projectile-handoff artwork, or KO silhouettes.
- Preserve a practical minimum transparent clearance around visible artwork; final QA records the measured minimum.
- Runtime `visual_scale` is chosen only after comparing the rendered idle height against Joe, Frank, and Fujiyama. Do not pre-bake runtime-size compensation into individual PNGs.

## Production contract

The final character contains exactly 73 frames:

| Animation | Frames | Loop | Pose intent |
|---|---:|:---:|---|
| `idle` | 4 | yes | grounded martial-arts guard with subtle breathing/weight shift |
| `walk` | 6 | yes | purposeful fighting walk, consistent body height |
| `punch` | 5 | no | guard, startup, extension/contact, retract, guard |
| `kick` | 6 | no | guard, chamber, extension, contact, retract, guard |
| `crouch` | 3 | no | standing transition, lower, stable crouch guard |
| `crouch_punch` | 5 | no | crouch guard through low punch and recovery |
| `crouch_kick` | 6 | no | crouch guard through low kick and recovery |
| `block` | 3 | no | enter guard, brace, stable standing defense |
| `crouch_block` | 3 | no | enter crouch guard, brace, stable low defense |
| `jump` | 5 | no | takeoff, rise, apex, fall, landing presentation |
| `hurt` | 3 | no | impact, maximum recoil, recovery presentation |
| `special_1` | 8 | no | Shuriken throw: ready, draw/present, wind-up, release, follow-through, recover; spawned projectile is separate after release |
| `special_2` | 8 | no | Karate Black Belt / flying-kick behavior: launch, advancing airborne kick, contact emphasis, recovery/landing |
| `ko` | 8 | no | stagger/fall progression into a stable grounded defeat pose |

Combat startup/active/recovery timers remain authoritative. The animation should visually support those timings but must not change combat logic.

## Batch order

Keep batches small and complete before integration:

1. Batch A — `idle` 4, `walk` 6, `punch` 5, `kick` 6.
2. Batch B — `crouch` 3, `crouch_punch` 5, `crouch_kick` 6, `block` 3, `crouch_block` 3.
3. Batch C — `jump` 5, `hurt` 3, `ko` 8.
4. Batch D — `special_1` 8, Shuriken throw.
5. Batch E — `special_2` 8, flying kick.

Before committing any production batch: verify expected frame count, RGBA, non-empty alpha, crop clearance, shared baseline where applicable, consistent group scale, identity/clothing consistency, and animation readability in sequence.
