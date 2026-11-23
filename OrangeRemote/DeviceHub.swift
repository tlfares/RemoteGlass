import SwiftUI
import UIKit

/// État central de l'app : appareils, onglets de télécommande, fonds d'écran, connexions.
@MainActor
final class DeviceHub: ObservableObject {
    // MARK: Données persistées

    @Published var devices: [SavedDevice] { didSet { persist(devices, key: Keys.devices) } }
    @Published var tabs: [RemoteTabConfig] { didSet { persist(tabs, key: Keys.tabs) } }
    @Published var sharedBackground: BackgroundStyle { didSet { persist(sharedBackground, key: Keys.sharedBackground) } }
    @Published var glassTint: Double { didSet { defaults.set(glassTint, forKey: Keys.tint) } }
    @Published var buttonShape: ButtonShape { didSet { defaults.set(buttonShape.rawValue, forKey: Keys.buttonShape) } }
    @Published var disableStretch: Bool { didSet { defaults.set(disableStretch, forKey: Keys.disableStretch) } }
    /// Écran large (iPad, iPhone Duo) : affiche deux télécommandes côte à côte.
    @Published var splitView: Bool { didSet { defaults.set(splitView, forKey: Keys.splitView) } }
    /// Onglet affiché à droite en écran partagé (nil = onglet suivant).
    @Published var splitPartnerID: UUID? { didSet { defaults.set(splitPartnerID?.uuidString, forKey: Keys.splitPartner) } }

    // MARK: État d'exécution

    @Published private(set) var statuses: [UUID: ConnectionStatus] = [:]
    /// Entrées connues par TV (menu Source) et entrée actuellement affichée.
    @Published private(set) var inputSources: [UUID: [InputSource]] = [:]
    @Published private(set) var currentInput: [UUID: String] = [:]
    @Published var isKeyboardVisible = false {
        didSet { if !isKeyboardVisible { lastKeyboardDismiss = Date() } }
    }

    @Published private(set) var isScanning = false
    @Published private(set) var discovered: [DiscoveredDevice] = []
    @Published private(set) var hasScanned = false
    @Published var pairing: PairingState?

    private var controllers: [UUID: any RemoteController] = [:]
    private var relocating: Set<UUID> = []
    private var lastKeyboardDismiss: Date?
    private var gtvSession: AndroidTVPairingSession?
    private var hisenseSession: HisenseVIDAAClient?
    private var pairingTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let devices = "devices.v2"
        static let tabs = "tabs.v2"
        static let sharedBackground = "sharedBackground.v2"
        static let tint = "bgTint"
        static let buttonShape = "bgButtonShape"
        static let disableStretch = "bgDisableStretch"
        static let splitView = "splitView"
        static let splitPartner = "splitPartner"
    }

    struct PairingState: Identifiable, Equatable {
        enum Step: Equatable {
            case connecting
            case waitingForTV
            case needsPIN
            case validating
            case failed(String)
        }
        var id: String { candidate.id }
        var candidate: DiscoveredDevice
        var step: Step
        /// Onglet à créer une fois l'appareil appairé.
        var createsTab: Bool
        /// Onglet existant auquel ajouter l'appareil une fois appairé.
        var targetTabID: UUID?
    }

    // MARK: Init & migration

    init() {
        let defaults = UserDefaults.standard
        glassTint = defaults.object(forKey: Keys.tint) as? Double
            ?? ((Int(UIDevice.current.systemVersion.split(separator: ".").first ?? "") ?? 0) >= 27 ? 0.5 : 0)
        buttonShape = defaults.string(forKey: Keys.buttonShape).flatMap(ButtonShape.init(rawValue:)) ?? .squircle
        disableStretch = defaults.bool(forKey: Keys.disableStretch)
        splitView = defaults.object(forKey: Keys.splitView) as? Bool ?? true
        splitPartnerID = defaults.string(forKey: Keys.splitPartner).flatMap(UUID.init(uuidString:))

        if let devices: [SavedDevice] = Self.load(Keys.devices) {
            // Chaque valeur est relue indépendamment : un fond illisible ne doit jamais effacer les appareils.
            let tabs: [RemoteTabConfig] = Self.load(Keys.tabs) ?? []
            self.devices = devices
            self.tabs = tabs.isEmpty ? [RemoteTabConfig(deviceID: devices.first?.id, layout: devices.first?.kind.defaultLayout ?? .classic)] : tabs
            self.sharedBackground = Self.load(Keys.sharedBackground) ?? BackgroundStyle.preset(for: devices.first?.kind ?? .orange)
        } else {
            let migrated = Self.migrateFromV1(defaults)
            self.devices = migrated.devices
            self.tabs = migrated.tabs
            self.sharedBackground = migrated.background
            persist(devices, key: Keys.devices)
            persist(tabs, key: Keys.tabs)
            persist(sharedBackground, key: Keys.sharedBackground)
        }
    }

    /// Reprend la configuration de la version précédente (un décodeur Orange + des Google TV).
    private static func migrateFromV1(_ defaults: UserDefaults) -> (devices: [SavedDevice], tabs: [RemoteTabConfig], background: BackgroundStyle) {
        var devices: [SavedDevice] = []
        var tabs: [RemoteTabConfig] = []
        let provider = defaults.string(forKey: "selectedProvider") ?? "Orange"

        var orangeID: UUID?
        if let ip = defaults.string(forKey: "decoderIP"), !ip.isEmpty {
            let device = SavedDevice(
                kind: .orange,
                name: defaults.string(forKey: "decoderName") ?? "",
                ip: ip,
                mac: defaults.string(forKey: "decoderMAC").flatMap { $0.isEmpty ? nil : $0 }
            )
            orangeID = device.id
            devices.append(device)
        }

        var currentGTV: UUID?
        let currentGTVIP = defaults.string(forKey: "androidTVIP") ?? ""
        if let data = defaults.data(forKey: "savedGTVDevices"),
           let saved = try? JSONDecoder().decode([SavedGTVDevice].self, from: data) {
            for gtv in saved {
                let device = SavedDevice(id: gtv.id, kind: .androidTV, name: gtv.name, ip: gtv.ip, serviceName: gtv.serviceName)
                if gtv.ip == currentGTVIP { currentGTV = device.id }
                devices.append(device)
            }
        }

        // Versions plus anciennes : une seule Google TV, stockée à plat (la liste n'était pas toujours écrite).
        if !devices.contains(where: { $0.kind == .androidTV }),
           let pairedName = defaults.string(forKey: "androidTVPairedDevice"), !pairedName.isEmpty,
           !currentGTVIP.isEmpty {
            let device = SavedDevice(
                kind: .androidTV,
                name: pairedName,
                ip: currentGTVIP,
                serviceName: defaults.string(forKey: "androidTVServiceName") ?? pairedName
            )
            currentGTV = device.id
            devices.append(device)
        }

        // Un onglet par Google TV (celle utilisée en dernier d'abord), dans la limite de la tab bar.
        var gtvTabs = devices.filter { $0.kind == .androidTV }.map { RemoteTabConfig(deviceID: $0.id, layout: .trackpad) }
        if let currentGTV, let index = gtvTabs.firstIndex(where: { $0.deviceID == currentGTV }) {
            gtvTabs.insert(gtvTabs.remove(at: index), at: 0)
        }
        let orangeTab = orangeID.map { [RemoteTabConfig(deviceID: $0, layout: .classic)] } ?? []
        tabs = provider == "Android TV" ? gtvTabs + orangeTab : orangeTab + gtvTabs
        // Au-delà de la limite, les appareils restent enregistrés (proposés dans « Nouvelle télécommande »).
        tabs = Array(tabs.prefix(Self.maxTabs))
        if tabs.isEmpty {
            // Premier lancement : un onglet vide qui guide vers l'ajout d'un appareil.
            tabs.append(RemoteTabConfig(layout: provider == "Android TV" ? .trackpad : .classic))
        }

        // Fond d'écran : on garde les couleurs et la photo existantes.
        let kind: DeviceKind = provider == "Android TV" ? .androidTV : .orange
        var background = BackgroundStyle.preset(for: kind)
        if let hexes = defaults.array(forKey: "bgColors") as? [String], !hexes.isEmpty {
            background.colorHexes = hexes
        }
        background.weight = defaults.object(forKey: "bgWeight") as? Double ?? 0.5
        background.spread = defaults.object(forKey: "bgSpread") as? Double ?? 0.5
        background.showPhoto = defaults.bool(forKey: "bgShowPhoto")
        let legacyImage = URL.documentsDirectory.appendingPathComponent("bgImage.jpg")
        if FileManager.default.fileExists(atPath: legacyImage.path) {
            background.imageFile = "bgImage.jpg"
        }
        return (devices, tabs, background)
    }

    // MARK: Accès

    func device(_ id: UUID?) -> SavedDevice? {
        guard let id else { return nil }
        return devices.first { $0.id == id }
    }

    func status(of id: UUID?) -> ConnectionStatus {
        guard let id, device(id) != nil else { return .needsAddress }
        return statuses[id] ?? .idle
    }

    func background(for tab: RemoteTabConfig?) -> BackgroundStyle {
        tab?.background ?? sharedBackground
    }

    func title(for tab: RemoteTabConfig) -> String {
        if let title = tab.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        return activeDevice(in: tab)?.kind.shortName ?? String(localized: "Télécommande")
    }

    func symbol(for tab: RemoteTabConfig) -> String {
        tab.symbol ?? activeDevice(in: tab)?.kind.systemImage ?? "dot.radiowaves.left.and.right"
    }

    /// Appareil actuellement piloté par l'onglet (l'appareil principal, ou celui choisi dans le menu du haut).
    func activeDevice(in tab: RemoteTabConfig) -> SavedDevice? {
        if let id = tab.activeDeviceID, tab.allDeviceIDs.contains(id), let active = device(id) { return active }
        return device(tab.deviceID)
    }

    func devices(in tab: RemoteTabConfig) -> [SavedDevice] {
        tab.allDeviceIDs.compactMap { device($0) }
    }

    /// Onglets où l'appareil apparaît.
    func tabs(containing deviceID: UUID) -> [RemoteTabConfig] {
        tabs.filter { $0.allDeviceIDs.contains(deviceID) }
    }

    // MARK: Plusieurs appareils dans un onglet

    func selectDevice(_ deviceID: UUID, in tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }), tabs[index].allDeviceIDs.contains(deviceID) else { return }
        tabs[index].activeDeviceID = deviceID == tabs[index].deviceID ? nil : deviceID
    }

    /// Ajoute un appareil à un onglet existant et l'affiche.
    func attachDevice(_ deviceID: UUID, to tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabs[index].deviceID == nil {
            tabs[index].deviceID = deviceID
            tabs[index].layout = device(deviceID)?.kind.defaultLayout ?? .classic
        } else if !tabs[index].allDeviceIDs.contains(deviceID) {
            tabs[index].extraDeviceIDs = (tabs[index].extraDeviceIDs ?? []) + [deviceID]
        }
        selectDevice(deviceID, in: tabID)
    }

    /// Retire un appareil d'un onglet ; il reste dans les appareils liés.
    func detachDevice(_ deviceID: UUID, from tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = tabs[index]
        if tab.deviceID == deviceID {
            // L'appareil principal s'en va : le suivant prend sa place (avec sa disposition).
            let next = tab.extraDeviceIDs?.first
            tab.deviceID = next
            if let next { tab.layout = tab.extraLayouts?[next] ?? device(next)?.kind.defaultLayout ?? .classic }
            tab.extraDeviceIDs?.removeAll { $0 == next }
        } else {
            tab.extraDeviceIDs?.removeAll { $0 == deviceID }
        }
        tab.extraLayouts?[deviceID] = nil
        if tab.extraDeviceIDs?.isEmpty == true { tab.extraDeviceIDs = nil }
        if tab.extraLayouts?.isEmpty == true { tab.extraLayouts = nil }
        if let active = tab.activeDeviceID, !tab.allDeviceIDs.contains(active) || active == tab.deviceID { tab.activeDeviceID = nil }
        tabs[index] = tab
    }

    /// Disposition de l'appareil affiché (chaque appareil d'un onglet garde la sienne).
    func layout(in tab: RemoteTabConfig) -> RemoteLayout {
        guard let active = activeDevice(in: tab), active.id != tab.deviceID else { return tab.layout }
        return tab.extraLayouts?[active.id] ?? active.kind.defaultLayout
    }

    func setLayout(_ layout: RemoteLayout, in tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if let active = activeDevice(in: tabs[index]), active.id != tabs[index].deviceID {
            var layouts = tabs[index].extraLayouts ?? [:]
            layouts[active.id] = layout
            tabs[index].extraLayouts = layouts
        } else {
            tabs[index].layout = layout
        }
    }

    var televisions: [SavedDevice] { devices.filter { $0.kind.isTelevision } }

    /// Onglet affiché à côté de `tab` en écran partagé : celui choisi, sinon le suivant.
    /// Seconde télécommande de l'écran partagé : celle choisie dans les réglages, sinon le deuxième onglet.
    /// Elle quitte la tab bar et se fond dans les autres onglets (« Orange + LG »).
    var fixedSplitPartner: RemoteTabConfig? {
        guard tabs.count > 1 else { return nil }
        return tabs.first { $0.id == splitPartnerID } ?? tabs[1]
    }

    func splitPartner(for tab: RemoteTabConfig) -> RemoteTabConfig? {
        guard let fixed = fixedSplitPartner else { return nil }
        // Inutile d'afficher deux fois le même appareil côte à côte.
        let shown = activeDevice(in: tab)?.id
        let showsOther: (RemoteTabConfig) -> Bool = { $0.id != tab.id && (shown == nil || self.activeDevice(in: $0)?.id != shown) }
        return showsOther(fixed) ? fixed : tabs.first(where: showsOther)
    }

    /// Badge court d'un bouton power (« BOX », « TV »…).
    func powerBadge(for device: SavedDevice?) -> String {
        guard let device else { return "" }
        return device.kind.isTelevision ? String(localized: "TV") : String(localized: "BOX")
    }

    /// Le thème Google (dégradé multicolore) active l'icône alternative.
    var prefersGoogleIcon: Bool { sharedBackground.colorHexes.count > 2 && !sharedBackground.isMesh }

    // MARK: Envoi de commandes

    func send(_ key: OrangeKey, in tab: RemoteTabConfig, direction: Int32 = 3) {
        guard let target = target(for: key, in: tab) else {
            return
        }
        send(key, to: target, direction: direction)
    }

    func togglePower(_ deviceID: UUID?) {
        guard let device = device(deviceID) else { return }
        let controller = controller(for: device)
        Task {
            do {
                try await controller.togglePower()
                setStatus(.connected, for: device.id)
            } catch {
                handleFailure(of: device, error: error)
            }
        }
    }

    func sendText(_ text: String, in tab: RemoteTabConfig) {
        guard let device = activeDevice(in: tab), device.kind.supportsKeyboard else { return }
        let controller = controller(for: device)
        Task {
            do {
                try await controller.sendText(text)
                setStatus(.connected, for: device.id)
            } catch {
                handleFailure(of: device, error: error)
            }
        }
    }

    func loadInputSources(for deviceID: UUID?) {
        guard let device = device(deviceID) else { return }
        let controller = controller(for: device)
        Task {
            guard let result = try? await controller.inputSources() else { return }
            inputSources[device.id] = result.sources
            currentInput[device.id] = result.currentID
            if device.sourceVolumes?.isEmpty == false { observeInputChanges(of: device.id) }
        }
    }

    func selectInput(_ source: InputSource, deviceID: UUID?) {
        guard let device = device(deviceID) else { return }
        let controller = controller(for: device)
        currentInput[device.id] = source.id
        Task {
            do {
                try await controller.selectInput(source)
                setStatus(.connected, for: device.id)
                await applySourceVolume(for: source.id, deviceID: device.id, after: 1.2)
            } catch {
                handleFailure(of: device, error: error)
            }
        }
    }

    /// Volume par défaut d'une entrée (nil = ne rien changer).
    func setSourceVolume(_ level: Int?, for sourceID: String, deviceID: UUID) {
        guard var device = device(deviceID) else { return }
        var volumes = device.sourceVolumes ?? [:]
        volumes[sourceID] = level
        device.sourceVolumes = volumes.isEmpty ? nil : volumes
        updateDevice(device)
        if level != nil { observeInputChanges(of: deviceID) }
    }

    func currentVolume(of deviceID: UUID) async -> Int? {
        guard let device = device(deviceID) else { return nil }
        return try? await controller(for: device).volume()
    }

    /// Suit les changements d'entrée faits avec la vraie télécommande, pour appliquer le volume prévu.
    private func observeInputChanges(of deviceID: UUID) {
        guard let device = device(deviceID) else { return }
        let controller = controller(for: device)
        Task {
            try? await controller.observeForegroundApp { [weak self] appID in
                Task { @MainActor in self?.foregroundAppChanged(to: appID, deviceID: deviceID) }
            }
        }
    }

    private func foregroundAppChanged(to appID: String, deviceID: UUID) {
        guard let sources = inputSources[deviceID] else { return }
        let sourceID = sources.first { $0.appID == appID }?.id
        let previous = currentInput[deviceID]
        currentInput[deviceID] = sourceID
        // Pas d'entrée connue avant (premier signal) ou même entrée : rien à faire.
        guard let sourceID, previous != nil, previous != sourceID else { return }
        Task { await applySourceVolume(for: sourceID, deviceID: deviceID, after: 0.8) }
    }

    private func applySourceVolume(for sourceID: String, deviceID: UUID, after delay: Double) async {
        guard let device = device(deviceID), let level = device.sourceVolumes?[sourceID] else { return }
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        try? await controller(for: device).setVolume(level)
    }

    private func target(for key: OrangeKey, in tab: RemoteTabConfig) -> SavedDevice? {
        activeDevice(in: tab)
    }

    private func send(_ key: OrangeKey, to device: SavedDevice, direction: Int32) {
        let controller = controller(for: device)
        Task {
            do {
                try await controller.send(key, direction: direction)
                setStatus(.connected, for: device.id)
            } catch RemoteControllerError.unsupportedKey {
                // Touche absente sur cet appareil : on ignore sans marquer d'erreur.
            } catch {
                handleFailure(of: device, error: error)
            }
        }
    }

    func testConnection(_ deviceID: UUID?) {
        guard let device = device(deviceID) else { return }
        setStatus(.testing, for: device.id)
        let controller = controller(for: device)
        Task {
            if await controller.ping() {
                setStatus(.connected, for: device.id)
                if device.kind == .orange { await refreshOrangeIdentity(device) }
            } else {
                handleFailure(of: device, error: RemoteControllerError.notConnected)
            }
        }
    }

    /// Au retour au premier plan : on vérifie en silence que les appareils des onglets répondent.
    func refreshVisibleDevices() {
        let ids = Set(tabs.flatMap { [activeDevice(in: $0)?.id, $0.companionID] }.compactMap { $0 })
        for id in ids {
            guard let device = device(id), device.kind == .orange, device.mac != nil else { continue }
            Task {
                let probe = await OrangeRemoteClient.probe(ip: device.ip, timeout: 1)
                if probe?.mac?.uppercased() != device.mac?.uppercased() {
                    await relocate(device)
                } else {
                    setStatus(.connected, for: device.id)
                }
            }
        }
    }

    private func controller(for device: SavedDevice) -> any RemoteController {
        if let existing = controllers[device.id] { return existing }
        let controller: any RemoteController
        switch device.kind {
        case .orange:
            controller = OrangeController(host: device.ip)
        case .androidTV:
            let client = AndroidTVRemoteClient(host: device.ip, serviceName: device.serviceName ?? "")
            client.onTextInputRequest = { [weak self] in
                Task { @MainActor in
                    guard let self, Date().timeIntervalSince(self.lastKeyboardDismiss ?? .distantPast) > 0.5 else { return }
                    self.isKeyboardVisible = true
                }
            }
            controller = client
        case .lgWebOS:
            let client = LGWebOSClient(host: device.ip, clientKey: device.token, mac: device.mac)
            let id = device.id
            client.onCredentials = { [weak self] key, mac in
                Task { @MainActor in self?.updateCredentials(id, token: key, mac: mac) }
            }
            controller = client
        case .samsung:
            let client = SamsungTVClient(host: device.ip, token: device.token, mac: device.mac)
            let id = device.id
            client.onToken = { [weak self] token in
                Task { @MainActor in self?.updateCredentials(id, token: token, mac: nil) }
            }
            controller = client
        case .roku:
            controller = RokuClient(host: device.ip)
        case .hisense:
            controller = HisenseVIDAAClient(host: device.ip, clientID: device.token, mac: device.mac)
        case .sfr:
            controller = SFRDecoderClient(host: device.ip, variant: device.token.flatMap(SFRVariant.init(rawValue:)), mac: device.mac)
        case .freebox:
            controller = FreeboxPlayerClient(host: device.ip, code: device.token ?? "")
        }
        controllers[device.id] = controller
        return controller
    }

    private func dropController(_ id: UUID) {
        controllers.removeValue(forKey: id)?.disconnect()
    }

    private func updateCredentials(_ id: UUID, token: String?, mac: String?) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        if let token { devices[index].token = token }
        if let mac, devices[index].mac == nil { devices[index].mac = mac }
    }

    private func setStatus(_ status: ConnectionStatus, for id: UUID) {
        // Pas de « Envoi… » à chaque touche : on ne republie que les vrais changements d'état.
        if statuses[id] != status { statuses[id] = status }
    }

    private func handleFailure(of device: SavedDevice, error: Error) {
        if case RemoteControllerError.unauthorized = error {
            setStatus(.needsPairing, for: device.id)
            return
        }
        setStatus(.failed, for: device.id)
        Task { await relocate(device) }
    }

    /// L'appareil a peut-être changé d'IP (DHCP) : on le retrouve par son adresse MAC.
    private func relocate(_ device: SavedDevice) async {
        guard device.mac != nil, !relocating.contains(device.id) else { return }
        relocating.insert(device.id)
        defer { relocating.remove(device.id) }
        guard let newIP = await NetworkScanner.relocate(device), newIP != device.ip,
              let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].ip = newIP
        dropController(device.id)
        setStatus(.connected, for: device.id)
    }

    private func refreshOrangeIdentity(_ device: SavedDevice) async {
        guard let info = await OrangeRemoteClient.probe(ip: device.ip, timeout: 1.5),
              let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        if let name = info.name, devices[index].name.isEmpty { devices[index].name = name }
        if let mac = info.mac { devices[index].mac = mac }
    }

    // MARK: Détection & appairage

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let found = await NetworkScanner.scan()
            discovered = found
            isScanning = false
            hasScanned = true
        }
    }

    func isAlreadySaved(_ candidate: DiscoveredDevice) -> SavedDevice? {
        devices.first { saved in
            saved.kind == candidate.kind
                && (saved.ip == candidate.ip || (saved.mac != nil && saved.mac?.uppercased() == candidate.mac?.uppercased()))
        }
    }

    /// Ajoute un appareil trouvé (ou saisi à la main) ; lance l'appairage si le protocole l'exige.
    func add(_ candidate: DiscoveredDevice, createsTab: Bool, targetTabID: UUID? = nil) {
        cancelPairing()
        if let existing = isAlreadySaved(candidate) {
            // Déjà connu : on met à jour son IP et on le réutilise.
            if let index = devices.firstIndex(of: existing) {
                devices[index].ip = candidate.ip
                dropController(existing.id)
            }
            if let targetTabID {
                attachDevice(existing.id, to: targetTabID)
            } else if createsTab {
                addTab(for: existing.id)
            }
            return
        }

        pairing = PairingState(candidate: candidate, step: .connecting, createsTab: createsTab, targetTabID: targetTabID)
        pairingTask = Task {
            do {
                switch candidate.kind {
                case .orange, .roku:
                    let probe: any RemoteController = candidate.kind == .orange ? OrangeController(host: candidate.ip) : RokuClient(host: candidate.ip)
                    guard await probe.ping() else { throw RemoteControllerError.notConnected }
                    finishPairing(SavedDevice(kind: candidate.kind, name: candidate.name ?? "", ip: candidate.ip, mac: candidate.mac))

                case .androidTV:
                    let gtv = candidate.androidTV ?? DiscoveredAndroidTVDevice(
                        name: candidate.displayName, ip: candidate.ip, serviceName: candidate.displayName,
                        port: 6467, serviceType: "_androidtvremote2._tcp.", serviceDomain: "local."
                    )
                    gtvSession = try await AndroidTVPairingSession.start(device: gtv, clientServiceName: "RemoteGlass", clientName: "RemoteGlass")
                    pairing?.step = .needsPIN

                case .lgWebOS:
                    pairing?.step = .waitingForTV
                    let client = LGWebOSClient(host: candidate.ip, clientKey: nil, mac: candidate.mac)
                    let box = CredentialBox()
                    client.onCredentials = { key, mac in box.set(token: key, mac: mac) }
                    try await client.pair()
                    var device = SavedDevice(kind: .lgWebOS, name: candidate.name ?? "", ip: candidate.ip, mac: candidate.mac, token: box.token)
                    try? await Task.sleep(nanoseconds: 800_000_000) // laisse arriver l'adresse MAC
                    device.mac = device.mac ?? box.mac
                    controllers[device.id] = client
                    finishPairing(device)

                case .samsung:
                    pairing?.step = .waitingForTV
                    let client = SamsungTVClient(host: candidate.ip, token: nil, mac: candidate.mac)
                    let box = CredentialBox()
                    client.onToken = { box.set(token: $0, mac: nil) }
                    try await client.pair()
                    let device = SavedDevice(kind: .samsung, name: candidate.name ?? "", ip: candidate.ip, mac: candidate.mac, token: box.token)
                    controllers[device.id] = client
                    finishPairing(device)

                case .sfr:
                    let client = SFRDecoderClient(host: candidate.ip, variant: candidate.hint.flatMap(SFRVariant.init(rawValue:)), mac: candidate.mac)
                    let variant: SFRVariant
                    if let known = candidate.hint.flatMap(SFRVariant.init(rawValue:)) {
                        guard await client.ping() else { throw RemoteControllerError.notConnected }
                        variant = known
                    } else {
                        variant = try await client.identify()
                    }
                    let device = SavedDevice(kind: .sfr, name: candidate.name ?? variant.label, ip: candidate.ip, mac: candidate.mac, token: variant.rawValue)
                    controllers[device.id] = client
                    finishPairing(device)

                case .freebox:
                    guard await isTCPPortOpen(ip: candidate.ip, port: 80, timeout: 3) else { throw RemoteControllerError.notConnected }
                    pairing?.step = .needsPIN

                case .hisense:
                    let client = HisenseVIDAAClient(host: candidate.ip, clientID: nil, mac: candidate.mac)
                    if try await client.startPairing() {
                        hisenseSession = client
                        pairing?.step = .needsPIN
                    } else {
                        let device = SavedDevice(kind: .hisense, name: candidate.name ?? "", ip: candidate.ip, mac: candidate.mac, token: client.clientID)
                        controllers[device.id] = client
                        finishPairing(device)
                    }
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                pairing?.step = .failed(Self.describe(error, kind: candidate.kind))
            }
        }
    }

    func submitPIN(_ pin: String) {
        if let state = pairing, state.candidate.kind == .freebox {
            pairing?.step = .validating
            Task {
                let candidate = state.candidate
                let client = FreeboxPlayerClient(host: candidate.ip, code: pin)
                do {
                    try await client.validate()
                    let device = SavedDevice(kind: .freebox, name: candidate.name ?? "", ip: candidate.ip, mac: candidate.mac, token: pin.filter(\.isNumber))
                    controllers[device.id] = client
                    finishPairing(device)
                } catch RemoteControllerError.unauthorized {
                    pairing?.step = .failed(String(localized: "Code refusé. Vérifie le code télécommande réseau dans les réglages du Player."))
                } catch {
                    pairing?.step = .failed(String(localized: "Ce Player ne répond pas à la télécommande réseau. Les Freebox Pop, Ultra et Mini 4K s'ajoutent en mode Google TV."))
                }
            }
            return
        }
        if let client = hisenseSession, let state = pairing {
            pairing?.step = .validating
            Task {
                do {
                    try await client.confirm(code: pin)
                    hisenseSession = nil
                    let candidate = state.candidate
                    let device = SavedDevice(kind: .hisense, name: candidate.name ?? "", ip: candidate.ip, mac: candidate.mac, token: client.clientID)
                    controllers[device.id] = client
                    finishPairing(device)
                } catch {
                    pairing?.step = .failed(String(localized: "Code refusé ou expiré. Réessaie."))
                }
            }
            return
        }
        guard let session = gtvSession, let state = pairing else { return }
        pairing?.step = .validating
        Task {
            do {
                try await session.finish(pin: pin)
                let candidate = state.candidate
                finishPairing(SavedDevice(
                    kind: .androidTV,
                    name: candidate.displayName,
                    ip: candidate.ip,
                    mac: candidate.mac,
                    serviceName: candidate.androidTV?.serviceName ?? candidate.displayName
                ))
            } catch {
                pairing?.step = .failed(String(localized: "Code refusé ou expiré. Réessaie."))
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        gtvSession?.cancel()
        gtvSession = nil
        hisenseSession?.disconnect()
        hisenseSession = nil
        pairing = nil
    }

    private func finishPairing(_ device: SavedDevice) {
        let createsTab = pairing?.createsTab ?? false
        let targetTabID = pairing?.targetTabID
        devices.append(device)
        setStatus(.connected, for: device.id)
        gtvSession = nil
        pairing = nil
        if let targetTabID {
            attachDevice(device.id, to: targetTabID)
        } else if createsTab {
            addTab(for: device.id)
        }
    }

    private static func describe(_ error: Error, kind: DeviceKind) -> String {
        switch error {
        case let error as HisenseError:
            error.localizedDescription
        case RemoteControllerError.unauthorized:
            String(localized: "La TV a refusé la connexion. Autorise RemoteGlass dans les réglages de la TV puis réessaie.")
        case RemoteControllerError.timedOut:
            kind.pairingHint == nil
                ? String(localized: "L'appareil ne répond pas.")
                : String(localized: "Pas de réponse : la demande n'a pas été acceptée sur la TV.")
        default:
            String(localized: "Impossible de joindre l'appareil. Vérifie qu'il est allumé et sur le même Wi-Fi.")
        }
    }

    // MARK: Gestion des appareils

    func updateDevice(_ device: SavedDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        if devices[index].ip != device.ip || devices[index].token != device.token { dropController(device.id) }
        devices[index] = device
    }

    func removeDevice(_ id: UUID) {
        dropController(id)
        devices.removeAll { $0.id == id }
        statuses[id] = nil
        for tab in tabs where tab.allDeviceIDs.contains(id) {
            detachDevice(id, from: tab.id)
        }
        for index in tabs.indices where tabs[index].companionID == id {
            tabs[index].companionID = nil
        }
        inputSources[id] = nil
        currentInput[id] = nil
    }

    // MARK: Gestion des onglets

    static let maxTabs = 4

    var canAddTab: Bool { tabs.count < Self.maxTabs }

    @discardableResult
    func addTab(for deviceID: UUID?) -> RemoteTabConfig? {
        // Un onglet vide (premier lancement) est réutilisé plutôt que dupliqué.
        if let emptyIndex = tabs.firstIndex(where: { $0.deviceID == nil && $0.companionID == nil }) {
            tabs[emptyIndex].deviceID = deviceID
            tabs[emptyIndex].layout = device(deviceID)?.kind.defaultLayout ?? .classic
            return tabs[emptyIndex]
        }
        guard canAddTab else { return nil }
        var tab = RemoteTabConfig(deviceID: deviceID, layout: device(deviceID)?.kind.defaultLayout ?? .classic)
        tab.title = nil
        tabs.append(tab)
        tab = tabs[tabs.count - 1]
        return tab
    }

    func updateTab(_ tab: RemoteTabConfig) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs[index] = tab
    }

    /// Supprime l'onglet ; ses appareils restent dans les appareils liés.
    func removeTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        tabs.removeAll { $0.id == id }
        if splitPartnerID == id { splitPartnerID = nil }
        if tabs.isEmpty { tabs = [RemoteTabConfig()] }
    }

    func moveTabs(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Persistance

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Récupère les identifiants livrés par les callbacks des clients pendant l'appairage.
private final class CredentialBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _token: String?
    private var _mac: String?

    var token: String? { lock.withLock { _token } }
    var mac: String? { lock.withLock { _mac } }

    func set(token: String?, mac: String?) {
        lock.withLock {
            if let token { _token = token }
            if let mac { _mac = mac }
        }
    }
}

extension ConnectionStatus {
    func title(for kind: DeviceKind?) -> String {
        switch self {
        case .needsAddress: String(localized: "Aucun appareil")
        case .notFound: String(localized: "Aucun appareil trouvé")
        default: title(for: kind == .androidTV ? "Android TV" : "Orange")
        }
    }
}
