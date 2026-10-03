import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/pdf_reading_state_store.dart';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const position = {'page': 2, 'panel': 3, 'signature': '[[0,0,0.5,0.5]]'};
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('first interaction preserves automatic document mode without an opening write', () async {
    final store = PdfReadingStateStore(await SharedPreferences.getInstance());
    expect(store.hasSavedMode('fresh'), isFalse);
    await store.saveView('fresh', const PdfReadingView(zoom: 2), enabled: true);
    expect(store.read('fresh')['enabled'], isTrue);
    await store.savePosition('fresh-position', 'cfi', null, enabled: true);
    expect(store.read('fresh-position')['enabled'], isTrue);
  });
  test(
      'legacy view defaults to single page; continuous preference persists per book',
      () async {
    expect(
        PdfReadingView.fromJson({'zoom': 2, 'fit': 'width', 'rotation': 0})
            .mode,
        'single');
    expect(
        () => PdfReadingView.fromJson(
            {'zoom': 1, 'fit': 'screen', 'rotation': 0, 'mode': 'invalid'}),
        throwsFormatException);
    final store = PdfReadingStateStore(await SharedPreferences.getInstance());
    await store.saveView('scroll-book', const PdfReadingView(mode: 'scroll'));
    expect(store.readView('scroll-book').mode, 'scroll');
    expect(store.readView('other-book').mode, 'single');
  });
  test('viewport preferences and normalized center survive independent writes',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PdfReadingStateStore(prefs);
    await store.setEnabled('a', true);
    await Future.wait([
      store.saveView(
          'a', const PdfReadingView(zoom: 15, fit: 'width', rotation: 270)),
      store.savePosition('a', 'cfi', {
        ...position,
        'center': {'x': .3, 'y': .7}
      }),
    ]);
    final reload = PdfReadingStateStore(prefs);
    expect(reload.readView('a').zoom, 15);
    expect(reload.readView('a').rotation, 270);
    expect(reload.read('a')['position']['center'], {'x': .3, 'y': .7});
    expect(reload.readView('missing').zoom, 1);
    for (final value in [-1, 2, double.nan]) {
      expect(
          () => store.savePosition('a', 'cfi', {
                ...position,
                'center': {'x': value, 'y': .5}
              }),
          throwsFormatException);
    }
    expect(() => store.saveView('a', const PdfReadingView(zoom: 16)),
        throwsFormatException);
  });
  test(
      'mode and source-page position survive reload and concurrent book writes',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PdfReadingStateStore(prefs);
    expect(store.read('a')['enabled'], false);
    await Future.wait(
        [store.setEnabled('a', true), store.setEnabled('b', true)]);
    await Future.wait([
      store.savePosition('a', 'epubcfi(/6/6)', position),
      store.setEnabled('b', false)
    ]);
    final reload = PdfReadingStateStore(prefs);
    expect(reload.read('a')['position'], position);
    expect(reload.read('a')['enabled'], true);
    expect(reload.read('b')['enabled'], false);
    await reload.setEnabled('a', false);
    expect(reload.read('a')['position'], null);
  });
  test(
      'invalid positions are rejected; corrupt collections cannot be overwritten',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PdfReadingStateStore(prefs);
    expect(() => store.savePosition('a', '', position), throwsFormatException);
    expect(() => store.savePosition('a', 'cfi', {...position, 'panel': 9}),
        throwsFormatException);
    await prefs.setString(PdfReadingStateStore.key, 'corrupt');
    expect(store.read('a')['enabled'], false);
    await expectLater(store.setEnabled('a', true), throwsFormatException);
    expect(prefs.getString(PdfReadingStateStore.key), 'corrupt');
  });
  test(
      'global import/export never transfers PDF device-local mode or positions',
      () async {
    await Prefs().initPrefs();
    final store = PdfReadingStateStore(Prefs().prefs);
    await store.setEnabled('a', true);
    expect(await Prefs().buildPrefsBackupMap(),
        isNot(contains(PdfReadingStateStore.key)));
    await Prefs().applyPrefsBackupMap({
      PdfReadingStateStore.key: {'type': 'string', 'value': '{}'}
    });
    expect(store.read('a')['enabled'], true);
  });
}
