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
# --project-name is required here: without it, flutter create derives the
# Android package from the target directory name ("app"), producing
# com.example.app instead of com.example.intercom_app. Our custom
# MainActivity.kt/NearbyDiscoveryPlugin.kt then get copied into a package
# directory that doesn't match the real one, compile fine as dead code, and
# the actual running MainActivity is the untouched Flutter default - which
# never registers our MethodChannel, hence "MissingPluginException: No
# implementation found for method startBrowsing" at runtime despite a
# perfectly successful build.
flutter create --org com.example --project-name intercom_app -i swift -a kotlin app

echo "==> Copying Dart source"
rm -rf app/lib
cp -r custom/lib app/lib
cp custom/pubspec.yaml app/pubspec.yaml

echo "==> Copying Android native module"
ANDROID_KOTLIN_DIR="app/android/app/src/main/kotlin/com/example/intercom_app"
# Verify this is actually where Flutter put the generated MainActivity.kt
# before we overwrite it - if the package doesn't match, we'd silently
# write our custom code into an unused directory (exactly the bug fixed
# above), so catch that decisively instead of relying on --project-name
# alone forever.
if [ ! -f "$ANDROID_KOTLIN_DIR/MainActivity.kt" ]; then
  echo "ERROR: Expected the generated MainActivity.kt at $ANDROID_KOTLIN_DIR/MainActivity.kt but it's not there." >&2
  echo "The real package directory Flutter generated is probably different. Contents of app/android/app/src/main/kotlin/:" >&2
  find app/android/app/src/main/kotlin -type f >&2
  exit 1
fi
mkdir -p "$ANDROID_KOTLIN_DIR"
cp custom/android_native/NearbyDiscoveryPlugin.kt "$ANDROID_KOTLIN_DIR/"
cp custom/android_native/MainActivity.kt "$ANDROID_KOTLIN_DIR/"

echo "==> Adding Nearby Connections dependency to Android build.gradle"
GRADLE_FILE="app/android/app/build.gradle"
if ! grep -q "play-services-nearby" "$GRADLE_FILE" 2>/dev/null; then
  # Append a new dependencies block rather than trying to insert into an
  # existing one - Gradle merges multiple dependencies{} blocks in the same
  # file just fine, and current Flutter templates don't reliably scaffold
  # an empty one to anchor on (this is why "Unresolved reference: Strategy/
  # DiscoveryOptions/Payload" showed up - the awk insertion never matched
  # anything, so the dependency silently never got added).
  cat >> "$GRADLE_FILE" <<'EOF'

dependencies {
    implementation "com.google.android.gms:play-services-nearby:19.3.0"
}
EOF
fi

echo "==> Ensuring compileSdk/targetSdk/minSdk 34 (record_android needs minSdk>=23; compileSdk 35 hit a corrupted android.jar on the runner, so staying on the more mature 34 instead)"
sed -i.bak -E 's/(compileSdk(Version)?)[[:space:]]*=?[[:space:]]*flutter\.compileSdkVersion/\1 = 34/' "$GRADLE_FILE"
sed -i.bak -E 's/(targetSdk(Version)?)[[:space:]]*=?[[:space:]]*flutter\.targetSdkVersion/\1 = 34/' "$GRADLE_FILE"
sed -i.bak -E 's/(minSdk(Version)?)[[:space:]]*=?[[:space:]]*flutter\.minSdkVersion/\1 = 23/' "$GRADLE_FILE"
rm -f "$GRADLE_FILE.bak"

echo "==> Bumping Kotlin Gradle Plugin version"
# Flutter's default template pins an older Kotlin (~1.7.x). Adding the Nearby
# Connections dependency pulls in kotlin-stdlib 1.9.24 transitively, and the
# older compiler can't read that newer metadata format ("Class 'kotlin.Unit'
# was compiled with an incompatible version of Kotlin"). Bump wherever the
# version is declared - this has moved between settings.gradle (plugins
# block, current) and the root build.gradle (ext.kotlin_version, older) across
# Flutter versions, so patch both locations if present.
for KOTLIN_FILE in "app/android/settings.gradle" "app/android/build.gradle"; do
  if [ -f "$KOTLIN_FILE" ]; then
    python3 - "$KOTLIN_FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
content = re.sub(
    r'(id\s+["\']org\.jetbrains\.kotlin\.android["\']\s+version\s+["\'])[\d.]+(["\'])',
    r'\g<1>1.9.22\g<2>',
    content,
)
content = re.sub(
    r"(ext\.kotlin_version\s*=\s*['\"])[\d.]+(['\"])",
    r"\g<1>1.9.22\g<2>",
    content,
)
with open(path, 'w') as f:
    f.write(content)
PYEOF
  fi
done

echo "==> Bumping Android Gradle Plugin (and Gradle wrapper) version"
# record_android's prebuilt classes.jar uses sealed classes (a newer JVM
# bytecode feature). D8 bundled with AGP 7.3.0 (the Flutter template
# default) can't dex sealed classes at all - "Sealed classes are not
# supported as program classes" - no dependency-version fix helps here,
# only a newer AGP does. AGP 8.x requires Gradle 8.4+, so bump both together
# or the build fails a different way (AGP refusing to run on old Gradle).
for AGP_FILE in "app/android/settings.gradle" "app/android/build.gradle"; do
  if [ -f "$AGP_FILE" ]; then
    python3 - "$AGP_FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
content = re.sub(
    r'(id\s+["\']com\.android\.application["\']\s+version\s+["\'])[\d.]+(["\'])',
    r'\g<1>8.3.2\g<2>',
    content,
)
content = re.sub(
    r"(classpath\s+['\"]com\.android\.tools\.build:gradle:)[\d.]+(['\"])",
    r"\g<1>8.3.2\g<2>",
    content,
)
with open(path, 'w') as f:
    f.write(content)
PYEOF
  fi
done
WRAPPER_PROPS="app/android/gradle/wrapper/gradle-wrapper.properties"
if [ -f "$WRAPPER_PROPS" ]; then
  sed -i.bak -E 's/gradle-[0-9]+\.[0-9]+(\.[0-9]+)?-/gradle-8.4-/' "$WRAPPER_PROPS"
  rm -f "$WRAPPER_PROPS.bak"
fi

echo "==> Merging AndroidManifest permissions"
MANIFEST="app/android/app/src/main/AndroidManifest.xml"
if ! grep -q "BLUETOOTH_ADVERTISE" "$MANIFEST"; then
  # Read the permissions file directly rather than pre-stripping its comment
  # header through sed - that comment is a single self-contained XML comment
  # now (valid to insert as-is), and the previous sed '/<!--/,/-->/d' step
  # hit a classic gotcha: when the opening and closing markers are on the
  # SAME line, GNU sed's range address doesn't close there, so it silently
  # consumed the entire file to EOF looking for another '-->' that never
  # came. PERMS ended up empty every time, which is why the merge kept
  # "succeeding" while inserting nothing but a blank line.
  python3 - "$MANIFEST" "custom/android_native/AndroidManifest_permissions.xml" <<'PYEOF'
import sys
manifest_path = sys.argv[1]
perms_path = sys.argv[2]
with open(perms_path) as f:
    perms = f.read()
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
if ! grep -q "BLUETOOTH_ADVERTISE" "$MANIFEST"; then
  echo "ERROR: AndroidManifest permission merge did not take effect - BLUETOOTH_ADVERTISE is still missing after patching." >&2
  echo "Dumping the manifest as generated so this is debuggable from the CI log:" >&2
  cat "$MANIFEST" >&2
  exit 1
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
      -e 's/flutter\.compileSdkVersion/34/g' \
      -e 's/flutter\.targetSdkVersion/34/g' \
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
