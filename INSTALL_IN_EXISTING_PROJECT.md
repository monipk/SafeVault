# Install into your existing Flutter project

This bundle matches the existing package name `os_project`, so you can copy its `lib/`, `test/`, `pubspec.yaml`, and `analysis_options.yaml` into the Flutter project you already created.

From the project root:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

For Android, use:

```powershell
flutter devices
flutter run -d <android-device-id>
```

Then open `PLATFORM_SETUP.md` for the Android/iOS permission additions required by local authentication, image capture, and scheduled notifications.
