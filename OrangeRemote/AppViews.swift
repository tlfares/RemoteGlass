import SwiftUI
import UIKit

// MARK: - Racine

struct RemoteView: View {
    @StateObject private var hub = DeviceHub()
    @State private var selection = ""
    @State private var backgroundFade = BackgroundFade()
    @State private var showAddDevice = false
    @State private var windowSize: CGSize = .zero
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private static let settingsTag = "settings"

    private var selectedTab: RemoteTabConfig? {
        hub.tabs.first { $0.id.uuidString == selection }
    }

    /// Sélection qui prépare le fondu du fond avant de changer d'onglet (évite une frame sans transition).
    private var animatedSelection: Binding<String> {
        Binding(
            get: { selection },
            set: { select($0) }
        )
    }

    private func select(_ newValue: String) {
        guard newValue != selection else { return }
        let old = selection == Self.settingsTag ? nil : hub.tabs.first { $0.id.uuidString == selection }
        backgroundFade = BackgroundFade(token: backgroundFade.token + 1, from: hub.background(for: old))
        selection = newValue
    }

    /// Écran partagé actif : la seconde télécommande n'a plus son propre onglet.
    private var mergedPartner: RemoteTabConfig? {
        guard hub.splitView, windowSize.width >= RemotePage.minimumSplitWidth, let fixed = hub.fixedSplitPartner else { return nil }
        // Il ne quitte la tab bar que s'il est réellement affiché à côté d'un autre onglet.
        return hub.tabs.contains { $0.id != fixed.id && hub.splitPartner(for: $0)?.id == fixed.id } ? fixed : nil
    }

    private var visibleTabs: [RemoteTabConfig] {
        guard let partner = mergedPartner else { return hub.tabs }
        return hub.tabs.filter { $0.id != partner.id }
    }

    private func title(for tab: RemoteTabConfig) -> String {
        guard let partner = mergedPartner else { return hub.title(for: tab) }
        return "\(hub.title(for: tab)) + \(hub.title(for: partner))"
    }

    var body: some View {
        TabView(selection: animatedSelection) {
            ForEach(visibleTabs) { tab in
                Tab(title(for: tab), systemImage: hub.symbol(for: tab), value: tab.id.uuidString) {
                    RemotePage(
                        hub: hub,
                        tab: tab,
                        isSelected: selection == tab.id.uuidString,
                        openSettings: { select(Self.settingsTag) },
                        addDevice: { showAddDevice = true }
                    )
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                }
            }

            Tab(String(localized: "Réglages"), systemImage: "gearshape", value: Self.settingsTag) {
                SettingsTab(hub: hub, isSelected: selection == Self.settingsTag)
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
            }
        }
        // iPad en paysage : tab bar native en bas (comme sur iPhone) ; le contenu garde sa vraie classe.
        .environment(\.horizontalSizeClass, windowSize.width > windowSize.height ? .compact : horizontalSizeClass)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        .onChange(of: mergedPartner?.id) { _, partnerID in
            // L'onglet affiché vient de fusionner : on bascule sur l'onglet combiné.
            if let partnerID, selection == partnerID.uuidString {
                selection = visibleTabs.first?.id.uuidString ?? Self.settingsTag
            }
        }
        .environment(\.backgroundFade, backgroundFade)
        .tint(hub.background(for: selectedTab).accent)
        .environment(\.glassTint, hub.glassTint)
        .environment(\.buttonShape, hub.buttonShape)
        .environment(\.disableStretch, hub.disableStretch)
        .onAppear {
            if selection.isEmpty { selection = hub.tabs.first?.id.uuidString ?? Self.settingsTag }
            updateAppIcon()
        }
        .onChange(of: hub.tabs.map(\.id)) { _, ids in
            // Onglet supprimé : on retombe sur le premier.
            if selection != Self.settingsTag, !ids.contains(where: { $0.uuidString == selection }) {
                selection = ids.first?.uuidString ?? Self.settingsTag
            }
        }
        .onChange(of: hub.prefersGoogleIcon) { _, _ in updateAppIcon() }
        .sheet(isPresented: $showAddDevice) {
            AddDeviceSheet(hub: hub, createsTab: true)
        }
        .sheet(isPresented: .init(
            get: { !hasSeenOnboarding },
            set: { if !$0 { hasSeenOnboarding = true } }
        )) {
            OnboardingView(accent: hub.sharedBackground.accent) {
                hasSeenOnboarding = true
                if hub.devices.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showAddDevice = true }
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationCornerRadius(40)
            .presentationBackground(.ultraThinMaterial)
            .interactiveDismissDisabled()
        }
    }

    /// Ne change l'icône que si nécessaire : iOS affiche une alerte à chaque changement.
    private func updateAppIcon() {
        let desired: String? = hub.prefersGoogleIcon ? "RemoteGlassGTV" : nil
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != desired else { return }
        UIApplication.shared.setAlternateIconName(desired)
    }
}

// MARK: - Page : une télécommande, ou deux côte à côte sur grand écran

struct RemotePage: View {
    @ObservedObject var hub: DeviceHub
    var tab: RemoteTabConfig
    var isSelected: Bool
    var openSettings: () -> Void
    var addDevice: () -> Void

    /// Largeur minimale pour deux télécommandes confortables (≈ 320 pt chacune).
    static let minimumSplitWidth: CGFloat = 640
    static let splitAnimation = Animation.spring(response: 0.62, dampingFraction: 0.86)

    /// Le partenaire n'apparaît qu'après coup : en dépliant, on voit d'abord la télécommande
    /// unique de l'écran externe glisser vers la gauche pour laisser place à la seconde.
    @State private var partnerShown = false

    var body: some View {
        GeometryReader { proxy in
            let eligible = proxy.size.width >= Self.minimumSplitWidth && hub.splitView ? hub.splitPartner(for: tab) : nil
            let partner = partnerShown ? eligible : nil
            // En portrait, les deux télécommandes s'empilent : la principale en haut.
            let isVertical = proxy.size.height > proxy.size.width
            let layout = isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            ZStack {
                SplitBackground(
                    primary: hub.background(for: tab),
                    partner: eligible.map { hub.background(for: $0) },
                    isSplit: partner != nil,
                    isVertical: isVertical
                )

                layout {
                    // Un appareil déjà affiché dans l'autre moitié n'a pas besoin d'un second bouton power ici.
                    // Les deux trackpads s'alignent sur la moitié qui a le plus de rangées de boutons.
                    let matchedRows = partner.flatMap { partner in
                        buttonRows(tab).flatMap { mine in buttonRows(partner).map { max(mine, $0) } }
                    }
                    pane(tab, shownElsewhere: eligible.flatMap { hub.activeDevice(in: $0)?.id }, matchedRows: matchedRows)
                    if let partner {
                        pane(partner, shownElsewhere: hub.activeDevice(in: tab)?.id, matchedRows: matchedRows)
                            .transition(.move(edge: isVertical ? .bottom : .trailing).combined(with: .opacity))
                    }
                }
            }
            .onAppear { partnerShown = eligible != nil }
            .onChange(of: eligible?.id) { _, id in
                guard id != nil else {
                    partnerShown = false
                    return
                }
                if partnerShown {
                    // Changement de partenaire : simple fondu enchaîné.
                    withAnimation(Self.splitAnimation) { partnerShown = true }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(Self.splitAnimation) { partnerShown = true }
                }
            }
            .animation(Self.splitAnimation, value: partner?.id)
        }
        .ignoresSafeArea(.keyboard)
    }

    /// Rangées de boutons autour du trackpad (nil en disposition classique).
    private func buttonRows(_ tab: RemoteTabConfig) -> Int? {
        guard hub.layout(in: tab) == .trackpad else { return nil }
        return (hub.activeDevice(in: tab)?.kind ?? .orange).supportsKeyboard ? 3 : 2
    }

    private func pane(_ tab: RemoteTabConfig, shownElsewhere: UUID?, matchedRows: Int?) -> some View {
        RemoteTabView(hub: hub, tab: tab, isSelected: isSelected, drawsBackground: false, deviceShownElsewhere: shownElsewhere, matchedButtonRows: matchedRows, openSettings: openSettings, addDevice: addDevice)
            .tint(hub.background(for: tab).accent)
            .id(tab.id)
    }
}

/// Fond d'une page. En mode double : noir en haut, et la couleur de chaque télécommande
/// monte depuis son coin inférieur (gauche pour l'une, droite pour l'autre).
struct SplitBackground: View {
    var primary: BackgroundStyle
    var partner: BackgroundStyle?
    var isSplit: Bool
    var isVertical = false

    var body: some View {
        ZStack {
            FadingBackground(style: primary)
                .opacity(isSplit ? 0 : 1)
            if let partner {
                FadingBackground(style: primary, splitPartner: partner, isVertical: isVertical)
                    .opacity(isSplit ? 1 : 0)
            }
        }
        .animation(RemotePage.splitAnimation, value: isSplit)
    }
}

/// Deux lueurs fondues sur du noir : depuis les coins inférieurs côte à côte,
/// depuis les coins haut-gauche / bas-droit quand les télécommandes sont empilées.
struct CornerGlowBackground: View {
    var leading: BackgroundStyle
    var trailing: BackgroundStyle
    var isVertical = false

    var body: some View {
        GeometryReader { proxy in
            // Portrait (empilées) : coins opposés, la diagonale reste sombre.
            // Paysage (côte à côte) : les deux couleurs montent des coins inférieurs, noir en haut.
            let radius = isVertical
                ? hypot(proxy.size.width, proxy.size.height) * 0.62
                : max(proxy.size.width * 0.74, proxy.size.height * 0.92)
            ZStack {
                Color.black
                glow(leading, corner: isVertical ? .topLeading : .bottomLeading, radius: radius)
                glow(trailing, corner: .bottomTrailing, radius: radius)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: leading)
        .animation(.easeInOut(duration: 0.35), value: trailing)
    }

    @ViewBuilder
    private func glow(_ style: BackgroundStyle, corner: UnitPoint, radius: CGFloat) -> some View {
        let fade = RadialGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.8), location: 0.3),
                .init(color: .white.opacity(0.35), location: 0.62),
                .init(color: .white.opacity(0.08), location: 0.85),
                .init(color: .clear, location: 1),
            ],
            center: corner,
            startRadius: 0,
            endRadius: radius
        )
        if style.showPhoto && style.imageFile != nil || style.colorHexes.count > 2 {
            // Photo ou dégradé multicolore : on garde le fond tel quel, révélé depuis le coin.
            BackgroundView(style: style).mask(fade)
        } else {
            (style.colors.last ?? .orange).mask(fade)
        }
    }
}

// MARK: - Onglet télécommande

struct RemoteTabView: View {
    @ObservedObject var hub: DeviceHub
    var tab: RemoteTabConfig
    var isSelected: Bool
    var drawsBackground = true
    /// Appareil affiché dans l'autre moitié de l'écran (mode double).
    var deviceShownElsewhere: UUID? = nil
    /// Mode double : nombre de rangées de boutons commun aux deux moitiés, pour aligner les trackpads.
    var matchedButtonRows: Int? = nil
    var openSettings: () -> Void
    var addDevice: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshToken = 0
    @State private var keyboardLayoutVisible = false
    /// Cadre du clavier (coordonnées écran) : la page ignore le clavier, on réserve donc la place nous-mêmes.
    @State private var keyboardFrame: CGRect = .zero
    @State private var showAddDeviceHere = false
    @State private var showTabSettings = false

    private var activeDevice: SavedDevice? { hub.activeDevice(in: tab) }
    private var kind: DeviceKind { activeDevice?.kind ?? .orange }
    private var isTrackpad: Bool { hub.layout(in: tab) == .trackpad }

    /// Menu Source pour les TV qui listent leurs entrées (LG webOS).
    private var sourceMenu: SourceMenu? {
        // Menu des entrées quand la TV sait les lister (LG, Roku TV) ; sinon le bouton envoie la touche Source.
        guard let device = activeDevice, device.kind.supportsInput else { return nil }
        let id = device.id
        return SourceMenu(
            sources: hub.inputSources[id] ?? [],
            currentID: hub.currentInput[id],
            load: { hub.loadInputSources(for: id) },
            select: { hub.selectInput($0, deviceID: id) }
        )
    }

    private var power: PowerActions {
        let primary = activeDevice
        let extra = hub.device(tab.companionID).flatMap { $0.id == primary?.id || $0.id == deviceShownElsewhere ? nil : $0 }
        var primaryBadge = hub.powerBadge(for: primary)
        var extraBadge = hub.powerBadge(for: extra)
        if let primary, let extra, primaryBadge == extraBadge {
            primaryBadge = primary.kind.shortName.uppercased()
            extraBadge = extra.kind.shortName.uppercased()
        }
        return PowerActions(
            primary: { hub.togglePower(primary?.id) },
            primaryBadge: primaryBadge,
            extra: extra.map { device in { hub.togglePower(device.id) } },
            extraBadge: extraBadge
        )
    }

    var body: some View {
        ZStack {
            if drawsBackground {
                FadingBackground(style: hub.background(for: tab))
            }

            if activeDevice == nil {
                EmptyRemoteView(accent: hub.background(for: tab).accent, hasDevices: !hub.devices.isEmpty, addDevice: addDevice, openSettings: openSettings)
            } else {
                remote
            }
        }
        // « Réglages… » du menu du haut : les réglages de cet onglet, pas l'écran Réglages général.
        .sheet(isPresented: $showTabSettings) {
            TabEditorSheet(hub: hub, tabID: tab.id)
        }
        .sheet(isPresented: $showAddDeviceHere) {
            AddDeviceSheet(hub: hub, createsTab: false, targetTabID: tab.id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshToken &+= 1
                hub.refreshVisibleDevices()
            }
        }
        .onAppear { keyboardLayoutVisible = hub.isKeyboardVisible }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            guard isTrackpad, isSelected else { return }
            let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            withAnimation(Self.keyboardAnimation(for: notification)) {
                keyboardFrame = frame
                keyboardLayoutVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            guard isTrackpad else { return }
            withAnimation(Self.keyboardAnimation(for: notification)) {
                keyboardLayoutVisible = false
                keyboardFrame = .zero
            }
        }
    }

    private var remote: some View {
        GeometryReader { proxy in
            // Partie de la page masquée par le clavier.
            let keyboardOverlap = keyboardLayoutVisible && keyboardFrame.height > 0
                ? min(proxy.size.height * 0.7, max(0, proxy.frame(in: .global).maxY - keyboardFrame.minY))
                : 0
            let ownRows = kind.supportsKeyboard ? 3 : 2
            let paddingRows = keyboardLayoutVisible ? 0 : max(0, (matchedButtonRows ?? ownRows) - ownRows)
            let metrics = RemoteLayoutMetrics(
                containerSize: CGSize(width: proxy.size.width, height: proxy.size.height - keyboardOverlap),
                isCleanMode: isTrackpad,
                isKeyboardVisible: keyboardLayoutVisible,
                hasPowerRow: kind.supportsKeyboard || paddingRows > 0,
                splitsPowerRowWhenWide: power.extra != nil
            )

            let header = RemoteHeader(hub: hub, tab: tab, isCompact: metrics.usesCompactHeader, openSettings: { showTabSettings = true }, addDeviceHere: { showAddDeviceHere = true })
                .offset(y: isSelected ? 0 : -6)
                .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.85), value: isSelected)
            // Mode large : le nom de l'appareil passe au-dessus des boutons de gauche.
            let wideHeader = metrics.isWide ? AnyView(header) : nil

            VStack(spacing: metrics.sectionSpacing) {
                if !metrics.isWide {
                    header
                }

                Group {
                    if isTrackpad {
                        CleanControlSurface(
                            buttonSize: metrics.buttonSize,
                            spacing: metrics.controlSpacing,
                            touchPadHeight: metrics.touchPadHeight,
                            send: { hub.send($0, in: tab) },
                            sendDirection: { hub.send($0, in: tab, direction: $1) },
                            sendText: { hub.sendText($0, in: tab) },
                            toggleClassic: { setLayout(.classic) },
                            kind: kind,
                            power: power,
                            showsBottomRow: !metrics.hidesBottomRow,
                            isKeyboardVisible: $hub.isKeyboardVisible,
                            isWide: metrics.isWide,
                            wideHeader: wideHeader,
                            sourceMenu: sourceMenu,
                            paddingRows: metrics.isWide ? 0 : paddingRows
                        )
                    } else {
                        ControlSurface(
                            keypad: Self.keypad,
                            buttonSize: metrics.buttonSize,
                            spacing: metrics.controlSpacing,
                            send: { hub.send($0, in: tab) },
                            sendDirection: { hub.send($0, in: tab, direction: $1) },
                            kind: kind,
                            power: power,
                            toggleClean: { setLayout(.trackpad) },
                            isWide: metrics.isWide,
                            wideHeader: wideHeader,
                            sourceMenu: sourceMenu
                        )
                    }
                }
                .frame(maxWidth: metrics.maxContentWidth)
                .transition(.opacity.combined(with: .scale(scale: 0.93)))
                .id(refreshToken)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: metrics.pinControlsToBottom ? .bottom : .center)
            .padding(.bottom, metrics.pinControlsToBottom ? 8 : 0)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .padding(.bottom, keyboardOverlap)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func setLayout(_ layout: RemoteLayout) {
        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) {
            hub.setLayout(layout, in: tab.id)
        }
    }

    static let keypad: [[OrangeKey]] = [
        [.one, .two, .three],
        [.four, .five, .six],
        [.seven, .eight, .nine],
        [.zero],
    ]

    private static func keyboardAnimation(for notification: Notification) -> Animation {
        let rawDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? UIView.AnimationCurve.easeInOut.rawValue
        let duration = max(0.16, rawDuration)
        switch UIView.AnimationCurve(rawValue: curveValue) ?? .easeInOut {
        case .easeIn: return .easeIn(duration: duration)
        case .easeOut: return .easeOut(duration: duration)
        case .linear: return .linear(duration: duration)
        default: return .easeInOut(duration: duration)
        }
    }
}

// MARK: - En-tête : appareil piloté et état

struct RemoteHeader: View {
    @ObservedObject var hub: DeviceHub
    var tab: RemoteTabConfig
    var isCompact: Bool
    var openSettings: () -> Void
    var addDeviceHere: () -> Void = {}

    private var active: SavedDevice? { hub.activeDevice(in: tab) }
    private var tabDevices: [SavedDevice] { hub.devices(in: tab) }
    /// Appareils enregistrés qu'on peut ajouter à cet onglet.
    private var otherDevices: [SavedDevice] {
        let here = Set(tab.allDeviceIDs)
        return hub.devices.filter { !here.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: isCompact ? 4 : 10) {
            deviceMenu
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }

    /// Toucher le nom de l'appareil permet d'en changer instantanément.
    private var deviceMenu: some View {
        Menu {
            // Plusieurs appareils dans l'onglet : on bascule de l'un à l'autre ici.
            if tabDevices.count > 1 {
                Section(String(localized: "Dans cet onglet")) {
                    ForEach(tabDevices) { device in
                        Button {
                            withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) {
                                hub.selectDevice(device.id, in: tab.id)
                            }
                        } label: {
                            Label(device.displayName, systemImage: device.id == active?.id ? "checkmark" : device.kind.systemImage)
                        }
                    }
                }
            }

            Section {
                if otherDevices.isEmpty {
                    Button(action: addDeviceHere) {
                        Label(String(localized: "Ajouter un appareil ici"), systemImage: "plus")
                    }
                } else {
                    Menu {
                        ForEach(otherDevices) { device in
                            Button {
                                withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) {
                                    hub.attachDevice(device.id, to: tab.id)
                                }
                            } label: {
                                Label(device.displayName, systemImage: device.kind.systemImage)
                            }
                        }
                        Divider()
                        Button(action: addDeviceHere) {
                            Label(String(localized: "Nouvel appareil…"), systemImage: "plus")
                        }
                    } label: {
                        Label(String(localized: "Ajouter un appareil ici"), systemImage: "plus")
                    }
                }
                if tabDevices.count > 1, let active {
                    Button(role: .destructive) {
                        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) {
                            hub.detachDevice(active.id, from: tab.id)
                        }
                    } label: {
                        Label(String(localized: "Retirer de cet onglet"), systemImage: "minus.circle")
                    }
                }
            }

            Section {
                Button {
                    hub.testConnection(active?.id)
                } label: {
                    Label(String(localized: "Tester la connexion"), systemImage: "antenna.radiowaves.left.and.right")
                }
                Button(action: openSettings) {
                    Label(String(localized: "Réglages…"), systemImage: "gearshape")
                }
            }
        } label: {
            Group {
                if isCompact {
                    HStack(spacing: 7) {
                        icon(size: 18)
                        labels(alignment: .leading, nameFont: .subheadline.weight(.semibold))
                    }
                } else {
                    VStack(spacing: 6) {
                        icon(size: 30)
                        labels(alignment: .center, nameFont: .headline)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func icon(size: CGFloat) -> some View {
        Image(systemName: active?.kind.systemImage ?? "tv")
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect(.replace))
    }

    private func labels(alignment: HorizontalAlignment, nameFont: Font) -> some View {
        let status = hub.status(of: active?.id)
        return VStack(alignment: alignment, spacing: 1) {
            HStack(spacing: 4) {
                Text(active?.displayName ?? String(localized: "Aucun appareil"))
                    .font(nameFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(0.6)
            }
            if !isCompact || status != .connected {
                HStack(spacing: 5) {
                    Circle()
                        .fill(status.indicatorColor)
                        .frame(width: 6, height: 6)
                    Text(status.title(for: active?.kind))
                        .font(.caption)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

extension ConnectionStatus {
    var indicatorColor: Color {
        switch self {
        case .connected: .green
        case .failed, .notFound, .needsPairing: .red
        case .testing, .sending, .scanning, .pairing: .yellow
        case .idle, .needsAddress: .white.opacity(0.5)
        }
    }
}

/// Onglet sans appareil : un seul geste pour commencer.
struct EmptyRemoteView: View {
    var accent: Color
    var hasDevices: Bool
    var addDevice: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 44, weight: .semibold))
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(.white)
            VStack(spacing: 6) {
                Text("Aucun appareil")
                    .font(.title3.weight(.bold))
                Text("Ajoute ton décodeur ou ta TV : tout reste sur ton réseau local.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Button(action: addDevice) {
                Label("Ajouter un appareil", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .frame(minHeight: 52)
            }
            .buttonStyle(RemoteGlassButtonStyle(prominent: true))
            .environment(\.buttonShape, .squircle)
            if hasDevices {
                Button("Choisir dans les réglages", action: openSettings)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

// MARK: - Fond

/// Changement d'onglet en cours : le fond à faire disparaître en fondu.
struct BackgroundFade: Equatable {
    var token = 0
    var from: BackgroundStyle?
}

private struct BackgroundFadeKey: EnvironmentKey {
    static let defaultValue = BackgroundFade()
}

extension EnvironmentValues {
    var backgroundFade: BackgroundFade {
        get { self[BackgroundFadeKey.self] }
        set { self[BackgroundFadeKey.self] = newValue }
    }
}

/// Fond d'un onglet qui apparaît en fondu depuis celui de l'onglet précédent.
/// La TabView ne met pas à jour les onglets cachés : on s'appuie donc sur un jeton qui change
/// à chaque sélection plutôt que sur « isSelected ». Tant que le jeton n'est pas consommé,
/// l'ancien fond est superposé, puis il s'efface en douceur.
struct FadingBackground: View {
    var style: BackgroundStyle
    /// Mode double : fond fusionné avec celui de la seconde télécommande.
    var splitPartner: BackgroundStyle?
    var isVertical = false

    @Environment(\.backgroundFade) private var fade
    @State private var consumedToken = 0

    static let animation = Animation.easeInOut(duration: 0.55)

    var body: some View {
        let fadingIn = fade.token != consumedToken
        ZStack {
            if let splitPartner {
                CornerGlowBackground(leading: style, trailing: splitPartner, isVertical: isVertical)
            } else {
                BackgroundView(style: style)
            }
            // Couche persistante dont on anime l'opacité : les transitions d'insertion/retrait
            // ne sont pas animées dans les pages de la TabView.
            if let from = fade.from, from != style {
                BackgroundView(style: from)
                    .opacity(fadingIn ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { consume() }
        .onChange(of: fade.token) { _, _ in consume() }
    }

    private func consume() {
        let token = fade.token
        guard token != consumedToken else { return }
        // Une frame avec l'ancien fond, puis le fondu.
        DispatchQueue.main.async {
            withAnimation(Self.animation) { consumedToken = token }
        }
    }
}

struct BackgroundView: View {
    var style: BackgroundStyle

    var body: some View {
        ZStack {
            if style.showPhoto, let file = style.imageFile, let image = BackgroundImageStore.image(named: file) {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else if style.isMesh, style.colorHexes.count >= 3 {
                MeshBackground(colors: style.colors, weight: style.weight, spread: style.spread)
            } else if style.colorHexes.count > 2 {
                let colors = style.colors
                ZStack {
                    colors.first ?? .black
                    LinearGradient(colors: Array(colors.dropFirst()), startPoint: .leading, endPoint: .trailing)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.55),
                                    .init(color: .white.opacity(0.5), location: 0.7),
                                    .init(color: .white, location: 0.85),
                                    .init(color: .white, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                let colors = style.colors
                let c1 = colors.first ?? .black
                let c2 = colors.last ?? c1
                let start = max(0, style.weight - (0.01 + style.spread * 0.49))
                let end = min(1, style.weight + (0.01 + style.spread * 0.49))
                LinearGradient(
                    stops: [
                        .init(color: c1, location: 0),
                        .init(color: c1, location: start),
                        .init(color: c2, location: end),
                        .init(color: c2, location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(Color.black.opacity(0.06))
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: style)
    }
}

/// Dégradé fondu à 3 ou 4 teintes : sombre en haut, la teinte la plus claire au coin inférieur droit.
struct MeshBackground: View {
    var colors: [Color]
    var weight: Double
    var spread: Double

    var body: some View {
        let c0 = colors[0]
        let c1 = colors[1]
        let c2 = colors[2]
        let c3 = colors.count > 3 ? colors[3] : c2
        // « Hauteur » déplace la rangée du milieu, « Progression » la courbe.
        let mid = Float(0.3 + weight * 0.4)
        let bend = Float(0.05 + spread * 0.2)
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, mid], [0.5 - bend, mid + bend * 0.6], [1, mid - bend],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                c0, c0, c0,
                c0, c1.mix(with: c0, by: 0.35), c1,
                c1, c2, c3,
            ],
            smoothsColors: true
        )
        .overlay(Color.black.opacity(0.06))
    }
}

// MARK: - Bienvenue

struct OnboardingView: View {
    var accent: Color
    var onConfirm: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isConstrained = proxy.size.height < 650
            ScrollView {
                VStack(spacing: isConstrained ? 14 : 22) {
                    VStack(spacing: 8) {
                        Text("Bienvenue sur\nRemoteGlass")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Une télécommande pour ta box et ta TV.\nSans compte, sans pub, 100 % en local.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 10) {
                        ForEach(DeviceKind.allCases) { kind in
                            HStack(spacing: 14) {
                                Image(systemName: kind.systemImage)
                                    .font(.title3)
                                    .frame(width: 34)
                                    .foregroundStyle(kind.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(kind.compatibilityNote)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 10) {
                        tip("square.stack.3d.up.fill", String(localized: "Un onglet par télécommande, réorganisable à volonté."))
                        tip("power", String(localized: "Associe ta TV à ta box : power TV et volume TV dans la même télécommande."))
                        tip("paintpalette.fill", String(localized: "Un fond commun, ou un fond différent pour chaque onglet."))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    Spacer(minLength: isConstrained ? 0 : 12)

                    Button(action: onConfirm) {
                        Text("Commencer")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .background(accent, in: Capsule())
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, min(24, max(16, proxy.size.width * 0.055)))
                .padding(.top, isConstrained ? 16 : 34)
                .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 22)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
