import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/service/remote_library/baidu_auth.dart';
import 'package:anx_reader/widgets/baidu_library_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends BaiduAuth {
  late final result = Completer<bool>();
  int claims = 0;
  @override
  Future<bool> restore() async => false;
  @override
  Future<({String ticket, Uri url})> start(String proof, CancelToken cancel,
          {bool mobile = false}) async =>
      (
        ticket: 'ticket',
        url: Uri.parse('https://openapi.baidu.com/oauth/2.0/authorize')
      );
  @override
  Future<bool> claim(String ticket, String proof, CancelToken cancel) {
    claims++;
    return Future.any([result.future, cancel.whenCancel.then((_) => false)]);
  }
}

class _Browser extends PlatformChromeSafariBrowser {
  _Browser()
      : super.implementation(PlatformChromeSafariBrowserCreationParams());
  int closes = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> open(
      {WebUri? url,
      Map<String, String>? headers,
      List<WebUri>? otherLikelyURLs,
      WebUri? referrer,
      // Required by the plugin's current method signature.
      // ignore: deprecated_member_use
      ChromeSafariBrowserClassOptions? options,
      ChromeSafariBrowserSettings? settings}) async {
    // Android pauses Flutter while the system browser page covers the activity.
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  @override
  Future<void> close() async {
    closes++;
    dismiss();
  }

  void dismiss() {
    eventHandler?.onClosed();
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

class _Platform extends InAppWebViewPlatform {
  final browser = _Browser();
  @override
  PlatformChromeSafariBrowser createPlatformChromeSafariBrowser(
          PlatformChromeSafariBrowserCreationParams params) =>
      browser;
  @override
  PlatformChromeSafariBrowser createPlatformChromeSafariBrowserStatic() =>
      browser;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  late _Auth auth;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs().prefs = await SharedPreferences.getInstance();
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    auth = _Auth();
  });
  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  Future<void> login(WidgetTester tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: BaiduLibrarySettings(auth: auth))));
    await tester.pump();
    await tester.tap(find.text('Sign in to Baidu'));
    await tester.pump();
    expect(auth.claims, 1);
    expect(platform.browser.closes, 0);
  }

  testWidgets('verified claim closes browser even while Flutter is paused',
      (tester) async {
    await login(tester);
    auth.result.complete(true);
    await tester.pump();
    await tester.pump();
    expect(platform.browser.closes, 1);
    expect(find.text('Connected. Select Baidu Netdisk in Remote.'),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
  testWidgets('manual dismissal without authorization never shows connected',
      (tester) async {
    await login(tester);
    platform.browser.dismiss();
    auth.result.complete(false);
    await tester.pump();
    expect(platform.browser.closes, 0);
    expect(find.text('Sign in to Baidu'), findsOneWidget);
    expect(
        find.text('Connected. Select Baidu Netdisk in Remote.'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
  testWidgets('leaving settings cancels pending claim and closes its browser',
      (tester) async {
    await login(tester);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(platform.browser.closes, 1);
    await tester.pump(const Duration(seconds: 5));
  });
}
