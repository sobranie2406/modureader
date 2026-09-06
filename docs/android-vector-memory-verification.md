# Android 向量化内存修订验证（6330）

## 问题与范围

用户反馈：Beta3，Android 16，iQOO Neo8，EPUB 使用第三个 512 维中文 BGE 模型向量化到一定进度后退出。没有收到崩溃堆栈，当前没有连接该手机，不能确定是系统内存回收、原生信号崩溃还是其他原因。

四个内嵌模型原先共用同一条推理路径。旧实现使用默认 ONNX 内存池，把最多 512 × 512 个隐藏状态值传给 Dart，再复制、池化为最终向量；会增加连续推理的内存与垃圾回收压力。这是代码中确认的风险，不是已经在原手机复现的唯一根因。

## 代码修改

- Android 使用独立的后台串行通道与 CPU 会话，单线程、基础图优化，关闭 CPU arena 与 memory pattern。
- 在原生端完成均值池化及 L2 归一化，只跨通道返回 384/512 个最终值。保留模型 ID、输出维度与池化方式，不清除原有书籍或索引。
- 输入张量、输出 Result 和 SessionOptions 使用明确的关闭生命周期；异常后释放模型，会话空闲 15 秒后卸载。
- 捕获可捕获的 Java 内存不足异常并报告任务失败。这不能拦截 Android 强杀、SIGSEGV 或其他原生信号。
- 重新分词后再次限制实际输入为 512 tokens，保留末尾分隔 token。
- macOS/Linux/Windows/iOS 继续使用原有推理后端；本次只生成 Android 修订包。

官方资源所有权说明：[ONNX Java 入门](https://onnxruntime.ai/docs/get-started/with-java.html)、[Result.close](https://onnxruntime.ai/docs/api/java/ai/onnxruntime/OrtSession.Result.html)。

## 已执行测试

- Flutter 全套：242 项通过、2 项跳过；其中向量模块 40 项通过（新增 6 项通道、维度、错误和长度边界测试）。
- 阅读器 JavaScript：19 项通过。
- 安装包检查工具单元测试：18 项通过。
- 新增/修改的推理 Dart 代码、通道测试和集成测试逐文件 `dart analyze` 均通过。Flutter 多文件分析命令遇到分析器内部 JSON 错误，未将该失败记为通过。
- Android ARM64 Debug 编译通过。
- Android ARM64 / x64 Release（6330）编译通过。两个 APK 均验证原签名指纹、应用 ID、版本号、非调试标记、无震动权限、四个内嵌模型内容哈希、新原生推理通道、ONNX 1.24.3 原生库 Build ID，以及全部 7 个原生库的架构和 16 KB 对齐。
- 使用生产 Java 会话实现、官方 ONNX Runtime Java 1.24.3 及四个真实内嵌模型，在 macOS ARM64 执行 332 次推理。每个模型 80 次交替长度（16—512 tokens）及 3 次释放/重载推理；校验维度、有限值、归一化、过长输入拒绝。
- Java 堆上限 192 MiB、直接内存上限 128 MiB。以下为第 16/80 次推理后请求 GC 的进程 RSS 检查点，并非峰值，也不是 Android 内存测量。

| 模型 | 维度 | 次数 | RSS 检查点 KiB（16 → 80） | 结果 |
| --- | ---: | ---: | ---: | --- |
| all-MiniLM-L6-v2 | 384 | 83 | 185264 → 192944 | 通过 |
| bge-small-en-v1.5 | 384 | 83 | 229952 → 231776 | 通过 |
| bge-small-zh-v1.5 | 512 | 83 | 286000 → 287872 | 通过 |
| multilingual-e5-small | 384 | 83 | 527424 → 323408 | 通过 |

测试不使用用户书籍或密钥。E5 模型仍明显较大，不能据此保证所有手机可在任意内存压力下运行。

## 尚未验证

- iQOO Neo8 / Android 16 原 EPUB 的完整向量化、后台切换、阅读与向量化并行的真机体验。
- 其他 Android 设备、极大 EPUB、系统低内存强制回收，以及 Rust tokenizer 的完整真机压力路径。
- `integration_test/bundled_embedding_test.dart` 新增真实分词与通道压力模式，但本机没有 Android 设备，未执行该模式。连接设备后可运行：

```sh
flutter test integration_test/bundled_embedding_test.dart -d DEVICE_ID --dart-define=MODU_EMBEDDING_STRESS=true
```

该模式每个模型运行 80 次长短中英文文本，校验输出，并在释放后重新加载。它仍不能替代原 EPUB 重现测试。

## 安装与复测

版本为 `0.1.0-beta.3+6330`，原 Beta3 为 6329。使用原默读专用签名密钥，不更换应用 ID；应直接覆盖安装，不要卸载旧版。iQOO Neo8 选择 ARM64 APK。

安装后在书籍菜单重新向量化原 EPUB，先验证中文 BGE，再验证其余三个模型；观察能否完成、取消/排队和阅读是否正常。如果仍退出，需要崩溃时间和系统日志确认原因，不应继续把所有退出归因于内存。

不改 README。按用户后续要求，以本次 6330 修订包替换既有 Beta3 Release 的 Android 附件及其校验、许可附件；其他平台仍保留 6329，原 Beta3 标签不移动。Android 对应修订源码在 Release 说明和许可附件中单独链接。

安装包位于 `dist-release/android-hotfix-6330/`：

- `Modu-0.1.0-beta.3-6330-android-arm64.apk`，SHA-256：`045eac1a427c6292fdc9da4b3766f7a8e28ed24d08f6e76b2a6fd4496155473c`。
- `Modu-0.1.0-beta.3-6330-android-x64.apk`，SHA-256：`f96b5fec3ab8b65338467c6882e6e1ed87fc33005e81dbc11dd2da02cd073501`。

本地打包注意：调试测试后使用标准 `flutter build apk --release ...` 流程重新生成平台插件注册文件。本次两次 `--no-pub` 构建保留了测试插件注册，但 release 依赖不包含测试插件，导致 Java 编译失败；移除该跳过参数后重新构建。不要手工把 integration_test 加进正式版依赖。
