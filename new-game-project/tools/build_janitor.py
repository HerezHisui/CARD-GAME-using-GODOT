"""Rebuild editable Janitor rig, clips, cloth proxy and game GLB with Blender 4.5.

Coordinates in this file use Godot convention: X right, Y up, Z toward the player.
The supplied mesh is preserved, including UV seams and embedded PBR textures.
"""
import bpy
import json
import math
import hashlib
import heapq
from pathlib import Path
from mathutils import Vector, Quaternion

PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "assets/characters/janitor"
SOURCE = Path("C:/Users/0stef/Downloads/meshy-model-2026-10-30T09-10-58-481Z.glb")
OUTPUT.mkdir(parents=True, exist_ok=True)
(OUTPUT / "source").mkdir(exist_ok=True)
(OUTPUT / "source/.gdignore").touch()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
mesh.name = "JanitorMesh"
original_matrix = mesh.matrix_world.copy()
mesh.parent = None
mesh.matrix_world.identity()
for vertex in mesh.data.vertices:
    vertex.co = original_matrix @ vertex.co
    vertex.co.z += 0.9998779892921448
for obj in list(bpy.context.scene.objects):
    if obj != mesh:
        bpy.data.objects.remove(obj, do_unlink=True)

def point(value):
    return Vector((value[0], -value[2], value[1]))

def godot(value):
    return [value.x, value.z, -value.y]

armature = bpy.data.armatures.new("JanitorSkeleton")
rig = bpy.data.objects.new("JanitorRig", armature)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
mesh.select_set(False)
bpy.ops.object.mode_set(mode='EDIT')
bones = {}
segments = {}

def bone(name, head, tail, parent=None, deform=True):
    result = armature.edit_bones.new(name)
    result.head, result.tail = point(head), point(tail)
    result.use_deform = deform
    if parent:
        result.parent = bones[parent]
    bones[name] = result
    segments[name] = (point(head), point(tail))
    return result

bone('Root', (0, 0, 0), (0, .2, 0), deform=False)
bone('Hips', (0, .82, -.06), (0, 1.15, -.06), 'Root')
bone('Spine', (0, 1.15, -.06), (0, 1.48, -.07), 'Hips')
bone('Chest', (0, 1.48, -.07), (0, 1.64, -.07), 'Spine')
bone('Head', (0, 1.64, -.07), (0, 1.94, -.07), 'Chest')
hand_vertices = {}
for side, sign in [('L', -1), ('R', 1)]:
    shoulder = (sign * .21, 1.56, -.035)
    elbow = (sign * .32, 1.28 if sign < 0 else 1.18, .015)
    wrist = (sign * .245, 1.335 if sign < 0 else 1.16, .32 if sign < 0 else .13)
    palm = (sign * .205, 1.30 if sign < 0 else 1.10, .43 if sign < 0 else .23)
    bone('Shoulder_' + side, (sign * .05, 1.55, -.07), shoulder, 'Chest')
    bone('Arm_' + side, shoulder, elbow, 'Shoulder_' + side)
    bone('Forearm_' + side, elbow, wrist, 'Arm_' + side)
    bone('Hand_' + side, wrist, palm, 'Forearm_' + side)
    # The scan already has flexed fingers. Small additive curls keep that rest shape.
    for i, finger in enumerate(['Thumb', 'Index', 'Middle', 'Ring', 'Little']):
        spread = (i - 2) * .026
        base = (palm[0] + spread, palm[1] + (.018 if i == 0 else 0), palm[2] - .012)
        tip = (base[0] + sign * .01, base[1] - (.045 if sign > 0 else .035), base[2] + .047)
        end = (tip[0] + sign * .003, tip[1] - .025, tip[2] + .018)
        bone(f'{finger}1_{side}', base, tip, 'Hand_' + side)
        bone(f'{finger}2_{side}', tip, end, f'{finger}1_{side}')
    bone('Grip_' + side, palm, (palm[0], palm[1] + .08, palm[2]), 'Hand_' + side, False)

# A closed 8-column, 5-row cloth cage follows the existing robe silhouette.
# The upper row is pinned. Lower rows become independent, physics-driven skin bones.
cloth_points = []
for row in range(5):
    y = .90 - row * .215
    rx = .275 + row * .029
    rz = .22 + row * .034
    for column in range(8):
        angle = column * math.tau / 8
        p = (math.cos(angle) * rx, y, -.06 + math.sin(angle) * rz)
        index = len(cloth_points)
        cloth_points.append(p)
        bone(f'Cloth_{index:02}', p, (p[0], p[1] + .06, p[2]), 'Root')
bpy.ops.object.mode_set(mode='OBJECT')
groups = {name: mesh.vertex_groups.new(name=name) for name in segments
          if armature.bones[name].use_deform}

def distance_squared(p, segment):
    a, b = segment
    direction = b - a
    t = max(0, min(1, (p - a).dot(direction) / direction.length_squared))
    return (p - a - direction * t).length_squared

def smoothstep(low, high, x):
    t = max(0, min(1, (x - low) / (high - low)))
    return t * t * (3 - 2 * t)

mixed = 0
finger_counts = {}
# Find exposed hands from the supplied albedo, then feather at the cuff along the actual
# surface. A coordinate box had cut through the lowest fingertips of the asymmetric scan.
image = bpy.data.images['texture_0']
pixels = image.pixels[:]
skin = set()
for loop in mesh.data.loops:
    uv = mesh.data.uv_layers.active.data[loop.index].uv
    u = (uv.x * 15.9871788 + .000011) % 1
    v = (uv.y * 16.0035667 - 15.00357151) % 1
    offset = (int(v * (image.size[1] - 1)) * image.size[0] + int(u * (image.size[0] - 1))) * 4
    color = pixels[offset:offset + 3]
    x, y, z = godot(mesh.data.vertices[loop.vertex_index].co)
    if .65 < y < 1.55 and z > .04 and abs(x) > .04 and min(color) > .18 and max(color) > .4:
        skin.add(loop.vertex_index)
canonical = {}
mapping = []
for vertex in mesh.data.vertices:
    key = tuple(round(c, 6) for c in vertex.co)
    canonical.setdefault(key, vertex.index)
    mapping.append(canonical[key])
adjacent = {i: {} for i in set(mapping)}
for edge in mesh.data.edges:
    a, b = (mapping[i] for i in edge.vertices)
    length = (mesh.data.vertices[a].co - mesh.data.vertices[b].co).length
    if a != b:
        adjacent[a][b] = length
        adjacent[b][a] = length
colored = {mapping[i] for i in skin}
components = []
while colored:
    component = {colored.pop()}
    stack = list(component)
    while stack:
        current = stack.pop()
        for neighbor in adjacent[current]:
            if neighbor in colored:
                colored.remove(neighbor)
                component.add(neighbor)
                stack.append(neighbor)
    components.append(component)
hand_distance = {}
for side, sign in [('L', -1), ('R', 1)]:
    candidates = [c for c in components if sum(mesh.data.vertices[i].co.x * sign for i in c) > 0]
    core = max(candidates, key=len)
    distances = {i: 0.0 for i in core}
    pending = [(0.0, i) for i in core]
    heapq.heapify(pending)
    while pending:
        distance, index = heapq.heappop(pending)
        if distance > distances[index]:
            continue
        for neighbor, length in adjacent[index].items():
            candidate = distance + length
            if candidate < .60 and candidate < distances.get(neighbor, math.inf):
                distances[neighbor] = candidate
                heapq.heappush(pending, (candidate, neighbor))
    hand_distance[side] = distances
    print('HAND REGION', side, 'core positions', len(core), 'feather positions', len(distances))
for vertex in mesh.data.vertices:
    p = vertex.co
    x, y, z = godot(p)
    side = 'L' if x < 0 else 'R'
    # Separate sleeve fields from torso; the original robe has no underlying body mesh.
    sleeve = smoothstep(.13, .32, abs(x)) * smoothstep(.60, 1.10, y)
    sleeve *= 1 - smoothstep(1.48, 1.70, y)
    sleeve *= smoothstep(-.20, .05, z)
    distance_to_hand = hand_distance[side].get(mapping[vertex.index], math.inf)
    # The cuff transitions into the moving forearm/sleeve, not the stationary hips.
    # Surface distance includes the inward-facing sleeve folds that an X cutoff missed.
    sleeve = max(sleeve, 1 - smoothstep(.20, .55, distance_to_hand))
    hand = 1 - smoothstep(.025, .18, distance_to_hand)
    weights = {}
    # Compact, continuous support avoids truncating a moving arm out of an eight-weight vertex.
    if y <= 1.05:
        weights['Hips'] = 1 - sleeve
    else:
        names = ['Hips', 'Spine', 'Chest', 'Head']
        levels = [1.05, 1.40, 1.60, 1.78]
        band = next((i for i in range(3) if y <= levels[i + 1]), 2)
        t = smoothstep(levels[band], levels[band + 1], y)
        weights[names[band]] = (1 - sleeve) * (1 - t)
        weights[names[band + 1]] = (1 - sleeve) * t
    arm_names = ['Arm_' + side, 'Forearm_' + side, 'Hand_' + side]
    values = [1 / max(.003, distance_squared(p, segments[name])) ** 2 for name in arm_names]
    for name, value in zip(arm_names, values):
        weights[name] = sleeve * value / sum(values)
    # Blend the robe into the waist continuously, including the lower hanging sleeves.
    blend = (1 - smoothstep(.72, 1.06, y)) * (1 - sleeve)
    for name in weights:
        weights[name] *= 1 - blend
    # Bilinear cage weights are continuous across angular and row boundaries.
    u = (math.atan2(z + .06, x) % math.tau) * 8 / math.tau
    v = max(0, min(4, (.90 - y) / .215))
    column, row = int(u), min(3, int(v))
    column_mix, row_mix = u - column, v - row
    for r, row_weight in [(row, 1 - row_mix), (row + 1, row_mix)]:
        for c, column_weight in [(column, 1 - column_mix), ((column + 1) % 8, column_mix)]:
            weights[f'Cloth_{r * 8 + c:02}'] = blend * row_weight * column_weight
    if hand > 0:
        for name in weights:
            weights[name] *= 1 - hand
        finger_names = [name for name in segments if name.endswith('_' + side)
                        and any(name.startswith(f) for f in ['Thumb', 'Index', 'Middle', 'Ring', 'Little'])]
        closest = min(finger_names, key=lambda name: distance_squared(p, segments[name]))
        finger_mix = 0.0
        if hand == 1:
            finger_mix = smoothstep(.27 if side == 'R' else .42, .30 if side == 'R' else .47, z) * .85
        weights[closest] = hand * finger_mix
        weights['Hand_' + side] = weights.get('Hand_' + side, 0) + hand * (1 - finger_mix)
        finger_counts[closest] = finger_counts.get(closest, 0) + 1
    weights = sorted(((k, v) for k, v in weights.items() if v > .0000001), key=lambda item: -item[1])
    assert len(weights) <= 8, (vertex.index, weights)
    total = sum(v for _, v in weights)
    assert total > 0
    if len(weights) > 1:
        mixed += 1
    for name, weight in weights:
        groups[name].add([vertex.index], weight / total, 'REPLACE')

# The support above fits the export format directly. Never truncate and renormalize a
# geodesically smoothed field: doing so made adjacent vertices lose different moving bones.
modifier = mesh.modifiers.new('Janitor skin', 'ARMATURE')
modifier.object = rig
mesh.parent = rig
rig.show_in_front = True

# Each clip is editable as a Blender action and exported as an independent glTF animation.
def action(name, duration, poses, loop=False):
    bpy.context.scene.render.fps = 30
    clip = bpy.data.actions.new(name)
    clip.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = clip
    for b in rig.pose.bones:
        b.rotation_mode = 'QUATERNION'
        b.rotation_quaternion = Quaternion()
    for t, changes in poses:
        for b in rig.pose.bones:
            if b.name.startswith('Cloth_') or b.name == 'Root':
                continue
            euler = changes.get(b.name, (0, 0, 0))
            # Object-space axes converted into each bone's rest basis.
            rotation = Quaternion(point((1, 0, 0)), euler[0])
            rotation @= Quaternion(point((0, 1, 0)), euler[1])
            rotation @= Quaternion(point((0, 0, 1)), euler[2])
            rest = armature.bones[b.name].matrix_local.to_quaternion()
            b.rotation_quaternion = rest.inverted() @ rotation @ rest
            b.keyframe_insert('rotation_quaternion', frame=1 + t * 30, group=b.name)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, clip)
    rig.animation_data.action = None
    return clip

# Right palm supports a levitating fan. Left hand directs it toward the board.
hold = {'Arm_L': (0, 0, 0), 'Arm_R': (-.40, 0, -.04), 'Forearm_R': (-.55, -.05, .07),
        'Hand_R': (-.55, .03, .05), 'Hand_L': (.03, 0, 0)}
def pose(**changes):
    result = dict(hold)
    for name, angles in changes.items():
        base = hold.get(name, (0, 0, 0))
        result[name] = tuple(a + b for a, b in zip(base, angles))
    return result
action('idle', 2.4, [(0, hold), (.6, pose(Chest=(.009, .006, 0), Head=(0, -.012, .005))),
                     (1.2, pose(Chest=(-.006, 0, 0))), (1.8, pose(Head=(.007, .012, 0))), (2.4, hold)], True)
action('card_play', 1.2, [(0, hold), (.26, pose(Forearm_L=(-.08, -.10, -.06), Hand_L=(-.10, .05, .02))),
                         (.52, pose(Arm_L=(.10, -.06, .04), Forearm_L=(-.22, .08, .04), Hand_L=(-.12, 0, 0), Chest=(.035, 0, 0))),
                         (.72, pose(Arm_L=(.16, .04, .03), Forearm_L=(-.25, .10, .04), Hand_L=(-.08, 0, -.04), Chest=(.045, 0, 0))),
                         (1.2, hold)])
action('warden_pattern', .9, [(0, hold), (.35, pose(Chest=(-.018, 0, 0), Arm_L=(.08, -.06, -.12),
                        Arm_R=(.28, .06, .12), Head=(.025, 0, 0))), (.9, hold)])
for track in rig.animation_data.nla_tracks:
    track.mute = True
rig.animation_data.action = bpy.data.actions['idle']
bpy.context.scene.frame_set(1)

# Editable proxy reference, with explicit pins. Runtime Godot uses the same nodes and constraints.
proxy_mesh = bpy.data.meshes.new('ClothProxyTopology')
faces = []
constraints = []
for row in range(5):
    for col in range(8):
        a = row * 8 + col
        b = row * 8 + (col + 1) % 8
        constraints.append([a, b])
        if row < 4:
            c, d = a + 8, b + 8
            faces.append((a, b, d, c))
            constraints.extend([[a, c], [a, d], [b, c]])
        if row < 3:
            constraints.append([a, a + 16])
proxy_mesh.from_pydata([point(p) for p in cloth_points], [], faces)
proxy = bpy.data.objects.new('ClothProxy_Reference', proxy_mesh)
bpy.context.collection.objects.link(proxy)
pins = proxy.vertex_groups.new(name='PinnedWaist')
pins.add(list(range(8)), 1, 'REPLACE')
proxy.hide_render = True
proxy.hide_set(True)
proxy['method'] = 'Godot fixed-step Verlet, structural/shear/bend constraints; pinned upper ring; body collisions'
proxy['runtime_data'] = 'cloth_proxy.json'

# Export only the mesh and rig; proxy is reference geometry, never rendered as a second robe.
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
rig.animation_data.action = None
for track in rig.animation_data.nla_tracks:
    track.mute = False
bpy.ops.export_scene.gltf(filepath=str(OUTPUT / 'janitor_rigged.glb'), export_format='GLB',
    use_selection=True, export_animations=True, export_animation_mode='NLA_TRACKS',
    export_frame_range=False, export_force_sampling=True, export_yup=True,
    export_skins=True, export_all_influences=True)
for track in rig.animation_data.nla_tracks:
    track.mute = True
rig.animation_data.action = bpy.data.actions['idle']
bpy.context.scene.frame_set(1)
for image in bpy.data.images:
    image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / 'source/janitor.blend'))
cloth = {'points': cloth_points, 'pins': list(range(8)), 'constraints': constraints,
         'bones': [f'Cloth_{i:02}' for i in range(40)],
         'collision': {'center': [0, .44, -.06], 'radii': [.15, .47, .115]}}
(OUTPUT / 'cloth_proxy.json').write_text(json.dumps(cloth, indent=2))
audit = {'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
         'vertices': len(mesh.data.vertices), 'triangles': len(mesh.data.polygons),
         'bones': len(armature.bones), 'mixed_weight_vertices': mixed,
         'finger_regions': finger_counts, 'geometry_repairs': 'None; original topology and UVs retained.',
         'animations': ['idle', 'card_play', 'warden_pattern']}
(OUTPUT / 'rig_audit.json').write_text(json.dumps(audit, indent=2))
print('JANITOR BUILD', json.dumps(audit))
