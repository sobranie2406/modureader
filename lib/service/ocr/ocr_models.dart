import 'dart:io';

class OcrModelSpec {
  const OcrModelSpec(this.id, this.name, this.englishName, this.files,
      {this.revision = OcrModels.revision,
      this.upstreamBase = 'https://huggingface.co/SWHL/RapidOCR/resolve',
      this.upstreamName = 'Hugging Face',
      this.detectionThreshold = .3,
      this.boxThreshold = .5});
  final String id, name, englishName;
  final String revision, upstreamBase, upstreamName;
  final Map<String, (String, int, String)> files;
  final double detectionThreshold, boxThreshold;
  String readingProfile(bool vertical) {
    if (id == OcrModels.manga.id) return vertical ? 'manga-vertical' : 'manga';
    return vertical ? 'vertical' : '';
  }

  int get totalBytes => files.values.fold(0, (n, file) => n + file.$2);
}

abstract final class OcrModels {
  static const revision = '1cfba2e90fc938db55889873735088de210cc173';
  static const v4Mobile = OcrModelSpec(
      'ppocr-v4-mobile-1', 'PP-OCRv4 中英文', 'PP-OCRv4 Chinese / English', {
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
  static const v5Mobile = OcrModelSpec(
      'ppocr-v5-mobile-1',
      'PP-OCRv5 移动版',
      'PP-OCRv5 Mobile',
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
      upstreamBase: 'https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve',
      upstreamName: 'ModelScope');
  static const defaultModel = v6Small;
  static const v6Small = OcrModelSpec(
      'ppocr-v6-small-1',
      'PP-OCRv6 Small（默认推荐）',
      'PP-OCRv6 Small (recommended)',
      {
        'det.onnx': (
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/28fe5895c24fd108c19eb3e8479f4ab385fbfc62/inference.onnx',
          9880512,
          'd73e0058b7a8086bbd57f3d10b8bcd4ff95363f67e06e2762b5e814fe9c9410e'
        ),
        'rec.onnx': (
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/b8f84f0b80c529de40b4fbb3544b84fa7233a513/inference.onnx',
          21159378,
          '5435fd747c9e0efe15a96d0b378d5bd157e9492ed8fd80edf08f30d02fa24634'
        ),
        'rec.yml': (
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/b8f84f0b80c529de40b4fbb3544b84fa7233a513/inference.yml',
          150579,
          'ab078671bb49f06228eadccd34f1bb501e157f7a047095ffb943ba81512c77d1'
        ),
      },
      revision: 'v6-1',
      detectionThreshold: .2,
      boxThreshold: .45);
  static const v6Medium = OcrModelSpec(
      'ppocr-v6-medium-1',
      'PP-OCRv6 Medium（高精度）',
      'PP-OCRv6 Medium (high accuracy)',
      {
        'det.onnx': (
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_det_onnx/resolve/61323801669c338b7891481ec7bac61ce31b576a/inference.onnx',
          62032837,
          'eb13b44b25bb36f89528b68720af8a61d9cf381176107f465db1757b65d086e1'
        ),
        'rec.onnx': (
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_rec_onnx/resolve/50c7eacafc52fa7bcf4194e8cd08e46f8558504b/inference.onnx',
          76554979,
          '9c09abf0957f7968c7586464b7397b84ad2387a0497a351af40e9acc71b673ba'
        ),
        'rec.yml': (
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_rec_onnx/resolve/50c7eacafc52fa7bcf4194e8cd08e46f8558504b/inference.yml',
          150580,
          '991b700facf5b50a7de193468207d5f4255b538dde0d312ae3b7c7a9b6873129'
        ),
      },
      revision: 'v6-1',
      detectionThreshold: .2,
      boxThreshold: .45);
  static const manga = OcrModelSpec(
      'manga-ocr-1',
      'RT-DETR-V2 + MangaOCR（日语漫画）',
      'RT-DETR-V2 + MangaOCR (Japanese manga)',
      {
        'det.onnx': (
          'https://huggingface.co/ogkalu/comic-text-and-bubble-detector/resolve/16e8a622f91fabc6b5b65c96d32d1183f8843546/detector-v4-s_int8.onnx',
          11120765,
          '5fe9e4f576e49d4e7e8b0e029d6d3cdc252abd4694113e1cae120e62c931ea79'
        ),
        'encoder.onnx': (
          'https://huggingface.co/l0wgear/manga-ocr-2025-onnx/resolve/e8b27bbd3f424fe3877e0bda704d6a920e4f0a33/encoder_model.onnx',
          22356885,
          'f87668ae0f62d6f032dac6b213e8c0fea84cd15895ac8cab624cc9a2f49d4a27'
        ),
        'decoder.onnx': (
          'https://huggingface.co/l0wgear/manga-ocr-2025-onnx/resolve/e8b27bbd3f424fe3877e0bda704d6a920e4f0a33/decoder_model.onnx',
          118053454,
          '6b1fb216d542c4b2a4fa5b9d7ae3522081eb85fb959d2cecd28055af956a8a5e'
        ),
        'vocab.txt': (
          'https://huggingface.co/l0wgear/manga-ocr-2025-onnx/resolve/e8b27bbd3f424fe3877e0bda704d6a920e4f0a33/vocab.txt',
          24072,
          '344fbb6b8bf18c57839e924e2c9365434697e0227fac00b88bb4899b78aa594d'
        ),
      },
      revision: 'v1');
  static const all = [
    defaultModel,
    v6Medium,
    manga,
    v5Mobile,
    v4Mobile,
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
  // HarmonyOS uses a separate Paddle-only ONNX bridge.
  static Iterable<OcrModelSpec> get supported =>
      Platform.operatingSystem == 'ohos' ? all.where((m) => m != manga) : all;
  static OcrModelSpec byId(String id) => supported
      .firstWhere((model) => model.id == id, orElse: () => defaultModel);
}
