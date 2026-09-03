"""The one shared human body. Every folk job builds on this.

Proportions are copied VERBATIM from the original `Folk/villager.py` -- this
module does not re-derive a single number, because villager.py's own docstring
spent two attempts getting the head-to-body ratio right and re-deriving it here
would be throwing that work away. See `assets/Folk/villager.py` for the
reasoning behind each ratio; this file only reproduces the geometry.

BUILT AT ATTENTION, always. `03-folk-rig.md` section 3 is the reason: rest
pose is what every clip is measured FROM, so a baked lean is a lean added to
every frame of every animation a job author will ever write. `body()` never
takes an angle -- arms level, feet level, head facing front, every time. The
asymmetry that makes an unrigged mesh look alive standing still is not this
module's job any more; it is the walk cycle's. What DOES still vary between
jobs, and costs nothing at runtime, is the small stuff: a diagonal strap, an
off-centre satchel, a hair parting -- keep that kind of detail in the per-job
extras, not in a pose.

`SKELETON` is exported from these same constants and `folkrig.py` imports it,
so there is exactly one place that knows where the joints are. Move a
constant here and the bones follow; that is the whole point of pulling this
out of folkrig.

Parts are claimed by NAME (`folkrig.GROUPS`), never by which function built
them. Every hair style emits `_Hair*` names; the `beard` style additionally
emits `_Beard`, which `GROUPS` already claims for the Head bone. An asset that
adds a part folkrig does not recognise fails the rig build by design -- see
`docs/03-folk-rig.md` section 2.

This module imports only from `kit`. It must never import `folkrig` -- the
skeleton flows body -> rig, not the other way, or the two modules would need
each other's globals to load at all.
"""
import math
import os

from kit import M, box, soften_all

# --------------------------------------------------------------- proportions
# Copied verbatim from the original Folk/villager.py. Do not "improve" these
# toward realism -- at 40 px the head IS the character and the body is a
# coloured stand for it; villager.py's docstring has the reasoning.
HEAD_W, HEAD_D, HEAD_H = 0.34, 0.30, 0.32
HEAD_Z = 0.46              # underside of the head
BODY_Z = 0.22               # underside of the tunic; also the Root->Torso joint
BODY_H = 0.26

HEAD_C = HEAD_Z + HEAD_H * 0.5     # head box centre, used by every hair style

# Bone geometry, unchanged from the tuple folkrig.py used to hardcode.
ARM_X, ARM_TOP, ARM_BOT = 0.152, 0.450, 0.229
LEG_X, LEG_TOP = 0.066, 0.210
TORSO_TOP = 0.480
HEAD_TOP = 0.780

# The grip position for a job that plants a staff (adventurer today). Pulled
# out from the hanging-hand column so the hand meets a vertical shaft instead
# of hovering inside it -- the exact offset the adventurer's original file
# used for its HandR before this migration.
GRIP_R = (0.170, -0.048)

# name, head, tail, parent -- folkrig.py imports this directly. A bone that
# does not start at the joint it drives is a bone that shears its part, so
# these come from the proportions above rather than being retyped.
SKELETON = (
    ("Root",  (0.000, 0.0, 0.000),   (0.000, 0.0, BODY_Z),   None),
    ("Torso", (0.000, 0.0, BODY_Z),  (0.000, 0.0, TORSO_TOP), "Root"),
    ("Head",  (0.000, 0.0, HEAD_Z),  (0.000, 0.0, HEAD_TOP),  "Torso"),
    ("ArmL",  (-ARM_X, 0.0, ARM_TOP), (-ARM_X, 0.0, ARM_BOT),  "Torso"),
    ("ArmR",  (ARM_X, 0.0, ARM_TOP),  (ARM_X, 0.0, ARM_BOT),   "Torso"),
    ("LegL",  (-LEG_X, 0.0, LEG_TOP), (-LEG_X, 0.0, 0.000),    "Root"),
    ("LegR",  (LEG_X, 0.0, LEG_TOP),  (LEG_X, 0.0, 0.000),     "Root"),
)

# --------------------------------------------------------------- prop anchors
# Local-space points a job builder can hang a prop from, in the SAME "level"
# rest pose body() always builds. Approximate, not measured -- a job author
# placing a prop should still nudge it against a `-- look` render, the way
# every hand-placed box in this codebase is tuned.
HAND_R = (0.156, 0.0, BODY_Z + 0.04)
HAND_L = (-0.156, 0.0, BODY_Z + 0.04)
CHEST = (0.0, -0.098, BODY_Z + 0.11)
BACK = (0.0, 0.145, 0.40)
HIP_L = (-0.066, -0.02, 0.10)
HIP_R = (0.066, -0.02, 0.10)
BROW = (0.0, -HEAD_D * 0.5 + 0.01, HEAD_C + 0.06)
CROWN = (0.0, 0.02, HEAD_Z + HEAD_H + 0.02)
BELT = (0.0, -0.09, BODY_Z + 0.02)

# ------------------------------------------------------------------ palette
# Keys a job's palette dict may set; anything omitted falls back to these.
# `sleeves` defaults to whatever `tunic` resolved to -- most jobs want one
# garment colour, and the villager and adventurer both did before this file
# existed.
_DEFAULT_PALETTE = dict(
    skin="skin", hair="hair_warm", tunic="cloth_green", sleeves=None,
    apron="cloth_orange", kerchief="cloth_red", boots="leather",
    legs="wood_dark",
)


def _resolve(palette):
    p = dict(_DEFAULT_PALETTE)
    p.update(palette or {})
    if p["sleeves"] is None:
        p["sleeves"] = p["tunic"]
    try:
        return {k: M[v] for k, v in p.items()}
    except KeyError as e:
        raise SystemExit("FAIL: folkbody palette key %s has no kit.M entry -- "
                         "check the material name, not src/kit.py." % e)


# --------------------------------------------------------------------- hair
# Every style is a function(tag, hero, plain, P) -> None, appending parts to
# the lists it is handed. All names contain "_Hair" (folkrig.GROUPS claims
# that substring for Head) except the beard slab, which claims "_Beard"
# directly -- both keys already exist in GROUPS.

def _hair_cap(tag, hero, plain, P):
    """The villager's cap: a crown mass, two low sideburns, a back lobe."""
    hero.append(box(tag + "_Hair", (0, 0.012, HEAD_Z + HEAD_H - 0.01),
                    (HEAD_W + 0.03, HEAD_D + 0.03, 0.17), P["hair"]))
    # Sideburns, not side panels -- high and back, so the lower front of the
    # head stays skin and an eye is never hidden behind its own hair.
    for sx in (-1, 1):
        plain.append(box("%s_HairSide%s" % (tag, "L" if sx < 0 else "R"),
                         (sx * (HEAD_W * 0.5 - 0.008), 0.045, HEAD_C + 0.075),
                         (0.042, HEAD_D * 0.62, HEAD_H * 0.44), P["hair"]))
    plain.append(box(tag + "_HairBack", (0, 0.125, HEAD_C + 0.045),
                     (HEAD_W - 0.05, 0.075, HEAD_H * 0.55), P["hair"]))


def _hair_curly(tag, hero, plain, P):
    """A ring of small curls around the back and top of the crown.

    Smooth-shaded only (`plain`), not bevelled -- the head's own hero-pass
    bevel already reads as "rounded" at 40 px, and eight more hero-cost boxes
    would spend triangles this asset does not have. Kept off the front third
    of the head so the face stays readable.
    """
    n = 7
    r = HEAD_W * 0.46
    top = HEAD_C + HEAD_H * 0.40
    for i in range(n):
        ang = math.pi * 2.0 * i / n
        cx, cy = r * math.sin(ang), r * math.cos(ang) * 0.6
        if cy < -0.03:          # the front-facing third: leave the face bare
            continue
        plain.append(box("%s_HairCurl%d" % (tag, i),
                         (cx, cy + 0.03, top - abs(cx) * 0.15),
                         (0.085, 0.085, 0.085), P["hair"]))


def _hair_topknot(tag, hero, plain, P):
    """A single bun above the crown. Sides stay bare on purpose."""
    plain.append(box(tag + "_Hair", (0, 0.03, HEAD_C + HEAD_H * 0.56),
                     (0.11, 0.11, 0.095), P["hair"]))


def _hair_beard(tag, hero, plain, P):
    """The cap, plus a slab under the chin."""
    _hair_cap(tag, hero, plain, P)
    plain.append(box(tag + "_Beard", (0, -HEAD_D * 0.40, HEAD_C - HEAD_H * 0.34),
                     (HEAD_W * 0.62, 0.10, HEAD_H * 0.40), P["hair"]))


def _hair_none(tag, hero, plain, P):
    return


_HAIR_STYLES = {
    "cap": _hair_cap,
    "curly": _hair_curly,
    "topknot": _hair_topknot,
    "beard": _hair_beard,
    "none": _hair_none,
}


# --------------------------------------------------------------------- body
def body(tag, palette, hair="cap", apron=True, kerchief=True, hands="level"):
    """The shared human, in symmetric rest pose. Returns (hero, plain).

    `hero` carries the silhouette and is meant to go through
    `soften_all(width=0.025, segments=2)`; `plain` is smooth-shaded only.
    `finish()` below does both passes -- call it once, after adding any
    per-job extras, rather than softening here.
    """
    if hair not in _HAIR_STYLES:
        raise SystemExit("FAIL: folkbody.body() got hair=%r, expected one of %s"
                         % (hair, sorted(_HAIR_STYLES)))
    if hands not in ("level", "staff"):
        raise SystemExit("FAIL: folkbody.body() got hands=%r, expected "
                         "'level' or 'staff'" % hands)

    P = _resolve(palette)
    hero, plain = [], []

    hero.append(box(tag + "_Head", (0, 0, HEAD_C),
                    (HEAD_W, HEAD_D, HEAD_H), P["skin"]))
    _HAIR_STYLES[hair](tag, hero, plain, P)

    # Two dark eyes and nothing else -- a mouth is noise at play distance.
    # Always hair_dark: an eye is a dot, not a garment, and does not belong to
    # the palette.
    for sx in (-1, 1):
        ex, ey = sx * 0.075, -HEAD_D * 0.5 + 0.012
        plain.append(box("%s_Eye%s" % (tag, "L" if sx < 0 else "R"),
                         (ex, ey, HEAD_C - 0.01), (0.05, 0.03, 0.068),
                         M["hair_dark"]))

    # Torso. Narrower than the head on purpose (villager.py's docstring).
    hero.append(box(tag + "_Tunic", (0, 0, BODY_Z + BODY_H * 0.5),
                    (0.24, 0.19, BODY_H), P["tunic"]))
    if apron:
        plain.append(box(tag + "_Apron", (0, -0.098, BODY_Z + 0.11),
                         (0.175, 0.025, 0.19), P["apron"]))
    if kerchief:
        plain.append(box(tag + "_Kerchief", (0, -0.005, HEAD_Z - 0.01),
                         (0.235, 0.205, 0.055), P["kerchief"]))
    # One strap, always -- leather, not palette-driven (no job has asked for a
    # different strap colour yet). Rotated about Y, not Z: a Z yaw spins a
    # long box in PLAN, so this runs shoulder to hip and stays inside the
    # tunic width instead of sticking out of the ribs.
    plain.append(box(tag + "_Strap", (0, -0.112, BODY_Z + 0.14),
                     (0.26, 0.026, 0.042), M["leather"], rot=(0, 34, 0)))

    # Arms, SHORT and LEVEL -- no rot=. The ArmL/ArmR bones swing them at
    # runtime; a rest-pose tilt here is a tilt added to every frame of every
    # clip a job author writes (03-folk-rig.md section 3).
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Arm%s" % (tag, side),
                         (sx * ARM_X, 0.0, BODY_Z + 0.145),
                         (0.072, 0.072, 0.17), P["sleeves"]))
        if hands == "staff" and side == "R":
            hx, hy, hz = GRIP_R[0], GRIP_R[1], BODY_Z + 0.055
        else:
            hx, hy, hz = sx * 0.156, 0.0, BODY_Z + 0.04
        plain.append(box("%s_Hand%s" % (tag, side), (hx, hy, hz),
                         (0.072, 0.072, 0.062), P["skin"]))

    # Legs and boots, both LEVEL -- one foot forward in rest pose is a
    # permanent limp once the LegL/LegR bones add their own swing on top.
    for sx in (-1, 1):
        side = "L" if sx < 0 else "R"
        plain.append(box("%s_Leg%s" % (tag, side),
                         (sx * LEG_X, 0.0, 0.145),
                         (0.088, 0.088, 0.13), P["legs"]))
        plain.append(box("%s_Boot%s" % (tag, side),
                         (sx * LEG_X, -0.016, 0.048),
                         (0.115, 0.15, 0.096), P["boots"]))

    return hero, plain


def finish(hero, plain, extra_hero=(), extra_plain=()):
    """The two soften passes, run once over body() plus a job's own extras.

    2.5 cm at two segments on the hero masses -- the same chunky radius the
    ground tiles carry, so the folk and the world read as one thing. Width 0
    on everything else: smooth-shaded and tagged, no radius, no triangles.
    """
    hero = list(hero) + list(extra_hero)
    plain = list(plain) + list(extra_plain)
    soften_all(hero, width=0.025, segments=2)
    soften_all(plain, width=0.0)
    return hero + plain
