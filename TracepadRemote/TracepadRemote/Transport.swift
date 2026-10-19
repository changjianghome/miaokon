import Foundation
import Network

/// USBMux 通过 USB 连接到手机上的 TCP listener；手机不再主动访问 Wi-Fi IP。
final class Sender {
    private let port = NWEndpoint.Port(rawValue: 7311)!
    private var listener: NWListener?
    private var connection: NWConnection?
    private var ready = false
    private var receiveBuffer = Data()
    private var listenerRetry: DispatchWorkItem?
    private let queue = DispatchQueue(label: "tracepad.sender", qos: .userInteractive)
    var onState: ((String) -> Void)?
    var onAck: ((String) -> Void)?

    func startUSBListener() {
        queue.async { [weak self] in self?.openListener() }
    }

    /// 从手机端重启 USB TCP 监听，并释放现有连接，让 Mac 自动重连。
    func restartUSBListener() {
        queue.async { [weak self] in
            guard let self else { return }
            self.onState?("正在重启 USB 连接…")
            self.listenerRetry?.cancel()
            self.listenerRetry = nil

            let oldConnection = self.connection
            self.connection = nil
            self.ready = false
            self.receiveBuffer.removeAll(keepingCapacity: true)
            oldConnection?.stateUpdateHandler = nil
            oldConnection?.cancel()

            let oldListener = self.listener
            self.listener = nil
            oldListener?.stateUpdateHandler = nil
            oldListener?.newConnectionHandler = nil
            oldListener?.cancel()

            // 等系统完成旧 listener 的端口释放后再重新绑定。
            self.queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.openListener()
            }
        }
    }

    private func openListener() {
        guard listener == nil else { return }
        do {
            let tcpListener = try NWListener(using: .tcp, on: port)
            listener = tcpListener
            tcpListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            tcpListener.stateUpdateHandler = { [weak self] state in
                guard let self, self.listener === tcpListener else { return }
                switch state {
                case .ready:
                    self.onState?("USB 服务就绪，等待 Mac")
                case .failed(let error):
                    self.onState?("USB 服务失败：\(error.localizedDescription)，正在重试")
                    tcpListener.cancel()
                    self.listener = nil
                    self.scheduleListenerRetry()
                case .cancelled:
                    if self.listener === tcpListener { self.listener = nil }
                default:
                    break
                }
            }
            tcpListener.start(queue: queue)
        } catch {
            onState?("USB 服务启动失败：\(error.localizedDescription)，正在重试")
            scheduleListenerRetry()
        }
    }

    private func scheduleListenerRetry() {
        guard listenerRetry == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.listenerRetry = nil
            self.openListener()
        }
        listenerRetry = item
        queue.asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func accept(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        ready = false
        receiveBuffer.removeAll(keepingCapacity: true)
        newConnection.stateUpdateHandler = { [weak self] state in
            guard let self, self.connection === newConnection else { return }
            switch state {
            case .ready:
                self.ready = true
                self.onState?("USB 已连接 Mac")
                self.read(from: newConnection)
            case .failed(let error):
                self.ready = false
                self.onState?("USB 连接断开：\(error.localizedDescription)，等待重连")
                self.connection = nil
            case .cancelled:
                self.ready = false
                self.connection = nil
                self.onState?("等待 Mac 通过 USB 连接")
            default:
                break
            }
        }
        newConnection.start(queue: queue)
    }

    func send(_ ev: Ev) {
        let frame = encodeFrame(ev.json)
        queue.async { [weak self] in
            guard let self, self.ready, let connection = self.connection else { return }
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                if let error { self?.onState?("USB 发送失败：\(error.localizedDescription)") }
            })
        }
    }

    private func read(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, self.connection === connection else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.consumeAcks()
            }
            if error != nil || isComplete {
                self.ready = false
                self.connection = nil
                self.onState?("USB 已断开，等待 Mac 重连")
                return
            }
            self.read(from: connection)
        }
    }

    private func consumeAcks() {
        while receiveBuffer.count >= 4 {
            let length = receiveBuffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length <= 65_536 else {
                receiveBuffer.removeAll(keepingCapacity: true)
                onState?("收到无效 USB 响应")
                return
            }
            let frameLength = 4 + Int(length)
            guard receiveBuffer.count >= frameLength else { return }
            let body = receiveBuffer.subdata(in: 4..<frameLength)
            receiveBuffer.removeSubrange(0..<frameLength)
            if let ack = try? JSONDecoder().decode(Ack.self, from: body), ack.t == "ack" {
                onAck?(ack.id)
            }
        }
    }
}
