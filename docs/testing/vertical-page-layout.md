# 竖排阅读页布局

## 使用

- 阅读界面 → 阅读设置 → 文字方向：选择「竖排」。原书本身为竖排时，「自动」也采用竖排边栏。
- 同一区域新增「竖排红色边框」开关，默认关闭；开启后显示红色双框、左右栏分隔线及正文列间细线。
- 正文和左右栏共用整页背景色/背景图片，图片模糊和透明度也保持一致。正文列线按当前可见文字实际位置计算，随字号、行距及翻页重绘，不覆盖跨列图片。
- 章节标题移到右侧；本章剩余页数及全书位置移到左侧。界面语言为中文时使用中文数字，例如「本章剩余四十页」「四十五·一千二百三十九」；繁体中文使用「剩餘」「頁」。
- 全书位置沿用阅读器的虚拟页位置，不是纸质书原始页码。长标题在边栏内省略，不覆盖正文。
- 横排继续采用现有页眉页脚，不显示红框，也不保留竖排边栏空隙。固定版式内容不在本次重排范围内。
- 注释框按实际文字方向计算尺寸：竖排将横排的宽高策略对调，超长内容左右滚动，禁止上下漂移；横排保持上下滚动。均保留 25% 屏幕面积上限、正文 80% 字号及文字末尾留白，短注释仍收缩。
- 注释字号以点击位置所在段落的普通正文实际 CSS 字号为基准，不以序号、上标或阅读设置的 em 值为基准；书籍给正文 span 单独设置字号时也纳入测量。弹框中的嵌套 em/百分比/固定字号统一为该基准的 80%，保留加粗、斜体以及真正上下标的相对大小。嵌套注释沿用最初正文基准，不逐层缩小。

## 实现约束

Mac 的边框和边栏绘制在 WebView 的 renderer shadow root 内，所有装饰节点均设置 `pointer-events:none`，不在 WKWebView 上方叠加整窗 Flutter 绘制层。`IgnorePointer` 只控制 Flutter 命中测试，不足以保证 macOS 原生视图上的覆盖层透传鼠标事件。其他平台目前保留 Flutter 边栏：Windows / Linux 插件采用 Texture 和 Flutter Listener 转发输入，与 macOS 的 AppKitView 不同。

实际文字区域由 renderer host 的物理 padding 缩进，而不是平移 WebView；iframe 的 DOM 坐标因此包含边栏偏移。边栏考虑系统安全区域和页眉页脚字号。Mac 与其他平台共享中文数字和标签格式；页码变化只更新装饰节点，不调用完整 changeStyle，不重新分页，也不修改章节 DOM 或 CFI。

切换文字方向时同步更新章节 iframe 和分页器的方向缓存，原地重新排版，不通过跳到其他章节刷新，因此不额外制造阅读历史。

## 验证

- `flutter test test/widgets/vertical_page_chrome_test.dart`：中文数字、繁体中文、英文、开关持久化、左右边栏位置和安全区域。
- `node --test test/vertical_page_chrome.test.mjs`：物理边距、横排恢复、自动方向及无界面渲染。
- `MODU_JSDOM_ROOT=<jsdom安装目录> node --test test/vertical_web_chrome.test.mjs`：所有装饰节点鼠标穿透、标题安全文本、页码原地更新、红框开关及横排/无界面模式清理。
- `test/reader_footnote_typography.test.mjs` 与 `test/fixtures/footnote-typography.html`：真实 FootnoteHandler 点击路径、原文序号与段落字号区别、嵌套小字号覆盖及每次打开重新取值；WebKit 已验证正文 30px / 序号 10px / 注释原样式 9px 时注释实际为 24px。
- `test/fixtures/vertical-input.html`：使用真实 renderer/view 的合成注释点击和翻页用例；macOS 原生对照入口 `test/fixtures/mac_vertical_input_harness.dart`，不初始化个人书库或同步服务。
- 回归：阅读导航、搜索、选中样式、连续章节及 TTS 游标测试。
- Playwright 隔离合成书页：390×780 视口中确认右到左竖排、翻页，以及分页/滚动模式中横排与竖排的往返切换。
- 已重新生成阅读器兼容 bundle。Mac 原生合成页对照：旧 Flutter 整屏红框开启时鼠标点击不翻页；关闭旧层、仅保留 WebView 装饰后同位置单击正常翻页，注释链接可弹框。Windows/Linux 未进行实机验收；移动端保留原绘制方式。
