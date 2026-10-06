import 'dart:io';
import 'dart:convert';

import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:anx_reader/service/sync/webdav_request_policy.dart';
import 'package:anx_reader/service/sync/sync_feedback.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Response<dynamic> busy(int status, {String? retryAfter}) => Response<dynamic>(
    requestOptions: RequestOptions(path: '/test'),
    statusCode: status,
    headers: Headers.fromMap({
      if (retryAfter != null) 'retry-after': [retryAfter]
    }));

void main() {
  test('recognition uses the hostname, never a path or lookalike', () {
    for (final url in [
      'https://dav.jianguoyun.com/dav/',
      'https://DAV.JIANGUOYUN.COM.:443/dav'
    ]) {
      expect(isJianguoyunWebdav(url), isTrue);
    }
    for (final url in [
      'https://jianguoyun.com.example.com',
      'https://notjianguoyun.com',
      'https://example.com/jianguoyun.com',
      'https://jianguoyun.com@example.com',
      'invalid'
    ]) {
      expect(isJianguoyunWebdav(url), isFalse);
    }
  });

  test('only Jianguoyun has a ten-minute automatic interval', () {
    var now = DateTime.utc(2026);
    final limited = WebdavRequestPolicy(jianguoyun: true, now: () => now);
    final normal = WebdavRequestPolicy(jianguoyun: false, now: () => now);
    expect(limited.automaticDelay, const Duration(seconds: 2));
    limited.syncStarted();
    normal.syncStarted();
    now = now.add(const Duration(minutes: 1));
    expect(limited.automaticDelay, const Duration(minutes: 9));
    expect(normal.automaticDelay, const Duration(seconds: 2));
    now = now.add(const Duration(minutes: 9));
    expect(limited.automaticDelay, const Duration(seconds: 2));
  });

  test('account state is shared across clients and folders, not users', () {
    final first = WebdavRequestPolicy.forAccount(
        'https://dav.jianguoyun.com/dav/a', 'alice');
    expect(
        identical(
            first,
            WebdavRequestPolicy.forAccount(
                'https://dav.jianguoyun.com/dav/b', 'alice')),
        isTrue);
    expect(
        identical(
            first,
            WebdavRequestPolicy.forAccount(
                'https://dav.jianguoyun.com/dav/a', 'bob')),
        isFalse);
  });

  test('Jianguoyun repeated busy bursts back off to thirty minutes', () {
    var now = DateTime.utc(2026);
    final policy = WebdavRequestPolicy(jianguoyun: true, now: () => now);
    for (final minutes in [5, 10, 20, 30, 30]) {
      policy.observe(busy(503));
      expect(policy.cooldown, Duration(minutes: minutes));
      // Neither a manual request nor a successful in-flight response may
      // bypass a server cooldown established by another operation.
      policy.observe(busy(200));
      expect(policy.rejectWhileCooling(RequestOptions(method: 'PUT')),
          isA<DioException>());
      expect(policy.automaticDelay, Duration(minutes: minutes));
      now = now.add(Duration(minutes: minutes));
    }
  });

  test('ten-minute automatic interval is a scheduling gate, not an HTTP quota',
      () {
    var now = DateTime.utc(2026);
    final policy = WebdavRequestPolicy(jianguoyun: true, now: () => now);
    policy.syncStarted();
    now = now.add(const Duration(seconds: 1));
    expect(policy.automaticDelay, const Duration(minutes: 9, seconds: 59));
    expect(policy.rejectWhileCooling(RequestOptions(method: 'GET')), isNull);
    // A bare in-memory test policy has no restart persistence. The application
    // supplies device-local storage; that path is covered separately below.
    final restarted = WebdavRequestPolicy(jianguoyun: true, now: () => now);
    expect(restarted.automaticDelay, const Duration(seconds: 2));
  });

  test('rolling budget is reserved atomically and survives restart', () async {
    final temp = await Directory.systemTemp.createTemp('modu-policy-test-');
    var now = DateTime.utc(2026);
    final file = File('${temp.path}/state.json');
    WebdavRequestPolicy policy() => WebdavRequestPolicy(
        jianguoyun: true,
        now: () => now,
        requestLimit: 3,
        stateFile: () async => file);
    try {
      final first = policy();
      await first.prepare();
      first.syncStarted();
      final results = await Future.wait(List.generate(
          8, (_) => first.beforeRequest(RequestOptions(method: 'PUT'))));
      expect(results.where((error) => error == null).length, 3);
      expect(
          results
              .whereType<DioException>()
              .every((error) => error.error is WebdavRequestBudgetExceeded),
          isTrue);
      final restored = policy();
      await restored.prepare();
      expect(restored.automaticDelay, const Duration(minutes: 30));
      expect((await restored.beforeRequest(RequestOptions()))?.error,
          isA<WebdavRequestBudgetExceeded>());
      expect(
          syncFailureMessage(results.last!, chinese: true), contains('请求预算'));
      now = now.add(const Duration(minutes: 30));
      expect(await restored.beforeRequest(RequestOptions()), isNull);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
      'server cooldown and automatic interval persist; ordinary DAV has no quota',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-policy-test-');
    var now = DateTime.utc(2026);
    try {
      for (final limited in [false, true]) {
        final file = File('${temp.path}/$limited.json');
        WebdavRequestPolicy policy() => WebdavRequestPolicy(
            jianguoyun: limited,
            now: () => now,
            requestLimit: 2,
            stateFile: () async => file);
        final first = policy();
        await first.prepare();
        first.syncStarted();
        first.observe(busy(503, retryAfter: '1800'));
        await first.persist();
        now = now.add(const Duration(minutes: 1));
        final restored = policy();
        await restored.prepare();
        expect(restored.cooldown, const Duration(minutes: 29));
        expect(restored.rejectWhileCooling(RequestOptions())?.error,
            isA<WebdavCoolingDown>());
        now = now.add(const Duration(minutes: 29));
        for (var i = 0; i < 4; i++) {
          final result = await restored.beforeRequest(RequestOptions());
          expect(result == null, !limited || i < 2);
        }
        expect((jsonDecode(await file.readAsString()) as Map).keys,
            isNot(contains('username')));
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
      'invalid persisted budget fails conservatively instead of granting a new allowance',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-policy-test-');
    try {
      final file = File('${temp.path}/state.json');
      await file.writeAsString('{broken');
      final policy =
          WebdavRequestPolicy(jianguoyun: true, stateFile: () async => file);
      await policy.prepare();
      expect(policy.cooldown.inMinutes, greaterThanOrEqualTo(29));
      expect(await policy.beforeRequest(RequestOptions()), isA<DioException>());
    } finally {
      await temp.delete(recursive: true);
    }
  });

  for (final status in [429, 503]) {
    test('$status honors seconds and HTTP-date hints, suppresses all methods',
        () {
      var now = DateTime.utc(2026);
      final policy = WebdavRequestPolicy(jianguoyun: true, now: () => now);
      policy.observe(busy(status, retryAfter: '1800'));
      expect(policy.cooldown, const Duration(minutes: 30));
      for (final method in ['GET', 'PROPFIND', 'PUT', 'DELETE', 'OPTIONS']) {
        final error = policy.rejectWhileCooling(RequestOptions(method: method));
        expect(error?.error, isA<WebdavCoolingDown>());
        expect(error?.response?.statusCode, status);
        expect(syncFailureMessage(error!, chinese: true), contains('30 分钟'));
      }
      now = now.add(const Duration(minutes: 30));
      expect(policy.rejectWhileCooling(RequestOptions()), isNull);
      policy.observe(busy(status,
          retryAfter: HttpDate.format(now.add(const Duration(hours: 1)))));
      expect(policy.cooldown, const Duration(hours: 1));
    });
  }

  test('fallback backs off without treating 503 as permanent incompatibility',
      () {
    var now = DateTime.utc(2026);
    final policy = WebdavRequestPolicy(jianguoyun: false, now: () => now);
    policy.observe(busy(503, retryAfter: 'invalid'));
    expect(policy.cooldown, const Duration(minutes: 1));
    policy.observe(busy(503)); // Concurrent failures do not double backoff.
    expect(policy.cooldown, const Duration(minutes: 1));
    now = now.add(const Duration(minutes: 1));
    policy.observe(busy(503));
    expect(policy.cooldown, const Duration(minutes: 2));
    policy.observe(busy(200));
    expect(policy.cooldown, const Duration(minutes: 2));
    now = now.add(const Duration(hours: 1));
    policy.observe(busy(429));
    expect(policy.cooldown, const Duration(minutes: 1));
  });

  test('real WebDAV transport blocks repeat requests across client instances',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    server.listen((request) async {
      calls++;
      request.response.statusCode = 503;
      request.response.headers.set('retry-after', '1800');
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/dav';
    try {
      final one = WebdavClient(url: url, username: 'a', password: 'test');
      final two =
          WebdavClient(url: url, username: 'a', password: 'other-app-password');
      await expectLater(one.ping(), throwsA(isA<DioException>()));
      await expectLater(two.ping(), throwsA(isA<DioException>()));
      await expectLater(
          one.readProps('modu/database8.db'), throwsA(isA<DioException>()));
      expect(calls, 1);
    } finally {
      await server.close(force: true);
    }
  });
}
