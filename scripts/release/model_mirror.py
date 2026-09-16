"""Prepare byte-identical Hugging Face model assets for a Gitee Release.

Only public, pinned model files and their licenses are copied. No upload/auth.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from bundle_models import ROOT, ASSETS, manifest, valid, fetch

PART_SIZE = 64 * 1024 * 1024
BASE = "https://gitee.com/sobranie2406/modu-models/releases/download/models-v1"


def prepare(source, output):
    output.mkdir(parents=True, exist_ok=True)
    checksums = []
    catalog = manifest()
    for model in catalog["models"]:
        for item in model["files"]:
            original = source / model["id"] / item["name"]
            if not valid(original, item):
                raise ValueError(f"Missing or corrupt source: {model['id']}/{item['name']}")
            count = (item["size"] + PART_SIZE - 1) // PART_SIZE
            parts = []
            digest = hashlib.sha256()
            with original.open("rb") as reader:
                for index in range(count):
                    name = f"{model['id']}-{model['revision']}-{item['name']}"
                    if count > 1:
                        name += f".part-{index + 1:02d}"
                    data = reader.read(PART_SIZE)
                    digest.update(data)
                    destination = output / name
                    destination.write_bytes(data)
                    checksum = hashlib.sha256(data).hexdigest()
                    checksums.append(f"{checksum}  {name}")
                    parts.append(dict(name=name, size=len(data), sha256=checksum,
                                      url=f"{BASE}/{name}"))
            if digest.hexdigest() != item["sha256"]:
                raise ValueError("Source changed during preparation")
            item["mirror_parts"] = parts
    for license_name in ["MiniLM-Embedding-Apache-2.0.txt", "BGE-Embedding-MIT.txt",
                         "E5-Embedding-MIT.txt"]:
        shutil.copyfile(ROOT / "LICENSES" / license_name, output / license_name)
    (output / "manifest.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    (output / "SHA256SUMS").write_text("\n".join(checksums) + "\n", encoding="utf-8")
    print(f"Prepared {len(checksums)} model/tokenizer attachments and original licenses in {output}")
    print("Not uploaded. Verify public Gitee downloads before announcing mirror availability.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ASSETS)
    parser.add_argument("--output", type=Path, default=ROOT / "build/model-mirror")
    parser.add_argument("--fetch", action="store_true", help="Fetch missing pinned public files from Hugging Face")
    args = parser.parse_args()
    if args.fetch:
        for model in manifest()["models"]:
            for item in model["files"]:
                fetch((model, item), args.source)
    prepare(args.source, args.output)
