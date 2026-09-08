# Shipping the web build

The game is live at **https://mandrille.github.io/gods-and-lamb/**, served from
the `gh-pages` branch of `mandrille/gods-and-lamb`.

## Why it works on plain static hosting

The web preset has `variant/thread_support=false`. A threaded Godot web build
needs the server to send `Cross-Origin-Opener-Policy` and
`Cross-Origin-Embedder-Policy`, and GitHub Pages cannot set headers at all — the
page would fail to start, with no useful error. Single-threaded costs us one
core, and for a game whose per-frame work is a few hundred transforms that is
the right trade. The same property is what lets the build run on itch.io,
playgama, crazygames, or a file server.

Measured on the deployed site: `index.wasm` is 39.5 MB on disk and **10.2 MB
over the wire** — GitHub Pages gzips it and reports `Content-Encoding: gzip`
without being asked. `index.pck` is 1.5 MB. Nothing else is over 300 KB.

## Deploying

```bash
cd godot
godot --headless --export-release "Web" "$PWD/builds/web/index.html"
```

Then push those files to `gh-pages`. A detached worktree keeps it off `master`,
which is why the branch has no source in it at all:

```bash
git worktree add --detach /tmp/pages
cd /tmp/pages && git checkout gh-pages
cp "$OLDPWD/godot/builds/web/"index.* .
rm -f *.import && touch .nojekyll
git add -A && git commit -m "Web build" && git push
```

`.nojekyll` matters: without it GitHub's Jekyll step ignores files it does not
recognise, and the build is mostly files it does not recognise.

## The phone

`display/window/stretch/mode` is `canvas_items` and the aspect is `expand`, so
the canvas fills whatever shape the browser gives it. What that does NOT do is
make the UI the right *size*: the project draws its UI in a 720-unit-wide space,
and a 375 pt handset maps those 720 units onto 375 points, so every control lands
at half size. `vale_root._apply_ui_scale` sets `content_scale_factor` on the
window when it is taller than it is wide, which deals the UI out in ~400 units
instead — the 3D still renders at the window's full resolution.

Below 520 units the HUD also *rearranges*: the day clock takes the full first
row instead of floating centred over the ledger, the Commune and Wrath buttons
become a row above the card hand instead of a column beside it, and the boon
draft turns its three cards into three full-width rows.

`tools/phone_probe.gd` holds all of this. It sizes the window to 750x1624 (a
375x812 handset at 2x), lets the game pick its own scale, and then asserts that
nothing overlaps, nothing hangs off the edge, no tap target is under 44 units,
every modal fits, a real `InputEventScreenTouch` selects a villager, and two
fingers zoom.

Things it found that nothing else would have:

- `Overhead._unhandled_input` handled `InputEventMouseButton` only, so a finger
  could never select or bless a villager. The project sets
  `emulate_mouse_from_touch`, which is exactly what hid it — the emulation drove
  the HUD and the camera, so everything *else* answered a tap.
- Selecting a villager consumed that press, so the camera rig never counted that
  finger and a pinch starting on a person did not zoom. Finger bookkeeping now
  happens in `_input`, before anything can consume it; only the gestures are
  decided in `_unhandled_input`.
- The nightfall panel is 460 units wide, which is wider than the whole screen.
