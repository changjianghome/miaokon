# miaokon — PUBLIC SOURCE

> **PUBLIC / 公开源码仓库**。这里只维护清理后的源码；构建过程、个人签名信息和旧安装包保存在独立的私有历史仓库。

把 iPhone 或 Android 手机当作 Mac 的多点触控板。iPhone 使用 USB；Android 可选 USB 或同一局域网 Wi-Fi。手机负责识别手势，Mac 端将手势转换成鼠标操作。

## 功能

- 单指移动与左键、双指右键和滚动
- 双指捏合缩放
- 三指拖拽、四指桌面切换与 Mission Control
- 独立调节鼠标、滚动和缩放速度，支持触觉反馈
- Android 可通过 USB/ADB 或 Wi-Fi 连接；Wi-Fi 模式无需开启 USB 调试

## 项目结构

```text
TracepadMac/       macOS 接收端
TracepadRemote/    iOS 触控板
TracepadAndroid/   Android 触控板
tools/             图标生成工具
```

## 环境要求

- macOS 13 或更高版本
- iOS 16 或更高版本
- Android 8.0（API 26）或更高版本
- Xcode（构建 iOS 端）
- JDK 17 与 Android SDK Platform 35（构建 Android 端）
- Homebrew 的 `libusbmuxd`（提供 iPhone USB 转发 `iproxy`）
- Android USB 模式需要 `platform-tools`（提供 `adb` 转发）；Wi-Fi 模式不依赖 ADB
- Wi-Fi 模式需要手机和 Mac 接入同一局域网

安装 USB 工具：

```sh
brew install libusbmuxd
```

## 构建

### Mac 端

```sh
./tools/package-mac-app.sh ./dist/miaokon-mac-usb.app usb
./tools/package-mac-app.sh ./dist/miaokon-mac-wifi.app wifi
```

若已安装 Apple Development 签名证书，可设置 `CODESIGN_IDENTITY` 环境变量以保留系统授权身份；否则脚本使用本地临时签名。

### iPhone 端

在 Xcode 打开 `TracepadRemote/TracepadRemote.xcodeproj`，选择 `TracepadRemote` scheme 和已连接的 iPhone，在 **Signing & Capabilities** 里选择你自己的开发团队，然后运行。首次安装需在 iPhone 上信任此开发者，并启用开发者模式（若系统要求）。

### Android 端

```sh
cd TracepadAndroid
./gradlew assembleDebug
```

APK 位于 `TracepadAndroid/app/build/outputs/apk/debug/app-debug.apk`。首次构建需在 Android Studio SDK Manager 接受 SDK 许可并安装 Platform 35 / Build Tools 35.0.0。

## 使用

1. iPhone 用 USB 连接 Mac 并确认信任；Android 可用 USB（开启 USB 调试并授权此 Mac）或 Wi-Fi（手机和 Mac 接入同一局域网）。
2. 启动 Mac 接收端并授予“辅助功能/设备控制”权限。
3. 启动对应的手机端并保持在前台。Android Wi-Fi 模式下，在 Mac 菜单栏勾选“Android 改用 Wi-Fi（无需 USB 调试）”；发现手机后自动连接。首次使用需允许 macOS 访问本地网络。

Android USB 模式使用 ADB `forward`；Android Wi-Fi 模式通过 Bonjour 发现手机并直接建立 TCP 连接。Mac 菜单可在 USB/ADB 与 Wi-Fi 之间切换。iPhone 仍使用独立的 USBMux/iproxy 通道，iOS 与 Android 手机工程可以分别构建和调试。

## 开源与隐私

本仓库只包含源码、必要图标资源和构建说明，不包含签名证书、开发者团队 ID、设备 UDID、个人构建产物或调试日志。每位开发者需在自己的 Xcode 中设置签名团队。

项目代码采用 MIT License。`TracepadMac/Sources/DockSwipe/` 中的 DockSwipe 代码保留其原始许可与署名，详见该目录的 `LICENSE-iss.txt`。
