import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationCachePath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _StreamingChat extends AiChat {
  final streams = <StreamController<List<ChatMessage>>>[];
  bool regenerating = false;

  @override
  Stream<List<ChatMessage>> sendMessageStream(
    String message,
    WidgetRef widgetRef,
    bool isRegenerate, {
    String? skillId,
    String? sourceText,
    String? sourceContext,
    bool selectionRequest = false,
    bool webSearch = false,
    String? homePromptId,
    CancelableLangchainRunner? requestRunner,
  }) {
    regenerating = isRegenerate;
    final controller = StreamController<List<ChatMessage>>();
    streams.add(controller);
    return controller.stream;
  }

  void emit(String answer, {bool thinking = true}) {
    final messages = [
      ChatMessage.humanText('旧问题'),
      ChatMessage.ai('旧回答\n\n${'历史内容。\n\n' * 20}'),
      ChatMessage.humanText('新问题'),
      ChatMessage.ai(thinking ? '<think>内部思考过程。</think>$answer' : answer),
    ];
    state = AsyncData(messages);
    streams.last.add(messages);
  }
}

void main() {
  const firstParagraph = '# 本次回答第一段';
  final longAnswer = '$firstParagraph\n\n${'正文内容，需要从第一段开始阅读。\n\n' * 80}';

  Future<_StreamingChat> mount(WidgetTester tester, AiChatScope scope,
      {Size size = const Size(390, 800)}) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final directory = Directory.systemTemp.createTempSync('modu-ai-scroll-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
      directory.deleteSync(recursive: true);
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = _StreamingChat();
    await tester.pumpWidget(ProviderScope(
      overrides: [aiChatProvider(scope).overrideWith(() => chat)],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AiChatStream(scope: scope),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新问题');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    return chat;
  }

  Finder answer() => find.byWidgetPredicate((widget) =>
      widget is StyledMarkdown && widget.data.startsWith(firstParagraph));
  ScrollPosition position(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!.position;

  for (final scope in AiChatScope.values) {
    testWidgets('${scope.name} landscape keyboard keeps draft and send visible',
        (tester) async {
      final chat = await mount(tester, scope);
      chat.emit('A complete response.', thinking: false);
      await chat.streams.last.close();
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('ai-message-input'));
      await tester.enterText(editor, 'Unsent keyboard draft');
      final fieldBefore = tester.state(editor);
      tester.view.physicalSize = const Size(800, 400);
      tester.view.viewInsets = const FakeViewPadding(bottom: 270);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.state(editor), same(fieldBefore));
      expect(tester.widget<TextField>(editor).controller!.text,
          'Unsent keyboard draft');
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
      final send = find.byKey(const ValueKey('ai-send-message'));
      expect(tester.getBottomRight(send).dy, lessThanOrEqualTo(130));
      expect(tester.getTopLeft(editor).dy, greaterThanOrEqualTo(0));
      expect(find.byIcon(Icons.keyboard_hide), findsOneWidget);

      tester.view.viewInsets = FakeViewPadding.zero;
      tester.view.physicalSize = const Size(390, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.state(editor), same(fieldBefore));
      expect(tester.widget<TextField>(editor).controller!.text,
          'Unsent keyboard draft');
      expect(find.byIcon(Icons.keyboard_hide), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final scope in AiChatScope.values) {
    testWidgets(
        '${scope.name} reply completion returns to the first answer paragraph',
        (tester) async {
      final chat = await mount(tester, scope);
      chat.emit(longAnswer);
      await tester.pumpAndSettle();
      expect(position(tester).extentAfter, 0);
      final atBottom = position(tester).pixels;
      await chat.streams.last.close();
      await tester.pumpAndSettle();
      expect(position(tester).pixels, lessThan(atBottom));
      expect(position(tester).pixels, greaterThan(0),
          reason: 'old conversation is above the current answer');
      expect(tester.getTopLeft(answer()).dy,
          closeTo(tester.getTopLeft(find.byType(ListView)).dy, 1));
      expect(find.byIcon(Icons.stop), findsNothing);
      final finalOffset = position(tester).pixels;
      await tester.pump();
      expect(position(tester).pixels, finalOffset);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'a reply completed before its first frame still reveals its start',
      (tester) async {
    final chat = await mount(tester, AiChatScope.reader);
    chat.emit(longAnswer);
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(answer()).dy,
        closeTo(tester.getTopLeft(find.byType(ListView)).dy, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('short replies on desktop stay entirely visible on completion',
      (tester) async {
    final chat =
        await mount(tester, AiChatScope.library, size: const Size(1100, 760));
    chat.emit('$firstParagraph\n\n简短的词语解释。', thinking: false);
    await tester.pumpAndSettle();
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(ListView));
    final reply = tester.getRect(answer());
    expect(reply.top, greaterThanOrEqualTo(bounds.top));
    expect(reply.bottom, lessThanOrEqualTo(bounds.bottom));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'completion in the final token frame keeps all six trailing CJK characters',
      (tester) async {
    final chat = await mount(tester, AiChatScope.reader);
    final prefix = '$firstParagraph\n\n${'词语释义和相关知识。\n\n' * 80}后来泛指所有';
    const tail = '房屋或房间。';
    chat.emit(prefix);
    await tester.pumpAndSettle();
    chat.emit('$prefix$tail');
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    expect(tester.widget<StyledMarkdown>(answer()).data, '$prefix$tail');
    final text = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join();
    expect(text, contains('后来泛指所有$tail'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('regeneration returns to the new answer once, not an old answer',
      (tester) async {
    final chat = await mount(tester, AiChatScope.library);
    chat.emit(longAnswer);
    await tester.pumpAndSettle();
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重新生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新生成'));
    await tester.pump();
    expect(chat.regenerating, isTrue);
    chat.emit('$firstParagraph\n\n新的回答。\n\n${'新的段落。\n\n' * 100}');
    await tester.pumpAndSettle();
    expect(position(tester).extentAfter, 0);
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(answer()).dy,
        closeTo(tester.getTopLeft(find.byType(ListView)).dy, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stopping generation does not trigger a completion jump',
      (tester) async {
    final chat = await mount(tester, AiChatScope.reader);
    chat.emit(longAnswer);
    await tester.pumpAndSettle();
    final offset = position(tester).pixels;
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    unawaited(chat.streams.last.close());
    await tester.pumpAndSettle();
    expect(position(tester).pixels, offset);
    expect(find.byIcon(Icons.stop), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'manual scrolling during generation is not overridden on completion',
      (tester) async {
    final chat = await mount(tester, AiChatScope.reader);
    chat.emit(longAnswer);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    final offset = position(tester).pixels;
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    expect(position(tester).pixels, offset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'errors show the retry message instead of jumping to stale output',
      (tester) async {
    final chat = await mount(tester, AiChatScope.reader);
    chat.emit(longAnswer);
    await tester.pumpAndSettle();
    chat.streams.last.addError(StateError('请求失败，请重试'));
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-request-error')), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '新问题');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
