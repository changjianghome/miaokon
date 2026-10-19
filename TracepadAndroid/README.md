# miaokon-sj Android 端

这是 iPhone 版之外的 Android 触控板客户端。支持 ADB USB 转发和同一局域网内的 Wi-Fi 直连，复用现有 TCP 7311 帧格式和 Mac 鼠标事件处理。

## 手势

- 单指移动与左键；单指长按拖动
- 双指右键、上下/左右滚动、捏合缩放
- 三指拖拽；四指纵向滚动、Mission Control、桌面切换
- 独立设置鼠标横/纵速度、滚动和缩放速度、自然滚动及触觉反馈

## 构建

需要 JDK 17 和 Android SDK Platform 35 / Build Tools 35.0.0。

```sh
cd TracepadAndroid
./gradlew assembleDebug
```

首次构建前，在 Android Studio SDK Manager 接受 Android SDK 许可并安装 `Android 15 (API 35)` 与 Build Tools 35.0.0。也可用 `sdkmanager --licenses` 接受许可，再通过 `sdkmanager` 安装对应组件。

APK 输出在 `app/build/outputs/apk/debug/app-debug.apk`。

## 连接方式

USB 模式：Android 设置中启用 USB 调试并授权这台 Mac，USB 连接后打开本 App，Mac 自动建立 ADB 端口转发。

Wi-Fi 模式：Android 手机与 Mac 接入同一局域网，打开本 App，在 Mac 菜单栏勾选“Android 改用 Wi-Fi（无需 USB 调试）”。Mac 通过 Bonjour 自动发现手机并连接。首次使用时允许 macOS 访问本地网络。

如果 Mac 上有多个 Android 设备，当前版本会选择 ADB 列表中的第一台授权设备。iPhone 原有 USBMux/iproxy 连接仍受支持。

## Android 适配说明

- 手机端监听 TCP 7311 并广播 `_miaokon._tcp` Bonjour 服务；ADB forward 与 Wi-Fi 直连复用同一事件协议。
- Mac 端保留原有事件解析与鼠标注入，只新增 ADB USB 桥接选择。
- Android 侧屏幕固定横屏，触控区铺满界面，顶部按钮提供设置、重连、连通性测试和震动测试。
