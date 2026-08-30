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
| what does it look like | `build.py -- look <asset_id>` | TBM (~40 s expected) |
| how big is it, exactly | `build.py -- measure <asset_id> [k=v]` | TBM (~10 s expected) |
| does it pass the gate | `build.py -- asset <asset_id>` | TBM (~30 s expected) |
| does everything still build | `build.py -- assets` | minutes |

"TBM" is to-be-measured. The expectations are Robotin's numbers, carried over
as a guess. Replace each one with our own the first time you run it — a cost
table nobody has measured is a rumour.

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

Agents that write code are dispatched into **their own git worktree**. Work
there freely and commit narrowly with a real message. The orchestrator merges,
runs the gate and lands it. Do not merge to the main branch, do not rebase
other people's work, and do not `git push`.

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
