import Foundation
import AppKit
import ApplicationServices
import ServiceManagement

// 同时输出到控制台和 ~/Library/Logs/miaokon-mac.log（.app 双击启动时控制台不可见）
let logPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/miaokon-mac.log")
FileManager.default.createFile(atPath: logPath.path, contents: nil)
let logHandle = try? FileHandle(forWritingTo: logPath)
func log(_ s: String) {
    print(s)
    fflush(stdout)
    if let h = logHandle {
        h.seekToEndOfFile()
        h.write((s + "\n").data(using: .utf8) ?? Data())
    }
}

// MARK: - 启动参数

var port: UInt16 = 7311
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    if a == "--port", let p = args.popFirst(), let n = UInt16(p) { port = n }
    if a == "--help" {
        log("""
        miaokon-mac —— 极简触控板接收端
        用法：miaokon-mac [--port 7311]
        首次运行需在「系统设置 → 隐私与安全性 → 设备控制和数据访问」允许本程序。
        """)
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class LoginItemController: NSObject {
    private let service = SMAppService.mainApp
    let menuItem = NSMenuItem(title: "开机启动", action: #selector(toggle(_:)), keyEquivalent: "")

    override init() {
        super.init()
        menuItem.target = self
        refreshState()
    }

    func refreshState() {
        switch service.status {
        case .enabled, .requiresApproval:
            menuItem.state = .on
        case .notRegistered, .notFound:
            menuItem.state = .off
        @unknown default:
            menuItem.state = .off
        }
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
                log("[login-item] 已关闭开机启动")
            } else {
                try service.register()
                log("[login-item] 已请求开启开机启动，当前状态：\(service.status)")
            }
            refreshState()
        } catch {
            refreshState()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法更改开机启动设置"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
            log("[login-item] 设置失败：\(error.localizedDescription)")
        }
    }
}

final class AndroidWiFiController: NSObject {
    private let server: Server
    let menuItem = NSMenuItem(title: "Android 改用 Wi-Fi（无需 USB 调试）", action: #selector(toggle(_:)), keyEquivalent: "")

    init(server: Server, wifiEnabled: Bool) {
        self.server = server
        super.init()
        menuItem.target = self
        menuItem.state = wifiEnabled ? .on : .off
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        sender.state = enabled ? .on : .off
        server.setAndroidWiFiEnabled(enabled)
        log("[android] 连接模式切换为\(enabled ? "Wi-Fi" : "USB/ADB")")
    }
}

let loginItemController = LoginItemController()

// 请求 CGEvent 投递权限。macOS 27 将该权限显示为“设备控制和数据访问”。
let eventAccess = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
log("[main] 启动 \(Date()) 事件发送权限：\(eventAccess ? "已授权" : "未授权（请在系统设置的设备控制和数据访问中开启）")")

let mouse = Mouse()
let injectOK = mouse.selfTest()
log("[main] 注入自检：\(injectOK ? "正常" : (eventAccess ? "失败（系统光标未移动）" : "失败（事件发送权限未授权）"))")
let defaultAndroidWiFi = Bundle.main.object(forInfoDictionaryKey: "MiaokonAndroidWiFiDefault") as? Bool ?? false
let androidServer = Server(mouse: mouse, port: port, remotePort: 7311, bridgeKind: .android,
                           androidWiFiEnabled: defaultAndroidWiFi)
let androidWiFiController = AndroidWiFiController(server: androidServer, wifiEnabled: defaultAndroidWiFi)
let iPhonePort = port == UInt16.max ? port - 1 : port + 1
let iPhoneServer = Server(mouse: mouse, port: iPhonePort, remotePort: 7311, bridgeKind: .iPhone)

// 菜单栏状态：图标 + 端口 + 当前连接数 + 权限提示
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let button = statusItem.button {
    if let mouseIcon = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "miaokon-mac") {
        mouseIcon.isTemplate = true
        button.image = mouseIcon
    } else {
        button.title = "🖱"
    }
}
let menu = NSMenu()
let androidInfo = NSMenuItem(title: "Android · 正在启动…", action: nil, keyEquivalent: "")
androidInfo.isEnabled = false
menu.addItem(androidInfo)
menu.addItem(androidWiFiController.menuItem)
let iPhoneInfo = NSMenuItem(title: "iPhone · 正在启动…", action: nil, keyEquivalent: "")
iPhoneInfo.isEnabled = false
menu.addItem(iPhoneInfo)
let permissionGranted = CGPreflightPostEventAccess()
let permState = NSMenuItem(title: permissionGranted ? "设备控制和数据访问：已授权" : "设备控制和数据访问：未授权（点下面打开授权页面）", action: nil, keyEquivalent: "")
permState.isEnabled = false
menu.addItem(permState)
menu.addItem(.separator())
let perm = NSMenuItem(title: permissionGranted ? "查看设备控制和数据访问设置…" : "打开授权页面…", action: #selector(NSWorkspace.openDeviceControlSettings), keyEquivalent: "")
// 菜单项若 target 为空，会因 responder chain 找不到 NSWorkspace action 而呈灰色、无法点击。
perm.target = NSWorkspace.shared
perm.isEnabled = true
menu.addItem(perm)
menu.addItem(loginItemController.menuItem)
menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu

androidServer.onClientState = { state in
    DispatchQueue.main.async { androidInfo.title = "Android · " + state }
}
iPhoneServer.onClientState = { state in
    DispatchQueue.main.async { iPhoneInfo.title = "iPhone · " + state }
}
for server in [androidServer, iPhoneServer] {
    server.onEvent = { ev in
        if let k = ev.k, k != .move && k != .scroll && k != .drag {
            log("[event] \(k.rawValue) v=\(ev.v ?? 0)")
        }
    }
}

do {
    try androidServer.start()
} catch {
    androidInfo.title = "Android · 启动失败：\(error.localizedDescription)"
    log("[main] Android USB 转发启动失败：\(error.localizedDescription)")
}
do {
    try iPhoneServer.start()
} catch {
    iPhoneInfo.title = "iPhone · 启动失败：\(error.localizedDescription)"
    log("[main] iPhone USB 转发启动失败：\(error.localizedDescription)")
}

DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    if !androidServer.isReady {
        let mode = defaultAndroidWiFi ? "Wi-Fi" : "USB"
        log("[main] Android \(mode) 通道尚未就绪；确认 miaokon-sj 前台运行")
    }
    if !iPhoneServer.isReady {
        log("[main] iPhone USB 通道尚未就绪；确认 miaokon-sj 前台运行和 USB 信任")
    }
}

let terminationObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.willTerminateNotification,
    object: app,
    queue: .main
) { _ in
    androidServer.stop()
    iPhoneServer.stop()
}

// 每 3 秒刷新一次权限状态（用户授权后无需重启程序）
let permTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
    let granted = CGPreflightPostEventAccess()
    permState.title = granted ? "设备控制和数据访问：已授权" : "设备控制和数据访问：未授权（点下面打开授权页面）"
    perm.title = granted ? "查看设备控制和数据访问设置…" : "打开授权页面…"
    perm.isEnabled = true
    loginItemController.refreshState()
}
RunLoop.main.add(permTimer, forMode: .common)

extension NSWorkspace {
    @objc func openDeviceControlSettings() {
        // Privacy_Accessibility 会在 macOS 27 上直达“设备控制和数据访问”，
        // 在较早版本则直达“辅助功能”。
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
           NSWorkspace.shared.open(url) {
            log("[permission] 已打开设备控制和数据访问授权页")
        } else if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            log("[permission] 授权页深链打开失败，退回隐私与安全设置")
            NSWorkspace.shared.open(fallback)
        }
    }
}

log("[main] 就绪，Android \(defaultAndroidWiFi ? "Wi-Fi Bonjour" : "ADB USB") 与 iPhone USBMux 独立运行，可同时连接")
app.run()
NotificationCenter.default.removeObserver(terminationObserver)
