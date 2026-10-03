# Validation — 1.3

## Executed here

- Parsed all Dart source/test/tool files with the tree-sitter Dart grammar; no missing/error syntax nodes.
- Verified relative Dart imports resolve locally.
- Parsed Android XML and Apple plist overlays.
- Exercised the schema-1-to-2 SQL addition in Python SQLite, checking retained records and foreign-key cascading for assets.
- Checked ZIP integrity and inclusion of the current sources, tests, assets, installer and feature-status documents.
- Reviewed official Flutter lifecycle and local_auth 3.0.2 documentation for prompt backgrounding/cancellation behaviour.

## Not executed here

There is no Flutter or Dart SDK installed in this workspace. No Flutter analysis, compilation, unit/widget tests, native build, rendered UI screenshot, physical biometric authentication, notification delivery, scanner execution or migration of the user's actual database has been run here. Syntax parsing does not check Dart types or Flutter runtime behaviour.

## Included regression tests (must run on your PC)

- lifecycle_test.dart: background/resume, native inactive state, biometric success/cancel, PIN fallback and tappable Settings after unlocking.
- migration_test.dart: open a version-one encrypted database, retain its record/file and add the assets table.
- organizer_test.dart: quiet-hour boundaries, backward-compatible metadata, receipt suggestions, calendar escaping and encrypted multi-file/version backup restore.
- Existing recovery, crypto, repository, backup, reminder and UI tests retained. Recovery timeouts increased to five minutes without reducing PBKDF2 work.

Use `flutter test --timeout 5m --concurrency=1`. If a test fails, stop and inspect the failure rather than bypassing it. Device acceptance steps are in UI_UPDATE.md.

Sources reviewed:
- https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html
- https://pub.dev/packages/local_auth
- https://pub.dev/documentation/local_auth/latest/local_auth/LocalAuthentication-class.html
