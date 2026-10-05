"""Build a tiny self-contained glTF sample for the first-floor import check."""

import base64
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "first_floor" / "sample_crate.gltf"

faces = [
    ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
    ((0, 0, -1), (-1, 0, 0), (0, 1, 0)),
    ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
    ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
    ((0, 1, 0), (1, 0, 0), (0, 0, -1)),
    ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
]

positions = []
normals = []
indices = []
for normal, axis_u, axis_v in faces:
    start = len(positions) // 3
    for sign_u, sign_v in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
        positions.extend(
            (normal[i] + sign_u * axis_u[i] + sign_v * axis_v[i]) * 0.5
            for i in range(3)
        )
        normals.extend(normal)
    indices.extend([start, start + 1, start + 2, start, start + 2, start + 3])

position_bytes = struct.pack(f"<{len(positions)}f", *positions)
normal_bytes = struct.pack(f"<{len(normals)}f", *normals)
index_bytes = struct.pack(f"<{len(indices)}H", *indices)
buffer = position_bytes + normal_bytes + index_bytes
document = {
    "asset": {"version": "2.0", "generator": "slime_lab sample"},
    "scene": 0,
    "scenes": [{"nodes": [0]}],
    "nodes": [{"name": "SampleCrate", "mesh": 0}],
    "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2, "material": 0}]}],
    "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [0.28, 0.67, 0.72, 1], "metallicFactor": 0.1, "roughnessFactor": 0.48}}],
    "buffers": [{"uri": "data:application/octet-stream;base64," + base64.b64encode(buffer).decode(), "byteLength": len(buffer)}],
    "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": len(position_bytes), "target": 34962},
        {"buffer": 0, "byteOffset": len(position_bytes), "byteLength": len(normal_bytes), "target": 34962},
        {"buffer": 0, "byteOffset": len(position_bytes) + len(normal_bytes), "byteLength": len(index_bytes), "target": 34963},
    ],
    "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": len(positions) // 3, "type": "VEC3", "min": [-0.5, -0.5, -0.5], "max": [0.5, 0.5, 0.5]},
        {"bufferView": 1, "componentType": 5126, "count": len(normals) // 3, "type": "VEC3"},
        {"bufferView": 2, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
    ],
}
OUTPUT.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(OUTPUT)
