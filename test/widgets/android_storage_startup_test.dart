import 'dart:async';
import 'dart:io';

import 'package:anx_reader/page/android_storage_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows progress, safe failure and permits retry', (tester) async {
    var attempts = 0;
    final ready = Completer<void>();
    await tester.pumpWidget(AndroidStorageStartup(start: () async {
      attempts++;
      if (attempts == 1) {
        throw const FileSystemException('disk full', '/private/path');
      }
      await ready.future;
    }));
    await tester.pump();
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('/private/path'), findsNothing);
    expect(find.textContaining('可用空间'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete();
    await tester.pump();
  });
}
