import SwiftUI
import Combine

final class Model: ObservableObject {
    @Published var state: String = "正在启动…"
    @Published var hud: String = "就绪"
    @Published var testResult: String = ""

    let gestures = Gestures()
    let sender = Sender()
    private var timer: Timer?
    private var pingTimer: Timer?
    private var settingsCancellables = Set<AnyCancellable>()

    init() {
        let settings = Settings.shared
        settings.$horizontalMoveSpeed
            .removeDuplicates()
            .sink { [weak self] speed in self?.gestures.horizontalMoveSpeed = speed }
            .store(in: &settingsCancellables)
        settings.$verticalMoveSpeed
            .removeDuplicates()
            .sink { [weak self] speed in self?.gestures.verticalMoveSpeed = speed }
            .store(in: &settingsCancellables)
        settings.$scrollSpeed
            .removeDuplicates()
            .sink { [weak self] speed in self?.gestures.scrollSpeed = speed }
            .store(in: &settingsCancellables)
        settings.$zoomSpeed
            .removeDuplicates()
            .sink { [weak self] speed in self?.gestures.zoomSpeed = speed }
            .store(in: &settingsCancellables)
        settings.$hapticFeedback
            .removeDuplicates()
            .sink { [weak self] enabled in self?.gestures.hapticFeedbackEnabled = enabled }
            .store(in: &settingsCancellables)
        settings.$hapticStrength
            .removeDuplicates()
            .sink { [weak self] strength in self?.gestures.hapticStrength = strength }
            .store(in: &settingsCancellables)
        settings.$adaptiveMoveSpeed
            .removeDuplicates()
            .sink { [weak self] enabled in self?.gestures.adaptiveMoveSpeedEnabled = enabled }
            .store(in: &settingsCancellables)
        settings.$slowMoveMultiplier
            .removeDuplicates()
            .sink { [weak self] multiplier in self?.gestures.slowMoveMultiplier = multiplier }
            .store(in: &settingsCancellables)
        settings.$naturalScroll
            .removeDuplicates()
            .sink { [weak self] natural in self?.gestures.naturalScroll = natural }
            .store(in: &settingsCancellables)
        settings.$twoFingerRightClick
            .removeDuplicates()
            .sink { [weak self] enabled in self?.gestures.twoFingerRightClick = enabled }
            .store(in: &settingsCancellables)
        settings.$enableDrag
            .removeDuplicates()
            .sink { [weak self] enabled in self?.gestures.singleFingerDragEnabled = enabled }
            .store(in: &settingsCancellables)
        sender.onState = { [weak self] s in
            DispatchQueue.main.async { self?.state = s }
        }
        sender.onAck = { [weak self] id in
            DispatchQueue.main.async {
                guard let self, id == self.pendingTestID else { return }
                self.testResult = "Mac 已收到并回应 ✓"
            }
        }
        gestures.send = { [weak self] ev in
            guard let self else { return }
            self.sender.send(ev)
            switch ev.k {
            case .move:
                self.moveSendCount += 1
                if self.moveSendCount % 30 == 0 {
                    self.debugLog("sent \(self.moveSendCount) move speedX=\(String(format: "%.1f", self.gestures.horizontalMoveSpeed))x speedY=\(String(format: "%.1f", self.gestures.verticalMoveSpeed))x d=\(String(format: "%.4f", ev.dx)),\(String(format: "%.4f", ev.dy))")
                }
            case .scroll:
                self.scrollSendCount += 1
                if self.scrollSendCount % 20 == 0 {
                    self.debugLog("sent \(self.scrollSendCount) scroll speed=\(String(format: "%.1f", self.gestures.scrollSpeed))x natural=\(self.gestures.naturalScroll) dy=\(String(format: "%.4f", ev.dy))")
                }
            default:
                break
            }
        }
        gestures.onHUD = { [weak self] text, fingers in
            self?.hud = fingers > 0 ? "\(fingers) 指 · \(text)" : text
        }
        gestures.onDebug = { [weak self] s in self?.debugLog(s) }
        sender.startUSBListener()
        // 心跳：既让 Mac 端知道在线，也帮我们确认手机是否真的发出去了
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sender.send(Ev(k: .pause))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.gestures.tick()
        }
    }

    func testConnection() {
        let id = UUID().uuidString
        pendingTestID = id
        testResult = "等待 Mac 回应…"
        var ev = Ev(k: .pause, id: id)
        ev.dbg = "manual_connection_test"
        sender.send(ev)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.pendingTestID == id, self.testResult == "等待 Mac 回应…" else { return }
            self.testResult = "未收到 Mac 回应，请检查 Mac 端是否运行新版"
        }
    }

    func restartUSBConnection() {
        sender.restartUSBListener()
    }

    func testHaptic() {
        gestures.testHaptic()
    }

    /// 调试日志既写文件（File 里可见），也经过心跳通道带回 Mac 侧日志
    private var recentDebug: [String] = []
    private var moveSendCount = 0
    private var scrollSendCount = 0
    private var pendingTestID: String?
    private lazy var logPath: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("tracepad.debug.log")
    }()
    func debugLog(_ s: String) {
        recentDebug.append(s)
        if recentDebug.count > 20 { recentDebug.removeFirst() }
        NSLog("[tp] %@", s)
        // 写进 app 沙盒，事后可用 devicectl 拉出来看
        let line = "\(Date().timeIntervalSince1970) \(s)\n"
        if let h = try? FileHandle(forWritingTo: logPath) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8) ?? Data())
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: logPath)
        }
        // 同时发一个调试包，Mac 端日志里能看到手机内部状态
        var ev = Ev(k: .pause)
        ev.v = -1
        ev.dbg = s
        sender.send(ev)
    }
}
