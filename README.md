# LifeVault

LifeVault is a local-first Flutter mobile app for organizing personal documents, subscriptions, important dates, maintenance, notes, and reminders.

## Project setup

This source bundle is designed for Flutter 3.47+ / Dart 3.13+ and uses Riverpod, GoRouter, Drift/SQLite, secure storage, local authentication, local notifications, file picker, image picker, and timezone support.

From the project root:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

For Android:

```powershell
flutter devices
flutter run -d <your-device-id>
```

For web, install Flutter 3.47+ and Chrome, extract this project, then run from
the extracted project directory:

```powershell
flutter pub get
flutter run -d chrome
```

The Drift web runtime files are included in `web/`. See [WEB_SETUP.md](WEB_SETUP.md)
if you need to restore them or configure a production web server.

## Android configuration

### Biometric app lock

Add this permission to `android/app/src/main/AndroidManifest.xml` alongside the other `<uses-permission>` entries:

```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
```

The current `local_auth` package supports `canCheckBiometrics`, `getAvailableBiometrics`, `isDeviceSupported`, and `authenticate`; the app uses these APIs and requests biometric-only authentication. See the package docs for platform-specific requirements.

### Scheduled notifications

The notification plugin needs the Android manifest receivers/permissions documented by the plugin. In particular, scheduled notifications need the boot receiver, and Android 13+ requires notification permission at runtime. This app uses inexact scheduling, so it does not request exact-alarm permission.

Add these to the `<manifest>` / `<application>` sections as required by the plugin version:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

Inside `<application>`:

```xml
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
    </intent-filter>
</receiver>
```

The plugin also documents desugaring requirements for scheduled notifications. If your Android build reports desugaring errors, enable core library desugaring in `android/app/build.gradle` (or the equivalent Gradle Kotlin DSL file for your Flutter template) using the version shown in the plugin's current Android setup instructions.

## Architecture

```text
lib/
├── app/
│   ├── life_vault_app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   ├── database/
│   ├── models/
│   ├── repositories/
│   ├── services/
│   ├── utils/
│   └── widgets/
└── features/
    ├── auth/
    ├── dashboard/
    ├── documents/
    ├── important_dates/
    ├── maintenance/
    ├── notes/
    ├── planner/
    ├── reminders/
    ├── search/
    ├── settings/
    ├── subscriptions/
    └── vault/
```

The app intentionally starts with an empty database. There are no seeded records, mock users, demo subscriptions, sample notes, fake documents, or placeholder entries.

## Security notes

The app PIN is never stored directly. LifeVault stores a salted SHA-256 verifier in `flutter_secure_storage`. Biometric authentication is delegated to the operating system through `local_auth`.

The SQLite database remains local to the device. Export/import uses an explicit JSON backup flow initiated from Settings.

## Extensibility

Repositories and services are separated from the UI so Firebase sync, OCR, AI categorization, or a stronger encrypted database layer can be introduced later without replacing the feature screens.
