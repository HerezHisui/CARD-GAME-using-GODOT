"""Read-only source diagnosis. Isolate transforms and report the actual failing skin edges."""
import bpy
import json
import numpy as np
from pathlib import Path
from mathutils import Quaternion, Vector

folder = Path(__file__).resolve().parents[1] / 'assets/characters/janitor'
bpy.ops.wm.open_mainfile(filepath=str(folder / 'source/janitor.blend'))
rig = bpy.data.objects['JanitorRig']
mesh = bpy.data.objects['JanitorMesh']
rest = np.array([v.co[:] for v in mesh.data.vertices])
edges = np.array([e.vertices[:] for e in mesh.data.edges])
lengths = np.linalg.norm(rest[edges[:, 1]] - rest[edges[:, 0]], axis=1)
valid = lengths > .001
report = {'cases': [], 'bones': [], 'worst': []}

def reset():
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    for bone in rig.pose.bones:
        bone.location = Vector()
        bone.rotation_quaternion = Quaternion()
        bone.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()

def measure(name):
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    actual = np.array([v.co[:] for v in evaluated.data.vertices])
    ratios = np.linalg.norm(actual[edges[:, 1]] - actual[edges[:, 0]], axis=1) / np.maximum(1e-8, lengths)
    result = {'case': name, 'p99': float(np.percentile(ratios[valid], 99)),
              'max': float(ratios[valid].max()), 'motion': float(np.linalg.norm(actual-rest, axis=1).max()),
              'edges_over_2_5': int(sum((ratios > 2.5) & valid))}
    report['cases'].append(result)
    print('ISOLATION', result)
    return ratios

reset()
measure('rest_no_animation_no_cloth')
for name in ['Arm_L', 'Arm_R', 'Forearm_L', 'Forearm_R', 'Hand_L', 'Hand_R', 'Chest']:
    reset()
    bone = rig.pose.bones[name]
    basis = rig.data.bones[name].matrix_local.to_quaternion()
    bone.rotation_quaternion = basis.inverted() @ Quaternion((1, 0, 0), -.15) @ basis
    measure(name + '_only_0.15rad_no_cloth')
reset()
for b in rig.pose.bones:
    if b.name.startswith('Cloth_'):
        b.location = rig.data.bones[b.name].matrix_local.to_3x3().inverted() @ Vector((0, -.006, 0))
measure('cloth_translation_only_6mm_no_animation')
reset()
rig.animation_data.action = bpy.data.actions['idle']
bpy.context.scene.frame_set(1)
ratios = measure('authored_holding_no_runtime_cloth')
for index in np.argsort(np.where(valid, ratios, 0))[-12:]:
    item = {'ratio': float(ratios[index]), 'vertices': []}
    for vertex_index in edges[index]:
        vertex = mesh.data.vertices[int(vertex_index)]
        weights = {mesh.vertex_groups[g.group].name: round(g.weight, 5) for g in vertex.groups}
        item['vertices'].append({'id': int(vertex_index), 'position': list(vertex.co), 'weights': weights})
    report['worst'].append(item)
for bone in rig.data.bones:
    if bone.name.startswith('Cloth_'):
        continue
    report['bones'].append({'name': bone.name, 'head': list(bone.head_local), 'tail': list(bone.tail_local),
                            'length': bone.length, 'determinant': bone.matrix_local.determinant(),
                            'pose_angle': rig.pose.bones[bone.name].rotation_quaternion.angle})

# Report duplicate-position seams, loose vertices and welded geometric components separately.
canonical = {}
mapping = []
for p in rest:
    key = tuple(np.round(p, 6))
    canonical.setdefault(key, len(canonical))
    mapping.append(canonical[key])
parent = list(range(len(canonical)))
def root(i):
    while parent[i] != i:
        parent[i] = parent[parent[i]]
        i = parent[i]
    return i
for a, b in edges:
    parent[root(mapping[int(a)])] = root(mapping[int(b)])
components = {}
for i in range(len(parent)):
    components.setdefault(root(i), 0)
    components[root(i)] += 1
report['topology'] = {'vertices': len(rest), 'welded_positions': len(canonical),
                      'components': sorted(components.values(), reverse=True),
                      'weight_sum_range': [min(sum(g.weight for g in v.groups) for v in mesh.data.vertices),
                                           max(sum(g.weight for g in v.groups) for v in mesh.data.vertices)]}
print('TOPOLOGY', report['topology'])
destination = folder / 'diagnosis.json'
destination.write_text(json.dumps(report, indent=2))
print('DIAGNOSIS', destination)
