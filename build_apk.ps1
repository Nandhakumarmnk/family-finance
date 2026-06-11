# Builds a debug APK locally. Run from the family_finance/ folder.
# Requires: Flutter SDK + Android SDK + JDK 17 already installed and on PATH.
#
#   powershell -ExecutionPolicy Bypass -File .\build_apk.ps1
#
# Output APK: build\app\outputs\flutter-apk\app-debug.apk

$ErrorActionPreference = "Stop"

Write-Host "==> Checking Flutter toolchain..." -ForegroundColor Cyan
flutter --version
flutter doctor

# Generate android/ (and other platform folders) if missing. Safe for lib/.
if (-not (Test-Path ".\android")) {
    Write-Host "==> Generating platform folders..." -ForegroundColor Cyan
    flutter create . --org net.ramrajcotton --project-name family_finance
}

Write-Host "==> Fetching dependencies..." -ForegroundColor Cyan
flutter pub get

Write-Host "==> Building debug APK..." -ForegroundColor Cyan
flutter build apk --debug

$apk = "build\app\outputs\flutter-apk\app-debug.apk"
if (Test-Path $apk) {
    Write-Host "`n APK built: $((Resolve-Path $apk).Path)" -ForegroundColor Green
    Write-Host "Install on a connected device with:  flutter install  (or  adb install `"$apk`")"
} else {
    Write-Host "Build finished but APK not found at $apk" -ForegroundColor Yellow
}
