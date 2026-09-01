# Working on Gods and Lamb as an agent

Read this first. Every `lamb-*` agent shares it; your own definition adds only
its specialism.

**Project:** `C:\Goliath\Gods and lamb` — `blender/` builds the geometry,
`godot/` runs it. Script-generated: primitives + booleans + flat colours, no
textures, no hand modelling, no external assets. Deeper docs live in
`blender/docs/` and `blender/assets/README.md`. Read the one that covers your
task rather than guessing from filenames.

The game: a chill incremental god-game. Tiny autonomous followers generate
Faith; the player spends it dragging Miracle cards onto followers and tiles;
the village drifts toward Utopia or Savage Cult. Web and mobile, low animation
overhead, cute rounded-cube art, vibrant colour.

Much of this pipeline is ported from `C:\Goliath\Robotin`. When something here
looks odd, the reason is usually written down there — but do not assume Robotin's
answer is still ours. Three things are deliberately different:

1. **GL Compatibility, not Forward+.** Godot's web export only runs the
   Compatibility renderer. No volumetric fog, no SSAO, emissives clamped.
   Contact shading comes from **AO baked into vertex colours**, not from a
   screen-space effect.
2. **Nothing has physics.** Followers hop tile to tile on a tween. There are no
   rigidbodies, no colliders, no `rb_col_*`. Do not port collision machinery.
3. **A library, not a diorama.** Each asset exports as its own `.glb` and Godot
   instances it. The village grows during play; it is never a frozen scene.

---

## 1. Nobody owns any file

You may edit whatever the task needs, anywhere in the repo. There are no
per-agent territories and none are to be introduced. This is a standing
decision with a scar behind it: a previous split ("do not edit across this
line") blocked a release pipeline from fixing a version code and shipped a
rival SDK inside a build, because whoever *could* edit the file was not
whoever *noticed*.

The "owns" column in the roster is a **routing hint**, not a fence. It says who
to ask first, not who is permitted.

What replaces ownership is **machine-checked guards**: the asset gate, the
export read-back, the Godot library test. If you are tempted to write a rule
that must be remembered, write a check that runs instead.

**Never weaken a check to make your work pass.** These checks are load-bearing
and each was paid for with a bug. If one fires, it is usually right. If you
genuinely believe a check is wrong, say so in your report and leave it — do not
quietly relax a threshold, widen a tolerance, or delete a case.

## 2. Look before you build

The single most expensive mistake available to you is answering a *shape*
question with a *full sweep*.

| what you want to know | command | cost |
|---|---|---|
| how big is it, exactly | `build.py -- measure <asset_id> [k=v]` | **~2 s** |
| what does it look like | `build.py -- look <asset_id>` | **~2-5 s** (3 angles) |
| what does it look like LIT | `build.py -- lit <asset_id>` | **~3.5 s** (bake + 3 angles) |
| does a floor of it tile | `build.py -- field <asset_id> n=4` | **~5 s** |
| does the whole village hold together | `build.py -- scene` | **~30 s** (renders BOTH ways) |
| does it pass the gate | `build.py -- asset <asset_id>` | **~0.5 s** |
| does EVERY asset pass | `build.py -- assets` | **~45 s** (27 assets, one process each) |
| does the AO bake show | `build.py -- ao <asset_id>` | **~3 s** |
| does a folk rig and walk | `build.py -- rig <folk asset_id>` | **~6 s** (`blender/docs/03-folk-rig.md`) |

Measured on this machine, not inherited. The numbers carried over from the
parent project (~10 s / ~40 s) were far too pessimistic: this project has no
level build, so even the expensive command is half a minute.

That changes the advice rather than removing it. Nothing here is expensive
enough to avoid, so **look at more things, not fewer** -- the failure mode in
this project is not a slow command, it is judging an asset from its triangle
count. The scene render is the one that keeps catching real problems, because
a relationship between two pieces is invisible in a picture of one.

**EEVEE is not the expensive one.** The received wisdom that a lit render costs
40-70x a Workbench one is about *Cycles*. Measured on the island at a matched
1600x1000, three Workbench frames took **2.0 s** and three EEVEE frames took
**2.3 s**, plus **0.4 s** for the AO bake. `-- look` is the shape loop because
it skips the merge and the bake, not because its renderer is cheaper.

**`-- asset` EXISTS and is a real gate.** It collects every fault in one pass:
triangle cap, declared footprint against the measured AABB, the `anchor="floor"`
contract, and ngon/degenerate/zero-edge/loose debris. `-- assets` runs the whole
tree, one process each, and fails once with every failure listed. An asset that
has passed it may be called gated.

What is still missing is the half that runs AFTER the gate: `library`, `export`
and `guards` are named in `build.py`'s PLANNED tuple and exit saying so, so
there is no `verify.py`, no export read-back and no Godot library test. Nothing
you build reaches the engine yet.

Trust `build.py`'s own `TARGETS` and `PLANNED` over any prose — including this
file. This paragraph was wrong for long enough to matter.

Run from `C:\Goliath\Gods and lamb\blender`:

```
blender --background --factory-startup --python build.py -- look Terrain/grass
```

`-- look` renders three Workbench angles into `blender/out/look/` — flat
material colour, no gate, no Godot. **Open the PNG.** A triangle count cannot
tell you that a roof overhangs its own doorway; the first frame can.

**Do not run `-- assets`, `-- library`, `-- export`, or the Godot tools.** The
orchestrator owns integration: one build, one gate, one commit. Eight agents
each starting a full sweep will thrash the machine and make the collect-all
gate useless — its whole value is reporting every failure in a single run.

## 3. Measure, never derive

Assets are built by code and their real dimensions are frequently not what the
arithmetic suggests. Before sizing anything against anything, `-- measure` it.
Sizes derived on paper have cost the parent project multiple rebuild cycles.

## 4. Judge at the game's camera, not at arm's length

This is our version of Robotin's "open the PNG", and it is stricter. Followers
are roughly 40 px tall on a phone. An asset that reads beautifully in a
three-quarter close-up and turns to mush at the play camera has failed, and the
close-up will not tell you. When a shape decision is marginal, look at it at
game distance before keeping it.

Corollary: detail below about 2 cm is invisible and costs triangles. Spend the
budget on **silhouette and hue**, not on surface detail.

## 5. Colour does the work light cannot

Under GL Compatibility there is one directional light and a sky. There is no
ambient occlusion pass to separate two objects that touch. So:

- Adjacent parts must differ in **hue, not value**. Two neutrals of different
  brightness read as one object under the key light.
- Every asset needs at least one saturated hue.
- Everything goes through `soften_all` — the bevel is what catches the key and
  gives an edge its highlight. `assert_soften` measures "went through the
  pass", not "has a bevel".

## 6. Your working copy

**A git worktree when one is available, a directory partition when it is not.**

Worktree isolation requires the SESSION to be running inside a git repository,
and it frequently is not -- Claude Code is often started somewhere else and
pointed at this project by path. When that happens the fallback is a directory
partition: each agent is told which folder it may write to, and it writes
nowhere else. Reading anything is always fine.

The partition is not a territory. Rule 1 still stands: nobody owns a file, and
the partition exists only so three agents writing at the same minute do not
tread on each other. It lasts for one dispatch and then it is gone.

Two things make the partition safe, and a dispatch that skips them is asking
for trouble:

- **New files in distinct folders.** Two agents adding assets under different
  categories cannot collide. Two agents both editing `src/kit.py` can.
- **One writer for the shared files.** `build.py`, `src/` and the palette get
  exactly one agent per dispatch, and that agent is told the others are running
  `build.py` concurrently, so its edits there are single atomic writes made
  late.

In a worktree: commit narrowly with a real message and report the branch. In a
partition: do NOT commit. The orchestrator reviews everything together, runs
the gate, and lands one commit. Never merge to main, never rebase other
people's work, never `git push`.

Read a file before you edit it. Prefer editing an existing builder over adding
a parallel one.

## 7. What to report back

Your final message is the whole of what the orchestrator sees — it is data, not
a conversation. Lead with the outcome, then:

- **what changed** — files, and one line on why each
- **what you verified** — the exact command and its result, not "should work".
  If you did not verify, say that plainly.
- **what you left** — anything blocked, skipped, or that you think is wrong.
  Under-reporting a problem here is worse than the problem.
- **numbers** — tri counts, AABBs, mesh counts. Paste them; don't summarise.

Screenshots you produced: give the path. The orchestrator can open it.

## 8. House style

Follow the surrounding code: comment density, naming, idiom. This codebase
comments *why*, especially where a wrong-looking choice is deliberate and where
a bug was paid for — match that. Do not add a comment restating what the line
does.

## 9. How this file grows

Every trap that costs real debugging time gets written down:

- a bpy-level trap → `blender/docs/02-blender-gotchas.md`
- a trap specific to one kind of asset → that agent's **Traps** section
- a trap two agents have both written down → here, and deleted from both
- a trap that can be machine-checked → `verify.py`, and **not** written in
  prose at all

A rule in prose is a rule someone will forget. Promote it to a check the moment
it is checkable.
