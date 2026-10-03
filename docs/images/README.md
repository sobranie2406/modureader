# Display assets / 展示素材

## Current homepage / 当前首页

The English homepage is [README.md](../../README.md); the Chinese homepage is [README_zh.md](../../README_zh.md). README_EN.md keeps the previous English URL working.

The 29 images in `showcase/cross-platform/` are the current homepage set. A macOS window sits behind an overlapping iPhone, with a clear headline, a light backdrop and soft shadows. Each major feature has its own image beside its description; the Chinese page also includes framed vertical reading.

当前首页使用 29 张双端展示图，按功能分散在中英文介绍中。图像以实际界面和代码支持的功能为依据，经内置图像生成工具排版与重绘；iPhone 保留灵动岛、状态栏和底部横条，界面使用 iOS 风格字体。已移除桌面录屏标记和鼠标指针。

Every feature pair uses **iPhone configuration → Mac result**. Keep these roles fixed: the phone shows controls or an editing step, while the larger Mac window shows what those controls produce. Preserve the actual Mac interface structure; replace private content only within that structure.

功能配图统一为 **手机设置 → Mac 效果**，不交换设备角色。Mac 保留实际界面的布局与控件关系，隐私内容仅在原有框架内替换。

| Assets | Configuration | Visible result |
| --- | --- | --- |
| `library-*` | Create a folder for selected books | Books organized into a folder |
| `styles-*` | Font, thickness and spacing | Comfortable book typography |
| `css-*` | Visual CSS and highlight rules | Colored dialogue, wavy underlines and keyword highlights |
| `listening-*` | Narration template and voice description | Current passage highlighting and compact playback controls |
| `skills-*` | A chapter-summary prompt | A reader AI answer and follow-up input |
| `selection-*` | Custom AI action and scope | Selection handles, toolbar and annotation controls |
| `translation-*` | Translation provider | An in-reader translation result |
| `dictionary-*` | Imported dictionary enabled | An offline word definition beside the book |
| `notes-*` | Highlight and comment editing | Saved book notes |
| `statistics-*` | Add a dashboard card | Reading charts and records |
| `vector-*` | Local embedding model | An AI answer citing retrieved chapter excerpts |
| `sync-*` | Sync and database backup | Restored reading progress and annotation |
| `backup-*` | Global settings export | Export completion with the saved file location |

The opening `reading-*` banners and `vertical-zh` show reading layouts directly. Only the selected final assets are tracked; prompt drafts and discarded variants stay outside the published source tree.

Reading examples use the original demonstration books [《阅读，让思考慢下来》](../examples/modu-reading-demo.epub) and [The Quiet Reader](../examples/modu-reading-demo-en.epub), with additional original sample passages and dictionary definitions written for the artwork. Book source and redistribution terms are in [examples/README.md](../examples/README.md). Statistics, notes, retrieval excerpts and AI answers are illustrative demo data, not private account data or performance benchmarks. No private bookshelf, notes, AI conversation or credentials are included. Settings shown illustrate the features, not necessarily factory defaults.

## Source archive / 来源归档

The source images were removed from the current tracked tree on 2026-10-03 to avoid shipping unused, duplicate or upstream marketing material. They remain recoverable in [the previous Git revision](https://github.com/sobranie2406/modureader/tree/dae8ecc4ef7ac34cfe252f8039008716d5cee6ff/docs/images), and local working copies are ignored rather than deleted:

- `showcase/*.png`: the previous iPhone-only renders used to compose the current artwork.
- `v1.1.9/`: Android and Mac Modu 1.1.9+10063 captures from 2026-10-01, including the original demonstration books and settings screens.
- The seven older `*-macos.jpg` files: Modu 1.1.1+10033 captures from 2026-09-21, including the then-approved vertical-reading example.
- `Anx-logo.jpg`, `main.jpg`, `wide*.png`, `mobile*.png` and `zh/`: inherited Anx Reader marketing assets, not current Modu UI.

这些旧素材已撤出当前源码，但本地副本及 Git 历史仍保留，便于恢复或继续设计。不要将上游截图作为默读当前界面重新发布。各依赖的许可证、版权声明和来源文档不属于本次素材清理范围。
