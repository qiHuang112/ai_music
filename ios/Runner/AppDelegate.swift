import Flutter
import UIKit
import Vision

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
    let channel = FlutterMethodChannel(
      name: "ai_music/screenshot_ocr",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(code: "invalid_image", message: "Image file is unavailable", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        do {
          guard let image = UIImage(contentsOfFile: path), let pixels = image.cgImage else {
            throw NSError(domain: "ai_music/screenshot_ocr", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image dimensions are unavailable"])
          }
          try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([request])
          let lines: [[String: Any]] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return [
              "text": text,
              "left": box.minX,
              "top": 1 - box.maxY,
              "right": box.maxX,
              "bottom": 1 - box.minY,
              "imageWidth": pixels.width,
              "imageHeight": pixels.height,
            ]
          }
          DispatchQueue.main.async { result(lines) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }
}
