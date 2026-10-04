class OcrModelSpec {
  const OcrModelSpec(this.id, this.name, this.englishName, this.files,
      {this.revision = OcrModels.revision,
      this.upstreamBase = 'https://huggingface.co/SWHL/RapidOCR/resolve',
      this.upstreamName = 'Hugging Face'});
  final String id, name, englishName;
  final String revision, upstreamBase, upstreamName;
  final Map<String, (String, int, String)> files;
  int get totalBytes => files.values.fold(0, (n, file) => n + file.$2);
}

abstract final class OcrModels {
  static const revision = '1cfba2e90fc938db55889873735088de210cc173';
  static const defaultModel = OcrModelSpec('ppocr-v4-mobile-1',
      'PP-OCRv4 中英文（推荐）', 'PP-OCRv4 Chinese / English (recommended)', {
    'det.onnx': (
      'PP-OCRv4/ch_PP-OCRv4_det_infer.onnx',
      4745517,
      'd2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9'
    ),
    'rec.onnx': (
      'PP-OCRv4/ch_PP-OCRv4_rec_infer.onnx',
      10857958,
      '48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b'
    ),
  });
  static const all = [
    defaultModel,
    OcrModelSpec(
        'ppocr-v5-mobile-1',
        'PP-OCRv5 中英文（轻量新版）',
        'PP-OCRv5 Chinese / English (new mobile)',
        {
          'det.onnx': (
            'onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx',
            4819576,
            '4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae'
          ),
          'rec.onnx': (
            'onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx',
            16631306,
            '5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5'
          ),
        },
        revision: 'v3.9.2',
        upstreamBase:
            'https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve',
        upstreamName: 'ModelScope'),
    OcrModelSpec('ppocr-v3-mobile-1', 'PP-OCRv3 中英文（更小）',
        'PP-OCRv3 Chinese / English (smaller)', {
      'det.onnx': (
        'PP-OCRv3/ch_PP-OCRv3_det_infer.onnx',
        2432880,
        '3439588c030faea393a54515f51e983d8e155b19a2e8aba7891934c1cf0de526'
      ),
      'rec.onnx': (
        'PP-OCRv3/ch_PP-OCRv3_rec_infer.onnx',
        10690752,
        '897a3ededb38fee0dae2c1ccee38241f37df202c9509e3abca02e9217c5ee615'
      ),
    }),
    OcrModelSpec('ppocr-v3-english-mobile-1', 'PP-OCRv3 英文（轻量）',
        'PP-OCRv3 English (lightweight)', {
      'det.onnx': (
        'PP-OCRv4/en_PP-OCRv3_det_infer.onnx',
        2423224,
        'f139598bc2af4e4b6fe98dec11574e30edfdd91fc94ac1425c18ace3bd5a866b'
      ),
      'rec.onnx': (
        'PP-OCRv3/en_PP-OCRv3_rec_infer.onnx',
        8967018,
        'ef7abd8bd3629ae57ea2c28b425c1bd258a871b93fd2fe7c433946ade9b5d9ea'
      ),
    }),
  ];
  static OcrModelSpec byId(String id) =>
      all.firstWhere((model) => model.id == id, orElse: () => defaultModel);
}
