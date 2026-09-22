import 'dart:async';
import 'dart:io';
import 'package:anx_reader/service/tts/notification_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('background/desktop does not check or request a permission', () async {
    final gate = NotificationPermissionGate(
      status: () async => throw StateError('unexpected status'),
      request: () async => throw StateError('unexpected request'),
      wasAsked: () => false,
      markAsked: () async => fail('unexpected write'),
    );
    expect(await gate.ensure(foregroundAndroid: false), isNull);
  });
  for (final status in [
    PermissionStatus.granted,
    PermissionStatus.denied,
    PermissionStatus.permanentlyDenied,
    PermissionStatus.restricted
  ]) {
    test('$status: request only when possible and never nag after denial',
        () async {
      var asked = false;
      var requests = 0;
      final gate = NotificationPermissionGate(
        status: () async => status,
        request: () async {
          requests++;
          return PermissionStatus.denied;
        },
        wasAsked: () => asked,
        markAsked: () async {
          asked = true;
        },
      );
      expect(await gate.ensure(foregroundAndroid: true), status);
      expect(requests, status.isDenied ? 1 : 0);
      expect(await gate.ensure(foregroundAndroid: true), isNull);
      expect(requests, status.isDenied ? 1 : 0);
    });
  }
  test('overlapping playback starts share one system permission dialog',
      () async {
    final result = Completer<PermissionStatus>();
    var asked = false;
    var requests = 0;
    final gate = NotificationPermissionGate(
      status: () async => PermissionStatus.denied,
      request: () {
        requests++;
        return result.future;
      },
      wasAsked: () => asked,
      markAsked: () async {
        asked = true;
      },
    );
    final a = gate.ensure(foregroundAndroid: true);
    final b = gate.ensure(foregroundAndroid: true);
    result.complete(PermissionStatus.granted);
    expect(await Future.wait([a, b]),
        [PermissionStatus.granted, PermissionStatus.granted]);
    expect(requests, 1);
  });
  test('notification permission and media foreground service are both declared',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest,
        contains('android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'));
    expect(manifest, contains('android:foregroundServiceType="mediaPlayback"'));
  });
}
