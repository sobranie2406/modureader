import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:anx_reader/models/reader_progress.dart';
import 'package:anx_reader/models/reading_info.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const progress = ReaderProgress(
    currentChapter: 2,
    totalChapters: 3,
    currentPage: 9,
    totalPages: 15,
    chapters: [
      ReaderProgressChapter(number: 1, title: '开篇', start: 0, end: .1),
      ReaderProgressChapter(number: 2, title: '长章节', start: .1, end: .9),
      ReaderProgressChapter(number: 3, title: '结尾', start: .9, end: 1),
    ],
  );

  test('chapter index and chapter-page progress use independent counts', () {
    expect(progress.chapterProgress, '2/3');
    expect(progress.chapterPageProgress, '9/15');
    expect(const ReaderProgress().chapterPageProgress, '—');
    expect(
        const ReaderProgress(currentPage: 50, totalPages: 15)
            .chapterPageProgress,
        '15/15');
  });
  test('drag preview uses size-weighted boundaries and handles book ends', () {
    expect(progress.chapterAt(0)!.title, '开篇');
    expect(progress.chapterAt(.099)!.number, 1);
    expect(progress.chapterAt(.1)!.number, 2);
    expect(progress.chapterAt(.8)!.title, '长章节');
    expect(progress.chapterAt(.9)!.number, 3);
    expect(progress.chapterAt(1)!.number, 3);
    expect(progress.chapterAt(double.nan), isNull);
    expect(const ReaderProgress().chapterAt(.5), isNull);
  });
  test('shared boundaries skip empty/non-linear sections', () {
    final ranges = progress.copyWithChapters([
      progress.chapters[0],
      const ReaderProgressChapter(number: 2, title: '非正文', start: .1, end: .1),
      const ReaderProgressChapter(number: 3, title: '正文', start: .1, end: 1),
      const ReaderProgressChapter(number: 4, title: '封底', start: 1, end: 1),
    ]);
    expect(ranges.chapterAt(.1)!.title, '正文');
    expect(ranges.chapterAt(1)!.title, '正文');
  });
  test('old saved chapterProgress remains valid; new page option roundtrips',
      () {
    final old = ReadingInfoModel.fromJson({
      'footer': {'center': 'chapterProgress'}
    });
    expect(old.footer.center, ReadingInfoEnum.chapterProgress);
    final changed = old.copyWith(
        header:
            old.header.copyWith(right: ReadingInfoEnum.chapterPageProgress));
    final json = jsonDecode(jsonEncode(changed.toJson()));
    expect(ReadingInfoModel.fromJson(json).header.right,
        ReadingInfoEnum.chapterPageProgress);
    expect(json['header']['right'], 'chapterPageProgress');
  });
  test('both header/footer progress choices survive global settings export',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().readingInfo = const ReadingInfoModel(
        header: ReadingInfoSectionModel(right: ReadingInfoEnum.chapterProgress),
        footer: ReadingInfoSectionModel(
            center: ReadingInfoEnum.chapterPageProgress));
    final data = await GlobalSettingsTransfer.decode(
        GlobalSettingsTransfer.link(
            await GlobalSettingsTransfer.export(Prefs())));
    Prefs().readingInfo = const ReadingInfoModel();
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().readingInfo.header.right, ReadingInfoEnum.chapterProgress);
    expect(
        Prefs().readingInfo.footer.center, ReadingInfoEnum.chapterPageProgress);
  });
}
