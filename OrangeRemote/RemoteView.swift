import SwiftUI
import PhotosUI
import UIKit

struct RemoteView: View {
    @StateObject private var model = RemoteViewModel()
    @State private var selectedTab: AppTab = .remote
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private let keypad: [[OrangeKey]] = [
        [.one, .two, .three],
        [.four, .five, .six],
        [.seven, .eight, .nine],
        [.zero]
    ]

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                RemoteTab(
                    status: model.status,
                    provider: model.selectedProvider,
                    keypad: keypad,
                    send: model.send,
                    sendDirection: model.send(_:direction:),
                    sendText: model.sendText,
                    bgColors: model.bgColors,
                    bgImageData: model.bgImageData,
                    bgShowPhoto: model.bgShowPhoto,
                    bgWeight: model.bgWeight,
                    bgSpread: model.bgSpread,
                    bgTint: model.bgTint,
                    bgButtonShape: model.bgButtonShape,
                    bgDisableStretch: model.bgDisableStretch,
                    selectedTab: $selectedTab,
                    isKeyboardVisible: $model.isKeyboardVisible
                )
                .tabItem {
                    Label(AppTab.remote.label, systemImage: AppTab.remote.systemName)
                }
                .tag(AppTab.remote)

                SettingsTab(
                    decoderIP: $model.decoderIP,
                    androidTVIP: $model.androidTVIP,
                    status: model.status,
                    isScanning: model.isScanning,
                    foundDecoders: model.foundDecoders,
                    discoveredAndroidTV: model.discoveredAndroidTV,
                    pendingAndroidTVPairing: model.pendingAndroidTVPairing,
                    pairingMessage: model.pairingMessage,
                    selectedProvider: $model.selectedProvider,
                    scanAction: model.scanLocalNetwork,
                    pairAction: model.beginAndroidTVPairing,
                    finishPairingAction: model.finishAndroidTVPairing,
                    cancelPairingAction: model.cancelPairing,
                    confirmAction: {
                        if model.selectedProvider == "Android TV" {
                            model.discoveredAndroidTV = []
                            if !model.androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                model.testConnection()
                            }
                        } else {
                            model.foundDecoders = []
                            if !model.decoderIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                model.testConnection()
                            }
                        }
                    },
                    onSceneActive: { model.onActive() },
                    savedGTVDevices: model.savedGTVDevices,
                    connectToSavedAction: { device in
                        model.connectToSavedGTVDevice(device)
                    },
                    bgColors: $model.bgColors,
                    bgImageData: $model.bgImageData,
                    showPhoto: $model.bgShowPhoto,
                    bgWeight: $model.bgWeight,
                    bgSpread: $model.bgSpread,
                    bgTint: $model.bgTint,
                    bgButtonShape: $model.bgButtonShape,
                    disableStretch: $model.bgDisableStretch,
                    selectedTab: $selectedTab,
                    hasCustomizedColors: $model.hasCustomizedColors
                )
                .tabItem {
                    Label(AppTab.settings.label, systemImage: AppTab.settings.systemName)
                }
                .tag(AppTab.settings)
            }
            .tint(model.bgColors.count > 2 ? .blue : .orange)
        }
        .sheet(isPresented: .init(
            get: { !hasSeenOnboarding },
            set: { if !$0 { hasSeenOnboarding = true } }
        )) {
            OnboardingView(
                provider: $model.selectedProvider,
                accentColor: model.bgColors.count > 2 ? .blue : .orange,
                onConfirm: {
                    hasSeenOnboarding = true
                    selectedTab = .settings
                }
            )
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationCornerRadius(40)
            .presentationBackground(.ultraThinMaterial)
            .interactiveDismissDisabled()
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case remote = "Remote"
    case settings = "Settings"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .remote: String(localized: "Remote")
        case .settings: String(localized: "Settings")
        }
    }

    var systemName: String {
        switch self {
        case .remote: "dot.radiowaves.left.and.right"
        case .settings: "gearshape"
        }
    }

}

private struct HeaderView: View {
    var status: ConnectionStatus
    var provider: String = "Orange"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tv")
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(status.title(for: provider))
                .font(.headline)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }
}

private struct RemoteTab: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshToken = 0
    @State private var isEpureMode = false
    var status: ConnectionStatus
    var provider: String
    var keypad: [[OrangeKey]]
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var sendText: (String) -> Void
    var bgColors: [Color]
    var bgImageData: Data?
    var bgShowPhoto: Bool
    var bgWeight: Double
    var bgSpread: Double
    var bgTint: Double
    var bgButtonShape: ButtonShape
    var bgDisableStretch: Bool
    @Binding var selectedTab: AppTab
    @Binding var isKeyboardVisible: Bool

    private var isCompact: Bool {
        UIScreen.main.bounds.height <= 700
    }

    var body: some View {
        ZStack {
            BackgroundView(colors: bgColors, imageData: bgImageData, showImage: bgShowPhoto, weight: bgWeight, spread: bgSpread)

            GeometryReader { proxy in
                let widthSize = (proxy.size.width - 78) / 5
                let heightSize = (proxy.size.height - 114) / 10.8
                let buttonSize = min(62, max(isCompact && (isKeyboardVisible || !isEpureMode) ? 42 : 48, min(widthSize, heightSize)))

                VStack(spacing: isCompact ? 0 : 12) {
                    if isCompact {
                        Color.clear.frame(height: 6)

                        HeaderView(status: status, provider: provider)
                            .offset(y: -10 + (selectedTab == .remote ? 0 : -6))
                            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.85), value: selectedTab)

                        if isEpureMode {
                            CleanControlSurface(
                                buttonSize: buttonSize,
                                send: send,
                                sendDirection: sendDirection,
                                sendText: sendText,
                                toggleClassic: { withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) { isEpureMode = false } },
                                provider: provider,
                                isKeyboardVisible: $isKeyboardVisible,
                                isCompact: true
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.93)))
                            .id(refreshToken)
                        } else {
                            ControlSurface(
                                keypad: keypad,
                                buttonSize: buttonSize,
                                send: send,
                                sendDirection: sendDirection,
                                provider: provider,
                                toggleClean: { withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) { isEpureMode = true } },
                                isCompact: true
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.93)))
                            .id(refreshToken)
                        }
                    } else {
                        Spacer(minLength: 0)

                        HeaderView(status: status, provider: provider)
                            .offset(y: -10 + (selectedTab == .remote ? 0 : -6))
                            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.85), value: selectedTab)

                        if isEpureMode {
                            CleanControlSurface(
                                buttonSize: buttonSize,
                                send: send,
                                sendDirection: sendDirection,
                                sendText: sendText,
                                toggleClassic: { withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) { isEpureMode = false } },
                                provider: provider,
                                isKeyboardVisible: $isKeyboardVisible
                            )
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.93)))
                            .id(refreshToken)
                        } else {
                            ControlSurface(
                                keypad: keypad,
                                buttonSize: buttonSize,
                                send: send,
                                sendDirection: sendDirection,
                                provider: provider,
                                toggleClean: { withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) { isEpureMode = true } }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.93)))
                            .id(refreshToken)
                        }

                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, isCompact ? 4 : 10)
                .padding(.bottom, isCompact ? 2 : 4)
                .offset(y: isCompact ? 0 : 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.glassTint, bgTint)
        .environment(\.buttonShape, bgButtonShape)
        .environment(\.disableStretch, bgDisableStretch)
        .onAppear {
            isEpureMode = provider == "Android TV"
        }
        .onChange(of: provider) { _, newProvider in
            withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) {
                isEpureMode = newProvider == "Android TV"
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshToken &+= 1
            }
        }
    }
}

private struct SettingsTab: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshToken = 0
    @Binding var decoderIP: String
    @Binding var androidTVIP: String
    var status: ConnectionStatus
    var isScanning: Bool
    var foundDecoders: [String]
    var discoveredAndroidTV: [DiscoveredAndroidTVDevice]
    var pendingAndroidTVPairing: DiscoveredAndroidTVDevice?
    var pairingMessage: String?
    @Binding var selectedProvider: String
    var scanAction: () -> Void
    var pairAction: (DiscoveredAndroidTVDevice) -> Void
    var finishPairingAction: (String) -> Void
    var cancelPairingAction: () -> Void
    var confirmAction: () -> Void
    var onSceneActive: () -> Void
    var savedGTVDevices: [SavedGTVDevice]
    var connectToSavedAction: (SavedGTVDevice) -> Void
    @Binding var bgColors: [Color]
    @Binding var bgImageData: Data?
    @Binding var showPhoto: Bool
    @Binding var bgWeight: Double
    @Binding var bgSpread: Double
    @Binding var bgTint: Double
    @Binding var bgButtonShape: ButtonShape
    @Binding var disableStretch: Bool
    @Binding var selectedTab: AppTab
    @Binding var hasCustomizedColors: Bool

    @ViewBuilder
    private var savedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appareils enregistrés")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            ForEach(savedGTVDevices) { device in
                Button {
                    connectToSavedAction(device)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "tv")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.body.weight(.medium))
                            Text(device.ip)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        if device.ip == androidTVIP {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .padding(.horizontal, 14)
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .squircle)
                .transition(.scale(scale: 0, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: savedGTVDevices)
    }

    var body: some View {
        ZStack {
            BackgroundView(colors: bgColors, imageData: bgImageData, showImage: showPhoto, weight: bgWeight, spread: bgSpread)

            ScrollView {
                VStack(spacing: 20) {
                    Color.clear
                        .frame(height: 40)
                        .accessibilityHidden(true)

                    HeaderView(status: status, provider: selectedProvider)
                        .offset(y: selectedTab == .settings ? 0 : -6)
                        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.85), value: selectedTab)

                    AddressPanel(
                        decoderIP: $decoderIP,
                        androidTVIP: $androidTVIP,
                        isScanning: isScanning,
                        foundDecoders: foundDecoders,
                        discoveredAndroidTV: discoveredAndroidTV,
                        pendingAndroidTVPairing: pendingAndroidTVPairing,
                        pairingMessage: pairingMessage,
                        selectedProvider: selectedProvider,
                        scanAction: scanAction,
                        pairAction: pairAction,
                        finishPairingAction: finishPairingAction,
                        cancelPairingAction: cancelPairingAction,
                        confirmAction: confirmAction
                    )
                    .id(refreshToken)

                    if selectedProvider == "Android TV" && !savedGTVDevices.isEmpty {
                        savedDevicesSection
                    }

                    BackgroundSettingsPanel(
                        colors: $bgColors,
                        imageData: $bgImageData,
                        showPhoto: $showPhoto,
                        weight: $bgWeight,
                        spread: $bgSpread,
                        tint: $bgTint,
                        buttonShape: $bgButtonShape,
                        disableStretch: $disableStretch,
                        selectedProvider: $selectedProvider,
                        hasCustomizedColors: $hasCustomizedColors
                    )

                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text("Credits :")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                            Link("@rmxptfl", destination: URL(string: "https://twitter.com/rmxptfl")!)
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
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .environment(\.glassTint, bgTint)
        .environment(\.disableStretch, disableStretch)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshToken &+= 1
                onSceneActive()
            }
        }
        .onChange(of: bgColors) { _, newColors in
            let isGTV = newColors.count > 2
            UIApplication.shared.setAlternateIconName(isGTV ? "RemoteGlassGTV" : nil)
        }
        .onAppear {
            let isGTV = bgColors.count > 2
            UIApplication.shared.setAlternateIconName(isGTV ? "RemoteGlassGTV" : nil)
        }
    }
}

private struct AddressPanel: View {
    @Binding var decoderIP: String
    @Binding var androidTVIP: String
    @FocusState private var addressFocused: Bool
    var isScanning: Bool
    var foundDecoders: [String]
    var discoveredAndroidTV: [DiscoveredAndroidTVDevice]
    var pendingAndroidTVPairing: DiscoveredAndroidTVDevice?
    var pairingMessage: String?
    var selectedProvider: String
    var scanAction: () -> Void
    var pairAction: (DiscoveredAndroidTVDevice) -> Void
    var finishPairingAction: (String) -> Void
    var cancelPairingAction: () -> Void
    var confirmAction: () -> Void
    @State private var androidTVPin = ""

    @State private var orangeState: OrangeIPState = .initial
    @State private var gtvManualIPShown = false
    @State private var gtvHasScanned = false

    private enum OrangeIPState {
        case initial
        case results
        case editing
    }

    private var currentIP: Binding<String> {
        Binding(
            get: { selectedProvider == "Android TV" ? androidTVIP : decoderIP },
            set: { v in
                if selectedProvider == "Android TV" { androidTVIP = v }
                else { decoderIP = v }
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            if selectedProvider == "Android TV" {
                androidTVBody
            } else {
                orangeBody
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: pendingAndroidTVPairing)
    }

    @ViewBuilder
    private var orangeBody: some View {
        switch orangeState {
        case .initial:
            Button {
                addressFocused = false
                scanAction()
                orangeState = .results
            } label: {
                Label(isScanning ? "Connexion" : "Détecter", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .disabled(isScanning)
            .buttonStyle(RemoteGlassButtonStyle(prominent: true))
            .environment(\.buttonShape, .squircle)

        case .results:
            Button {
                addressFocused = false
                scanAction()
            } label: {
                Label(isScanning ? "Recherche…" : "Détecter", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .disabled(isScanning)
            .buttonStyle(RemoteGlassButtonStyle(prominent: true))
            .environment(\.buttonShape, .squircle)

            ForEach(foundDecoders, id: \.self) { ip in
                Button {
                    decoderIP = ip
                    addressFocused = false
                    orangeState = .editing
                } label: {
                    Text(ip)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .squircle)
            }

            Button {
                decoderIP = ""
                orangeState = .editing
            } label: {
                Text("Saisir manuellement l'ip")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(RemoteGlassButtonStyle())
            .environment(\.buttonShape, .squircle)

        case .editing:
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.headline)
                TextField("IP du décodeur", text: currentIP)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($addressFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        addressFocused = false
                    }
            }
            .padding(14)
            .staticGlassPanel()

            Button {
                addressFocused = false
                confirmAction()
                orangeState = .initial
            } label: {
                Label("Confirmer", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(RemoteGlassButtonStyle(prominent: true))
            .environment(\.buttonShape, .squircle)
        }
    }

    @ViewBuilder
    private var androidTVBody: some View {
        if gtvManualIPShown {
            HStack(spacing: 10) {
                Image(systemName: "tv")
                    .font(.headline)
                TextField("IP de la Google TV", text: currentIP)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($addressFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        addressFocused = false
                    }
            }
            .padding(14)
            .staticGlassPanel()

            HStack(spacing: 10) {
                Button {
                    addressFocused = false
                    confirmAction()
                    gtvManualIPShown = false
                    gtvHasScanned = false
                } label: {
                    Label("Confirmer", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }

                Button {
                    addressFocused = false
                    gtvManualIPShown = false
                } label: {
                    Label("Annuler", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
            }
            .buttonStyle(RemoteGlassButtonStyle(prominent: true))
            .environment(\.buttonShape, .squircle)
        }

        if let pendingAndroidTVPairing {
            VStack(spacing: 10) {
                VStack(spacing: 4) {
                    Text(pendingAndroidTVPairing.name)
                        .font(.body.weight(.semibold))
                    if let pairingMessage {
                        Text(pairingMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    TextField("Code PIN", text: $androidTVPin)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($addressFocused)
                        .padding(14)
                        .staticGlassPanel()

                    Button {
                        addressFocused = false
                        finishPairingAction(androidTVPin)
                    } label: {
                        Image(systemName: "checkmark")
                            .frame(width: 48, height: 48)
                    }
                    .disabled(androidTVPin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(RemoteGlassButtonStyle(prominent: true))

                    Button {
                        androidTVPin = ""
                        addressFocused = false
                        cancelPairingAction()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(RemoteGlassButtonStyle())
                }
                .environment(\.buttonShape, .squircle)
            }
            .padding(12)
            .staticGlassPanel()
            .transition(.scale(scale: 0).combined(with: .opacity))
        }

        if !gtvManualIPShown && pendingAndroidTVPairing == nil {
            Button {
                addressFocused = false
                androidTVPin = ""
                gtvHasScanned = true
                scanAction()
            } label: {
                Label(isScanning ? "Recherche…" : "Détecter", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .disabled(isScanning)
            .buttonStyle(RemoteGlassButtonStyle(prominent: true))
            .environment(\.buttonShape, .squircle)

            if !discoveredAndroidTV.isEmpty {
                VStack(spacing: 8) {
                    ForEach(discoveredAndroidTV) { device in
                        Button {
                            androidTVPin = ""
                            addressFocused = false
                            pairAction(device)
                        } label: {
                            VStack(spacing: 2) {
                                Text(device.name)
                                    .font(.body.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                        }
                    }
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .squircle)
            }

            if gtvHasScanned {
                Button {
                    gtvManualIPShown = true
                } label: {
                    Text("Saisir manuellement l'ip")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(RemoteGlassButtonStyle())
                .environment(\.buttonShape, .squircle)
            }
        }
    }
}

private struct ControlSurface: View {
    var keypad: [[OrangeKey]]
    var buttonSize: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var provider: String
    var toggleClean: () -> Void
    var isCompact = false

    var body: some View {
        VStack(spacing: isCompact ? 8 : 14) {
            HStack(spacing: 10) {
                RemoteButton(systemName: "power", size: buttonSize, tint: .orange) { send(.power) }
                Spacer(minLength: 8)
                RemoteButton(systemName: "record.circle", size: buttonSize) { send(.record) }
            }

            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: 16) {
                    VerticalPair(
                        topIcon: "plus",
                        bottomIcon: "minus",
                        title: String(localized: "VOL"),
                        buttonSize: buttonSize,
                        topAction: { send(.volumeUp) },
                        bottomAction: { send(.volumeDown) }
                    )
                    RemoteButton(systemName: "speaker.slash.fill", size: buttonSize) { send(.mute) }
                }

                Spacer(minLength: 8)

                DirectionPad(buttonSize: buttonSize, send: send, sendDirection: sendDirection, provider: provider)
                    .padding(.horizontal, 8)
                    .offset(y: -(buttonSize * 0.45))

                Spacer(minLength: 8)

                VStack(spacing: 16) {
                    VerticalPair(
                        topIcon: "chevron.up",
                        bottomIcon: "chevron.down",
                        title: String(localized: "CH"),
                        buttonSize: buttonSize,
                        topAction: { send(.channelUp) },
                        bottomAction: { send(.channelDown) }
                    )
                    RemoteButton(systemName: "playpause.fill", size: buttonSize) { send(.playPause) }
                }
            }

            Group {
                HStack(spacing: 10) {
                    RemoteButton(systemName: "arrow.uturn.backward", size: buttonSize) { send(.back) }
                    RemoteButton(systemName: "house.fill", size: buttonSize) { send(.menu) }
                    RemoteButton(systemName: "rectangle.3.group", size: buttonSize) { toggleClean() }
                }

                VStack(spacing: 6) {
                    ForEach(keypad.indices, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(keypad[row]) { key in
                                RemoteButton(title: digitTitle(for: key), size: buttonSize) { send(key) }
                            }
                        }
                    }
                }
            }
            .offset(y: -4)
        }
    }

    private func digitTitle(for key: OrangeKey) -> String {
        switch key {
        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        default: ""
        }
    }
}

// MARK: - Clean Mode

private struct CleanControlSurface: View {
    var buttonSize: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var sendText: (String) -> Void
    var toggleClassic: () -> Void
    var provider: String
    @Binding var isKeyboardVisible: Bool
    var isCompact = false
    @State private var textFieldText = ""

    private var isKeyboardCompactHeight: Bool {
        isCompact || UIScreen.main.bounds.width <= 400
    }

    private var isMini: Bool {
        let model: String
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            model = sim
        } else {
            var systemInfo = utsname()
            uname(&systemInfo)
            let mirror = Mirror(reflecting: systemInfo.machine)
            model = mirror.children.compactMap { $0.value as? Int8 }.filter { $0 != 0 }.map { String(UnicodeScalar(UInt8($0))) }.joined()
        }
        return model == "iPhone13,1" || model == "iPhone14,4"
    }

    var body: some View {
        VStack(spacing: isCompact ? 8 : (isKeyboardVisible ? (isKeyboardCompactHeight ? 6 : 10) : 16)) {
                if provider == "Android TV" {
                    RemoteButton(systemName: "power", size: buttonSize, tint: .orange) { send(.power) }

                    if isKeyboardVisible {
                        HStack(spacing: 10) {
                            Button {
                                sendText("\u{1B}")
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isKeyboardVisible = false
                                    textFieldText = ""
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: buttonSize, height: buttonSize)
                                    .staticGlassPanel(cornerRadius: 22)
                            }

                            VisibleTextField(
                                text: $textFieldText,
                                sendText: sendText,
                                onSubmit: {
                                    sendText("\n")
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        isKeyboardVisible = false
                                        textFieldText = ""
                                    }
                                },
                                isActive: $isKeyboardVisible
                            )
                            .frame(height: buttonSize)
                            .environment(\.glassTint, 0)
                            .staticGlassPanel(cornerRadius: 22)
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity),
                            removal: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity)
                        ))
                    } else {
                        HStack(spacing: 10) {
                            RemoteButton(systemName: "keyboard", size: buttonSize) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isKeyboardVisible = true
                                }
                            }
                            RemoteButton(systemName: "minus", size: buttonSize) { send(.volumeDown) }
                            RemoteButton(systemName: "plus", size: buttonSize) { send(.volumeUp) }
                            RemoteButton(systemName: "speaker.slash.fill", size: buttonSize) { send(.mute) }
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    }
            } else {
                HStack(spacing: 10) {
                    RemoteButton(systemName: "power", size: buttonSize, tint: .orange) { send(.power) }
                    RemoteButton(systemName: "minus", size: buttonSize) { send(.volumeDown) }
                    RemoteButton(systemName: "plus", size: buttonSize) { send(.volumeUp) }
                    RemoteButton(systemName: "speaker.slash.fill", size: buttonSize) { send(.mute) }
                }
            }

            TouchPad(buttonSize: buttonSize, send: send, sendDirection: sendDirection, isKeyboardMinimized: isKeyboardVisible, provider: provider, keyboardCompact: isKeyboardCompactHeight)

            if !(isKeyboardVisible && isMini) {
                HStack(spacing: 10) {
                    RemoteButton(systemName: "arrow.uturn.backward", size: buttonSize) { send(.back) }
                    RemoteButton(systemName: "playpause.fill", size: buttonSize) { send(.playPause) }
                    RemoteButton(systemName: "house.fill", size: buttonSize) { send(.menu) }
                    RemoteButton(systemName: "square.grid.3x3", size: buttonSize) { toggleClassic() }
                }
            }
        }
    }
}

private struct TouchPad: View {
    var buttonSize: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var isKeyboardMinimized: Bool = false
    var provider: String = "Orange"
    var keyboardCompact: Bool = false

    @State private var isActive = false
    @State private var dragTranslation: CGSize = .zero
    @State private var touchTask: Task<Void, Never>?
    @State private var didSendDown = false
    @State private var didLongPress = false

    private let swipeThreshold: CGFloat = 30
    private let swipeDetection: Duration = .milliseconds(80)
    private let longPressDuration: Duration = .milliseconds(800)

    var body: some View {
        let height: CGFloat = isKeyboardMinimized
            ? (keyboardCompact
                ? max(120, min(170, buttonSize * 3.5))
                : max(180, min(300, buttonSize * 4.2)))
            : max(200, min(360, buttonSize * 5.2))

        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .staticGlassPanel(cornerRadius: 28)
            .overlay {
                ZStack {
                    if isActive {
                        if abs(dragTranslation.width) > swipeThreshold || abs(dragTranslation.height) > swipeThreshold {
                            arrowIcon
                                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                                Image(systemName: "app")
                                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    } else {
                VStack(spacing: 12) {
                            Image(systemName: "hand.point.up.fill")
                                .font(.system(size: buttonSize * 0.3))
                            Text("Tap · Glisser")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.white.opacity(0.45))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isActive)
                .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.6), value: dragTranslation)
            }
            .scaleEffect(isActive ? 0.97 : 1)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isActive)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let wasActive = isActive
                        isActive = true
                        dragTranslation = value.translation

                        if !wasActive {
                            didSendDown = false
                            didLongPress = false
                            if provider == "Android TV" {
                                touchTask = Task {
                                    try? await Task.sleep(for: swipeDetection)
                                    guard !Task.isCancelled, isActive else { return }
                                    guard abs(dragTranslation.width) < swipeThreshold,
                                          abs(dragTranslation.height) < swipeThreshold else { return }
                                    didSendDown = true
                                    sendDirection(.ok, 1)
                                    let remaining = longPressDuration - swipeDetection
                                    try? await Task.sleep(for: remaining)
                                    guard !Task.isCancelled, isActive else { return }
                                    guard abs(dragTranslation.width) < 10,
                                          abs(dragTranslation.height) < 10 else { return }
                                    didLongPress = true
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            }
                        }
                    }
                    .onEnded { value in
                        touchTask?.cancel()
                        let t = value.translation
                        let isSwipe = abs(t.width) > swipeThreshold || abs(t.height) > swipeThreshold
                        let isTap = abs(t.width) < 10 && abs(t.height) < 10

                        if isSwipe {
                            let direction: OrangeKey
                            if abs(t.width) > abs(t.height) {
                                direction = t.width > 0 ? .right : .left
                            } else {
                                direction = t.height > 0 ? .down : .up
                            }
                            send(direction)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } else if provider == "Android TV" {
                            if didLongPress {
                                sendDirection(.ok, 2)
                            } else if didSendDown && isTap {
                                sendDirection(.ok, 2)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } else if isTap {
                                send(.ok)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        } else if isTap {
                            send(.ok)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }

                        isActive = false
                        dragTranslation = .zero
                        didSendDown = false
                        didLongPress = false
                    }
            )
            .onDisappear {
                touchTask?.cancel()
            }
    }

    @ViewBuilder
    private var arrowIcon: some View {
        if abs(dragTranslation.width) > abs(dragTranslation.height) {
            Image(systemName: dragTranslation.width > 0 ? "arrow.right" : "arrow.left")
        } else {
            Image(systemName: dragTranslation.height > 0 ? "arrow.down" : "arrow.up")
        }
    }
}

private struct DirectionPad: View {
    var buttonSize: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var provider: String

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: buttonSize, height: buttonSize)
                RemoteButton(systemName: "chevron.up", size: buttonSize) { send(.up) }
                Color.clear.frame(width: buttonSize, height: buttonSize)
            }
            GridRow {
                RemoteButton(systemName: "chevron.left", size: buttonSize) { send(.left) }
                if provider == "Android TV" {
                    LongPressOkButton(size: buttonSize, send: send, sendDirection: sendDirection)
                } else {
                    RemoteButton(title: String(localized: "OK"), size: buttonSize, prominent: true) { send(.ok) }
                }
                RemoteButton(systemName: "chevron.right", size: buttonSize) { send(.right) }
            }
            GridRow {
                Color.clear.frame(width: buttonSize, height: buttonSize)
                RemoteButton(systemName: "chevron.down", size: buttonSize) { send(.down) }
                Color.clear.frame(width: buttonSize, height: buttonSize)
            }
        }
    }
}

private struct LongPressOkButton: View {
    @Environment(\.buttonShape) private var buttonShape
    var size: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void

    @State private var isPressed = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var didSendDown = false
    @State private var didLongPress = false

    var body: some View {
        let cr = buttonShape == .circle ? size / 2 : 20
        Text("OK")
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .frame(width: size, height: size)
            .padding(.horizontal, 4)
            .contentShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
            .modifier(RemoteGlassButtonChrome(prominent: true))
            .foregroundStyle(.white)
            .scaleEffect(isPressed ? 0.97 : 1)
            .opacity(isPressed ? 0.9 : 1)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        didSendDown = false
                        didLongPress = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        longPressTask = Task {
                            try? await Task.sleep(for: .milliseconds(80))
                            guard !Task.isCancelled, isPressed else { return }
                            didSendDown = true
                            sendDirection(.ok, 1)
                            try? await Task.sleep(for: .milliseconds(720))
                            guard !Task.isCancelled, isPressed else { return }
                            didLongPress = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        longPressTask?.cancel()
                        if didLongPress {
                            sendDirection(.ok, 2)
                        } else if didSendDown {
                            sendDirection(.ok, 2)
                        } else {
                            send(.ok)
                        }
                        isPressed = false
                        didSendDown = false
                        didLongPress = false
                    }
            )
            .onDisappear {
                longPressTask?.cancel()
            }
    }
}

private struct VerticalPair: View {
    var topIcon: String
    var bottomIcon: String
    var title: String
    var buttonSize: CGFloat
    var topAction: () -> Void
    var bottomAction: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            RemoteButton(systemName: topIcon, size: buttonSize, action: topAction)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.74))
            RemoteButton(systemName: bottomIcon, size: buttonSize, action: bottomAction)
        }
    }
}

private struct RemoteButton: View {
    @Environment(\.buttonShape) private var buttonShape
    var title: String?
    var systemName: String?
    var size: CGFloat
    var prominent = false
    var tint: Color?
    var action: () -> Void

    init(title: String, size: CGFloat, prominent: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemName = nil
        self.size = size
        self.prominent = prominent
        self.tint = tint
        self.action = action
    }

    init(systemName: String, size: CGFloat, prominent: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = nil
        self.systemName = systemName
        self.size = size
        self.prominent = prominent
        self.tint = tint
        self.action = action
    }

    var body: some View {
        let cr = buttonShape == .circle ? size / 2 : 20
        Button(action: action) {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: size * 0.34, weight: .semibold))
                } else {
                    Text(title ?? "")
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                }
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
        }
        .buttonStyle(RemoteGlassButtonStyle(prominent: prominent))
        .tint(tint)
        .accessibilityLabel(title ?? systemName ?? String(localized: "Commande"))
    }
}

private struct RemoteGlassButtonStyle: ButtonStyle {
    @Environment(\.disableStretch) var disableStretch
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let scale: CGFloat = pressed ? (disableStretch ? 1.3 : 0.97) : 1
        configuration.label
            .padding(.horizontal, 4)
            .modifier(RemoteGlassButtonChrome(prominent: prominent))
            .foregroundStyle(.white)
            .scaleEffect(scale)
            .opacity(pressed ? (disableStretch ? 1 : 0.9) : 1)
            .saturation(pressed && disableStretch ? 1.35 : 1)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            }
    }
}

private struct RemoteGlassButtonChrome: ViewModifier {
    @Environment(\.glassTint) var glassTint
    @Environment(\.buttonShape) var buttonShape
    @Environment(\.disableStretch) var disableStretch
    var prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if buttonShape == .circle {
                if glassTint > 0 {
                    content
                        .background(.black.opacity(glassTint * 0.4), in: Circle())
                        .glassEffect(disableStretch ? .regular : .regular.interactive(), in: Circle())
                } else {
                    content
                        .glassEffect(disableStretch ? .regular : .regular.interactive(), in: Circle())
                }
            } else {
                if glassTint > 0 {
                    content
                        .background(.black.opacity(glassTint * 0.4), in: .rect(cornerRadius: 20))
                        .glassEffect(disableStretch ? .regular : .regular.interactive(), in: .rect(cornerRadius: 20))
                } else {
                    content
                        .glassEffect(disableStretch ? .regular : .regular.interactive(), in: .rect(cornerRadius: 20))
                }
            }
        } else {
            if buttonShape == .circle {
                if prominent {
                    content
                        .background(.orange.opacity(0.52), in: Circle())
                } else {
                    content
                        .background(.ultraThinMaterial, in: Circle())
                }
            } else {
                if prominent {
                    content
                        .background(.orange.opacity(0.52), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    content
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }
}

private struct BackgroundSettingsPanel: View {
    @Binding var colors: [Color]
    @Binding var imageData: Data?
    @Binding var showPhoto: Bool
    @Binding var weight: Double
    @Binding var spread: Double
    @Binding var tint: Double
    @Binding var buttonShape: ButtonShape
    @Binding var disableStretch: Bool
    @Binding var selectedProvider: String
    @Binding var hasCustomizedColors: Bool
    @State private var isProviderExpanded = false
    @State private var isBackgroundExpanded = false
    @State private var isButtonsExpanded = false
    @State private var mode: BackgroundMode = .gradient
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var showCropSheet = false

    private var color1Binding: Binding<Color> {
        Binding(
            get: { colors.first ?? .black },
            set: { colors[0] = $0; hasCustomizedColors = true }
        )
    }

    private var color2Binding: Binding<Color> {
        Binding(
            get: { colors.last ?? (colors.first ?? .orange) },
            set: { colors[colors.count - 1] = $0; hasCustomizedColors = true }
        )
    }

    private var accentColor: Color {
        colors.count > 2 ? .blue : .orange
    }

    private static let orangePreset: [Color] = [
        Color(hex: "000000") ?? .black,
        Color(hex: "FF6A00") ?? .orange,
    ]

    private static let googleTVPreset: [Color] = [
        Color(hex: "000000") ?? .black,
        Color(hex: "4285F4") ?? .blue,
        Color(hex: "34A853") ?? .green,
        Color(hex: "EA4335") ?? .red,
        Color(hex: "FBBC04") ?? .yellow,
    ]

    private enum BackgroundMode: String, CaseIterable, Identifiable {
        case gradient
        case image
        var id: String { rawValue }
        var localizedName: String {
            switch self {
            case .gradient: String(localized: "Dégradé")
            case .image: String(localized: "Photo")
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Button {
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                    isProviderExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "network")
                        .font(.headline)
                    Text("Fournisseur (bêta)")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isProviderExpanded ? 180 : 0))
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isProviderExpanded {
                HStack(spacing: 10) {
                    Button {
                        selectedProvider = "Orange"
                    } label: {
                        Text("Orange")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RemoteGlassButtonStyle(prominent: selectedProvider == "Orange"))
                    .environment(\.buttonShape, .squircle)

                    Button {
                        selectedProvider = "Android TV"
                    } label: {
                        Text("Google TV")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RemoteGlassButtonStyle(prominent: selectedProvider == "Android TV"))
                    .environment(\.buttonShape, .squircle)
                }
            }

            Divider()
                .overlay(.white.opacity(0.15))

            Button {
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                    isBackgroundExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "paintpalette.fill")
                        .font(.headline)
                    Text("Fond d'écran")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isBackgroundExpanded ? 180 : 0))
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isBackgroundExpanded {
                Picker("Mode", selection: $mode) {
                    ForEach(BackgroundMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .gradient {
                    VStack(spacing: 12) {
                        if colors.count == 2 {
                            Group {
                                ColorPicker("Couleur 1", selection: color1Binding, supportsOpacity: false)
                                    .foregroundStyle(.white)

                                ColorPicker("Couleur 2", selection: color2Binding, supportsOpacity: false)
                                    .foregroundStyle(.white)

                            VStack(spacing: 4) {
                                HStack {
                                    Text("Hauteur")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(Int(weight * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                                Slider(value: $weight, in: 0...1)
                                    .tint(accentColor)
                            }

                            VStack(spacing: 4) {
                                HStack {
                                    Text("Progression")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(Int(spread * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                                Slider(value: $spread, in: 0...1)
                                    .tint(accentColor)
                            }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        let isGoogleTVTheme = colors.count > 2
                        Button {
                            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                if isGoogleTVTheme {
                                    colors = Self.orangePreset
                                } else {
                                    colors = Self.googleTVPreset
                                }
                                hasCustomizedColors = true
                                weight = 0.5
                                spread = 0.5
                            }
                        } label: {
                            Text("Thème Google TV")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .overlay(alignment: .leading) {
                                    Image(systemName: isGoogleTVTheme ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isGoogleTVTheme ? accentColor : .white.opacity(0.6))
                                        .padding(.leading, 16)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RemoteGlassButtonStyle(prominent: isGoogleTVTheme))

                        Button {
                            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                colors = RemoteViewModel.defaultPreset(for: selectedProvider)
                                weight = 0.5
                                spread = 0.5
                                hasCustomizedColors = false
                            }
                        } label: {
                            Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RemoteGlassButtonStyle())
                    }
                } else {
                    let hasImage = imageData != nil
                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        PhotoPickerLabel(hasImage: hasImage)
                    }
                    .buttonStyle(RemoteGlassButtonStyle(prominent: true))

                    if imageData != nil {
                        Button(role: .destructive) {
                            imageData = nil
                        } label: {
                            Label("Supprimer la photo", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RemoteGlassButtonStyle())
                    }
                }
            }

            Divider()
                .overlay(.white.opacity(0.15))

            Button {
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                    isButtonsExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "square.grid.3x3")
                        .font(.headline)
                    Text("Boutons")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isButtonsExpanded ? 180 : 0))
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isButtonsExpanded {
                let isCircular = buttonShape == .circle
                Button {
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                        buttonShape = isCircular ? .squircle : .circle
                    }
                } label: {
                    Text("Boutons circulaires")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .overlay(alignment: .leading) {
                            Image(systemName: isCircular ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isCircular ? accentColor : .white.opacity(0.6))
                                .padding(.leading, 16)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(RemoteGlassButtonStyle(prominent: isCircular))

                Toggle("Désactiver HDR et étirement", isOn: $disableStretch)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .tint(accentColor)

                VStack(spacing: 4) {
                    HStack {
                        Text("Teinte Liquid Glass")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(tint * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "drop")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        Slider(value: $tint, in: 0...1)
                            .tint(accentColor)
                        Image(systemName: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
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
        .padding(14)
        .staticGlassPanel()
        .onChange(of: photosPickerItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                selectedImageData = data
                showCropSheet = true
            }
        }
        .onChange(of: mode) { _, newMode in
            showPhoto = newMode == .image
        }
        .onAppear {
            mode = showPhoto ? .image : .gradient
        }
        .sheet(isPresented: $showCropSheet) {
            if let data = selectedImageData, let uiImage = UIImage(data: data) {
                CropView(image: uiImage) { cropped in
                    if let jpeg = cropped.jpegData(compressionQuality: 0.95) {
                        imageData = jpeg
                        showPhoto = true
                    }
                    selectedImageData = nil
                    showCropSheet = false
                } onCancel: {
                    selectedImageData = nil
                    showCropSheet = false
                }
            }
        }
    }
}

private struct PhotoPickerLabel: View {
    var hasImage: Bool

    var body: some View {
        Label(hasImage ? String(localized: "Changer la photo") : String(localized: "Choisir une photo"),
              systemImage: "photo.fill")
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
    }
}

private struct CropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size

            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .clipped()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, lastScale * value)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )

                CropGridOverlay(size: screenSize)

                VStack {
                    HStack {
                        Button("Annuler") { onCancel() }
                            .foregroundStyle(.white)
                            .fontWeight(.semibold)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        Button("Utiliser") {
                            if let cropped = cropImage(screenSize: screenSize) {
                                onCrop(cropped)
                            }
                        }
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)

                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }

    private func cropImage(screenSize: CGSize) -> UIImage? {
        // Normalize orientation — draw respects EXIF orientation
        let oriented = UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(at: .zero)
        }

        guard let cgImage = oriented.cgImage else { return nil }

        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let fillScale = max(
            screenSize.width / pixelSize.width,
            screenSize.height / pixelSize.height
        )
        let totalScale = fillScale * scale

        let visiblePixels = CGSize(
            width: screenSize.width / totalScale,
            height: screenSize.height / totalScale
        )
        let origin = CGPoint(
            x: (pixelSize.width - visiblePixels.width) / 2 - offset.width / totalScale,
            y: (pixelSize.height - visiblePixels.height) / 2 - offset.height / totalScale
        )

        let cropRect = CGRect(origin: origin, size: visiblePixels)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

private struct CropGridOverlay: View {
    let size: CGSize

    var body: some View {
        Path { path in
            let w = size.width
            let h = size.height
            path.move(to: CGPoint(x: w / 3, y: 0))
            path.addLine(to: CGPoint(x: w / 3, y: h))
            path.move(to: CGPoint(x: 2 * w / 3, y: 0))
            path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
            path.move(to: CGPoint(x: 0, y: h / 3))
            path.addLine(to: CGPoint(x: w, y: h / 3))
            path.move(to: CGPoint(x: 0, y: 2 * h / 3))
            path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
        }
        .stroke(.white.opacity(0.4), lineWidth: 0.5)
        .allowsHitTesting(false)
    }
}

private struct BackgroundView: View {
    var colors: [Color]
    var imageData: Data?
    var showImage: Bool = true
    var weight: Double = 0.5
    var spread: Double = 0.5

    var body: some View {
        ZStack {
            if showImage, let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if colors.count > 2 {
                let base = colors.first ?? .black
                let bandColors = Array(colors.dropFirst())
                ZStack {
                    base
                    LinearGradient(
                        gradient: Gradient(colors: bandColors),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.55),
                                .init(color: .white.opacity(0.5), location: 0.7),
                                .init(color: .white, location: 0.85),
                                .init(color: .white, location: 1),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            } else {
                let c1 = colors.first ?? .black
                let c2 = colors.last ?? c1
                let s = max(0, weight - (0.01 + spread * 0.49))
                let e = min(1, weight + (0.01 + spread * 0.49))

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: c1, location: 0),
                        .init(color: c1, location: s),
                        .init(color: c2, location: e),
                        .init(color: c2, location: 1),
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(Color.black.opacity(0.06))
            }
        }
        .ignoresSafeArea()
    }
}



private struct VisibleTextField: UIViewRepresentable {
    @Binding var text: String
    var sendText: (String) -> Void
    var onSubmit: () -> Void
    @Binding var isActive: Bool

    func makeUIView(context: Context) -> UITextField {
        let tf = BackspaceReportingTextField()
        tf.delegate = context.coordinator
        tf.returnKeyType = .search
        tf.enablesReturnKeyAutomatically = false
        tf.font = .systemFont(ofSize: 22)
        tf.textColor = .white
        tf.backgroundColor = .clear
        tf.attributedPlaceholder = NSAttributedString(
            string: String(localized: "Saisissez votre texte…"),
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        )
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        tf.leftViewMode = .always
        tf.onDeleteBackward = { context.coordinator.handleBackspace() }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isActive {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: VisibleTextField

        init(parent: VisibleTextField) {
            self.parent = parent
        }

        func handleBackspace() {
            if parent.text.isEmpty {
                parent.sendText("\u{8}")
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let currentText = textField.text ?? ""
            guard let swiftRange = Range(range, in: currentText) else { return true }
            let newText = currentText.replacingCharacters(in: swiftRange, with: string)

            if string.isEmpty, range.length > 0 {
                DispatchQueue.main.async {
                    self.parent.text = newText
                    self.parent.sendText("\u{8}")
                }
            } else if !string.isEmpty {
                DispatchQueue.main.async {
                    self.parent.text = newText
                    self.parent.sendText(string)
                }
            }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

private class BackspaceReportingTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        onDeleteBackward?()
        super.deleteBackward()
    }
}

private struct TintedGlassPanelModifier: ViewModifier {
    @Environment(\.glassTint) var glassTint
    var cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if glassTint > 0 {
                content
                    .background(.black.opacity(glassTint * 0.4), in: .rect(cornerRadius: cornerRadius))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            if glassTint > 0 {
                content
                    .background(.black.opacity(glassTint * 0.4), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 24) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func staticGlassPanel(cornerRadius: CGFloat = 24) -> some View {
        modifier(TintedGlassPanelModifier(cornerRadius: cornerRadius))
    }
}

private struct GlassTintKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

extension EnvironmentValues {
    var glassTint: Double {
        get { self[GlassTintKey.self] }
        set { self[GlassTintKey.self] = newValue }
    }
}

private struct ButtonShapeKey: EnvironmentKey {
    static let defaultValue: ButtonShape = .squircle
}

extension EnvironmentValues {
    var buttonShape: ButtonShape {
        get { self[ButtonShapeKey.self] }
        set { self[ButtonShapeKey.self] = newValue }
    }
}

// MARK: - Onboarding

private struct OnboardingView: View {
    @Binding var provider: String
    var accentColor: Color
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 50)

            Text("Bienvenue sur\nRemoteGlass")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Choisissez votre fournisseur")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 12) {
                    providerButton(
                        name: "Orange",
                        isSelected: provider == "Orange",
                        icon: {
                            (UIImage(named: "orangedecoder").map { Image(uiImage: $0) } ?? Image(systemName: "tv"))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: 70)
                        },
                        action: { provider = "Orange" }
                    )

                providerButton(
                    name: "Google TV",
                    isSelected: provider == "Android TV",
                    icon: {
                        (UIImage(named: "playerpop").map { Image(uiImage: $0) } ?? Image(systemName: "tv"))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 70)
                    },
                    action: { provider = "Android TV" }
                )
            }

            if provider == "Orange" {
                compatibleOrange
            } else {
                compatibleGoogleTV
            }

            Spacer()

            Button(action: onConfirm) {
                Text("Confirmer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(accentColor, in: Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }

    private func providerButton(name: LocalizedStringKey, isSelected: Bool, @ViewBuilder icon: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon()
                Text(name)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 130)
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(RemoteGlassButtonStyle(prominent: isSelected))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: isSelected ? accentColor.opacity(0.45) : .clear, radius: 12, x: 0, y: 0)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isSelected ? accentColor : .clear, lineWidth: 2)
        )
    }

    private var compatibleOrange: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(accentColor)
            Text("Compatible avec tous les décodeurs Orange")
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var compatibleGoogleTV: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compatible avec :")
                .font(.subheadline.weight(.semibold))
            CompatibleRow(colors: [.red], name: "Free", description: "Player Pop et Mini 4K")
            CompatibleRow(colors: [.blue], name: "Bouygues", description: "Bbox Miami, 4K et 4K HDR")
            CompatibleRow(colors: [.red, .green], name: "SFR/RED", description: "Connect TV")
            CompatibleRow(colors: [.white], name: "Autres", description: "Tout appareil Android TV / Google TV")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct CompatibleRow: View {
    let colors: [Color]
    let name: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                        .font(.caption)
                }
            }
            Text(name)
                .font(.caption.weight(.medium))
            Text(description)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

private struct DisableStretchKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var disableStretch: Bool {
        get { self[DisableStretchKey.self] }
        set { self[DisableStretchKey.self] = newValue }
    }
}
