# Display assets / 展示素材

## Current homepage / 当前首页

The English homepage is [README.md](../../README.md); the Chinese homepage is [README_zh.md](../../README_zh.md). README_EN.md keeps the previous English URL working.

Only the nine images in `showcase/cross-platform/` are published in the current source tree. Each pairs a macOS window behind an overlapping iPhone, showing reading/navigation, voice templates, AI reading skills or selection-tool customization. The Chinese page also includes framed vertical reading. Images accompany their corresponding feature descriptions.

当前首页保留九张中英文双端展示图：Mac 窗口在后、iPhone 在前错位叠放，搭配简洁标题、浅色背景与柔和阴影。Mac 部分以实际界面截图为依据，iPhone 部分使用先前生成的手机渲染图作为来源，保留灵动岛、状态栏和底部横条。已移除桌面录屏标记与鼠标指针。

Reading content comes from the original demonstration books [《阅读，让思考慢下来》](../examples/modu-reading-demo.epub) and [The Quiet Reader](../examples/modu-reading-demo-en.epub). Their source and redistribution terms are in [examples/README.md](../examples/README.md). No private bookshelf, notes, AI conversation or credentials are included. Settings shown illustrate the features, not necessarily factory defaults.

## Source archive / 来源归档

The source images were removed from the current tracked tree on 2026-10-03 to avoid shipping unused, duplicate or upstream marketing material. They remain recoverable in [the previous Git revision](https://github.com/sobranie2406/modureader/tree/dae8ecc4ef7ac34cfe252f8039008716d5cee6ff/docs/images), and local working copies are ignored rather than deleted:

- `showcase/*.png`: the previous iPhone-only renders used to compose the current artwork.
- `v1.1.9/`: Android and Mac Modu 1.1.9+10063 captures from 2026-10-01, including the original demonstration books and settings screens.
- The seven older `*-macos.jpg` files: Modu 1.1.1+10033 captures from 2026-09-21, including the then-approved vertical-reading example.
- `Anx-logo.jpg`, `main.jpg`, `wide*.png`, `mobile*.png` and `zh/`: inherited Anx Reader marketing assets, not current Modu UI.

这些旧素材已撤出当前源码，但本地副本及 Git 历史仍保留，便于恢复或继续设计。不要将上游截图作为默读当前界面重新发布。各依赖的许可证、版权声明和来源文档不属于本次素材清理范围。
