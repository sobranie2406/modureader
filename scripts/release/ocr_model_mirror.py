"""Prepare pinned, byte-identical OCR models and notices for Gitee (no upload)."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
REVISION = '1cfba2e90fc938db55889873735088de210cc173'
MODELS = {
 'ppocr-v5-mobile-1': {
    'det.onnx': ('onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx', 4819576,
                 '4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae'),
    'rec.onnx': ('onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx', 16631306,
                 '5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5'),
 },
 'ppocr-v4-mobile-1': {
    'det.onnx': ('PP-OCRv4/ch_PP-OCRv4_det_infer.onnx', 4745517,
                 'd2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9'),
    'rec.onnx': ('PP-OCRv4/ch_PP-OCRv4_rec_infer.onnx', 10857958,
                 '48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b'),
 },
 'ppocr-v3-mobile-1': {
    'det.onnx': ('PP-OCRv3/ch_PP-OCRv3_det_infer.onnx', 2432880,
                 '3439588c030faea393a54515f51e983d8e155b19a2e8aba7891934c1cf0de526'),
    'rec.onnx': ('PP-OCRv3/ch_PP-OCRv3_rec_infer.onnx', 10690752,
                 '897a3ededb38fee0dae2c1ccee38241f37df202c9509e3abca02e9217c5ee615'),
 },
 'ppocr-v3-english-mobile-1': {
    'det.onnx': ('PP-OCRv4/en_PP-OCRv3_det_infer.onnx', 2423224,
                 'f139598bc2af4e4b6fe98dec11574e30edfdd91fc94ac1425c18ace3bd5a866b'),
    'rec.onnx': ('PP-OCRv3/en_PP-OCRv3_rec_infer.onnx', 8967018,
                 'ef7abd8bd3629ae57ea2c28b425c1bd258a871b93fd2fe7c433946ade9b5d9ea'),
 },
}


def prepare(source, output):
    output.mkdir(parents=True, exist_ok=True)
    manifest = dict(revision=REVISION, license='Apache-2.0', models=[])
    sums = []
    for model_id, files in MODELS.items():
        revision = 'v3.9.2' if model_id == 'ppocr-v5-mobile-1' else REVISION
        base = ('https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve' if model_id == 'ppocr-v5-mobile-1'
                else 'https://huggingface.co/SWHL/RapidOCR/resolve')
        model = dict(id=model_id, revision=revision, files=[])
        manifest['models'].append(model)
        for local, (upstream, size, digest) in files.items():
            path = source / Path(upstream).name
            with path.open('rb') as file:
                if path.stat().st_size != size or hashlib.file_digest(file, 'sha256').hexdigest() != digest:
                    raise ValueError(f'Invalid OCR file: {local}')
            name = f'{model_id}-{revision}-{Path(upstream).name}'
            shutil.copy2(path, output / name)
            sums.append(f'{digest}  {name}')
            model['files'].append(dict(name=name, size=size, sha256=digest,
                source=f'{base}/{revision}/{upstream}',
                mirror=f'https://gitee.com/sobranie2406/modu-models/releases/download/ocr-v1/{name}'))
    shutil.copy2(ROOT / 'LICENSES/PaddleOCR-Apache-2.0.txt', output / 'PaddleOCR-Apache-2.0.txt')
    (output / 'ocr-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'OCR-SHA256SUMS').write_text('\n'.join(sums) + '\n')
    (output / 'OCR-SOURCE.txt').write_text(
        'PP-OCRv3/v4/v5 mobile OCR models, copyright PaddlePaddle/PaddleOCR contributors.\n'
        'Licensed under Apache-2.0; original license included.\n'
        'Upstream: https://github.com/PaddlePaddle/PaddleOCR\n'
        'ONNX distribution: https://huggingface.co/SWHL/RapidOCR\n'
        f'Pinned revision: {REVISION}\n'
        'v5 distribution: https://www.modelscope.cn/models/RapidAI/RapidOCR (v3.9.2, pinned SHA-256)\n'
        'Files are copied without modification. This is a distribution mirror, not a new model license.\n')
    print(f'Prepared {len(sums)} verified model files and 4 metadata/license files: {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/ocr-model-mirror')
    args = parser.parse_args()
    prepare(args.source, args.output)
