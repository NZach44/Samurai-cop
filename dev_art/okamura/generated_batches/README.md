# Okamura production sprite batches

Generated source batches for Milestone 15D. Godot ignores this development-art tree via `dev_art/.gdignore`.

Production contract: 73 frames total across idle, walk, punch, kick, crouch, crouch_punch, crouch_kick, block, crouch_block, jump, hurt, special_1, special_2, and ko.

Visual contract: bald older Japanese man; stocky/powerful build; thick arched eyebrows; moustache connected to a long pointed goatee; black loose V-neck martial-arts top with wide sleeves; black trousers; black belt; black footwear; stern/ferocious expression.

Special 1: **Shuriken!** projectile throw.
Special 2: **Karate Black Belt**, implemented by the runtime as `FLYING_KICK` behavior.

Production follows the Joe staged workflow: film references → approved canonical design → small animation batches → normalized production frames. Do not commit exploratory contact sheets or rejected generations. In particular, any generation that invents a briefcase/knife special is invalid because it conflicts with the current Okamura move data.

## Local source-package layout

Approved source art belongs under the ignored local workspace:

```text
reference/okamura/generated_batches/
├── batch_a/
│   ├── scale_anchor.png
│   ├── idle/
│   ├── walk/
│   ├── punch/
│   └── kick/
├── batch_b/
│   ├── scale_anchor.png
│   ├── crouch/
│   ├── crouch_punch/
│   ├── crouch_kick/
│   ├── block/
│   └── crouch_block/
├── batch_c/
│   ├── scale_anchor.png
│   ├── jump/
│   ├── hurt/
│   └── ko/
├── batch_d/
│   ├── scale_anchor.png
│   └── special_1/
└── batch_e/
    ├── scale_anchor.png
    └── special_2/
```

Every `scale_anchor.png` must be a neutral standing Okamura generated in the **same independent generation group** as that batch. Do not copy an anchor from another batch.

After all five source groups are complete:

```bash
python3 tools/init_okamura_art_package.py --generation-tag v1
python3 tools/process_okamura_art.py --dry-run
```

The dry run must pass before production promotion. The final transaction is:

```bash
python3 tools/process_okamura_art.py
python3 tools/validate_okamura_production.py
```

The processor normalizes each group with one uniform multiplier, validates crop/baseline/anatomy, imports complete animations into `okamura_frames.tres`, runs Godot headless validation, and rolls back on failure. Final `CharacterData.visual_scale` is selected afterward from measured runtime idle height against the finished roster; it is not baked into individual PNGs.
