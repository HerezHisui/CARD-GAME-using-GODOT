"""Evaluate real skin deformation in the editable Blender source, not only bone motion."""
import bpy
import json
import numpy as np
from pathlib import Path

folder = Path(__file__).resolve().parents[1] / 'assets/characters/janitor'
bpy.ops.wm.open_mainfile(filepath=str(folder / 'source/janitor.blend'))
mesh = bpy.data.objects['JanitorMesh']
rig = bpy.data.objects['JanitorRig']
rest = np.array([v.co[:] for v in mesh.data.vertices])
edges = np.array([e.vertices[:] for e in mesh.data.edges])
lengths = np.linalg.norm(rest[edges[:, 1]] - rest[edges[:, 0]], axis=1)
valid = lengths > .001
results = []
for name, frames in [('idle', range(1, 74)), ('card_play', range(1, 38)),
                     ('warden_pattern', range(1, 29))]:
    rig.animation_data.action = bpy.data.actions[name]
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        deformed = np.array([v.co[:] for v in evaluated.data.vertices])
        ratios = np.linalg.norm(deformed[edges[:, 1]] - deformed[edges[:, 0]], axis=1) / np.maximum(.000001, lengths)
        sample = {'clip': name, 'frame': frame, 'finite': bool(np.isfinite(deformed).all()),
                  'max_displacement': float(np.linalg.norm(deformed - rest, axis=1).max()),
                  'stretch_p99': float(np.percentile(ratios[valid], 99)),
                  'stretch_max': float(ratios[valid].max())}
        worst = np.argsort(np.where(valid, ratios, 0))[-4:]
        sample['worst_edges'] = [{'ratio': float(ratios[i]), 'rest_a': rest[edges[i, 0]].tolist(),
                                  'rest_b': rest[edges[i, 1]].tolist()} for i in worst]
        results.append(sample)
        if frame in [1, 9, 17, 23, 37, 73]:
            print('DEFORMATION', {k: v for k, v in sample.items() if k != 'worst_edges'})
(folder / 'deformation_validation.json').write_text(json.dumps(results, indent=2))
assert all(r['finite'] for r in results), 'Nonfinite skin deformation'
assert all(r['stretch_p99'] < 2.5 for r in results), 'Excessive broad skin stretching'
assert all(r['stretch_max'] < 4.0 for r in results), 'Localized skin spike'
assert max(r['max_displacement'] for r in results) > .1, 'Mesh did not deform'
print('DEFORMATION CHECK PASSED')
