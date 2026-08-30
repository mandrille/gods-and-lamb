# Gods and Lamb

A chill incremental god-game for web and mobile. Tiny autonomous followers
generate Faith; you spend it dragging Miracle cards onto them; the village
drifts toward Utopia or Savage Cult.

Cute rounded-cube art, generated entirely by Python in Blender — no textures, no
hand modelling, no external assets.

- `blender/` builds the geometry, one `.py` per asset, gated by a build that
  refuses to ship a mesh over its triangle cap or a render that is empty.
- `godot/` runs it. Godot 4.7, GL Compatibility, exporting to web and Android.
- `docs/GDD.md` is the design.
- `AGENTS.md` is what an agent working here reads first.
- `CLAUDE.md` is the command list and the non-negotiable rules.

## Quick start

```
cd blender
blender --background --factory-startup --python build.py -- assets
blender --background --factory-startup --python build.py -- library
cd ../godot
godot --headless --path . --import
```

The launchers hardcode the Blender and Godot executables near the top of
`BUILD.bat` — edit those two lines for your machine.
