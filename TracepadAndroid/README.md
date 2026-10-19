# miaokon-sj Android 端

这是 iPhone 版之外的 Android 触控板客户端。它通过 Android USB 调试桥（ADB）有线连接到 Mac，复用现有 TCP 7311 帧格式和 Mac 鼠标事件处理。

> **适配开发中：** Android APK 尚未完成构建，也未在实体手机上验证；当前设备已完成 ADB 授权，后续可直接用于安装与手势验收。

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

## USB 使用

1. Android 设置中启用开发者选项和 USB 调试，并在手机授权这台 Mac。
2. 用 USB 线连接手机，启动 Mac 端 `miaokon-mac`。
3. 打开本 App，保持在前台；Mac 端会检测已授权的 Android 设备并建立 ADB 端口转发。
4. 手机状态显示 USB 已连接后开始操作。

如果 Mac 上有多个 Android 设备，当前版本会选择 ADB 列表中的第一台授权设备。iPhone 原有 USBMux/iproxy 连接仍受支持。

## Android 适配说明

- 手机端监听 `127.0.0.1:7311`，Mac 使用 `adb forward tcp:7311 tcp:7311` 接入；控制数据沿 USB ADB 通道传输，不使用 Wi-Fi。
- Mac 端保留原有事件解析与鼠标注入，只新增 ADB USB 桥接选择。
- Android 侧屏幕固定横屏，触控区铺满界面，顶部按钮提供设置、重连、连通性测试和震动测试。
