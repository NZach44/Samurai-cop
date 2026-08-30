# Fujiyama Joe-style generated source batches

These two source atlases are repository-transport derivatives of the fresh full-pose Fujiyama generations.
They are half-resolution, palette-quantized source atlases used only to deterministically reconstruct
the 73 production PNGs. They are not runtime textures.

Production rules:
- exactly 73 frames
- 512x512 RGBA output
- baseline Y=495
- one fixed scale multiplier per source atlas
- no per-frame or per-animation scaling
- alpha-component isolation and crop-edge QA before commit
- runtime CharacterData visual_scale=2.05
