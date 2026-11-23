import PhotosUI
import SwiftUI
import UIKit

// MARK: - Appareils liés

/// Tous les appareils enregistrés, qu'ils soient sur un onglet ou non.
struct LinkedDevicesPanel: View {
    @ObservedObject var hub: DeviceHub
    @State private var openedDevice: SavedDevice?
    @State private var showAdd = false
    @State private var isExpanded = false

    var body: some View {
        SettingsPanel(
            title: String(localized: "Appareils liés"),
            symbol: "link",
            footer: hub.canAddTab
                ? String(localized: "Un nouvel appareil a son propre onglet. Pour en regrouper plusieurs sur un onglet, touche le nom de l'appareil en haut de la télécommande.")
                : String(localized: "Les 4 onglets sont pris : un nouvel appareil s'ajoute à un onglet depuis le nom de l'appareil, en haut de la télécommande."),
            isExpanded: $isExpanded
        ) {
            EmptyView()
        } content: {
            ForEach(hub.devices) { device in
                Button {
                    openedDevice = device
                } label: {
                    SettingsRow(
                        symbol: device.kind.systemImage,
                        title: device.displayName,
                        subtitle: subtitle(for: device),
                        status: hub.status(of: device.id)
                    )
                }
                .buttonStyle(RemoteGlassButtonStyle())
            }

            Button {
                showAdd = true
            } label: {
                Label("Ajouter un appareil", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(RemoteGlassButtonStyle(prominent: hub.devices.isEmpty))
        }
        .environment(\.buttonShape, .squircle)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hub.devices)
        .sheet(item: $openedDevice) { device in
            DeviceSheet(hub: hub, deviceID: device.id)
        }
        .sheet(isPresented: $showAdd) {
            AddDeviceSheet(hub: hub, createsTab: hub.canAddTab)
        }
    }

    private func subtitle(for device: SavedDevice) -> String {
        let tabs = hub.tabs(containing: device.id).map { hub.title(for: $0) }
        let place = tabs.isEmpty ? String(localized: "Sur aucun onglet") : tabs.joined(separator: ", ")
        return [device.kind.shortName, device.ip, place].joined(separator: " · ")
    }
}

/// Fiche d'un appareil : adresse, onglets, volume par entrée, suppression.
struct DeviceSheet: View {
    @ObservedObject var hub: DeviceHub
    var deviceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    /// Réglages d'un appareil : couleur de sa marque (bordeaux LG, bleu Samsung…), quel que soit le fond.
    private var accent: Color { hub.device(deviceID)?.kind.accent ?? hub.sharedBackground.accent }

    var body: some View {
        if let device = hub.device(deviceID) {
            GlassSheet(title: device.displayName, accent: accent) {
                DeviceDetailsPanel(hub: hub, deviceID: deviceID)
                tabsPanel(device)
                if device.kind == .lgWebOS {
                    SourceVolumesPanel(hub: hub, deviceID: deviceID, accent: accent)
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Oublier cet appareil", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .foregroundStyle(.red)
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .squircle)
                .confirmationDialog("Oublier \(device.displayName) ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Oublier", role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { hub.removeDevice(deviceID) }
                    }
                } message: {
                    Text("Il disparaîtra de ses onglets. Tu pourras le rajouter à tout moment.")
                }
            }
        }
    }

    private func tabsPanel(_ device: SavedDevice) -> some View {
        SettingsPanel(
            title: String(localized: "Onglets"),
            symbol: "square.stack.3d.up.fill",
            footer: String(localized: "Un appareil peut apparaître sur plusieurs onglets.")
        ) {
            EmptyView()
        } content: {
            ForEach(hub.tabs) { tab in
                let isOn = tab.allDeviceIDs.contains(deviceID)
                Button {
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                        if isOn { hub.detachDevice(deviceID, from: tab.id) } else { hub.attachDevice(deviceID, to: tab.id) }
                    }
                } label: {
                    CheckRow(symbol: hub.symbol(for: tab), title: hub.title(for: tab), isOn: isOn, accent: accent)
                }
                .buttonStyle(RemoteGlassButtonStyle(prominent: isOn))
            }
            if hub.canAddTab {
                Button {
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) { _ = hub.addTab(for: deviceID) }
                } label: {
                    Label("Nouvel onglet pour cet appareil", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(RemoteGlassButtonStyle())
            }
        }
        .environment(\.buttonShape, .squircle)
    }
}

/// Ligne avec une coche, pour les choix multiples des réglages.
struct CheckRow: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var isOn: Bool
    var accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? accent : .white.opacity(0.4))
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Appareils d'un onglet (éditeur d'onglet)

struct TabDevicesPanel: View {
    @ObservedObject var hub: DeviceHub
    var tabID: UUID
    var accent: Color
    @State private var openedDevice: SavedDevice?
    @State private var showAdd = false

    private var tab: RemoteTabConfig? { hub.tabs.first { $0.id == tabID } }

    var body: some View {
        if let tab {
            let devices = hub.devices(in: tab)
            let others = hub.devices.filter { !tab.allDeviceIDs.contains($0.id) }
            SettingsPanel(
                title: String(localized: "Appareils de l'onglet"),
                symbol: "rectangle.stack.fill",
                footer: devices.count > 1
                    ? String(localized: "Passe de l'un à l'autre en touchant le nom de l'appareil, en haut de la télécommande.")
                    : nil
            ) {
                EmptyView()
            } content: {
                if devices.count > 1 {
                    ForEach(devices) { device in
                        Button {
                            openedDevice = device
                        } label: {
                            SettingsRow(
                                symbol: device.kind.systemImage,
                                title: device.displayName,
                                subtitle: device.id == tab.deviceID ? String(localized: "Appareil principal") : device.kind.shortName,
                                status: hub.status(of: device.id)
                            )
                        }
                        .buttonStyle(RemoteGlassButtonStyle())
                    }
                } else if let device = devices.first {
                    DeviceDetailsPanel(hub: hub, deviceID: device.id)
                }

                Menu {
                    ForEach(others) { device in
                        Button {
                            hub.attachDevice(device.id, to: tabID)
                        } label: {
                            Label(device.displayName, systemImage: device.kind.systemImage)
                        }
                    }
                    if !others.isEmpty { Divider() }
                    Button {
                        showAdd = true
                    } label: {
                        Label("Nouvel appareil…", systemImage: "plus")
                    }
                } label: {
                    Label(devices.isEmpty ? String(localized: "Choisir un appareil") : String(localized: "Ajouter un appareil à cet onglet"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .menuStyle(.button)
                .buttonStyle(RemoteGlassButtonStyle(prominent: devices.isEmpty))
            }
            .environment(\.buttonShape, .squircle)
            .sheet(item: $openedDevice) { device in
                DeviceSheet(hub: hub, deviceID: device.id)
            }
            .sheet(isPresented: $showAdd) {
                AddDeviceSheet(hub: hub, createsTab: false, targetTabID: tabID)
            }
        }
    }
}

// MARK: - Volume par entrée

struct SourceVolumesPanel: View {
    @ObservedObject var hub: DeviceHub
    var deviceID: UUID
    var accent: Color

    var body: some View {
        let sources = hub.inputSources[deviceID] ?? []
        let volumes = hub.device(deviceID)?.sourceVolumes ?? [:]
        SettingsPanel(
            title: String(localized: "Volume par entrée"),
            symbol: "speaker.wave.2.fill",
            footer: String(localized: "Quand la TV passe sur une entrée, son volume est réglé tout seul. Ça marche aussi avec la vraie télécommande, tant que RemoteGlass est ouvert.")
        ) {
            EmptyView()
        } content: {
            if sources.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Allume la TV pour voir ses entrées.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            ForEach(sources) { source in
                SourceVolumeRow(
                    title: source.label,
                    isCurrent: hub.currentInput[deviceID] == source.id,
                    level: Binding(
                        get: { volumes[source.id] },
                        set: { hub.setSourceVolume($0, for: source.id, deviceID: deviceID) }
                    ),
                    currentVolume: { await hub.currentVolume(of: deviceID) },
                    accent: accent
                )
            }
        }
        .onAppear { hub.loadInputSources(for: deviceID) }
    }
}

private struct SourceVolumeRow: View {
    var title: String
    var isCurrent: Bool
    @Binding var level: Int?
    var currentVolume: () async -> Int?
    var accent: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                if isCurrent {
                    Text("Actuelle")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent.opacity(0.35)))
                }
                Spacer()
                if let level {
                    Text("\(level)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                }
                Toggle("", isOn: Binding(
                    get: { level != nil },
                    set: { enabled in
                        if enabled {
                            // On part du volume actuel de la TV : il suffit souvent de valider.
                            level = 15
                            Task { if let current = await currentVolume() { level = current } }
                        } else {
                            level = nil
                        }
                    }
                ))
                .labelsHidden()
                .tint(accent)
            }
            if let level {
                Slider(
                    value: Binding(get: { Double(level) }, set: { self.level = Int($0.rounded()) }),
                    in: 0...100,
                    step: 1
                )
                .tint(accent)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .staticGlassPanel(cornerRadius: 18)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: level != nil)
    }
}

// MARK: - Feedback

/// Le formulaire du site (tlfares.pages.dev), en natif. L'app est déjà renseignée,
/// et les infos utiles (version, appareil, iOS…) sont ajoutées au message.
struct FeedbackPanel: View {
    @ObservedObject var hub: DeviceHub
    var accent: Color

    enum Kind: String, CaseIterable, Identifiable {
        case feedback = "Feedback", bug = "Bug", idea = "Idea"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .feedback: String(localized: "Commentaire")
            case .bug: String(localized: "Bug")
            case .idea: String(localized: "Idée")
            }
        }
    }

    enum SendState: Equatable {
        case idle, sending, sent, failed(String)
    }

    @State private var kind: Kind = .feedback
    @State private var message = ""
    @State private var contact = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var attachment: Data?
    @State private var state: SendState = .idle
    @State private var isExpanded = false
    @FocusState private var messageFocused: Bool

    private var context: String { FeedbackSender.context(devices: hub.devices) }
    private var maxMessage: Int { max(200, FeedbackSender.maxMessage - context.count - 2) }
    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SettingsPanel(
            title: String(localized: "Feedback"),
            symbol: "bubble.left.and.text.bubble.right.fill",
            footer: String(localized: "Envoyé directement au développeur, avec : \(context.replacingOccurrences(of: "\n", with: " · "))"),
            isExpanded: $isExpanded
        ) {
            EmptyView()
        } content: {
            Picker("Type", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .focused($messageFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .onChange(of: message) { _, value in
                        if value.count > maxMessage { message = String(value.prefix(maxMessage)) }
                        if case .sent = state { state = .idle }
                    }
            }
            .padding(10)
            .staticGlassPanel(cornerRadius: 18)

            FieldRow(symbol: "person.crop.circle", placeholder: String(localized: "Contact (facultatif) : Telegram, X ou e-mail"), text: $contact, keyboard: .emailAddress)

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(attachment == nil ? String(localized: "Capture d'écran") : String(localized: "Capture jointe"), systemImage: attachment == nil ? "paperclip" : "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(RemoteGlassButtonStyle(prominent: attachment != nil))

                if attachment != nil {
                    Button {
                        photoItem = nil
                        attachment = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(RemoteGlassButtonStyle())
                    .accessibilityLabel(Text("Retirer la capture"))
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { attachment = await FeedbackSender.jpegData(from: item) }
            }

            Button(action: send) {
                HStack(spacing: 8) {
                    if state == .sending { ProgressView().tint(.white) }
                    Text(state == .sending ? String(localized: "Envoi…") : String(localized: "Envoyer"))
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
            }
            .buttonStyle(RemoteGlassButtonStyle(prominent: true))
            .disabled(trimmed.count < 3 || state == .sending)
            .opacity(trimmed.count < 3 ? 0.5 : 1)

            switch state {
            case .sent:
                Label("Envoyé, merci !", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
            default:
                EmptyView()
            }
        }
        .environment(\.buttonShape, .squircle)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: state)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: attachment != nil)
    }

    private var placeholder: String {
        switch kind {
        case .feedback: String(localized: "Qu'est-ce que tu en penses ?")
        case .bug: String(localized: "Qu'est-ce qui ne marche pas ? Sur quel appareil ?")
        case .idea: String(localized: "Qu'est-ce qui te manque ?")
        }
    }

    private func send() {
        messageFocused = false
        state = .sending
        let report = FeedbackSender.Report(kind: kind.rawValue, message: trimmed, context: context, contact: contact, attachment: attachment)
        Task {
            do {
                try await FeedbackSender.send(report)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                message = ""
                contact = ""
                photoItem = nil
                attachment = nil
                state = .sent
            } catch let error as FeedbackSender.Failure {
                state = .failed(error.message)
            } catch {
                state = .failed(FeedbackSender.Failure.network.message)
            }
        }
    }
}

enum FeedbackSender {
    /// Le Worker qui reçoit aussi le formulaire du site et le transfère sur Telegram.
    static let endpoint = URL(string: "https://feedback.tlfares.workers.dev")!
    /// Le Worker n'accepte que les envois venant du site.
    static let origin = "https://tlfares.pages.dev"
    static let maxMessage = 2000
    static let maxFile = 10 * 1024 * 1024

    struct Report: Sendable {
        var kind: String
        var message: String
        var context: String
        var contact: String
        var attachment: Data?
    }

    enum Failure: Error {
        case tooMany, tooLarge, network
        var message: String {
            switch self {
            case .tooMany: String(localized: "Trop de messages, réessaie dans un moment.")
            case .tooLarge: String(localized: "La capture dépasse 10 Mo.")
            case .network: String(localized: "Envoi impossible. Réessaie plus tard.")
            }
        }
    }

    /// « RemoteGlass 1.2 (14) · iPhone16,1 · iOS 26.1 · fr-FR » + les types d'appareils configurés.
    static func context(devices: [SavedDevice]) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let language = Locale.preferredLanguages.first ?? Locale.current.identifier
        var lines = ["RemoteGlass \(version) (\(build)) · \(modelIdentifier) · \(system) · \(language)"]
        var kinds: [String] = []
        for device in devices where !kinds.contains(device.kind.displayName) { kinds.append(device.kind.displayName) }
        if !kinds.isEmpty { lines.append(String(localized: "Appareils : \(kinds.joined(separator: ", "))")) }
        return lines.joined(separator: "\n")
    }

    /// Identifiant du modèle (« iPhone16,1 »), plus précis que « iPhone ».
    static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated + " (Simulator)" }
        var system = utsname()
        uname(&system)
        let identifier = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    /// Capture choisie, ré-encodée en JPEG (format que Telegram affiche directement).
    static func jpegData(from item: PhotosPickerItem?) async -> Data? {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        guard let image = UIImage(data: data) else { return data }
        return image.jpegData(compressionQuality: 0.85) ?? data
    }

    static func send(_ report: Report) async throws {
        if let attachment = report.attachment, attachment.count > maxFile { throw Failure.tooLarge }
        let boundary = "RemoteGlass-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("kind", report.kind)
        field("app", "RemoteGlass")
        // Le Worker ne lit que ses champs : les infos de l'appareil voyagent dans le message.
        field("message", String("\(report.message)\n\n\(report.context)".prefix(maxMessage)))
        field("contact", report.contact.trimmingCharacters(in: .whitespacesAndNewlines))
        if let attachment = report.attachment {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"capture.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
            body.append(attachment)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        let (_, response) = try await URLSession.shared.upload(for: request, from: body)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return
        case 429: throw Failure.tooMany
        case 413: throw Failure.tooLarge
        default: throw Failure.network
        }
    }
}
