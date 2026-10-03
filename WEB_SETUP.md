# Flutter web and Drift setup

The Flutter web scaffold is in `web/`. Drift also requires `sqlite3.wasm` and
`drift_worker.js` beside `index.html`. These assets are pinned to the versions
in `pubspec.lock`: sqlite3 3.6.0 and Drift 2.35.0.

To restore or refresh the assets in PowerShell after `flutter pub get`:

```powershell
Copy-Item "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\drift-2.35.0\drift_worker.js" web\drift_worker.js
Invoke-WebRequest -Uri "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.6.0/sqlite3.wasm" -OutFile web\sqlite3.wasm
```

Run locally with `flutter run -d chrome`. Flutter's development server serves
`.wasm` files with the required `application/wasm` MIME type. Configure that
same MIME type for `.wasm` on any custom production web server. When upgrading
Drift or sqlite3, update these files to compatible releases as described at
<https://drift.simonbinder.eu/platforms/web/>.
