"""A skeleton and a walk cycle for the folk.

Deliberately the SMALLEST rig that can walk: seven bones, rigid skinning, one
vertex group per part at weight 1.0, no deform hierarchy below the knee. The
followers are 40 px tall and the whole style is stacked boxes -- a bone per
finger would cost skinning weight in the vertex buffer and be invisible.

    Root ------ Torso ------ Head
      |            |
      |            +-------- ArmL, ArmR
      |
      +--------- LegL, LegR

WHY THE PARTS ARE NOT MERGED FIRST. Every other target in this project merges
an asset into one mesh, and a rig cannot: rigid skinning assigns each PART to a
bone, and after the merge there are no parts, only one soup of triangles whose
vertices would have to be re-sorted into groups geometrically. So `build()`
still returns loose parts and `rig()` binds them, and only then is a single
skinned mesh joined out of them -- with the groups already correct.

BONE ROLL is the one thing here that cannot be eyeballed. Arms and legs swing
fore and aft, which is a rotation about WORLD X, and a bone that points
straight down has no natural roll -- Blender picks one. If it picks wrong the
leg swings sideways and the walk becomes a curtsy. `align_roll` sets it and
`assert_roll_is_sagittal` MEASURES it by actually rotating the bone and looking
at where the tail went, because the roll number itself is not readable.
"""
import math

import bpy
from mathutils import Euler, Vector

# Heads and tails come from folkbody.py's own constants -- a bone that does
# not start at the joint it drives is a bone that shears its part. folkbody
# is the one place that knows where the joints are now; this used to be a
# tuple hardcoded here, retyped from villager.py by hand.
from folkbody import SKELETON

# Which part goes on which bone, matched on the name AFTER the tag prefix.
# Order matters: the first match wins, so "ArmL" must be tested before "Arm".
GROUPS = (
    # A HELD tool goes on the hand that holds it -- on the torso it stays
    # vertical while the arm swings out from under it (the original `_Staff`
    # lesson). A SLUNG or two-handed prop (lute, satchel, quiver) goes on the
    # torso, or the arm swing drags it across the body every stride.
    ("ArmL",  ("_ArmL", "_HandL", "_Bow", "_Book", "_Rock")),
    ("ArmR",  ("_ArmR", "_HandR", "_Staff", "_Axe", "_Hammer", "_Bottle",
               "_Pick")),
    ("LegL",  ("_LegL", "_BootL")),
    ("LegR",  ("_LegR", "_BootR")),
    ("Head",  ("_Head", "_Hair", "_Eye", "_Kerchief", "_Sprig", "_Beard",
               "_Cap", "_Hood", "_Veil", "_Brow", "_Leaf", "_Helm")),
    ("Torso", ("_Tunic", "_Apron", "_Vest", "_Hem", "_Strap", "_Pack",
               "_Bedroll", "_Lute", "_Satchel", "_Belt", "_Pouch", "_Stole",
               "_Quiver", "_Rope", "_Emblem", "_Cassock", "_Sack")),
)

FPS = 24
CYCLE = 24          # frames; frame CYCLE+1 is a copy of frame 1


def bone_for(name):
    """The bone a part belongs on, or None. Unclaimed parts are a FAILURE, not
    a default -- silently dropping a part onto the root is how a satchel ends
    up floating where the character used to be."""
    for bone, keys in GROUPS:
        if any(k in name for k in keys):
            return bone
    return None


def action_fcurves(act):
    """Every fcurve on an action, whichever API this Blender has.

    Blender 5.2 REMOVED `Action.fcurves`. Actions are layered and slotted now,
    and the curves live at layers[] -> strips[] -> channelbags[] -> fcurves.
    `keyframe_insert` still creates the slot and the channelbag on its own, so
    authoring is unchanged -- but any code that counts curves to prove the
    action is not empty has to walk the new path, and a bare `act.fcurves`
    raises AttributeError rather than returning nothing.
    """
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def build_armature(name="FolkRig"):
    arm_data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for bname, head, tail, parent in SKELETON:
        eb = arm_data.edit_bones.new(bname)
        eb.head, eb.tail = Vector(head), Vector(tail)
        eb.use_connect = False
        # Local Z toward -Y, so local X lands on world X and a fore/aft swing
        # is a rotation about the bone's own X. Asserted below, not trusted.
        eb.align_roll(Vector((0.0, -1.0, 0.0)))
        made[bname] = eb
    for bname, _h, _t, parent in SKELETON:
        if parent:
            made[bname].parent = made[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def bake_and_group(meshes, tag="", bone_of=None):
    """Bake each part's own modifiers, then put it in exactly one vertex group.

    `bone_of` is the name-to-bone rule, and it defaults to this rig's. The
    sibling quadruped rig passes its own: the bake order below and the rigid
    one-group-per-part bind are properties of the KIT, not of having two legs,
    and duplicating them into critterrig would mean two copies of the one
    ordering fact this file exists to record.

    THE ORDER IS THE WHOLE POINT and it cost a wrong build to learn. Joining
    first and baking after does not work: `join` keeps the ACTIVE object's
    modifier stack and throws the rest away, so the head's Bevel was applied to
    all nineteen parts and a 516-triangle villager came out at 2052. Baking per
    part first means each box keeps its own bevel -- or its own lack of one --
    and the join is then a pure concatenation.

    Rigid skinning, not automatic weights. Auto weights on stacked boxes bleed
    the tunic into the arm and tear a shoulder on the first frame; one bone per
    part is exactly predictable, which at 40 px is worth more than a soft elbow.
    """
    bone_of = bone_of or bone_for
    unclaimed = [ob.name for ob in meshes
                 if bone_of(ob.name[len(tag):] if tag
                            and ob.name.startswith(tag) else ob.name) is None]
    if unclaimed:
        raise SystemExit("FAIL: %d part(s) match no bone in %s.GROUPS: %s. "
                         "Add the name or rename the part -- an unbound part "
                         "stays behind when the character walks off."
                         % (len(unclaimed), bone_of.__module__,
                            ", ".join(unclaimed)))

    bpy.ops.object.select_all(action="DESELECT")
    for ob in meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    # Bakes Bevel and Weighted Normal on every selected object independently,
    # each against its OWN stack. The custom normals survive into the result.
    bpy.ops.object.convert(target="MESH")

    for ob in meshes:
        short = ob.name[len(tag):] if tag and ob.name.startswith(tag) else ob.name
        for vg in list(ob.vertex_groups):
            ob.vertex_groups.remove(vg)
        vg = ob.vertex_groups.new(name=bone_of(short))
        vg.add(range(len(ob.data.vertices)), 1.0, "REPLACE")
    return len(meshes)


def attach(arm, mesh):
    """One Armature modifier on the finished skinned mesh.

    After the join, so there is exactly one -- which is also what a glTF skin
    is. Nineteen armature modifiers on nineteen objects would export as
    nineteen skinned meshes and nineteen draw calls.
    """
    mesh.parent = arm
    mesh.matrix_parent_inverse = arm.matrix_world.inverted()
    m = mesh.modifiers.new("Armature", "ARMATURE")
    m.object = arm
    idx = list(mesh.modifiers).index(m)
    if idx:
        mesh.modifiers.move(idx, 0)
    return m


def _key_rot(pb, frame, rx):
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = Euler((math.radians(rx), 0.0, 0.0), "XYZ")
    pb.keyframe_insert("rotation_euler", frame=frame)


def _lift_axis(arm, mesh):
    """Which component of Root's pose location raises the character.

    Pose-bone location is in BONE space, and the Root bone points along +Z, so
    its local Y is world up and its local Z is world -Y. Writing the bob to
    `.z` -- the obvious guess, and the first thing this did -- slides the
    character BACKWARDS instead of lifting it, which in a side view of a walk
    looks like a stride.

    So it is measured: nudge each axis by 1 cm and keep the one that actually
    moved the mesh up.
    """
    pb = arm.pose.bones["Root"]
    base = min(p.z for p in evaluated_points(mesh))
    best, best_gain = None, 0.0
    for axis in range(3):
        v = [0.0, 0.0, 0.0]
        v[axis] = 0.01
        pb.location = v
        bpy.context.view_layer.update()
        gain = min(p.z for p in evaluated_points(mesh)) - base
        if gain > best_gain:
            best, best_gain = axis, gain
    pb.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    if best is None or best_gain < 0.008:
        raise SystemExit("FAIL: no component of Root.location lifts the mesh. "
                         "The rig is not driving the skin at all.")
    return best


def walk_action(arm, mesh, name="walk", swing=26.0, arm_swing=18.0):
    """A four-key walk on a 24-frame loop, with the feet PLANTED by measurement.

    Contact, pass, contact, pass, contact -- the last is a copy of the first, so
    the cycle closes. A three-key walk reads as a limp, because the two contacts
    are not the same distance from the pass.

    Forward is NEGATIVE rotation about X: the character fronts -Y, and for a
    point below the pivot Rx(theta) sends it to +Y for positive theta. Backwards
    gives a moonwalk, which looks deliberate enough to survive a casual look.

    THE BODY HEIGHT IS NOT AUTHORED. One bone per leg means the foot swings on
    an arc about the hip, so a 26 degree stride lifts the boot's leading corner
    six centimetres -- on a 0.855 m character, both feet hovering at every
    contact. Deriving the drop from leg length and cos(swing) gets the leg but
    not the boot, which is 15 cm deep and tilts with it. So each key is posed
    first and the root is then dropped by whatever the MEASURED lowest vertex
    turns out to be. Change the swing, change the boot, and the feet still land.
    """
    arm.animation_data_create()
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act

    pb = arm.pose.bones
    half = CYCLE // 2
    keys = (
        (1,                    -swing,  swing),
        (1 + half // 2,           0.0,    0.0),
        (1 + half,              swing, -swing),
        (1 + half + half // 2,    0.0,    0.0),
        (1 + CYCLE,            -swing,  swing),
    )
    for f, left, right in keys:
        _key_rot(pb["LegL"], f, left)
        _key_rot(pb["LegR"], f, right)
        # Arms counter-swing: the arm opposite the forward leg goes forward.
        _key_rot(pb["ArmL"], f, -left * (arm_swing / swing))
        _key_rot(pb["ArmR"], f, -right * (arm_swing / swing))

    # Planted on EVERY frame, not on the five keys. Planting the keys alone was
    # the first attempt and assert_feet_on_floor caught it: the leg rotations
    # ease on a bezier, so the height between two correct keys is whatever the
    # curve felt like, and the villager sank 9.9 mm through the ground at
    # frame 5. Twenty-five keys on one channel is nothing to store and it makes
    # the vertical motion exactly the foot arc -- which is also where a walk's
    # bob comes from, so the bob is now measured rather than invented.
    axis = _lift_axis(arm, mesh)
    root = pb["Root"]
    for f in range(1, CYCLE + 2):
        bpy.context.scene.frame_set(f)
        root.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
        drop = min(p.z for p in evaluated_points(mesh))
        v = [0.0, 0.0, 0.0]
        v[axis] = -drop
        root.location = v
        root.keyframe_insert("location", frame=f)
    bpy.context.scene.frame_set(1)

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


# ------------------------------------------------------------------- asserts
def evaluated_points(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [ob.matrix_world @ v.co.copy() for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def assert_rigid_weights(meshes):
    """Every vertex in exactly one group at 1.0. A vertex shared between two
    bones on a box rig is a modelling error, not a soft edge."""
    bad = []
    for ob in meshes:
        for v in ob.data.vertices:
            if len(v.groups) != 1 or abs(v.groups[0].weight - 1.0) > 1e-4:
                bad.append("%s v%d groups=%d" % (ob.name, v.index, len(v.groups)))
                break
    if bad:
        raise SystemExit("FAIL: skinning is not rigid: %s" % "; ".join(bad[:6]))
    return len(meshes)


def assert_roll_is_sagittal(arm, bones=("LegL", "LegR", "ArmL", "ArmR")):
    """Rotate each swinger about its LOCAL X and check the tail went fore/aft.

    The roll number is unreadable, so this measures the thing the roll is FOR.
    Without it the first sign that a leg swings sideways is a render, and by
    then the walk has been keyframed against the wrong axis.
    """
    bad = []
    for bname in bones:
        pb = arm.pose.bones[bname]
        pb.rotation_mode = "XYZ"
        rest_tail = (arm.matrix_world @ pb.bone.matrix_local).translation.copy()
        rest_tail = arm.matrix_world @ pb.bone.tail_local
        pb.rotation_euler = Euler((math.radians(20.0), 0.0, 0.0), "XYZ")
        bpy.context.view_layer.update()
        moved = arm.matrix_world @ pb.tail
        d = moved - rest_tail
        pb.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
        bpy.context.view_layer.update()
        if abs(d.y) < 2.0 * abs(d.x):
            bad.append("%s moved (%.4f, %.4f, %.4f) -- sideways, not fore/aft"
                       % (bname, d.x, d.y, d.z))
    if bad:
        raise SystemExit("FAIL: bone roll is not sagittal: %s. align_roll got "
                         "the wrong axis, so the walk swings out to the side."
                         % "; ".join(bad))
    return len(bones)


def assert_action_deforms(arm, meshes, frames=(1, 7, 13), min_travel=0.02):
    """The mesh actually MOVES between keyframes.

    An action can exist, be assigned, own fcurves and drive nothing -- an
    unslotted action, a missing Armature modifier, or an empty vertex group all
    present as a perfectly still character with a perfectly good rig.
    """
    sc = bpy.context.scene
    sc.frame_set(frames[0])
    bpy.context.view_layer.update()
    base = {ob.name: evaluated_points(ob) for ob in meshes}
    worst = 0.0
    for f in frames[1:]:
        sc.frame_set(f)
        bpy.context.view_layer.update()
        for ob in meshes:
            now = evaluated_points(ob)
            for a, b in zip(base[ob.name], now):
                worst = max(worst, (a - b).length)
    sc.frame_set(frames[0])
    if worst < min_travel:
        raise SystemExit("FAIL: the rig is a statue -- the largest vertex "
                         "travel across frames %s was %.4f m, under %.3f. The "
                         "action exists and moves nothing."
                         % (list(frames), worst, min_travel))
    return worst


def assert_feet_on_floor(arm, meshes, tol=0.004):
    """No frame floats and no frame sinks.

    Checked on EVERY frame of the cycle, not on the keys: the keys are the
    frames that were explicitly planted, so checking those would be checking
    that an assignment assigned. The interpolation between them is where a
    character wades through the ground.
    """
    sc = bpy.context.scene
    worst_lo, worst_hi, at = 0.0, 0.0, (0, 0)
    for f in range(1, CYCLE + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        z = min(min(p.z for p in evaluated_points(ob)) for ob in meshes)
        if z < worst_lo:
            worst_lo, at = z, (f, at[1])
        if z > worst_hi:
            worst_hi, at = z, (at[0], f)
    sc.frame_set(1)
    if -worst_lo > tol or worst_hi > tol:
        raise SystemExit("FAIL: the walk does not stay on the floor -- sinks "
                         "%.4f m at frame %d, floats %.4f m at frame %d "
                         "(tolerance %.3f)."
                         % (-worst_lo, at[0], worst_hi, at[1], tol))
    return worst_lo, worst_hi


def assert_cycle_closes(arm, meshes, tol=1e-5):
    """Frame 1 and frame CYCLE+1 must be the same pose, or the walk pops."""
    sc = bpy.context.scene
    sc.frame_set(1)
    bpy.context.view_layer.update()
    first = {ob.name: evaluated_points(ob) for ob in meshes}
    sc.frame_set(1 + CYCLE)
    bpy.context.view_layer.update()
    worst = 0.0
    for ob in meshes:
        for a, b in zip(first[ob.name], evaluated_points(ob)):
            worst = max(worst, (a - b).length)
    sc.frame_set(1)
    if worst > tol:
        raise SystemExit("FAIL: the walk does not loop -- frame 1 and frame %d "
                         "differ by %.6f m. The character will pop every cycle."
                         % (1 + CYCLE, worst))
    return worst


# ------------------------------------------------------- the other three clips
#
# Walk is the load-bearing one and it lives above, with its measured foot
# planting. These three are cheaper: nothing here takes a stride, so the feet
# stay where the rest pose put them and the only vertical motion is deliberate.
#
# All four end up as SEPARATE glTF animations, which needs each action pushed
# to its own NLA track -- the exporter's default ACTIONS mode collects actions
# from NLA plus whatever is currently assigned. An action merely created and
# left in bpy.data is invisible to it, and the export comes back with one clip
# and no error at all.


def _plant(arm, mesh, act, frames):
    """Drop the Root each frame so the lowest vertex sits on z=0.

    Same measured approach as the walk, and for the same reason: a pose that
    bends the torso or swings the arms moves the boots as well, and deriving
    the drop from the numbers that were authored gets the bone but not the
    geometry hanging off it.
    """
    axis = _lift_axis(arm, mesh)
    root = arm.pose.bones["Root"]
    for f in frames:
        bpy.context.scene.frame_set(f)
        root.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
        drop = min(p.z for p in evaluated_points(mesh))
        v = [0.0, 0.0, 0.0]
        v[axis] = -drop
        root.location = v
        root.keyframe_insert("location", frame=f)
    bpy.context.scene.frame_set(1)


def assert_bends_forward(arm, mesh, name, frame, rest_frame=1, tol=0.012):
    """The upper body must move FORWARD at `frame`, not backward.

    Reasoned sign conventions are exactly the kind of thing that comes out
    backwards and still builds, renders and exports -- the villagers arched
    away from the tree they were chopping for a whole session because the
    torso copied the walk's leg sign. So it is measured: take the mean Y of
    the vertices above the hip at the bent frame and at rest, and require the
    bent one to be further toward -Y, which is the way this character faces.
    """
    sc = bpy.context.scene

    def upper_mean_y(f):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        pts = [p for p in evaluated_points(mesh) if p.z > 0.42]
        if not pts:
            raise SystemExit("FAIL: %s has no vertices above the hip to "
                             "measure a lean with." % name)
        return sum(p.y for p in pts) / len(pts)

    rest = upper_mean_y(rest_frame)
    bent = upper_mean_y(frame)
    sc.frame_set(1)
    if bent > rest - tol:
        raise SystemExit(
            "FAIL: %s leans the WRONG WAY at frame %d. The upper body sits at "
            "y=%.4f and rest is y=%.4f; the character fronts -Y, so a forward "
            "bend must be MORE negative by at least %.3f. Torso and Head take "
            "POSITIVE rotation to lean forward (their tails are above the "
            "pivot); Arms and Legs take NEGATIVE (theirs hang below)."
            % (name, frame, bent, rest, tol))
    print("  %s leans forward %.1f mm at frame %d"
          % (name, (rest - bent) * 1000.0, frame))


def _finish(arm, act, last):
    curves = action_fcurves(act)
    if not curves:
        raise SystemExit("FAIL: action %r came out with no fcurves. An action "
                         "assigned but unslotted takes keyframes that go "
                         "nowhere." % act.name)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
    # Push to its own NLA track and clear the active slot, so the next action
    # starts from a clean armature rather than layering onto this one.
    track = arm.animation_data.nla_tracks.new()
    track.name = act.name
    track.strips.new(act.name, 1, act)
    arm.animation_data.action = None
    return act


def _begin(arm, name):
    arm.animation_data_create()
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    return act


def idle_action(arm, mesh, name="idle", length=48):
    """Standing about: a slow breath and the faintest sway.

    Deliberately small. An idle with visible movement reads as fidgeting, and
    with a dozen villagers standing around it turns the island into a crowd of
    people who all need the lavatory. The whole range here is four degrees.
    """
    act = _begin(arm, name)
    pb = arm.pose.bones
    keys = ((1, 0.0, 1.5), (1 + length // 2, 2.0, -1.5), (1 + length, 0.0, 1.5))
    for f, torso, arms in keys:
        _key_rot(pb["Torso"], f, torso)
        _key_rot(pb["Head"], f, -torso * 0.5)
        _key_rot(pb["ArmL"], f, arms)
        _key_rot(pb["ArmR"], f, arms)
    _plant(arm, mesh, act, range(1, length + 2))
    return _finish(arm, act, length)


def pickup_action(arm, mesh, name="pickup", length=30):
    """Bend, take something off the ground, straighten up.

    One cycle rather than a one-shot, because the follower does this for a few
    seconds at a time and a clip that ends leaves them frozen mid-bend. The
    hold at the bottom is what makes it read as PICKING something up instead
    of as bobbing.
    """
    act = _begin(arm, name)
    pb = arm.pose.bones
    # SIGNS ARE NOT THE SAME FOR EVERY BONE, and getting this backwards is
    # what made them arch away from the thing they were picking up.
    #
    # Rx(theta) sends a point at (0,0,+1) to (0,-sin, cos) and a point at
    # (0,0,-1) to (0,+sin,-cos). The character fronts -Y. So for a bone whose
    # tail is ABOVE its head -- Torso, Head -- POSITIVE leans forward; for one
    # whose tail hangs BELOW -- Arms, Legs -- NEGATIVE swings forward. The walk
    # only ever moves legs and arms, so it never had to state the other half of
    # the rule, and the first version of this action copied its sign.
    #     frame              torso   arms    head
    keys = ((1,               5.0,  -10.0,   2.0),
            (1 + length // 4,    46.0,  -68.0,  14.0),
            (1 + length // 2,    50.0,  -78.0,  16.0),   # the hold, down low
            (1 + 3 * length // 4, 24.0,  -34.0,   8.0),
            (1 + length,          5.0,  -10.0,   2.0))
    for f, torso, arms, head in keys:
        _key_rot(pb["Torso"], f, torso)
        _key_rot(pb["Head"], f, head)
        _key_rot(pb["ArmL"], f, arms)
        _key_rot(pb["ArmR"], f, arms)
    _plant(arm, mesh, act, range(1, length + 2))
    assert_bends_forward(arm, mesh, name, 1 + length // 2)
    return _finish(arm, act, length)


def chop_action(arm, mesh, name="chop", length=24):
    """Axe up, axe down, recover.

    The timing is the whole thing: the windup is slow and the strike is one
    frame. Evenly-spaced keys give a swing that looks like stirring soup.
    """
    act = _begin(arm, name)
    pb = arm.pose.bones
    # Same sign rule as pickup: +torso leans FORWARD, -arms swing forward.
    # So the windup leans back with the arms raised behind, and the strike
    # throws the torso forward while the arms come down in front.
    #     frame       torso   arms
    keys = ((1,           5.0,  -25.0),   # ready, axe low in front
            (1 + 9,     -14.0,  105.0),   # windup: lean back, axe up behind
            (1 + 11,    -11.0,   99.0),   # the tiny hitch before the strike
            (1 + 13,     34.0,  -55.0),   # STRIKE, one frame of travel
            (1 + 17,     24.0,  -40.0),   # follow through
            (1 + length,  5.0,  -25.0))
    for f, torso, arms in keys:
        _key_rot(pb["Torso"], f, torso)
        _key_rot(pb["Head"], f, torso * 0.4)
        _key_rot(pb["ArmL"], f, arms)
        _key_rot(pb["ArmR"], f, arms)
    _plant(arm, mesh, act, range(1, length + 2))
    # Frame 14 is the strike -- the one frame the whole action is about.
    assert_bends_forward(arm, mesh, name, 1 + 13)
    return _finish(arm, act, length)


def all_actions(arm, mesh):
    """Every clip a follower needs, in one call.

    Walk LAST and left assigned: the walk is what a follower plays most of the
    time, and leaving the armature holding it means a look-dev render or a
    static export shows a character mid-stride rather than in rest pose.
    """
    idle_action(arm, mesh)
    pickup_action(arm, mesh)
    chop_action(arm, mesh)
    act = walk_action(arm, mesh)
    track = arm.animation_data.nla_tracks.new()
    track.name = act.name
    track.strips.new(act.name, 1, act)
    return [t.name for t in arm.animation_data.nla_tracks]
