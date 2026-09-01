"""Blender to Godot: the glTF flag set, and the two shapes of export.

The flags are the whole of this module and every one of them is load-bearing.
They are the set the parent project verified against Blender's own exporter
source, carried over with the skinning ones kept live because our folk are
rigged.

`export_extras` is the one that will bite. It defaults to FALSE, and the
obvious export call writes a valid GLB of a plausible size containing NONE of
the `lamb_*` data, with no warning of any kind. Every tag, silently absent.
`verify_export.assert_glb_readback()` exists for exactly that.

`export_apply` bakes modifiers -- which is what we want for a bevel -- and
SKIPS armature modifiers, which is what keeps a skin a skin. Do not replace it
with `object.convert()`, which does not make that distinction and would freeze
every follower into its rest pose.
"""
import os

import bpy

FLAGS = dict(
    export_format="GLB",
    # Bakes Bevel and WeightedNormal. Skips Armature, so the skin survives.
    export_apply=True,
    # DEFAULTS TO FALSE. Without it every lamb_* tag is silently gone.
    export_extras=True,
    export_yup=True,
    export_skins=True,
    export_animations=True,
    export_rest_position_armature=True,
    export_leaf_bone=False,
    export_def_bones=False,
    export_cameras=False,
    export_lights=False,
    export_materials="EXPORT",
    export_normals=True,
    export_tangents=False,
    use_visible=False,
)


def _export(path, use_selection):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kw = dict(FLAGS)
    kw["use_selection"] = use_selection
    try:
        bpy.ops.export_scene.gltf(filepath=path, **kw)
    except TypeError as exc:
        # The exporter gains and loses keywords between versions. Drop the ones
        # this build does not know rather than failing the whole export -- but
        # say which, because a silently dropped flag is how export_extras stops
        # being set.
        bad = [k for k in kw if k not in _known_keywords()]
        if not bad:
            raise
        print("  NOTE: exporter does not accept %s on this Blender (%s); "
              "dropped." % (", ".join(sorted(bad)), exc))
        for k in bad:
            kw.pop(k)
        bpy.ops.export_scene.gltf(filepath=path, **kw)
    return path


def _known_keywords():
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    return {p.identifier for p in props}


def select_only(objects):
    bpy.ops.object.select_all(action="DESELECT")
    keep = [o for o in objects if o.name in bpy.data.objects]
    for ob in keep:
        ob.select_set(True)
    if keep:
        bpy.context.view_layer.objects.active = keep[0]
    return keep


def export_static(objects, path):
    """One static asset: a tile, a plant, a building. No armature."""
    select_only(objects)
    return _export(path, use_selection=True)


def export_rigged(armature, meshes, path):
    """A folk asset: armature, skinned mesh and every action on it.

    The ARMATURE has to be in the selection or the exporter writes the mesh
    with no skin and no animation, which looks like a perfectly good static
    character until nothing moves.
    """
    select_only([armature] + list(meshes))
    return _export(path, use_selection=True)
