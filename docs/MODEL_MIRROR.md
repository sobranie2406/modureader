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
