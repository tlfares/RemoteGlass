import SwiftUI
import UIKit
import ImageIO

// MARK: - Types d'appareils

enum DeviceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case orange
    case sfr
    case freebox
    case androidTV
    case lgWebOS
    case samsung
    case roku
    case hisense

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orange: String(localized: "Décodeur Orange")
        case .sfr: String(localized: "Décodeur SFR")
        case .freebox: String(localized: "Freebox Player")
        case .androidTV: String(localized: "Google TV / Android TV")
        case .lgWebOS: String(localized: "TV LG webOS")
        case .samsung: String(localized: "TV Samsung")
        case .roku: String(localized: "Roku")
        case .hisense: String(localized: "TV Hisense VIDAA")
        }
    }

    var shortName: String {
        switch self {
        case .orange: "Orange"
        case .sfr: "SFR"
        case .freebox: "Freebox"
        case .androidTV: "Google TV"
        case .lgWebOS: "LG"
        case .samsung: "Samsung"
        case .roku: "Roku"
        case .hisense: "Hisense"
        }
    }

    var systemImage: String {
        switch self {
        case .orange, .sfr, .freebox: "tv.and.mediabox"
        case .androidTV: "play.tv"
        case .lgWebOS, .samsung, .hisense: "tv"
        case .roku: "tv.badge.wifi"
        }
    }

    /// Une TV « écran » : elle peut servir de TV associée à un décodeur (power + volume).
    var isTelevision: Bool {
        switch self {
        case .orange, .sfr, .freebox: false
        case .androidTV, .lgWebOS, .samsung, .roku, .hisense: true
        }
    }

    var defaultLayout: RemoteLayout {
        isTelevision || self == .androidTV ? .trackpad : .classic
    }

    /// Bouton « Source » (sélecteur d'entrée HDMI…). Hisense VIDAA n'expose pas de touche fiable.
    var supportsInput: Bool {
        isTelevision && self != .hisense
    }

    var supportsKeyboard: Bool {
        switch self {
        case .orange, .sfr, .freebox, .hisense: false
        case .androidTV, .lgWebOS, .samsung, .roku: true
        }
    }

    /// Appui long réel (key down / key up) plutôt qu'un simple tap.
    var supportsLongPress: Bool {
        switch self {
        case .androidTV, .roku, .samsung: true
        case .orange, .sfr, .freebox, .lgWebOS, .hisense: false
        }
    }

    var accent: Color {
        switch self {
        case .orange: .orange
        case .sfr: Color(hex: "E2001A") ?? .red
        case .freebox: Color(hex: "CD1E25") ?? .red
        case .androidTV: .blue
        case .lgWebOS: Color(hex: "C6004B") ?? .pink
        case .samsung: Color(hex: "1E50D6") ?? .blue
        case .roku: .purple
        case .hisense: Color(hex: "00A99D") ?? .teal
        }
    }

    var defaultColors: [Color] {
        switch self {
        case .orange:
            [Color(hex: "000000") ?? .black, Color(hex: "FF6A00") ?? .orange]
        case .sfr:
            [Color(hex: "000000") ?? .black, Color(hex: "B30015") ?? .red]
        case .freebox:
            [Color(hex: "000000") ?? .black, Color(hex: "8E1418") ?? .red]
        case .androidTV:
            [
                Color(hex: "000000") ?? .black,
                Color(hex: "4285F4") ?? .blue,
                Color(hex: "34A853") ?? .green,
                Color(hex: "EA4335") ?? .red,
                Color(hex: "FBBC04") ?? .yellow,
            ]
        case .lgWebOS:
            [Color(hex: "000000") ?? .black, Color(hex: "A50034") ?? .red]
        case .samsung:
            [Color(hex: "000000") ?? .black, Color(hex: "1428A0") ?? .blue]
        case .roku:
            [Color(hex: "000000") ?? .black, Color(hex: "6C3C97") ?? .purple]
        case .hisense:
            [Color(hex: "000000") ?? .black, Color(hex: "00877C") ?? .teal]
        }
    }

    /// Ce que l'utilisateur doit faire pendant l'appairage.
    var pairingHint: String? {
        switch self {
        case .orange, .sfr, .roku: nil
        case .freebox: String(localized: "Saisis le code télécommande réseau : sur la TV, Réglages › Système › Informations Freebox Player et Server.")
        case .androidTV, .hisense: String(localized: "Saisis le code affiché sur la TV.")
        case .lgWebOS, .samsung: String(localized: "Accepte la demande de connexion qui s'affiche sur la TV.")
        }
    }

    var compatibilityNote: String {
        switch self {
        case .orange: String(localized: "Tous les décodeurs TV Orange")
        case .sfr: String(localized: "Décodeur TV SFR 4K (STB7), LaBox, décodeur Box 8. Le SFR Connect TV passe par Google TV.")
        case .freebox: String(localized: "Freebox Révolution, Crystal, Delta et One. Pop, Ultra et Mini 4K passent par Google TV.")
        case .androidTV: String(localized: "Free Player Pop, Bbox, SFR Connect TV, Sony, TCL, Philips, Chromecast…")
        case .lgWebOS: String(localized: "TV LG depuis 2014")
        case .samsung: String(localized: "TV Samsung Tizen depuis 2016")
        case .roku: String(localized: "Roku TV, Express, Streaming Stick")
        case .hisense: String(localized: "TV Hisense / Toshiba VIDAA (selon le firmware). Les Hisense Google TV ou Roku passent par ces protocoles.")
        }
    }
}

enum RemoteLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case trackpad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: String(localized: "Classique")
        case .trackpad: String(localized: "Trackpad")
        }
    }

    var systemImage: String {
        switch self {
        case .classic: "square.grid.3x3"
        case .trackpad: "rectangle.3.group"
        }
    }
}

// MARK: - Appareil enregistré

struct SavedDevice: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: DeviceKind
    var name: String
    var ip: String
    var mac: String?
    /// Google TV : nom de service Bonjour utilisé pour l'identité TLS.
    var serviceName: String?
    /// LG : client-key. Samsung : token.
    var token: String?
    /// Volume appliqué automatiquement en passant sur une entrée (identifiant d'entrée → niveau).
    var sourceVolumes: [String: Int]?

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.displayName : trimmed
    }
}

// MARK: - Fond d'écran

struct BackgroundStyle: Codable, Equatable, Sendable {
    var colorHexes: [String]
    /// Nom du fichier image dans Documents (nil = pas de photo).
    var imageFile: String?
    var showPhoto: Bool = false
    var weight: Double = 0.5
    var spread: Double = 0.5

    var colors: [Color] {
        get { colorHexes.compactMap { Color(hex: $0) } }
        set { colorHexes = newValue.map(\.hex) }
    }

    static func preset(for kind: DeviceKind) -> BackgroundStyle {
        BackgroundStyle(colorHexes: kind.defaultColors.map(\.hex))
    }

    /// Couleur d'accent cohérente avec le fond (bleu pour les dégradés « Google »).
    var accent: Color {
        colorHexes.count > 2 ? .blue : (colors.last ?? .orange).saturatedAccent
    }
}

private extension Color {
    /// Les fonds très sombres donnent un accent illisible : on retombe sur l'orange.
    var saturatedAccent: Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (s < 0.25 || b < 0.25) ? .orange : self
    }
}

/// Décode les photos de fond une seule fois, réduites à la taille de l'écran.
@MainActor
enum BackgroundImageStore {
    private static var cache: [String: UIImage] = [:]

    static func url(for file: String) -> URL {
        URL.documentsDirectory.appendingPathComponent(file)
    }

    static func image(named file: String) -> UIImage? {
        if let cached = cache[file] { return cached }
        let maxPixel = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale
        guard let source = CGImageSourceCreateWithURL(url(for: file) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache[file] = image
        return image
    }

    static func data(named file: String) -> Data? {
        try? Data(contentsOf: url(for: file))
    }

    /// Écrit la photo (hors du thread principal) et renvoie son nouveau nom de fichier.
    static func store(_ data: Data) -> String {
        let file = "bg-\(UUID().uuidString).jpg"
        let destination = url(for: file)
        Task.detached(priority: .utility) {
            try? data.write(to: destination, options: .atomic)
        }
        if let image = UIImage(data: data) {
            cache[file] = image
        }
        return file
    }

    static func remove(_ file: String) {
        cache[file] = nil
        try? FileManager.default.removeItem(at: url(for: file))
    }
}

// MARK: - Onglet de télécommande

struct RemoteTabConfig: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String?
    var symbol: String?
    var deviceID: UUID?
    /// Appareil d'un autre onglet dont le bouton power est ajouté à côté de celui-ci (typiquement la TV sur l'onglet box).
    var companionID: UUID?
    var layout: RemoteLayout = .classic
    /// nil = fond commun à toute l'app.
    var background: BackgroundStyle?
    /// Autres appareils de l'onglet, choisis depuis le menu du haut (par défaut : aucun, un onglet = un appareil).
    var extraDeviceIDs: [UUID]?
    /// Appareil affiché parmi ceux de l'onglet (nil = l'appareil principal).
    var activeDeviceID: UUID?
    /// Disposition propre à chaque appareil ajouté (l'appareil principal utilise `layout`).
    var extraLayouts: [UUID: RemoteLayout]?

    /// Tous les appareils de l'onglet, le principal en premier.
    var allDeviceIDs: [UUID] {
        var ids = deviceID.map { [$0] } ?? []
        for id in extraDeviceIDs ?? [] where !ids.contains(id) { ids.append(id) }
        return ids
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.symbol == rhs.symbol
            && lhs.deviceID == rhs.deviceID && lhs.companionID == rhs.companionID
            && lhs.layout == rhs.layout
            && lhs.background == rhs.background
            && lhs.extraDeviceIDs == rhs.extraDeviceIDs && lhs.activeDeviceID == rhs.activeDeviceID
            && lhs.extraLayouts == rhs.extraLayouts
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Icônes proposées pour un onglet.
let tabSymbolChoices: [String] = [
    "tv.and.mediabox", "tv", "play.tv", "tv.badge.wifi", "appletvremote.gen4.fill",
    "dot.radiowaves.left.and.right", "sofa.fill", "bed.double.fill", "house.fill",
    "gamecontroller.fill", "film.fill", "sportscourt.fill", "star.fill", "heart.fill",
]

// MARK: - Contrôleurs

/// direction : 1 = appui, 2 = relâchement, 3 = tap (convention du protocole Google TV).
/// Une entrée de la TV (HDMI 1, TV…), proposée dans le menu Source.
struct InputSource: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    var appID: String?
    var isConnected = true
}

protocol RemoteController: AnyObject, Sendable {
    func send(_ key: OrangeKey, direction: Int32) async throws
    func sendText(_ text: String) async throws
    func togglePower() async throws
    /// Liste des entrées et entrée actuelle, pour les TV qui savent la donner.
    func inputSources() async throws -> (sources: [InputSource], currentID: String?)
    func selectInput(_ source: InputSource) async throws
    /// Prévient à chaque changement d'application ou d'entrée au premier plan (identifiant d'app).
    func observeForegroundApp(_ onChange: @escaping @Sendable (String) -> Void) async throws
    /// Volume absolu (0–100).
    func setVolume(_ level: Int) async throws
    func volume() async throws -> Int
    func ping() async -> Bool
    func disconnect()
}

extension RemoteController {
    func sendText(_ text: String) async throws {}
    func togglePower() async throws { try await send(.power, direction: 3) }
    func inputSources() async throws -> (sources: [InputSource], currentID: String?) { throw RemoteControllerError.unsupportedKey }
    func selectInput(_ source: InputSource) async throws { throw RemoteControllerError.unsupportedKey }
    func observeForegroundApp(_ onChange: @escaping @Sendable (String) -> Void) async throws { throw RemoteControllerError.unsupportedKey }
    func setVolume(_ level: Int) async throws { throw RemoteControllerError.unsupportedKey }
    func volume() async throws -> Int { throw RemoteControllerError.unsupportedKey }
}

enum RemoteControllerError: LocalizedError {
    case unsupportedKey
    case notConnected
    case unauthorized
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedKey: String(localized: "touche non prise en charge")
        case .notConnected: String(localized: "appareil injoignable")
        case .unauthorized: String(localized: "connexion refusée sur la TV")
        case .timedOut: String(localized: "délai dépassé")
        }
    }
}

final class OrangeController: RemoteController, @unchecked Sendable {
    let host: String
    init(host: String) { self.host = host }

    func send(_ key: OrangeKey, direction: Int32) async throws {
        guard key.code != 0 else { throw RemoteControllerError.unsupportedKey }
        let mode: RemoteMode = switch direction {
        case 1: .press
        case 2: .release
        default: .tap
        }
        try await OrangeRemoteClient(decoderIP: host).send(key, mode: mode)
    }

    func ping() async -> Bool {
        await OrangeRemoteClient.probe(ip: host, timeout: 1.5) != nil
    }

    func disconnect() {}
}

// MARK: - Décodage tolérant
// Les clés absentes (anciennes versions, futurs champs) reprennent leur valeur par défaut
// au lieu de faire échouer tout le décodage — et donc perdre la configuration.

extension RemoteTabConfig {
    private enum CodingKeys: String, CodingKey {
        case id, title, symbol, deviceID, companionID, layout, background
        case extraDeviceIDs, activeDeviceID, extraLayouts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        symbol = try? c.decodeIfPresent(String.self, forKey: .symbol)
        deviceID = try? c.decodeIfPresent(UUID.self, forKey: .deviceID)
        companionID = try? c.decodeIfPresent(UUID.self, forKey: .companionID)
        layout = (try? c.decodeIfPresent(RemoteLayout.self, forKey: .layout)) ?? .classic
        background = try? c.decodeIfPresent(BackgroundStyle.self, forKey: .background)
        extraDeviceIDs = try? c.decodeIfPresent([UUID].self, forKey: .extraDeviceIDs)
        activeDeviceID = try? c.decodeIfPresent(UUID.self, forKey: .activeDeviceID)
        extraLayouts = try? c.decodeIfPresent([UUID: RemoteLayout].self, forKey: .extraLayouts)
    }
}

extension BackgroundStyle {
    private enum CodingKeys: String, CodingKey {
        case colorHexes, imageFile, showPhoto, weight, spread
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colorHexes = try c.decode([String].self, forKey: .colorHexes)
        imageFile = try? c.decodeIfPresent(String.self, forKey: .imageFile)
        showPhoto = (try? c.decodeIfPresent(Bool.self, forKey: .showPhoto)) ?? false
        weight = (try? c.decodeIfPresent(Double.self, forKey: .weight)) ?? 0.5
        spread = (try? c.decodeIfPresent(Double.self, forKey: .spread)) ?? 0.5
    }
}

extension SavedDevice {
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, ip, mac, serviceName, token, sourceVolumes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(DeviceKind.self, forKey: .kind)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        ip = try c.decode(String.self, forKey: .ip)
        mac = try? c.decodeIfPresent(String.self, forKey: .mac)
        serviceName = try? c.decodeIfPresent(String.self, forKey: .serviceName)
        token = try? c.decodeIfPresent(String.self, forKey: .token)
        sourceVolumes = try? c.decodeIfPresent([String: Int].self, forKey: .sourceVolumes)
    }
}
