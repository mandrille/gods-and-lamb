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

# name, head, tail, parent. Heads and tails come from villager.py's own
# constants -- a bone that does not start at the joint it drives is a bone that
# shears its part.
SKELETON = (
    ("Root",  (0.000, 0.0, 0.000), (0.000, 0.0, 0.220), None),
    ("Torso", (0.000, 0.0, 0.220), (0.000, 0.0, 0.480), "Root"),
    ("Head",  (0.000, 0.0, 0.460), (0.000, 0.0, 0.780), "Torso"),
    ("ArmL",  (-0.152, 0.0, 0.450), (-0.152, 0.0, 0.229), "Torso"),
    ("ArmR",  (0.152, 0.0, 0.450), (0.152, 0.0, 0.229), "Torso"),
    ("LegL",  (-0.066, 0.0, 0.210), (-0.066, 0.0, 0.000), "Root"),
    ("LegR",  (0.066, 0.0, 0.210), (0.066, 0.0, 0.000), "Root"),
)

# Which part goes on which bone, matched on the name AFTER the tag prefix.
# Order matters: the first match wins, so "ArmL" must be tested before "Arm".
GROUPS = (
    ("ArmL",  ("_ArmL", "_HandL")),
    # The staff goes on the hand that holds it, not on the torso. On the torso
    # it stays vertical while the arm swings out from under it.
    ("ArmR",  ("_ArmR", "_HandR", "_Staff")),
    ("LegL",  ("_LegL", "_BootL")),
    ("LegR",  ("_LegR", "_BootR")),
    ("Head",  ("_Head", "_Hair", "_Eye", "_Kerchief", "_Sprig")),
    ("Torso", ("_Tunic", "_Apron", "_Vest", "_Hem", "_Strap", "_Pack",
               "_Bedroll")),
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


def bake_and_group(meshes, tag=""):
    """Bake each part's own modifiers, then put it in exactly one vertex group.

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
    unclaimed = [ob.name for ob in meshes
                 if bone_for(ob.name[len(tag):] if tag
                             and ob.name.startswith(tag) else ob.name) is None]
    if unclaimed:
        raise SystemExit("FAIL: %d part(s) match no bone in folkrig.GROUPS: %s. "
                         "Add the name or rename the part -- an unbound part "
                         "stays behind when the character walks off."
                         % (len(unclaimed), ", ".join(unclaimed)))

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
        vg = ob.vertex_groups.new(name=bone_for(short))
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
