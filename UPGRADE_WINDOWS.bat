@echo off
cd /d "%~dp0"
echo Back up your vault in the app before upgrading.
call dart tool/upgrade.dart
if errorlevel 1 goto failed
call flutter build apk --release
if errorlevel 1 goto failed
echo APK: %cd%\build\app\outputs\flutter-apk\app-release.apk
pause
exit /b 0
:failed
echo Upgrade stopped. Please copy the error output for diagnosis.
pause
exit /b 1
