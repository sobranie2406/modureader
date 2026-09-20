import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/material.dart';

LocalDictionaryStore? _store;
LocalDictionaryStore defaultDictionaryStore() {
  final root = getBasePath('dictionaries');
  if (_store?.root != root) _store = LocalDictionaryStore(root);
  return _store!;
}

String dictionaryLabel(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

String dictionaryError(BuildContext context, Object error) {
  final code = error is DictionaryFailure ? error.code : '';
  final (zh, en) = switch (code) {
    'name' => ('字典名称应为 1–80 个字符。', 'Use a name of 1–80 characters.'),
    'files' || 'companions' => (
        '每次导入一本字典：选择一个 MDX，或同时选择同名字典的 IFO、IDX（可为 IDX.GZ）、DICT（可为 DICT.DZ）及可选 SYN。也可选择包含这些文件的 ZIP。',
        'Import one MDX, or select the matching IFO, IDX/IDX.GZ, DICT/DICT.DZ and optional SYN together. A ZIP containing one dictionary also works.'
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
