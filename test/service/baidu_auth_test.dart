import 'dart:convert';
import 'package:anx_reader/service/remote_library/baidu_auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = 'a' * 43;
  late BaiduAuth auth;
  late List<RequestOptions> requests;
  late Map<String, dynamic> Function(RequestOptions) response;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({BaiduAuth.sessionKey: session});
    requests = [];
    response = (_) => {'access_token': 'test-access', 'expires_in': 3600};
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options);
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: ResponseBody.fromString(jsonEncode(response(options)), 200)));
      }));
    auth = BaiduAuth(client: client);
  });
  tearDown(() => auth.close());

  test(
      'device session restored securely, concurrent token loads coalesce and cache',
      () async {
    expect(await auth.restore(), isTrue);
    expect(await Future.wait([auth.accessToken(), auth.accessToken()]),
        ['test-access', 'test-access']);
    expect(await auth.accessToken(), 'test-access');
    expect(requests.length, 1);
    expect(requests.single.headers['Authorization'], 'Bearer $session');
    expect(await auth.storage.readAll(), {BaiduAuth.sessionKey: session});
    await auth.disconnect();
    expect(requests.last.path, endsWith('/v1/revoke'));
    expect(await auth.storage.readAll(), isEmpty);
  });

  test('login URL must match Baidu, state and exact callback', () async {
    final proof = BaiduAuth.newProof();
    response = (_) => {
          'ticket': 'test-ticket',
          'authorize_url':
              'https://openapi.baidu.com/oauth/2.0/authorize?state=test-ticket&redirect_uri=${Uri.encodeComponent('${BaiduAuth.origin}/oauth/baidu/callback')}'
        };
    expect(
        (await auth.start(proof, CancelToken())).url.host, 'openapi.baidu.com');
    expect((requests.single.data as Map)['challenge'], hasLength(64));
    expect(requests.single.data.toString(), isNot(contains(proof)));
    response =
        (_) => {'ticket': 'test-ticket', 'authorize_url': 'https://evil.test/'};
    await expectLater(auth.start(proof, CancelToken()), throwsFormatException);
  });

  test(
      'new authorization persists only session and revokes previous device session',
      () async {
    await auth.restore();
    final fresh = 'b' * 43;
    response = (request) => request.path.endsWith('/v1/revoke')
        ? {'ok': true}
        : {
            'session': fresh,
            'access_token': 'test-new-access',
            'expires_in': 3600
          };
    expect(await auth.claim('ticket', 'proof', CancelToken()), isTrue);
    expect(await auth.storage.readAll(), {BaiduAuth.sessionKey: fresh});
    expect(requests.last.headers['Authorization'], 'Bearer $session');
    expect(await auth.accessToken(), 'test-new-access');
  });

  test('changed session invalidates cached account token', () async {
    await auth.restore();
    await auth.accessToken();
    await auth.storage.write(key: BaiduAuth.sessionKey, value: 'c' * 43);
    await auth.restore();
    response = (_) => {'access_token': 'other-account', 'expires_in': 3600};
    expect(await auth.accessToken(), 'other-account');
    expect(requests.length, 2);
  });
}
