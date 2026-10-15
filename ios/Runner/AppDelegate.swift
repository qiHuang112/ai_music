import Flutter
import UIKit
import Vision
import Darwin

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
    let performance = FlutterMethodChannel(
      name: "ai_music/performance",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    performance.setMethodCallHandler { call, result in
      guard call.method == "sample" else {
        result(FlutterMethodNotImplemented)
        return
      }
      AppPerformanceSampler.sample(result)
    }
    // Sends a downloaded file through the system share sheet.
    let share = FlutterMethodChannel(
      name: "ai_music/share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    share.setMethodCallHandler { call, result in
      guard call.method == "file" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(code: "invalid_file", message: "File is unavailable", details: nil))
        return
      }
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      var presenter = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
      while let presented = presenter?.presentedViewController { presenter = presented }
      guard let host = presenter else {
        result(FlutterError(code: "no_window", message: "No window to present from", details: nil))
        return
      }
      let sheet = UIActivityViewController(
        activityItems: [URL(fileURLWithPath: path)],
        applicationActivities: nil
      )
      // iPad presents this as a popover and needs an anchor.
      sheet.popoverPresentationController?.sourceView = host.view
      sheet.popoverPresentationController?.sourceRect = CGRect(
        x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0
      )
      host.present(sheet, animated: true) { result(nil) }
    }
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

private enum AppPerformanceSampler {
  private static let queue = DispatchQueue(label: "ai_music.performance", qos: .utility)

  static func sample(_ result: @escaping FlutterResult) {
    queue.async {
      var memory = mach_task_basic_info()
      var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
      let status = withUnsafeMutablePointer(to: &memory) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
      }
      var usage = rusage()
      guard status == KERN_SUCCESS, getrusage(RUSAGE_SELF, &usage) == 0 else {
        DispatchQueue.main.async {
          result(FlutterError(code: "performance_unavailable", message: "Process counters are unavailable", details: nil))
        }
        return
      }
      let cpuMs = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
      let counters: [String: Any] = [
        "cpuTimeMs": cpuMs,
        "elapsedTimeMs": ProcessInfo.processInfo.systemUptime * 1000,
        "memoryBytes": memory.resident_size,
        "memoryKind": "RSS",
      ]
      DispatchQueue.main.async { result(counters) }
    }
  }
}
