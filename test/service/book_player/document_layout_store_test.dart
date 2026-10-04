import 'dart:ui';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:anx_reader/service/book_player/document_layout_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const cropped = DocumentPageLayout(
    crop: Rect.fromLTWH(.1, .2, .8, .6), preset: 'four', order: 'column-rtl');

class FailingPrefs implements SharedPreferences {
  String? value;
  bool fail = false;
  @override
  String? getString(String key) => value;
  @override
  Future<bool> setString(String key, String data) async {
    value = data;
    if (fail) {
      fail = false;
      return false;
    }
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    value = null;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'automatic mode and margin persist per scope; legacy layouts stay manual',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = DocumentLayoutStore(await SharedPreferences.getInstance());
    final config = DocumentLayoutConfig(
        all: cropped.copyWith(autoCrop: true, autoMargin: .05),
        pages: {2: cropped});
    await store.save('auto', config);
    final restored = store.read('auto');
    expect(restored.forPage(0).autoCrop, true);
    expect(restored.forPage(1).autoMargin, .05);
    expect(restored.forPage(2).autoCrop, false);
    expect(DocumentPageLayout.fromJson(cropped.toJson()).autoCrop, false);
    for (final invalid in [
      {'autoCrop': 1},
      {'autoMargin': '3'},
      {'autoMargin': .3},
      {'autoMargin': double.nan}
    ]) {
      expect(
          () => DocumentPageLayout.fromJson({...cropped.toJson(), ...invalid}),
          throwsFormatException);
    }
  });
  test('seven grids tile the crop; row/column and RTL orders match JS contract',
      () {
    for (final grid in DocumentPageLayout.grids.entries) {
      final regions = cropped.copyWith(preset: grid.key).regions;
      expect(regions.length, grid.value.$1 * grid.value.$2);
      expect(regions.fold<double>(0, (sum, r) => sum + r.width * r.height),
          closeTo(.48, 1e-9));
      for (final region in regions) {
        expect(region.left, greaterThanOrEqualTo(.1));
        expect(region.bottom, lessThanOrEqualTo(.8 + 1e-9));
      }
    }
    List<String> order(String value) => const DocumentPageLayout(preset: 'four')
        .copyWith(order: value)
        .regions
        .map((r) => '${(r.top * 2).round()}${(r.left * 2).round()}')
        .toList();
    expect(order('row-ltr'), ['00', '01', '10', '11']);
    expect(order('row-rtl'), ['01', '00', '11', '10']);
    expect(order('column-ltr'), ['00', '10', '01', '11']);
    expect(order('column-rtl'), ['01', '11', '00', '10']);
  });
  test(
      'rotation is reversible and config serialization rejects corrupt geometry',
      () {
    for (final rotation in [0, 90, 180, 270]) {
      final restored = rotateDocumentRegion(
          rotateDocumentRegion(cropped.crop, rotation), -rotation);
      expect(restored.left, closeTo(cropped.crop.left, 1e-9));
      expect(restored.top, closeTo(cropped.crop.top, 1e-9));
      expect(restored.width, closeTo(cropped.crop.width, 1e-9));
    }
    expect(DocumentPageLayout.fromJson(cropped.toJson()).toJson(),
        cropped.toJson());
    expect(
        () => DocumentPageLayout.fromJson({
              'crop': {'x': 0, 'y': 0, 'width': 0, 'height': 1},
              'preset': 'single',
              'order': 'row-ltr'
            }),
        throwsFormatException);
    expect(() => DocumentLayoutConfig.fromJson({'version': 2, 'pages': {}}),
        throwsFormatException);
    expect(() => const DocumentPageLayout(preset: 'bad').regions,
        throwsFormatException);
  });
  test(
      'odd/even use visible page numbers, scopes replace only relevant overrides',
      () {
    const single = DocumentPageLayout(),
        two = DocumentPageLayout(preset: 'horizontal2');
    var config = const DocumentLayoutConfig(
        all: single, odd: cropped, even: two, pages: {0: single, 1: cropped});
    expect(config.forPage(0).preset, 'single');
    expect(config.forPage(2).preset, 'four');
    expect(config.forPage(3).preset, 'horizontal2');
    config = config.apply(DocumentLayoutScope.odd, 0, two);
    expect(config.pages.containsKey(0), false);
    expect(config.forPage(0).preset, 'horizontal2');
    expect(config.forPage(1).preset, 'four');
    config = config.apply(DocumentLayoutScope.all, 0, single);
    expect(config.pages, isEmpty);
    expect(config.odd, null);
    expect(config.even, null);
    expect(config.forPage(1).preset, 'single');
  });
  test(
      'two books and concurrent saves survive reload; one page can restore original',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final a = DocumentLayoutStore(prefs), b = DocumentLayoutStore(prefs);
    final config = const DocumentLayoutConfig(all: cropped)
        .apply(DocumentLayoutScope.current, 3, const DocumentPageLayout());
    await Future.wait([
      a.save('a', config),
      b.save('b', const DocumentLayoutConfig(odd: cropped))
    ]);
    await prefs.reload();
    expect(a.read('a').forPage(2).preset, 'four');
    expect(a.read('a').forPage(3).preset, 'single');
    expect(b.read('b').forPage(0).preset, 'four');
    expect(b.read('b').forPage(1).preset, 'single');
  });
  test(
      'failed platform write rolls back local cache and does not poison next save',
      () async {
    final prefs = FailingPrefs(), store = DocumentLayoutStore(FailingPrefs());
    final target = DocumentLayoutStore(prefs);
    await target.save('a', const DocumentLayoutConfig(all: cropped));
    final previous = prefs.value;
    prefs.fail = true;
    await expectLater(
        target.save('a', const DocumentLayoutConfig()), throwsStateError);
    expect(prefs.value, previous);
    expect(target.read('a').forPage(0).preset, 'four');
    await target.save('a', const DocumentLayoutConfig());
    expect(target.read('a').forPage(0).preset, 'single');
    expect(() => store.save('', const DocumentLayoutConfig()),
        throwsArgumentError);
  });
  test(
      'invalid stored JSON falls back for reading but is not erased by a write',
      () async {
    SharedPreferences.setMockInitialValues({DocumentLayoutStore.key: '{bad'});
    final prefs = await SharedPreferences.getInstance(),
        store = DocumentLayoutStore(await SharedPreferences.getInstance());
    expect(store.read('a').forPage(0).preset, 'single');
    await expectLater(
        store.save('a', const DocumentLayoutConfig()), throwsFormatException);
    expect(prefs.getString(DocumentLayoutStore.key), '{bad');
  });
  test('global preferences neither export nor overwrite local document layouts',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final store = DocumentLayoutStore(Prefs().prefs);
    await store.save('a', const DocumentLayoutConfig(all: cropped));
    expect(await Prefs().buildPrefsBackupMap(),
        isNot(contains(DocumentLayoutStore.key)));
    await Prefs().applyPrefsBackupMap({
      DocumentLayoutStore.key: {'type': 'string', 'value': '{}'}
    });
    expect(store.read('a').forPage(0).preset, 'four');
  });
}
