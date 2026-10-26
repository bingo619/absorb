# 验证记录

- 日期：2026-10-26（Asia/Shanghai）。
- 源码基线：`pounat/absorb@761ec117952bbc996fc4d6c3c75e62a2e269e65a`，版本 `1.12.1+301`。
- 工具：Apple Silicon Mac；Flutter 3.47.0；Dart 3.13.0；Xcode 27.0（27A266a）。
- 所有代码改动只在本地。未推送远程仓库，未创建远程 PR，未安装到手机。

## 自动测试：通过

```bash
flutter test --no-pub test/ios_wma_playback_test.dart --reporter expanded
```

结果：**18 项全部通过**。测试注入 `http.MockClient` 与内存 SharedPreferences，不连接用户服务器。

覆盖：

- iOS 书籍 / 播客：关闭原始 WMA 会话，在同一 endpoint 重开强制转码会话，只返回新会话。
- 强制转码请求同时设置 `forceTranscode: true` 和 `forceDirectPlay: false`，保留设备描述、episodeId 和 startOffset。
- MP3、MP4/M4B、FLAC、OGG 在 iOS / Android 仍发送原有直放请求。
- Android WMA 仍广告其 MIME，继续直放，不触发额外请求。
- 服务端忽略转码标志时，最多两次播放请求；关闭无效会话后退出，不循环。
- 转码请求失败时，不把原始 WMA 返回给播放器。
- WMA MIME、codec、带查询参数/编码路径/大写扩展名的 URL、文件元数据、多轨检测。
- 已转码 HLS 即使保留源 WMA 元数据，也不会被当成原始 WMA 重试。
- 只删除相关 iOS/WMA 旧缓存；MP3 和 Android WMA 缓存保留。

## 静态检查：通过

```bash
flutter analyze --no-pub \
  lib/services/api_service.dart \
  lib/services/audio_player_service.dart \
  lib/services/playback_format_policy.dart \
  lib/services/session_cache.dart \
  test/ios_wma_playback_test.dart
```

结果：**No issues found**。

## 原生 iOS 编译

结果：**iOS Release 无签名编译成功**，输出 `build/ios/iphoneos/Runner.app`（Flutter 报告 71.1 MB）。未使用签名证书，也未安装到设备。

验证过程：

1. 默认 Swift Package Manager 路径在获取上游二进制包依赖阶段持续等待，约 5 分钟后停止此次尝试；它未证明应用编译成功或失败。
2. 本次设置 `FLUTTER_SWIFT_PACKAGE_MANAGER=false`，改用 CocoaPods，进入了 Xcode 原生编译。首次遇到上游 Pod target 最低版本 iOS 12 与 Xcode 27 要求至少 iOS 15 的 Target Integrity 错误。
3. 仅在本机验证副本的 Podfile 中临时将低于 15 的 Pod target 提升为 15，重新编译成功；Xcode 构建阶段约 112 秒。此调整作为 `xcode27-pods-ios15.patch` 单独交付，详细应用方法在 `BUILD_IOS_zh.md`。

成功构建使用：

```bash
FLUTTER_SWIFT_PACKAGE_MANAGER=false \
  flutter build ios --release --no-codesign --no-pub
```

本机 CocoaPods 为 1.15.2，Flutter 提示推荐 1.16.2 以上；虽然本次构建成功，安装文档仍建议使用更新版本。构建时 CocoaPods 使用独立缓存目录。默认 Swift 包迁移与生成的 Podfile.lock / 翻译变动没有混入 WMA 补丁或完整源码包。

## 补丁与源码包

已在原始基线的独立副本通过 `git apply --check`、实际应用和反向应用检查，并逐字节比对 5 个修改文件。源码 ZIP 通过完整性检查，并逐字节比对同一组文件。独立 Xcode 27 兼容补丁也通过应用检查。

主补丁只包含 4 个 Dart 生产文件与 1 个测试文件。Xcode 27 的 Pods 部署版本兼容补丁独立提供，不会自动应用；源码包不包含本机构建生成的 Podfile.lock、翻译文件变动或 Xcode 配置迁移。

未完成的验证：用户实际 WMA 文件、用户 Audiobookshelf/FFmpeg 与反向代理、用户证书签名、iPhone 上的声音/拖动/锁屏连续播放。测试通过和无签名编译均不能代替这些真机检查。
