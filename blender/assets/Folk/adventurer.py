"""FOLK.folk.adventurer - the follower who goes out and fetches things.

Same body as the villager and deliberately so: one set of proportions is what
makes a crowd read as one people. Everything here is about being TOLD APART
from the villager at forty pixels, which is a harder problem than it sounds --
two 40 px figures with the same silhouette and the same two hues are the same
character wearing different clothes, and nobody will ever see the difference.

Three things carry it, in the order they read at play distance:

* SILHOUETTE. A staff planted on the ground beside him and a bedroll humped
  above his shoulders. A vertical line and a shoulder lump survive being 40 px
  tall; a satchel buckle does not.
* HUE INVERSION. The villager is green-bodied with an orange strip. This one is
  orange-bodied with a green hem and green sleeves, which is what the reference
  actually shows -- the patterned vest is the big garment and the green tunic
  underneath only shows at the cuffs and the hem. It inverts the villager
  without either of them leaving the palette.
* ONE SPARK. The warmglow at the staff tip is the only emissive thing a
  follower carries, and it is what finds him in a field at dusk.

Argued with the reference in two places, both for the same reason the villager
darkened its tunic -- the reference is drawn on a white backdrop and this thing
lives on grass:

* the reference has bare skin legs. Kept, because it separates from the
  villager's dark trousers by HUE and the boots stay brown either way.
* the reference carries a flower basket in the off hand. Dropped. At 40 px it
  is a brown lump on a brown hand, and the cap is 600 triangles -- the staff
  buys far more silhouette per triangle than the basket does.

RIGGED now, like every folk asset, and REPOSED for it: the head yaw, the
staff-arm tilt and the leading boot that used to carry this asset's liveliness
are gone. `03-folk-rig.md` section 3 is why -- rest pose is what every clip is
measured FROM, so a baked lean used to be a lean added to every frame of every
animation, and a mirrored ArmL/ArmR bone on an asymmetric body would deform the
two sides differently. What replaces the lean is exactly what replaced it on
the villager: nothing needs to, because the walk cycle is now where the
liveliness comes from. What still carries the asymmetry that costs nothing at
runtime is the diagonal pack strap, the bedroll off to one side, the staff
itself -- kept as before.

MIGRATED onto `assets/_kit/folkbody.py`. The shared torso mass (`body()`'s
`_Tunic`, orange here) stands in for what used to be a separate `_Vest` box --
close enough in size that the silhouette does not move, and one shared garment
mass is the whole point of the migration. The green `_Hem` band, the pack, the
bedroll, the staff and its leaf stay as this file's own extra parts, because
`folkbody.body()` has no idea what a staff is.

Fronts -Y. The staff stands on z=0 with the boots, which is why the shaft is
vertical -- a tilted shaft puts its lower corner through the floor and the
anchor check is measured, not intended.
"""
import os

from kit import M, box
from folkbody import BACK, body, finish

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="adventurer",
    category=CATEGORY,
    # RE-MEASURED after the rest pose was squared up, the same move
    # villager.py went through first (03-folk-rig.md section 3): levelling the
    # staff arm and the leading boot pulled the AABB in from the old 0.44 x
    # 0.40, though not as far as it first looks -- the staff itself is what
    # sets the new X extent (0.219 m out at STAFF_X, past the swinging arm).
    footprint=(0.42, 0.36),
    anchor="floor",
    slots=(),
)

STAFF_X = 0.186            # the staff owns this column
STAFF_TOP = 0.96

# Orange body, green trim -- the inverse of the villager's green body / orange
# trim, which is what the reference actually shows once the patterned vest is
# read as the big garment and the green tunic underneath only shows at the
# hem. Bare skin legs, not `skin_warm`: a mid-brown leg above a brown boot is
# the value-only pairing the whole palette rule exists to stop, and the light
# leg against the dark boot is a hue AND a value break.
PALETTE = dict(tunic="cloth_orange", sleeves="cloth_green", kerchief="cloth_red",
               hair="hair_warm", skin="skin", boots="leather", legs="skin")


def build(tag="ADVENTURER", **kw):
    hero, plain = body(tag, PALETTE, hair="cap", apron=False, kerchief=True,
                       hands="staff")

    # The hem: a green band right under the shared tunic's bottom edge, which
    # is the two centimetres where the layering actually reads.
    plain.append(box(tag + "_Hem", (0, 0, 0.195),
                     (0.252, 0.20, 0.042), M["cloth_green"]))

    # The leaf in the hair. One, not the reference's sprig of three -- three
    # 2 cm leaves at play distance are one green pixel, and one 9 cm leaf is a
    # green pixel that sticks out of the head where you can see it.
    plain.append(box(tag + "_Sprig", (0.075, 0.03, 0.866),
                     (0.09, 0.025, 0.055), M["leaf_light"], rot=(0, 38, 0)))

    # No second strap here: `body()` already builds one `_Strap` (a shared
    # part folkbody always adds, per its own docstring) and the API gives job
    # files no way to reposition it. Adding a second box named `_Strap` would
    # collide -- Blender renames the duplicate object rather than erroring,
    # so it would still bind to Torso but draw two overlapping straps for
    # nothing. Flagged in the report: the pack-side diagonal this file used to
    # draw for itself is gone, and body()'s front strap stands in for it.

    # The pack, and the bedroll lashed across the top of it, at the BACK
    # anchor. The roll is what actually does the work: it breaks the shoulder
    # line, which is the one part of a 40 px figure the eye is certain about.
    # Blue, not wool white -- this asset is otherwise entirely brown and
    # orange, and the roll sits against leather where a near-neutral is a
    # value change and disappears.
    plain.append(box(tag + "_Pack", BACK, (0.20, 0.11, 0.22), M["leather"]))
    plain.append(box(tag + "_Bedroll", (BACK[0], BACK[1] + 0.005, BACK[2] + 0.125),
                     (0.24, 0.10, 0.075), M["cloth_blue"]))

    # The staff. Vertical and planted: it shares the floor with the boots, so
    # the anchor check sees one number and not a shaft corner below zero. The
    # gripping hand sits at folkbody's GRIP_R (hands="staff" above), which is
    # what STAFF_X is matched to.
    plain.append(box(tag + "_Staff", (STAFF_X, -0.03, STAFF_TOP * 0.5),
                     (0.036, 0.036, STAFF_TOP), M["wood"]))
    plain.append(box(tag + "_StaffGlow", (STAFF_X, -0.03, STAFF_TOP + 0.025),
                     (0.05, 0.05, 0.05), M["warmglow"]))
    # The leaf grows OUT of the glow rather than hovering above it, and leans
    # INWARD over his head. Leaning it outward cost 3 cm of footprint for
    # nothing: the declaration is the square the village reserves, and a
    # follower does not get a wider plot because his stick has a leaf on it.
    plain.append(box(tag + "_StaffLeaf", (STAFF_X - 0.022, -0.03, STAFF_TOP + 0.058),
                     (0.105, 0.025, 0.06), M["leaf_light"], rot=(0, -55, 0)))

    return finish(hero, plain)
