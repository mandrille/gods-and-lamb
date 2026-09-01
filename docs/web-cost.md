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

## What is still unmeasured

- **Frame rate**, desktop or mobile, in a real browser window.
- **Load time on a real connection.** 11 MB is fine on a desktop and is
  15 seconds on a bad 4G link. If that matters, the lever is the engine, not
  the art: a stripped build profile, not a smaller village.
- **Anything on an actual phone.** Fill rate is the ceiling and no desktop
  number predicts it. `rendering/scaling_3d/scale` in `project.godot` is the
  lever when it is measured.
