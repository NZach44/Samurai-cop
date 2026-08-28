# Fujiyama generated batches

This directory tracks the AI-generated source batches used to build Fujiyama's production sprites.

Workflow intentionally mirrors the original Joe Marshall process:

- generate complete animation batches from the original Fujiyama references;
- keep one coherent character scale within each batch and across the character;
- mechanically crop/split only after generation;
- validate alpha/crop/baseline before integration;
- commit each completed batch here;
- integrate final production PNGs under `assets/characters/fujiyama/sprites/`;
- do not require playtesting until all 73 frames are integrated.

The generated source art is development-only; `dev_art/.gdignore` prevents Godot from importing it into the game.
