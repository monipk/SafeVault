// Run with the Dart SDK bundled with Flutter: dart tool/setup.dart
import 'dart:io';

Future<void> command(String executable, List<String> args) async {
  stdout.writeln('> $executable ${args.join(' ')}');
  final p = await Process.start(
    executable,
    args,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await p.exitCode;
  if (code != 0) {
    throw ProcessException(executable, args, 'Command failed', code);
  }
}

void edit(String path, String Function(String) transform) {
  final f = File(path);
  if (f.existsSync()) {
    f.writeAsStringSync(transform(f.readAsStringSync()));
  }
}

Future<void> main(List<String> args) async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run from the safe_vault folder.');
    exit(1);
  }
  if (File('.safe_vault_setup_complete').existsSync() &&
      !args.contains('--reapply')) {
    stdout.writeln(
      'Already configured. Run flutter pub get, then flutter run. Use --reapply only to reapply platform overlays.',
    );
    return;
  }
  // flutter create produces official SDK-matched runners, Gradle wrapper and platform project files.
  // Stash user-authored app files while create supplies the missing platform scaffold.
  final mainFile = File('lib/main.dart');
  final main = mainFile.readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final analysis = File('analysis_options.yaml').readAsStringSync();
  try {
    await command('flutter', [
      'create',
      '--no-pub',
      '--project-name',
      'safe_vault',
      '--org',
      'app.safevault',
      '--platforms=android,ios,web,windows,macos,linux',
      '.',
    ]);
  } finally {
    mainFile.writeAsStringSync(main);
    File('pubspec.yaml').writeAsStringSync(pubspec);
    File('analysis_options.yaml').writeAsStringSync(analysis);
  }
  final sampleTest = File('test/widget_test.dart');
  if (sampleTest.existsSync()) {
    sampleTest.deleteSync();
  }
  for (final entity in Directory(
    'platform_overlays',
  ).listSync(recursive: true).whereType<File>()) {
    final target = File(
      entity.path.replaceAll('\\', '/').replaceFirst(
        'platform_overlays/',
        '',
      ),
    );
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
  edit('android/app/build.gradle.kts', (s) {
    s = s.replaceAll('minSdk = flutter.minSdkVersion', 'minSdk = 24');
    s = s.replaceAll(
      'compileSdk = flutter.compileSdkVersion',
      'compileSdk = 36',
    );
    if (!s.contains('isCoreLibraryDesugaringEnabled')) {
      s = s.replaceFirst(
        'compileOptions {',
        'compileOptions {\n        isCoreLibraryDesugaringEnabled = true',
      );
    }
    s = s.replaceAll('JavaVersion.VERSION_11', 'JavaVersion.VERSION_17');
    if (!s.contains('desugar_jdk_libs')) {
      s +=
          '\ndependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }\n';
    }
    return s;
  });
  edit(
    'android/settings.gradle.kts',
    (s) => s.replaceAllMapped(
      RegExp(r'id\("com.android.application"\) version "([^"]+)"'),
      (m) {
        final parts = m[1]!
            .split('.')
            .map((e) => int.tryParse(e) ?? 0)
            .toList();
        if (parts[0] < 8 || (parts[0] == 8 && parts[1] < 11)) {
          return 'id("com.android.application") version "8.11.1"';
        }
        return m[0]!;
      },
    ),
  );
  edit(
    'android/gradle/wrapper/gradle-wrapper.properties',
    (s) => s.replaceAllMapped(
      RegExp(r'gradle-(\d+)\.(\d+)(?:\.\d+)?-(all|bin)\.zip'),
      (m) {
        final major = int.parse(m[1]!), minor = int.parse(m[2]!);
        return major < 8 || (major == 8 && minor < 13)
            ? 'gradle-8.13-${m[3]}.zip'
            : m[0]!;
      },
    ),
  );
  for (final variant in ['values', 'values-night']) {
    edit(
      'android/app/src/main/res/$variant/styles.xml',
      (s) => s
          .replaceAll(
            '@android:style/Theme.Light.NoTitleBar',
            'Theme.AppCompat.Light.NoActionBar',
          )
          .replaceAll(
            '@android:style/Theme.Black.NoTitleBar',
            'Theme.AppCompat.DayNight.NoActionBar',
          ),
    );
  }
  for (final platform in ['ios', 'macos']) {
    edit('$platform/Runner/Info.plist', (s) {
      if (!s.contains('NSFaceIDUsageDescription')) {
        s = s.replaceFirst(
          '</dict>',
          '<key>NSFaceIDUsageDescription</key><string>Use Face ID to unlock your Safe Vault.</string>\n</dict>',
        );
      }
      s = s.replaceAll(
        '<string>safe_vault</string>',
        '<string>Safe Vault</string>',
      );
      return s;
    });
  }
  for (final path in [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    edit(path, (s) {
      if (!s.contains('keychain-access-groups')) {
        s = s.replaceFirst(
          '</dict>',
          r'<key>keychain-access-groups</key><array><string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string></array>'
              '\n</dict>',
        );
      }
      if (!s.contains('com.apple.security.files.user-selected.read-write')) {
        s = s.replaceFirst(
          '</dict>',
          '<key>com.apple.security.files.user-selected.read-write</key><true/>\n</dict>',
        );
      }
      return s;
    });
  }
  // iOS Keychain entitlement is wired in the Xcode project for every configuration.
  File('ios/Runner/Runner.entitlements').writeAsStringSync(
    r'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>keychain-access-groups</key><array><string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string></array></dict></plist>''',
  );
  edit(
    'ios/Runner.xcodeproj/project.pbxproj',
    (s) => s.contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements')
        ? s
        : s.replaceAll(
            'INFOPLIST_FILE = Runner/Info.plist;',
            'INFOPLIST_FILE = Runner/Info.plist;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
          ),
  );
  await command('dart', ['tool/upgrade.dart', '--native-only']);
  await command('flutter', ['pub', 'get']);
  await command('dart', ['run', 'flutter_launcher_icons']);
  File(
    '.safe_vault_setup_complete',
  ).writeAsStringSync(DateTime.now().toIso8601String());
  stdout.writeln(
    '\nSetup complete. Run flutter analyze, flutter test, then flutter run.\nFor Chrome, first run: dart tool/setup_web.dart',
  );
}
