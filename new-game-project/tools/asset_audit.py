"""Check runtime dependencies and lossless classroom integrity using Python 3.

Run: python tools/asset_audit.py
Read-only: no deletion or resource rewriting.
"""
from pathlib import Path
from urllib.parse import unquote
import hashlib
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
TEXT = {".gd", ".tscn", ".tres", ".godot", ".gdshader"}
OPTIONAL = {"assets/title_screen.png"}  # Deliberate fallback until artwork arrives.


def glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    size, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A
    return json.loads(data[20:20 + size]), data[28 + size:]


def audit():
    seen, missing = set(), []

    def walk(relative):
        if relative in seen or relative in OPTIONAL:
            return
        seen.add(relative)
        path = (ROOT / relative).resolve()
        assert path.is_relative_to(ROOT), relative
        if not path.is_file():
            missing.append(relative)
            return
        if path.suffix in TEXT:
            for dependency in re.findall(r'res://([^"\s\)]+)', path.read_text(encoding="utf-8-sig")):
                walk(dependency)
        elif path.suffix == ".glb":
            document, _ = glb(path)
            for resource in document.get("images", []) + document.get("buffers", []):
                if "uri" in resource:
                    uri = unquote(resource["uri"])
                    assert ":" not in uri and not Path(uri).is_absolute()
                    walk((path.parent / uri).relative_to(ROOT).as_posix())

    walk("project.godot")
    assert not missing, f"Missing runtime dependencies: {missing}"
    unused = [f.relative_to(ROOT).as_posix() for folder in ["assets", "scripts", "scenes", "data"]
              for f in (ROOT / folder).rglob("*")
              if f.is_file() and f.suffix not in {".import", ".uid", ".md"}
              and not f.name.endswith("manifest.json")
              and f.relative_to(ROOT).as_posix() not in seen]
    assert not unused, f"Unreferenced runtime files (review before adding): {unused}"
    room = ROOT / "assets/supplied_classroom"
    manifest = json.loads((room / "play_area_manifest.json").read_text())
    model = room / "classroom_play_area.glb"
    assert hashlib.sha256(model.read_bytes()).hexdigest() == manifest["runtime_glb_sha256"]
    document, binary = glb(model)
    geometry = b"".join(binary[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
                        for v in document["bufferViews"])
    assert hashlib.sha256(geometry).hexdigest() == manifest["geometry_buffer_sha256"]
    assert len(document["images"]) == len(manifest["runtime_texture_sha256"]) == 33
    for name, checksum in manifest["runtime_texture_sha256"].items():
        data = (room / name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == checksum, f"Texture changed: {name}"
        assert list(struct.unpack_from(">II", data, 16)) == manifest["runtime_texture_dimensions"][name]
    content = [f for f in ROOT.rglob("*") if f.is_file()
               and not set(f.relative_to(ROOT).parts) & {".godot", "artifacts", "__pycache__", "builds"}]
    print(f"PASS: {len(seen)} runtime files; no missing or unused resources; geometry and all 33 original textures verified.")
    print(f"Source project: {sum(f.stat().st_size for f in content):,} bytes (caches/builds/test captures excluded).")


if __name__ == "__main__":
    audit()
