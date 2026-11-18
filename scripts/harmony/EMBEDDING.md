# HarmonyOS 本地 ONNX 推理

`modu/ohos_embedding` 使用独立的 ONNX Runtime CPU 会话。加载、推理和释放均在原生异步任务中执行，通道按顺序调用；不访问远程向量接口。

构建前运行：

```sh
python3 scripts/harmony/prepare_embedding_runtime.py
```

脚本只下载 `embedding_runtime.json` 固定版本、提交和 SHA-256 的 OHOS arm64 产物，校验后写入 `build/` 及忽略的 OHOS 打包目录。`--archive /path/runtime.zip` 支持使用已下载原件。许可证随 HAP 打包。发布检查拒绝缺失、其他架构或不匹配的运行库。

运行库由 [onnxruntime-libs](https://github.com/csukuangfj/onnxruntime-libs/blob/master/.github/workflows/harmony-os-shared.yaml) 从 [Microsoft ONNX Runtime](https://github.com/microsoft/onnxruntime/tree/v1.27.0) 源码交叉编译，不属于 Microsoft 官方 OHOS 二进制发布。更换版本须重新审核 ABI、依赖、许可证、模型兼容性与校验值。

通道接口：

- `isAvailable()`：检查本机运行库 API。
- `load({modelPath})`：只读取本地 ONNX 文件。
- `embed({ids: Int64List, dimensions})`：最多 512 个 token，返回 384 或 512 维归一化向量。
- `close()`：释放当前会话。

`modu/ohos_ocr` 复用同一个 ONNX 运行库，分别加载文字检测和识别模型。`load({path})` 打开单个模型，`run({name, data, shape})` 接收 Float32 图像张量并返回输出张量及形状，`close()` 释放 OCR 会话。

本地检查：

```sh
python3 -B -m unittest discover -s test -p 'harmony_*test.py' -v
```

原生编译可用 SDK 的 `native/build/cmake/ohos.toolchain.cmake`，指定 `OHOS_ARCH=arm64-v8a`。设备验收覆盖内置向量模型、英文和中文文本推理、OCR 模型切换、PDF 文字提取和扫描页识别。
