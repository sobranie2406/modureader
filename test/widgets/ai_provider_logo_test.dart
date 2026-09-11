import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/provider_brand.dart';
import 'package:anx_reader/widgets/ai/ai_provider_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'official and generic icons render at 20/28/32px in $brightness',
        (tester) async {
      final providers = [
        for (final brand in ProviderBrand.values)
          AiProvider(
              id: 'custom-${brand.name}',
              title: brand.name,
              url: '',
              protocol: AiProtocol.openai),
        const AiProvider(
            id: 'unknown', title: '自定义', url: '', protocol: AiProtocol.openai),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
            body: Wrap(children: [
          for (final size in [20.0, 28.0, 32.0])
            for (final provider in providers)
              AiProviderLogo(provider: provider, size: size),
        ])),
      ));
      // Decode images outside the fake clock, just as an app loads its assets.
      await tester.runAsync(() async {
        for (final brand in ProviderBrand.values) {
          await precacheImage(
              AssetImage(brand.asset), tester.element(find.byType(Wrap)));
        }
      });
      await tester.pumpAndSettle();
      expect(
          find.byType(Image), findsNWidgets(ProviderBrand.values.length * 3));
      expect(find.byIcon(Icons.smart_toy_outlined), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editing a custom endpoint immediately updates its official icon',
      (tester) async {
    Future<void> show(String url) async {
      await tester.pumpWidget(MaterialApp(
          home: AiProviderLogo(
        provider: AiProvider(
            id: 'custom', title: '我的接口', url: url, protocol: AiProtocol.openai),
      )));
      await tester.pump();
    }

    await show('https://api.minimaxi.com/v1');
    expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        ProviderBrand.minimax.asset);
    await show('https://api.moonshot.cn/v1');
    expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        ProviderBrand.kimi.asset);
    await show('https://custom.example/v1');
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
  });
}
