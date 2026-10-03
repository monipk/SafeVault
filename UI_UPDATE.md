# Safe Vault 1.3 — install and verify

## Before running the updated app

1. In your existing app, save an encrypted backup and keep its password. Save this backup separately as your pre-1.3 copy.
2. If the biometric freeze prevents access, close/reopen the existing app, use PIN and temporarily disable biometrics so you can back up. Do not uninstall or clear app data to fix the freeze.
3. Close running Flutter builds and IDE debugging sessions.

This update changes the local database from schema 1 to schema 2 on first launch so multiple files and versions can be stored. Source backups do not back up phone data. Do not reinstall an older app against the upgraded database.

## Install source

1. Extract Safe_Vault_1_3_Organizer_Update.zip into Downloads, OUTSIDE the existing project.
2. Open its safe_vault folder and double-click APPLY_UI_UPDATE.bat.
3. Enter your existing project folder:

   C:\Hackathon\mobile application flutter\Safe Vault\SafeVault

4. The installer saves affected original source outside the project and applies the new lib/test files. It preserves native identifiers, signing and existing dependencies. It runs:

   ```powershell
   flutter pub get
   flutter analyze --no-fatal-infos
   flutter test --timeout 5m --concurrency=1
   ```

If any command fails, stop and copy the first error output. Do not skip failed tests or uninstall your app.

## Build only after checks pass

```powershell
cd "C:\Hackathon\mobile application flutter\Safe Vault\SafeVault"
flutter build apk --release
explorer .\build\app\outputs\flutter-apk
```

Install app-release.apk as an update using the same signing key. This archive contains source, not a prebuilt APK or IPA. iOS still needs a Mac/signing and separate device testing.

## Required checks on your phone

Start with biometric tests before adding real new data:

1. Enable biometrics. Lock/unlock successfully, then try cancel → PIN, wrong fingerprint → PIN, and Cancel → use PIN.
2. Leave and return five times; repeat once with immediate auto-lock and once with 30-second auto-lock. After every unlock tap Add, Settings, a navigation tab, and a document.
3. Open the notification shade and dismiss it while unlocked. Verify taps still work. Background the app during a biometric prompt and verify it never exposes a locked vault without successful authentication.
4. Verify PIN fallback still works when biometrics is unavailable. No authentication attempt should keep the app busy indefinitely.
5. Open your pre-existing records and attachments after migration. Save a 1.3 encrypted backup, then test restore on a separate test installation/device before depending on it.
6. On a disposable test record: add two files; replace one; preview the old version; delete a copy. Check the original/other file still opens.
7. Try a one-minute main reminder and another additional reminder with the app backgrounded. Test quiet hours spanning midnight and snooze. OS settings can still delay alerts.
8. Check layout at normal and large system text sizes, with glass on/off. Check PIN keyboard, cropping, folder filters, long names and five bottom tabs.

These are acceptance checks, not a claim they have already passed. Report what remains visible during any freeze (home, lock screen or shield), whether a biometric prompt appeared, and whether Android Back still works.

## Where to find new features

- More menu → Tools & templates: receipts, photo-to-PDF, templates, storage.
- Open an item → Files & versions; Organize & reminders.
- Long-press an item → select more → bulk menu.
- Settings → Personalize: folders, tabs, cards, text/contrast and quiet hours.
- Settings → Preferences: English or partial Tamil interface.
- Settings → Guide: setup checklist and existing basics.

Read FEATURES_1_3.md for the full feature matrix. Some requested native features are deliberately deferred; there are no fake OCR, cloud-sync or payment-app connection buttons.
