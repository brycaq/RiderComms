import 'package:permission_handler/permission_handler.dart';

/// Requests every permission nearby discovery + push-to-talk audio need.
/// Android 12+ requires explicit runtime grants for Bluetooth advertise/
/// scan/connect and nearby Wi-Fi even though they're declared in the
/// manifest - skipping this means the native discovery call throws a
/// SecurityException the moment you try to host or join, which (without
/// the try/catch added in home_screen.dart) fails silently before ever
/// navigating anywhere. That's what "the buttons don't do anything" was.
///
/// Returns the list of permissions that were NOT granted, so the caller
/// can tell the user specifically what's missing. Empty list = all good.
Future<List<Permission>> requestDiscoveryPermissions() async {
  final permissions = <Permission>[
    Permission.bluetoothAdvertise,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.nearbyWifiDevices,
    Permission.locationWhenInUse,
    Permission.microphone,
  ];
  final statuses = await permissions.request();
  return permissions
      .where((p) => !(statuses[p]?.isGranted ?? false) && !(statuses[p]?.isLimited ?? false))
      .toList();
}
