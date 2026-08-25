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

echo "==> Ensuring compileSdk/targetSdk/minSdk (record_android + audioplayers require newer SDKs)"
# Regex allows an optional '=' because Flutter's template has used both
# "compileSdk flutter.compileSdkVersion" (older) and
# "compileSdk = flutter.compileSdkVersion" (current) styles - matching only
# one meant the substitution silently did nothing on the other.
sed -i.bak -E 's/(compileSdk(Version)?)[[:space:]]*=?[[:space:]]*flutter\.compileSdkVersion/\1 = 35/' "$GRADLE_FILE"
sed -i.bak -E 's/(targetSdk(Version)?)[[:space:]]*=?[[:space:]]*flutter\.targetSdkVersion/\1 = 35/' "$GRADLE_FILE"
sed -i.bak -E 's/(minSdk(Version)?)[[:space:]]*=?[[:space:]]*flutter\.minSdkVersion/\1 = 23/' "$GRADLE_FILE"
rm -f "$GRADLE_FILE.bak"

echo "==> Pinning buildToolsVersion to match compileSdk 35"
# Without this, Gradle can pair compileSdk 35 with whatever build-tools
# happens to already be cached on the runner (observed: 30.0.3) - aapt2 from
# a build-tools version that old can't parse the newer platform's resource
# table format, producing a cryptic "entry offsets overlap actual entry
# data" error that looks like SDK corruption but isn't.
python3 - "$GRADLE_FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
if 'buildToolsVersion' not in content:
    content = re.sub(
        r'(compileSdk(Version)?\s*=?\s*35\s*\n)',
        r'\1    buildToolsVersion "35.0.0"\n',
        content,
        count=1,
    )
with open(path, 'w') as f:
    f.write(content)
PYEOF

echo "==> Merging AndroidManifest permissions"
MANIFEST="app/android/app/src/main/AndroidManifest.xml"
if ! grep -q "BLUETOOTH_ADVERTISE" "$MANIFEST"; then
  # Strip any <!-- ... --> comment block(s) as a whole, not just lines that
  # start with the markers - a comment spanning multiple lines needs a range
  # delete or leftover text (even English prose) gets inserted as raw XML.
  PERMS=$(sed '/<!--/,/-->/d' custom/android_native/AndroidManifest_permissions.xml)
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
cd "$ROOT_DIR"

echo "==> Patching record_android's build.gradle in the pub cache"
# record_android ships its own build.gradle referencing flutter.compileSdkVersion,
# a legacy property that isn't reliably exposed to plugin subprojects under the
# Flutter Gradle Plugin loading used by current `flutter create` templates. This
# breaks regardless of which record version resolves, since the sub-package
# (record_android) versions independently of the top-level `record` package.
# Patch it directly wherever pub put it - the version number in the folder name
# varies, so glob for it instead of hardcoding.
PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
for GRADLE in "$PUB_CACHE_DIR"/hosted/pub.dev/record_android-*/android/build.gradle; do
  if [ -f "$GRADLE" ]; then
    sed -i.bak \
      -e 's/flutter\.compileSdkVersion/35/g' \
      -e 's/flutter\.targetSdkVersion/35/g' \
      -e 's/flutter\.minSdkVersion/23/g' \
      "$GRADLE"
    rm -f "$GRADLE.bak"
    echo "   patched $GRADLE"
  fi
done

echo "==> Registering new iOS Swift file with the Xcode project"
# Unlike Android (Gradle auto-discovers every .kt file under the source set),
# Xcode only compiles files explicitly listed in project.pbxproj. Dropping a
# new .swift file into Runner/ via cp is invisible to Xcode's build system
# until it's registered - use mod-pbxproj (a small, widely-used CLI) to add
# it to the Runner target's Sources build phase.
python3 -m pip install --quiet --user --break-system-packages pbxproj
PBXPROJ_BIN="$(python3 -m site --user-base)/bin/pbxproj"
# Run from inside app/ios/ with paths relative to it - pbxproj resolves the
# file argument relative to the .xcodeproj's own directory, so passing the
# app/ios/ prefix again (as when run from repo root) doubles it into
# app/ios/app/ios/... and Xcode can't find the file.
(cd app/ios && "$PBXPROJ_BIN" file Runner.xcodeproj Runner/MultipeerDiscoveryPlugin.swift --target Runner)

echo "Done. Project is ready in ./app"
echo "Run: cd app && flutter run"
