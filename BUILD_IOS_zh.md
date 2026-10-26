# Absorb：iOS/WMA 修复与 Mac 自行安装

基于公开项目 [pounat/absorb](https://github.com/pounat/absorb)，基线提交：

```text
761ec117952bbc996fc4d6c3c75e62a2e269e65a
Absorb 1.12.1+301；.flutter-version = 3.47.0
```

交付的是源代码，不是已经签名、可直接安装的 IPA。没有推送、修改远程仓库或创建远程 PR。

## 修复了什么

- 书籍 `startPlaybackSession` 与播客 `startEpisodePlaybackSession` 使用同一兼容性检查。
- iOS 不再宣称支持 `audio/x-ms-wma`；Android 的 MIME 列表和默认请求保持不变。
- API 识别到 iOS 的原始 WMA 轨道时，先关闭该会话，再发送 `forceDirectPlay: false, forceTranscode: true`。仅把新会话交给播放器；强制转码后仍返回原始 WMA 时失败退出，不循环重试，也不退回原始 WMA。
- 检测覆盖 WMA MIME、常见 WMA codec、轨道 URL、文件元数据，以及多轨文件中后面的 WMA 轨道。
- 旧的 iOS/WMA 直放缓存自动失效；其他格式和 Android WMA 缓存保留。
- 播放器按服务器实际返回的 `playMethod == 2` 识别 iOS 转码会话，避免再次执行同样的转码回退。

**为什么仍可能短暂显示 Direct Play？** API 调用最初只有 itemId/episodeId，没有可靠的源格式信息。为了严格保留其他格式的现有直放行为，首个会话仍使用原有请求读取轨道。确认是 iOS/WMA 后会马上关闭它并强制转码，原始 WMA 不会交给音频播放器加载。服务器界面可能瞬间显示探测会话为 Direct Play，最终活跃会话应为 Transcode（`playMethod: 2`），通常返回 HLS `.m3u8`。首次开始 WMA 会多一次建会话请求。

这比把所有 iOS 内容都设成 `forceTranscode: true` 更窄，也保留了 MP3、M4B、FLAC、OGG 等格式的现有行为。仅从 MIME 列表删除 WMA 不足以修复，因为服务器的 `forceDirectPlay` 优先于 MIME 协商；依据：[Audiobookshelf 服务端 startSession](https://github.com/advplyr/audiobookshelf/blob/master/server/managers/PlaybackSessionManager.js)、[播放 API 参数](https://api.audiobookshelf.org/#play-a-library-item-or-podcast-episode)。

## 获取可构建源码

**方式 A：直接解压 `absorb-ios-wma-source.zip`。** 内含完整项目源码、vendored packages、新测试和本说明，不包含 Flutter SDK、构建缓存、证书或私钥。进入解压后的 `absorb-ios-wma` 文件夹，后续命令都在该项目根目录执行。

**方式 B：给基线版本应用补丁。** 如果已有自己修改过的 Absorb，先另建一份目录；补丁只保证适配上面的基线提交，不要强行覆盖新版本的同名文件。

```bash
git clone https://github.com/pounat/absorb.git absorb-ios-wma
cd absorb-ios-wma
git switch --detach 761ec117952bbc996fc4d6c3c75e62a2e269e65a
git switch -c fix/ios-wma-transcoding
```

把 `absorb-ios-wma.patch` 放到项目的上一级目录，再执行：

```bash
git apply --check ../absorb-ios-wma.patch
git apply ../absorb-ios-wma.patch
```

补丁包含 4 个生产文件和 1 个测试文件。若检查失败，通常是版本不同；此时用方式 A 更直接。

## 1. 准备 Mac 工具

1. 安装完整 Xcode，打开一次，完成组件安装和许可确认。Xcode 要支持手机当前的 iOS 版本。
2. 按 [Flutter 官方安装说明](https://docs.flutter.dev/install) 安装 **Flutter 3.47.0**，或从 [SDK archive](https://docs.flutter.dev/install/archive) 下载该版本并把 `bin` 加入 PATH。本次测试使用 Dart 3.13.0（随 Flutter 3.47.0 提供）。
3. 安装 CocoaPods，建议 **1.16.2 或更新**；如果已使用 Homebrew，可执行 `brew install cocoapods`，已有旧版则执行 `brew upgrade cocoapods`。
4. 原项目还包含使用 iOS 17 API 的小组件扩展，建议先用 iOS 17 或更新的真机验证；不要为迁就旧设备随意降低所有 target 的部署版本。

在终端确认：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
flutter --version
flutter doctor -v
flutter precache --ios
```

Xcode 不在 `/Applications/Xcode.app` 时，替换为实际路径。若提示许可未接受，按提示运行 `sudo xcodebuild -license` 并阅读确认。官方环境与设备说明：[Set up iOS development](https://docs.flutter.dev/platform-integration/ios/setup)。

## 2. 获取依赖并打开 Xcode

**使用 Xcode 27 时先做这一项兼容性调整：** 本次原生构建实际发现，部分 Pods 仍声明最低 iOS 12，Xcode 27 会将它报为 Target Integrity 错误。交付包附带独立的 `xcode27-pods-ios15.patch`，用于把 Podfile 的平台设为 iOS 15，并在 `post_install` 中仅将低于 15 的 Pod target 提升到 15；不降低已经更高的 target。它不属于 WMA 修复，也不会自动应用。

在完整源码包根目录可执行：

```bash
git apply --check xcode27-pods-ios15.patch
git apply xcode27-pods-ios15.patch
```

如果使用方式 B，请先把这个独立补丁也复制到项目根目录。若 Flutter 已自动把 Podfile 平台改成 15、导致整份补丁检查失败，可手动只将补丁里的 `target.build_configurations.each` 那段加入已有 `post_install` 的 target 循环，再重新 `pod install`。不要只改生成的 Pods.xcodeproj，否则下一次装依赖会丢失调整。

在项目根目录运行：

```bash
flutter pub get
flutter test test/ios_wma_playback_test.dart
cd ios
pod install
cd ..
open ios/Runner.xcworkspace
```

打开 **Runner.xcworkspace**，包含 CocoaPods 依赖。保留 `pubspec.lock`，无需运行依赖升级。

Flutter 3.47 可能自动加入 Swift Package Manager 集成并调整 Xcode 项目。这些属于本机工具生成的配置；WMA 补丁本身不修改签名、Podfile 或 Xcode 工程。如果 Xcode 长时间停在解析依赖，检查它报告的包地址能否访问，使用 Xcode 的 File → Packages → Resolve Package Versions 重试；不要把网络解析失败当成 WMA Dart 补丁编译失败。

本次验证还尝试了 CocoaPods 路径。若要让某次 Flutter 构建保持该路径、避免插件的自动 Swift 包迁移，可在命令前加本次环境变量（不修改全局设置）：

```bash
FLUTTER_SWIFT_PACKAGE_MANAGER=false flutter build ios --release --no-codesign
```

之后在 Xcode 配置签名并安装。如果随后使用终端运行或导出，也给对应的 `flutter run` / `flutter build ipa` 命令加相同环境变量。原项目的 **AbsorbPlayerCore 本地 Swift 包**仍要保留；关闭的是 Flutter 插件的依赖管理迁移。

## 3. 配置自己的签名

上游自带作者的 Team 和 `com.barnabas.absorb` 标识。你没有作者的签名权限，必须改用自己的 Team 和标识。

### 所有账号都要做

1. Xcode → Settings → Accounts，登录自己的 Apple Account。
2. 选择 Runner target → Signing & Capabilities，勾选 Automatically manage signing，Team 选自己的团队。对 Debug / Profile / Release 都生效。
3. Runner 的 Bundle Identifier 换成自己唯一的名字，例如 `com.yourname.absorb.wmafix`。示例中的 `yourname` 要自行替换。
4. 若保留 NowPlayingWidgetExtension，其 Bundle Identifier 改为主应用标识加 `.NowPlayingWidget`，Team 也选自己的。RunnerTests 如需要签名，也改为自己的标识和 Team。
5. 保留 Background Modes 中的 Audio 功能，供锁屏播放使用。

用不同 Bundle ID 安装会作为独立应用共存，不会直接继承 App Store 版本的本地设置与下载；需重新登录服务器。

### 保留小组件：使用有相应能力的开发团队

- 为自己的主应用和扩展配置同一个、属于自己的 App Group，例如 `group.com.yourname.absorb.wmafix`。
- 原 App Group 在代码中也有硬编码，必须把以下文件中的 `group.com.barnabas.absorb` 同步改成自己的组名：
  - `ios/Runner/Runner.entitlements`
  - `ios/NowPlayingWidget/NowPlayingWidgetExtension.entitlements`
  - `ios/NowPlayingWidget/NowPlayingWidget.swift`
  - `ios/Runner/AbsorbPlayerCore.swift`
  - `ios/Runner/AppDelegate.swift`
  - `ios/AbsorbPlayerCore/Sources/AbsorbPlayerCore/Intents.swift`
  - `lib/services/home_widget_service.dart`
- App Group 必须在你的团队下注册并同时分配给主应用和扩展；Xcode 自动签名通常可以协助配置。[Apple App Group 配置说明](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)。
- **CarPlay 不是付费账号自动获得的权限。** 如果你的团队没有获得相应授权，在 Runner 中移除 CarPlay capability，并从 `Runner.entitlements` 删除 `com.apple.developer.carplay-audio`；无需删除相关 Swift 源码。[Apple CarPlay entitlement](https://developer.apple.com/carplay/)。Siri 也必须由所选团队的描述文件实际支持，否则移除 Siri capability 及相应 entitlement。

### 免费 Personal Team：只验证手机上的播放

Apple 允许免费账号在自己的设备上测试，但能力受限；不能直接继承作者的 App Groups / Siri / CarPlay 描述文件。免费签名的描述文件 **7 天过期**，需要重新构建安装；具体数量限制见 [Apple Personal Team 说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

如 Xcode 报某项 capability 不支持，为这份自用副本做以下精简：

1. Runner → Signing & Capabilities，移除 Siri、CarPlay 和不被团队支持的 App Groups。
2. 检查 `ios/Runner/Runner.entitlements`，删除对应 entitlement；只保留 Xcode 能签发的项目。若全部移除，文件可保留一个空的 `<dict/>`。
3. 如果无法签名 App Group / 小组件，在 Runner → Build Phases → Embed App Extensions 中移除 NowPlayingWidgetExtension.appex，并在 Target Dependencies 中移除 NowPlayingWidgetExtension。若 scheme 单独列出扩展，也移除其构建项。保留 Runner 依赖的 **AbsorbPlayerCore 本地 Swift 包**，不要把它当成小组件一起删除。
4. 这份精简安装不具备被移除的小组件、Siri、CarPlay 功能。它是签名限制的独立本地调整，未混入通用 WMA 补丁；需在自己的设备验证应用和锁屏播放。

不能用 `--no-codesign` 绕过真机签名，它只用于编译检查；原始未签名 `.app` 不能直接在 iPhone 上运行。

## 4. 安装到 iPhone

1. USB 连接手机，解锁并信任 Mac。
2. 设置 → 隐私与安全性 → 开发者模式，启用并按提示重启。
3. Xcode 顶部 scheme 选 Runner，运行设备选自己的 iPhone。
4. Product → Scheme → Edit Scheme → Run，Build Configuration 选 **Release**，再点运行，等待签名、编译和安装。Release 适合日常脱离调试器使用。
5. 如手机要求信任开发者，在 设置 → 通用 → VPN 与设备管理 中信任自己的证书。

签名设置完成后也可从项目根目录安装：

```bash
flutter devices
flutter run --release -d YOUR_DEVICE_ID
```

`YOUR_DEVICE_ID` 替换成上一条列出的手机 ID。需要导出开发用 IPA 且团队/描述文件允许时：

```bash
flutter build ipa --release --export-method development
```

输出在 `build/ios/ipa/`。该 IPA 仍受所用签名与设备范围限制。自用 USB 安装无需发布到 App Store、上传 TestFlight 或运行上游 GitHub/Codemagic 发布工作流。[Flutter iOS 构建与签名说明](https://docs.flutter.dev/deployment/ios)。

## 5. 在实际服务器验证

1. 使用在线播放；若这本书已下载为原始 WMA，先移除该本地下载，让应用进入服务器流播放路径。
2. 播放原来失败的 WMA 书籍，确认最终活跃会话显示 Transcode，能连续播放、拖动进度、锁屏继续播放。
3. 若有 WMA 播客，也验证一集；再播放 MP3/M4B，确认仍是原有直放行为。
4. 日志应出现 `iOS/WMA detected - requesting server transcoding`，随后请求应含 `forceDirectPlay: false`、`forceTranscode: true`；新会话通常是 `playMethod: 2`，URL 指向 `.m3u8`。
5. 若仍失败，看 Audiobookshelf 的转码 / FFmpeg 日志及 HLS 请求；服务器必须能解码该 WMA 并提供转码流，反向代理也必须允许 HLS 访问。

**范围限制：** 这次修复的是 Audiobookshelf 的在线播放会话。它没有给 iOS 添加本地 WMA 解码器；原始 WMA 的离线下载不能因此直接播放。若需要离线听，先把文件转成 iOS 可播放格式再入库。本次未连接你的真实服务器，也未在你的 iPhone 上验证。

## 代码清单与回退

- `lib/services/api_service.dart`
- `lib/services/playback_format_policy.dart`（新增）
- `lib/services/session_cache.dart`
- `lib/services/audio_player_service.dart`
- `test/ios_wma_playback_test.dart`（新增；上游忽略 test 目录，但交付包与补丁包含此文件）

若通过方式 B 应用，在尚未继续修改这些文件的前提下可回退：

```bash
git apply --reverse --check ../absorb-ios-wma.patch
git apply --reverse ../absorb-ios-wma.patch
```

补丁回退不处理你自行做的签名调整。重新分发时保留项目 GPL-3.0 许可证及对应源码。
