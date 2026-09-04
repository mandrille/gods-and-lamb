# PC first, then price it for web

The working rule, from 2026-09-01:

> Make the change for **PC**. Get it right there. Then run `RUN web`, read the
> size report, and decide whether the change is affordable — cut it or keep it.

Not "build for web and hope it works on PC", and not "build for PC and find out
about web at the end". Desktop is where the change gets judged as *art*; the web
build is where it gets judged as *cost*, and those are two separate questions
asked in that order.

## What a web build actually costs, measured

`RUN web` on the first complete build, 2026-09-01:

| file | raw | gzip | what it is |
|---|---|---|---|
| `index.wasm` | 38 MB | **9.7 MB** | the Godot engine |
| `index.pck` | 569 KB | **526 KB** | the entire game: 27 GLBs, every script, the layout |
| `index.js` | 274 KB | 67 KB | the JS loader |
| `index.html` | 5.4 KB | 2.2 KB | the shell |
| **total** | **39 MB** | **11 MB** | |

Gzip is the number that matters; any server worth using sends the wasm
compressed, and it compresses about 4:1.

**The engine is 88% of the download and it is fixed.** Our entire game — all the
geometry, all the code, the whole village layout — is **5%** of what a player
waits for.

## What that means for a change

It means the intuition to fear is the wrong one. "Will this art blow the
download budget" is almost always **no**: the pck would have to grow by an order
of magnitude before it rivalled the engine. A new building is a few tens of KB.
Doubling the asset library would still leave the engine dominant.

So judge a change against **`index.pck`, not the total**. A change that adds
40 KB to the pck has moved the download by 0.4%, and arguing about it is
arguing about the wrong axis.

The costs that ARE worth arguing about, in the order they will bite:

1. **Draw calls and fill rate**, not bytes. GL Compatibility on a phone is
   fill-bound long before it is vertex-bound. The ground already goes through
   `MultiMeshInstance3D` — 3255 tiles in 6 batches — because 3255 nodes would
   not survive. Anything that breaks batching is expensive in a way the size
   report will never show you.
2. **Per-frame script work.** An idle game can have a hundred followers on
   screen. `follower.gd` is a lerp and a rotation on purpose; there is no
   physics body and no navigation agent anywhere.
3. **Skinned meshes.** Each rigged follower is a pose evaluation per frame.
   Seven bones is cheap; the number of followers is the thing to watch.
4. **Anything requiring cross-origin isolation.** The web preset is built
   `thread_support=false` deliberately: a threaded build needs the server to
   send COOP/COEP headers, and without them the page does not start at all —
   which rules out itch.io, plain static hosting, and just opening the file.
   Turning threads on is not a performance tweak, it is a hosting decision.

## The loop

```
RUN            build anything stale, then play on PC
RUN test       headless checks before you trust a build
RUN shots      screenshots, with a stale-frame guard
RUN web        web build + the size report above
RUN serve      the same, served at http://localhost:8712
```

Verified 2026-09-01: the web build loads and renders in a browser with no
console errors, same scene as desktop — village, river, bridge, lit, followers
walking. Frame rate was NOT measured: the automation pane throttles
`requestAnimationFrame` when it is not visible, so any number from it would be
made up. Measure it in a real window before quoting one, and measure it on a
real phone before believing it.

## A worked example, 2026-09-01

One session added: 2.25x the land (64x48 -> 96x72 tiles, 7338 ground tiles),
drag-pan and zoom, hover and click picking, a particle system, depth fog and
glow, an escape menu with four tabs of live controls, settings persistence, a
stress spawner, touch input and a portrait configuration.

    before   index.pck  538,528 gzip     TOTAL 10,721,113 gzip
    after    index.pck  581,566 gzip     TOTAL 10,764,150 gzip
    delta               +43,038          +0.4% of the download

**Everything in that list cost 43 KB.** More than doubling the world cost
nothing measurable, because the ground is data in `vale.json` and instanced
from meshes that already shipped. The particle system added no textures at all
-- its emission points are a small generated RGBF strip and its puff is drawn
in code.

This is the shape the answer usually has. If a change ever DOES move the pck by
megabytes, it will be because something started shipping bitmaps, and that is
worth a conversation. Geometry and code are not.

What that session cost where it actually matters, measured rather than
guessed: **3 draw calls** for the whole village's particles regardless of prop
count, and **+0.002 ms/frame** for the 500-particle simulation on a desktop
GPU -- below the noise floor there, and untested on a phone, which is where
alpha billboards are expected to bite.

## A second worked example, 2026-09-01

One session added: a full walkability grid over 6,912 cells with A*, per-prop
footprint blocking, a needs-driven brain per follower, a connected-region flood
fill, two new headless probes, and a rewrite of how settings persist.

    before   index.pck  581,566 gzip     TOTAL 10,764,150 gzip
    after    index.pck  593,505 gzip     TOTAL 10,776,089 gzip
    delta               +11,939          +0.11% of the download

**All of the simulation groundwork cost 12 KB.** It is pure code and one extra
field per prop in `vale.json` (the declared footprint), which is exactly the
cheap half of the axis — the pck grew by 2%, the download by a tenth of a
percent.

What it costs where it matters is a different question and is NOT answered by
this number: A* runs once per follower per errand, not per frame, and the grid
is a `PackedByteArray` of 6,912 bytes built once. The thing to watch is
follower count, which is being measured separately.

## The one that made the download smaller, 2026-09-01

Folding the two skinned folk assets from 8 and 11 surfaces down to 1 each, and
setting the vertex-colour flag at load:

    before   index.pck  593,505 gzip
    after    index.pck  591,641 gzip
    delta               -1,864

A **5.2x** cut in per-follower frame cost that also shrank the download,
because eight materials collapsed into one and the colour they carried moved
into a vertex channel (COLOR_0). That channel was shared with an AO bake at the
time; the bake was removed on 2026-09-04 and the fold, which is what actually
bought the 5.2x, kept the channel to itself.

Worth stating plainly, since it cuts against the usual shape: **the axis that
mattered here was not bytes at all.** Nothing in this size report would ever
have found it. The measurement that did is in `godot/tools/perf_followers.gd`,
and it needed a WINDOWED run -- `--headless` uses the dummy rendering driver
and reports every draw call and GPU millisecond as zero.

## The gameplay slice, 2026-09-01

Sixteen systems: needs and stats, personality, memory, thoughts, morality,
work and a village ledger, conversations, a procedural archipelago you buy
with Faith, a miracle deck, blessing, punishment, area wrath, the whole UI,
one-shot FX, nine sounds and three new animation clips.

    before   index.pck  591,641 gzip     TOTAL 10,774,225 gzip
    after    index.pck  676,648 gzip     TOTAL 10,859,233 gzip
    delta               +85,007          +0.79% of the download

**85 KB for the entire game.** Two things kept it there, and both were
deliberate:

- **The sounds are generated, not shipped.** Nine effects, built from a few
  hundred samples of arithmetic at startup, in `scripts/audio/sfx.gd`. A
  modest set of .wav files would have been a megabyte -- twelve times the cost
  of everything else in this batch put together, and by far the most expensive
  thing in the project.
- **The world is generated, not authored.** The archipelago is a function, so
  nine islands cost the same as one. What grew instead was the GLB library
  (three extra animation clips per folk asset, +26 KB across the two of them),
  which is the honest price of item 14.

The three new animations are the only part of this batch that is really
*content*, and they are also the only part that scales with how much more of
it we make. Everything else is code.

## What is still unmeasured

- **Frame rate**, desktop or mobile, in a real browser window.
- **Load time on a real connection.** 11 MB is fine on a desktop and is
  15 seconds on a bad 4G link. If that matters, the lever is the engine, not
  the art: a stripped build profile, not a smaller village.
- **Anything on an actual phone.** Fill rate is the ceiling and no desktop
  number predicts it. `rendering/scaling_3d/scale` in `project.godot` is the
  lever when it is measured.
