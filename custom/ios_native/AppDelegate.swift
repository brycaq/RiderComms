import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let discoveryPlugin = MultipeerDiscoveryPlugin()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController

        let methodChannel = FlutterMethodChannel(
            name: "intercom/discovery_methods",
            binaryMessenger: controller.binaryMessenger
        )
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.discoveryPlugin.handle(call, result: result)
        }

        let eventChannel = FlutterEventChannel(
            name: "intercom/discovery_events",
            binaryMessenger: controller.binaryMessenger
        )
        eventChannel.setStreamHandler(discoveryPlugin)

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
