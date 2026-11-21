import Foundation
import Network
import os

/// Appareil trouvé sur le réseau local, prêt à être ajouté.
struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    var kind: DeviceKind
    var name: String?
    var ip: String
    var mac: String?
    var androidTV: DiscoveredAndroidTVDevice?
    /// Info propre au protocole (ex. modèle de décodeur SFR).
    var hint: String?

    var id: String { "\(kind.rawValue)-\(ip)" }
    var displayName: String { name ?? kind.displayName }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Détection 100 % locale : balayage HTTP du sous-réseau (Orange, SFR, Samsung, Roku, LG, Hisense) + Bonjour (Google TV, AirPlay, SFR) + DNS Freebox.
enum NetworkScanner {
    static func scan() async -> [DiscoveredDevice] {
        await triggerLocalNetworkPermission()
        let base = await localIPv4Base() ?? "192.168.1"

        async let subnet = scanSubnet(base: base)
        async let googleTV = browseAndroidTVMDNS()
        async let airPlay = AirPlayBrowser().browse()
        async let sfrServices = AirPlayBrowser(serviceType: "_ws._tcp.").browse()
        async let freeboxPlayers = FreeboxPlayerClient.discover()
        async let laBox = resolveIPv4("websocket.labox")

        var results = await subnet
        let airPlayInfo = await airPlay

        // AirPlay donne le vrai nom de la TV (celui choisi par l'utilisateur) et son adresse MAC.
        for index in results.indices {
            if let info = airPlayInfo[results[index].ip] {
                if results[index].kind != .orange { results[index].name = results[index].name ?? info.name }
                results[index].mac = results[index].mac ?? info.mac
            }
        }
        // LG : la plupart des modèles récents s'annoncent en AirPlay même si le port SSAP a été raté.
        for (ip, info) in airPlayInfo where info.manufacturer.localizedCaseInsensitiveContains("LG")
            && !results.contains(where: { $0.ip == ip }) {
            results.append(DiscoveredDevice(kind: .lgWebOS, name: info.name, ip: ip, mac: info.mac))
        }
        // SFR : les décodeurs s'annoncent en Bonjour « _ws._tcp » (STB7…, STB8…, ws_server pour LaBox).
        var sfrHints: [String: SFRVariant] = [:]
        for (ip, info) in await sfrServices {
            let name = info.name.lowercased()
            if name.hasPrefix("stb8") { sfrHints[ip] = .stb8 }
            else if name.hasPrefix("stb7") { sfrHints[ip] = .stb7 }
            else if name.hasPrefix("ws_server") { sfrHints[ip] = .labox }
        }
        if let ip = await laBox, LocalNetworkTrustDelegate.isPrivateHost(ip) { sfrHints[ip] = .labox }
        for (ip, variant) in sfrHints where !results.contains(where: { $0.ip == ip && $0.kind == .sfr }) {
            results.append(DiscoveredDevice(kind: .sfr, name: nil, ip: ip, mac: airPlayInfo[ip]?.mac))
        }
        for index in results.indices where results[index].kind == .sfr {
            results[index].hint = sfrHints[results[index].ip]?.rawValue
        }
        for ip in await freeboxPlayers where !results.contains(where: { $0.ip == ip && $0.kind == .freebox }) {
            results.append(DiscoveredDevice(kind: .freebox, name: nil, ip: ip, mac: airPlayInfo[ip]?.mac))
        }
        // Hisense VIDAA : on ne garde l'entrée AirPlay que si le broker MQTT répond
        // (les Hisense sous Google TV ou Roku sont déjà détectées par leur propre protocole).
        for (ip, info) in airPlayInfo where info.manufacturer.localizedCaseInsensitiveContains("Hisense")
            && !results.contains(where: { $0.ip == ip }) {
            if await HisenseVIDAAClient.isListening(ip: ip, timeout: 1.5) {
                results.append(DiscoveredDevice(kind: .hisense, name: info.name, ip: ip, mac: info.mac))
            }
        }

        for device in await googleTV where !results.contains(where: { $0.ip == device.ip && $0.kind == .androidTV }) {
            // Une Google TV peut aussi répondre comme TV (ex : Sony) : on garde les deux entrées.
            results.append(DiscoveredDevice(kind: .androidTV, name: device.name, ip: device.ip, mac: airPlayInfo[device.ip]?.mac, androidTV: device))
        }
        return results.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return DeviceKind.allCases.firstIndex(of: lhs.kind)! < DeviceKind.allCases.firstIndex(of: rhs.kind)!
            }
            return lastOctet(lhs.ip) < lastOctet(rhs.ip)
        }
    }

    /// Retrouve un appareil par son adresse MAC après un changement d'IP (DHCP).
    static func relocate(_ device: SavedDevice) async -> String? {
        guard let mac = device.mac?.uppercased(), !mac.isEmpty else { return nil }
        let base = await localIPv4Base() ?? "192.168.1"
        let hits = await scanSubnet(base: base, kinds: [device.kind])
        return hits.first { $0.mac?.uppercased() == mac }?.ip
    }

    // MARK: Sous-réseau

    static func scanSubnet(base: String, kinds: Set<DeviceKind> = [.orange, .sfr, .samsung, .roku, .lgWebOS, .hisense]) async -> [DiscoveredDevice] {
        await withTaskGroup(of: [DiscoveredDevice].self) { group in
            var host = 1
            var running = 0
            var results: [DiscoveredDevice] = []
            // ~48 hôtes à la fois : rapide sans saturer le Wi-Fi.
            while host <= 254 || running > 0 {
                while host <= 254 && running < 48 {
                    let ip = "\(base).\(host)"
                    group.addTask { await probe(ip: ip, kinds: kinds) }
                    host += 1
                    running += 1
                }
                if let batch = await group.next() {
                    results.append(contentsOf: batch)
                    running -= 1
                }
            }
            return results
        }
    }

    private static func probe(ip: String, kinds: Set<DeviceKind>) async -> [DiscoveredDevice] {
        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            if kinds.contains(.orange) {
                group.addTask {
                    guard let decoder = await OrangeRemoteClient.probe(ip: ip, timeout: 0.8) else { return nil }
                    return DiscoveredDevice(kind: .orange, name: decoder.name, ip: ip, mac: decoder.mac)
                }
            }
            if kinds.contains(.roku) {
                group.addTask {
                    guard let info = await RokuClient.deviceInfo(ip: ip, timeout: 0.8) else { return nil }
                    return DiscoveredDevice(kind: .roku, name: info.name, ip: ip, mac: info.mac)
                }
            }
            if kinds.contains(.samsung) {
                group.addTask { await probeSamsung(ip: ip) }
            }
            if kinds.contains(.lgWebOS) {
                group.addTask { await probeLG(ip: ip) }
            }
            if kinds.contains(.sfr) {
                group.addTask {
                    guard await isTCPPortOpen(ip: ip, port: SFRDecoderClient.port, timeout: 0.8) else { return nil }
                    return DiscoveredDevice(kind: .sfr, name: nil, ip: ip, mac: nil)
                }
            }
            if kinds.contains(.hisense) {
                group.addTask {
                    guard await HisenseVIDAAClient.isListening(ip: ip, timeout: 0.8) else { return nil }
                    return DiscoveredDevice(kind: .hisense, name: nil, ip: ip, mac: nil)
                }
            }
            var found: [DiscoveredDevice] = []
            for await result in group {
                if let result { found.append(result) }
            }
            return found
        }
    }

    private static func probeSamsung(ip: String) async -> DiscoveredDevice? {
        guard let url = URL(string: "http://\(ip):8001/api/v2/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.8
        guard let (data, response) = try? await localNetworkSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = json["device"] as? [String: Any] else { return nil }
        let rawName = (device["name"] as? String) ?? (json["name"] as? String)
        let name = rawName.map { $0.replacingOccurrences(of: "[TV] ", with: "") }
        let mac = (device["wifiMac"] as? String)?.uppercased()
        return DiscoveredDevice(kind: .samsung, name: name, ip: ip, mac: mac)
    }

    /// Le serveur SSAP des TV LG répond « hello world » en HTTP sur le port 3000.
    private static func probeLG(ip: String) async -> DiscoveredDevice? {
        guard let url = URL(string: "http://\(ip):3000/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.8
        guard let (data, _) = try? await localNetworkSession.data(for: request) else { return nil }
        let body = String(decoding: data.prefix(64), as: UTF8.self).lowercased()
        guard body.contains("hello world") else { return nil }
        return DiscoveredDevice(kind: .lgWebOS, name: nil, ip: ip, mac: nil)
    }

    private static func triggerLocalNetworkPermission() async {
        // Force l'apparition de la demande d'accès au réseau local dès le premier scan.
        guard let gateway = await localIPv4Base(), let url = URL(string: "http://\(gateway).1/") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        _ = try? await localNetworkSession.data(for: request)
    }

    private static func lastOctet(_ ip: String) -> Int {
        ip.split(separator: ".").last.flatMap { Int($0) } ?? 0
    }
}

// MARK: - AirPlay (noms et adresses MAC des TV)

struct AirPlayInfo: Sendable {
    var name: String
    var mac: String?
    var manufacturer: String
}

private final class AirPlayBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var results: [String: AirPlayInfo] = [:]
    private var continuation: CheckedContinuation<[String: AirPlayInfo], Never>?
    private var didFinish = false
    private let serviceType: String

    init(serviceType: String = "_airplay._tcp.") {
        self.serviceType = serviceType
    }

    func browse() async -> [String: AirPlayInfo] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.continuation = continuation
                let browser = NetServiceBrowser()
                self.browser = browser
                browser.delegate = self
                browser.searchForServices(ofType: self.serviceType, inDomain: "local.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.finish() }
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let ip = BonjourAndroidTVBrowser.preferredIPAddress(from: sender.addresses ?? []) else { return }
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        func value(_ key: String) -> String? {
            txt[key].map { String(decoding: $0, as: UTF8.self) }
        }
        let mac = value("deviceid").flatMap { $0.filter(\.isHexDigit).count == 12 ? $0.uppercased() : nil }
        let manufacturer = value("manufacturer") ?? value("model") ?? ""
        lock.withLock {
            results[ip] = AirPlayInfo(name: sender.name, mac: mac, manufacturer: manufacturer)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        finish()
    }

    private func finish() {
        lock.lock()
        guard !didFinish else { lock.unlock(); return }
        didFinish = true
        let result = results
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        browser?.stop()
        services.forEach { $0.stop() }
        continuation?.resume(returning: result)
    }
}
