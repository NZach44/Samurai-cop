# SAMURAI COP — Codex Instructions

## Project

This is a small 2D fighting game built with Godot 4.7 using GDScript.

Primary targets:

1. Desktop development
2. Web browser
3. Android phones

The game should remain lightweight and suitable for inexpensive Android hardware.

## Development philosophy

Build the smallest working implementation first.

Do not introduce unnecessary abstractions, plugins, frameworks,
external dependencies, or complicated architecture.

Prefer built-in Godot functionality.

Do not add third-party addons without explicitly asking first.

## Game architecture

The game is a 2D one-on-one fighting game.

Core concepts:

- Fighter
- Fighter state machine
- Input handling
- Hitboxes
- Hurtboxes
- Moves
- Health
- Rounds
- Character data
- Arena
- UI

Fighters should share one reusable fighter framework.

Do not duplicate complete fighter scripts per character.

Character-specific properties should eventually be data-driven.

## Coding rules

Use GDScript only.

Target Godot 4.7 APIs.

Use typed GDScript where practical.

Prefer small scripts with clear responsibilities.

Use descriptive variable and function names.

Avoid deeply nested logic.

Comment why something exists, not obvious syntax.

Do not perform large refactors unless requested.

## Scene rules

Prefer reusable scenes.

Suggested structure:

scenes/fighters/
scenes/arenas/
scenes/game/
scenes/ui/

Scripts belong under scripts/.

Game data belongs under data/.

## Combat rules

Combat should eventually support:

- idle
- walk
- crouch
- jump
- attack
- block
- hit stun
- knockdown
- KO

Do not implement all states at once.

Implement only what the current task requires.

Hit detection should use dedicated hitboxes and hurtboxes rather
than relying on visual sprite bounds.

## Target devices

Keep web and Android compatibility in mind.

Avoid platform-specific functionality unless necessary.

Avoid large textures and unnecessary memory allocation.

Do not assume keyboard-only input.

Input actions must use Godot Input Map so touch controls can later
map to the same actions.

## Workflow

Before changing code:

1. Inspect the relevant files.
2. Explain briefly what you intend to change.
3. Make the smallest change that solves the task.

After changing code:

1. Check for parser errors.
2. Run any available Godot validation/test command.
3. Summarize changed files.
4. Mention anything that needs testing manually inside Godot.

Never silently rewrite large parts of the project.

## Safety

Do not delete scenes, assets, or resources unless explicitly requested.

Do not modify export signing credentials.

Never put credentials or API keys into the repository.

Do not commit generated builds.

## Current milestone

Two placeholder fighters must be able to:

- appear in one arena
- walk
- face each other
- punch
- receive damage
- lose health
- reach KO

No combos, special moves, character art, online multiplayer,
AI-generated content, or advanced menus are required yet.
