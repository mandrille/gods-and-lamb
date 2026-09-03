# Content batch — the shared spec every author works from

Read `C:\Goliath\Gods and lamb\AGENTS.md` and `blender\assets\README.md` first.
This file is the batch's contract: ids, families, footprints, colourways, references,
and what you may and may not touch. Paths are plain, never links.

## Commands (run from `C:\Goliath\Gods and lamb\blender`)

```
set LAMB_VOCAB_OPEN=1        (PowerShell: $env:LAMB_VOCAB_OPEN="1")
blender --background --factory-startup --python build.py -- look    <Category/variant>
blender --background --factory-startup --python build.py -- measure <Category/variant>
blender --background --factory-startup --python build.py -- asset   <Category/variant>
blender --background --factory-startup --python build.py -- rig     <Category/variant>   (folk + animals only)
```

`LAMB_VOCAB_OPEN=1` is REQUIRED for this batch: six families are new and the vocab is
regenerated once by the orchestrator at the end. Do NOT run `-- vocab`, `-- assets`,
`-- library`, `-- export`, and touch nothing under `godot/`.

`-- look` writes `out/look/<Category>_<variant>_{front,three_quarter,along}.png` in
seconds. **Iterate against the play camera**: a villager is ~1.1 m and ~40 px tall in
play; a building is seen from ~30 m up at ~35°. If it does not read at that size it
does not read. Post the PNG paths in your report.

## The style (all references are clay/plasticine, chibi)

Chunky, bevelled, saturated, few big masses. Silhouette first, colour last. The
existing idiom: build sharp primitives → booleans → `soften_all(hero, width=…,
segments=2)` on the 2–3 masses that carry the silhouette, `soften_all(plain,
width=0.0)` on everything else. Weighted normals are added by the harness — never
call `weighted_normals_all` yourself. Materials are `kit.M[...]` keys only; colourways
are `kit.scheme(key)` keys only. Both are already registered — if a key you want is
missing, use the nearest and FLAG it, do not edit `src/kit.py`.

New materials this batch: `adobe tile_blue tile_green shingle iron_dark ember`.
`ember` is the wolf's eyes and nothing else.

## Shared files you may NOT edit

`src/kit.py`, `src/vocab.py`, `src/registry.py`, `build.py`,
`assets/_kit/folkrig.py`, `assets/_kit/critterrig.py` — all pre-edited. Every part
name you need is already claimed (see the rig section). Another author's files are
off limits too; the table below says who owns what.

## References — `blender/refs/`

characters/: `Clay_bard_playing_lute`, `Clay_builder_carrying_hammer` (leather cap,
hammer + rock — this is the BUILDER), `Clay_cow_standing`, `Clay_hunter_carrying_bow`,
`Clay_lamb_and_sheep`, `Clay_lumberjack_holding_axe`, `Clay_nurse_standing`,
`Clay_priest_holding_book`, `Evil_clay_wolf_with_glowing` (THE wolf: dark, red eyes,
teeth, crouched). `Clay_wolf_standing` is a friendly dog — ignore it. There is no miner
reference: same body, a dark cap/helm, a pick over the shoulder, an ore sack.

buildings/: `Clay_blacksmith_forge_with_anvil`, `Clay_cottage_house_architectural`
(the regular HOUSE), `Clay_medieval_church_building`, `Clay_medieval_hotel_architecture`,
`Clay_medieval_tavern_inn_building`, `Clay_mine_shack_entrance`,
`Clay_warrior_barracks_architecture`, `Clay_windmill_tower_sculpture`,
`Clay_woodcutter_hut_architectura` (LUMBER CAMP), `Medieval_clay_farm_barn`,
`Medieval_clay_mansion_architecture`.

Adapt to OUR scale and simplicity: a reference has fifty details, an asset gets the five
that survive at 15 px — one door, one or two windows, one roof, one identifying prop.

## Humans — one body, seven jobs

`assets/_kit/folkbody.py` (owner: folk-A) is the ONLY human body. Proportions come from
`Folk/villager.py` verbatim (head 0.34×0.30×0.32 at z 0.46; tunic 0.24×0.19×0.26 at
z 0.22; arms at x ±0.152 from z 0.450 to 0.229; legs at x ±0.066 from z 0.210; head top
0.780). folkbody exports `SKELETON` built from those constants and folkrig imports it.

API:
```
body(tag, palette, hair="cap"|"curly"|"topknot"|"beard"|"none",
     apron=True, kerchief=True, hands="level"|"staff") -> (hero, plain)
finish(hero, plain, extra_hero=(), extra_plain=()) -> list     # the two soften passes
anchors: HAND_R HAND_L CHEST BACK HIP_L HIP_R BROW CROWN BELT  (xyz tuples)
palette keys: skin hair tunic sleeves apron kerchief boots legs  -> kit.M keys
```
Hair styles emit `_Hair*` names (claimed by the rig's `_Hair`). Villager and adventurer
are migrated onto it — that migration is the regression test: `-- measure` on both
must still read ~0.40×0.35 (±2 cm) and `-- rig` must pass.

A job file (owners: folk-B, folk-C) is ~40 lines: docstring, ASSET (`cls="folk"`,
`family="folk"`, footprint MEASURED — a bow or axe head pokes out, write the honest
number), a palette dict, a `build()` of 6–12 lines that calls `body(...)` and adds 2–4
plain props at the anchors, then `finish(...)`. Cap 600 tris. Rig part names
available (substring-matched, first hit wins):

| Bone | Names |
|---|---|
| ArmR | `_ArmR _HandR _Staff _Axe _Hammer _Bottle _Pick` |
| ArmL | `_ArmL _HandL _Bow _Book _Rock` |
| Torso | `_Tunic _Apron _Vest _Hem _Strap _Pack _Bedroll _Lute _Satchel _Belt _Pouch _Stole _Quiver _Rope _Emblem _Cassock _Sack` |
| Head | `_Head _Hair _Eye _Kerchief _Sprig _Beard _Cap _Hood _Veil _Brow _Leaf _Helm` |
| LegL/R | `_LegL _BootL` / `_LegR _BootR` |

Held tool → the hand that holds it. Slung/two-handed → Torso. Unclaimed name = hard
fail.

| Job | Hair | Palette (tunic / apron / kerchief) | Props |
|---|---|---|---|
| priest | cap, `hair_warm` | `stone` cassock (`_Cassock` over tunic) / none / none | `_Stole` white slab with dots (two thin `wool` strips), `_Book` in HandL (open, `plaster` + `wood_dark`) |
| lumberjack | beard (`_Beard` big slab + curly `_Hair`) | `cloth_green` / none / none | `_Rope` belt, `_Axe` in HandR (wood haft, `stone_dark` head) |
| miner | none, `_Helm` dark cap | `leather` / none / none | `_Pick` over HandR, `_Sack` on hip, `_Belt` |
| builder | none, `_Cap` leather cap with stitch | `sand` tunic / none / none | `_Hammer` HandR (`stone` head), `_Rock` HandL, `_Belt` with `_Pouch` |
| hunter | topknot (`_Hair` bun), `_Brow` | `cloth_green` hooded (`_Hood` collar) / none / none | `_Bow` HandL (thin curved: 3 boxes), `_Quiver` on back, `_Pouch` ×2 |
| nurse | none, `_Veil` (wimple: cap + two side slabs, `wool`) | `plaster` dress (tunic longer, no legs visible: `_Hem`) / none / none | `_Emblem` green sprig on chest (`leaf`), `_Satchel`, `_Bottle` HandR |
| bard | curly + `_Leaf` (`leaf`) | `cloth_orange` / `cloth_blue` patch / none | `_Lute` on Torso (body `plaster` + `wood_dark` neck, 3 `petal_*` pegs), `_Satchel` |

## Animals (owner: animals)

| Id | Family | Rig | Footprint | Notes |
|---|---|---|---|---|
| Animals/wolf | `predator` (NEW) | critterrig | ~0.42×1.05 | Crouched: body low, head forward of the shoulders. `_Body _Neck _Rump`, `_Tail1.._Tail3` (segmented), `_Head _Muzzle _Snout _Ear* _Brow`, `_Eye*` in **`ember`**, `_Fang` (2–4 tiny `wool` wedges), `_Ruff` at the shoulders, `_LegXX` + `_PawXX`. Colours: `hair_dark` body, `wood_dark` underside. Clips: call `critterrig.all_actions` as-is (graze is never played). |
| Animals/lamb | `livestock` | critterrig | ~0.26×0.55 | ~55% of the sheep, ONE bevelled `_Body` box (no fleece balls), `_Head` `wool`, dark `_LegXX` + `_HoofXX`. |
| Animals/sheep, cow | existing | — | — | Touch-ups ONLY if the play-scale read improves and the gate stays green (sheep: face + darker legs; cow: `_Patch` boxes, small `_Horn`). No re-topology. |

## Buildings

`cls="building"`, `anchor="floor"`, cap 2500, footprint MEASURED (rotated roof slabs
reach past the arithmetic). All ≤ 2.5 m in plan. Costs are engine-side; ignore.

| Id | Owner | Status | Family | Footprint target | Scheme |
|---|---|---|---|---|---|
| Buildings/hut, hut_b | A | REDO to the house ref (id kept) | house | 1.7×1.5 | house_terracotta / house_plaster |
| Buildings/cottage, cottage_b | A | REDO, the larger house | house | 2.2×1.9 | cottage_red / cottage_blue |
| Buildings/shrine | A | REDO to the CHURCH ref (id kept: bell tower + cross, blue arched windows) | shrine | 2.4×1.8 | church_tile |
| Buildings/mansion | A | new (tall, balconies, domed tower) | house | 2.5×2.2 | mansion_teal |
| Buildings/tavern | A | new (cream cube, orange tiles, hanging sign, glowing windows) | inn (NEW) | 2.0×1.7 | tavern_cream |
| Buildings/hotel | A | new (3 storeys half-timbered, balcony, sign) | inn | 2.2×1.8 | hotel_timber |
| Buildings/lumber_camp | B | new (log cabin, water wheel, log pile) | works (NEW) | 2.4×2.0 | lumber_log |
| Buildings/mine | B | new (rock block, timber entrance, ore pile, attached hut) | works | 2.2×2.0 | mine_rock |
| Buildings/smithy | B | new (adobe, arched forge + `warmglow`, chimney, anvil) | works | 2.0×1.8 | smithy_adobe |
| Buildings/barracks | B | new (crenellated keep, gate, shield + spears, flag) | keep (NEW) | 2.4×2.4 | barracks_terracotta |
| Buildings/farm, farm_b | B | new (low barn + fenced crop rows) | farm (NEW) | 2.5×2.5 | farm_red / farm_green |
| Buildings/windmill | B | new (stone tower, conical roof, four sails on −Y) | mill (NEW) | ≈2.2×1.2 | windmill_stone |

Multi-instance buildings (hut, cottage, farm) share a builder in `assets/_kit/bld_<name>.py`
with `build(tag, scheme_key)`; the variant files are ~25 lines each (ASSET + one call).
Singletons are one file each calling `kit.scheme(key)` directly. Roof tiles are a few
wide boxes, never per tile; sails and balconies at `segments=2`. Mansion, church and
windmill are the cap risks.

## Report format

Per asset: id, measured footprint, tri count / cap, gate result, `-- rig` result (if
rigged) with clip names, the three PNG paths. Then: anything you had to flag (a missing
material/anchor, a family you were unsure of), in one line each.
