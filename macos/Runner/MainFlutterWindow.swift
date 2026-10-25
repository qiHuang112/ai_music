import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var sharingPicker: NSSharingServicePicker?
  private var navigationChannel: FlutterMethodChannel?

  /// The traffic lights sit inside the Flutter sidebar's glass panel: the
  /// close button's left edge and the row's centre, from the window's top left.
  private let lightsLeading: CGFloat = 26
  private let lightsCenterY: CGFloat = 28
  private var placingLights = false

  /// Mini player mode: the same window, shrunk, floating and without lights.
  /// Its two heights: the strip and the square.
  private static let miniStrip: CGFloat = 52
  private static let miniSquare: CGFloat = 336
  private var mini = false
  private var miniOnTop = true
  private var fullFrame: NSRect?
  private var fullMinSize = NSSize(width: 760, height: 600)
  private var miniTopLeft: NSPoint?

  private var titlebarInset: CGFloat {
    styleMask.contains(.fullScreen) || mini ? 0 : max(0, frame.height - contentLayoutRect.height)
  }

  private var lights: [NSButton] {
    [.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
  }

  /// Moves the lights into the sidebar panel and narrows the titlebar to
  /// them. The rest of the top edge then belongs to Flutter, which drags and
  /// zooms the window itself. AppKit lays the titlebar out again on resizes
  /// and appearance changes, so this runs after each of those.
  private func placeTrafficLights() {
    guard !placingLights, !mini, !styleMask.contains(.fullScreen),
          let close = standardWindowButton(.closeButton),
          let zoom = standardWindowButton(.zoomButton),
          let titlebar = close.superview,
          let container = titlebar.superview else { return }
    placingLights = true
    defer { placingLights = false }
    let spacing: CGFloat = 20
    let height = lightsCenterY + close.frame.height / 2 + 8
    let width = lightsLeading + spacing * 2 + zoom.frame.width + 10
    let target = NSRect(x: 0, y: frame.height - height, width: width, height: height)
    if container.frame != target { container.frame = target }
    if titlebar.frame != container.bounds { titlebar.frame = container.bounds }
    // Shrunk, the titlebar would paint its own pale backdrop in the corner
    // outside the panel; only the lights may show.
    hideTitlebarBackground(in: container)
    for (i, button) in lights.enumerated() {
      let y = titlebar.isFlipped
        ? lightsCenterY - button.frame.height / 2
        : height - lightsCenterY - button.frame.height / 2
      let origin = NSPoint(x: lightsLeading + CGFloat(i) * spacing, y: y)
      if button.frame.origin != origin { button.setFrameOrigin(origin) }
    }
  }

  private func hideTitlebarBackground(in view: NSView) {
    for child in view.subviews where !(child is NSButton) {
      let name = String(describing: type(of: child))
      // The titlebar's material, its decoration (the shading and line under
      // a normal titlebar) and a plain backing view.
      if child is NSVisualEffectView || name.contains("Background")
        || name.contains("Decoration") || type(of: child) == NSView.self {
        child.isHidden = true
      } else {
        hideTitlebarBackground(in: child)
      }
    }
  }

  @objc private func titlebarMoved(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in self?.placeTrafficLights() }
  }

  private func reportInset() {
    navigationChannel?.invokeMethod("titlebarInset", arguments: titlebarInset)
  }

  func windowDidResize(_ notification: Notification) {
    hideTooltip()
    placeTrafficLights()
    reportInset()
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard mini else { return }
    let square = frame.height > (Self.miniStrip + Self.miniSquare) / 2
    resizeMini(size: NSSize(width: frame.width, height: square ? Self.miniSquare : Self.miniStrip))
    navigationChannel?.invokeMethod("miniShape", arguments: square)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    placeTrafficLights()
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    reportInset()
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    placeTrafficLights()
    reportInset()
  }

  /// Zoom fills the screen's usable area (above the Dock, below the menu
  /// bar) and zooming again returns to the earlier size. It never enters
  /// full screen.
  func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
    (window.screen ?? NSScreen.main)?.visibleFrame ?? newFrame
  }

  private func enterMini(size: NSSize) {
    guard !styleMask.contains(.fullScreen) else { return }
    if mini {
      resizeMini(size: size)
      return
    }
    mini = true
    fullFrame = frame
    fullMinSize = contentMinSize
    lights.forEach { $0.isHidden = true }
    level = miniOnTop ? .floating : .normal
    // Like NetEase's: only the height changes, between the strip and the
    // square, and a drag of the edge snaps to whichever is nearer.
    contentMinSize = NSSize(width: size.width, height: Self.miniStrip)
    contentMaxSize = NSSize(width: size.width, height: Self.miniSquare)
    let visible = (screen ?? NSScreen.main)?.visibleFrame ?? frame
    let topLeft = miniTopLeft ?? NSPoint(x: visible.maxX - size.width - 24, y: visible.maxY - 24)
    setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height),
             display: true, animate: true)
    reportInset()
  }

  /// Changes the mini player's height. A drag of the edge keeps the top in
  /// place; the cover and 词 grow and shrink it from its foot, as NetEase's.
  private func resizeMini(size: NSSize, fromBottom: Bool = false) {
    guard mini else { return }
    var rect = NSRect(x: frame.minX, y: fromBottom ? frame.minY : frame.maxY - size.height,
                      width: size.width, height: size.height)
    // Never past the menu bar or below the Dock.
    if let visible = (screen ?? NSScreen.main)?.visibleFrame {
      rect.origin.y = min(max(rect.minY, visible.minY), visible.maxY - rect.height)
    }
    setFrame(rect, display: true, animate: true)
  }

  private var tooltipPanel: NSPanel?

  /// A system-style tooltip for a control whose rect is given from the
  /// Flutter view's top left. Being its own small window, it can hang below
  /// the 52pt mini strip, where a Flutter tooltip would be cut off.
  private func showTooltip(text: String, rect: NSRect) {
    hideTooltip()
    guard let view = contentView, !text.isEmpty else { return }
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 12)
    label.textColor = .labelColor
    let textSize = label.fittingSize
    let size = NSSize(width: ceil(textSize.width) + 16, height: ceil(textSize.height) + 8)
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.level = .popUpMenu
    let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    material.material = .toolTip
    material.state = .active
    material.wantsLayer = true
    material.layer?.cornerRadius = 5
    material.layer?.masksToBounds = true
    label.frame = NSRect(x: 8, y: 4, width: ceil(textSize.width), height: ceil(textSize.height))
    material.addSubview(label)
    panel.contentView = material
    let local = NSRect(x: rect.minX,
                       y: view.isFlipped ? rect.minY : view.bounds.height - rect.maxY,
                       width: rect.width, height: rect.height)
    let anchor = convertToScreen(view.convert(local, to: nil))
    // Below the control, or above it when the screen ends.
    var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)
    if let visible = (screen ?? NSScreen.main)?.visibleFrame {
      if origin.y < visible.minY { origin.y = anchor.maxY + 6 }
      origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
    }
    panel.setFrameOrigin(origin)
    panel.orderFront(nil)
    tooltipPanel = panel
  }

  private func hideTooltip() {
    tooltipPanel?.orderOut(nil)
    tooltipPanel = nil
  }

  /// A native menu at a point given from the Flutter view's top left. It can
  /// reach past the edge of the small mini player window, as NetEase's does.
  private func popUpMenu(_ arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let view = contentView,
          let entries = arguments?["items"] as? [[String: Any]] else {
      result(nil)
      return
    }
    let picker = MenuPicker()
    let menu = NSMenu()
    menu.autoenablesItems = false
    for entry in entries {
      if entry["separator"] as? Bool == true {
        menu.addItem(.separator())
        continue
      }
      let item = NSMenuItem(title: entry["title"] as? String ?? "",
                            action: #selector(MenuPicker.pick(_:)), keyEquivalent: "")
      item.target = picker
      item.representedObject = entry["id"] as? String
      item.isEnabled = entry["enabled"] as? Bool ?? true
      item.state = entry["checked"] as? Bool == true ? .on : .off
      menu.addItem(item)
    }
    let x = arguments?["x"] as? Double ?? 0
    let top = arguments?["y"] as? Double ?? 0
    let point = NSPoint(x: x, y: view.isFlipped ? top : view.bounds.height - top)
    menu.popUp(positioning: nil, at: point, in: view)
    // The chosen item's action has run by the time the menu closes.
    DispatchQueue.main.async { result(picker.picked) }
  }

  private func exitMini() {
    guard mini else { return }
    hideTooltip()
    miniTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
    mini = false
    level = .normal
    contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    contentMinSize = fullMinSize
    lights.forEach { $0.isHidden = false }
    if let fullFrame = fullFrame {
      setFrame(fullFrame, display: true, animate: true)
    }
    placeTrafficLights()
    reportInset()
  }

  @objc private func openSearch(_ sender: Any?) {
    makeKeyAndOrderFront(nil)
    navigationChannel?.invokeMethod("search", arguments: nil)
  }

  @objc private func toggleMiniPlayer(_ sender: Any?) {
    makeKeyAndOrderFront(nil)
    navigationChannel?.invokeMethod("mini", arguments: nil)
  }

  @objc private func openSettings(_ sender: Any?) {
    makeKeyAndOrderFront(nil)
    navigationChannel?.invokeMethod("settings", arguments: nil)
  }
  func windowDidMove(_ notification: Notification) {
    hideTooltip()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideTooltip()
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
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      func size() -> NSSize {
        NSSize(width: arguments?["width"] as? Double ?? 360, height: arguments?["height"] as? Double ?? 380)
      }
      switch call.method {
      case "windowStyle":
        let dark = arguments?["dark"] as? Bool ?? false
        self.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        DispatchQueue.main.async { self.placeTrafficLights() }
        result(self.titlebarInset)
      case "startDrag":
        // The press that started the drag in Flutter is still the current event.
        if let event = self.currentEvent { self.performDrag(with: event) }
        result(nil)
      case "zoom":
        if !self.mini && !self.styleMask.contains(.fullScreen) { self.zoom(nil) }
        result(nil)
      case "enterMini":
        self.enterMini(size: size())
        result(nil)
      case "miniSize":
        self.resizeMini(size: size(), fromBottom: arguments?["fromBottom"] as? Bool ?? false)
        result(nil)
      case "popupMenu":
        self.hideTooltip()
        self.popUpMenu(arguments, result: result)
      case "showTooltip":
        self.showTooltip(
          text: arguments?["text"] as? String ?? "",
          rect: NSRect(x: arguments?["x"] as? Double ?? 0, y: arguments?["y"] as? Double ?? 0,
                       width: arguments?["width"] as? Double ?? 0, height: arguments?["height"] as? Double ?? 0))
        result(nil)
      case "hideTooltip":
        self.hideTooltip()
        result(nil)
      case "exitMini":
        self.exitMini()
        result(nil)
      case "alwaysOnTop":
        self.miniOnTop = call.arguments as? Bool ?? true
        if self.mini { self.level = self.miniOnTop ? .floating : .normal }
        result(nil)
      case "close":
        self.performClose(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
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
      let miniPlayer = NSMenuItem(title: "迷你播放器", action: #selector(toggleMiniPlayer(_:)), keyEquivalent: "m")
      miniPlayer.keyEquivalentModifierMask = [.command, .shift]
      miniPlayer.target = self
      viewMenu.insertItem(miniPlayer, at: 1)
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
    if let container = standardWindowButton(.closeButton)?.superview?.superview {
      container.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(
        self, selector: #selector(titlebarMoved(_:)),
        name: NSView.frameDidChangeNotification, object: container)
    }
    placeTrafficLights()
  }
}

/// Receives the item picked from a native popup menu.
private class MenuPicker: NSObject {
  var picked: String?

  @objc func pick(_ sender: NSMenuItem) {
    picked = sender.representedObject as? String
  }
}
