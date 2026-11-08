# iPhone Duo 适配

## 需求与场景（2026-11-06）

用户要求适配折叠屏 iPhone Duo。保留现有来听入口和播放控制器，折叠、展开、旋转或分屏改变窗口尺寸时，不能重新装载队列、重置进度或打断播放。

- 窄窗口：唱片、歌词预览和播放控制采用单栏，可纵向滚动。
- 宽窗口：唱片与播放控制在一侧，完整歌词在另一侧；按可用空间决定布局，不按设备名称或物理分辨率判断。
- 系统侧边区域：内容在 `SafeArea` 内布局，随左右安全边距变化重新计算空间。
- 高度受限或大字体：歌词详情和播放控制仍可滚动到达，不能因固定纵向布局溢出。

原有失败场景：播放器无论窗口宽度都使用单列；歌词详情页的固定头部、控制区和 `Expanded` 歌词在短窗口或大字体下可能挤出屏幕。

## 平台前提与验收边界

苹果的 [适配指南](https://developer.apple.com/iphone-duo/prepare/) 说明：iOS 26 及更早 SDK 的构建运行在兼容布局中；iOS 27 SDK 支持动态扩展；iOS 27.1 及更新 SDK 提供完整显示区域支持。另见 [设计指南](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)。

2026-11-06 的布局开发使用 Xcode 26.5，仅完成 Flutter widget 窗口测试；测试尺寸是覆盖用例，不作为 Duo 的官方逻辑尺寸。2026-11-07 用户要求升级后，已安装并默认选用 `/Applications/Xcode-27.1.app`（27A9275），iOS 27.1 SDK 和模拟器组件已安装；Duo 模拟器启动、闭合与展开系统画面均已验证。旧版保留于 `/Applications/Xcode.app`，升级验证见[日志](worklog/2026-11-07.md)。

2026-11-07 后续已完成 iOS 27.1 SDK 的原生构建与 Duo 模拟器播放验证。Flutter 3.44.2 上通过独立窗口通道传递 UIKit 的 occlusion / division 保留区域，不依赖普通 `SafeArea` 覆盖折线；摄像头区域包含系统给出的交互边距。iOS 最低版本随 Xcode 27.1 的编译要求从 13 调整为 15。尚无已连接的 Duo 真机，真实折叠手感、后台／锁屏、分屏和动态岛活动仍需真机验证。

代码、测试和本机产物仍在当前 `repos/ai-music` 工程；本轮不发布、不安装到 iPhone (105)。实际验证结果见当日工作日志。

## 后续需求（2026-11-07）

用户要求参考 QQ 音乐及知名听歌软件，继续完善实际 Duo 效果。参考 QQ 音乐 App Store 更新记录（Duo 歌词、唱片架）与其公开演示（侧边导航、悬停上歌词下操作），Apple Music 用户实拍的播放／歌词或队列分栏；保留来听现有黑胶设计和同一播放控制器。

本轮实现：宽屏侧边导航、播放器歌词／待播切换；接入 UIKit 27.1 原生 reservedRegions，分开折线两侧，避开摄像头。外屏／小窗口保留单栏，动态切换不重建播放任务。验证目标为当前 Mac 的 iPhone Duo 模拟器，产物在本仓库 build/，无真机 Duo，不发布。

参考：
- https://apps.apple.com/hk/app/id414603431 （QQ 音乐官方更新说明）
- https://www.ithome.com/1/004/335.htm （QQ 音乐公开演示报道）
- https://www.reddit.com/r/AppleMusic/comments/1xg0rmv/apple_music_on_the_duo/ （用户实拍，非官方技术文档）
- https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
- https://developer.apple.com/documentation/uikit/uiview/reservedregions(kind:options:)

## 首轮实现与实际验证（右侧留白问题已由下文修正）

- 首页：可用空间足够时显示右侧导航，底部保留迷你播放器；窄窗口回到底部导航。切换时保留选中页面、搜索文字和页面状态。
- 播放器：展开为黑胶／控制和歌词／待播两栏；待播使用同一队列，支持点歌、排序和现有管理操作。窄屏维持单栏，矮而宽的外屏改为唱片在左、预览和控制在右。
- 半折叠：读取 UIKit `UIView.reservedRegions(kind:)` 的有效 division 区域；竖向折线左右分栏，横向折线上歌词／队列、下唱片／控制。区域太小时选较大的一侧滚动显示，不把控制放进折线。
- 原生观察在 `updateConstraints` 中进行，系统保留区域变化会重新通知；旋转时丢弃尺寸不匹配的旧快照，转换为 Flutter display features。全局遮挡区域用最近边缘留白保护按钮和弹层。背景继续延伸到保留区域。
- 26 项定向测试通过（播放器 21、区域几何 1、首页折叠状态 1、原有窄屏／队列回归 3）；短外屏布局补充后再次运行折叠测试通过。所有改动文件静态检查通过。
- Device Hub / iOS 27.1：真实 QQ 热歌榜加载，播放《天龙八部之宿敌》，展开／半折叠／旋转时进度继续推进；切到待播列表点《我不难过》，歌曲与控制同步更新，展开与闭合保持同一歌曲继续播放。重新安装保留缓存和播放恢复数据；外屏横放可直接看到播放及切歌按钮。
- 截图位于 `build/duo-evidence/`，包括展开、上下悬停、外屏横放。属于模拟器结果，不冒充 Duo 真机体验。

## 本机重现构建

先完成 Flutter 测试，再准备 iOS 工程。不要在 pod install 同时运行 flutter test：测试命令可能将生成的插件元数据切回非 Swift Package 模式，导致插件同时通过 Pods 和 Swift Packages 链接。

```sh
/Users/huangqi/ClaudeProject/tools/flutter/bin/flutter build ios --simulator --debug --no-pub --config-only
xcrun xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'id=09E7FA0F-0710-4348-B00C-CE00BEA84648' \
  -clonedSourcePackagesDirPath build/ios/SourcePackages \
  BUILD_DIR=/Users/huangqi/CodexProject/laiting-studio/repos/ai-music/build/ios \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
```

Xcode 27.1 的 lipo 同时验证 arm64 / x86_64 时在本机报 `-verify_arch requires exactly one input file`；当前 Apple Silicon 模拟器构建显式选择 arm64，仍使用 27.1 编译器和 SDK。安装产物为 `build/ios/Debug-iphonesimulator/Runner.app`，实际工程身份 `com.tjs.aimusic`，没有变更应用身份。日志 `build/duo-xcode-build.log`；不生成或发布 IPA。

## 用户修正：右侧导航（2026-11-07）

用户指出半屏、外屏右侧仍有空白，要求按苹果布局方式将导航按钮放到右侧。上一版整体裁掉遮挡所在边缘，造成摄像头／状态栏下方也不可用，首页另占一条侧栏，播放器返回和操作仍在顶部。本轮改用 UIKit `verticalBarEdge`，让导航占用系统侧栏，只按实际矩形避让摄像头、状态栏和折线；返回／页面操作先于主导航，空间不足用溢出菜单。适用外屏、展开／半折叠和分屏的系统侧栏位置，保留 iPhone 普通窗口和内屏竖向的正常布局。


本轮实现：

- 原生桥接传递 `traitCollection.verticalBarEdge`，注册 `systemTraitsAffectingVerticalBarEdge`，并提供状态栏的窗口坐标矩形。
- `DuoScaffold` 让主导航、返回与页面操作占用原本的系统侧边空间，按实际摄像头／状态栏／折线矩形排布，短窗口保留“更多”入口。反向旋转及分屏采用系统给出的物理左右位置，不按文字方向翻转。
- 首页四个入口、播放器、完整歌词、队列、设置子页、歌单、下载、评论、音源页面共用侧栏；歌单滚动标题保留在内容区，导航和操作移到侧边。嵌套页面不重复创建侧栏。
- 树结构在左右／普通布局间保持稳定；播放和页面状态继续沿用。外屏队列使用带侧边返回的独立页；歌词详情也保留队列入口。

验证：28 项定向测试通过（原有播放器／区域 22、首页折叠 1、窄屏全路由／长队列 1、新增侧栏 4），受影响文件静态检查无问题；最终 Xcode 27.1 arm64 模拟器构建成功并安装。新增测试覆盖侧边安全区域利用、遮挡和折线避让、短屏溢出入口、物理左右位置及嵌套内容状态保持。

Duo 模拟器实查：外屏竖放首页导航位于右下方；播放页右侧包含返回、收藏、加入歌单、完整歌词、队列。半折叠横向布局的右边不再整条留空；上下半折叠随系统恢复水平导航，歌词和控制分处折线两侧。反向横放侧栏随系统移到左边；队列、完整歌词和返回入口可用。播放《我不难过》旋转后继续推进，歌单页返回／刷新在侧边，不重复顶部返回。以上是模拟器结果，真机与真实多任务分屏仍未验收。

最终构建日志：`build/duo-right-xcode-build.log`。截图：`build/duo-evidence/right-rail-outer-player.png`、`right-rail-half-player.png`、`right-rail-outer-home.png`。未发布、未推送，未操作 iPhone (105)。


## 用户真机体验包（2026-11-07）

用户随后接入 iPhone Duo（iPhone19,4，iOS 27.2），明确要求安装体验。以源码 `0a67d7e` 构建 Release arm64，使用本机已登录的个人开发账号临时签名，不改工程原签名设置。`com.tjs.aimusic` / 来听 / 1.0.4（8267）已安装；用户开启开发者模式并信任开发者后，应用启动成功。签名有效至 2026-11-14。仅本机真机体验交付，未公开发布；未将安装及启动成功作为真机播放／折叠／后台全部验收。产物与详情见 [工作日志](worklog/2026-11-07.md)。

## 二次优化方案：按系统竖栏样式重做导航（2026-11-07）

用户对上一版 Duo 适配不满意：UI 样式和导航条不好看，没有用系统的导航样式。要求参考国内外主流音乐 App 的 Duo 适配整体优化。

### 现状对照

在 Duo 模拟器外屏对比系统设置／Safari：系统竖栏没有整条底色，状态栏和灵动岛在上，其下是**单个圆形玻璃按钮**（返回、书签），底部是**一个竖直胶囊容器**装一组仅图标的 Tab／工具项；页面大标题仍在内容区左上。本应用当前的 `DuoRail`：整条 20% 底色竖带、方形 Material 文字按钮（图标＋文字）、矩形选中色块、不分组，观感接近 Android NavigationRail；子页另加 40pt 横向 AppBar 标题条占用竖向空间；展开横向走自建 `preferSideNavigation`，与系统侧栏样式不一致，内容单列拉伸。

### 参考结论

- Apple HIG《Designing for iPhone Duo》与 Tech Talk《Raise the bar with iPhone Duo》：竖栏固定宽度、项目仅符号；顶部留给返回／关闭，随后是显著操作，其余工具项保持原分组，Tab 在底部，组间由系统留空；空间不足时默认**工具项先从下往上**收进"…"溢出菜单，导航型页面保留 Tab；文字按钮留在横向；内屏竖持是唯一保留横向栏的姿态；折叠时只做小幅位移，不重排结构。
- Apple Music（iOS 27）：竖向堆叠布局在宽窗口重排为两栏；返回／分享／更多在竖栏上部，Tab 在下部。
- QQ 音乐 20.9.6：展开后导航移到侧边、播放控制仍在底部；悬停时上半歌词、下半封面＋切歌。
- Spotify：扩展资料库视图，迷你播放器靠右；被评测批评的恰是菜单未贴到最右而留白。

### 方案

A. **竖栏重做（核心）**：去掉整条底色，栏宽取系统安全区；顶组＝返回／关闭 → 页面操作，各为 44pt 圆形玻璃按钮；底组＝主导航 Tab 放进一个竖直玻璃胶囊，仅图标，选中态为强调色填充圆，Tooltip／Semantics 提供文字，更新点／下载中徽标叠在图标角上；溢出先收工具项，Tab 最后，"…"菜单沿用应用弹出菜单样式；仍按矩形避开相机、状态栏与折线，折线时顶组在上半、Tab 组在下半。
B. **标题条**：竖栏模式下不再渲染 40pt AppBar 横条。首页／音乐库／下载／设置的大标题留在内容区；播放器与完整歌词页沉浸无标题。
C. **内屏横向**：统一走系统侧栏（去掉自建侧栏分支），内容区两栏：首页"搜索＋收藏＋歌单 | 发现榜单"，播放器"唱片＋控制 | 歌词／待播"，切换改用 Cupertino 滑动分段控件；迷你播放器留在内容区底部。
D. **内屏竖向**：保留横向底部 Tab（系统行为），列表与表单内容限制最大宽度居中，不拉伸。
E. **悬停**：保留"上歌词／待播、下唱片＋控制"，竖栏按钮分到折线两侧。
F. **不改**：播放控制器、队列逻辑、窗口状态保持、原生 reservedRegions／verticalBarEdge 桥。

未选方案：用原生 `UITabBarController`／`UINavigationController` 承载 Flutter 视图以获得真正的系统栏。需要 Flutter 路由与原生栏双向同步，PlatformView 与焦点行为有风险，本轮不做；若后续坚持真系统栏再单独评估。

### 实现与验证（2026-11-07）

A、B、C（播放器两栏沿用，切换控件换为 Cupertino 滑动分段；首页 ≥720pt 两栏）、E（竖栏分组按折线矩形分段）已实现；D 的内屏竖向最大宽度限制未做。另修正播放器背景在侧栏处的接缝（`DuoScaffold.background` 铺满窗口）和无顶部安全区时唱片贴边。测试、构建与外屏截图见当日[工作日志](worklog/2026-11-07.md)；内屏展开与悬停因模拟器缺少命令行姿态控制，仅有窗口测试覆盖，待 Device Hub 手动展开或真机复查。

## 三次：导航改用 UIKit 系统组件（2026-11-07）

用户试过真机后指出：上一波导航仍是 Flutter 画的，不是系统组件，没有系统质感；沉浸效果也差一点。要求能用系统组件的尽量都用系统组件。

### 方案：原生壳 + Flutter 内容

- **层次**：`MusicShellController`（窗口根）下面两层同尺寸子视图：底层是原有的 `DuoFlutterViewController`（整窗 Flutter 内容，不动）；上层是 `UITabBarController`（4 个 `UINavigationController`，根控制器与被推入的控制器都是透明的占位 `ShellPageController`，视图不接收触摸）。系统因此按真正的容器绘制 Liquid Glass 的 Tab 栏、导航栏、按钮和菜单；在 iPhone Duo 上自动变成竖栏并自动避让相机、状态栏和折线，在内屏竖持自动回到横向栏，无需应用判断设备。
- **触摸**：壳视图重写 `hitTest`，命中占位视图或系统容器的透明包装视图时转交 Flutter 视图；命中栏、按钮、菜单时留给系统。
- **安全区**：把当前占位视图的 `safeAreaLayoutGuide` 换算后设置为 Flutter 控制器的 `additionalSafeAreaInsets`，Flutter 内容自动避让导航栏／Tab 栏／竖栏，不再自己画侧栏。模态期间冻结该值，避免内容在遮罩后面重排。
- **路由镜像**：Flutter 根 `Navigator` 的 `PageRoute` 推入／弹出时，壳在当前 Tab 的导航控制器里同步推入／弹出占位控制器，系统提供返回按钮、标题切换动画与竖栏上的返回位置；系统返回键或 Flutter 自己的手势返回都只触发一次弹出，互不回声。Flutter 的底部弹层和对话框不镜像，期间壳隐藏两条栏（系统弹层也会盖住 Tab 栏），关闭后恢复。
- **页面描述**：`DuoScaffold` 在壳模式下不再渲染 Flutter `AppBar` 与侧栏，而是把标题、是否沉浸、操作（`IconButton`→`UIBarButtonItem` 图标，`TextButton`→文字项，`PopupMenuButton`→`UIMenu`）、首页 Tab（标题、SF Symbol、角标）上报给壳；图标优先映射 SF Symbol，没有对应时把字形渲染成模板位图。点按由原生回调 Flutter 执行原回调。一级页用大标题（Bodoni 72 与应用标题字体一致），推入页用行内标题，沉浸页无标题并隐藏 Tab 栏。
- **主题**：Flutter 主题变化时同步明暗、强调色与文字色到壳，系统栏与状态栏随应用皮肤。
- **不变**：播放控制器、队列、歌词、Duo 折线布局、原生保留区域桥、Android／Mac／鸿蒙行为。Flutter 自绘的 `DuoRail` 只在非 iOS 宽窗保留。
- **后续可选**：迷你播放器改为 `UITabAccessory`（Apple Music 式收进 Tab 栏）；播放页改为系统 sheet。

验收目标：iPhone Duo 模拟器外屏（竖／横）与普通 iPhone 模拟器的首页、音乐库、播放页、推入页返回、菜单；Flutter 测试在壳未激活时行为不变；安装到用户真机。

### 实现与验证（2026-11-07 深夜）

已按上述方案实现：`ios/Runner/MusicShell.swift`（`MusicShellController`／`ShellPageController`／`ShellView` 触摸分流／安全区转发／主题与菜单）、`SceneDelegate` 在场景连接后把 storyboard 的 Flutter 控制器移入壳并显式注册场景生命周期；Flutter 侧 `native_shell.dart`（握手、路由镜像、页面描述合并、SF Symbol 映射、字形位图兜底、主题同步）与 `DuoScaffold` 的壳模式（不画 AppBar／侧栏，上报标题、操作、Tab）。原普通 `Scaffold` 的推入页（更新、榜单、歌单直达、听歌统计、截图导入、下载品质）改为 `DuoScaffold` 以获得原生栏。首页两栏阈值提升到 840pt，避免 800pt 测试窗口与内屏竖持出现两栏。

模拟器结果：iPhone Duo 内屏横向——系统竖栏底部 Tab 胶囊（琥珀选中色）、页面操作与返回在竖栏顶部、系统大标题在内容左上、播放页隐藏 Tab 栏并以系统返回键返回；原生 Tab 点按切到音乐库，Flutter 状态保留。iPhone 18 Pro（iOS 27.0）——底部 Liquid Glass Tab 栏带文字、音乐库页行内标题＋玻璃操作胶囊、推入收藏页有系统返回与排序 `UIMenu`。截图 `build/duo-evidence/shell-*.png`。

已知与待办：普通 iPhone 上一级页只显示行内标题（iOS 26 大标题依赖原生滚动视图，透明占位滚动视图不触发）；Duo 外屏姿态本轮未实查（需在 Device Hub 折叠）；迷你播放器仍为 Flutter，`UITabAccessory` 留待下一步；`widget_test` 中「mini player and song page swipe between songs」在基线提交上同样失败，与本轮无关。

### 第二轮反馈处理（2026-11-08）

用户真机试用后反馈 13 条，处理如下（均在当前工作区，未提交）：

- **底部播放条材质**：iOS 26 起改为系统 `UITabAccessory`（Apple Music 同款玻璃材质，系统决定高度），内容为封面／歌名／歌手／播放暂停／下一首，由 Flutter 经 `nowPlaying` 消息喂数据，点按回调 Flutter 打开播放页；Flutter 自绘迷你播放条在附件生效时隐藏，沉浸页（播放器、歌词）主动撤下附件。无法查看用户真机上的 QQ 音乐，材质以苹果系统附件为准。
- **过场动画**（队列返回、歌词热评进出、皮肤页返回抖动）：所有页面推入改为 `AppPageRoute`，壳模式下 0.35 s 与 UIKit 同步；播放页在壳模式下改为系统横向推入而不是自下而上；壳在 `willShow` 时提前把目标页安全区写给 Flutter，去掉过场结束时的内容跳动；一级页全部取消大标题（行内），根页无操作时隐藏导航栏。
- **音乐库顶部空行／歌单标题太低**：一级页标题改回 Flutter 内容里的 masthead，系统栏只放操作；歌单详情在壳模式下把列表名交给系统行内标题，去掉 Flutter 的大标题 sliver。
- **宽屏布局**：音乐库"收藏／本地"与"我的听歌"限宽 560pt 左对齐；首页两栏阈值 840pt。
- **播控中心队列通底**：播放器右栏去掉底部内边距，嵌入式队列列表自己延伸到底并把底部安全区作为内边距。
- **下载管理遮挡**：壳模式下非沉浸推入页统一在导航栏下方留出安全区。
- **歌曲页竖屏底部太空**：窄布局改为 `SliverFillRemaining` 均匀分布唱片、歌词预览与控制；矮窗口（<760pt）唱片缩小到高度的 24%。
- **孔板印刷大屏太花**：半色调网点按短边缩放并封顶 1.5 倍。
- **局域网地址**：默认改为本机 `http://192.168.31.167:8787`，设置里保存的旧默认 `192.168.31.57` 读取时自动迁移，输入框提示同步更新。注意本机当前没有运行 8787 的音乐库服务（`tool/lan_music_server.py --root <音乐目录> --port 8787`），同步前需先启动。

### 第三轮反馈处理（2026-11-08）

设置页滚不到底／遮挡（空的 Flutter 底栏让 Scaffold 丢掉底部安全区）、返回弹动（一级页与推入页导航栏高度不同）、横屏迷你播放器（附件内联环境）三项已处理，细节见[工作日志](worklog/2026-11-08.md)。现在导航栏在所有页面常驻透明，一级页标题由 Flutter 画在栏下方，系统操作按钮与标题同一行。

### 第四轮：播控条改为 QQ 音乐式悬浮玻璃条（2026-11-08）

参考用户提供的 QQ 音乐实录：播控条改为原生 `UIGlassEffect` 悬浮胶囊，按内容区居中、宽屏限宽、竖屏近全宽，含封面／歌名／收藏／上一首／播放暂停／下一首／队列，窄时自动收起次要按钮；不再使用 `UITabAccessory`。细节见[工作日志](worklog/2026-11-08.md)。

### 第五轮（2026-11-08）

内屏竖持播放页改为按剩余高度定唱片尺寸、不再上下滚动；常规宽度顶部 Tab 栏背景透明；滑动切歌支持轻扫并去掉拖动中的重建；悬浮播控条加"歌词"按钮。细节见[工作日志](worklog/2026-11-08.md)。

### 第六轮（2026-11-08）

竖栏常驻歌词／热评／队列入口；滑动切歌整块跟手并带入相邻歌曲；沉浸页隐藏顶部 Tab 栏；播控条按 Tab 栏顶边定位。用户要求此后只在模拟器验证，验收后再装真机。细节见[工作日志](worklog/2026-11-08.md)。

### 第七轮（2026-11-08）

播控条：按压缩放反馈（去掉会吞触摸的交互式玻璃）、只在一级 Tab 页显示、手机只留播放＋队列、与系统 Tab 栏胶囊对齐、条上左右横滑切歌（跟手、松手判定、滑出滑入动画）。两台模拟器验证通过，细节见[工作日志](worklog/2026-11-08.md)。

### 第八轮（2026-11-08）

播放页：顶栏只留返回＋"更多"原生菜单；歌名／歌手左对齐、心形同行；控制行改为裸图标均布（模式、上一首、播放、下一首、队列）；窄布局用定高滑块均分唱片、信息与歌词预览。返回"退两次"根因是壳在 `didShow` 才通知 Flutter，改为 `willShow` 同步（按导航栈判断页面已弹出，侧滑等交互结束再通知）。细节见[工作日志](worklog/2026-11-08.md)。

### 第九轮（2026-11-08）

内屏竖持顶部黑带：`DuoWindow` 按摄像头遮挡给整个导航器加了顶部内边距，露出应用级背景；壳模式下不再加该内边距。细节见[工作日志](worklog/2026-11-08.md)。
