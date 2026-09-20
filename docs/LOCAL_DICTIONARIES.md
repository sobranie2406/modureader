# 本地自定义字典 / Local dictionaries

## 使用方法

1. 打开「设置 → 自定义字典 → 导入字典」。应用不内嵌词典数据，请仅导入有权使用的文件。
2. 每次导入一本字典，填写自定义名称。可同时保留多本，在设置中改名、启用/停用或删除。
3. 阅读时选中文字，在选中菜单点「字典」。窗口显示所有已启用字典的完全匹配释义，忽略词首尾空格和大小写；可以修改查询词。未匹配时不会自动联网翻译。
4. 查询不改变阅读位置；关闭窗口后恢复阅读器焦点。

同一字典每次查询最多返回 20 条同名词目；重定向查找最多访问 8 个目标，避免恶意或循环跳转阻塞查询。

## 格式范围

| 格式 | 导入方式与限制 |
| --- | --- |
| MDX | 1.x / 2.x，未压缩或 zlib；支持 UTF-8、UTF-16，其他编码由解析库提供，尚未逐个验证。支持 `@@@LINK=` 跳转词条并防止循环。单文件上限 256 MiB。 |
| StarDict | 2.4.2 / 3.0.0；一次选择同名 `.ifo`、`.idx` / `.idx.gz`、`.dict` / `.dict.dz`，以及可选 `.syn`。支持 32/64 位偏移、同义词、多字段文字释义。 |
| ZIP | 内含单本上述字典，可有子目录。支持 Store/Deflate；不支持加密 ZIP，拒绝越界路径、符号链接和重名配套文件。逐块解压并检查实际大小及 CRC。 |

仅呈现文字释义。HTML/XML 定义转换为文本并保留段落分隔，不执行 JavaScript、不加载网页、外部 CSS、图片或音频。
MDD 多媒体、DSL、MDX 3、LZO 压缩及加密正文暂不支持，不保证所有商业 MDX 都可导入。
StarDict 的音频/图片字段和资源引用不展示；仅有媒体的词条会提示没有文字释义。
MDX 解析依赖目前不校验其内部 checksum，因此成功导入不代表经过出版方完整性认证。

## 存储与可靠性

- 字典解析、压缩文件展开和 SQLite 索引建立在独立 Dart isolate 中执行，不在 Flutter UI 线程中运行。
- 将词目、标准化查询键和文字释义保存为独立的本地 SQLite 文件；查询不需要重新加载原始词典，也不依赖原文件路径。
- 数据目录为应用存储下的 `dictionaries/`，不加入书籍数据库、设置备份或 WebDAV 同步清单。
- 字典名称只作为数据库字段保存，不作为文件路径。删除只删除应用内的导入结果，不删除原始字典。
- 导入先在 `.import-*` 临时目录构建，验证完成后原子发布；异常回滚并清理临时目录，保留现有字典。强制结束进程可能留下临时目录，但不会将半成品作为可用字典。
- StarDict 验证配套文件、词条数、索引长度、记录偏移、同义词目标和字段边界。
- 单条释义上限 2 MiB，StarDict 索引上限 64 MiB，字典正文/导入释义总量上限 2 GiB、词条上限 200 万。ZIP 压缩文件上限 512 MiB，解压的字典文件总量上限 2 GiB。需要额外临时磁盘空间。
- 失败提示只给错误类别，不显示原始词典正文、文件路径或解析器异常内容。

## 验证

自动测试使用自主生成的小型词典，不内嵌或再分发商业词典。覆盖 MDX 1/2、UTF-8/UTF-16、zlib、跳转循环，StarDict 文本/压缩/64 位偏移/同义词，ZIP、错误导入回滚、路径校验、启停/改名/删除与移动/桌面查询窗口。

尚未用用户提供的实际大体积字典或移动设备完成导入兼容性验证。测试通过不等同于所有格式变种或全部设备均验证通过。

## English overview

Use **Settings → Custom dictionaries** to import, rename, enable or remove local dictionaries. Select text in the reader and choose **Dictionary** for offline exact-word lookup across enabled dictionaries. No dictionary data is bundled or uploaded/synchronized.

Supported text dictionaries: MDX 1/2 (uncompressed/zlib, up to 256 MiB), StarDict 2.4.2/3.0.0 with matching IFO, IDX/IDX.GZ, DICT/DICT.DZ and optional SYN, or one dictionary packaged in ZIP. HTML definitions are converted to safe text. MDD media, DSL, MDX 3, LZO and encrypted record blocks are not supported. Actual large dictionaries and mobile-device imports still require compatibility testing.

## 实现来源

- MDX: [dict_reader](https://github.com/mumu-lhl/dict_reader), pinned to 1.6.1 (MIT); transitive cryptography utilities only serve format decoding, not any blockchain/network service. Flutter includes dependency licenses in its license registry.
- StarDict: implemented against the [official file-format specification](https://github.com/huzheng001/stardict-3/blob/master/dict/doc/StarDictFileFormat).
- Archive decoding uses the existing `archive` dependency; local databases use the existing native SQLite runtime.
