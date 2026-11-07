import Flutter
import UIKit

// Real UIKit navigation chrome over the single Flutter view.
//
// The window's root is `MusicShellController`. Under it sit two full-size
// children: the Flutter view controller (all content) and a
// `UITabBarController` whose tabs are `UINavigationController`s holding
// transparent `ShellPageController`s. UIKit draws the tab bar, navigation
// bars, buttons and menus, moves them into the vertical bar on iPhone Duo,
// and keeps them clear of the camera and the fold. Touches that land on the
// transparent page views go to Flutter; the pages' safe area is forwarded to
// Flutter as `additionalSafeAreaInsets`, so content avoids the bars.
final class MusicShellController: UIViewController, UITabBarControllerDelegate,
  UINavigationControllerDelegate
{
  let flutter: FlutterViewController
  let tabs = UITabBarController()
  private(set) var channel: FlutterMethodChannel?
  private var pages: [Int: ShellPageController] = [:]
  private var roots: [ShellPageController] = []
  private var poppedByFlutter = Set<Int>()
  private var theme = ShellTheme()
  private var modalDepth = 0
  private var lastInsets = UIEdgeInsets(top: -1, left: -1, bottom: -1, right: -1)

  init(flutter: FlutterViewController) {
    self.flutter = flutter
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func loadView() {
    let view = ShellView(frame: UIScreen.main.bounds)
    view.shell = self
    self.view = view
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    addChild(flutter)
    flutter.view.frame = view.bounds
    flutter.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(flutter.view)
    flutter.didMove(toParent: self)

    for index in 0..<4 {
      let root = ShellPageController(id: -(index + 1), shell: self)
      root.isRoot = true
      roots.append(root)
      let nav = UINavigationController(rootViewController: root)
      nav.delegate = self
      nav.view.backgroundColor = .clear
      nav.navigationBar.prefersLargeTitles = true
      nav.tabBarItem = UITabBarItem(title: nil, image: nil, tag: index)
      roots[index].navigationItem.largeTitleDisplayMode = .always
      tabs.addChild(nav)
    }
    tabs.viewControllers = tabs.children
    tabs.delegate = self
    tabs.view.backgroundColor = .clear
    addChild(tabs)
    tabs.view.frame = view.bounds
    tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(tabs.view)
    tabs.didMove(toParent: self)
    applyTheme()

    let channel = FlutterMethodChannel(name: "ai_music/shell", binaryMessenger: flutter.binaryMessenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      self.handle(call, result: result)
    }
  }

  override var childForStatusBarStyle: UIViewController? { tabs }
  override var childForStatusBarHidden: UIViewController? { tabs }
  override var childForHomeIndicatorAutoHidden: UIViewController? { tabs }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    syncInsets()
  }

  // MARK: - Flutter → shell

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "hello":
      result(true)
    case "theme":
      theme = ShellTheme(args)
      applyTheme()
      result(nil)
    case "tabs":
      configureTabs(args)
      result(nil)
    case "select":
      if let index = args["index"] as? Int, index >= 0, index < roots.count, tabs.selectedIndex != index {
        tabs.selectedIndex = index
        syncInsets()
      }
      result(nil)
    case "page":
      if let id = args["id"] as? Int {
        page(for: id)?.apply(ShellPageSpec(args["spec"] as? [String: Any] ?? [:]), theme: theme)
        syncInsets()
      }
      result(nil)
    case "push":
      if let id = args["id"] as? Int { push(id: id, spec: ShellPageSpec(args["spec"] as? [String: Any] ?? [:])) }
      result(nil)
    case "pop":
      if let id = args["id"] as? Int { pop(id: id) }
      result(nil)
    case "modal":
      setModal(args["active"] as? Bool ?? false)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var currentNavigation: UINavigationController? {
    tabs.selectedViewController as? UINavigationController
  }

  /// The page currently showing in the selected tab.
  private var visiblePage: ShellPageController? {
    currentNavigation?.topViewController as? ShellPageController
  }

  private func page(for id: Int) -> ShellPageController? {
    // Ids below zero address the root of a tab; the home route is id 0 and
    // lives in whichever tab is selected.
    if id <= 0 { return roots[min(roots.count - 1, max(0, tabs.selectedIndex))] }
    return pages[id]
  }

  private func configureTabs(_ args: [String: Any]) {
    let items = args["items"] as? [[String: Any]] ?? []
    for (index, nav) in tabs.children.enumerated() {
      guard index < items.count else { continue }
      let item = items[index]
      let title = item["title"] as? String
      let image = ShellPageSpec.image(symbol: item["symbol"] as? String, glyph: item["glyph"] as? FlutterStandardTypedData)
      let selected = ShellPageSpec.image(symbol: item["selectedSymbol"] as? String, glyph: nil) ?? image
      let bar = UITabBarItem(title: title, image: image, selectedImage: selected)
      bar.badgeValue = item["badge"] as? String
      nav.tabBarItem = bar
    }
    if let selected = args["selected"] as? Int, selected >= 0, selected < roots.count,
      tabs.selectedIndex != selected
    {
      tabs.selectedIndex = selected
    }
    if let spec = args["spec"] as? [String: Any] {
      roots[tabs.selectedIndex].apply(ShellPageSpec(spec), theme: theme)
    }
    syncInsets()
  }

  private func push(id: Int, spec: ShellPageSpec) {
    guard let nav = currentNavigation, pages[id] == nil else { return }
    let page = ShellPageController(id: id, shell: self)
    page.apply(spec, theme: theme)
    page.hidesBottomBarWhenPushed = spec.immersive
    pages[id] = page
    nav.pushViewController(page, animated: true)
    nav.view.layoutIfNeeded()
    syncInsets()
  }

  private func pop(id: Int) {
    guard let page = pages.removeValue(forKey: id) else { return }
    poppedByFlutter.insert(id)
    guard let nav = page.navigationController else { return }
    if nav.topViewController === page {
      nav.popViewController(animated: nav === currentNavigation)
    } else {
      nav.setViewControllers(nav.viewControllers.filter { $0 !== page }, animated: false)
    }
    syncInsets()
  }

  /// Flutter sheets and dialogs cover the content; the bars step aside like
  /// they do under a system sheet, and the content keeps its layout meanwhile.
  private func setModal(_ active: Bool) {
    modalDepth = max(0, modalDepth + (active ? 1 : -1))
    let hidden = modalDepth > 0
    for case let nav as UINavigationController in tabs.children {
      nav.setNavigationBarHidden(hidden || (nav.topViewController as? ShellPageController)?.spec.chromeless == true, animated: true)
    }
    if #available(iOS 18.0, *) {
      tabs.setTabBarHidden(hidden || visiblePage?.hidesBottomBarWhenPushed == true, animated: true)
    } else {
      tabs.tabBar.isHidden = hidden
    }
    if !hidden { syncInsets() }
  }

  // MARK: - Shell → Flutter

  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    channel?.invokeMethod("tabSelected", arguments: ["index": tabBarController.selectedIndex])
    syncInsets()
  }

  func navigationController(
    _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
  ) {
    // Anything we pushed that UIKit no longer holds was popped by the person:
    // the back button, the edge swipe or a long-press jump.
    let gone = pages.filter { $0.value.navigationController == nil && !poppedByFlutter.contains($0.key) }
    for (id, _) in gone.sorted(by: { $0.key > $1.key }) {
      pages[id] = nil
      channel?.invokeMethod("popped", arguments: ["id": id])
    }
    poppedByFlutter = poppedByFlutter.filter { pages[$0] != nil }
    syncInsets()
  }

  func perform(action id: String) {
    channel?.invokeMethod("action", arguments: ["id": id])
  }

  // MARK: - Geometry

  /// The visible page's safe area, less what the window already gives the
  /// Flutter view, becomes Flutter's extra padding.
  func syncInsets() {
    guard modalDepth == 0, let page = visiblePage, page.isViewLoaded, page.view.window != nil,
      page.transitionCoordinator == nil || page.navigationController?.topViewController === page
    else { return }
    let want = page.view.safeAreaInsets
    // The window's own safe area (status bar, home indicator, Duo strips).
    // Not the Flutter view's: that already carries the extra we add here.
    let have = view.safeAreaInsets
    let extra = UIEdgeInsets(
      top: max(0, want.top - have.top),
      left: max(0, want.left - have.left),
      bottom: max(0, want.bottom - have.bottom),
      right: max(0, want.right - have.right)
    )
    guard extra != lastInsets else { return }
    lastInsets = extra
    flutter.additionalSafeAreaInsets = extra
  }

  // MARK: - Appearance

  private func applyTheme() {
    overrideUserInterfaceStyle = theme.dark ? .dark : .light
    // Tint inherits down the view tree; set it at the top so the vertical
    // bar's items pick it up as well as the horizontal bars.
    view.tintColor = theme.tint
    tabs.view.tintColor = theme.tint
    tabs.tabBar.tintColor = theme.tint
    for case let nav as UINavigationController in tabs.children {
      nav.view.tintColor = theme.tint
      nav.navigationBar.tintColor = theme.tint
      let appearance = UINavigationBarAppearance()
      appearance.configureWithTransparentBackground()
      appearance.titleTextAttributes = [.foregroundColor: theme.text]
      appearance.largeTitleTextAttributes = [
        .foregroundColor: theme.text,
        .font: theme.largeTitleFont,
      ]
      nav.navigationBar.standardAppearance = appearance
      nav.navigationBar.scrollEdgeAppearance = appearance
      nav.navigationBar.compactAppearance = appearance
      for case let page as ShellPageController in nav.viewControllers {
        page.apply(page.spec, theme: theme)
        page.setNeedsStatusBarAppearanceUpdate()
      }
    }
  }

  var statusBarStyle: UIStatusBarStyle { theme.dark ? .lightContent : .darkContent }

  /// Views that only exist to hold the chrome. Touches on them belong to the
  /// Flutter content underneath.
  func isPassive(_ view: UIView) -> Bool {
    if view is ShellPassView || view === tabs.view { return true }
    for nav in tabs.children where view === nav.view { return true }
    return Self.passiveClassNames.contains(NSStringFromClass(type(of: view)))
  }

  private static let passiveClassNames: Set<String> = [
    "UILayoutContainerView", "UINavigationTransitionView", "UIViewControllerWrapperView",
    "UITransitionView", "UIDropShadowView", "_UIParallaxDimmingView",
  ]
}

/// Routes content touches to Flutter and chrome touches to UIKit.
final class ShellView: UIView {
  weak var shell: MusicShellController?

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let hit = super.hitTest(point, with: event) else { return nil }
    guard let shell, let flutterView = shell.flutter.view else { return hit }
    if hit === self || shell.isPassive(hit) {
      return flutterView.hitTest(flutterView.convert(point, from: self), with: event)
    }
    return hit
  }
}

/// A page's transparent stand-in inside the navigation controller. It is a
/// scroll view that never scrolls: UIKit looks for one at the top of the
/// content to decide that a large title may be shown expanded.
final class ShellPassView: UIScrollView {
  override func layoutSubviews() {
    super.layoutSubviews()
    if contentSize != bounds.size { contentSize = bounds.size }
  }
}

final class ShellPageController: UIViewController {
  let id: Int
  var isRoot = false
  private(set) var spec = ShellPageSpec([:])
  private weak var shell: MusicShellController?

  init(id: Int, shell: MusicShellController) {
    self.id = id
    self.shell = shell
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func loadView() {
    let view = ShellPassView()
    view.backgroundColor = .clear
    view.isScrollEnabled = false
    view.showsVerticalScrollIndicator = false
    view.showsHorizontalScrollIndicator = false
    self.view = view
  }

  override var preferredStatusBarStyle: UIStatusBarStyle { shell?.statusBarStyle ?? .default }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(spec.chromeless, animated: animated)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    shell?.syncInsets()
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    shell?.syncInsets()
  }

  func apply(_ spec: ShellPageSpec, theme: ShellTheme) {
    self.spec = spec
    navigationItem.title = spec.title
    navigationItem.largeTitleDisplayMode = isRoot && !spec.immersive && spec.title != nil ? .always : .never
    navigationItem.hidesBackButton = spec.hidesBack
    navigationItem.leftItemsSupplementBackButton = false
    navigationItem.leftBarButtonItems = spec.leading.map { [$0.barButton(shell: shell)] }
    navigationItem.rightBarButtonItems = spec.actions.reversed().map { $0.barButton(shell: shell) }
    if isViewLoaded, let nav = navigationController, nav.topViewController === self {
      nav.setNavigationBarHidden(spec.chromeless, animated: false)
    }
  }
}

struct ShellTheme {
  var dark = true
  var tint = UIColor.systemOrange
  var text = UIColor.label
  var fontName: String? = "BodoniSvtyTwoITCTT-Bold"

  init() {}

  init(_ args: [String: Any]) {
    dark = args["dark"] as? Bool ?? true
    if let argb = args["tint"] as? Int { tint = UIColor(argb: argb) }
    if let argb = args["text"] as? Int { text = UIColor(argb: argb) }
    fontName = args["font"] as? String ?? fontName
  }

  var largeTitleFont: UIFont {
    let size: CGFloat = 32
    if let name = fontName, let font = UIFont(name: name, size: size) { return font }
    return UIFont.systemFont(ofSize: size, weight: .bold)
  }
}

struct ShellAction {
  let id: String
  let title: String
  let symbol: String?
  let glyph: FlutterStandardTypedData?
  let enabled: Bool
  let prominent: Bool
  let menu: [ShellMenuEntry]

  init(_ raw: [String: Any]) {
    id = raw["id"] as? String ?? ""
    title = raw["title"] as? String ?? ""
    symbol = raw["symbol"] as? String
    glyph = raw["glyph"] as? FlutterStandardTypedData
    enabled = raw["enabled"] as? Bool ?? true
    prominent = raw["prominent"] as? Bool ?? false
    menu = (raw["menu"] as? [[String: Any]] ?? []).map(ShellMenuEntry.init)
  }

  func barButton(shell: MusicShellController?) -> UIBarButtonItem {
    let image = ShellPageSpec.image(symbol: symbol, glyph: glyph)
    let item: UIBarButtonItem
    if !menu.isEmpty {
      let actions = menu.map { entry -> UIMenuElement in
        let action = UIAction(
          title: entry.title,
          image: ShellPageSpec.image(symbol: entry.symbol, glyph: nil),
          attributes: entry.enabled ? [] : .disabled,
          state: entry.checked ? .on : .off
        ) { [weak shell] _ in shell?.perform(action: entry.id) }
        return action
      }
      item = image != nil
        ? UIBarButtonItem(image: image, menu: UIMenu(children: actions))
        : UIBarButtonItem(title: title, menu: UIMenu(children: actions))
    } else {
      let primary = UIAction(title: title, image: nil) { [weak shell] _ in shell?.perform(action: id) }
      if let image {
        item = UIBarButtonItem(image: image, primaryAction: primary)
      } else {
        item = UIBarButtonItem(title: title, primaryAction: primary)
        item.style = prominent ? .done : .plain
      }
    }
    item.isEnabled = enabled
    item.accessibilityLabel = title
    // The vertical bar shows symbols only and names them in its overflow menu.
    item.title = title
    if image != nil { item.image = image }
    return item
  }
}

struct ShellMenuEntry {
  let id: String
  let title: String
  let symbol: String?
  let enabled: Bool
  let checked: Bool

  init(_ raw: [String: Any]) {
    id = raw["id"] as? String ?? ""
    title = raw["title"] as? String ?? ""
    symbol = raw["symbol"] as? String
    enabled = raw["enabled"] as? Bool ?? true
    checked = raw["checked"] as? Bool ?? false
  }
}

struct ShellPageSpec {
  let title: String?
  let immersive: Bool
  /// The page draws its own Flutter bar; UIKit shows nothing for it.
  let chromeless: Bool
  let hidesBack: Bool
  let leading: ShellAction?
  let actions: [ShellAction]

  init(_ raw: [String: Any]) {
    title = raw["title"] as? String
    immersive = raw["immersive"] as? Bool ?? false
    chromeless = raw["chromeless"] as? Bool ?? false
    hidesBack = raw["hidesBack"] as? Bool ?? false
    leading = (raw["leading"] as? [String: Any]).map(ShellAction.init)
    actions = (raw["actions"] as? [[String: Any]] ?? []).map(ShellAction.init)
  }

  static func image(symbol: String?, glyph: FlutterStandardTypedData?) -> UIImage? {
    if let symbol, let image = UIImage(systemName: symbol) { return image }
    if let glyph, let image = UIImage(data: glyph.data, scale: 3) {
      return image.withRenderingMode(.alwaysTemplate)
    }
    return nil
  }
}

extension UIColor {
  convenience init(argb: Int) {
    self.init(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
