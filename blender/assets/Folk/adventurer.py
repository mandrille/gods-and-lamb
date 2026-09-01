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

UNRIGGED, permanently, like every folk asset. Pose is baked in: the head is
yawed the OPPOSITE way from the villager's, the staff arm is forward, the free
arm hangs back and one boot leads. Two followers modelled at attention read as
one asset instanced twice.

Fronts -Y. The staff stands on z=0 with the boots, which is why the shaft is
vertical -- a tilted shaft puts its lower corner through the floor and the
anchor check is measured, not intended.
"""
import math
import os

from kit import M, box, soften_all

CATEGORY = os.path.basename(os.path.dirname(os.path.abspath(__file__)))

ASSET = dict(
    cls="folk",
    family="folk",
    variant="adventurer",
    category=CATEGORY,
    # MEASURED, and matched to the villager on purpose: the village reserves
    # ground from this number, and two followers of the same people should
    # reserve the same square.
    footprint=(0.44, 0.40),
    anchor="floor",
    slots=(),
)

HEAD_W, HEAD_D, HEAD_H = 0.34, 0.30, 0.32
HEAD_Z = 0.46             # underside of the head
BODY_Z = 0.22             # underside of the garment
YAW = 9.0                 # head yaw, shared by everything on the head
STAFF_X = 0.186           # the staff owns this column, hand included
STAFF_TOP = 0.96


def _yaw(x, y):
    """Turn a point with the head.

    `rot=` yaws a box about its OWN centre, so anything sitting on the face has
    to have its CENTRE turned as well or the head rotates out from under it.
    The first pass skipped this and the far eye ended up 11 mm behind its own
    cheek -- invisible, and the front render was a face with one eye. This is
    the same fault build.py's look camera comment was written about, arriving
    by a different route, so it is worth spending six lines to make impossible.
    """
    c, s = math.cos(math.radians(YAW)), math.sin(math.radians(YAW))
    return x * c - y * s, x * s + y * c


def build(tag="ADVENTURER", **kw):
    # Hero parts carry the silhouette and earn a bevel at 108 triangles each.
    # Three is all this asset can afford: head, hair and vest are the three
    # masses you can still see at play distance.
    hero, plain = [], []

    head_c = HEAD_Z + HEAD_H * 0.5
    hero.append(box(tag + "_Head", (0, 0, head_c),
                    (HEAD_W, HEAD_D, HEAD_H), M["skin"], rot=(0, 0, YAW)))

    # Hair: cap, sideburns high and back, and the crown behind. Every piece
    # carries the head yaw -- masses at different yaws meet along a slanted
    # crease that reads as a notch, and a head is the worst place for one.
    hero.append(box(tag + "_Hair", (0, 0.012, HEAD_Z + HEAD_H - 0.01),
                    (HEAD_W + 0.03, HEAD_D + 0.03, 0.17),
                    M["hair_warm"], rot=(0, 0, YAW)))
    for sx in (-1, 1):
        plain.append(box("%s_HairSide%s" % (tag, "L" if sx < 0 else "R"),
                         (sx * (HEAD_W * 0.5 - 0.008), 0.045, head_c + 0.075),
                         (0.042, HEAD_D * 0.62, HEAD_H * 0.44),
                         M["hair_warm"], rot=(0, 0, YAW)))
    plain.append(box(tag + "_HairBack", (0, 0.125, head_c + 0.045),
                     (HEAD_W - 0.05, 0.075, HEAD_H * 0.55),
                     M["hair_warm"], rot=(0, 0, YAW)))

    # The leaf in the hair. One, not the reference's sprig of three: three
    # 2 cm leaves at play distance are one green pixel, and one 9 cm leaf is a
    # green pixel that sticks out of the head where you can see it. Its lower
    # half is INSIDE the cap -- the first pass floated it a centimetre clear
    # and it read as a green cube hovering over a boy.
    sx_, sy_ = _yaw(0.075, 0.03)
    plain.append(box(tag + "_Sprig", (sx_, sy_, 0.866),
                     (0.09, 0.025, 0.055), M["leaf_light"], rot=(0, 38, 0)))

    # Two dark eyes and nothing else. The reference's eyes are blue and the
    # palette has no eye blue; it would not matter if it did, because at 40 px
    # an iris is the same dark dot whatever colour it was painted.
    for sx in (-1, 1):
        ex, ey = _yaw(sx * 0.075, -HEAD_D * 0.5 + 0.012)
        plain.append(box("%s_Eye%s" % (tag, "L" if sx < 0 else "R"),
                         (ex, ey, head_c - 0.01),
                         (0.055, 0.03, 0.075), M["hair_dark"], rot=(0, 0, YAW)))

    # Torso. The vest is the body and the green is a hem under it -- one band,
    # not a second full mass, because the whole layering effect is visible in
    # the two centimetres where the hues meet.
    hero.append(box(tag + "_Vest", (0, 0, 0.365),
                    (0.26, 0.20, 0.235), M["cloth_orange"]))
    plain.append(box(tag + "_Hem", (0, 0, 0.2325),
                     (0.252, 0.20, 0.042), M["cloth_green"]))
    plain.append(box(tag + "_Kerchief", (0, -0.005, HEAD_Z - 0.01),
                     (0.235, 0.205, 0.055), M["cloth_red"], rot=(0, 0, YAW)))
    # Pack strap, on the diagonal. Rotated about Y and not about Z: a Z yaw
    # spins a long box in PLAN, so the villager's strap and this one's first
    # pass were both horizontal bars sticking out past the ribs rather than
    # anything crossing a chest. About Y it runs shoulder to hip and stays
    # inside the body width.
    plain.append(box(tag + "_Strap", (0, -0.104, 0.398),
                     (0.26, 0.026, 0.034), M["leather"], rot=(0, 42, 0)))

    # The pack, and the bedroll lashed across the top of it. The roll is what
    # actually does the work: it breaks the shoulder line, which is the one
    # part of a 40 px figure the eye is certain about. Blue, not wool white --
    # this asset was coming out entirely brown and orange, and the roll sits
    # against leather where a near-neutral is a value change and disappears.
    plain.append(box(tag + "_Pack", (0, 0.145, 0.40),
                     (0.20, 0.11, 0.22), M["leather"]))
    plain.append(box(tag + "_Bedroll", (0, 0.15, 0.525),
                     (0.24, 0.10, 0.075), M["cloth_blue"]))

    # Arms, short, one forward on the staff and one hanging back. Negative X
    # tilt swings the lower end toward -Y, which is forward.
    for sx, tilt in ((-1, 14.0), (1, -34.0)):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Arm%s" % (tag, side),
                         (sx * 0.152, 0.0, BODY_Z + 0.145),
                         (0.072, 0.072, 0.17), M["cloth_green"],
                         rot=(tilt, 0, 0)))
    plain.append(box(tag + "_HandL", (-0.156, 0.022, BODY_Z + 0.04),
                     (0.072, 0.072, 0.062), M["skin"]))
    # The staff hand is pulled out to STAFF_X so it grips the shaft instead of
    # hovering three centimetres inside of it.
    plain.append(box(tag + "_HandR", (0.170, -0.048, BODY_Z + 0.055),
                     (0.072, 0.072, 0.062), M["skin"]))

    # Bare legs and oversized boots, one foot leading. `skin` and not
    # `skin_warm`: the warm one is a mid brown, and a mid brown leg above a
    # brown boot is the value-only pairing the whole palette rule exists to
    # stop. The light leg against the dark boot is a hue AND a value break, and
    # it is what makes the ankle visible at play distance.
    for sx, fwd in ((-1, 0.030), (1, -0.020)):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Leg%s" % (tag, side),
                         (sx * 0.066, fwd, 0.145),
                         (0.088, 0.088, 0.13), M["skin"]))
        plain.append(box("%s_Boot%s" % (tag, side),
                         (sx * 0.066, fwd - 0.016, 0.048),
                         (0.115, 0.15, 0.096), M["leather"]))

    # The staff. Vertical and planted: it shares the floor with the boots, so
    # the anchor check sees one number and not a shaft corner below zero.
    plain.append(box(tag + "_Staff", (STAFF_X, -0.03, STAFF_TOP * 0.5),
                     (0.036, 0.036, STAFF_TOP), M["wood"]))
    plain.append(box(tag + "_StaffGlow", (STAFF_X, -0.03, STAFF_TOP + 0.025),
                     (0.05, 0.05, 0.05), M["warmglow"]))
    # The leaf grows OUT of the glow rather than hovering above it -- two loose
    # cubes stacked over a stick is what the first pass looked like -- and it
    # leans INWARD, over his head. Leaning it outward cost 3 cm of footprint
    # for nothing: the declaration is the square the village reserves, and a
    # follower does not get a wider plot because his stick has a leaf on it.
    plain.append(box(tag + "_StaffLeaf", (STAFF_X - 0.022, -0.03, STAFF_TOP + 0.058),
                     (0.105, 0.025, 0.06), M["leaf_light"], rot=(0, -55, 0)))

    # Two passes, same radii as the villager: 2.5 cm at two segments on the
    # three hero masses so the folk catch the key light the way the ground
    # tiles do, and width 0 on everything else -- smooth-shaded and tagged, no
    # radius, no triangles.
    soften_all(hero, width=0.025, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
