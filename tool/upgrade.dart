// Patch existing native runners without recreating them or changing applicationId/signing.
import 'dart:io';
import 'setup.dart' show command;

late Directory backup;
void write(String path, String contents) {
  final file = File(path);
  if (file.existsSync()) {
    final saved = File('${backup.path}/$path');
    saved.parent.createSync(recursive: true);
    file.copySync(saved.path);
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
void edit(String path, String Function(String) patch) {
  final f = File(path);
  if (f.existsSync()) write(path, patch(f.readAsStringSync()));
}
Future<void> main(List<String> args) async {
  if (!File('pubspec.yaml').existsSync()) throw StateError('Run from the project root.');
  backup = Directory('.safe_vault_native_backups/${DateTime.now().millisecondsSinceEpoch}');
  if (Directory('android').existsSync()) {
    final files = Directory('android/app/src/main').listSync(recursive: true).whereType<File>();
    final activities = files.where((f) => f.path.endsWith('MainActivity.kt')).toList();
    if (activities.length != 1) throw StateError('Expected one Kotlin MainActivity. Merge native changes manually; no Android files were changed.');
    final activity = activities.single;
    final source = activity.readAsStringSync();
    final packageName = RegExp(r'package\s+([\w.]+)').firstMatch(source)?.group(1);
    if (packageName == null) throw StateError('Cannot determine MainActivity package.');
    // Preserve the current activity and existing method channels.
    var patched = source.replaceAll('io.flutter.embedding.android.FlutterActivity',
      'io.flutter.embedding.android.FlutterFragmentActivity')
      .replaceAll(RegExp(r'\bFlutterActivity\b'), 'FlutterFragmentActivity');
    if (!patched.contains('safe_vault/privacy')) {
      if (patched.contains('configureFlutterEngine')) {
        stdout.writeln('Custom MainActivity found: preserve its configureFlutterEngine and merge the safe_vault/privacy channel from platform_overlays manually.');
      } else {
        final declaration = RegExp(r'class MainActivity\s*:\s*FlutterFragmentActivity\(\)\s*(\{)?');
        patched = patched.replaceFirstMapped(declaration, (m) =>
          'class MainActivity : FlutterFragmentActivity() {\n'
          '    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {\n'
          '        super.configureFlutterEngine(flutterEngine)\n'
          '        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)\n'
          '        io.flutter.plugin.common.MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safe_vault/privacy").setMethodCallHandler { call, result ->\n'
          '            if (call.method == "secure") {\n'
          '                if (call.arguments == true) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)\n'
          '                else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)\n'
          '                result.success(null)\n'
          '            } else result.notImplemented()\n'
          '        }\n'
          '    }\n'
          '${m[1] == null ? "}" : ""}');
      }
    }
    write(activity.path, patched);
    var widget = File('platform_overlays/android/app/src/main/kotlin/app/safevault/safe_vault/SafeVaultWidget.kt')
      .readAsStringSync().replaceFirst('package app.safevault.safe_vault', 'package $packageName');
    final gradle = File('android/app/build.gradle.kts');
    final groovy = File('android/app/build.gradle');
    final buildText = gradle.existsSync() ? gradle.readAsStringSync() : groovy.existsSync() ? groovy.readAsStringSync() : '';
    final namespace = RegExp(r'''namespace\s*(?:=\s*)?["']([^"']+)["']''').firstMatch(buildText)?.group(1);
    if (namespace != null && namespace != packageName) {
      widget = widget.replaceFirst('package $packageName', 'package $packageName\nimport $namespace.R');
    }
    write('${activity.parent.path}/SafeVaultWidget.kt', widget);
    for (final f in Directory('platform_overlays/android/app/src/main/res').listSync(recursive: true).whereType<File>()) {
      final target = f.path.replaceAll('\\', '/').replaceFirst('platform_overlays/', '');
      write(target, f.readAsStringSync());
    }
    edit('android/app/src/main/AndroidManifest.xml', (s) {
      for (final permission in ['USE_BIOMETRIC','POST_NOTIFICATIONS','RECEIVE_BOOT_COMPLETED','SCHEDULE_EXACT_ALARM']) {
        if (!s.contains('android.permission.$permission')) {
          s = s.replaceFirst('<application', '<uses-permission android:name="android.permission.$permission"/>\n    <application');
        }
      }
      s = s.replaceFirstMapped(RegExp(r'<application\b[^>]*>'), (m) {
        var tag = m[0]!;
        if (tag.contains('android:label=')) {
          tag = tag.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Safe Vault"');
        } else { tag = tag.replaceFirst('<application', '<application android:label="Safe Vault"'); }
        return tag;
      });
      final declarations = <String, String>{
        'ScheduledNotificationReceiver': '<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>',
        'ScheduledNotificationBootReceiver': '<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"><intent-filter><action android:name="android.intent.action.BOOT_COMPLETED"/><action android:name="android.intent.action.MY_PACKAGE_REPLACED"/></intent-filter></receiver>',
        'ActionBroadcastReceiver': '<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"/>',
        'SafeVaultWidget': '<receiver android:name="$packageName.SafeVaultWidget" android:exported="false" android:label="Safe Vault"><intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter><meta-data android:name="android.appwidget.provider" android:resource="@xml/safe_vault_widget_info"/></receiver>',
      };
      for (final entry in declarations.entries) {
        if (!s.contains(entry.key)) s = s.replaceFirst('</application>', '${entry.value}\n</application>');
      }
      return s;
    });
    for (final f in Directory('android/app/src/main/res').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('styles.xml'))) {
      edit(f.path, (s) => s.replaceAll('@android:style/Theme.Light.NoTitleBar', 'Theme.AppCompat.Light.NoActionBar')
        .replaceAll('@android:style/Theme.Black.NoTitleBar', 'Theme.AppCompat.DayNight.NoActionBar'));
    }
    edit('android/app/build.gradle.kts', (s) {
      s = s.replaceAll('minSdk = flutter.minSdkVersion', 'minSdk = 24');
      if (!s.contains('isCoreLibraryDesugaringEnabled')) s = s.replaceFirst('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true');
      if (!s.contains('desugar_jdk_libs')) s += '\ndependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }\n';
      return s;
    });
  }
  for (final platform in ['ios','macos']) {
    edit('$platform/Runner/Info.plist', (s) {
      if (!s.contains('NSFaceIDUsageDescription')) s = s.replaceFirst('</dict>', '<key>NSFaceIDUsageDescription</key><string>Unlock Safe Vault using Face ID.</string>\n</dict>');
      // The launcher widget contains no personal data and needs no App Group.
      if (platform == 'ios' && !s.contains('<string>safevault</string>')) {
        if (s.contains('<key>CFBundleURLTypes</key>')) {
          stdout.writeln('Existing iOS URL schemes detected. Add safevault to CFBundleURLTypes manually for widget navigation.');
        } else {
          s = s.replaceFirst('</dict>', '<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>safevault</string></array></dict></array>\n</dict>');
        }
      }
      return s;
    });
    edit('$platform/Runner/AppDelegate.swift', (s) {
      if (!s.contains('import UserNotifications')) s = 'import UserNotifications\n$s';
      if (!s.contains('UNUserNotificationCenter.current().delegate')) {
        if (platform == 'ios') {
          s = s.replaceFirst('return super.application(application, didFinishLaunchingWithOptions: launchOptions)',
            'UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate\n    return super.application(application, didFinishLaunchingWithOptions: launchOptions)');
        } else {
          // macOS FlutterAppDelegate normally supplies the delegate; retain SDK lifecycle code.
          stdout.writeln('macOS: verify foreground notification delivery on your signed build.');
        }
      }
      return s;
    });
  }
  stdout.writeln('Native changes saved. Originals: ${backup.path}. Application ID and signing were preserved.');
  if (!args.contains('--native-only')) {
    await command('flutter', ['pub', 'get']);
    await command('dart', ['run', 'flutter_launcher_icons']);
    await command('dart', ['format', 'lib', 'test', 'tool']);
    await command('flutter', ['analyze', '--no-fatal-infos']);
    await command('flutter', ['test']);
  }
}
