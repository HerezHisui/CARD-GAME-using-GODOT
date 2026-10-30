"""Run with portable Blender --background --python tools/audit_janitor.py."""
import bpy
import json
import numpy as np
from pathlib import Path
from mathutils import Vector

SOURCE = Path("C:/Users/0stef/Downloads/meshy-model-2026-10-30T09-10-58-481Z.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
mesh = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
points = [mesh.matrix_world @ vertex.co for vertex in mesh.data.vertices]
print("AUDIT", json.dumps({
    "vertices": len(points), "triangles": len(mesh.data.polygons),
    "minimum": [min(p[i] for p in points) for i in range(3)],
    "maximum": [max(p[i] for p in points) for i in range(3)],
    "images": [(im.name, list(im.size)) for im in bpy.data.images],
    "modifiers": [m.type for m in mesh.modifiers],
    "materials": [m.name for m in mesh.data.materials],
}))
for material in mesh.data.materials:
    for node in material.node_tree.nodes:
        print("NODE", node.type, node.name,
              [(socket.name, list(socket.default_value) if hasattr(socket.default_value, '__len__')
                else socket.default_value) for socket in node.inputs
               if not socket.is_linked and socket.type in {'VECTOR', 'VALUE'}])
image = bpy.data.images['texture_0']
pixels = np.array(image.pixels[:], dtype=np.float32).reshape(image.size[1], image.size[0], 4)
bright = set()
for loop in mesh.data.loops:
    uv = mesh.data.uv_layers.active.data[loop.index].uv
    u = (uv.x * 15.9871788 + 0.000011) % 1
    v = (uv.y * 16.0035667 - 15.00357151) % 1
    color = pixels[int(v * (image.size[1] - 1)), int(u * (image.size[0] - 1))]
    if min(color[:3]) > 0.3 and max(color[:3]) > 0.55:
        bright.add(loop.vertex_index)
for sign in [-1, 1]:
    region = np.array([list(points[i]) for i in bright if points[i].x * sign > 0.05])
    print('HAND', sign, len(region), 'percentiles', np.percentile(region, [0, 10, 50, 90, 100], axis=0).tolist())
# Save an inspection source separately from the supplied asset.
output = Path(__file__).resolve().parents[1] / "assets/characters/janitor/source"
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(output / "janitor_inspected.blend"))
