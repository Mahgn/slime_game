"""Bake the supplied rectangular Cyclops blocks without loading editor plugins.

Reads the actual scene (including manual edits), refuses non-box geometry, and
preserves block names, transforms, dimensions and materials. Does not overwrite
an existing output. Usage: python tools/convert_lab_blockout.py SOURCE OUTPUT
"""
import itertools
from pathlib import Path
import re
import sys


def convert(source: Path, target: Path) -> int:
    text = source.read_text(encoding="utf-8-sig")
    sections = re.findall(r"(\[[^\n]+\])\n(.*?)(?=\n\[|\Z)", text, re.S)
    resources = {}
    nodes = []
    for header, body in sections:
        if header.startswith("[sub_resource"):
            resources[re.search(r'id="([^"]+)"', header)[1]] = (header, body)
        elif header.startswith("[node") and 'parent="."' in header:
            nodes.append((header, body))
    materials = {key: value for key, value in resources.items() if 'type="StandardMaterial3D"' in value[0]}
    baked = []
    for header, body in nodes:
        name = re.search(r'name="([^"]+)"', header)[1]
        mesh_id = re.search(r'mesh_vector_data = SubResource\("([^"]+)"\)', body)[1]
        mesh = resources[mesh_id][1]
        assert "num_vertices = 8\n" in mesh and "num_faces = 6\n" in mesh, name
        positions_id = re.search(r'vertex_data = \{.*?"position": SubResource\("([^"]+)"\)', mesh, re.S)[1]
        floats = re.search(r'data = PackedFloat32Array\(([^)]+)\)', resources[positions_id][1])[1]
        values = [float(value) for value in floats.split(",")]
        vertices = set(zip(values[::3], values[1::3], values[2::3]))
        axes = [sorted(set(v[axis] for v in vertices)) for axis in range(3)]
        assert all(len(axis) == 2 for axis in axes), f"Non-box block: {name}"
        assert vertices == set(itertools.product(*axes)), f"Non-box block: {name}"
        centre = [(axis[0] + axis[1]) / 2 for axis in axes]
        size = [axis[1] - axis[0] for axis in axes]
        assert all(abs(value) < 0.00001 for value in centre), f"Off-centre block: {name}"
        transform = re.search(r'^transform = (.+)$', body, re.M)[1]
        material = re.search(r'materials = Array\[Material\]\(\[SubResource\("([^"]+)"\)\]\)', body)[1]
        baked.append((name, transform, size, material))
    assert baked, "No Cyclops blocks found"
    assert not target.exists(), f"Refusing to overwrite {target}"
    parts = [f'[gd_scene load_steps={1 + len(materials) + 2 * len(baked)} format=3]\n']
    parts += [header + "\n" + body for header, body in materials.values()]
    for index, (_, _, size, material) in enumerate(baked):
        vector = "Vector3(" + ", ".join(format(value, ".9g") for value in size) + ")"
        parts.append(f'[sub_resource type="BoxMesh" id="Mesh_{index}"]\nmaterial = SubResource("{material}")\nsize = {vector}\n')
        parts.append(f'[sub_resource type="BoxShape3D" id="Shape_{index}"]\nsize = {vector}\n')
    parts.append('[node name="OpeningBlockout" type="Node3D"]\n')
    for index, (name, transform, _, _) in enumerate(baked):
        parts.append(f'[node name="{name}" type="StaticBody3D" parent="."]\ntransform = {transform}\ncollision_layer = 1\ncollision_mask = 0\n')
        parts.append(f'[node name="Stone" type="MeshInstance3D" parent="{name}"]\nmesh = SubResource("Mesh_{index}")\n')
        parts.append(f'[node name="CollisionShape3D" type="CollisionShape3D" parent="{name}"]\nshape = SubResource("Shape_{index}")\n')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(parts), encoding="utf-8")
    print(f"BAKED {len(baked)} blocks: names, transforms, bounds and materials preserved")
    return len(baked)


if __name__ == "__main__":
    convert(Path(sys.argv[1]), Path(sys.argv[2]))
