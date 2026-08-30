# Assets

One `.py` per asset. The file builds geometry and nothing else — it does not
place, tag, merge, position or export. The harness does that when it is being
gated; the village does it when the game is running.

Modules whose name starts with an underscore are **excluded from discovery**.
That is how shared helpers live inside this tree: `_kit/` holds them.

## The contract

```python
"""TERRAIN.ground.grass - one village ground tile."""
import os
from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="terrain",          # terrain | nature | folk | building
    family="ground",        # closed vocabulary, src/vocab.py
    variant="grass",        # the (family, variant) pair must be unique
    category=CATEGORY,
    footprint=(1.0, 1.0),   # metres in plan, honest to 2 cm
    anchor="floor",         # origin = the point it stands on
    slots=(),               # optional local points a follower stands on
)

def build(tag, **kw):
    """Parts built at the ORIGIN, standing on z=0. Return a flat list."""
    P = [box(tag + "_Block", (0, 0, 0.5), (1.0, 1.0, 1.0), M["grass"])]
    soften_all(P, width=0.06, segments=2)
    return P
```

- `variant` **must equal the filename**; `category` **must equal the parent
  folder**. The filesystem is the uniqueness guard, and the registry enforces
  it.
- `build()` returns a flat list of parts. One function is the entire interface.
- Objects are namespaced by the `tag` prefix you are handed.

## The order that matters

Inside a builder, always:

1. create geometry with `box` / `cyl` / `torus` / `sphere` / `cone` — these
   produce **sharp** meshes deliberately
2. apply every boolean
3. `soften_all(P)` — bevel and smooth, **last**

Bevelling before a boolean tears the cut edges. This is gotcha #1 and it is the
most common way to produce a visibly wrong asset.

## Families are closed, variants are free

`src/vocab.py` is **generated**. A new **variant** of an existing family costs
nothing. A new **family** costs a vocabulary regeneration, so reuse a family and
take a fresh variant where you can — and flag it rather than spending one if
nothing fits.

## Triangle caps

| cls | cap | drawn |
|---|---|---|
| `terrain` | 400 | hundreds of times, through MultiMesh |
| `folk` | 600 | about 40 px tall on a phone |
| `nature` | 800 | in clumps |
| `building` | 2500 | a handful of times |

Counted on the **evaluated** mesh — an unapplied Bevel is invisible to
`calc_loop_triangles()`. A cap is fixed by fixing the geometry, never by raising
the number.

## Facing

Everything floor-standing fronts **-Y**. Get it wrong and the asset shows the
village its back, which is invisible in a build log and obvious in the first
render.

## Colour

Materials come from `kit.M[...]` by key. Never construct one inside a builder.

Adjacent parts must differ in **hue, not value** — there is no ambient occlusion
pass under GL Compatibility to separate two touching surfaces, and two neutrals
of different brightness read as a single object. Every asset needs at least one
saturated hue.

## Checking your work

```
blender --background --factory-startup --python build.py -- look Terrain/grass
blender --background --factory-startup --python build.py -- measure Terrain/grass
blender --background --factory-startup --python build.py -- asset Terrain/grass
```

`-- look` is the cheap one and it renders three angles. **Open the PNG.** A
triangle count cannot tell you that a roof overhangs its own doorway.
