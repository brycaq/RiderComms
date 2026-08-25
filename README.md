# Intercom

Cross-platform (Flutter) intercom app. Discovers nearby users via Bluetooth /
Wi-Fi (MultipeerConnectivity on iOS, Nearby Connections on Android), lets one
device host a session for others to join, and supports push-to-talk audio
between connected peers.

## Why the repo is structured this way

Flutter projects contain a large amount of generated boilerplate (Gradle
wrapper, Xcode project files, plugin registrant code) that shouldn't be
hand-written or hand-edited. This repo keeps only the code that's actually
custom in `custom/`, and `scripts/setup.sh` runs the standard `flutter
create` scaffolding, then overlays the custom Dart + native code and merges
the required permissions. This is the same pattern most real Flutter
projects with custom native modules use.
