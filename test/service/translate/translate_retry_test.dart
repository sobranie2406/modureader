import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/enums/lang_list.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/service/translate/microsoft_free.dart';

/// A provider that answers however the test wants and counts its attempts.
class _ScriptedProvider extends TranslateServiceProvider {
  _ScriptedProvider(this.behaviour);

  final void Function(int attempt) behaviour;
  int attempts = 0;

  @override
  TranslateService get service => TranslateService.microsoftFree;

  @override
  String getLabel(BuildContext context) => 'test';

  @override
  Widget translate(String text, LangListEnum from, LangListEnum to,
          {String? contextText, bool isFullText = false}) =>
      throw UnimplementedError();

  @override
  Stream<String> translateStream(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
    Future<void>? whenCancelled,
  }) async* {
    attempts++;
    behaviour(attempts);
    yield 'done';
  }
}

class _BlockedAdapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: SocketException('blocked by the network'),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('an unreachable provider is not retried', () async {
    // Retrying a blocked host triples the wait for the same failure, which is
    // how one plugin translate call ended up taking 63 s.
    final provider = _ScriptedProvider((_) {
      throw const TranslateUnavailableException('offline');
    });
    await expectLater(
        provider.translateTextOnly(
            'hello', LangListEnum.english, LangListEnum.simplifiedChinese),
        throwsA(isA<TranslateUnavailableException>()));
    expect(provider.attempts, 1);
  });

  test('an empty answer is still retried', () async {
    final provider = _ScriptedProvider((_) {
      throw Exception('empty');
    });
    await expectLater(
        provider.translateTextOnly(
            'hello', LangListEnum.english, LangListEnum.simplifiedChinese),
        throwsA(isA<Exception>()));
    expect(provider.attempts, 3);
  });

  test('a transient failure recovers on a later attempt', () async {
    final provider = _ScriptedProvider((attempt) {
      if (attempt == 1) throw Exception('flaky');
    });
    expect(
        await provider.translateTextOnly(
            'hello', LangListEnum.english, LangListEnum.simplifiedChinese),
        'done');
    expect(provider.attempts, 2);
  });

  test('a blocked free endpoint fails once, as unavailable', () async {
    final adapter = _BlockedAdapter();
    final provider = MicrosoftFreeTranslateProvider(
        dioFactory: () => Dio()..httpClientAdapter = adapter);
    await expectLater(
        provider.translateTextOnly(
            'hello', LangListEnum.english, LangListEnum.simplifiedChinese),
        throwsA(isA<TranslateUnavailableException>()));
    // One HTTP attempt, not three: the old code waited three connect timeouts.
    expect(adapter.calls, 1);
  });

  test('a non-200 answer from the free endpoint is unavailable, not retried',
      () async {
    var calls = 0;
    final provider = MicrosoftFreeTranslateProvider(
        dioFactory: () => Dio()
          ..httpClientAdapter = _StatusAdapter(() {
            calls++;
            return 429;
          }));
    await expectLater(
        provider.translateTextOnly(
            'hello', LangListEnum.english, LangListEnum.simplifiedChinese),
        throwsA(isA<TranslateUnavailableException>()));
    expect(calls, 1);
  });
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);
  final int Function() status;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('rate limited', status());
  @override
  void close({bool force = false}) {}
}
