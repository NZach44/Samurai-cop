# Peggy visual notes

Status: production sprite integration in progress.

Reference folder: `reference/peggy/`

- Body build: TODO — confirm from local references.
- Clothing/colors: TODO — confirm garments and choose a simplified palette.
- Hair: TODO — confirm shape and color.
- Facial traits: TODO — record approved stylized design decisions.
- Visual silhouette: TODO — identify readable distinguishing shapes.
- Fighting stance: TODO — explore after Joe establishes the roster standard.
- Accessories: TODO — confirm from references.

## Production cross-animation scale QA

Internal frame consistency, valid alpha bounds, and a stable baseline are not
sufficient by themselves. Every new Peggy animation batch must also be checked
against an approved cross-animation body-scale anchor before runtime import.

- Standing animations use the approved Peggy idle/neutral standing reference.
- Crouching animations use the approved held-crouch reference,
  `assets/characters/peggy/sprites/crouch/crouch_003.png`.
- When an animation has a known source state, compare both its first and final
  frames with that state's approved anchor.
- Matching poses may differ by at most 3% in physical visible height.
- Poses that intentionally change height (including jumps, KO poses, and deep
  crouches) are compared using invariant anatomy: head size, shoulder width,
  torso scale, limb thickness, and shoe size. Overall pose height is not scale
  authority for those poses.
- A failure rejects the batch. Never compensate with CharacterData scale,
  animation-specific scale, per-frame scale, transform offsets, or PNG resizing.

The generation group's same-generation neutral `scale_anchor.png` requirement
from the character art guide still applies. Cross-animation anchors are an
additional transition-continuity gate, not a replacement for generation-scale
normalization.
