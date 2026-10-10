import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/l10n/modu_strings.dart';

LocalDictionaryStore? _store;
LocalDictionaryStore defaultDictionaryStore() {
  final root = getBasePath('dictionaries');
  if (_store?.root != root) _store = LocalDictionaryStore(root);
  return _store!;
}

String dictionaryLabel(BuildContext context, String zh, String en) =>
    ModuStrings.text(context, zh, en);

// Keep every definition/example, but remove blank lines added by block tags.
String compactDictionaryText(String text) => text
    .replaceAll(RegExp(r'\r\n?'), '\n')
    .replaceAll(RegExp(r'\n[ \t]*(?:\n[ \t]*)+'), '\n')
    .trim();

String dictionaryError(BuildContext context, Object error) {
  final code = error is DictionaryFailure ? error.code : '';
  final (zh, en) = switch (code) {
    'name' => ('字典名称应为 1–80 个字符。', 'Use a name of 1–80 characters.'),
    'files' || 'companions' => (
        '每次导入一本字典：一个 MDX 及可选同名 MDD、图片、音频、CSS、JS；或同名字典的 IFO、IDX、DICT 及可选 SYN。也可使用单本字典 ZIP 保留资源目录。',
        'Import one MDX with optional matching MDD, images, audio, CSS and JS; or matching IFO, IDX, DICT and optional SYN. A ZIP can preserve resource directories.'
      ),
    'mdxSize' => (
        'MDX 暂支持不超过 256 MiB 的文件，请选择较小的字典。',
        'MDX files are currently limited to 256 MiB. Please choose a smaller dictionary.'
      ),
    'size' || 'zipSize' => (
        '字典超过导入大小限制，请选择较小的字典。',
        'Dictionary exceeds the import size limit. Please choose a smaller dictionary.'
      ),
    'empty' => ('字典没有可查询的词条。', 'Dictionary has no entries.'),
    'archive' => (
        '压缩包路径、压缩方式或校验无效，未导入。',
        'Unsafe, unsupported or damaged archive; nothing was imported.'
      ),
    'io' => (
        '无法读取文件或写入字典，请检查文件权限和可用空间。',
        'Cannot read or save dictionary. Check file permissions and free space.'
      ),
    _ => (
        '字典不完整、损坏或格式暂不支持。请核对配套文件；暂不支持 MDX 3、LZO 压缩及加密正文。已有字典未改变。',
        'Dictionary is incomplete, damaged or unsupported. Check companion files. MDX 3, LZO and encrypted records are unsupported. Existing dictionaries are unchanged.'
      ),
  };
  return dictionaryLabel(context, zh, en);
}
