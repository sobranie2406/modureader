# 朗读漏标题 / 跳章节修复（2026-09-06）

## 对照来源

按 ReadAny 理解用户提到的“Reader Annie”，核对其官方源码提交
`021137eb3dbb398096193ee7b6819e665a281d32`：

- [朗读会话管理](https://github.com/codedogQBY/ReadAny/blob/021137eb3dbb398096193ee7b6819e665a281d32/packages/core/src/stores/tts-store.ts)：使用会话编号忽略停止后的迟到回调，只在自然播放结束时通知完成。
- [Foliate 朗读提取](https://github.com/codedogQBY/ReadAny/blob/021137eb3dbb398096193ee7b6819e665a281d32/packages/foliate-js/tts.js)：标题属于文本块；不应把普通链接文字整体当成需要跳过的注释。
- [播放游标](https://github.com/codedogQBY/ReadAny/blob/021137eb3dbb398096193ee7b6819e665a281d32/packages/core/src/tts/playback-cursor.ts)：按实际播放位置更新游标，而不是按合成请求进度更新。

本次针对默读 Flutter / WebView 调用链修复，并非直接替换成 ReadAny 的播放器。

## 已定位的问题

1. `initTts()` 已由 JavaScript `from()` 选中第一句，却丢弃其返回值；系统朗读随后调用 `next()`，再次前进，漏读标题/首句。
2. 文本过滤器跳过全部本地链接，包含返回目录链接的章节标题也被过滤。
3. Android 原生开始回调负责预入队，完成回调又推进游标；停止、恢复和章节加载交错时没有会话隔离。
4. 在线朗读预取可能跨越游标切章时刻，却仍用“排除当前句”的参数，漏掉下一章标题；以文字哈希去重还会漏掉没有 CFI 的重复段落。
5. 在线合成失败或返回空音频被标记为静音并自动继续，连续失败可能表现为整章被跳过。
6. 上/下一章按钮没有等待停止完成，切章后又调用上一/下一句，产生额外推进。
7. 章节结束依赖互相递归调用；空章或书末没有严格终止条件，导航失败也没有清楚地传回 Dart。

## 修复原则

- 初始化直接返回当前句，不再多走一次。保留普通链接和 H1–H6；仅过滤明确的脚注引用、回注标记、隐藏文本及 ruby 注音等。
- 系统语音以单条等待完成的播放循环推进，Android 关闭旧的双回调入队方式。
- 使用会话编号屏蔽停止后的异步结果；章节加载中暂停时，恢复保留已定位的新章首句。
- 在线语音只在稳定的播放游标处补充有序批次，在播放完成后推进；不再按文本去重。
- 合成、播放或导航失败暂停并展示错误，重试保留当前位置，不用静音代替失败。
- 章节导航串行化、空章有界处理、到书末停止；手动切章不再追加一次句子跳转。
- 原生媒体控制状态跟随真实播放结束/失败状态，避免书末仍显示正在播放。

## 验证与边界

本轮最终结果：215 项 Flutter 测试通过、2 项联网测试跳过；19 项 JavaScript
测试通过；1 项 macOS 原生系统语音集成测试通过；Android ARM64 Debug 构建成功。
本机 custom_lint 分析插件仍有运行环境错误，不能宣称完整静态分析通过。

- JavaScript 回归覆盖文本标题、链接标题、脚注、当前范围初始化、单句章节、空章、书末、双请求和停止取消。
- Dart 使用真实 `SystemTts` / `OnlineTts` 类与可控的原生/音频接口，验证顺序、错误重试和异步交错，而不是只检查源码字符串。
- macOS 原生系统语音集成测试实际完成三个测试句，包括两个标题，并验证原生完成后的游标顺序；未读取私人书库。窗口前台激活失败，因此不宣称进行了界面操作验收。
- Android ARM64 构建用于验证可编译/打包，不等同于 Android 真机听读验收。
- 没有用户原始问题书籍，没有新增 OCR：图片形式的标题、纯扫描 PDF 或文件本身缺失的文字不在这次文本提取修复范围。

复测命令：

```sh
flutter test --no-pub
MODU_JSDOM_ROOT=/path/to/jsdom-fixture node --test test/reader_business.test.mjs test/reader_background.test.mjs test/reader_tts.test.mjs
flutter test integration_test/tts_reader_test.dart -d macos --dart-define=MODU_NATIVE_TTS_TEST=true
```

上述验证在本地修复阶段完成。应用户后续发布要求，修复纳入 Beta3（build 6328）；不替换 Beta2 安装包。正式分发状态以 GitHub Release 和对应 CI 结果为准。
