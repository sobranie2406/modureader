import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loopback HTTP rejects raw file paths and cross-origin reads', () async {
    SharedPreferences.setMockInitialValues({'lastServerPort': 0});
    await Prefs().initPrefs();
    final directory = await Directory.systemTemp.createTemp('modu-http-test-');
    final book = await File('${directory.path}/fixture.pdf')
        .writeAsString('synthetic book bytes');
    final server = Server();
    await server.start();
    final client = HttpClient();
    Future<(int, String)> get(String url,
        {String? origin, String? host}) async {
      final request = await client.getUrl(Uri.parse(url));
      if (origin != null) request.headers.set('Origin', origin);
      if (host != null) request.headers.set('Host', host);
      final response = await request.close();
      expect(response.headers.value('access-control-allow-origin'), isNull);
      final bytes =
          await response.fold<List<int>>([], (all, part) => all..addAll(part));
      return (response.statusCode, String.fromCharCodes(bytes));
    }

    try {
      final url = server.bookUrl(book);
      expect(await get(url), (200, 'synthetic book bytes'));
      expect(
          (await get(
                  'http://127.0.0.1:${server.port}/book/${Uri.encodeComponent(book.path)}'))
              .$1,
          404);
      expect((await get(url, origin: 'https://example.com')).$1, 403);
      expect((await get(url, host: 'attacker.invalid:${server.port}')).$1, 403);
      expect(
          (await get(url, origin: 'http://127.0.0.1:${server.port}')).$1, 200);
      final route = server.setTempFile(book);
      server.releaseTempFile(route);
      expect((await get('http://127.0.0.1:${server.port}/$route')).$1, 404);
      expect((await get(url)).$1, 200);
    } finally {
      client.close(force: true);
      await server.stop();
      await directory.delete(recursive: true);
    }
  });
}
