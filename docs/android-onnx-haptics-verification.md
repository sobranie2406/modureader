# Android 本地推理与震动移除检查（2026-09-05）

## 问题与证据边界

用户报告小米 15 Ultra 点击四个内嵌模型的“测试推理”均闪退；
尚无 Android 版本、崩溃堆栈或连接的真机，不能确认该手机的最终根因。

四个模型共用 flutter_onnxruntime 1.8.4 的 Android 原生库，插件原来固定
ONNX Runtime 1.23.0。上游报告 1.23.x 在部分 ARM Android 设备上因
CPU 指令识别错误发生 SIGILL；Dart 的异常捕获不能拦截这类进程崩溃。

- 原生崩溃记录：<https://github.com/microsoft/onnxruntime/issues/27282>
- 后续报告与修复确认：<https://github.com/microsoft/onnxruntime/issues/27884>
- SME1/SME2 区分修正：<https://github.com/microsoft/onnxruntime/pull/25760>

## 本轮修改

- 只将 Android 的 onnxruntime-android 固定到 1.24.3，保持 CPU 推理及现有
  单会话串行调度，Apple/Windows/Linux 的运行库版本不变。
- 曾尝试 1.24.4，但 Maven Central 没有 Android 构件，构建失败后未保留此配置。
  对比上游 1.24.3 与 1.24.4，后者未修改 CPU 检测或 MLAS；1.24.3 已有
  SME1/SME2 修正且有正式 Android 构件。许可证随实际版本更新。
- 删除震动服务、开发者震动测试页、相关设置及 16 种语言文案，删除两个震动插件。
- 禁用底栏反馈，用 Manifest 合并规则阻止依赖重新引入 VIBRATE 权限；
  Android Activity 关闭 DecorView 触觉反馈，覆盖 Flutter 框架长按反馈路径。
  不修改系统输入法自己的震动设置。
- CocoaPods 重新生成锁文件以移除震动插件，并使锁文件与现有 Flutter 插件一致；
  Apple ONNX 仍为 1.23.0，未升级 Apple 运行库。

## 已验证

- Flutter 全量测试：205 通过、2 跳过（需要显式开启的联网测试）。
- 最终版本配置的平台回归检查：3 通过。
- 阅读器 JavaScript 回归：10 通过；发布打包脚本测试：18 通过。
- Gradle debugRuntimeClasspath：1.23.0 被规则替换为 1.24.3。
- 1.24.3 官方 AAR 内 ARM64 / x86_64 的 ONNX 及 JNI 库：64 位架构、16 KB
  ELF LOAD 对齐检查通过。
- Android ARM64 Debug APK 构建成功，7 个原生库架构及 16 KB ELF 对齐通过；
  APK zipalign 16 KB 检查、v2 签名校验通过。
- ONNX 和 JNI 的合并输入与官方 1.24.3 AAR 完全一致，APK 内库与构建去符号后的
  输出完全一致。AAR 与最终 APK 不应直接按全文件哈希比较，因为构建会剥离符号。
- APK 包含全部四个 ONNX 模型及新版许可证，最终权限列表不含 VIBRATE。

本地测试包：`build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`（约 246 MiB）。
SHA-256：`4569628afae1ac88c20e2c814101a7d4db7fc09ee7057fdc61c5bc1a47efbf1f`。
这是 Debug 签名，不是正式更新包，不能保证覆盖安装已有 Beta1；不要为安装它直接
卸载现有应用而丢失书籍、笔记或设置。未重新构建或发布正式签名版本。

## 真机验收仍待执行

1. 保留现有应用数据，在使用相同正式签名的测试版本中逐个测试中文 BGE、英文 BGE、
   MiniLM 和 E5，记录实际输出维数及是否闪退。
2. 对书籍排队向量化，同时打开其他书籍阅读；确认完成、取消、重新向量化均正常。
3. 检查底栏切换、统计卡片、长按菜单与文字选择不再触发应用震动。
4. 若仍闪退，采集复现时的 Android crash buffer，区分 SIGILL、SIGSEGV、
   Java 异常和系统低内存终止后再作针对性修复。日志分享前应去除私人信息。

本轮不等同于真机修复验收，不会自动提交代码或替换 GitHub Beta1 发布包。
