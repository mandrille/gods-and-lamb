"""A skeleton and three clips for the livestock.

Same doctrine as `folkrig` and a different animal. Seven bones, rigid skinning,
one vertex group per part at weight 1.0, no deform hierarchy below the knee --
all of that is unchanged. What changes is the TOPOLOGY: a quadruped hangs its
body between four legs instead of stacking it on two, so the folk skeleton does
not fit it and must not be forced to. Bound to `folkrig`, a cow gets a femur
through its own barrel and a head where its shoulder is.

    Root ------ Body ------ Head
      |
      +-------- LegFL, LegFR, LegBL, LegBR

THE JOINTS ARE MEASURED, NOT AUTHORED. `folkrig.SKELETON` is a table of
coordinates copied out of `villager.py`, and that works because there is
exactly one folk body. There are two animals and they are different sizes, so
the same table would have to be duplicated per asset -- and would rot silently
the first time a builder moved a leg, because a bone that misses its joint
shears its part and still renders. So every joint here is read off the
EVALUATED bounds of the parts that will hang on it: the front-left leg bone
runs from the top of whatever `_LegFL` turned out to be down to its lowest
vertex, and the body bone spans the underside of the barrel to its spine.
Change the proportions and the skeleton follows. This is the project's
`measure, never derive` rule applied to the rig itself.

Evaluated, not raw: at the time the armature is built the parts still carry
their Bevel modifiers, and the sheep's fleece asks for an 8 cm bevel. The
un-evaluated cage is eight centimetres wider than the animal.

WHAT REUSES folkrig. Everything that is about rigging rather than about being
a biped: the fcurve walk for Blender 5.2's slotted actions, the bake-then-group
order, the armature modifier, and all five asserts. Only the skeleton, the
group table and the clips are new. The private helpers are imported on purpose
-- they are the shared machinery of one rig kit split across two files, not
somebody else's internals.
"""
import bpy
from mathutils import Vector

import folkrig
from folkrig import (FPS, CYCLE, action_fcurves, attach, evaluated_points,
                     assert_action_deforms, assert_cycle_closes,
                     assert_feet_on_floor, assert_rigid_weights,
                     _begin, _finish, _key_rot, _plant)

# Which part goes on which bone, matched on the name after the tag prefix.
# Order matters -- the first match wins -- and the legs are tested first
# because every one of them also contains "_Leg".
GROUPS = (
    ("LegFL", ("_LegFL", "_HoofFL")),
    ("LegFR", ("_LegFR", "_HoofFR")),
    ("LegBL", ("_LegBL", "_HoofBL")),
    ("LegBR", ("_LegBR", "_HoofBR")),
    # The skull and everything carried ON it. The NECK is deliberately not
    # here: it belongs to the body, and the Head bone pivots at the back of the
    # skull -- which is inside the neck -- so a nod turns the head without
    # opening a seam at the shoulder.
    ("Head",  ("_Head", "_Ear", "_Horn", "_Eye", "_Muzzle", "_Blaze",
               "_Topknot", "_Poll")),
    ("Body",  ("_Body", "_Fleece", "_Neck", "_Rump", "_Tail", "_Udder",
               "_Patch", "_Mark", "_Collar", "_Bell", "_Saddle")),
)

LEGS = ("LegFL", "LegFR", "LegBL", "LegBR")
# The diagonal pairs a walking quadruped moves together. Getting this wrong
# gives a pace -- both legs on one side together -- which is a real gait for a
# camel and reads as a broken animation for a cow.
DIAGONAL_A = ("LegFL", "LegBR")
DIAGONAL_B = ("LegFR", "LegBL")


def bone_for(name):
    """The bone a part belongs on, or None. Unclaimed is a FAILURE upstream."""
    for bone, keys in GROUPS:
        if any(k in name for k in keys):
            return bone
    return None


def _claimed_bounds():
    """{bone: (lo, hi)} over the EVALUATED world bounds of the scene's parts.

    Only meshes a bone claims are measured. An unclaimed part is not silently
    ignored -- `bake_and_group` refuses the whole asset over it -- but that
    check belongs there, and this function must not fall over on the look-dev
    ground plane before it gets the chance.
    """
    out = {}
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        bone = bone_for(ob.name)
        if bone is None:
            continue
        for p in evaluated_points(ob):
            lo, hi = out.get(bone, (None, None))
            if lo is None:
                out[bone] = (Vector(p), Vector(p))
                continue
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return out


def measured_skeleton():
    """(name, head, tail, parent) per bone, read off the built parts.

    Every bone is VERTICAL. That is not laziness about anatomy: `align_roll`
    below points each bone's local Z at -Y so a fore/aft swing is a rotation
    about the bone's own X, and a bone lying along Y has no such roll to give.
    A horizontal spine would need its own axis convention and buy nothing at
    40 px, where the visible motion is four legs and a head.
    """
    b = _claimed_bounds()
    missing = [n for n in LEGS + ("Body", "Head") if n not in b]
    if missing:
        raise SystemExit(
            "FAIL: nothing in this asset feeds %s. critterrig needs four legs, "
            "a body and a head, claimed by name through critterrig.GROUPS -- "
            "see the table there for the part names each bone takes."
            % ", ".join(missing))

    belly = b["Body"][0].z
    back = b["Body"][1].z
    # The head pivots at the REARMOST point of the skull, which is the joint,
    # not at its centre. The animals front -Y, so rearmost is max y.
    head_y = b["Head"][1].y
    head_lo, head_hi = b["Head"][0].z, b["Head"][1].z

    bones = [("Root", (0.0, 0.0, 0.0), (0.0, 0.0, belly), None),
             ("Body", (0.0, 0.0, belly), (0.0, 0.0, back), "Root"),
             ("Head", (0.0, head_y, head_lo), (0.0, head_y, head_hi), "Body")]
    for leg in LEGS:
        lo, hi = b[leg]
        cx = (lo.x + hi.x) * 0.5
        cy = (lo.y + hi.y) * 0.5
        # Down to the ground, not to the top of the hoof: the bone must reach
        # the contact point or the foot swings about a pivot above the floor
        # and the plant measures a stride the leg is not making.
        bones.append((leg, (cx, cy, hi.z), (cx, cy, lo.z), "Root"))

    for name, head, tail, _parent in bones:
        if (Vector(tail) - Vector(head)).length < 0.02:
            raise SystemExit("FAIL: bone %r came out %.4f m long. The parts it "
                             "is measured from are missing or flat."
                             % (name, (Vector(tail) - Vector(head)).length))
    return tuple(bones)


def build_armature(name="CritterRig"):
    """The skeleton, sized to whatever is standing in the scene right now.

    Called after the parts are built and before they are baked, which is the
    only window in which both facts are available: the parts exist, and they
    are still separate objects with names a bone can be matched against.
    """
    skeleton = measured_skeleton()
    arm_data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for bname, head, tail, _parent in skeleton:
        eb = arm_data.edit_bones.new(bname)
        eb.head, eb.tail = Vector(head), Vector(tail)
        eb.use_connect = False
        # Local Z toward -Y, so local X lands on world X and a fore/aft swing
        # is a rotation about the bone's own X. Asserted below, not trusted.
        eb.align_roll(Vector((0.0, -1.0, 0.0)))
        made[bname] = eb
    for bname, _h, _t, parent in skeleton:
        if parent:
            made[bname].parent = made[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def bake_and_group(meshes, tag=""):
    """folkrig's, with this rig's group table. See folkrig.bake_and_group."""
    return folkrig.bake_and_group(meshes, tag=tag, bone_of=bone_for)


def assert_roll_is_sagittal(arm, bones=LEGS + ("Head",)):
    """folkrig's, over the bones THIS rig swings.

    Four legs and a head, not two arms and two legs -- passing folkrig's
    default here would raise KeyError on ArmL and never check a single one of
    the bones that actually move.
    """
    return folkrig.assert_roll_is_sagittal(arm, bones=bones)


def walk_action(arm, mesh, name="walk", swing=17.0, nod=2.5):
    """A four-key diagonal walk on the same 24-frame loop the folk use.

    DIAGONAL, not lateral: front-left swings with back-right. That is the gait
    a cow and a sheep actually use at a walk, and it is also the only one that
    reads at 40 px -- a lateral pair looks like the animal is falling over.

    Swing is 17 degrees against the folk's 26. A quadruped carries its weight
    on four short legs and does not need to reach; at the folk's angle the legs
    scissor past each other and the animal looks like it is skating.

    Forward is NEGATIVE rotation about X, exactly as in folkrig: these front -Y
    and every leg bone hangs BELOW its pivot, so Rx(theta) sends the foot to +Y
    for positive theta. Backwards gives a moonwalking cow, which looks
    deliberate enough to survive a casual look.

    THE BODY HEIGHT IS NOT AUTHORED -- `_plant` drops the Root each frame by
    the measured lowest vertex, so changing the swing or the hoof still lands
    the feet. Four legs make this stricter than it is for the folk, not looser:
    the lowest of four feet is the one the whole animal has to stand on.
    """
    act = _begin(arm, name)
    pb = arm.pose.bones
    half = CYCLE // 2
    #        frame                  pair A   pair B
    keys = ((1,                     -swing,   swing),
            (1 + half // 2,            0.0,     0.0),
            (1 + half,               swing,  -swing),
            (1 + half + half // 2,     0.0,     0.0),
            (1 + CYCLE,             -swing,   swing))
    for f, a, bswing in keys:
        for leg in DIAGONAL_A:
            _key_rot(pb[leg], f, a)
        for leg in DIAGONAL_B:
            _key_rot(pb[leg], f, bswing)
        # The head bobs with the stride and the body barely moves. A walking
        # animal's head is the loose end of the whole system; the barrel is
        # the part that stays level, and pitching it reads as a limp.
        _key_rot(pb["Head"], f, nod if a < 0 else -nod)
        _key_rot(pb["Body"], f, 0.0)

    _plant(arm, mesh, act, range(1, CYCLE + 2))

    curves = action_fcurves(act)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
    if not curves:
        raise SystemExit("FAIL: the walk action came out with no fcurves. An "
                         "action assigned but unslotted takes keyframes that "
                         "go nowhere.")
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 1, CYCLE
    return act


def idle_action(arm, mesh, name="idle", length=72):
    """Standing in a field: a breath and one slow look around.

    Three seconds long and four degrees wide, and both numbers are deliberate.
    Livestock stand still for most of the game and a herd of them sharing one
    clip will drift into phase with each other; a long cycle makes that drift
    slow enough not to read, and a small range makes it not matter when it
    does. The folk idle is 48 frames for the same reason -- animals are calmer,
    so this one is longer still.
    """
    act = _begin(arm, name)
    pb = arm.pose.bones
    #        frame              body   head
    keys = ((1,                  0.0,   0.0),
            (1 + length // 3,    1.6,  -2.6),
            (1 + 2 * length // 3, 0.4,   2.2),
            (1 + length,         0.0,   0.0))
    for f, body, head in keys:
        _key_rot(pb["Body"], f, body)
        _key_rot(pb["Head"], f, head)
        for leg in LEGS:
            _key_rot(pb[leg], f, 0.0)
    _plant(arm, mesh, act, range(1, length + 2))
    return _finish(arm, act, length)


def graze_action(arm, mesh, name="graze", length=96):
    """Head down, crop, chew, head up. The clip that makes them livestock.

    POSITIVE rotation on the Head, and this is the one sign in the file that is
    not the same as the legs': the skull sits ABOVE its pivot, so Rx(theta)
    sends it toward -Y and downward for positive theta -- forward and down,
    which is where the grass is. The legs hang below their pivots and take the
    opposite sign. folkrig paid for this distinction with villagers who arched
    away from the tree they were chopping, and it is asserted there for the
    same reason it is stated here.

    The head DIPS and holds rather than pumping. An animation that returns to
    the top every second reads as a nervous tic; grazing is mostly the hold.
    """
    act = _begin(arm, name)
    pb = arm.pose.bones
    #        frame                 body   head
    keys = ((1,                     0.0,   2.0),    # up, looking about
            (1 + length // 6,       3.0,  30.0),    # down to the grass
            (1 + length // 3,       3.2,  33.0),    # cropping
            (1 + length // 2,       3.0,  28.0),    # chewing, still low
            (1 + 2 * length // 3,   3.2,  33.0),
            (1 + 5 * length // 6,   1.0,  10.0),    # coming up
            (1 + length,            0.0,   2.0))
    for f, body, head in keys:
        _key_rot(pb["Body"], f, body)
        _key_rot(pb["Head"], f, head)
        for leg in LEGS:
            _key_rot(pb[leg], f, 0.0)
    _plant(arm, mesh, act, range(1, length + 2))
    assert_head_dips(arm, mesh, name, 1 + length // 3)
    return _finish(arm, act, length)


def assert_head_dips(arm, mesh, name, frame, rest_frame=1, tol=0.02):
    """The muzzle must end up LOWER at `frame` than at rest.

    A reasoned sign convention is exactly the kind of thing that comes out
    backwards and still builds, renders and exports -- folkrig's equivalent
    caught villagers arching away from the tree they were chopping. So it is
    measured: the lowest vertex of the head half of the mesh, at the dip and at
    rest. A cow that grazes the sky is a picture nobody would think to check.
    """
    sc = bpy.context.scene

    def muzzle_z(f):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        pts = evaluated_points(mesh)
        front = sorted(pts, key=lambda p: p.y)[:max(8, len(pts) // 20)]
        return min(p.z for p in front)

    rest = muzzle_z(rest_frame)
    dip = muzzle_z(frame)
    sc.frame_set(1)
    if dip > rest - tol:
        raise SystemExit(
            "FAIL: %s raises the head instead of lowering it at frame %d. The "
            "muzzle sits at z=%.4f and rest is z=%.4f. The skull is ABOVE its "
            "pivot, so a POSITIVE Head rotation dips it -- the legs hang below "
            "theirs and take the opposite sign."
            % (name, frame, dip, rest))
    print("  %s dips the muzzle %.0f mm at frame %d"
          % (name, (rest - dip) * 1000.0, frame))


def all_actions(arm, mesh):
    """Every clip an animal needs, in one call.

    Walk LAST and left assigned, for the same reason folkrig does it: a static
    render taken after this shows the pose the game shows most of the time.
    Each clip goes to its own NLA track or the glTF exporter cannot see it --
    ACTIONS mode collects from NLA plus whatever is assigned, and an action
    merely sitting in bpy.data exports as nothing, with no error at all.
    """
    idle_action(arm, mesh)
    graze_action(arm, mesh)
    act = walk_action(arm, mesh)
    track = arm.animation_data.nla_tracks.new()
    track.name = act.name
    track.strips.new(act.name, 1, act)
    return [t.name for t in arm.animation_data.nla_tracks]
