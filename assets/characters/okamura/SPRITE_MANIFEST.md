# Okamura sprite manifest

Final production contract: **73 PNG frames** in 14 animation directories.

```text
idle/idle_001.png ... idle_004.png
walk/walk_001.png ... walk_006.png
punch/punch_001.png ... punch_005.png
kick/kick_001.png ... kick_006.png
crouch/crouch_001.png ... crouch_003.png
crouch_punch/crouch_punch_001.png ... crouch_punch_005.png
crouch_kick/crouch_kick_001.png ... crouch_kick_006.png
block/block_001.png ... block_003.png
crouch_block/crouch_block_001.png ... crouch_block_003.png
jump/jump_001.png ... jump_005.png
hurt/hurt_001.png ... hurt_003.png
special_1/special_1_001.png ... special_1_008.png
special_2/special_2_001.png ... special_2_008.png
ko/ko_001.png ... ko_008.png
```

Expected counts:

| Animation | Count |
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
| special_1 | 8 |
| special_2 | 8 |
| ko | 8 |
| **TOTAL** | **73** |

Each production PNG must be `512x512`, RGBA, non-empty, and free of edge clipping. Grounded frames must use a shared baseline. Generation groups use one uniform scale multiplier; per-frame scaling is prohibited.

`special_1` visually supports the existing **Shuriken!** projectile move. The shuriken leaves the hand at release; the runtime projectile is separate from the fighter sprite after that point.

`special_2` visually supports the existing **Karate Black Belt** move, whose runtime behavior is `FLYING_KICK`.

`okamura_frames.tres` must not be switched from placeholders for an animation until every expected production frame for that animation has passed QA.
