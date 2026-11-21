import SwiftUI
import UIKit

// MARK: - Réglages

struct SettingsTab: View {
    @ObservedObject var hub: DeviceHub
    var isSelected: Bool

    @State private var editingTab: RemoteTabConfig?
    @State private var addMode: AddMode?
    @State private var showReorder = false
    @State private var isAppearanceExpanded = false
    @State private var isButtonsExpanded = false
    @State private var containerWidth: CGFloat = 0

    private enum AddMode: String, Identifiable {
        case remote
        var id: String { rawValue }
    }

    private var accent: Color { hub.sharedBackground.accent }

    var body: some View {
        ZStack {
            FadingBackground(style: hub.sharedBackground)

            ScrollView {
                VStack(spacing: 20) {
                    Text("Réglages")
                        .font(.largeTitle.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: isSelected ? 0 : -6)
                        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.85), value: isSelected)

                    remotesPanel
                    LinkedDevicesPanel(hub: hub)
                    if containerWidth >= RemotePage.minimumSplitWidth && hub.tabs.count > 1 {
                        splitPanel
                    }
                    appearancePanel
                    FeedbackPanel(hub: hub, accent: accent)
                    credits
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .padding(.bottom, 60)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .foregroundStyle(.white)
        .sheet(item: $editingTab) { tab in
            TabEditorSheet(hub: hub, tabID: tab.id)
        }
        .sheet(item: $addMode) { mode in
            AddDeviceSheet(hub: hub, createsTab: true)
        }
        .sheet(isPresented: $showReorder) {
            TabOrderSheet(hub: hub)
        }
    }

    // MARK: Télécommandes (onglets)

    private var remotesPanel: some View {
        SettingsPanel(
            title: String(localized: "Onglets"),
            symbol: "square.stack.3d.up.fill",
            footer: String(localized: "Un onglet par appareil (4 au maximum). Un onglet peut aussi en regrouper plusieurs : touche le nom de l'appareil en haut de la télécommande.")
        ) {
            if hub.tabs.count > 1 {
                Button {
                    showReorder = true
                } label: {
                    Label("Réorganiser", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .circle)
                .accessibilityLabel(Text("Réorganiser les onglets"))
            }
        } content: {
            ForEach(hub.tabs) { tab in
                Button {
                    editingTab = tab
                } label: {
                    SettingsRow(
                        symbol: hub.symbol(for: tab),
                        title: hub.title(for: tab),
                        subtitle: subtitle(for: tab),
                        accent: hub.background(for: tab).accent,
                        status: tab.deviceID.map { hub.status(of: $0) },
                        trailing: tab.background == nil ? nil : "paintpalette.fill"
                    )
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .squircle)
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }

            if hub.canAddTab {
                Button {
                    addMode = .remote
                } label: {
                    Label("Nouvel onglet", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(RemoteGlassButtonStyle(prominent: true))
                .environment(\.buttonShape, .squircle)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hub.tabs)
    }

    private func subtitle(for tab: RemoteTabConfig) -> String {
        let devices = hub.devices(in: tab)
        guard let device = devices.first else { return String(localized: "Aucun appareil") }
        if devices.count > 1 { return devices.map(\.displayName).joined(separator: " · ") }
        var parts = [device.displayName, device.ip]
        if let other = hub.device(tab.companionID) { parts.append("+ power \(hub.powerBadge(for: other))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Écran partagé (iPad, iPhone Duo)

    private var splitPanel: some View {
        SettingsPanel(
            title: String(localized: "Écran partagé"),
            symbol: "rectangle.split.2x1",
            footer: String(localized: "Ton écran est assez large pour afficher deux télécommandes en même temps.")
        ) {
            Toggle("", isOn: $hub.splitView.animation(.spring(response: 0.5, dampingFraction: 0.85)))
                .labelsHidden()
                .tint(accent)
        } content: {
            if hub.splitView {
                Text("Seconde télécommande (à droite, ou en bas en portrait)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 2)
                ForEach([RemoteTabConfig?.none] + hub.tabs.map(Optional.some), id: \.?.id) { tab in
                    let isOn = hub.splitPartnerID == tab?.id
                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { hub.splitPartnerID = tab?.id }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tab.map { hub.symbol(for: $0) } ?? "arrow.right.square")
                                .font(.title3)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.map { hub.title(for: $0) } ?? String(localized: "Automatique"))
                                    .font(.body.weight(.medium))
                                if tab == nil {
                                    Text("Le deuxième onglet")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.55))
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
                    .buttonStyle(RemoteGlassButtonStyle(prominent: isOn))
                    .environment(\.buttonShape, .squircle)
                }
            }
        }
    }

    // MARK: Apparence

    private var appearancePanel: some View {
        VStack(spacing: 14) {
            DisclosureHeader(title: String(localized: "Fond commun"), symbol: "paintpalette.fill", isExpanded: $isAppearanceExpanded)
            if isAppearanceExpanded {
                Text("Utilisé par les réglages et par chaque télécommande qui n'a pas son propre fond.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                BackgroundEditor(style: $hub.sharedBackground, accent: accent)
            }

            Divider().overlay(.white.opacity(0.15))

            DisclosureHeader(title: String(localized: "Boutons"), symbol: "square.grid.3x3", isExpanded: $isButtonsExpanded)
            if isButtonsExpanded {
                ButtonAppearanceEditor(
                    buttonShape: $hub.buttonShape,
                    disableStretch: $hub.disableStretch,
                    tint: $hub.glassTint,
                    accent: accent
                )
            }
        }
        .padding(14)
        .staticGlassPanel()
    }

    private var credits: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("Credits :")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Link("@rmxptfl", destination: URL(string: "https://tlfares.pages.dev")!)
                    .font(.caption2)
                    .underline()
                    .foregroundStyle(.white.opacity(0.7))
            }
            Link("Check for updates", destination: URL(string: "https://github.com/tlfares/RemoteGlass/releases")!)
                .font(.caption2)
                .underline()
                .foregroundStyle(.white.opacity(0.5))
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Briques communes

struct SettingsPanel<Accessory: View, Content: View>: View {
    var title: String
    var symbol: String
    var footer: String?
    /// Fourni : la section se replie (titre cliquable avec chevron).
    var isExpanded: Binding<Bool>? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    private var showsContent: Bool { isExpanded?.wrappedValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let isExpanded {
                    DisclosureHeader(title: title, symbol: symbol, isExpanded: isExpanded)
                } else {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                    Spacer()
                }
                accessory
            }
            .frame(minHeight: 34)
            if showsContent {
                content
            }
            if showsContent, let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 2)
            }
        }
        .padding(14)
        .staticGlassPanel()
    }
}

struct SettingsRow: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var accent: Color = .white
    var status: ConnectionStatus?
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(.white)
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
            Spacer(minLength: 4)
            if let status {
                Circle()
                    .fill(status.indicatorColor)
                    .frame(width: 8, height: 8)
            }
            if let trailing {
                Image(systemName: trailing)
                    .font(.caption)
                    .foregroundStyle(accent)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

struct DisclosureHeader: View {
    var title: String
    var symbol: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) { isExpanded.toggle() }
        } label: {
            HStack {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Conteneur de feuille : fond flou, titre, bouton OK.
struct GlassSheet<Content: View>: View {
    var title: String
    var accent: Color
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) { content }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(accent)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationCornerRadius(36)
        .presentationBackground(.ultraThinMaterial)
    }
}

struct FieldRow: View {
    var symbol: String
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 24)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onChange(of: text) { _, value in
                    // Adresse IP : une virgule tapée (clavier français) devient un point.
                    guard keyboard == .decimalPad || keyboard == .numbersAndPunctuation, value.contains(",") else { return }
                    text = value.replacingOccurrences(of: ",", with: ".")
                }
        }
        .padding(14)
        .staticGlassPanel(cornerRadius: 18)
    }
}

// MARK: - Éditeur d'onglet

struct TabEditorSheet: View {
    @ObservedObject var hub: DeviceHub
    var tabID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var binding: Binding<RemoteTabConfig>? {
        guard let index = hub.tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        return Binding(
            get: { hub.tabs.indices.contains(index) && hub.tabs[index].id == tabID ? hub.tabs[index] : RemoteTabConfig(id: tabID) },
            set: { hub.updateTab($0) }
        )
    }

    var body: some View {
        if let tab = binding {
            GlassSheet(title: hub.title(for: tab.wrappedValue), accent: hub.background(for: tab.wrappedValue).accent) {
                editor(tab)
            }
        }
    }

    @ViewBuilder
    private func editor(_ tab: Binding<RemoteTabConfig>) -> some View {
        let accent = hub.background(for: tab.wrappedValue).accent
        let primary = hub.device(tab.wrappedValue.deviceID)

        // Aperçu vivant de l'onglet
        ZStack {
            BackgroundView(style: hub.background(for: tab.wrappedValue))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(spacing: 8) {
                Image(systemName: hub.symbol(for: tab.wrappedValue))
                    .font(.system(size: 30, weight: .semibold))
                Text(hub.title(for: tab.wrappedValue))
                    .font(.headline)
            }
        }
        .frame(height: 130)
        .padding(.top, 8)

        // Nom & icône
        SettingsPanel(title: String(localized: "Onglet"), symbol: "character.cursor.ibeam", footer: nil) {
            EmptyView()
        } content: {
            FieldRow(
                symbol: "pencil",
                placeholder: primary?.kind.shortName ?? String(localized: "Nom de l'onglet"),
                text: Binding(get: { tab.wrappedValue.title ?? "" }, set: { tab.wrappedValue.title = $0.isEmpty ? nil : $0 })
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabSymbolChoices, id: \.self) { symbol in
                        let isOn = hub.symbol(for: tab.wrappedValue) == symbol
                        Button {
                            tab.wrappedValue.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 46, height: 46)
                        }
                        .buttonStyle(RemoteGlassButtonStyle(prominent: isOn))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(isOn ? accent : .clear, lineWidth: 2))
                    }
                }
                .padding(4)
            }
            .environment(\.buttonShape, .squircle)
        }

        // Appareils de l'onglet
        TabDevicesPanel(hub: hub, tabID: tabID, accent: accent)

        // Bouton power emprunté à un autre onglet
        let otherTabs = hub.tabs.filter { $0.id != tabID && $0.deviceID != nil && $0.deviceID != tab.wrappedValue.deviceID }
        if !otherTabs.isEmpty {
            SettingsPanel(
                title: String(localized: "Bouton power en plus"),
                symbol: "power",
                footer: String(localized: "Ajoute le bouton power d'un autre onglet à côté de celui-ci — par exemple celui de la TV sur l'onglet de la box.")
            ) {
                EmptyView()
            } content: {
                ForEach([RemoteTabConfig?.none] + otherTabs.map(Optional.some), id: \.?.id) { other in
                    let isOn = tab.wrappedValue.companionID == other?.deviceID
                    Button {
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                            tab.wrappedValue.companionID = other?.deviceID
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: other.map { hub.symbol(for: $0) } ?? "nosign")
                                .font(.title3)
                                .frame(width: 30)
                            Text(other.map { hub.title(for: $0) } ?? String(localized: "Aucun"))
                                .font(.body.weight(.medium))
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
                    .buttonStyle(RemoteGlassButtonStyle(prominent: isOn))
                    .environment(\.buttonShape, .squircle)
                }
            }
        }

        // Disposition
        SettingsPanel(title: String(localized: "Disposition"), symbol: "rectangle.3.group", footer: nil) {
            EmptyView()
        } content: {
            HStack(spacing: 10) {
                ForEach(RemoteLayout.allCases) { layout in
                    Button {
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) { tab.wrappedValue.layout = layout }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: layout.systemImage).font(.title2)
                            Text(layout.label).font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 76)
                    }
                    .buttonStyle(RemoteGlassButtonStyle(prominent: tab.wrappedValue.layout == layout))
                }
            }
            .environment(\.buttonShape, .squircle)
        }

        // Fond
        SettingsPanel(title: String(localized: "Fond d'écran"), symbol: "paintpalette.fill", footer: nil) {
            EmptyView()
        } content: {
            Picker("Fond", selection: Binding(
                get: { tab.wrappedValue.background != nil },
                set: { custom in
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                        if custom {
                            tab.wrappedValue.background = primary.map { BackgroundStyle.preset(for: $0.kind) } ?? hub.sharedBackground
                        } else {
                            tab.wrappedValue.background = nil
                        }
                    }
                }
            )) {
                Text("Commun").tag(false)
                Text("Personnalisé").tag(true)
            }
            .pickerStyle(.segmented)

            if tab.wrappedValue.background != nil {
                BackgroundEditor(
                    style: Binding(
                        get: { tab.wrappedValue.background ?? hub.sharedBackground },
                        set: { tab.wrappedValue.background = $0 }
                    ),
                    accent: accent
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }

        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Supprimer cet onglet", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .foregroundStyle(.red)
        }
        .buttonStyle(RemoteGlassButtonStyle())
        .environment(\.buttonShape, .squircle)
        .confirmationDialog("Supprimer \(hub.title(for: tab.wrappedValue)) ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { hub.removeTab(tabID) }
            }
        } message: {
            Text("Ses appareils restent dans « Appareils liés ».")
        }
    }
}

// MARK: - Ordre des onglets

struct TabOrderSheet: View {
    @ObservedObject var hub: DeviceHub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(hub.tabs) { tab in
                        Label(hub.title(for: tab), systemImage: hub.symbol(for: tab))
                            .font(.body.weight(.medium))
                            .listRowBackground(Color.white.opacity(0.08))
                    }
                    .onMove(perform: hub.moveTabs)
                    .onDelete { offsets in
                        guard hub.tabs.count - offsets.count >= 1 else { return }
                        offsets.map { hub.tabs[$0].id }.forEach(hub.removeTab)
                    }

                    Label("Réglages", systemImage: "gearshape")
                        .foregroundStyle(.white.opacity(0.45))
                        .listRowBackground(Color.white.opacity(0.04))
                        .moveDisabled(true)
                        .deleteDisabled(true)
                } footer: {
                    Text("Fais glisser pour changer l'ordre des onglets. Réglages reste toujours en dernier.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .navigationTitle("Ordre des onglets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(hub.sharedBackground.accent)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(36)
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - Ajout d'un appareil

struct AddDeviceSheet: View {
    @ObservedObject var hub: DeviceHub
    /// true : l'appareil ajouté devient une nouvelle télécommande (onglet).
    var createsTab: Bool
    /// Onglet existant auquel ajouter l'appareil (menu du haut d'une télécommande).
    var targetTabID: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var manualKind: DeviceKind = .orange
    @State private var manualIP = ""
    @State private var showManual = false
    @State private var pin = ""
    @State private var initialDeviceCount = 0
    @State private var initialTabCount = 0

    private var accent: Color { hub.sharedBackground.accent }

    /// Appareils déjà enregistrés sans onglet : un toucher suffit pour en faire une télécommande.
    private var savedWithoutTab: [SavedDevice] {
        let used = Set(hub.tabs.flatMap(\.allDeviceIDs))
        return hub.devices.filter { !used.contains($0.id) }
    }

    var body: some View {
        GlassSheet(title: createsTab && targetTabID == nil ? String(localized: "Nouvel onglet") : String(localized: "Ajouter un appareil"), accent: accent) {
            if let pairing = hub.pairing {
                PairingPanel(hub: hub, state: pairing, pin: $pin, accent: accent)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                if (createsTab || targetTabID != nil) && !savedWithoutTab.isEmpty {
                    SettingsPanel(title: String(localized: "Mes appareils"), symbol: "checkmark.seal.fill", footer: nil) {
                        EmptyView()
                    } content: {
                        ForEach(savedWithoutTab) { device in
                            Button {
                                if let targetTabID {
                                    hub.attachDevice(device.id, to: targetTabID)
                                } else {
                                    hub.addTab(for: device.id)
                                }
                                dismiss()
                            } label: {
                                SettingsRow(symbol: device.kind.systemImage, title: device.displayName, subtitle: "\(device.kind.shortName) · \(device.ip)")
                            }
                            .buttonStyle(RemoteGlassButtonStyle())
                        }
                    }
                    .environment(\.buttonShape, .squircle)
                }

                discoveryPanel
                manualPanel
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: hub.pairing)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: hub.discovered)
        .onAppear {
            initialDeviceCount = hub.devices.count
            initialTabCount = hub.tabs.count
            if !hub.isScanning { hub.scan() }
        }
        .onDisappear {
            if hub.pairing != nil { hub.cancelPairing() }
        }
        .onChange(of: hub.devices.count) { _, count in
            // Appairage réussi : on referme la feuille.
            if count > initialDeviceCount, hub.pairing == nil {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }

    private var discoveryPanel: some View {
        SettingsPanel(
            title: String(localized: "Sur ton réseau"),
            symbol: "dot.radiowaves.left.and.right",
            footer: String(localized: "L'iPhone doit être sur le même Wi-Fi que tes appareils, et ceux-ci allumés.")
        ) {
            Button {
                hub.scan()
            } label: {
                Group {
                    if hub.isScanning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
            }
            .disabled(hub.isScanning)
            .buttonStyle(RemoteGlassButtonStyle())
            .environment(\.buttonShape, .circle)
            .accessibilityLabel(Text("Relancer la détection"))
        } content: {
            if hub.isScanning && hub.discovered.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Recherche des box et TV…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else if hub.discovered.isEmpty && hub.hasScanned {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark").font(.title2)
                    Text("Aucun appareil trouvé")
                        .font(.subheadline.weight(.semibold))
                    Text("Vérifie l'accès au réseau local dans Réglages iOS › RemoteGlass, ou ajoute l'IP à la main.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            ForEach(hub.discovered) { candidate in
                let saved = hub.isAlreadySaved(candidate)
                Button {
                    pin = ""
                    hub.add(candidate, createsTab: createsTab, targetTabID: targetTabID)
                    if saved != nil { dismiss() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: candidate.kind.systemImage)
                            .font(.title3)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.displayName)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(candidate.ip)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer(minLength: 4)
                        if saved != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text(candidate.kind.shortName)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(candidate.kind.accent.opacity(0.55), in: Capsule())
                        }
                    }
                    .frame(minHeight: 52)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .squircle)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }

    private var manualPanel: some View {
        VStack(spacing: 12) {
            DisclosureHeader(title: String(localized: "Saisir une adresse IP"), symbol: "keyboard", isExpanded: $showManual)
            if showManual {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DeviceKind.allCases) { kind in
                            Button {
                                manualKind = kind
                            } label: {
                                Label(kind.shortName, systemImage: kind.systemImage)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 40)
                            }
                            .buttonStyle(RemoteGlassButtonStyle(prominent: manualKind == kind))
                        }
                    }
                    .padding(2)
                }
                .environment(\.buttonShape, .squircle)

                FieldRow(symbol: "network", placeholder: String(localized: "192.168.1.20"), text: $manualIP, keyboard: .numbersAndPunctuation)

                Button {
                    let ip = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
                    hub.add(DiscoveredDevice(kind: manualKind, name: nil, ip: ip), createsTab: createsTab, targetTabID: targetTabID)
                } label: {
                    Label("Connecter", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .disabled(manualIP.split(separator: ".").count != 4)
                .buttonStyle(RemoteGlassButtonStyle(prominent: true))
                .environment(\.buttonShape, .squircle)
            }
        }
        .padding(14)
        .staticGlassPanel()
    }
}

struct PairingPanel: View {
    @ObservedObject var hub: DeviceHub
    var state: DeviceHub.PairingState
    @Binding var pin: String
    var accent: Color
    @FocusState private var pinFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.candidate.kind.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .symbolEffect(.pulse, options: .repeating, isActive: isWaiting)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(state.candidate.displayName)
                    .font(.title3.weight(.bold))
                Text(state.candidate.ip)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            switch state.step {
            case .connecting:
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Connexion…").font(.subheadline)
                }
            case .waitingForTV:
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Regarde ta TV")
                        .font(.headline)
                    Text(state.candidate.kind.pairingHint ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            case .needsPIN, .validating:
                VStack(spacing: 10) {
                    Text(state.candidate.kind.pairingHint ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    TextField("Code", text: $pin)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .keyboardType([.hisense, .freebox].contains(state.candidate.kind) ? .numberPad : .asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($pinFocused)
                        .padding(14)
                        .staticGlassPanel(cornerRadius: 18)
                        .onAppear { pinFocused = true }
                        .onSubmit { submit() }
                    Button(action: submit) {
                        Group {
                            if state.step == .validating {
                                ProgressView().tint(.white)
                            } else {
                                Label("Valider", systemImage: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                    }
                    .disabled(pin.trimmingCharacters(in: .whitespaces).count < 4 || state.step == .validating)
                    .buttonStyle(RemoteGlassButtonStyle(prominent: true))
                }
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button {
                        pin = ""
                        hub.add(state.candidate, createsTab: state.createsTab, targetTabID: state.targetTabID)
                    } label: {
                        Label("Réessayer", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(RemoteGlassButtonStyle(prominent: true))
                }
            }

            Button("Annuler") {
                pin = ""
                hub.cancelPairing()
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.75))
        }
        .environment(\.buttonShape, .squircle)
        .frame(maxWidth: .infinity)
        .padding(18)
        .staticGlassPanel()
    }

    private var isWaiting: Bool {
        state.step == .waitingForTV || state.step == .connecting
    }

    private func submit() {
        guard pin.trimmingCharacters(in: .whitespaces).count >= 4 else { return }
        pinFocused = false
        hub.submitPIN(pin)
    }
}

// MARK: - Éditeur d'appareil

/// Réglages de l'appareil d'une télécommande : état, adresses, test.
struct DeviceDetailsPanel: View {
    @ObservedObject var hub: DeviceHub
    var deviceID: UUID

    var body: some View {
        if let device = hub.device(deviceID) {
            let status = hub.status(of: device.id)
            SettingsPanel(
                title: device.displayName,
                symbol: device.kind.systemImage,
                footer: device.mac == nil
                    ? String(localized: "Sans adresse MAC, RemoteGlass ne peut pas retrouver l'appareil s'il change d'IP, ni allumer une TV éteinte.")
                    : nil
            ) {
                HStack(spacing: 6) {
                    Circle().fill(status.indicatorColor).frame(width: 8, height: 8)
                    Text(status.title(for: device.kind))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            } content: {
                FieldRow(symbol: "network", placeholder: String(localized: "Adresse IP"), text: binding(\.ip), keyboard: .numbersAndPunctuation)
                FieldRow(
                    symbol: "barcode",
                    placeholder: String(localized: "Adresse MAC (facultatif)"),
                    text: Binding(
                        get: { hub.device(deviceID)?.mac ?? "" },
                        set: { value in
                            guard var updated = hub.device(deviceID) else { return }
                            updated.mac = value.isEmpty ? nil : value.uppercased()
                            hub.updateDevice(updated)
                        }
                    ),
                    keyboard: .asciiCapable
                )
                Button {
                    hub.testConnection(device.id)
                } label: {
                    Label("Tester la connexion", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .squircle)
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SavedDevice, String>) -> Binding<String> {
        Binding(
            get: { hub.device(deviceID)?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var updated = hub.device(deviceID) else { return }
                updated[keyPath: keyPath] = value
                hub.updateDevice(updated)
            }
        )
    }
}

// MARK: - Éditeur de fond

struct BackgroundEditor: View {
    @Binding var style: BackgroundStyle
    var accent: Color
    @State private var showPhotoPicker = false
    @State private var wallpaperDraft: WallpaperDraft?

    private var color1: Binding<Color> {
        Binding(get: { style.colors.first ?? .black }, set: { var c = style.colors; if !c.isEmpty { c[0] = $0 }; style.colors = c })
    }

    private var color2: Binding<Color> {
        Binding(get: { style.colors.last ?? .orange }, set: { var c = style.colors; if !c.isEmpty { c[c.count - 1] = $0 }; style.colors = c })
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: Binding(get: { style.showPhoto }, set: { style.showPhoto = $0 })) {
                Text("Dégradé").tag(false)
                Text("Photo").tag(true)
            }
            .pickerStyle(.segmented)

            if style.showPhoto {
                Button {
                    showPhotoPicker = true
                } label: {
                    PhotoPickerLabel(hasImage: style.imageFile != nil)
                }
                .buttonStyle(RemoteGlassButtonStyle(prominent: true))

                if style.imageFile != nil {
                    Button(role: .destructive) {
                        style.imageFile = nil
                        style.showPhoto = false
                    } label: {
                        Label("Supprimer la photo", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RemoteGlassButtonStyle())
                }
            } else {
                // Thèmes prêts à l'emploi, un par marque
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(DeviceKind.allCases) { kind in
                            let preset = BackgroundStyle.preset(for: kind)
                            let isOn = preset.colorHexes == style.colorHexes
                            Button {
                                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                    style.colorHexes = preset.colorHexes
                                    style.weight = 0.5
                                    style.spread = 0.5
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    BackgroundView(style: preset)
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isOn ? accent : .white.opacity(0.2), lineWidth: isOn ? 2.5 : 1))
                                    Text(kind.shortName)
                                        .font(.caption2.weight(.medium))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                }

                if style.colorHexes.count == 2 {
                    ColorPicker("Couleur 1", selection: color1, supportsOpacity: false)
                    ColorPicker("Couleur 2", selection: color2, supportsOpacity: false)
                    slider(String(localized: "Hauteur"), value: $style.weight)
                    slider(String(localized: "Progression"), value: $style.spread)
                }
            }
        }
        .environment(\.buttonShape, .squircle)
        .fullScreenCover(isPresented: $showPhotoPicker) {
            WallpaperPhotoPicker { image, targetPixelSize in
                wallpaperDraft = WallpaperDraft(image: WallpaperImageProcessor.normalizedImage(from: image), targetPixelSize: targetPixelSize)
                showPhotoPicker = false
            } onCancel: {
                showPhotoPicker = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $wallpaperDraft) { draft in
            WallpaperCropView(image: draft.image, targetPixelSize: draft.targetPixelSize) { wallpaper in
                if let jpeg = wallpaper.jpegData(compressionQuality: 0.92) {
                    style.imageFile = BackgroundImageStore.store(jpeg)
                    style.showPhoto = true
                }
                wallpaperDraft = nil
            } onCancel: {
                wallpaperDraft = nil
            }
            .ignoresSafeArea()
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Slider(value: value, in: 0...1).tint(accent)
        }
    }
}

struct ButtonAppearanceEditor: View {
    @Binding var buttonShape: ButtonShape
    @Binding var disableStretch: Bool
    @Binding var tint: Double
    var accent: Color

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(ButtonShape.allCases) { shape in
                    Button {
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) { buttonShape = shape }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: shape == .circle
                                  ? (buttonShape == shape ? "checkmark.circle.fill" : "circle")
                                  : (buttonShape == shape ? "checkmark.square.fill" : "square"))
                                .font(.title2)
                                .contentTransition(.symbolEffect(.replace))
                            Text(shape == .circle ? String(localized: "Ronds") : String(localized: "Arrondis"))
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 72)
                    }
                    .buttonStyle(RemoteGlassButtonStyle(prominent: buttonShape == shape))
                    .environment(\.buttonShape, .squircle)
                }
            }

            Toggle("Désactiver HDR et étirement", isOn: $disableStretch)
                .font(.caption)
                .tint(accent)

            VStack(spacing: 4) {
                HStack {
                    Text("Teinte Liquid Glass").font(.caption)
                    Spacer()
                    Text("\(Int(tint * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                HStack(spacing: 8) {
                    Image(systemName: "drop").font(.caption).foregroundStyle(.white.opacity(0.5))
                    Slider(value: $tint, in: 0...1).tint(accent)
                    Image(systemName: "drop.fill").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }

            if let major = Int(UIDevice.current.systemVersion.split(separator: ".").first ?? ""), major >= 27 {
                Text("Vous êtes sur iOS \(UIDevice.current.systemVersion), la teinte du Liquid Glass dépend aussi de vos réglages d'apparence iOS")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
