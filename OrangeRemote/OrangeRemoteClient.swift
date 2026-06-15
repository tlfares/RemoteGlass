import SwiftUI
import UIKit
import Network
import Security
import CryptoKit
import os

enum RemoteMode: Int {
    case tap = 0
    case press = 1
    case release = 2
}

struct OrangeRemoteClient {
    var decoderIP: String

    func send(_ key: OrangeKey, mode: RemoteMode = .tap) async throws {
        guard let url = URL(string: "http://\(decoderIP):8080/remoteControl/cmd?operation=01&key=\(key.code)&mode=\(mode.rawValue)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        _ = try await URLSession.shared.data(for: request)
    }

    func ping() async -> Bool {
        do {
            try await send(.power, mode: .release)
            return true
        } catch {
            return false
        }
    }
}

@MainActor
final class RemoteViewModel: ObservableObject {
    @Published var decoderIP: String {
        didSet { UserDefaults.standard.set(decoderIP, forKey: Self.decoderIPKey) }
    }
    @Published var status: ConnectionStatus = .idle
    @Published var isScanning = false
    @Published var foundDecoders: [String] = []
    @Published var shouldAutoRetry = false
    private var scanGeneration = 0
    @Published var bgColors: [Color] {
        didSet {
            let hexes = bgColors.map { $0.hex }
            UserDefaults.standard.set(hexes, forKey: Self.bgColorsKey)
        }
    }
    @Published var bgImageData: Data? {
        didSet {
            if let data = bgImageData {
                try? data.write(to: Self.bgImageURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: Self.bgImageURL)
            }
        }
    }
    @Published var bgShowPhoto: Bool {
        didSet { UserDefaults.standard.set(bgShowPhoto, forKey: Self.bgShowPhotoKey) }
    }
    @Published var bgWeight: Double {
        didSet { UserDefaults.standard.set(bgWeight, forKey: Self.bgWeightKey) }
    }
    @Published var bgSpread: Double {
        didSet { UserDefaults.standard.set(bgSpread, forKey: Self.bgSpreadKey) }
    }
    @Published var bgTint: Double {
        didSet { UserDefaults.standard.set(bgTint, forKey: Self.bgTintKey) }
    }
    @Published var bgButtonShape: ButtonShape {
        didSet { UserDefaults.standard.set(bgButtonShape.rawValue, forKey: Self.bgButtonShapeKey) }
    }
    @Published var bgDisableStretch: Bool {
        didSet { UserDefaults.standard.set(bgDisableStretch, forKey: Self.bgDisableStretchKey) }
    }
    @Published var hasCustomizedColors: Bool {
        didSet { UserDefaults.standard.set(hasCustomizedColors, forKey: Self.hasCustomizedColorsKey) }
    }
    @Published var selectedProvider: String {
        didSet {
            UserDefaults.standard.set(selectedProvider, forKey: Self.selectedProviderKey)
            if oldValue != selectedProvider {
                cancelScan()
                if !hasCustomizedColors && bgImageData == nil {
                    bgColors = Self.defaultPreset(for: selectedProvider)
                }
            }
        }
    }
    @Published var androidTVIP: String {
        didSet { UserDefaults.standard.set(androidTVIP, forKey: Self.androidTVIPKey) }
    }
    @Published var androidTVPairedDevice: String {
        didSet { UserDefaults.standard.set(androidTVPairedDevice, forKey: Self.androidTVPairedDeviceKey) }
    }
    @Published var androidTVServiceName: String {
        didSet { UserDefaults.standard.set(androidTVServiceName, forKey: Self.androidTVServiceNameKey) }
    }
    @Published var discoveredAndroidTV: [DiscoveredAndroidTVDevice] = []
    @Published var pendingAndroidTVPairing: DiscoveredAndroidTVDevice?
    @Published var pairingMessage: String?
    @Published var isKeyboardVisible = false {
        didSet {
            if !isKeyboardVisible {
                lastKeyboardDismissTime = Date()
            }
        }
    }
    private var lastKeyboardDismissTime: Date?

    @Published var savedGTVDevices: [SavedGTVDevice] = [] {
        didSet {
            guard let data = try? JSONEncoder().encode(savedGTVDevices) else { return }
            UserDefaults.standard.set(data, forKey: Self.savedGTVDevicesKey)
        }
    }

    private var scanTask: Task<Void, Never>?
    private var pairingSession: AndroidTVPairingSession?
    private var androidTVRemoteClient: AndroidTVRemoteClient?
    private var sendTextTask: Task<Void, Never>?

    private static let decoderIPKey = "decoderIP"
    private static let bgColorsKey = "bgColors"
    private static let bgShowPhotoKey = "bgShowPhoto"
    private static let bgWeightKey = "bgWeight"
    private static let bgSpreadKey = "bgSpread"
    private static let bgTintKey = "bgTint"
    private static let bgButtonShapeKey = "bgButtonShape"
    private static let bgDisableStretchKey = "bgDisableStretch"
    private static let hasCustomizedColorsKey = "hasCustomizedColors"
    private static let selectedProviderKey = "selectedProvider"
    private static let androidTVIPKey = "androidTVIP"
    private static let androidTVPairedDeviceKey = "androidTVPairedDevice"
    private static let androidTVServiceNameKey = "androidTVServiceName"
    private static let savedGTVDevicesKey = "savedGTVDevices"

    private static var bgImageURL: URL {
        URL.documentsDirectory.appendingPathComponent("bgImage.jpg")
    }

    static func defaultPreset(for provider: String) -> [Color] {
        switch provider {
        case "Android TV":
            return [
                Color(hex: "000000") ?? .black,
                Color(hex: "4285F4") ?? .blue,
                Color(hex: "34A853") ?? .green,
                Color(hex: "EA4335") ?? .red,
                Color(hex: "FBBC04") ?? .yellow,
            ]
        default:
            return [
                Color(hex: "000000") ?? .black,
                Color(hex: "FF6A00") ?? .orange,
            ]
        }
    }

    init() {
        decoderIP = UserDefaults.standard.string(forKey: Self.decoderIPKey) ?? ""
        hasCustomizedColors = UserDefaults.standard.object(forKey: Self.hasCustomizedColorsKey) as? Bool ?? false
        if let hexes = UserDefaults.standard.array(forKey: Self.bgColorsKey) as? [String], !hexes.isEmpty {
            bgColors = hexes.compactMap { Color(hex: $0) }
        } else {
            let c1 = Color(hex: UserDefaults.standard.string(forKey: "bgColor1") ?? "") ?? Color(hex: "000000") ?? .black
            let c2 = Color(hex: UserDefaults.standard.string(forKey: "bgColor2") ?? "") ?? Color(hex: "FF6A00") ?? .orange
            bgColors = [c1, c2]
        }
        bgImageData = try? Data(contentsOf: Self.bgImageURL)
        bgShowPhoto = UserDefaults.standard.object(forKey: Self.bgShowPhotoKey) as? Bool ?? false
        bgWeight = UserDefaults.standard.object(forKey: Self.bgWeightKey) as? Double ?? 0.5
        bgSpread = UserDefaults.standard.object(forKey: Self.bgSpreadKey) as? Double ?? 0.5
        let majorVersion = Int(UIDevice.current.systemVersion.split(separator: ".").first ?? "") ?? 0
        bgTint = UserDefaults.standard.object(forKey: Self.bgTintKey) as? Double ?? (majorVersion >= 27 ? 0.5 : 0)
        bgButtonShape = UserDefaults.standard.string(forKey: Self.bgButtonShapeKey)
            .flatMap(ButtonShape.init(rawValue:)) ?? .squircle
        bgDisableStretch = UserDefaults.standard.object(forKey: Self.bgDisableStretchKey) as? Bool ?? false
        selectedProvider = UserDefaults.standard.string(forKey: Self.selectedProviderKey) ?? "Orange"
        androidTVIP = UserDefaults.standard.string(forKey: Self.androidTVIPKey) ?? ""
        androidTVPairedDevice = UserDefaults.standard.string(forKey: Self.androidTVPairedDeviceKey) ?? ""
        androidTVServiceName = UserDefaults.standard.string(forKey: Self.androidTVServiceNameKey) ?? ""

        savedGTVDevices = Self.loadGTVDevices()
        if savedGTVDevices.isEmpty && !androidTVPairedDevice.isEmpty {
            savedGTVDevices = [
                SavedGTVDevice(
                    id: UUID(),
                    name: androidTVPairedDevice,
                    ip: androidTVIP,
                    serviceName: androidTVServiceName
                )
            ]
        }

        if decoderIP.isEmpty && androidTVIP.isEmpty {
            scanLocalNetwork()
        }
    }
    
    private static func loadGTVDevices() -> [SavedGTVDevice] {
        guard let data = UserDefaults.standard.data(forKey: Self.savedGTVDevicesKey),
              let devices = try? JSONDecoder().decode([SavedGTVDevice].self, from: data) else {
            return []
        }
        return devices
    }

    var canSend: Bool {
        if selectedProvider == "Android TV" {
            return !androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !androidTVPairedDevice.isEmpty
        }
        return !decoderIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentIP: String {
        selectedProvider == "Android TV" ? androidTVIP : decoderIP
    }

    func send(_ key: OrangeKey) {
        guard canSend else {
            status = .needsAddress
            return
        }

        status = .sending

        if selectedProvider == "Android TV" {
            let ip = androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                do {
                    if androidTVRemoteClient == nil {
                        androidTVRemoteClient = makeAndroidTVRemoteClient(ip: ip)
                    }
                    try await androidTVRemoteClient?.send(key)
                    await MainActor.run { status = .connected }
                } catch {
                    await MainActor.run { status = .failed }
                }
            }
        } else {
            let ip = decoderIP.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                do {
                    try await OrangeRemoteClient(decoderIP: ip).send(key)
                    await MainActor.run { status = .connected }
                } catch {
                    await MainActor.run { status = .failed }
                }
            }
        }
    }

    func send(_ key: OrangeKey, direction: Int32) {
        guard canSend else {
            status = .needsAddress
            return
        }

        status = .sending

        if selectedProvider == "Android TV" {
            let ip = androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                do {
                    if androidTVRemoteClient == nil {
                        androidTVRemoteClient = makeAndroidTVRemoteClient(ip: ip)
                    }
                    try await androidTVRemoteClient?.send(key, direction: direction)
                    await MainActor.run { status = .connected }
                } catch {
                    await MainActor.run { status = .failed }
                }
            }
        } else {
            send(key)
        }
    }

    func sendText(_ text: String) {
        guard canSend, selectedProvider == "Android TV" else {
            status = .needsAddress
            return
        }
        if text == "\u{8}" {
            let ip = androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines)
            sendTextTask?.cancel()
            sendTextTask = Task {
                do {
                    if androidTVRemoteClient == nil {
                        androidTVRemoteClient = makeAndroidTVRemoteClient(ip: ip)
                    }
                    try await androidTVRemoteClient?.sendKeyCode(67, direction: 3)
                    await MainActor.run { status = .connected }
                } catch {
                    await MainActor.run { status = .failed }
                }
            }
            return
        }
        if text == "\u{1B}" {
            return
        }
        sendTextTask?.cancel()
        sendTextTask = Task { [weak self] in
            guard let self else { return }
            let ip = androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                if androidTVRemoteClient == nil {
                    androidTVRemoteClient = makeAndroidTVRemoteClient(ip: ip)
                }
                try await androidTVRemoteClient?.sendText(text)
                await MainActor.run { status = .connected }
            } catch {
                await MainActor.run { status = .failed }
            }
        }
    }

    func testConnection() {
        guard canSend else {
            status = .needsAddress
            return
        }

        status = .testing

        if selectedProvider == "Android TV" {
            let ip = androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                let client = makeAndroidTVRemoteClient(ip: ip)
                let ok = await client.ping()
                if ok {
                    androidTVRemoteClient?.disconnect()
                    androidTVRemoteClient = client
                }
                await MainActor.run { status = ok ? .connected : .failed }
            }
        } else {
            let ip = decoderIP.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                let ok = await OrangeRemoteClient(decoderIP: ip).ping()
                await MainActor.run { status = ok ? .connected : .failed }
            }
        }
    }

    private func makeAndroidTVRemoteClient(ip: String) -> AndroidTVRemoteClient {
        let client = AndroidTVRemoteClient(host: ip, serviceName: androidTVServiceName)
        client.onTextInputRequest = { [weak self] in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.lastKeyboardDismissTime ?? .distantPast) > 0.5 else { return }
                self.isKeyboardVisible = true
            }
        }
        return client
    }

    func scanLocalNetwork() {
        cancelScan()
        guard !isScanning else { return }

        isScanning = true
        foundDecoders = []
        discoveredAndroidTV = []
        shouldAutoRetry = false
        status = .scanning

        let generation = scanGeneration + 1
        scanGeneration = generation

        scanTask = Task { [weak self] in
            defer {
                Task { @MainActor in
                    guard let self, self.scanGeneration == generation else { return }
                    self.isScanning = false
                    self.scanTask = nil
                }
            }
            guard let self else { return }

            if selectedProvider == "Android TV" {
                let devices = await discoverAndroidTV()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    discoveredAndroidTV = devices
                    if let first = devices.first {
                        androidTVIP = first.ip
                        status = androidTVPairedDevice.isEmpty ? .needsPairing : .connected
                    } else {
                        status = .notFound
                    }
                }
            } else {
                let base = await localIPv4Base() ?? "192.168.1"
                let hits = await scanOrange(base: base)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    foundDecoders = hits
                    if hits.isEmpty {
                        status = .notFound
                        shouldAutoRetry = true
                    } else {
                        status = .idle
                    }
                }
            }
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        if status == .scanning {
            status = .idle
        }
    }

    func beginAndroidTVPairing(_ device: DiscoveredAndroidTVDevice) {
        cancelPairing()
        androidTVIP = device.ip
        pendingAndroidTVPairing = device
        pairingMessage = "Connexion à \(device.name)…"
        status = .pairing

        Task {
            do {
                let session = try await AndroidTVPairingSession.start(
                    device: device,
                    clientServiceName: "RemoteGlass",
                    clientName: "RemoteGlass"
                )
                await MainActor.run {
                    pairingSession = session
                    pairingMessage = "Saisis le code affiché sur \(device.name)."
                    status = .pairing
                }
            } catch {
                await MainActor.run {
                    pairingMessage = "Impossible de lancer l'appairage : \(error.localizedDescription)"
                    status = .failed
                }
            }
        }
    }

    func finishAndroidTVPairing(pin: String) {
        guard let session = pairingSession,
              let device = pendingAndroidTVPairing else {
            pairingMessage = "Relance l'appairage."
            status = .failed
            return
        }

        pairingMessage = "Validation du code…"
        status = .pairing

        Task {
            do {
                try await session.finish(pin: pin)
                await MainActor.run {
                    androidTVIP = device.ip
                    androidTVPairedDevice = device.name
                    androidTVServiceName = device.serviceName
                    let saved = SavedGTVDevice(id: UUID(), name: device.name, ip: device.ip, serviceName: device.serviceName)
                    savedGTVDevices.removeAll { $0.ip == device.ip }
                    savedGTVDevices.append(saved)
                    discoveredAndroidTV = []
                    pairingSession = nil
                    pendingAndroidTVPairing = nil
                    pairingMessage = nil
                    status = .connected
                }
            } catch {
                await MainActor.run {
                    pairingMessage = "Code refusé ou appairage expiré : \(error.localizedDescription)"
                    status = .failed
                }
            }
        }
    }

    func cancelPairing() {
        pairingSession?.cancel()
        pairingSession = nil
        pendingAndroidTVPairing = nil
        pairingMessage = nil
        if status == .pairing {
            status = .idle
        }
    }

    func connectToSavedGTVDevice(_ device: SavedGTVDevice) {
        androidTVIP = device.ip
        androidTVPairedDevice = device.name
        androidTVServiceName = device.serviceName
        status = .testing
        testConnection()
    }

    func onActive() {
        if shouldAutoRetry || isScanning {
            shouldAutoRetry = false
            scanLocalNetwork()
        }
    }

    private func discoverAndroidTV() async -> [DiscoveredAndroidTVDevice] {
        await triggerLocalNetworkPermission()
        return await browseAndroidTVMDNS()
    }

    private nonisolated func triggerLocalNetworkPermission() async {
        // Force la permission réseau local (même si aucun appareil n'est trouvé)
        let probes = ["192.168.1.1", "192.168.0.1", "10.0.0.1"]
        for ip in probes {
            guard let url = URL(string: "http://\(ip):80/") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 0.5
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private var sanitizedIP: String {
        decoderIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func scanOrange(base: String) async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for host in 1...254 {
                let ip = "\(base).\(host)"
                group.addTask {
                    await Self.isOrangeDecoderReachable(ip: ip) ? ip : nil
                }
            }

            var results: [String] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results.sorted()
        }
    }

    private nonisolated static func isOrangeDecoderReachable(ip: String) async -> Bool {
        guard let url = URL(string: "http://\(ip):8080/remoteControl/cmd?operation=01&key=116&mode=2") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.7

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<500).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

enum ConnectionStatus: Equatable {
    case idle
    case needsAddress
    case scanning
    case pairing
    case needsPairing
    case notFound
    case testing
    case sending
    case connected
    case failed

    func title(for provider: String) -> String {
        switch self {
        case .idle: "Prêt"
        case .needsAddress: provider == "Android TV" ? "Adresse Google TV requise" : "Adresse requise"
        case .scanning: "Recherche…"
        case .pairing: "Appairage…"
        case .needsPairing: "Appairage requis"
        case .notFound: provider == "Android TV" ? "Aucun appareil Google TV trouvé" : "Aucun décodeur"
        case .testing: "Test…"
        case .sending: "Envoi…"
        case .connected: "Connecté"
        case .failed: "Injoignable"
        }
    }
}

// MARK: - Android TV Support (Google TV Remote Protocol)

struct DiscoveredAndroidTVDevice: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let ip: String
    let serviceName: String
    let port: UInt16
    let serviceType: String
    let serviceDomain: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ip == rhs.ip
    }
}

struct SavedGTVDevice: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let ip: String
    let serviceName: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Minimal Protobuf

private struct ProtoWriter {
    private var data = Data()

    mutating func tag(_ field: Int, _ wireType: Int) {
        varint(UInt64((field << 3) | wireType))
    }

    mutating func varint(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
    }

    mutating func int32(_ field: Int, _ value: Int32) {
        tag(field, 0)
        varint(UInt64(bitPattern: Int64(value)))
    }

    mutating func string(_ field: Int, _ value: String) {
        let raw = Data(value.utf8)
        tag(field, 2)
        varint(UInt64(raw.count))
        data.append(raw)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func message(_ field: Int, _ value: Data) {
        tag(field, 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    var encoded: Data { data }
}

private struct ProtoReader {
    private let data: Data
    private var offset = 0

    init(_ data: Data) { self.data = data }

    var isAtEnd: Bool { offset >= data.count }

    mutating func varint() -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count {
            let byte = data[offset]; offset += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    mutating func readTag() -> (Int, Int)? {
        guard let v = varint() else { return nil }
        return (Int(v >> 3), Int(v & 0x7))
    }

    mutating func int32() -> Int32? {
        guard let v = varint() else { return nil }
        return Int32(truncatingIfNeeded: v)
    }

    mutating func string() -> String? {
        guard let len = varint(), offset + Int(len) <= data.count else { return nil }
        let s = String(data: data[offset..<offset + Int(len)], encoding: .utf8)
        offset += Int(len)
        return s
    }

    mutating func dataValue() -> Data? {
        guard let len = varint(), offset + Int(len) <= data.count else { return nil }
        let chunk = data[offset..<offset + Int(len)]
        offset += Int(len)
        return chunk
    }

    mutating func skip(_ wireType: Int) {
        switch wireType {
        case 0: _ = varint()
        case 1: offset = min(offset + 8, data.count)
        case 2: if let len = varint() { offset = min(offset + Int(len), data.count) }
        case 5: offset = min(offset + 4, data.count)
        default: offset = data.count
        }
    }
}

// MARK: - mDNS discovery

private func browseAndroidTVMDNS() async -> [DiscoveredAndroidTVDevice] {
    let types = ["_androidtvremote2._tcp.", "_androidtvremote._tcp.", "_androidtv-remote._tcp."]
    var seen: [DiscoveredAndroidTVDevice] = []

    return await withTaskGroup(of: [DiscoveredAndroidTVDevice].self) { group in
        for type in types {
            group.addTask {
                await BonjourAndroidTVBrowser(type: type).browse()
            }
        }

        for await batch in group {
            for device in batch where !seen.contains(where: { $0.ip == device.ip }) {
                seen.append(device)
            }
        }
        return seen
    }
}

private final class BonjourAndroidTVBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let type: String
    private let domain = "local."
    private let lock = NSLock()
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var devices: [DiscoveredAndroidTVDevice] = []
    private var continuation: CheckedContinuation<[DiscoveredAndroidTVDevice], Never>?
    private var didFinish = false

    init(type: String) {
        self.type = type
    }

    func browse() async -> [DiscoveredAndroidTVDevice] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.continuation = continuation
                let browser = NetServiceBrowser()
                self.browser = browser
                browser.delegate = self
                browser.searchForServices(ofType: self.type, inDomain: self.domain)

                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    self.finish()
                }
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let ip = Self.preferredIPAddress(from: sender.addresses ?? []) else { return }
        lock.withLock {
            let device = DiscoveredAndroidTVDevice(
                name: sender.name,
                ip: ip,
                serviceName: sender.name,
                port: UInt16(max(sender.port, 0)),
                serviceType: type,
                serviceDomain: domain
            )
            if !devices.contains(device) {
                devices.append(device)
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        finish()
    }

    private func finish() {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let result = devices
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        browser?.stop()
        services.forEach { $0.stop() }
        continuation?.resume(returning: result)
    }

    private static func preferredIPAddress(from addresses: [Data]) -> String? {
        let candidates = addresses.compactMap(Self.ipAddress)
        return candidates.first(where: { !$0.contains(":") }) ?? candidates.first
    }

    private static func ipAddress(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let sockaddrPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                return nil
            }

            switch Int32(sockaddrPointer.pointee.sa_family) {
            case AF_INET:
                let ipv4 = rawBuffer.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                var address = ipv4.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return String(cString: buffer)

            case AF_INET6:
                let ipv6 = rawBuffer.baseAddress!.assumingMemoryBound(to: sockaddr_in6.self).pointee
                var address = ipv6.sin6_addr
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                    return nil
                }
                var ip = String(cString: buffer)
                if ipv6.sin6_scope_id != 0 {
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(ipv6.sin6_scope_id, &name) != nil {
                        ip += "%\(String(cString: name))"
                    }
                }
                return ip

            default:
                return nil
            }
        }
    }
}

private func resolveMDNSService(_ endpoint: NWEndpoint) async -> DiscoveredAndroidTVDevice? {
    guard case let .service(name, _, _, _) = endpoint else { return nil }

    let conn = NWConnection(to: endpoint, using: .tcp)

    return await withCheckedContinuation { continuation in
        let flag = ThreadSafeFlag()

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard !flag.set() else { return }
                let resolved: DiscoveredAndroidTVDevice? = {
                    guard let remote = conn.currentPath?.remoteEndpoint,
                          case let .hostPort(host, _) = remote else { return nil }
                    return DiscoveredAndroidTVDevice(
                        name: name,
                        ip: "\(host)",
                        serviceName: name,
                        port: 6466,
                        serviceType: "_androidtvremote2._tcp.",
                        serviceDomain: "local."
                    )
                }()
                conn.cancel()
                continuation.resume(returning: resolved)
            case .failed, .cancelled:
                guard !flag.set() else { return }
                conn.cancel()
                continuation.resume(returning: nil)
            default:
                break
            }
        }
        conn.start(queue: .global())

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            guard !flag.set() else { return }
            conn.cancel()
            continuation.resume(returning: nil)
        }
    }
}

// MARK: - Google TV Remote Protocol

private enum AndroidTVProtocolError: LocalizedError {
    case identityUnavailable
    case invalidCertificate
    case invalidFrame
    case pairingRejected
    case pairingFailed(Int32)
    case timedOut(String)
    case allPairingPortsFailed([String])

    var errorDescription: String? {
        switch self {
        case .identityUnavailable:
            "certificat client indisponible"
        case .invalidCertificate:
            "certificat TLS invalide"
        case .invalidFrame:
            "message protocole invalide"
        case .pairingRejected:
            "demande refusée par la Google TV"
        case .pairingFailed(let status):
            "statut \(status) du Google TV"
        case .timedOut(let stage):
            "timeout pendant \(stage)"
        case .allPairingPortsFailed(let errors):
            errors.joined(separator: " ; ")
        }
    }
}

private final class AndroidTVRemoteClient: @unchecked Sendable {
    let host: String
    let serviceName: String
    private var _connection: AndroidTVConnection?
    private let lock = OSAllocatedUnfairLock()
    private var keepaliveTask: Task<Void, Never>?
    private var receivingTask: Task<Void, Never>?

    init(host: String, serviceName: String) {
        self.host = host
        self.serviceName = serviceName
    }

    private var connection: AndroidTVConnection? {
        get { lock.withLock { _connection } }
        set { lock.withLock { _connection = newValue } }
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, let conn = self.connection, conn.isConnected else { break }
                try? await conn.sendFrame(AndroidTVRemoteMessage.active())
            }
        }
    }

    func ping() async -> Bool {
        do {
            try await send(.menu)
            return true
        } catch {
            return false
        }
    }

    private func ensureConnected() async throws -> AndroidTVConnection {
        if let existing = connection, existing.isConnected {
            return existing
        }
        disconnect()

        let conn = try await AndroidTVConnection.connect(
            host: host,
            port: 6466,
            purpose: "connexion remote 6466",
            identity: try AndroidTVIdentityStore.identity(commonName: serviceName.isEmpty ? "RemoteGlass" : serviceName),
            capturePeerCertificate: false
        )

        _ = try? await conn.receiveFrame(timeout: 1.2, purpose: "message remote initial")
        try await conn.sendFrame(AndroidTVRemoteMessage.configure())
        _ = try? await conn.receiveFrame(timeout: 1.2, purpose: "ack remote configure")
        try await conn.sendFrame(AndroidTVRemoteMessage.active())

        connection = conn
        startKeepalive()
        startReceiving(conn)
        return conn
    }

    private func startReceiving(_ conn: AndroidTVConnection) {
        receivingTask?.cancel()
        receivingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                do {
                    let data = try await conn.receive()
                    if Self.isImeShowRequest(data) {
                        onTextInputRequest?()
                    }
                } catch {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    private static func isImeShowRequest(_ data: Data) -> Bool {
        var reader = ProtoReader(data)
        while !reader.isAtEnd {
            guard let (field, wire) = reader.readTag() else { break }
            if field >= 21 && field <= 24 { return true }
            reader.skip(wire)
        }
        return false
    }

    func send(_ key: OrangeKey, direction: Int32 = 3) async throws {
        try await sendKeyCode(key.androidKeyCode, direction: direction)
    }

    func sendKeyCode(_ keyCode: Int, direction: Int32 = 3) async throws {
        do {
            let conn = try await ensureConnected()
            try await conn.sendFrame(AndroidTVRemoteMessage.keyInject(keyCode, direction: direction))
        } catch {
            disconnect()
            let conn = try await ensureConnected()
            try await conn.sendFrame(AndroidTVRemoteMessage.keyInject(keyCode, direction: direction))
        }
    }

    func sendText(_ text: String) async throws {
        let conn = try await ensureConnected()
        try await conn.sendFrame(AndroidTVRemoteMessage.setText(text))
    }

    func disconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        receivingTask?.cancel()
        receivingTask = nil
        lock.withLock {
            _connection?.cancel()
            _connection = nil
        }
    }

    var onTextInputRequest: (@Sendable () -> Void)?

    deinit {
        disconnect()
    }
}

private final class AndroidTVPairingSession: @unchecked Sendable {
    private let connection: AndroidTVConnection
    private let peerCertificate: Data
    private let clientCertificate: Data

    private init(connection: AndroidTVConnection, peerCertificate: Data, clientCertificate: Data) {
        self.connection = connection
        self.peerCertificate = peerCertificate
        self.clientCertificate = clientCertificate
    }

    static func start(device: DiscoveredAndroidTVDevice, clientServiceName: String, clientName: String) async throws -> AndroidTVPairingSession {
        var failures: [String] = []

        do {
            return try await start(host: device.ip, port: 6467, clientServiceName: clientServiceName, clientName: clientName)
        } catch {
            failures.append("IP \(device.ip):6467: \(error.localizedDescription)")
        }

        do {
            let endpoint = NWEndpoint.service(
                name: device.serviceName,
                type: device.serviceType,
                domain: device.serviceDomain,
                interface: nil
            )
            return try await start(endpoint: endpoint, purpose: "connexion TLS service Bonjour \(device.serviceName)", clientServiceName: clientServiceName, clientName: clientName)
        } catch {
            failures.append("service Bonjour \(device.serviceName): \(error.localizedDescription)")
        }

        if device.port > 0, device.port != 6467 {
            do {
                return try await start(host: device.ip, port: device.port, clientServiceName: clientServiceName, clientName: clientName)
            } catch {
                failures.append("IP \(device.ip):\(device.port): \(error.localizedDescription)")
            }
        }

        throw AndroidTVProtocolError.allPairingPortsFailed(failures)
    }

    private static func start(host: String, port: UInt16, clientServiceName: String, clientName: String) async throws -> AndroidTVPairingSession {
        try await start(
            endpoint: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!),
            purpose: "connexion TLS \(port)",
            clientServiceName: clientServiceName,
            clientName: clientName
        )
    }

    private static func start(endpoint: NWEndpoint, purpose: String, clientServiceName: String, clientName: String) async throws -> AndroidTVPairingSession {
        let identity = try AndroidTVIdentityStore.identity(commonName: clientServiceName)
        let clientCertificate = try AndroidTVIdentityStore.certificateData(commonName: clientServiceName)
        let connection = try await AndroidTVConnection.connect(
            endpoint: endpoint,
            purpose: purpose,
            identity: identity,
            capturePeerCertificate: true
        )

        guard let peerCertificate = connection.peerCertificateData else {
            connection.cancel()
            throw AndroidTVProtocolError.invalidCertificate
        }

        let session = AndroidTVPairingSession(
            connection: connection,
            peerCertificate: peerCertificate,
            clientCertificate: clientCertificate
        )
        try await connection.sendFrame(AndroidTVPairingMessage.pairingRequest(serviceName: clientServiceName, clientName: clientName))
        let requestAck = try await connection.receiveFrame(timeout: 4, purpose: "réponse PairingRequest")
        guard AndroidTVPairingMessage.hasField(11, in: requestAck), AndroidTVPairingMessage.status(requestAck) == 200 else {
            connection.cancel()
            throw AndroidTVProtocolError.pairingRejected
        }
        try await connection.sendFrame(AndroidTVPairingMessage.pairingOption())
        let option = try await connection.receiveFrame(timeout: 4, purpose: "réponse PairingOption")
        guard AndroidTVPairingMessage.hasField(20, in: option), AndroidTVPairingMessage.status(option) == 200 else {
            connection.cancel()
            throw AndroidTVProtocolError.pairingRejected
        }
        try await connection.sendFrame(AndroidTVPairingMessage.pairingConfiguration())
        let configurationAck = try await connection.receiveFrame(timeout: 4, purpose: "réponse PairingConfiguration")
        guard AndroidTVPairingMessage.hasField(31, in: configurationAck), AndroidTVPairingMessage.status(configurationAck) == 200 else {
            connection.cancel()
            throw AndroidTVProtocolError.pairingRejected
        }
        return session
    }

    func finish(pin: String) async throws {
        let normalized = pin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let secret = try AndroidTVPairingMessage.secret(
            pin: normalized,
            clientCertificate: clientCertificate,
            serverCertificate: peerCertificate
        )
        try await connection.sendFrame(AndroidTVPairingMessage.pairingSecret(secret))
        let response = try await connection.receiveFrame(timeout: 5, purpose: "réponse PairingSecret")
        let st = AndroidTVPairingMessage.status(response) ?? -1
        guard st == 200, AndroidTVPairingMessage.hasField(41, in: response) else {
            throw AndroidTVProtocolError.pairingFailed(st)
        }
        connection.cancel()
    }

    func cancel() {
        connection.cancel()
    }
}

private final class AndroidTVConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "RemoteGlass.GoogleTVConnection")
    private(set) var peerCertificateData: Data?
    private(set) var isConnected = false

    private init(connection: NWConnection) {
        self.connection = connection
    }

    static func connect(
        host: String,
        port: UInt16,
        purpose: String,
        identity: SecIdentity,
        capturePeerCertificate: Bool
    ) async throws -> AndroidTVConnection {
        try await connect(
            endpoint: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!),
            purpose: purpose,
            identity: identity,
            capturePeerCertificate: capturePeerCertificate
        )
    }

    static func connect(
        endpoint: NWEndpoint,
        purpose: String,
        identity: SecIdentity,
        capturePeerCertificate: Bool
    ) async throws -> AndroidTVConnection {
        let tls = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        guard let tlsIdentity = sec_identity_create(identity) else {
            throw AndroidTVProtocolError.identityUnavailable
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, tlsIdentity)

        final class PeerCert: @unchecked Sendable {
            var data: Data?
        }
        let captured = PeerCert()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { metadata, trust, complete in
            if capturePeerCertificate {
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate]
                if let certificate = chain?.first {
                    captured.data = SecCertificateCopyData(certificate) as Data
                }
            }
            complete(true)
        }, DispatchQueue(label: "RemoteGlass.GoogleTVVerify"))

        let options = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let wrapper = AndroidTVConnection(
            connection: NWConnection(
                to: endpoint,
                using: options
            )
        )

        return try await withCheckedThrowingContinuation { continuation in
            let flag = ThreadSafeFlag()

            wrapper.connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    wrapper.isConnected = true
                    guard !flag.set() else { return }
                    wrapper.peerCertificateData = captured.data
                    continuation.resume(returning: wrapper)
                case .failed(let error):
                    wrapper.isConnected = false
                    guard !flag.set() else { return }
                    wrapper.connection.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    wrapper.isConnected = false
                default:
                    break
                }
            }

            wrapper.connection.start(queue: wrapper.queue)
            wrapper.queue.asyncAfter(deadline: .now() + 5) {
                guard !flag.set() else { return }
                wrapper.connection.cancel()
                continuation.resume(throwing: AndroidTVProtocolError.timedOut(purpose))
            }
        }
    }

    func sendFrame(_ data: Data) async throws {
        var frame = Self.varint(UInt64(data.count))
        frame.append(data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receiveFrame(timeout: TimeInterval, purpose: String) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [connection] in
                let length = try await Self.receiveVarint(from: connection)
                guard length > 0, length <= 1024 * 1024 else {
                    throw AndroidTVProtocolError.invalidFrame
                }
                return try await Self.receiveExact(Int(length), from: connection)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AndroidTVProtocolError.timedOut(purpose)
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    func receive() async throws -> Data {
        let length = try await Self.receiveVarint(from: connection)
        guard length > 0, length <= 1024 * 1024 else {
            throw AndroidTVProtocolError.invalidFrame
        }
        return try await Self.receiveExact(Int(length), from: connection)
    }

    func cancel() {
        connection.cancel()
    }

    private static func varint(_ value: UInt64) -> Data {
        var data = Data()
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
        return data
    }

    private static func receiveVarint(from connection: NWConnection) async throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0

        while shift < 64 {
            let byteData = try await receiveExact(1, from: connection)
            let byte = byteData[byteData.startIndex]
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
        }

        throw AndroidTVProtocolError.invalidFrame
    }

    private static func receiveExact(_ length: Int, from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == length {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: AndroidTVProtocolError.invalidFrame)
                }
            }
        }
    }
}

private enum AndroidTVRemoteMessage {
    static func configure() -> Data {
        var device = ProtoWriter()
        device.string(1, "RemoteGlass")
        device.string(2, "Apple")
        device.int32(3, 1)
        device.string(4, "iPhone")
        device.string(5, "RemoteGlass")
        device.string(6, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")

        var configure = ProtoWriter()
        configure.int32(1, 622)
        configure.message(2, device.encoded)

        var message = ProtoWriter()
        message.message(1, configure.encoded)
        return message.encoded
    }

    static func active() -> Data {
        var active = ProtoWriter()
        active.int32(1, 622)

        var message = ProtoWriter()
        message.message(2, active.encoded)
        return message.encoded
    }

    static func keyInject(_ keyCode: Int, direction: Int32) -> Data {
        var key = ProtoWriter()
        key.int32(1, Int32(keyCode))
        key.int32(2, direction)

        var message = ProtoWriter()
        message.message(10, key.encoded)
        return message.encoded
    }

    static func setText(_ text: String) -> Data {
        var imeObject = ProtoWriter()
        imeObject.int32(1, 0)
        imeObject.int32(2, 0)
        imeObject.string(3, text)

        var editInfo = ProtoWriter()
        editInfo.int32(1, 1)
        editInfo.message(2, imeObject.encoded)

        var batchEdit = ProtoWriter()
        batchEdit.int32(1, 0)
        batchEdit.int32(2, 0)
        batchEdit.message(3, editInfo.encoded)

        var message = ProtoWriter()
        message.message(21, batchEdit.encoded)
        return message.encoded
    }
}

private enum AndroidTVPairingMessage {
    static func pairingRequest(serviceName: String, clientName: String) -> Data {
        var request = ProtoWriter()
        request.string(1, serviceName)
        request.string(2, clientName)

        var message = ProtoWriter()
        message.int32(1, 2)
        message.int32(2, 200)
        message.message(10, request.encoded)
        return message.encoded
    }

    static func pairingOption() -> Data {
        var encoding = ProtoWriter()
        encoding.int32(1, 3)
        encoding.int32(2, 6)

        var option = ProtoWriter()
        option.message(1, encoding.encoded)
        option.int32(3, 1)

        var message = ProtoWriter()
        message.int32(1, 2)
        message.int32(2, 200)
        message.message(20, option.encoded)
        return message.encoded
    }

    static func pairingConfiguration() -> Data {
        var encoding = ProtoWriter()
        encoding.int32(1, 3)
        encoding.int32(2, 6)

        var configuration = ProtoWriter()
        configuration.message(1, encoding.encoded)
        configuration.int32(2, 1)

        var message = ProtoWriter()
        message.int32(1, 2)
        message.int32(2, 200)
        message.message(30, configuration.encoded)
        return message.encoded
    }

    static func pairingSecret(_ secret: Data) -> Data {
        var secretMessage = ProtoWriter()
        secretMessage.bytes(1, secret)

        var message = ProtoWriter()
        message.int32(1, 2)
        message.int32(2, 200)
        message.message(40, secretMessage.encoded)
        return message.encoded
    }

    static func secret(pin: String, clientCertificate: Data, serverCertificate: Data) throws -> Data {
        guard let clientKey = certificatePublicKeyParts(clientCertificate),
              let serverKey = certificatePublicKeyParts(serverCertificate) else {
            throw AndroidTVProtocolError.invalidCertificate
        }

        let code = Data(hexString: pin) ?? Data(pin.utf8)

        var hasher = SHA256()
        hasher.update(data: clientKey.modulus)
        hasher.update(data: clientKey.exponent)
        hasher.update(data: serverKey.modulus)
        hasher.update(data: serverKey.exponent)
        hasher.update(data: code.dropFirst())
        return Data(hasher.finalize())
    }

    static func isOK(_ data: Data) -> Bool {
        status(data) == 200 && hasField(41, in: data)
    }

    static func status(_ data: Data) -> Int32? {
        var reader = ProtoReader(data)
        while let (field, wire) = reader.readTag() {
            if field == 2, wire == 0 {
                return reader.int32()
            }
            reader.skip(wire)
        }
        return nil
    }

    static func hasField(_ searchedField: Int, in data: Data) -> Bool {
        var reader = ProtoReader(data)
        while let (field, wire) = reader.readTag() {
            if field == searchedField {
                return true
            }
            reader.skip(wire)
        }
        return false
    }

    private static func certificatePublicKeyParts(_ certificateData: Data) -> (modulus: Data, exponent: Data)? {
        if let result = DER.rsaKeyPartsFromCertificateDER(certificateData) {
            return result
        }
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData),
              let key = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        return DER.rsaPublicKeyParts(keyData)
    }
}

private enum AndroidTVIdentityStore {
    private static let pkcs12Password = "RemoteGlass"
    private static let pkcs12Base64 = """
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
"""
    private static let keyTag = "com.remoteglass.googletv.identity.key".data(using: .utf8)!
    private static let certificateKey = "com.remoteglass.googletv.identity.certificate"
    private static let certificateCommonNameKey = "com.remoteglass.googletv.identity.commonName"
    private static let certificateLabel = "RemoteGlass Google TV"

    static var hasIdentity: Bool {
        (try? identity(commonName: "RemoteGlass")) != nil
    }

    static func identity(commonName: String) throws -> SecIdentity {
        try importedIdentity()
    }

    static func certificateData(commonName: String) throws -> Data {
        let identity = try importedIdentity()
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
              let certificate else {
            throw AndroidTVProtocolError.identityUnavailable
        }
        return SecCertificateCopyData(certificate) as Data
    }

    private static func importedIdentity() throws -> SecIdentity {
        guard let p12 = Data(base64Encoded: pkcs12Base64) else {
            throw AndroidTVProtocolError.identityUnavailable
        }

        let options = [kSecImportExportPassphrase as String: pkcs12Password] as CFDictionary
        var rawItems: CFArray?
        let status = SecPKCS12Import(p12 as CFData, options, &rawItems)
        guard status == errSecSuccess,
              let items = rawItems as? [[String: Any]],
              let identity = items.first?[kSecImportItemIdentity as String] else {
            throw AndroidTVProtocolError.identityUnavailable
        }
        return identity as! SecIdentity
    }

    private static func loadIdentity() throws -> SecIdentity {
        guard let expectedCertificateData = UserDefaults.standard.data(forKey: certificateKey) else {
            throw AndroidTVProtocolError.identityUnavailable
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw AndroidTVProtocolError.identityUnavailable
        }

        let identities: [SecIdentity]
        if let one = item as! SecIdentity? {
            identities = [one]
        } else if let many = item as? [SecIdentity] {
            identities = many
        } else {
            identities = []
        }

        for identity in identities {
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
                  let certificate,
                  SecCertificateCopyData(certificate) as Data == expectedCertificateData else {
                continue
            }
            return identity
        }

        throw AndroidTVProtocolError.identityUnavailable
    }

    private static func createIdentity(commonName: String) throws {
        let privateKey = try privateKey()
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw AndroidTVProtocolError.identityUnavailable
        }

        let certificate = try SelfSignedCertificate.make(
            privateKey: privateKey,
            publicKeyPKCS1: publicKeyData,
            commonName: commonName
        )
        UserDefaults.standard.set(certificate, forKey: certificateKey)
        UserDefaults.standard.set(commonName, forKey: certificateCommonNameKey)
        if let secCertificate = SecCertificateCreateWithData(nil, certificate as CFData) {
            SecItemDelete([
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: certificateLabel
            ] as CFDictionary)
            SecItemAdd([
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: secCertificate,
                kSecAttrLabel as String: certificateLabel
            ] as CFDictionary, nil)
        }
    }

    private static func privateKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let key = item as! SecKey? {
            return key
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: keyTag
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? AndroidTVProtocolError.identityUnavailable
        }
        return key
    }
}

private enum SelfSignedCertificate {
    static func make(privateKey: SecKey, publicKeyPKCS1: Data, commonName: String) throws -> Data {
        let validity = DER.sequence([
            DER.utcTime(Date(timeIntervalSinceNow: -3600)),
            DER.utcTime(Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 20))
        ])
        let name = DER.sequence([
            DER.set([
                DER.sequence([
                    DER.objectIdentifier([2, 5, 4, 3]),
                    DER.utf8String(commonName)
                ])
            ])
        ])
        let algorithm = DER.sequence([
            DER.objectIdentifier([1, 2, 840, 113549, 1, 1, 11]),
            DER.null()
        ])
        let rsaAlgorithm = DER.sequence([
            DER.objectIdentifier([1, 2, 840, 113549, 1, 1, 1]),
            DER.null()
        ])
        let subjectPublicKeyInfo = DER.sequence([
            rsaAlgorithm,
            DER.bitString(publicKeyPKCS1)
        ])
        let tbs = DER.sequence([
            DER.explicit(0, DER.integer(2)),
            DER.integer(Int.random(in: 1...Int(Int32.max))),
            algorithm,
            name,
            validity,
            name,
            subjectPublicKeyInfo
        ])

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbs as CFData,
            &error
        ) as Data? else {
            throw error?.takeRetainedValue() ?? AndroidTVProtocolError.identityUnavailable
        }

        return DER.sequence([
            tbs,
            algorithm,
            DER.bitString(signature)
        ])
    }
}

private enum DER {
    static func sequence(_ values: [Data]) -> Data { tagged(0x30, values.reduce(Data(), +)) }
    static func set(_ values: [Data]) -> Data { tagged(0x31, values.reduce(Data(), +)) }
    static func explicit(_ tag: UInt8, _ value: Data) -> Data { tagged(0xA0 + tag, value) }
    static func null() -> Data { Data([0x05, 0x00]) }
    static func utf8String(_ value: String) -> Data { tagged(0x0C, Data(value.utf8)) }
    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tagged(0x17, Data(formatter.string(from: date).utf8))
    }

    static func integer(_ value: Int) -> Data {
        var bytes: [UInt8] = []
        var v = value
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return tagged(0x02, Data(bytes))
    }

    static func objectIdentifier(_ components: [Int]) -> Data {
        guard components.count >= 2 else { return tagged(0x06, Data()) }
        var body = Data([UInt8(components[0] * 40 + components[1])])
        for component in components.dropFirst(2) {
            var stack = [UInt8(component & 0x7F)]
            var value = component >> 7
            while value > 0 {
                stack.insert(UInt8(value & 0x7F) | 0x80, at: 0)
                value >>= 7
            }
            body.append(contentsOf: stack)
        }
        return tagged(0x06, body)
    }

    static func bitString(_ value: Data) -> Data {
        var body = Data([0])
        body.append(value)
        return tagged(0x03, body)
    }

    static func rsaPublicKeyParts(_ data: Data) -> (modulus: Data, exponent: Data)? {
        var reader = DERReader(data)
        guard reader.readTag() == 0x30,
              let sequenceLength = reader.readLength() else {
            return nil
        }
        let end = reader.offset + sequenceLength
        guard reader.offset < end,
              reader.readTag() == 0x02,
              let modulusLength = reader.readLength(),
              let modulus = reader.readData(count: modulusLength),
              reader.offset < end,
              reader.readTag() == 0x02,
              let exponentLength = reader.readLength(),
              let exponent = reader.readData(count: exponentLength) else {
            return nil
        }
        return (stripLeadingZero(modulus), exponent)
    }

    private static func tagged(_ tag: UInt8, _ value: Data) -> Data {
        var data = Data([tag])
        data.append(length(value.count))
        data.append(value)
        return data
    }

    private static func length(_ count: Int) -> Data {
        if count < 128 {
            return Data([UInt8(count)])
        }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    private static func stripLeadingZero(_ data: Data) -> Data {
        var bytes = data
        while bytes.count > 1 && bytes.first == 0 {
            bytes.removeFirst()
        }
        return bytes
    }

    static func rsaKeyPartsFromCertificateDER(_ certData: Data) -> (modulus: Data, exponent: Data)? {
        var reader = DERReader(certData)

        guard reader.readTag() == 0x30, reader.readLength() != nil else { return nil }

        guard reader.readTag() == 0x30, let tbsLen = reader.readLength() else { return nil }
        let tbsEnd = reader.offset + tbsLen

        if reader.offset < tbsEnd, reader.peekTag() == 0xA0 {
            guard reader.readTag() == 0xA0, let len = reader.readLength() else { return nil }
            reader.offset += len
        }

        for _ in 0..<5 {
            guard reader.offset < tbsEnd else { return nil }
            guard reader.readTag() != nil, let len = reader.readLength() else { return nil }
            reader.offset += len
        }

        guard reader.offset < tbsEnd, reader.readTag() == 0x30, let spkiLen = reader.readLength() else { return nil }
        let spkiEnd = reader.offset + spkiLen

        guard reader.offset < spkiEnd else { return nil }
        guard reader.readTag() != nil, let algLen = reader.readLength() else { return nil }
        reader.offset += algLen

        guard reader.readTag() == 0x03, let bsLen = reader.readLength() else { return nil }
        let bsEnd = reader.offset + bsLen
        guard reader.offset < bsEnd, reader.readByte() == 0 else { return nil }

        return rsaPublicKeyParts(Data(reader.data[reader.offset...]))
    }
}

private struct DERReader {
    let data: Data
    var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    mutating func readTag() -> UInt8? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readLength() -> Int? {
        guard offset < data.count else { return nil }
        let first = data[offset]
        offset += 1
        if first < 0x80 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7F)
        guard byteCount > 0, offset + byteCount <= data.count else { return nil }
        var length = 0
        for _ in 0..<byteCount {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
        return length
    }

    mutating func readData(count: Int) -> Data? {
        guard count >= 0, offset + count <= data.count else { return nil }
        defer { offset += count }
        return data[offset..<offset + count]
    }

    func peekTag() -> UInt8? {
        guard offset < data.count else { return nil }
        return data[offset]
    }

    mutating func readByte() -> UInt8? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
    }
}

private extension Data {
    init?(hexString: String) {
        let sanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitized.count % 2 == 0 else { return nil }

        var bytes = Data()
        var index = sanitized.startIndex
        while index < sanitized.endIndex {
            let next = sanitized.index(index, offsetBy: 2)
            guard let byte = UInt8(sanitized[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = bytes
    }
}

private final class ThreadSafeFlag: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    @discardableResult
    func set() -> Bool {
        lock.lock()
        if _value { lock.unlock(); return true }
        _value = true
        lock.unlock()
        return false
    }
}

private final class SendableEndpointList: @unchecked Sendable {
    private var endpoints: [NWEndpoint] = []
    private let lock = NSLock()

    var values: [NWEndpoint] { lock.withLock { endpoints } }

    func merge(_ new: [NWEndpoint]) {
        lock.withLock {
            for ep in new where !endpoints.contains(ep) {
                endpoints.append(ep)
            }
        }
    }
}

private final class SendableDeviceList: @unchecked Sendable {
    private var devices: [DiscoveredAndroidTVDevice] = []
    private let lock = NSLock()

    var values: [DiscoveredAndroidTVDevice] { lock.withLock { devices } }

    func append(_ device: DiscoveredAndroidTVDevice) {
        lock.withLock {
            if !devices.contains(device) {
                devices.append(device)
            }
        }
    }
}

func localIPv4Base() async -> String? {
    await withCheckedContinuation { continuation in
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            continuation.resume(returning: nil)
            return
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family

            guard family == UInt8(AF_INET),
                  let name = String(validatingCString: interface.ifa_name),
                  name == "en0" || name == "en1" else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            let ip = String(decoding: hostname.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
            let parts = ip.split(separator: ".")
            if parts.count == 4 {
                address = parts.prefix(3).joined(separator: ".")
                break
            }
        }

        continuation.resume(returning: address)
    }
}

extension Color {
    var hex: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6, let int = Int(sanitized, radix: 16) else { return nil }
        self.init(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum ButtonShape: String, CaseIterable, Identifiable {
    case squircle
    case circle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .squircle: "Squircle"
        case .circle: "Circulaire"
        }
    }
}
