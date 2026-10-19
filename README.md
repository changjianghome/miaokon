# miaokon

把 iPhone 当作 Mac 的多点触控板，通过 USB 有线连接。手机负责识别手势，Mac 端将手势转换成鼠标操作。

## 功能

- 单指移动与左键、双指右键和滚动
- 双指捏合缩放
- 三指拖拽、四指桌面切换与 Mission Control
- 独立调节鼠标、滚动和缩放速度，支持触觉反馈
- 手机与 Mac 之间只通过 USB 连接

## 项目结构

```text
TracepadMac/       macOS 接收端
TracepadRemote/    iOS 触控板
tools/             图标生成工具
```

## 环境要求

- macOS 13 或更高版本
- iOS 16 或更高版本
- Xcode（构建 iOS 端）
- Homebrew 的 `libusbmuxd`（提供 `iproxy`，用于 USB 转发）

安装 USB 工具：

```sh
brew install libusbmuxd
```

## 构建

### Mac 端

```sh
cd TracepadMac
swift build -c release
```

### iPhone 端

在 Xcode 打开 `TracepadRemote/TracepadRemote.xcodeproj`，选择 `TracepadRemote` scheme 和已连接的 iPhone，在 **Signing & Capabilities** 里选择你自己的开发团队，然后运行。首次安装需在 iPhone 上信任此开发者，并启用开发者模式（若系统要求）。

## 使用

1. 用 USB 线连接 iPhone 和 Mac，并在 iPhone 上确认信任。
2. 启动 Mac 接收端并授予“辅助功能/设备控制”权限。
3. 启动 iPhone 端，看到 USB 已连接后即可使用。

## 开源与隐私

本仓库只包含源码、必要图标资源和构建说明，不包含签名证书、开发者团队 ID、设备 UDID、个人构建产物或调试日志。每位开发者需在自己的 Xcode 中设置签名团队。

项目代码采用 MIT License。`TracepadMac/Sources/DockSwipe/` 中的 DockSwipe 代码保留其原始许可与署名，详见该目录的 `LICENSE-iss.txt`。
