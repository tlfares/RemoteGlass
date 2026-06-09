import SwiftUI
import UIKit
import Network

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
    @Published var bgColor1: Color {
        didSet { UserDefaults.standard.set(bgColor1.hex, forKey: Self.bgColor1Key) }
    }
    @Published var bgColor2: Color {
        didSet { UserDefaults.standard.set(bgColor2.hex, forKey: Self.bgColor2Key) }
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

    private static let decoderIPKey = "decoderIP"
    private static let bgColor1Key = "bgColor1"
    private static let bgColor2Key = "bgColor2"
    private static let bgWeightKey = "bgWeight"
    private static let bgSpreadKey = "bgSpread"
    private static let bgTintKey = "bgTint"
    private static let bgButtonShapeKey = "bgButtonShape"
    private static let bgDisableStretchKey = "bgDisableStretch"

    private static var bgImageURL: URL {
        URL.documentsDirectory.appendingPathComponent("bgImage.jpg")
    }

    init() {
        decoderIP = UserDefaults.standard.string(forKey: Self.decoderIPKey) ?? ""
        bgColor1 = Color(hex: UserDefaults.standard.string(forKey: Self.bgColor1Key) ?? "") ?? Color(hex: "000000") ?? .black
        bgColor2 = Color(hex: UserDefaults.standard.string(forKey: Self.bgColor2Key) ?? "") ?? Color(hex: "FF6A00") ?? .orange
        bgImageData = try? Data(contentsOf: Self.bgImageURL)
        bgWeight = UserDefaults.standard.object(forKey: Self.bgWeightKey) as? Double ?? 0.5
        bgSpread = UserDefaults.standard.object(forKey: Self.bgSpreadKey) as? Double ?? 0.5
        let majorVersion = Int(UIDevice.current.systemVersion.split(separator: ".").first ?? "") ?? 0
        bgTint = UserDefaults.standard.object(forKey: Self.bgTintKey) as? Double ?? (majorVersion >= 27 ? 0.5 : 0)
        bgButtonShape = UserDefaults.standard.string(forKey: Self.bgButtonShapeKey)
            .flatMap(ButtonShape.init(rawValue:)) ?? .squircle
        bgDisableStretch = UserDefaults.standard.object(forKey: Self.bgDisableStretchKey) as? Bool ?? false
    }

    var canSend: Bool {
        !decoderIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send(_ key: OrangeKey) {
        guard canSend else {
            status = .needsAddress
            return
        }

        status = .sending
        let ip = sanitizedIP

        Task {
            do {
                try await OrangeRemoteClient(decoderIP: ip).send(key)
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
        let ip = sanitizedIP

        Task {
            let ok = await OrangeRemoteClient(decoderIP: ip).ping()
            await MainActor.run { status = ok ? .connected : .failed }
        }
    }

    func scanLocalNetwork() {
        guard !isScanning else { return }

        isScanning = true
        foundDecoders = []
        shouldAutoRetry = false
        status = .scanning

        Task {
            let base = await localIPv4Base() ?? "192.168.1"
            let hits = await scan(base: base)

            await MainActor.run {
                foundDecoders = hits
                if let first = hits.first {
                    decoderIP = first
                    status = .connected
                    shouldAutoRetry = false
                } else {
                    status = .notFound
                    shouldAutoRetry = true
                }
                isScanning = false
            }
        }
    }

    func onActive() {
        if shouldAutoRetry {
            shouldAutoRetry = false
            scanLocalNetwork()
        }
    }

    private var sanitizedIP: String {
        decoderIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func scan(base: String) async -> [String] {
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
    case notFound
    case testing
    case sending
    case connected
    case failed

    var title: String {
        switch self {
        case .idle: "Prêt"
        case .needsAddress: "Adresse requise"
        case .scanning: "Recherche"
        case .notFound: "Aucun décodeur"
        case .testing: "Test"
        case .sending: "Envoi"
        case .connected: "Connecté"
        case .failed: "Injoignable"
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
