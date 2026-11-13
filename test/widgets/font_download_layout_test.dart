import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/settings_page/subpage/fonts.dart';
import 'package:modu_reader/providers/fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fonts extends Fonts {
  _Fonts({this.atkinson = false});
  final bool atkinson;
  @override
  Future<List<RemoteFontModel>> build() async => [
        RemoteFontModel(
          id: 'test',
          name: atkinson ? 'Atkinson Hyperlegible Next' : 'Another font',
          files: ['font.ttf'],
          size: 100,
          preview: 'test-preview.png',
          desc: 'A font description that can wrap on smaller screens.',
          official: 'https://example.com',
          license: LicenseModel(
              name: 'SIL Open Font License 1.1',
              url: 'https://example.com/license'),
        ),
      ];
}

class _Downloads extends FontDownloads {
  _Downloads(this.status);
  final DownloadStatus status;
  @override
  Map<String, FontDownloadState> build() => {
        'test': FontDownloadState(
            fontId: 'test',
            filePath: 'font.ttf',
            status: status,
            progress: 0.5),
      };
  @override
  bool isDownloaded(String fontId, String filePath) => false;
}

void main() {
  setUpAll(() async {
    await L10n.delegate.load(const Locale('en'));
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1920, 1200)
  ]) {
    for (final status in [
      DownloadStatus.none,
      DownloadStatus.downloading,
      DownloadStatus.paused
    ]) {
      testWidgets('font cards fit $size and $status with large text',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(overrides: [
          fontsProvider.overrideWith(_Fonts.new),
          fontDownloadsProvider.overrideWith(() => _Downloads(status)),
        ]);
        addTearDown(container.dispose);
        await container.read(fontsProvider.future);
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: const Locale('en'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.8)),
                  child: child!),
              home: const FontsSettingPage(),
            )));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final list = tester.getRect(find.byType(ListView));
        expect(list.width, lessThanOrEqualTo(840));
        expect(list.center.dx, closeTo(size.width / 2, 1));
        final preview =
            tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
        expect(preview.height, lessThanOrEqualTo(140));
        expect(preview.width, lessThanOrEqualTo(480));
        expect(preview.width, lessThanOrEqualTo(list.width));
        expect(preview.fit, BoxFit.contain);
        await tester.drag(find.byType(ListView), const Offset(0, -1200));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [320.0, 1200.0]) {
    testWidgets(
        'Atkinson shows real Latin specimen without broken image at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [
        fontsProvider.overrideWith(() => _Fonts(atkinson: true)),
        fontDownloadsProvider
            .overrideWith(() => _Downloads(DownloadStatus.none)),
      ]);
      addTearDown(container.dispose);
      await container.read(fontsProvider.future);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: const FontsSettingPage(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsNothing);
      final specimen = find.text('ABCDEFGHIJK abcdefghijk\n0123456789');
      expect(
          tester.widget<Text>(specimen).style!.fontFamily, 'AtkinsonPreview');
      expect(tester.getSize(specimen).width, lessThan(width));
      expect(find.text('Atkinson Hyperlegible Next'), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
