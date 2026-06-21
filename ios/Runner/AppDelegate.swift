import Flutter
import UIKit

// iOS owns the host lifecycle only. Shared app behavior lives in Dart under
// lib/src so Android, iOS, and desktop keep one product implementation.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keep launch work minimal here; FlutterAppDelegate wires UIKit into the
    // Flutter engine and the Dart side builds the actual application state.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Plugins are generated from Flutter dependencies. Register them with the
    // implicit engine instead of hand-writing native bridges for app logic.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
