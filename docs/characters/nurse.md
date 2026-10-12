# Wild Nurse visual notes

Status: complete production integration; all 14 animations and 73 runtime frames are present.

Reference folder: `reference/nurse/`

- Identity: adult woman with a fair complexion and green eyes.
- Clothing/colors: white medical coat over a white top with light footwear.
- Hair: platinum blonde, worn in a low side ponytail with a white ribbon.
- Facial traits: small pearl-like earrings.
- Visual silhouette: narrow fighting stance with the ponytail and stethoscope clearly readable.
- Facing: production artwork faces right; runtime supplies the left-facing `flip_h`.
- Accessories: visible, naturally attached stethoscope; no clipboard or extra medical prop in idle.
- Idle contract: four frames at 6 FPS, looping, on the shared 512×512 canvas and Y=495 baseline.
- Walk contract: six frames at 9 FPS, looping, using the idle-approved scale and Y=495 baseline.
- Punch contract: five frames at 12 FPS, non-looping, using the idle-approved scale and Y=495 baseline.
- Kick contract: six frames at 12 FPS, non-looping, using the idle-approved scale and Y=495 baseline.
- Crouch contract: three frames at 8 FPS, non-looping and holding the final frame.
- Crouch punch contract: five frames at 12 FPS, non-looping.
- Crouch kick contract: six frames at 12 FPS, non-looping.
- Block and crouch block contracts: three frames each at 8 FPS, non-looping and holding the final frame.
- Jump contract: five frames at 10 FPS; runtime physics selects launch, ascent, apex, descent, and landing phases.
- Hurt contract: three frames at 10 FPS, non-looping and holding the final frame.
- Special 1 contract: eight frames at 12 FPS, non-looping. Wild Nurse throws a complete detached stethoscope projectile that spins in flight.
- Special 2 contract: eight frames at 12 FPS, non-looping. Wild Nurse aims a syringe and launches a small heart projectile from the syringe's measured runtime height (Y = -86).
- KO contract: eight frames at 10 FPS, non-looping and holding the final grounded pose.
- Runtime scale: one global `visual_scale = 1.63`; no animation-specific or per-frame runtime scale compensation.
