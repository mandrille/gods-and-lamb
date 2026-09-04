"""BUILDING.keep.barracks - a crenellated terracotta keep with a timber gate.

First and only building in the `keep` family (new this batch, alongside
`works`, `farm` and `mill`). A garrison building reads differently from a
house at fifteen pixels for exactly one reason: the toothed roofline. Get the
merlon ring right and everything else -- the gate, the shield, the spears --
is a bonus the three-quarter shot rewards but the far shot does not need.

Sized as the village's biggest footprint on purpose: a keep should dominate,
not sit smaller than the hut it is meant to tower over. The first pass of
this file measured 1.10 x 1.11 -- smaller than the hut's 1.67 x 1.44 -- and
that is a scale bug, not a style choice; a follower is 0.855 m tall and every
dimension here is set against that, not against the earlier draft.

The merlons are placed at even spacing along each of the four top edges
rather than modelled as one notched ring, because a notched ring is a
boolean-cut band and a row of small boxes is free-standing geometry that
costs the same triangles either way and cannot self-intersect.

The roof patch is a SMALL gable sitting on the back half of the flat top, not
a roof spanning the whole plan -- the reference shows exactly that: a keep is
mostly parapet, with just enough pitched roof to keep the rain out of the
stair down. It springs from the tower's own top face, so it needs no gable
cutters of its own; there is no wall above it to punch through.

Fronts -Y: the gate, the shield and the spears are all on the south wall.
"""
import os

from kit import M, box, cyl, boolean, scheme, gable_roof, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="keep",
    variant="barracks",
    category=CATEGORY,
    # MEASURED. The flag is the single highest point and the merlons are the
    # single widest, and neither is predictable from the tower box alone.
    footprint=(2.36, 2.38),
    anchor="floor",
    slots=(),
)

KW, KD, KH = 2.35, 2.15, 1.42   # taller than the cottage's 1.68 m total once
                                 # the merlons and flag stack on top

MW, MH = 0.22, 0.25             # merlon footprint -- roughly a follower's
                                 # shoulder width, so the tooth reads as
                                 # castle-scale rather than garden-wall scale
N_EDGE = 5                      # merlons per top edge

RW2, RD2 = 1.15, 0.92            # the small back-half roof patch
RRISE2, ROVER2, RTHICK2 = 0.42, 0.09, 0.08
RCY2 = 0.30                     # offset back from centre, toward -Y is front

GATE_W, GATE_H = 0.62, 1.00     # ~1.0 m so a 0.855 m follower walks in clear
GATE_DEPTH = 0.24

FLAG_X, FLAG_Y = -KW * 0.5 + 0.09, -KD * 0.5 + 0.09
FLAG_H = 0.75

SHIELD_X = KW * 0.5 - 0.62
SPEAR_XS = (KW * 0.5 - 0.34, KW * 0.5 - 0.26)


def _edge(length, margin, n):
    if n <= 1:
        return [0.0]
    span = length - 2.0 * margin
    return [-span * 0.5 + span * i / (n - 1) for i in range(n)]


def build(tag="BARRACKS", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "barracks_terracotta"))
    hero, plain, merlons = [], [], []

    tower = box(tag + "_Tower", (0, 0, KH * 0.5), (KW, KD, KH), body)
    boolean(tower, box("gate_cut",
                       (0, -KD * 0.5 + GATE_DEPTH * 0.5, GATE_H * 0.5),
                       (GATE_W, GATE_DEPTH * 2.0, GATE_H), None))
    boolean(tower, cyl("gate_round",
                       (0, -KD * 0.5 + GATE_DEPTH * 0.5, GATE_H),
                       GATE_W * 0.5, GATE_DEPTH * 2.0, None, axis="Y",
                       verts=12))
    hero.append(tower)

    # Centred slightly above half its own height, not exactly at it -- a box
    # sized to 0.85 of the gate height and centred at 0.42*GATE_H put its own
    # floor at -0.005, the same off-by-a-margin the spears needed fixing too.
    plain.append(box(tag + "_GateDark",
                 (0, -KD * 0.5 + GATE_DEPTH, GATE_H * 0.44),
                 (GATE_W - 0.03, 0.05, GATE_H * 0.85), M["hollow"]))

    # Stone surround -- a hue break against a terracotta body that a WOOD
    # trim (this scheme's jamb colour everywhere else) could not give it, and
    # castle gates read as stone-framed even in clay.
    fy = -KD * 0.5 - 0.022
    for sx in (-1, 1):
        plain.append(box("%s_Jamb%s" % (tag, "L" if sx < 0 else "R"),
                     (sx * (GATE_W * 0.5 + 0.045), fy, GATE_H * 0.5),
                     (0.09, 0.08, GATE_H), M["stone"]))
    arch = cyl(tag + "_ArchTop", (0, fy, GATE_H), GATE_W * 0.5 + 0.075, 0.08,
               M["stone"], axis="Y", verts=14)
    boolean(arch, cyl("archtop_cut", (0, fy, GATE_H), GATE_W * 0.5 + 0.008,
                      0.08 * 3.0, None, axis="Y", verts=14))
    plain.append(arch)

    # The gate itself: two timber leaves, proud of the wall and standing in
    # the opening rather than sunk into it -- a CLOSED gate, not a doorway.
    for sx, side in ((-1, "L"), (1, "R")):
        plain.append(box("%s_Gate%s" % (tag, side),
                     (sx * GATE_W * 0.25, -KD * 0.5 - 0.015, GATE_H * 0.44),
                     (GATE_W * 0.5 - 0.018, 0.05, GATE_H * 0.86), trim))

    # Shield and spears, leaning by the gate. Shield roughly chest-high on a
    # follower; spears taller than one, the way a leaning weapon reads.
    plain.append(box(tag + "_ShieldBack", (SHIELD_X, -KD * 0.5 - 0.045, 0.42),
                 (0.035, 0.34, 0.42), trim, rot=(0, 0, -6)))
    plain.append(box(tag + "_ShieldFace",
                 (SHIELD_X + 0.020, -KD * 0.5 - 0.045, 0.42),
                 (0.020, 0.25, 0.31), accent, rot=(0, 0, -6)))
    # Centred at half its own length PLUS a margin, or a tilted cylinder's
    # low end dips under the floor -- the first pass set z to exactly half
    # the shaft length (0.52 against a 1.05 m shaft) and `-- measure` came
    # back -0.005 before the tilt was even added.
    SPEAR_LEN = 1.05
    for sxo in SPEAR_XS:
        plain.append(cyl("%s_Spear%d" % (tag, int(sxo * 100)),
                     (sxo, -KD * 0.5 - 0.05, SPEAR_LEN * 0.5 + 0.025),
                     0.022, SPEAR_LEN, trim, axis="Z", verts=6,
                     rot=(0, 6, -4)))
        plain.append(box("%s_SpearTip%d" % (tag, int(sxo * 100)),
                     (sxo - 0.010, -KD * 0.5 - 0.043, SPEAR_LEN + 0.05),
                     (0.036, 0.036, 0.16), M["iron"], rot=(0, 6, -4)))

    # Crenellations: even spacing along all four top edges. Free-standing
    # boxes, never a notched ring -- a boolean band big enough to cut
    # crenels would need to be built solid first and cutting solids for a
    # castle wall is exactly the kind of overlapping-cutter trap this
    # project's builders avoid on purpose.
    z = KH + MH * 0.5
    for x in _edge(KW, MW * 0.7, N_EDGE):
        merlons.append(box("%s_MerF%d" % (tag, int(x * 100)),
                     (x, -KD * 0.5 + MW * 0.5, z), (MW, MW, MH), body))
        merlons.append(box("%s_MerB%d" % (tag, int(x * 100)),
                     (x, KD * 0.5 - MW * 0.5, z), (MW, MW, MH), body))
    for y in _edge(KD, MW * 0.7, N_EDGE):
        merlons.append(box("%s_MerL%d" % (tag, int(y * 100)),
                     (-KW * 0.5 + MW * 0.5, y, z), (MW, MW, MH), body))
        merlons.append(box("%s_MerR%d" % (tag, int(y * 100)),
                     (KW * 0.5 - MW * 0.5, y, z), (MW, MW, MH), body))

    hero.extend(gable_roof(tag + "_Roof", (0, RCY2, KH), RW2, RD2, RRISE2,
                        roof, overhang=ROVER2, thickness=RTHICK2))
    plain.append(box(tag + "_Ridge2", (0, RCY2, KH + RRISE2),
                 (0.08, RD2 + 0.30, 0.08), M["wood_dark"]))

    # Flagpole at the front-left corner, above the merlon it stands beside.
    # Doubled: a 10 cm flag on a 2 cm pole was one pixel at play scale.
    plain.append(cyl(tag + "_Pole", (FLAG_X, FLAG_Y, KH + MH + FLAG_H * 0.5),
                 0.04, FLAG_H, M["wood_dark"], axis="Z", verts=6))
    plain.append(box(tag + "_Flag",
                 (FLAG_X + 0.18, FLAG_Y, KH + MH + FLAG_H - 0.14),
                 (0.36, 0.02, 0.24), accent))

    # Merlons are twenty separate boxes -- an earlier pass bevelled them and
    # blew the triangle cap. A crenellation this small reads as a tooth
    # whether its corner is a 2 cm radius or a hard edge, so they join
    # `plain` and go through unbevelled.
    soften_all(hero, width=0.09, segments=3)
    soften_all(plain + merlons, width=0.0)
    return hero + merlons + plain
