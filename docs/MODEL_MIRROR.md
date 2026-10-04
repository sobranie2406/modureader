# 按需下载模型镜像

公开仓库：[sobranie2406/modu-models](https://gitee.com/sobranie2406/modu-models)；[模型发行版 models-v1](https://gitee.com/sobranie2406/modu-models/releases/tag/models-v1)。
2026-09-16 已发布 9 个模型/分词器附件、3 份许可证、清单与校验文件，并通过应用下载服务的四模型匿名下载、大小及 SHA-256 校验（包括 E5 分片重组）。新安装默认选择 Hugging Face，已保存的下载源不改变，用户可切换 Gitee。

仅镜像 `assets/models/embeddings/manifest.json` 中固定 revision 的 Xenova ONNX 量化模型及分词器。MiniLM 保留 Apache-2.0，BGE 与 E5 保留原 MIT 许可证、版权及来源，不将其改成默读的 GPL 许可证。

## 准备

`python3 scripts/release/model_mirror.py --fetch`

该命令下载缺失的公开文件，复用 SHA-256 校验通过的缓存，把发布附件生成到 `build/model-mirror`，不上传。不需要重复获取已有且校验完全相同的 HF 文件。

- 附件名称包含模型 ID、上游 40 位 revision 和原文件名。
- 文件大于 64 MiB 时分片（`.part-01`、`.part-02`）；目前仅 E5 权重需要。分片只拆分字节，不重新压缩、不修改模型。客户端按顺序流式合并，再校验原完整文件 SHA-256；截断、乱序或损坏都不能用于推理。
- 同时提供 `manifest.json`、`SHA256SUMS` 和三份原始许可证文件。
- 发布说明注明四个 HF 仓库、revision、尺寸与许可证，上传附件后再发布 Release。Gitee 如需账号安全验证/公开审核，先由账号持有人完成。
- 逐一验证无需登录的下载入口、重定向及重组后的原始 SHA-256。不能只看上传进度。已确认下载链：Gitee Release → 同仓库 attach_files → `https://foruda.gitee.com/attach_file/`。客户端仅接受对应路径的 HTTPS 地址；平台若引入其他 CDN，核实后再添加精确域名，不能放开任意网站。

## 回归验证

`flutter test --no-pub test/service/knowledge test/widgets/settings/vector_model_download_test.dart`

`python3 test/model_mirror_test.py` 与 `python3 test/release_package_test.py`

真实下载校验默认跳过，显式运行（消耗约 218 MB 流量，临时副本会自动清理）：

`flutter test --no-pub --dart-define=MODU_VERIFY_MODEL_MIRROR=true test/service/knowledge/model_mirror_live_test.dart`

## 构建与迁移

`pubspec.yaml` 仅声明模型 manifest，不声明权重目录。发布检查拒绝携带权重/分词器的旧缓存产物。CI 的模型文件仅用于独立原生推理测试：Android 在测试 APK，Windows/macOS 通过本机测试服务器下载；不移除四模型推理检查。

升级不会删除已下载的模型；相同大小及 SHA-256 的旧文件继续使用。默认自动索引仍关闭，模型缺失只提示下载，不能暗中下载四个模型。更换下载源不改变模型 revision、维度或索引格式。

## 轻量 OCR（独立于向量模型）

设置 → OCR 模型可选择模型与下载源。推荐优先下载并使用 v4，默认 v4、上游来源；v5 仅为可选模型，不自动切换已有选择。仅主动下载选中的模型，识别在本机进行。模型选择及下载源纳入全局设置备份，不包含模型权重。旧 v4 缓存路径保持不变，切换来源复用通过 SHA-256 校验的文件。

| 模型 | 检测 + 识别下载大小 | 上游 |
| --- | --- | --- |
| PP-OCRv4 中英文（默认） | 14.9 MiB | Hugging Face |
| PP-OCRv5 中英文轻量版 | 20.5 MiB | ModelScope |
| PP-OCRv3 中英文 | 12.5 MiB | Hugging Face |
| PP-OCRv3 英文 | 10.9 MiB | Hugging Face |

2026-10-04 已发布 [ocr-v1](https://gitee.com/sobranie2406/modu-models/releases/tag/ocr-v1)，包含 8 个模型文件和 4 个来源、许可证、清单及校验附件。不替换 `models-v1`。四套 Gitee 模型和 v5 上游已通过应用下载服务的匿名下载、字节大小及 SHA-256 校验，四模型均通过 Mac 原生推理检查。

精确文件、revision 和校验值见 `lib/service/ocr/ocr_models.dart`。v3/v4 固定 Hugging Face revision，v5 固定 RapidOCR 分发版本 v3.9.2 及官方 SHA-256。模型沿用 Apache-2.0，不修改原字节、不重新训练。没有下载 GitHub 权重的入口：这几套 ONNX 的实际分发源是 Hugging Face / ModelScope，界面如实显示。

准备附件：`python3 scripts/release/ocr_model_mirror.py --source <已下载原模型目录>`，输出至 `build/ocr-model-mirror`。脚本不上传；每个输入文件按原始文件名存放，大小或 SHA 不匹配会拒绝复制。

真实下载校验（默认跳过，显式执行约 80 MiB）：

`flutter test --no-pub --dart-define=MODU_VERIFY_OCR_MIRROR=true test/service/ocr_model_live_test.dart`

常规回归：`flutter test --no-pub test/service/ocr_model_store_test.dart test/widgets/settings/ocr_model_test.dart test/service/config_transfer`

下载器只接受指定来源的 HTTPS 重定向，失败不会暗中换源。识别 CPU 线程数上限 2；v5 更大的字表对应输入宽度及输出张量上限，避免单行推理输出无界增长。
