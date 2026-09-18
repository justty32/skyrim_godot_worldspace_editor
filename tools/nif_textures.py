#!/usr/bin/env python3
"""Read a NIF through the sibling parser and write its flat-glTF texture sidecar."""
import argparse
import json
from pathlib import Path
import sys

# Importing the sibling is read-only, including its Python bytecode cache.
sys.dont_write_bytecode = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("nif", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--mc-dir", type=Path,
                        default=Path(__file__).resolve().parents[2] / "model-converter")
    args = parser.parse_args()
    sys.path.insert(0, str(args.mc_dir))
    from nif2gltf.nif_reader import read_nif

    # write_gltf omits empty geometry, so sidecar indices must do the same.
    meshes = [mesh for mesh in read_nif(args.nif.read_bytes()) if not mesh.is_empty()]
    result = {"contract": "gltf-textures/1", "source": args.nif.name,
              "meshes": [{"index": i, "name": mesh.name, "diffuse": mesh.texture or ""}
                         for i, mesh in enumerate(meshes)]}
    output = args.out or args.nif.with_suffix(".textures.json")
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
