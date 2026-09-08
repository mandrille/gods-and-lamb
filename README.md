# Gods and Lamb

A chill incremental god-game. Tiny autonomous villagers live their own lives in a
valley; you are the god above them, and the only thing you can do is be kind to
them. Bless a woodcutter the moment she finishes a log and she works a little
harder at it tomorrow. Touch bare dirt and it greens. Touch the grass and
something grows in it. Faith is what belief in you feels like from the inside,
and it is the only currency there is.

**[Play it in a browser](https://mandrille.github.io/gods-and-lamb/)** — desktop
or phone, no install.

Cute rounded-cube art, generated entirely by Python in Blender — no textures, no
hand modelling, no external assets.

---

## What you actually do

- **Touch the world.** Every tree, rock, pond and patch of ground answers. A tree
  drops apples, a rock splits into stone, water turns to wine, dirt turns green.
  A plot arrives as bare desert; the village that grows on it is one you made
  tile by tile.
- **Bless people.** Catch a villager in the few seconds after they finish a job
  and the blessing lands: they gain Faith, and they get better at the thing you
  praised them for. There is no punishment in this game. You are a good god.
- **Watch them believe.** Every villager carries a Faith level of their own, from
  Atheist up through Agnostic, Believer and Adept to Devoted. Their devotion is
  what turns an ordinary day's work into Faith for you.
- **Spend Faith on miracles.** Rain, Grove, Calm, Bounty and the rest are cards
  you hold and sweep across the valley.
- **Answer the world when it takes something back.** Fires spread tree to tree,
  droughts eat grass from the edges in, and a wind walks a line through whatever
  you built. Each has an answer already in the deck — Rain puts out a fire, Calm
  settles a wind — and putting one down earns thanks from every villager at once.
- **Come back tomorrow.** A day is eight minutes and ends at nightfall with a
  summary and one choice: what to leave the village doing overnight. What
  happened while you were gone is waiting when you return.

## Controls

|               | Mouse                      | Touch                      |
|---------------|----------------------------|----------------------------|
| Look around   | drag the ground            | one finger                 |
| Zoom          | wheel                      | pinch                      |
| Turn          | right-drag                 | —                          |
| Bless / touch | click                      | tap                        |
| Cards         | click to arm, click to aim | tap to arm, tap to aim     |
| Menu          | Escape                     | back gesture               |

## Running it from source

Godot 4.7, **GL Compatibility** — not a preference. The web export runs
Compatibility only, and this game ships to web.

```bash
godot --path godot
```

Art is not committed as models. Every asset is a Python program under `blender/`
that builds it from primitives, gated by a build that refuses to ship a mesh over
its triangle cap or a render that is empty.

```bash
cd blender
blender --background --factory-startup --python build.py -- assets
blender --background --factory-startup --python build.py -- library
cd ../godot
godot --headless --path . --import
```

The launchers hardcode the Blender and Godot executables near the top of
`BUILD.bat` — edit those two lines for your machine.

## Tests

There is no unit-test framework. Instead there are ~30 *probes* under
`godot/tools/`, each a headless `SceneTree` that boots the real game, does
something a player would do, and prints what it measured before exiting 0 or 1.

```bash
godot --headless --audio-driver Dummy --script tools/calamity_probe.gd
```

They assert behaviour and design bands rather than implementation — that
engagement is worth roughly five times idling, that the first villager starts
work inside thirty seconds, that a solved fire pays more when it is caught early
than when it is caught late, that nothing on a 720x1280 screen is too small for
a thumb.

## Layout

- `blender/` — asset programs, the build gate, the GLB exporter
- `godot/scripts/` — sim, player, world, ui, save, audio
- `godot/tools/` — the probes
- `docs/GDD.md` — the design
- `AGENTS.md` — what an agent working here reads first
- `CLAUDE.md` — the command list and the non-negotiable rules

## Licence

Not yet chosen. Ask before reusing.
