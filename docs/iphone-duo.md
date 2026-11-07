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
