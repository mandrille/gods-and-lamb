"""BUILDING.shrine.shrine - the little stone temple Faith comes from.

This is the one building the player is meant to notice, so it is built out of
everything the rest of the village is not: stone instead of timber, a GOLD roof,
and steps. Steps are doing more work than they look like they are -- they lift
the whole thing off the ground plane, and a raised object reads as important at
a glance in a way no amount of surface detail does.

Gold is the only metal in the palette and nothing else uses it. That is the
point: at the play camera the shrine is a gold triangle in a field of terracotta
and thatch, and it can be found without being looked for.

The niche is a hole and it is treated like every other hole in this project --
cut, floored with `hollow`, and left alone. What sits in it is a single gold
flame, proud of the mouth rather than buried in it, because anything set back
inside a 20 cm recess is in shadow at forty pixels and simply is not there.

Fronts -Y. The ridge runs front-to-back so the -Y elevation is a pediment,
which is what a temple front is.
"""
import os

from kit import (M, box, cone, boolean, scheme, gable_roof, gable_cutters,
                 soften_all)

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="building",
    family="shrine",
    variant="shrine",
    category=CATEGORY,
    # MEASURED. The gold slabs are rotated, so X reaches past the eaves line by
    # roughly half the slab thickness times sin(pitch) -- the arithmetic on the
    # roof width alone says 1.38 and the truth is 1.44.
    footprint=(1.44, 1.30),
    anchor="floor",
    slots=(),
)

STEP0 = (1.34, 1.16, 0.10)
STEP1 = (1.14, 0.98, 0.10)
PLINTH_Z = STEP0[2] + STEP1[2]        # everything above stands on this

BODY_W, BODY_D, BODY_H = 0.86, 0.72, 0.66
BODY_Y = 0.06                          # set back, so the portico has depth
PIL = 0.14
PIL_Y = -0.40

NICHE_W, NICHE_H, NICHE_DEPTH = 0.38, 0.44, 0.22
NICHE_Z = PLINTH_Z + NICHE_H * 0.5 + 0.05

ENT_W, ENT_D, ENT_T = 1.10, 1.00, 0.11
ENT_Y = -0.02
ROOF_RISE, ROOF_OVER, ROOF_T = 0.40, 0.14, 0.11


def build(tag="SHRINE", **kw):
    body, trim, roof, accent = scheme(kw.get("scheme", "shrine_gold"))
    P = []

    # Two steps, dark then light. Alternating the value between courses is what
    # makes them read as separate treads; a single hue would be one grey wedge.
    P.append(box(tag + "_Step0", (0, 0, STEP0[2] * 0.5),
                 STEP0, trim))
    P.append(box(tag + "_Step1", (0, 0, STEP0[2] + STEP1[2] * 0.5),
                 STEP1, body))

    cella = box(tag + "_Cella", (0, BODY_Y, PLINTH_Z + BODY_H * 0.5),
                (BODY_W, BODY_D, BODY_H), body)
    # A single cutter, so nothing here can repeat the self-intersecting-join
    # failure. It runs well past the front face so the mouth of the niche is a
    # clean rectangle rather than a coplanar tangency for EXACT to resolve.
    boolean(cella, box("niche_cut",
                       (0, BODY_Y - BODY_D * 0.5 + NICHE_DEPTH * 0.5,
                        NICHE_Z),
                       (NICHE_W, NICHE_DEPTH * 2.0, NICHE_H), None))
    P.append(cella)
    P.append(box(tag + "_NicheDark",
                 (0, BODY_Y - BODY_D * 0.5 + NICHE_DEPTH, NICHE_Z),
                 (NICHE_W, 0.04, NICHE_H), M["hollow"]))

    # The offering: a gold flame on a dark plinth, standing at the MOUTH of the
    # niche, not inside it.
    fy = BODY_Y - BODY_D * 0.5 + 0.07
    P.append(box(tag + "_Altar", (0, fy, PLINTH_Z + 0.06),
                 (0.24, 0.16, 0.12), trim))
    P.append(cone(tag + "_Flame", (0, fy, PLINTH_Z + 0.26), 0.085, 0.0, 0.28,
                  roof, verts=8))

    # Free-standing portico columns, forward of the cella. They are what turns a
    # box with a hole in it into a temple, and they cost two boxes.
    for sx, side in ((-1, "L"), (1, "R")):
        P.append(box("%s_Column%s" % (tag, side),
                     (sx * 0.40, PIL_Y, PLINTH_Z + BODY_H * 0.5),
                     (PIL, PIL, BODY_H), body))

    ent_z = PLINTH_Z + BODY_H + ENT_T * 0.5
    P.append(box(tag + "_Entablature", (0, ENT_Y, ent_z),
                 (ENT_W, ENT_D, ENT_T), trim))
    # The one saturated cloth in the asset, hung across the portico. Stone and
    # gold are both warm and low-chroma next to each other, and this is the hue
    # that stops the upper half reading as a single ochre mass.
    P.append(box(tag + "_Banner", (0, ENT_Y - ENT_D * 0.5 - 0.015,
                                   ent_z - ENT_T * 0.5 - 0.075),
                 (0.72, 0.04, 0.15), accent))

    eaves = PLINTH_Z + BODY_H + ENT_T
    # The pediment. Without it the triangle between the two slopes is EMPTY and
    # the first render showed the horizon straight through the shrine above the
    # entablature -- the same open-gable failure as a wall stopped at the eaves,
    # just one storey up. Built as a full box and cut back to the roof
    # underside, one boolean per cutter for the reason above.
    #
    # Narrower than the entablature on purpose, so the cornice still projects
    # and the two do not read as one tall block. The cutters are still sized off
    # ENT_W because they have to match the ROOF, not this box.
    ped = box(tag + "_Pediment", (0, ENT_Y, eaves + ROOF_RISE * 0.5),
              (ENT_W - 0.08, ENT_D - 0.08, ROOF_RISE), body)
    for cutter in gable_cutters("pedcut", (0, ENT_Y, eaves), ENT_W, ENT_D,
                                ROOF_RISE, overhang=ROOF_OVER,
                                thickness=ROOF_T):
        boolean(ped, cutter)
    P.append(ped)

    P.extend(gable_roof(tag + "_Roof", (0, ENT_Y, eaves), ENT_W, ENT_D,
                        ROOF_RISE, roof, overhang=ROOF_OVER,
                        thickness=ROOF_T))
    P.append(box(tag + "_Ridge", (0, ENT_Y, eaves + ROOF_RISE),
                 (0.09, ENT_D + 0.30, 0.09), roof))
    # The finial. `cone` takes no rotation and needs none -- it is upright, and
    # a cone on anything tilted is a party hat.
    P.append(cone(tag + "_Finial", (0, ENT_Y, eaves + ROOF_RISE + 0.19),
                  0.085, 0.0, 0.30, roof, verts=8))

    soften_all(P, width=0.032, segments=2)
    return P
