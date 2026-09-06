# 可选崩溃诊断与设备环境

## 使用流程

设置 → 提交 Bug → 填写问题 → 可选勾选「附带崩溃日志」→ 展开日志预览 → 预览报告并确认 → 复制完整报告并打开 GitHub → 用户粘贴、核对后自行提交。

默认不附带日志；取消勾选会移除已经加载的日志。异步加载中不能提交或复制不完整报告。失败可重试，仍可提交普通反馈。报告不会自动上传，日志不放入 URL。

「附带设备与运行环境」独立控制平台版本、设备机型、CPU 架构、可用的内存容量及默读版本/构建号。各平台字段不同，缺失的字段不猜测。不导出主机名、设备自定义名称、账户、序列号、IMEI、Android ID、设备 UUID、产品 ID 或系统构建指纹。

## 全平台与系统能力边界

- Android、iOS、macOS、Windows、Linux 共用本地诊断记录：Flutter 异常、主 isolate 未处理异常的类型和应用源码位置、启动/退出、向量任务阶段与进度。异常消息、普通日志、用户文件路径、书名、正文、URL、密钥不记录。最近 16 条，文件约 30 KB 上限，不进入 WebDAV 同步。
- 下次启动保留上次记录。没有确认正常退出只标记「上次会话未确认结束」，不能把强制关闭、系统回收都认定为崩溃。
- Android 11+ 按用户勾选读取本应用最近可用的系统异常退出记录：退出原因、状态码、时间、RSS/PSS 采样；Android 12+ 尝试读取原生崩溃 tombstone，仅保留故障线程最多 32 帧的相对 PC、公开库名和 ELF Build ID。最多 3 条记录，每份原始 trace 读取上限 1 MiB。原始 trace 不落盘、不分享；内存内容、日志缓冲、异常消息、线程名称、全路径全部忽略。
- Android 保存的退出记录可能来自升级前的同一应用，但老版本没有本地诊断记录或阶段检查点时无法补造。
- iOS/macOS 已接入原生 MetricKit：插件注册时订阅诊断并处理系统保留的历史 payload；系统异步送达后，只把故障线程最多 32 帧的已知模块名、模块内偏移、二进制 UUID、数值异常类型/信号、应用版本和报告区间写入应用自己的支持目录。最多保留 3 份、32 KB，原子写入，排除系统备份。二进制 UUID 用于代码符号定位，不是设备 ID。不扫描用户 `.ips` 目录，不持久化原始 payload。报告区间不是精确崩溃时间；延迟送达、未送达和缺失故障线程均明确提示。
- Windows 已接入 `SetUnhandledExceptionFilter` + `StackWalk64`（x64/ARM64 上下文分支）。启动时预开应用专属记录文件，异常时先写入并刷新错误码/时间/构建号，再尝试最多 32 帧，只保存公开 DLL 名、相对 PC、PE 时间戳/映像大小；下次启动恢复上一份记录。不会生成 minidump、记录异常参数或启动符号服务器。保留先前异常处理器与系统退出行为；堆栈损坏、fail-fast、其他组件替换处理器以及系统强杀不保证可捕获。这里仍需 Windows 平台编译与实际子进程崩溃验证。
- Linux 已接入系统原生记录读取（不是自建信号处理器）：用户勾选时以参数数组运行 `coredumpctl --no-pager -1 --since=7 days ago info COREDUMP_EXE=<当前程序绝对路径>`，只取本程序最新记录，256 KiB 总管道上限、5 秒超时，退出失败/输出过大则丢弃原始输出。只导出信号及系统给出的第一条线程堆栈的公开模块/偏移，不假定该线程一定是故障线程。不读取 core 内存，不执行 `dump`/`debug`，不启用转储、不提权。没有 systemd-coredump、无权限、不同安装路径或记录已清理时会提示不可用；不承诺覆盖所有 Linux 发行版。
- 所有平台均不导出原始内存；子 isolate 内部未转交的错误和资源耗尽/系统强杀仍可能只有最后操作记录，甚至没有记录。诊断不进入 WebDAV 同步。
- **本次增加的是诊断能力，不等于已修复 iQOO 上持续发生的崩溃，也不承诺捕获所有类型的崩溃。**

Android 官方接口与格式：[ApplicationExitInfo](https://developer.android.com/reference/android/app/ApplicationExitInfo)、[tombstone.proto](https://android.googlesource.com/platform/system/core/+/refs/heads/main/debuggerd/proto/tombstone.proto)。

## 索引状态

重建前持久写入 `.building` 标记，正常结束、取消或捕获到失败后清理；进程意外结束则保留。标记存在时，书架不能拿旧索引或内存中的索引缓存显示「已索引」，但保留旧文件以供恢复。日志分别记录提取、准备、向量计算、保存、完成等阶段。

这只适用于新增标记之后开始的重建。旧版崩溃后显示已索引，既可能是旧索引，也可能是已经保存完成才退出，不能仅凭标签判断原因。

## 第一阶段验证（本地事件和 Android）

- 完整 Flutter 回归：258 项通过、2 项跳过。覆盖反馈服务、诊断脱敏、可选框、确认后复制、异步取消、设备字段与索引标记。新增诊断与索引标记代码逐文件静态分析通过。
- Android ARM64 Debug 与 macOS Debug 构建通过；未启动这些应用执行真实崩溃测试，Windows/Linux/iOS 未在本轮构建或真机验证。
- 使用合成异常、私密字段哨兵、合成 tombstone、模拟浏览器和剪贴板，不提交真实 Issue、不读取用户书籍或服务密钥。
- 未连接 iQOO Neo8，未制造实际手机崩溃。
- 本轮未修改 GitHub Release 和 README，不把未验证事项放到首页。

## 第二阶段验证（其他平台原生接入）

- 完整 Flutter 回归：267 项通过、2 项跳过；反馈相关 34 项通过。新增 Apple/Windows/Linux 格式过滤、损坏/超大输入、管道超时与输出限额测试均使用合成数据，没有访问真实系统崩溃记录或提交 Issue。
- Apple 原生 Swift 摘要测试已编译并运行通过：故障线程选择、公开模块白名单、嵌套堆栈遍历、32 帧限制、损坏/超大 JSON 和隐私哨兵。
- macOS Debug 已构建通过，确认插件注册和 MetricKit 链接；未制造真实应用崩溃或验证系统实际异步送达。
- iOS 全应用构建被本机 Xcode 环境阻挡：`xcodebuild -showdestinations` 显示 `iOS 26.5 is not installed`，无可用构建目标；有 SDK 头文件不等于已安装所需平台组件。未擅自安装组件，不将此算作构建通过。
- 已使用本机 iOS SDK 与 Flutter iOS framework，对完整 Apple 插件（含 iOS 注册分支）执行 `swiftc -typecheck -target arm64-apple-ios16.0`，通过；这只是原生代码类型检查，不等同于 iOS App 构建或真机诊断验证。
- Windows/Linux 尚未在目标系统构建或验证系统崩溃的完整读取链路。Windows 提供独立测试源 `test/native/WindowsCrashRecorderTest.cpp`，只能在隔离测试账户/虚拟机运行，不链接进 App，不增加用户可触发的崩溃入口。
- Beta3 Release 未更新；新增收集器不能补造旧版本未记录的 Windows 堆栈，也不等于已修复原向量化闪退。

## 原生测试和符号定位

Apple 摘要测试（macOS）：

```sh
swiftc third_party/modu_native_crash/darwin/Classes/NativeCrashSummary.swift test/native/AppleCrashSummaryTest.swift -o /tmp/modu-apple-crash-summary-test
/tmp/modu-apple-crash-summary-test
```

Windows 独立测试（隔离测试账户的 x64/ARM64 Native Tools 开发者命令行）：

```bat
cl /std:c++17 /EHsc /W4 /WX /wd4100 /DUNICODE /D_UNICODE /DFLUTTER_VERSION_BUILD=6330 test\native\WindowsCrashRecorderTest.cpp windows\runner\native_crash_recorder.cpp /Fe:modu-crash-test.exe /link dbghelp.lib shell32.lib ole32.lib
modu-crash-test.exe
```

该测试会启动自身子进程，制造测试异常并验证下次启动可读。诊断用的公开模块内偏移必须配合**崩溃时同一版本/架构**的二进制、dSYM/PDB/ELF 调试符号定位；不把偏移或主机测试结果当作手机闪退原因。

官方接口依据：[Apple MetricKit](https://developer.apple.com/documentation/metrickit/mxmetricmanager)、[Apple callStackTree JSON](https://developer.apple.com/documentation/metrickit/mxcallstacktree/jsonrepresentation())、[Windows 未处理异常接口](https://learn.microsoft.com/en-us/windows/win32/api/errhandlingapi/nf-errhandlingapi-setunhandledexceptionfilter)、[StackWalk64](https://learn.microsoft.com/en-us/windows/win32/api/dbghelp/nf-dbghelp-stackwalk)、[systemd coredumpctl](https://github.com/systemd/systemd/blob/main/man/coredumpctl.xml)。
