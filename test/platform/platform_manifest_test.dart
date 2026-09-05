import 'dart:io';

import 'package:anx_reader/config/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest uses Modu platform identity', () {
    final buildGradle = File('android/app/build.gradle').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/modu/reader/MainActivity.kt',
    ).readAsStringSync();
    final playStoreService =
        File('lib/service/iap/play_store_iap_service.dart').readAsStringSync();

    expect(buildGradle, contains('namespace "${AppIdentity.bundleId}"'));
    expect(buildGradle, contains('applicationId "${AppIdentity.bundleId}"'));
    expect(buildGradle, contains('minSdkVersion 26'));
    expect(activity, contains('package com.modu.reader'));
    expect(activity, contains('com.modu.reader/install_info'));
    expect(playStoreService, contains('AppIdentity.bundleId'));
    expect(
      File('android/app/src/main/kotlin/com/example/anx_reader/MainActivity.kt')
          .existsSync(),
      isFalse,
    );
    expect(
      File('android/app/src/main/kotlin/com/anxcye/anx_reader/MainActivity.kt')
          .existsSync(),
      isFalse,
    );
  });

  test('macOS config uses Modu platform identity', () {
    final appInfo =
        File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();

    expect(appInfo,
        contains('PRODUCT_BUNDLE_IDENTIFIER = ${AppIdentity.bundleId}'));
    expect(appInfo, contains('PRODUCT_NAME = Modu'));
  });

  test('macOS project targets the documented minimum system version', () {
    final podfile = File('macos/Podfile').readAsStringSync();
    final project =
        File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(podfile, contains("platform :osx, '14.0'"));
    expect(project, isNot(contains('MACOSX_DEPLOYMENT_TARGET = 12.0;')));
    expect(project, contains('MACOSX_DEPLOYMENT_TARGET = 14.0;'));
    expect(project, isNot(contains('Anx Reader.app')));
  });

  test('launch icons and user-facing surfaces use Modu branding', () {
    final macIcon = File(
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/1024-mac.png',
    );
    final projectIcon = File('assets/icon/modu-app-icon.png');
    expect(macIcon.existsSync(), isTrue);
    expect(projectIcon.existsSync(), isTrue);
    expect(macIcon.lengthSync(), greaterThan(10000));
    expect(projectIcon.lengthSync(), greaterThan(10000));

    for (final legacyIcon in [
      'assets/icon/Anx-logo.png',
      'assets/icon/Anx-logo-dark.png',
      'assets/icon/Anx-logo-tined.png',
    ]) {
      expect(File(legacyIcon).existsSync(), isFalse);
    }

    final userFacingSources = [
      'lib/enums/ai_prompts.dart',
      'lib/service/ai/langchain_registry.dart',
      'lib/widgets/book_share/excerpt_share_card.dart',
      'lib/widgets/book_share/excerpt_share_bottom_sheet.dart',
      'lib/page/home_page.dart',
      'web/manifest.json',
      'web/index.html',
      'ios/Runner/Info.plist',
      'linux/my_application.cc',
      'windows/runner/main.cpp',
      '.github/workflows/build-android.yaml',
      '.github/workflows/build-ios.yaml',
      '.github/workflows/build-macos.yaml',
      '.github/workflows/build-windows.yaml',
      '.github/ISSUE_TEMPLATE/bug-report.yaml',
    ]
        .map((path) => File(path).readAsStringSync())
        // The inherited Dart package namespace is an internal identifier, not
        // user-facing branding. Renaming it requires a repository-wide import
        // migration and is intentionally outside this resource check.
        .map(
          (source) => source.replaceAll(
            RegExp(
              r"^import 'package:anx_reader/.*$",
              multiLine: true,
            ),
            '',
          ),
        )
        .join('\n')
        .toLowerCase();

    expect(userFacingSources, isNot(contains('anx reader')));
    expect(userFacingSources, isNot(contains('anxreader')));
    expect(userFacingSources, isNot(contains('anx_reader')));
    expect(userFacingSources, contains('modu'));
  });
}
