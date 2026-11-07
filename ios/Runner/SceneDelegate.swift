import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {}

// Bridge window-local geometry, never device names or fixed screen dimensions.
class DuoFlutterViewController: FlutterViewController {
  private var regions: FlutterMethodChannel?
  private var probe: MusicRegionProbe?

  override func viewDidLoad() {
    super.viewDidLoad()
    let channel = FlutterMethodChannel(name: "ai_music/window_regions", binaryMessenger: binaryMessenger)
    regions = channel
    let probe = MusicRegionProbe(frame: view.bounds)
    probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    probe.isUserInteractionEnabled = false
    probe.backgroundColor = .clear
    probe.changed = { [weak channel] value in
      channel?.invokeMethod("changed", arguments: value)
    }
    self.probe = probe
    view.addSubview(probe)
    probe.setNeedsUpdateConstraints()
    if #available(iOS 27.1, *) {
      probe.registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
        (view: MusicRegionProbe, _: UITraitCollection) in
        view.setNeedsUpdateConstraints()
        view.setNeedsLayout()
      }
    }
    channel.setMethodCallHandler { [weak probe] call, result in
      guard call.method == "snapshot" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(probe?.snapshot() ?? [:])
    }
  }
}

private class MusicRegionProbe: UIView {
  var changed: (([String: Any]) -> Void)?
  private var previous: NSDictionary?

  func snapshot() -> [String: Any] {
    var regions = [[String: Any]]()
    if #available(iOS 27.1, *) {
      for (kind, name) in [(UIView.ReservedRegion.Kind.occlusion, "occlusion"), (.division, "division")] {
        for region in reservedRegions(kind: kind) where region.isActive {
          let rect = region.frame // Already includes Apple's interactive margins.
          regions.append(["kind": name, "x": rect.minX, "y": rect.minY,
                          "width": rect.width, "height": rect.height])
        }
      }
    }
    var edge = "none"
    if #available(iOS 27.1, *) {
      switch traitCollection.verticalBarEdge {
      case .leading: edge = "left"
      case .trailing: edge = "right"
      default: break
      }
    }
    // The status bar is a small rectangle within the vertical strip; do not
    // turn its safe-area inset into a full-height empty column.
    if let window, let manager = window.windowScene?.statusBarManager,
       !manager.isStatusBarHidden {
      let rect = convert(manager.statusBarFrame, from: window.screen.coordinateSpace)
      regions.append(["kind": "status", "x": rect.minX, "y": rect.minY,
                      "width": rect.width, "height": rect.height])
    }
    return ["width": bounds.width, "height": bounds.height,
            "verticalBarEdge": edge, "regions": regions]
  }

  private func publish() {
    let value = snapshot()
    let next = value as NSDictionary
    guard previous != next else { return }
    previous = next
    // Flutter handles this outside UIKit's constraint update pass.
    DispatchQueue.main.async { [weak self] in self?.changed?(value) }
  }

  override func updateConstraints() {
    // UIKit re-runs this method when the queried reserved regions change,
    // including a partial fold that doesn't change the window's bounds.
    publish()
    super.updateConstraints()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    publish()
  }
}
