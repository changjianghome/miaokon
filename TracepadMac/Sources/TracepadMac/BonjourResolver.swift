import Foundation

final class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let onResolved: (String, UInt16) -> Void
    private let serviceType: String
    private let serviceName: String
    private var browser: NetServiceBrowser?
    private var services: [String: NetService] = [:]

    init(serviceType: String = "_miaokon._tcp.", serviceName: String = "miaokon-sj",
         onResolved: @escaping (String, UInt16) -> Void) {
        self.serviceType = serviceType
        self.serviceName = serviceName
        self.onResolved = onResolved
    }

    func start() {
        DispatchQueue.main.async {
            guard self.browser == nil else { return }
            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType: self.serviceType, inDomain: "local.")
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
        guard service.name == serviceName else { return }
        services[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 6)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeValue(forKey: service.name)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        // 用 Bonjour 主机名而不是 IP：手机 DHCP 地址会变，主机名由 mDNS 持续更新。
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
