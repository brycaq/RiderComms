import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let discoveryPlugin = MultipeerDiscoveryPlugin()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController

        // Configure the audio session for simultaneous record + playback as
        // early as possible - iOS's default session category only allows
        // one or the other, which meant whichever device was actively
        // recording (both devices, always, with the automatic feed) could
        // not play back audio from the other side. Setting this natively,
        // before any Dart code runs, is a second layer alongside the
        // AudioPlayer.global.setAudioContext call in main.dart.
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }

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
