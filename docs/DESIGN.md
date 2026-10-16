# SAMURAI COP

## Concept

A deliberately cheesy 2D fighting game inspired by
the 1991 Samurai Cop movie (https://en.wikipedia.org/wiki/Samurai_Cop) with B-movie aesthetics.

## Core principles

- funny before realistic
- fast matches
- simple controls
- ridiculous characters
- exaggerated special moves
- playable on phones and browsers

## Initial match structure

Best of 3 rounds.

Each player starts with 100 health.

Rounds are untimed in the early release. A timed-round mode requires separate
timeout and tie-break rules before it can be enabled safely.

## Initial controls

Left
Right
Jump
Crouch
Punch
Kick
Block

## Future controls

Special attacks use directional combinations plus attack buttons.

## Initial fighters

TBD

## Non-goals for first release

- online multiplayer
- ranked matchmaking
- complex physics
- 3D graphics
- advanced story mode

## Character-bound arenas

Campaign and versus matches use the opponent/P2 fighter's `home_arena_id`.
The player character never overrides that selection. `ArenaCatalog` is the
single registry for stage names, production background paths, and optional
visual-only scale, offset, or modulation. If an arena ID or texture cannot be
loaded, the reusable arena scene keeps the match running with its default
background and prints one warning.

| Stage ID | Display name | Home fighter(s) | Production asset |
| --- | --- | --- | --- |
| `stage_01` | Lion Head Room | Jennifer | `assets/backgrounds/stage_01/background.png` |
| `stage_02` | Chief's House | Fujiyama | `assets/backgrounds/stage_02/background.png` |
| `stage_03` | Parking | Frank Washington | `assets/backgrounds/stage_03/background.png` |
| `stage_04` | Outlands | Yamashita, Joe Marshall | `assets/backgrounds/stage_04/background.png` |
| `stage_05` | Outlands 2 | Okamura | `assets/backgrounds/stage_05/background.png` |
| `stage_06` | Police Station | Peggy | `assets/backgrounds/stage_06/background.png` |
| `stage_07` | Hospital | Wild Nurse | `assets/backgrounds/stage_07/background.png` |

Backgrounds are static comic/cel-shaded PNGs generated from the movie stills
under `reference/backgrounds/`; those stills remain source references and are
never loaded at runtime. Final art contains no actors, text, logos, subtitles,
or baked UI. A full-rect `TextureRect` uses aspect-preserving cover scaling, so
the background crops rather than distorts across landscape aspect ratios.
Per-stage presentation metadata may adjust only background scale, offset, or
modulation; it must never change fighter scale, floor collision, arena bounds,
spawn positions, or mobile controls. On touch layouts the background excludes
the reserved bottom control zone.

## Campaign ladder preview

After character selection and after each campaign victory, the reusable
`CampaignLadder` screen reads the already-generated opponent order and current
fight index from `GameSession`. It displays all seven opponents, marks defeated
fighters, highlights the next opponent, and positions the player's portrait at
the current step. The preview is visual only and advances to the arena after
four seconds; opponent ordering and campaign progression remain authoritative
in `GameSession`.

After the seventh opponent is defeated, the match flow opens a four-second
campaign-completion reward screen instead of returning directly to character
selection. It uses the cel-shaded production illustration at
`assets/ui/campaign_complete/finish.png`, then clears campaign state and starts
again at character selection.
