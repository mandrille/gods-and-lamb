# Gods and Lamb — design

A chill, text-and-systems-heavy incremental god-game for web and mobile, with
low animation overhead. The player is a deity influencing an autonomous
population of tiny followers through a hand of cards — the Miracle Deck. The
village culture shifts dynamically toward a peaceful Utopia or a chaotic Savage
Cult depending on what the player rewards.

## Core loop

```
[Autonomous followers generate Faith]
            |
            v
[Player plays Miracle cards from hand]
            |
            v
[Simulation resolves trait-driven interactions]
            |
            v
[Town morality & population expand] --> [Draft new Miracle cards]
            |
            v
[Set persistent Aura / idle task, close app] --> [Process Away Log]
```

## 1. Autonomous follower simulation

Low art overhead by design. Depth is expressed through thought bubbles, text
chat logs and stat graphs, not animation.

- **Trait matrix.** Followers spawn with binary and qualitative personality
  traits — Generous/Greedy, Docile/Aggressive, Devout/Heretic.
- **Autonomous behaviour.** Followers fulfil basic needs (eating, resting),
  interact socially, and trigger moral dilemmas — a Greedy follower steals from
  the community apple store, and now the player has a decision to make.

## 2. The dual-alignment morality engine

A global meter runs from **Order / Utopia (+100)** to **Chaos / Cult (-100)**.

- **Good god path.** Punishing antisocial behaviour and rewarding cooperation
  increases follower safety, producing steady, compounding Faith and peaceful
  community building.
- **Evil god path.** Rewarding aggression, fear and sacrifice turns followers
  into savages who respect raw power, producing massive burst Faith through
  dominance rituals and fighting pits.

## 3. The Miracle Deck

- **Hand management.** A static hand of 3-4 cards along the bottom of the
  screen.
- **Drag-and-drop casting.** Dragging a card onto a follower or a terrain tile
  spends Faith, executes the miracle, and immediately draws a replacement.
- **Card types.**
  - *Direct interventions* — Lightning Bolt (smite / clear land), Bountiful
    Rain (grow crops / extinguish fire).
  - *Social modifiers* — Whisper of Doubt (provoke conflict / spark remorse),
    Inspiration (spawns a building project).
  - *Persistent auras* — long-duration modifiers slotted before closing the
    app: Aura of Fertility, Blood Moon.
- **Roguelite drafting.** Population milestones trigger a pick-one-of-three
  draft that expands and customises the deck.

## 4. Session pacing

| phase | timeframe | what the player does |
|---|---|---|
| Triage & harvest | 0-2 min | read the Away Log (a narrative summary of offline drama), collect the offline Faith cap |
| Active intervention | 2-7 min | respond to live dilemmas, play cards onto followers, draft new cards at milestones |
| Offline setup | 7-10 min | queue multi-hour passive miracles — Persistent Rain, shrine construction — to set up the next idle cycle |

## Art direction

Cute, chill, vibrant. The world is built out of cubes with rounded edges. Simple
assets, strong saturated colour, beautiful lighting.

Constraints that follow from shipping on web:

- Godot's web export runs **GL Compatibility** only. No volumetric fog, no
  SSAO, clamped emissives.
- So contact shading is **ambient occlusion baked into vertex colours** in
  Blender, multiplied into albedo. Free on every device.
- One warm directional light with soft shadows, plus a cool gradient sky for
  ambient fill.
- Adjacent surfaces separate by **hue, not value** — there is no AO pass to do
  it for us.
- Followers are RIGGED as of 2026-08-31: a 7-bone skeleton and a walk cycle,
  built by `blender/assets/_kit/folkrig.py` and documented in
  `blender/docs/03-folk-rig.md`. This reverses the original "unrigged, low
  animation overhead" line on the owner's say-so. Nothing ELSE is animated:
  terrain, buildings and plants are static meshes and stay that way, and the
  rig has not been carried into Godot yet.
- Terrain instances through `MultiMeshInstance3D`; per-instance tint carries
  neighbour-aware darkening that baked vertex AO cannot know about.

Portrait first: the 3D village occupies roughly the top 60% of a phone screen,
the card hand sits along the bottom. Desktop gets a wider framing of the same
scene.

## Milestones

**M1 — art vertical slice (current).** The Blender pipeline, the asset gate, the
terrain / building / nature / folk kits, the Godot library loader, and a web
export that loads. No simulation.

**M2 — systems.** Followers, needs, traits, Faith, the alignment meter, the
Miracle Deck, the Away Log. The reference implementation to read first is
`C:\Goliath\simulation\src` — a Dwarf-Fortress-style living-world sim already
written in TypeScript, with the tick loop, task queue, trait-driven agents,
chronicle and seeded RNG this game needs.
