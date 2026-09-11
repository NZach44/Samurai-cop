# Okamura package workflow

This is the canonical Milestone 15D handoff once acceptable generated source art exists. Rejected exploratory sheets do not belong here or under `assets/`.

## Source layout

The private generation package lives under the ignored `reference/` tree:

```text
reference/okamura/generated_batches/
├── batch_a/
│   ├── scale_anchor.png
│   ├── idle/idle_001.png ... idle_004.png
│   ├── walk/walk_001.png ... walk_006.png
│   ├── punch/punch_001.png ... punch_005.png
│   └── kick/kick_001.png ... kick_006.png
├── batch_b/
│   ├── scale_anchor.png
│   ├── crouch/crouch_001.png ... crouch_003.png
│   ├── crouch_punch/crouch_punch_001.png ... crouch_punch_005.png
│   ├── crouch_kick/crouch_kick_001.png ... crouch_kick_006.png
│   ├── block/block_001.png ... block_003.png
│   └── crouch_block/crouch_block_001.png ... crouch_block_003.png
├── batch_c/
│   ├── scale_anchor.png
│   ├── jump/jump_001.png ... jump_005.png
│   ├── hurt/hurt_001.png ... hurt_003.png
│   └── ko/ko_001.png ... ko_008.png
├── batch_d/
│   ├── scale_anchor.png
│   └── special_1/special_1_001.png ... special_1_008.png
├── batch_e/
│   ├── scale_anchor.png
│   └── special_2/special_2_001.png ... special_2_008.png
└── character_package.json
```

Every `scale_anchor.png` must be a neutral standing Okamura generated in the same generation group as that group's action frames. Do not copy one anchor across independently generated groups.

## Art requirements before packaging

Each source pose must preserve the approved canonical identity: bald older Japanese man, stocky/powerful proportions, strongly arched eyebrows, moustache connected to a long pointed goatee, loose black V-neck martial-arts top with wide sleeves, black trousers, black belt, and black footwear.

The accepted production direction is fighting-game cartoon/comic/cel-shaded art. Do not accept photoreal composites, contact sheets, labeled atlases, baked backgrounds, unrelated props, or invented moves.

`special_1` is the existing **Shuriken!** projectile animation. `special_2` is the existing **Karate Black Belt** move with `FLYING_KICK` runtime behavior.

## Create the descriptor

After all five group directories and same-generation anchors exist:

```bash
cd ~/Dev/games/samurai-cop
python3 tools/init_okamura_art_package.py --generation-tag v1
```

Use a new generation tag when a group is regenerated from scratch. The initializer refuses to create a descriptor when a required group directory or anchor is missing.

## Preflight without touching production

```bash
python3 tools/process_okamura_art.py --dry-run
```

Expected result:

```text
RESULT
  DRY RUN PASS
```

The dry run must pass package layout, frame counts, PNG decoding, group scale normalization, same-generation anchor provenance, RGBA/transparency, crop/background checks, baseline checks, and staged validation. It restores the shared manifest afterward.

For a direct final-production validation after frames exist:

```bash
python3 tools/validate_okamura_production.py
```

## Promote the complete character

Only after the dry run passes:

```bash
python3 tools/process_okamura_art.py
```

The shared processor stages all groups first. It promotes production PNGs, updates calibrated manifest metadata, imports `okamura_frames.tres`, creates the full contact sheet, and runs headless Godot only if every group validates. A failure rolls production resources and the shared manifest back.

After promotion, choose `data/fighters/okamura.tres` `visual_scale` from the measured runtime idle height against Joe, Frank, and Fujiyama. Do not compensate by rescaling individual PNGs.

Then run the runtime regression:

```bash
godot --headless --path . --script tools/tests/test_okamura_runtime_visuals.gd
```

The final acceptance target is exactly 73 frames across 14 animations, correct facing/flip behavior, matching runtime physical height, **Shuriken!** projectile behavior, and **Karate Black Belt** flying-kick behavior.

## Commit policy

Tracked development records may be copied under `dev_art/okamura/generated_batches/` after validation, because `dev_art/.gdignore` prevents Godot import/export. Production PNGs belong under `assets/characters/okamura/sprites/` only after passing the package transaction.

Never commit rejected image-generation attempts merely to preserve progress.
