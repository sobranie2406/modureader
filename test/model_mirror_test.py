"""Mirror assembly preserves pinned originals, attribution and checksums."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/release"))
import model_mirror


class ModelMirrorTest(unittest.TestCase):
    def test_split_and_unsplit_files_reassemble_exactly(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source"
            output = Path(tmp) / "output"
            model_dir = source / "fixture"
            model_dir.mkdir(parents=True)
            originals = {"model_quantized.onnx": bytes(range(19)), "tokenizer.json": b"{}"}
            catalog = {"models": [{"id": "fixture", "revision": "a" * 40,
                "license": "MIT", "repository": "Xenova/fixture", "files": [
                    {"name": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                    for name, data in originals.items()]}]}
            for name, data in originals.items():
                (model_dir / name).write_bytes(data)
            with patch.object(model_mirror, "manifest", return_value=copy.deepcopy(catalog)), \
                    patch.object(model_mirror, "PART_SIZE", 8):
                model_mirror.prepare(source, output)
            result = json.loads((output / "manifest.json").read_text())
            for item in result["models"][0]["files"]:
                assembled = b""
                for part in item["mirror_parts"]:
                    payload = (output / part["name"]).read_bytes()
                    self.assertEqual(len(payload), part["size"])
                    self.assertEqual(hashlib.sha256(payload).hexdigest(), part["sha256"])
                    self.assertIn("a" * 40, part["name"])
                    self.assertLessEqual(len(payload), 8)
                    assembled += payload
                self.assertEqual(assembled, originals[item["name"]])
                self.assertEqual(hashlib.sha256(assembled).hexdigest(), item["sha256"])
            self.assertEqual(len((output / "SHA256SUMS").read_text().splitlines()), 4)
            for name in ["MiniLM-Embedding-Apache-2.0.txt", "BGE-Embedding-MIT.txt", "E5-Embedding-MIT.txt"]:
                self.assertEqual((output / name).read_bytes(),
                                 (model_mirror.ROOT / "LICENSES" / name).read_bytes())

    def test_missing_sources_are_not_mirrored(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, "Missing or corrupt"):
                model_mirror.prepare(Path(tmp) / "empty", Path(tmp) / "output")


if __name__ == "__main__":
    unittest.main()
