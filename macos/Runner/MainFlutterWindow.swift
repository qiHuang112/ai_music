import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var sharingPicker: NSSharingServicePicker?
  private var navigationChannel: FlutterMethodChannel?

  private var titlebarInset: CGFloat {
    styleMask.contains(.fullScreen) ? 0 : max(0, frame.height - contentLayoutRect.height)
  }

  func windowDidResize(_ notification: Notification) {
    navigationChannel?.invokeMethod("titlebarInset", arguments: titlebarInset)
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    navigationChannel?.invokeMethod("titlebarInset", arguments: titlebarInset)
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    navigationChannel?.invokeMethod("titlebarInset", arguments: titlebarInset)
  }

  @objc private func openSearch(_ sender: Any?) {
    makeKeyAndOrderFront(nil)
    navigationChannel?.invokeMethod("search", arguments: nil)
  }

  @objc private func openSettings(_ sender: Any?) {
    makeKeyAndOrderFront(nil)
    navigationChannel?.invokeMethod("settings", arguments: nil)
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Keep Flutter and the audio session alive when only the window closes.
    orderOut(nil)
    return false
  }

  override func awakeFromNib() {
    // Let the Flutter skin paint behind the native traffic lights and drag area.
    styleMask.insert(.fullSizeContentView)
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    if #available(macOS 11.0, *) {
      titlebarSeparatorStyle = .none
    }
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1100, height: 780))
    self.contentMinSize = NSSize(width: 760, height: 600)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    navigationChannel = FlutterMethodChannel(name: "ai_music/desktop_navigation", binaryMessenger: flutterViewController.engine.binaryMessenger)
    navigationChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "windowStyle", let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let dark = (call.arguments as? [String: Any])?["dark"] as? Bool ?? false
      self.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      result(self.titlebarInset)
    }
    if let applicationMenu = NSApp.mainMenu?.items.first?.submenu,
       let settings = applicationMenu.items.first(where: { $0.keyEquivalent == "," }) {
      settings.title = "设置…"
      settings.target = self
      settings.action = #selector(openSettings(_:))
    }
    if let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu {
      let search = NSMenuItem(title: "搜索音乐…", action: #selector(openSearch(_:)), keyEquivalent: "k")
      search.target = self
      viewMenu.insertItem(search, at: 0)
    }

    let sharingChannel = FlutterMethodChannel(name: "ai_music/share", binaryMessenger: flutterViewController.engine.binaryMessenger)
    sharingChannel.setMethodCallHandler { [weak self, weak flutterViewController] call, result in
      guard call.method == "file" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String,
            FileManager.default.fileExists(atPath: path),
            let view = flutterViewController?.view,
            let self = self else {
        result(FlutterError(code: "unavailable", message: "File is unavailable", details: nil))
        return
      }
      self.sharingPicker = NSSharingServicePicker(items: [URL(fileURLWithPath: path)])
      self.sharingPicker?.show(relativeTo: NSRect(x: view.bounds.midX, y: 60, width: 1, height: 1), of: view, preferredEdge: .minY)
      result(nil)
    }

    super.awakeFromNib()
    delegate = self
  }
}
