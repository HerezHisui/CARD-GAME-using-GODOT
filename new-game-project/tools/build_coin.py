"""Build the approved sun/moon coin as self-contained, beveled GLB geometry.

Run with Python 3, no third-party packages. Coordinates use Z as the face normal;
the tails node rotates around X so it reads upright after the game's toss.
"""
import json
import math
from pathlib import Path
import struct


OUT = Path(__file__).resolve().parents[1] / "assets/coin/midnight_coin.glb"
doc = {"asset": {"version": "2.0", "generator": "Midnight DRRills coin builder"},
       "scene": 0, "scenes": [{"nodes": [0]}],
       "nodes": [{"name": "MidnightCoin", "children": []}],
       "meshes": [], "materials": [], "accessors": [], "bufferViews": []}
binary = bytearray()


def material(name, rgb, metallic=0.72, roughness=0.4):
    doc["materials"].append({"name": name, "pbrMetallicRoughness": {
        "baseColorFactor": [*rgb, 1], "metallicFactor": metallic,
        "roughnessFactor": roughness}})
    return len(doc["materials"]) - 1


GOLD = material("Warm antique gold", (0.72, 0.40, 0.12))
LIGHT = material("Polished raised gold", (0.95, 0.65, 0.25))
DARK = material("Recessed bronze", (0.34, 0.16, 0.045), 0.6, 0.55)
EDGE = material("Aged edge", (0.49, 0.25, 0.065), 0.65, 0.5)


def accessor(values, count, kind):
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    binary.extend(struct.pack("<" + "f" * len(values), *values))
    view = len(doc["bufferViews"])
    doc["bufferViews"].append({"buffer": 0, "byteOffset": offset,
                               "byteLength": len(binary) - offset})
    acc = {"bufferView": view, "componentType": 5126, "count": count, "type": kind}
    if kind == "VEC3":
        acc["min"] = [min(values[i::3]) for i in range(3)]
        acc["max"] = [max(values[i::3]) for i in range(3)]
    doc["accessors"].append(acc)
    return len(doc["accessors"]) - 1


def mesh(name, triangles, mat, tails=False):
    positions, normals = [], []
    for a, b, c in triangles:
        u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
        n = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
        length = math.sqrt(sum(x*x for x in n))
        if length < 1e-10:
            continue
        for p in (a, b, c):
            positions.extend(p)
            normals.extend(x / length for x in n)
    primitive = {"attributes": {"POSITION": accessor(positions, len(positions)//3, "VEC3"),
                                "NORMAL": accessor(normals, len(normals)//3, "VEC3")},
                 "material": mat, "mode": 4}
    doc["meshes"].append({"name": name, "primitives": [primitive]})
    node = {"name": name, "mesh": len(doc["meshes"]) - 1}
    if tails:
        node["rotation"] = [1, 0, 0, 0]
    doc["nodes"][0]["children"].append(len(doc["nodes"]))
    doc["nodes"].append(node)


def circle(radius, count=96, center=(0, 0), phase=0):
    return [(center[0]+radius*math.cos(phase+i*math.tau/count),
             center[1]+radius*math.sin(phase+i*math.tau/count)) for i in range(count)]


def ring(name, radii_z, mat, count=8, tails=False, center=(0, 0), solid_edge=False):
    phase = math.pi/8 if count == 8 else 0
    loops = [[(x, y, z) for x, y in circle(r, count, center, phase)] for r, z in radii_z]
    triangles = []
    for level, (inner, outer) in enumerate(zip(loops, loops[1:])):
        for i in range(count):
            j = (i+1) % count
            faces = [(inner[i], outer[i], outer[j]), (inner[i], outer[j], inner[j])]
            if solid_edge or radii_z[level+1][0] < radii_z[level][0]:
                faces = [(a, c, b) for a, b, c in faces]
            triangles.extend(faces)
    mesh(name, triangles, mat, tails)


def triangulate(poly):
    """Ear clipping handles the crescent's concave inner arc."""
    points = list(range(len(poly)))
    result = []
    def cross(a, b, c):
        return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    while len(points) > 3:
        for k, b in enumerate(points):
            a, c = points[k-1], points[(k+1) % len(points)]
            if cross(poly[a], poly[b], poly[c]) <= 1e-10:
                continue
            if any(all(cross(poly[u], poly[v], poly[p]) >= -1e-10
                       for u, v in [(a, b), (b, c), (c, a)])
                   for p in points if p not in (a, b, c)):
                continue
            result.append((a, b, c))
            points.pop(k)
            break
        else:
            raise ValueError("Cannot triangulate polygon")
    result.append(tuple(points))
    return result


def relief(name, polygon, z, height, mat=LIGHT, tails=False, bevel=0.94):
    cx = sum(p[0] for p in polygon)/len(polygon)
    cy = sum(p[1] for p in polygon)/len(polygon)
    top = [(cx+(x-cx)*bevel, cy+(y-cy)*bevel, z+height) for x, y in polygon]
    base = [(x, y, z) for x, y in polygon]
    triangles = [(top[a], top[b], top[c]) for a, b, c in triangulate(polygon)]
    for i in range(len(base)):
        j = (i+1) % len(base)
        triangles.extend([(base[i], base[j], top[j]), (base[i], top[j], top[i])])
    mesh(name, triangles, mat, tails)


def build():
    # One centered octagonal solid, followed by symmetrical stepped face borders.
    radius = 1/math.cos(math.pi/8)
    ring("Octagonal solid edge", [(radius*.97, -.10), (radius, -.075),
         (radius, .075), (radius*.97, .10)], EDGE, solid_edge=True)
    for tails in (False, True):
        side = "Tails" if tails else "Heads"
        relief(side+" recessed field", circle(radius*.96, 8, phase=math.pi/8),
               .075, .025, DARK, tails, 1)
        ring(side+" outer bright bevel", [(radius*.96, .10), (radius*.975, .125),
             (radius*.955, .145), (radius*.935, .13)], LIGHT, tails=tails)
        ring(side+" outer gold shoulder", [(radius*.935, .13), (radius*.905, .105),
             (radius*.88, .105)], GOLD, tails=tails)
        ring(side+" inset engraved border", [(radius*.88, .105), (radius*.87, .10),
             (radius*.858, .135)], DARK, tails=tails)
        ring(side+" broad raised border", [(radius*.858, .135), (radius*.81, .145),
             (radius*.735, .145), (radius*.675, .105)], GOLD, tails=tails)
        ring(side+" inner gold bevel", [(radius*.735, .145), (radius*.71, .135),
             (radius*.675, .105)], LIGHT, tails=tails)
        # Paired engraved bars at the cardinal points of the outer rim.
        for quadrant in range(4):
            angle = quadrant*math.pi/2
            for offset in (-.025, .025):
                polygon = [(offset-.007, .90), (offset+.007, .90),
                           (offset+.007, .985), (offset-.007, .985)]
                rotated = [(x*math.cos(angle)-y*math.sin(angle),
                            x*math.sin(angle)+y*math.cos(angle)) for x, y in polygon]
                relief(side+" rim engraving", rotated, .135, .003, DARK, tails, 1)
    relief("Heads sun disc", circle(.305), .12, .06)
    ring("Heads sun outline", [(.307, .12), (.321, .152), (.345, .152), (.36, .12)], LIGHT, 96)
    for i in range(16):
        a = i*math.tau/16
        length = .64 if i % 2 == 0 else .55
        points = [(.37, -.042), (length, 0), (.37, .042)]
        polygon = [(x*math.cos(a)-y*math.sin(a), x*math.sin(a)+y*math.cos(a)) for x, y in points]
        relief("Heads sun ray %02d" % i, polygon, .115, .052, bevel=.9)
    ring("Tails orbital ring", [(.591, .11), (.602, .125), (.616, .125), (.625, .11)], LIGHT, 128, True)
    for x, y in [(0, .61), (0, -.61), (-.61, 0), (.61, 0)]:
        relief("Tails orbit stud", circle(.069, 32, (x, y)), .11, .043, GOLD, True)
        ring("Tails stud engraved center", [(.027, .157), (.037, .157), (.046, .14)], LIGHT, 32, True, (x, y))
    # Intersections of two offset circles define a crescent with sharp horns.
    r, inner, dx, dy = .52, .50, .19, .16
    d = math.hypot(dx, dy)
    a = (r*r-inner*inner+d*d)/(2*d)
    h = math.sqrt(r*r-a*a)
    upper = (a*dx/d-h*dy/d, a*dy/d+h*dx/d)
    lower = (a*dx/d+h*dy/d, a*dy/d-h*dx/d)
    start, end = math.atan2(upper[1], upper[0]), math.atan2(lower[1], lower[0])+math.tau
    crescent = [(r*math.cos(start+(end-start)*i/64), r*math.sin(start+(end-start)*i/64))
                for i in range(65)]
    start, end = math.atan2(lower[1]-dy, lower[0]-dx), math.atan2(upper[1]-dy, upper[0]-dx)-math.tau
    crescent.extend([(dx+inner*math.cos(start+(end-start)*i/64),
                      dy+inner*math.sin(start+(end-start)*i/64)) for i in range(1, 64)])
    relief("Tails raised crescent", crescent, .117, .055, tails=True, bevel=.985)
    for index, (x, y, size) in enumerate([(-.035, .24, .115), (.255, .13, .17), (.005, -.12, .12)]):
        star = [(x+math.cos(i*math.pi/4)*(size if i%2 == 0 else size*.24),
                 y+math.sin(i*math.pi/4)*(size if i%2 == 0 else size*.24)) for i in range(8)]
        relief("Tails star %d" % index, star, .12, .055, tails=True, bevel=.86)
    doc["buffers"] = [{"byteLength": len(binary)}]
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    data = (struct.pack("<III", 0x46546C67, 2, 12+8+len(encoded)+8+len(binary))
            + struct.pack("<II", len(encoded), 0x4E4F534A)+encoded
            + struct.pack("<II", len(binary), 0x004E4942)+binary)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(data)
    print(f"Built {OUT.name}: {len(doc['meshes'])} meshes, {len(data)} bytes")


if __name__ == "__main__":
    build()
