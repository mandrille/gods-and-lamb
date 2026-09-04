"""Read a written GLB back and prove it carries what it was supposed to.

A GLB that is missing every tag is a valid file of a plausible size. It opens,
it renders, and nothing anywhere says the metadata went. The only way to know
is to reopen the bytes and look, which is what this does.

Parses the container by hand rather than importing the file back into Blender:
a re-import is slow, it needs a scene, and it would be testing Blender's
importer rather than the file.
"""
import json
import struct


def read_json_chunk(path):
    """The glTF JSON out of a binary GLB. Raises if it is not one."""
    with open(path, "rb") as fh:
        magic, version, _length = struct.unpack("<III", fh.read(12))
        if magic != 0x46546C67:
            raise SystemExit("FAIL: %s is not a GLB (bad magic 0x%08X)."
                             % (path, magic))
        if version != 2:
            raise SystemExit("FAIL: %s is glTF version %d, expected 2."
                             % (path, version))
        while True:
            head = fh.read(8)
            if len(head) < 8:
                raise SystemExit("FAIL: %s has no JSON chunk." % path)
            clen, ctype = struct.unpack("<II", head)
            body = fh.read(clen)
            if ctype == 0x4E4F534A:          # 'JSON'
                return json.loads(body.decode("utf-8"))


def assert_glb_readback(path, want_extras=("lamb_id",), want_skin=False,
                        want_animation=False, want_color0=False):
    """Reopen a GLB and fail if it is missing what it was exported for.

    `want_extras` is the check that pays for this whole module. export_extras
    defaults to False in the Blender exporter, and without it the file is
    valid, plausibly sized, and carries none of the project vocabulary.
    """
    doc = read_json_chunk(path)
    nodes = doc.get("nodes", [])
    meshes = doc.get("meshes", [])
    faults = []

    if not meshes:
        faults.append("no meshes at all")

    for key in want_extras:
        carriers = [n for n in nodes if key in (n.get("extras") or {})]
        if not carriers:
            faults.append("no node carries extras[%r] -- export_extras was "
                          "almost certainly False" % key)

    if want_skin and not doc.get("skins"):
        faults.append("no skins: the mesh exported without its armature, so "
                      "it is a static character")
    if want_animation and not doc.get("animations"):
        faults.append("no animations: the actions did not come across")
    # A folded mesh carries its ALBEDO in COLOR_0 and ships one white
    # material. Without the channel it is not a slightly wrong asset, it is a
    # white one -- and the exporter only emits COLOR_0 when a material reads
    # the attribute, which is one un-wired material away from silently gone.
    has_color0 = any("COLOR_0" in p.get("attributes", {})
                     for m in meshes for p in m.get("primitives", []))
    if want_color0 and not has_color0:
        faults.append("no COLOR_0: this mesh was folded to one material and "
                      "carries its albedo per vertex, so without the channel "
                      "it renders white. vfold.wire_all() did not reach it.")

    if faults:
        raise SystemExit("FAIL: %s did not export what it was asked for:%s  %s"
                         % (path, chr(10), (chr(10) + "  ").join(faults)))

    return {
        "nodes": len(nodes),
        "meshes": len(meshes),
        "skins": len(doc.get("skins", [])),
        "animations": len(doc.get("animations", [])),
        "materials": len(doc.get("materials", [])),
        "has_color0": any("COLOR_0" in p.get("attributes", {})
                          for m in meshes for p in m.get("primitives", [])),
    }
