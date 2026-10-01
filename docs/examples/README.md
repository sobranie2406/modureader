# 原创截图示例书 / Original demo books

以下两本书专为默读的公开文档创作，不是私人藏书，也不是应用中模型实际生成的回答。文字和 EPUB 随项目按 GPL-3.0-or-later 提供；完整原文保留在生成脚本中，可以随项目公开分发。

| 语言 | 示例书 | 内容 |
| --- | --- | --- |
| 中文 | [《阅读，让思考慢下来》](modu-reading-demo.epub) | 六章、50 段，约 3,400 汉字；阅读、AI 阅读伙伴、笔记、提问、知识联系与重读 |
| English | [The Quiet Reader](modu-reading-demo-en.epub) | Six chapters and 46 paragraphs, approximately 2,200 words; originally written in English |

两本 EPUB 都有可跳转的六章目录，适合展示翻页、章节导航、连续阅读、划词工具和设置界面。中文书可用于带边框的竖排展示；英文书用于英文界面和横排阅读展示。

These original books contain no private material or excerpts from third-party books. Their full text and reproducible EPUB sources are distributed with the project under GPL-3.0-or-later. The English book is not a machine translation of the Chinese book.

## 重新生成 / Rebuild

在仓库根目录运行，仅需 Python 标准库：

```sh
python3 docs/examples/make_screenshot_book.py
python3 docs/examples/make_english_screenshot_book.py
```

The scripts generate the EPUBs beside their source files. Both include an EPUB 3 manifest, spine and navigation document, with the uncompressed `mimetype` entry first in the archive.

实际界面截图的版本、设备与来源见[截图说明](../images/README.md)。
