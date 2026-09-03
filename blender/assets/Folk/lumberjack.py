"""FOLK.folk.lumberjack - felling the timber the lumber camp needs.

Same body as every other folk job. What tells him apart at 40 px, in the order
it reads: the BEARD, which the reference builds the entire character around --
it is nearly a third of his height and covers most of the torso -- and the
AXE, held upright in his right hand.

folkbody's `hair="beard"` style gives the cap-shaped hero mass (the
"curly-ish cap" that stands in for the reference's mop of curls -- an actual
curl ring was never validated for this batch and cap reads fine at play
distance) plus its own modest chin slab. That slab alone was not the identity
the reference shows, so this file adds one more plain mass beside it
(`_BeardBig`) to bulk the whole thing out.

No apron, no kerchief -- the reference wears neither, and the rope belt
(thatch-coloured, tied at the waist) is this job's own identity instead of
folkbody's default strap treatment.

Fronts -Y, symmetric rest pose (03-folk-rig.md section 3): the axe is a held
DETAIL, not a baked pose, so it stays where `hands="level"` puts the hand.
"""
import os

from kit import M, box
from folkbody import BELT, HAND_R, body, finish

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="lumberjack",
    category=CATEGORY,
    # MEASURED: the axe head sets X (it pokes to +0.30 on the right, the
    # beard bulk pulls the left edge to -0.19), the beard sets Y.
    footprint=(0.49, 0.37),
    anchor="floor",
    slots=(),
)

# Olive tunic, warm-brown hair/beard -- the reference's mottled green-brown
# tunic reads as `cloth_green` at this scale; legs stay the shared dark
# default so the boots do not fight the rope belt for the same brown.
PALETTE = dict(tunic="cloth_green", hair="hair_warm", skin="skin",
               boots="leather", legs="wood_dark")


def build(tag="LUMBERJACK", **kw):
    hero, plain = body(tag, PALETTE, hair="beard", apron=False,
                       kerchief=False, hands="level")

    # The beard, bulked out. Same front face as folkbody's own `_Beard` slab
    # (y=-0.12, half-depth 0.05) rather than pushed further forward -- a
    # first attempt at +0.02 forward and +30% wider swallowed the arms and
    # the axe whole in a close 35mm shot, because a mass that much CLOSER to
    # the camera grows in angular size far more than its world-space extent
    # suggests. Width capped at 0.20 (half 0.10) for the same reason: at
    # 0.24 it left only 3.6 cm of clearance to the 0.156 hand/axe column and
    # still ate the haft. PLAIN, not hero -- a hero bevel on this pushed the
    # asset to 648 tris against the 600 cap; folkbody's own default `_Beard`
    # slab is plain too, so this matches rather than fights it.
    extra_plain = [
        box(tag + "_BeardBig", (0, -0.12, 0.42),
           (0.20, 0.10, 0.19), M["hair_warm"]),
        # Rope belt: a full band around the waist, same box-wraps-the-torso
        # trick folkbody uses for its kerchief.
        box(tag + "_Rope", BELT, (0.27, 0.21, 0.032), M["thatch"]),
        # Axe: wood haft planted at the hand, stone head near the top --
        # pushed OUT in X past the head's own 0.17 half-width, not centred
        # over it. A first attempt centred the head at x=0.106, inside both
        # the skin head box's X range AND behind its front face in depth, so
        # the head box hid the axe head completely -- invisible in every
        # angle despite existing. Screen-space occlusion here is about
        # X/Z overlap through the camera, not just Y depth.
        box(tag + "_Axe", (HAND_R[0], HAND_R[1] - 0.02, 0.42),
           (0.032, 0.032, 0.34), M["wood"]),
        box(tag + "_AxeHead", (0.22, HAND_R[1] - 0.02, 0.565),
           (0.16, 0.05, 0.095), M["stone_dark"]),
    ]

    return finish(hero, plain, extra_plain=extra_plain)
