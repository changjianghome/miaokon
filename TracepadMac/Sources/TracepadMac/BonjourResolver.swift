import Foundation

final class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let onResolved: (String, UInt16) -> Void
    private var browser: NetServiceBrowser?
    private var services: [String: NetService] = [:]

    init(onResolved: @escaping (String, UInt16) -> Void) {
        self.onResolved = onResolved
    }

    func start() {
        DispatchQueue.main.async {
            guard self.browser == nil else { return }
            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType: "_miaokon._tcp.", inDomain: "local.")
        }
    }

    func stop() {
        DispatchQueue.main.async {
            self.browser?.stop()
            self.browser?.delegate = nil
            self.browser = nil
            for service in self.services.values {
                service.stop()
                service.delegate = nil
            }
            self.services.removeAll()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name == "miaokon-sj" else { return }
        services[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 6)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeValue(forKey: service.name)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty,
              let port = UInt16(exactly: sender.port),
              port > 0 else { return }
        onResolved(host, port)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        log("[wifi] Bonjour 主机名解析失败：\(errorDict)")
    }
}
