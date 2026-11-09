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
  private let nowPlayingBar = ShellNowPlayingBar()
  private var barShown = false
  private var lastInsets = UIEdgeInsets(top: -1, left: -1, bottom: -1, right: -1)
  private var lastMastheadTop: CGFloat?

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
      nav.tabBarItem = UITabBarItem(title: nil, image: nil, tag: index)
      roots[index].navigationItem.largeTitleDisplayMode = .never
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
    // The now-playing bar floats over the content, above the tab bar and
    // clear of the vertical strip, in the system glass material.
    nowPlayingBar.isHidden = true
    nowPlayingBar.onAction = { [weak self] action in self?.perform(action: "shell.player.\(action)") }
    view.addSubview(nowPlayingBar)

    if #available(iOS 27.1, *) {
      registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
        (shell: MusicShellController, _: UITraitCollection) in
        shell.reapplyPages()
        shell.refreshBar()
      }
    }

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
    layoutBar()
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
    case "nowPlaying":
      updateNowPlaying(args)
      result(nil)
    case "sharedGlyphs":
      lyricsGlyph = args["lyrics"] as? FlutterStandardTypedData
      reapplyPages()
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
      nav.setNavigationBarHidden(hidden || (nav.topViewController as? ShellPageController)?.hidesBar == true, animated: true)
    }
    if #available(iOS 18.0, *) {
      tabs.setTabBarHidden(hidden || visiblePage?.hidesBottomBarWhenPushed == true, animated: true)
    } else {
      tabs.tabBar.isHidden = hidden
    }
    if !hidden { syncInsets() }
  }

  // MARK: - Now playing

  /// Feeds the floating bar; it shows whenever something is loaded and the
  /// visible page is not immersive (the player draws its own controls).
  private func updateNowPlaying(_ args: [String: Any]) {
    nowPlayingPresent = args["present"] as? Bool ?? false
    nowPlayingBar.update(
      title: args["title"] as? String ?? "",
      artist: args["artist"] as? String ?? "",
      playing: args["playing"] as? Bool ?? false,
      favorite: args["favorite"] as? Bool ?? false,
      artwork: (args["art"] as? FlutterStandardTypedData).flatMap { UIImage(data: $0.data, scale: 3) }
    )
    refreshBar()
  }

  private var nowPlayingPresent = false

  /// The app's own lyrics glyph, sent once by Flutter: no SF Symbol reads as
  /// lyrics (the quote bubble looked like the comments beside it).
  private var lyricsGlyph: FlutterStandardTypedData?

  /// With the bars in a vertical strip, lyrics, comments and the queue are
  /// reachable from every page, under that page's own controls.
  var sharedActions: [ShellAction] {
    guard nowPlayingPresent, verticalBarActive else { return [] }
    return [
      ShellAction(id: "shell.player.lyrics", title: "歌词", symbol: lyricsGlyph == nil ? "text.alignleft" : nil, glyph: lyricsGlyph),
      ShellAction(id: "shell.player.comments", title: "歌曲热评", symbol: "bubble.left"),
      ShellAction(id: "shell.player.queue", title: "当前队列", symbol: "list.bullet"),
    ]
  }

  private var verticalBarActive: Bool {
    if #available(iOS 27.1, *) {
      switch traitCollection.verticalBarEdge {
      case .leading, .trailing: return true
      default: return false
      }
    }
    return false
  }

  /// How many buttons the vertical strip holds for this page beside its back
  /// button and the tabs; nil without a strip. Measured on iPhone Duo: a
  /// button takes 50pt, the camera (and, upright, the clock) the top, the
  /// tab group with its margins 252pt at the bottom.
  func verticalSlots(for page: ShellPageController) -> Int? {
    guard verticalBarActive else { return nil }
    let size = view.bounds.size
    let top: CGFloat = size.height > size.width ? 175 : 82
    // UIKit keeps the tabs hidden above any page in the stack that hid them
    // (pages pushed from the player).
    var stack = page.navigationController?.viewControllers ?? currentNavigation?.viewControllers ?? []
    if let index = stack.firstIndex(of: page) { stack = Array(stack[...index]) }
    let tabsHidden = page.spec.immersive || stack.contains { $0.hidesBottomBarWhenPushed }
    let tabs: CGFloat = tabsHidden ? 24 : 252
    let back: CGFloat = page.isRoot || page.spec.hidesBack ? 0 : 64
    return max(0, Int((size.height - top - tabs - back) / 50))
  }

  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.reapplyPages() }
  }

  /// Re-applies every page so shared actions follow the bar's edge and the
  /// playing state.
  private func reapplyPages() {
    for case let nav as UINavigationController in tabs.children {
      for case let page as ShellPageController in nav.viewControllers {
        page.apply(page.spec, theme: theme)
      }
    }
  }

  private var sharedActionsShown = false

  private func refreshBar() {
    let sharing = !sharedActions.isEmpty
    if sharing != sharedActionsShown {
      sharedActionsShown = sharing
      reapplyPages()
    }
    // Immersive pages take the whole display: on a wide window the tab bar
    // sits at the top and would otherwise stay as a strip over the player.
    if #available(iOS 18.0, *), modalDepth == 0 {
      let immersive = visiblePage?.spec.immersive == true
      if tabs.isTabBarHidden != immersive {
        tabs.setTabBarHidden(immersive, animated: true)
      }
    }
    // Like QQ Music, the bar lives on the top-level tabs only; pushed pages
    // and the player keep the full width for themselves.
    let wanted = nowPlayingPresent && visiblePage?.isRoot == true && visiblePage?.spec.immersive != true
    if wanted != barShown {
      barShown = wanted
      nowPlayingBar.isHidden = !wanted
      channel?.invokeMethod("accessory", arguments: ["active": nowPlayingPresent])
    }
    layoutBar()
    syncInsets()
  }

  /// Centered in the content area (left of a vertical bar), above a horizontal
  /// tab bar: near full width on a phone, a long capsule on a wide window.
  /// The top of a visible horizontal tab bar, in the shell's coordinates;
  /// nil when the bar is hidden or has moved into the vertical strip.
  private var horizontalTabBarTop: CGFloat? {
    let bar = tabs.tabBar
    guard !bar.isHidden, bar.alpha > 0, bar.window != nil else { return nil }
    let frame = view.convert(bar.bounds, from: bar)
    guard frame.width > frame.height, frame.maxY > view.bounds.midY else { return nil }
    return frame.minY
  }

  /// The glass capsule the tab bar actually draws: it sits inset inside the
  /// full-width bar, and the now-playing bar lines up with it.
  private var tabBarCapsule: CGRect? {
    var union: CGRect?
    func walk(_ view: UIView) {
      for sub in view.subviews {
        let name = NSStringFromClass(type(of: sub))
        if name.contains("Platter"), sub.bounds.width > 100, sub.bounds.height > 30 {
          let frame = self.view.convert(sub.bounds, from: sub)
          union = union.map { $0.union(frame) } ?? frame
        } else {
          walk(sub)
        }
      }
    }
    walk(tabs.tabBar)
    return union
  }

  private func layoutBar() {
    // The window's own safe area, widened by the page's: in split view the
    // vertical strip sits inside the app's half and only the page's safe
    // area knows about it, as it does about a horizontal tab bar below.
    var insets = view.safeAreaInsets
    // Insets, not the page's frame: that slides during a push or pop.
    if let page = visiblePage, page.isViewLoaded {
      let safe = page.view.safeAreaInsets
      insets.left = max(insets.left, safe.left)
      insets.right = max(insets.right, safe.right)
      insets.bottom = max(insets.bottom, safe.bottom)
    }
    var tabBar: CGRect?
    if let top = horizontalTabBarTop {
      insets.bottom = max(insets.bottom, view.bounds.maxY - top)
      tabBar = tabBarCapsule ?? view.convert(tabs.tabBar.bounds, from: tabs.tabBar).insetBy(dx: 16, dy: 0)
    }
    let content = view.bounds.inset(by: insets)
    let wide = traitCollection.horizontalSizeClass == .regular
    var x: CGFloat
    var width: CGFloat
    if let tabBar, !wide {
      // Edge to edge with the tab bar's own capsule, so the two stack neatly.
      x = tabBar.minX
      width = tabBar.width
    } else {
      width = wide ? min(640, max(360, content.width * 0.6)) : content.width - 24
      x = content.midX - width / 2
    }
    // Never under a vertical strip, whichever way the width was found.
    let lane = content.insetBy(dx: 12, dy: 0)
    if lane.width > 0 {
      let minX = max(x, lane.minX)
      width = max(0, min(x + width, lane.maxX) - minX)
      x = minX
    }
    let frame = CGRect(
      x: x,
      y: content.maxY - ShellNowPlayingBar.gap - ShellNowPlayingBar.height,
      width: width,
      height: ShellNowPlayingBar.height
    )
    if nowPlayingBar.frame != frame { nowPlayingBar.frame = frame }
    nowPlayingBar.wide = wide
    view.bringSubviewToFront(nowPlayingBar)
  }

  // MARK: - Shell → Flutter

  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    channel?.invokeMethod("tabSelected", arguments: ["index": tabBarController.selectedIndex])
    refreshBar()
    syncInsets()
  }

  func navigationController(
    _ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool
  ) {
    // Give Flutter the destination's insets as the transition starts, so the
    // page it reveals is already laid out for them instead of jumping after.
    reportPopped(in: navigationController)
    refreshBar()
    navigationController.view.layoutIfNeeded()
    syncInsets()
  }

  func navigationController(
    _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
  ) {
    flushPopped()
    refreshBar()
    syncInsets()
  }

  /// Anything we pushed that UIKit no longer holds was popped by the person:
  /// the back button, the edge swipe or a long-press jump. Flutter learns of
  /// it as the transition starts, so its own slide runs together with
  /// UIKit's instead of after it (which read as going back twice). An edge
  /// swipe can still be cancelled, so that one waits for the finger to decide.
  /// Whether UIKit has let go of a page. During a pop the controller is still
  /// parented until the transition ends, so the stack is what tells.
  private func isGone(_ page: ShellPageController) -> Bool {
    guard let nav = page.navigationController else { return true }
    return !nav.viewControllers.contains(page)
  }

  private func reportPopped(in navigationController: UINavigationController) {
    guard pages.contains(where: { isGone($0.value) && !poppedByFlutter.contains($0.key) })
    else { return }
    if let coordinator = navigationController.transitionCoordinator, coordinator.isInteractive {
      coordinator.notifyWhenInteractionChanges { [weak self] context in
        guard let self, !context.isCancelled else { return }
        self.flushPopped()
      }
      return
    }
    flushPopped()
  }

  private func flushPopped() {
    let gone = pages.filter { isGone($0.value) && !poppedByFlutter.contains($0.key) }
    for (id, _) in gone.sorted(by: { $0.key > $1.key }) {
      pages[id] = nil
      channel?.invokeMethod("popped", arguments: ["id": id])
    }
    poppedByFlutter = poppedByFlutter.filter { pages[$0] != nil }
  }

  func perform(action id: String) {
    channel?.invokeMethod("action", arguments: ["id": id])
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    refreshBar()
  }

  // MARK: - Geometry

  /// The visible page's safe area, less what the window already gives the
  /// Flutter view, becomes Flutter's extra padding.
  func syncInsets() {
    guard modalDepth == 0, let page = visiblePage, page.isViewLoaded, page.view.window != nil,
      page.transitionCoordinator == nil || page.navigationController?.topViewController === page
    else { return }
    var want = page.view.safeAreaInsets
    if let top = horizontalTabBarTop {
      want.bottom = max(want.bottom, view.bounds.maxY - top)
    }
    // The window's own safe area (status bar, home indicator, Duo strips).
    // Not the Flutter view's: that already carries the extra we add here.
    let have = view.safeAreaInsets
    // Content also keeps clear of the floating now-playing bar.
    let bar = barShown ? ShellNowPlayingBar.height + ShellNowPlayingBar.gap * 2 : 0
    let extra = UIEdgeInsets(
      top: max(0, want.top - have.top),
      left: max(0, want.left - have.left),
      bottom: max(0, want.bottom - have.bottom) + bar,
      right: max(0, want.right - have.right)
    )
    // A horizontal navigation bar across the top: the root's masthead takes
    // its row. On an open Duo held upright it sits beside the clock, inside
    // the window's own top inset, so "below the safe area" left a gap.
    var mastheadTop: CGFloat?
    if let nav = page.navigationController, !nav.isNavigationBarHidden {
      let bar = view.convert(nav.navigationBar.bounds, from: nav.navigationBar)
      if bar.width > view.bounds.width / 2, bar.width > bar.height, bar.minY < view.bounds.midY {
        mastheadTop = max(0, bar.minY)
      }
    }
    guard extra != lastInsets || mastheadTop != lastMastheadTop else { return }
    lastInsets = extra
    lastMastheadTop = mastheadTop
    flutter.additionalSafeAreaInsets = extra
    // Root pages lay their masthead under the transparent bar; tell Flutter
    // how much of the inset is bar, and where the bar's row starts.
    var chrome: [String: Any] = ["top": extra.top, "bottom": extra.bottom]
    if let mastheadTop { chrome["mastheadTop"] = mastheadTop }
    channel?.invokeMethod("chrome", arguments: chrome)
  }

  // MARK: - Appearance

  private func applyTheme() {
    overrideUserInterfaceStyle = theme.dark ? .dark : .light
    // No bar background of its own anywhere: on a wide window the tab bar
    // moves to the top and would otherwise lay a dark strip over the skin.
    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithTransparentBackground()
    tabs.tabBar.standardAppearance = tabAppearance
    tabs.tabBar.scrollEdgeAppearance = tabAppearance
    // Tint inherits down the view tree; set it at the top so the vertical
    // bar's items pick it up as well as the horizontal bars.
    view.tintColor = theme.tint
    nowPlayingBar.tintColor = theme.tint
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

/// A page's transparent stand-in inside the navigation controller.
final class ShellPassView: UIView {}

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
    self.view = view
  }

  override var preferredStatusBarStyle: UIStatusBarStyle { shell?.statusBarStyle ?? .default }

  /// Only a page that draws its own Flutter bar hides the system one. Roots
  /// keep it (transparent, title-less) so pushes and pops never change the
  /// content inset; their masthead is drawn under it by Flutter.
  var hidesBar: Bool { spec.chromeless }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(hidesBar, animated: animated)
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
    navigationItem.largeTitleDisplayMode = .never
    navigationItem.hidesBackButton = spec.hidesBack
    navigationItem.leftItemsSupplementBackButton = false
    navigationItem.leftBarButtonItems = spec.leading.map { [$0.barButton(shell: shell)] }
    // Shared now-playing actions sit after the page's own, skipping any the
    // page already offers.
    var actions = spec.actions
    // In the vertical strip a menu of plain commands spreads into buttons of
    // its own when they all fit, instead of hiding behind "…".
    if let slots = shell?.verticalSlots(for: self), actions.contains(where: \.expandable) {
      let expanded = actions.flatMap { $0.expandable ? $0.menu.map(ShellAction.init(entry:)) : [$0] }
      let symbols = Set(expanded.compactMap(\.symbol))
      let extra = (shell?.sharedActions ?? []).filter {
        !symbols.contains($0.symbol ?? "") && !spec.hiddenShared.contains($0.id)
      }
      if expanded.count + extra.count + (spec.leading == nil ? 0 : 1) <= slots { actions = expanded }
    }
    let own = Set(actions.compactMap(\.symbol))
    var shared = (shell?.sharedActions ?? []).filter {
      !own.contains($0.symbol ?? "") && !spec.hiddenShared.contains($0.id)
    }
    // The shared entries only fill free slots: past that the strip would fold
    // the page's own buttons into "…" for shortcuts the bar also offers.
    if let slots = shell?.verticalSlots(for: self) {
      let room = max(0, slots - actions.count - (spec.leading == nil ? 0 : 1))
      shared = Array(shared.prefix(room))
    }
    navigationItem.rightBarButtonItems = (actions + shared).reversed().map { $0.barButton(shell: shell) }
    if isViewLoaded, let nav = navigationController, nav.topViewController === self {
      nav.setNavigationBarHidden(hidesBar, animated: false)
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

  init(id: String, title: String, symbol: String?, glyph: FlutterStandardTypedData? = nil) {
    self.id = id
    self.title = title
    self.symbol = symbol
    self.glyph = glyph
    enabled = true
    prominent = false
    menu = []
  }

  /// One entry of a menu, standing on its own.
  init(entry: ShellMenuEntry) {
    id = entry.id
    title = entry.title
    symbol = entry.symbol
    glyph = entry.glyph
    enabled = entry.enabled
    prominent = false
    menu = []
  }

  /// A menu of plain commands, each with an icon: no choice marks to keep.
  var expandable: Bool {
    !menu.isEmpty && menu.allSatisfy {
      !$0.checked && ShellPageSpec.image(symbol: $0.symbol, glyph: $0.glyph) != nil
    }
  }

  func barButton(shell: MusicShellController?) -> UIBarButtonItem {
    let image = ShellPageSpec.image(symbol: symbol, glyph: glyph)
    let item: UIBarButtonItem
    if !menu.isEmpty {
      let actions = menu.map { entry -> UIMenuElement in
        let action = UIAction(
          title: entry.title,
          image: ShellPageSpec.image(symbol: entry.symbol, glyph: entry.glyph),
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
  let glyph: FlutterStandardTypedData?
  let enabled: Bool
  let checked: Bool

  init(_ raw: [String: Any]) {
    id = raw["id"] as? String ?? ""
    title = raw["title"] as? String ?? ""
    symbol = raw["symbol"] as? String
    glyph = raw["glyph"] as? FlutterStandardTypedData
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
  /// Shared now-playing entries that would lead to this very page.
  let hiddenShared: Set<String>

  init(_ raw: [String: Any]) {
    hiddenShared = Set(raw["hideShared"] as? [String] ?? [])
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

/// The floating now-playing bar: cover, song, play/pause and the queue on the
/// system glass material; swiping changes the song.
final class ShellNowPlayingBar: UIView {
  static let height: CGFloat = 56
  static let gap: CGFloat = 12

  var onAction: ((String) -> Void)?

  /// A wide window shows the full transport; a phone keeps play and the queue.
  var wide = false {
    didSet { if wide != oldValue { setNeedsLayout() } }
  }

  private let glass: UIVisualEffectView = {
    if #available(iOS 26.0, *) {
      // Not the interactive variant: it claims touches, and the bar's own
      // drag and tap would never arrive. The press scale below stands in.
      return UIVisualEffectView(effect: UIGlassEffect())
    }
    return UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
  }()
  private let highlight = UIView()
  private let cover = UIImageView()
  private let title = UILabel()
  private let favorite = UIButton(type: .system)
  private let previous = UIButton(type: .system)
  private let toggle = UIButton(type: .system)
  private let skip = UIButton(type: .system)
  private let queue = UIButton(type: .system)
  private let lyrics = UIButton(type: .system)

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerCurve = .continuous
    clipsToBounds = true
    glass.frame = bounds
    glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(glass)
    highlight.frame = bounds
    highlight.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    highlight.backgroundColor = UIColor.label.withAlphaComponent(0.08)
    highlight.alpha = 0
    highlight.isUserInteractionEnabled = false
    glass.contentView.insertSubview(highlight, at: 0)

    cover.contentMode = .scaleAspectFill
    cover.clipsToBounds = true
    cover.layer.cornerRadius = 8
    cover.layer.cornerCurve = .continuous
    cover.backgroundColor = UIColor.secondarySystemFill
    title.font = .systemFont(ofSize: 15, weight: .semibold)
    title.textColor = .label
    title.lineBreakMode = .byTruncatingTail
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    title.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let symbols = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    func button(_ control: UIButton, _ name: String, _ action: String, _ label: String) {
      control.setImage(UIImage(systemName: name, withConfiguration: symbols), for: .normal)
      control.accessibilityLabel = label
      control.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
      control.widthAnchor.constraint(equalToConstant: 40).isActive = true
    }
    button(favorite, "heart", "favorite", "收藏")
    button(previous, "backward.end.fill", "previous", "上一首")
    button(toggle, "play.fill", "toggle", "播放")
    button(skip, "forward.end.fill", "next", "下一首")
    button(queue, "list.bullet", "queue", "当前队列")
    lyrics.isHidden = true

    // Only the song (cover and title) moves with a swipe; it slides inside
    // its own clipped lane so the buttons at the end hold still.
    let song = UIStackView(arrangedSubviews: [cover, title])
    self.song = song
    song.axis = .horizontal
    song.alignment = .center
    song.spacing = 12
    song.translatesAutoresizingMaskIntoConstraints = false
    let lane = UIView()
    lane.clipsToBounds = true
    lane.addSubview(song)
    lane.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    lane.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let row = UIStackView(arrangedSubviews: [lane, favorite, previous, toggle, skip, queue])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = 2
    row.setCustomSpacing(8, after: lane)
    row.translatesAutoresizingMaskIntoConstraints = false
    glass.contentView.addSubview(row)
    NSLayoutConstraint.activate([
      song.leadingAnchor.constraint(equalTo: lane.leadingAnchor),
      song.trailingAnchor.constraint(equalTo: lane.trailingAnchor),
      song.topAnchor.constraint(equalTo: lane.topAnchor),
      song.bottomAnchor.constraint(equalTo: lane.bottomAnchor),
      cover.widthAnchor.constraint(equalToConstant: 38),
      cover.heightAnchor.constraint(equalToConstant: 38),
      row.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 9),
      row.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -6),
      row.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor),
    ])
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))
    let pan = UIPanGestureRecognizer(target: self, action: #selector(swipe(_:)))
    pan.maximumNumberOfTouches = 1
    addGestureRecognizer(pan)
  }

  private var song: UIStackView?

  /// A horizontal drag on the bar changes the song, the way QQ Music's does:
  /// the song slides with the finger, leaves, and the next one comes in.
  @objc private func swipe(_ pan: UIPanGestureRecognizer) {
    guard let row = song else { return }
    let dx = pan.translation(in: self).x
    switch pan.state {
    case .changed:
      // Only a sideways drag moves the song; a mostly vertical one does not.
      let dy = pan.translation(in: self).y
      guard abs(dx) > abs(dy) * 0.8 else { return }
      row.transform = CGAffineTransform(translationX: dx * 0.6, y: 0)
    case .ended, .cancelled:
      let velocity = pan.velocity(in: self).x
      let direction: Int = dx <= -56 || velocity <= -400 ? -1 : (dx >= 56 || velocity >= 400 ? 1 : 0)
      if direction == 0 || pan.state == .cancelled {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3,
                       options: [.allowUserInteraction]) { row.transform = .identity }
        return
      }
      onAction?(direction < 0 ? "next" : "previous")
      let width = bounds.width
      UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
        row.transform = CGAffineTransform(translationX: CGFloat(direction) * width, y: 0)
        row.alpha = 0
      } completion: { _ in
        row.transform = CGAffineTransform(translationX: CGFloat(-direction) * width * 0.5, y: 0)
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction]) {
          row.transform = .identity
          row.alpha = 1
        }
      }
    default:
      break
    }
  }

  // Pressing the bar itself (not a button) lights it faintly, the way a
  // system row highlights. Its size never changes: a scale on this view
  // fought the shell's frame layout and the bar shook.
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    press(true)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    press(false)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesCancelled(touches, with: event)
    press(false)
  }

  private func press(_ down: Bool) {
    UIView.animate(
      withDuration: down ? 0.08 : 0.25, delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
    ) {
      self.highlight.alpha = down ? 1 : 0
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
    // Play and the queue only, folded or open: songs change by swiping the
    // bar. Extra buttons appearing on a wide window crowded the row while a
    // fold opened.
    favorite.isHidden = true
    previous.isHidden = true
    skip.isHidden = true
  }

  @objc private func open() { onAction?("open") }

  func update(title text: String, artist name: String, playing: Bool, favorite liked: Bool, artwork: UIImage?) {
    title.text = name.isEmpty ? text : "\(text) - \(name)"
    cover.image = artwork
    let symbols = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    toggle.setImage(
      UIImage(systemName: playing ? "pause.fill" : "play.fill", withConfiguration: symbols), for: .normal)
    toggle.accessibilityLabel = playing ? "暂停" : "播放"
    favorite.setImage(
      UIImage(systemName: liked ? "heart.fill" : "heart", withConfiguration: symbols), for: .normal)
    favorite.accessibilityLabel = liked ? "取消收藏" : "收藏"
  }
}
