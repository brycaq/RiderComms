#!/usr/bin/env bash
# Generates the standard Flutter project skeleton (Gradle wrapper, Xcode
# project, generated plugin registrant, etc - all the boilerplate that
# isn't hand-written) and then overlays the custom source in custom/.
#
# Requires: Flutter SDK installed and on PATH. Run from the repo root.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found on PATH. Install it first: https://flutter.dev/docs/get-started/install"
  exit 1
fi

echo "==> Generating base Flutter project (app/)"
flutter create --org com.example -i swift -a kotlin app

echo "==> Copying Dart source"
rm -rf app/lib
cp -r custom/lib app/lib
cp custom/pubspec.yaml app/pubspec.yaml

echo "==> Copying Android native module"
ANDROID_KOTLIN_DIR="app/android/app/src/main/kotlin/com/example/intercom_app"
mkdir -p "$ANDROID_KOTLIN_DIR"
cp custom/android_native/NearbyDiscoveryPlugin.kt "$ANDROID_KOTLIN_DIR/"
cp custom/android_native/MainActivity.kt "$ANDROID_KOTLIN_DIR/"

echo "==> Adding Nearby Connections dependency to Android build.gradle"
GRADLE_FILE="app/android/app/build.gradle"
if ! grep -q "play-services-nearby" "$GRADLE_FILE" 2>/dev/null; then
  awk '/^dependencies *\{/{print;print "    implementation \"com.google.android.gms:play-services-nearby:19.3.0\"";next}1' \
    "$GRADLE_FILE" > "$GRADLE_FILE.tmp" && mv "$GRADLE_FILE.tmp" "$GRADLE_FILE"
fi

echo "==> Merging AndroidManifest permissions"
MANIFEST="app/android/app/src/main/AndroidManifest.xml"
if ! grep -q "BLUETOOTH_ADVERTISE" "$MANIFEST"; then
  PERMS=$(grep -v '^<!--\|^-->' custom/android_native/AndroidManifest_permissions.xml)
  python3 - "$MANIFEST" "$PERMS" <<'PYEOF'
import sys
manifest_path = sys.argv[1]
perms = sys.argv[2]
with open(manifest_path) as f:
    content = f.read()
content = content.replace("<application", perms + "\n    <application", 1)
if 'xmlns:tools=' not in content:
    content = content.replace(
        'xmlns:android="http://schemas.android.com/apk/res/android"',
        'xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools"',
        1,
    )
with open(manifest_path, "w") as f:
    f.write(content)
PYEOF
fi

echo "==> Copying iOS native module"
cp custom/ios_native/MultipeerDiscoveryPlugin.swift app/ios/Runner/
cp custom/ios_native/AppDelegate.swift app/ios/Runner/AppDelegate.swift

echo "==> Merging Info.plist permissions"
PLIST="app/ios/Runner/Info.plist"
python3 - "$PLIST" <<'PYEOF'
import sys, re
plist_path = sys.argv[1]
with open(plist_path) as f:
    content = f.read()
extra = """	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Intercom uses Bluetooth to discover nearby sessions.</string>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Intercom uses your local network to connect to nearby sessions.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Intercom needs the microphone for push-to-talk audio.</string>
	<key>NSBonjourServices</key>
	<array>
		<string>_intercom-app._tcp</string>
		<string>_intercom-app._udp</string>
	</array>
"""
content = re.sub(r"(<dict>)", r"\1\n" + extra, content, count=1)
with open(plist_path, "w") as f:
    f.write(content)
PYEOF

echo "==> Fetching packages"
cd app
flutter pub get

echo "Done. Project is ready in ./app"
echo "Run: cd app && flutter run"
