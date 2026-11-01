import 'package:anx_reader/page/book_player/image_viewer.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pixel =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAK0lEQVR4nO3OIQEAAAwEoetfeovxBoGnq1tKQEBAQEBAQEBAQEBAQEBgHXhUDfhqRFDd3gAAAABJRU5ErkJggg==';

Future<void> ready(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  // Native image decoding needs the real event loop, outside the fake clock.
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  testWidgets('starts at sixth image and swipes to both neighbors',
      (tester) async {
    final loaded = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: ImageViewer(
      image: pixel,
      bookName: 'Test',
      loadIndex: () async => const ImageGalleryIndex(10, 5),
      loadImage: (index) async {
        loaded.add(index);
        return pixel;
      },
    )));
    await ready(tester);
    expect(find.text('6 / 10'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await ready(tester);
    expect(find.text('7 / 10'), findsOneWidget);
    expect(loaded, contains(6));
    await tester.drag(find.byType(PageView), const Offset(700, 0));
    await ready(tester);
    await tester.drag(find.byType(PageView), const Offset(700, 0));
    await ready(tester);
    expect(find.text('5 / 10'), findsOneWidget);
    expect(loaded, contains(4));
    expect(find.byIcon(Icons.share), findsWidgets);
    expect(find.byIcon(Icons.download), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed index leaves the clicked image and close control usable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ImageViewer(
      image: pixel,
      bookName: 'Test',
      loadIndex: () async => throw StateError('index failed'),
    )));
    await ready(tester);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.share), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
