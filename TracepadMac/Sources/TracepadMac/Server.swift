import Foundation
import Network
import AppKit

/// USBMux/iproxy 把 Mac 本机端口转发到 iPhone listener；Mac 主动连入该通道。
final class Server {
    let port: UInt16
    private var connection: NWConnection?
    private var bridgeProcess: Process?
    private var retryWorkItem: DispatchWorkItem?
    private var retryDelay: TimeInterval = 1
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "tracepad.server", qos: .userInteractive)
    private let mouse: Mouse
    private(set) var isReady = false

    var onClientState: ((String) -> Void)?
    var onEvent: ((Event) -> Void)?

    init(mouse: Mouse, port: UInt16) {
        self.mouse = mouse
        self.port = port
    }

    deinit {
        stop()
    }

    func stop() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        connection?.cancel()
        connection = nil
        isReady = false
        if let process = bridgeProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        bridgeProcess = nil
    }

    func start() throws {
        let candidates = ["/opt/homebrew/bin/iproxy", "/usr/local/bin/iproxy"]
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw NSError(domain: "TracepadUSB", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "找不到 iproxy。请先在终端运行：brew install libusbmuxd"
            ])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        // -l 强制选择 USB；-s 显式限制监听只在本机回环地址。
        process.arguments = ["-l", "-s", "127.0.0.1", "\(port):\(port)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        bridgeProcess = process
        log("[usb] iproxy 已启动：USB → 127.0.0.1:\(port) → iPhone:\(port)")
        connectToPhone()
    }

    private func connectToPhone() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        connection?.cancel()
        isReady = false
        receiveBuffer.removeAll(keepingCapacity: true)
        onClientState?("等待 USB 手机连接…")

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let client = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
        connection = client
        client.stateUpdateHandler = { [weak self] state in
            guard let self, self.connection === client else { return }
            switch state {
            case .ready:
                self.isReady = true
                self.retryDelay = 1
                DispatchQueue.main.async { self.onClientState?("USB 已连接 iPhone") }
                log("[usb] USB TCP 通道已连接")
                self.read(from: client, buffer: Data())
            case .waiting(let error):
                self.isReady = false
                DispatchQueue.main.async { self.onClientState?("等待 USB：\(error.localizedDescription)") }
                self.scheduleReconnect(for: client)
            case .failed(let error):
                self.isReady = false
                DispatchQueue.main.async { self.onClientState?("USB 连接失败：\(error.localizedDescription)，正在重试") }
                self.scheduleReconnect(for: client)
            default:
                break
            }
        }
        client.start(queue: queue)
    }

    private func scheduleReconnect(for client: NWConnection) {
        guard retryWorkItem == nil else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 8)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.connection === client else { return }
            self.retryWorkItem = nil
            self.connectToPhone()
        }
        retryWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func read(from client: NWConnection, buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, self.connection === client else { return }
            var pending = buffer
            if let data, !data.isEmpty { pending.append(data) }
            while pending.count >= 4 {
                let length = pending.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                guard length <= 65_536 else {
                    log("[usb] 丢弃超长帧：\(length) bytes")
                    client.cancel()
                    self.scheduleReconnect(for: client)
                    return
                }
                let frameLength = 4 + Int(length)
                guard pending.count >= frameLength else { break }
                let body = pending.subdata(in: 4..<frameLength)
                pending.removeSubrange(0..<frameLength)
                self.handle(body, connection: client)
            }
            if error != nil || complete {
                self.isReady = false
                client.cancel()
                DispatchQueue.main.async { self.onClientState?("USB 已断开，等待手机重连") }
                self.scheduleReconnect(for: client)
                return
            }
            self.read(from: client, buffer: pending)
        }
    }

    private func handle(_ body: Data, connection: NWConnection) {
        guard let ev = try? JSONDecoder().decode(Event.self, from: body) else {
            log("[usb] 无法解析帧：\(String(data: body, encoding: .utf8) ?? "?")")
            return
        }
        if let id = ev.id {
            let ack = try! JSONSerialization.data(withJSONObject: ["t": "ack", "id": id])
            connection.send(content: encodeFrame(ack), completion: .contentProcessed { error in
                if let error { log("[usb] 回执发送失败：\(error)") }
            })
        }
        DispatchQueue.main.async { self.apply(ev) }
    }

    private func apply(_ ev: Event) {
        guard let k = ev.k else { return }
        if let d = ev.dbg { log("[phone] \(d)") }
        if k == .pause { return }
        if k != .move && k != .scroll && k != .drag && k != .pause && k != .spaceSwipe {
            log("[apply] \(k.rawValue) v=\(ev.v ?? 0) dx=\(ev.dx ?? 0) dy=\(ev.dy ?? 0)")
        }
        let v = ev.v ?? 0
        let dx = ev.dx ?? 0
        let dy = ev.dy ?? 0
        switch k {
        case .move: mouse.move(dx: dx, dy: dy)
        case .dragBeg: mouse.dragBegin()
        case .drag: mouse.move(dx: dx, dy: dy)
        case .dragEnd: mouse.dragEnd()
        case .tap: mouse.tap()
        case .doubleTap: mouse.doubleTap()
        case .rightClick: mouse.tap(button: .right)
        case .scroll: mouse.scroll(dx: dx, dy: dy)
        case .pinch: mouse.zoom(steps: Int32(v.rounded()))
        case .rotate: break
        case .threeSwipe, .fourSwipe:
            if v != 0 { mouse.systemSwipe(k, direction: v) }
        case .spaceSwipe:
            if let phase = ev.p { mouse.spaceSwipe(phase: phase, progress: dx, velocity: v) }
        case .pause: break
        }
        onEvent?(ev)
    }
}
