import SwiftUI
import UIKit

struct RemoteLayoutMetrics {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let sectionSpacing: CGFloat
    let controlSpacing: CGFloat
    let buttonSize: CGFloat
    let touchPadHeight: CGFloat
    let usesCompactHeader: Bool
    let pinControlsToBottom: Bool
    /// Clavier ouvert : la rangée du bas est masquée pour laisser la place au trackpad.
    let hidesBottomRow: Bool
    /// Zone large et basse (Duo déplié en portrait, iPad en paysage) : les blocs passent côte à côte.
    let isWide: Bool
    /// Largeur maximale de la télécommande : grandit avec les boutons sur les grands écrans.
    let maxContentWidth: CGFloat

    init(containerSize: CGSize, isCleanMode: Bool, isKeyboardVisible: Bool, hasPowerRow: Bool = false, splitsPowerRowWhenWide: Bool = false) {
        let width = max(containerSize.width, 1)
        let height = max(containerSize.height, 1)

        isWide = width >= 560 && width >= height * 1.15
        horizontalPadding = min(isWide ? 40 : 22, max(12, width * 0.048))
        verticalPadding = height < 600 ? 4 : 10
        usesCompactHeader = height < 640 || isKeyboardVisible
        sectionSpacing = usesCompactHeader ? 4 : 12
        controlSpacing = height < 600 || isKeyboardVisible ? 6 : min(18, max(10, height * 0.018))
        // Keep the surface attached to the keyboard while its safe-area animation
        // is still settling. The height fallback prevents a second jump when the
        // binding flips before GeometryReader receives the expanded height.
        pinControlsToBottom = isKeyboardVisible || (isCleanMode && height < 520)
        let contentWidth = max(1, width - horizontalPadding * 2)
        // Sur iPhone les boutons plafonnent à 62 pt ; les grands écrans en profitent jusqu'à 88 pt.
        let maximumButton = min(88, max(62, min(width, height) * 0.09))
        // Hauteur réelle de l'en-tête (icône + nom + état) ; une marge évite de coller à la tab bar.
        let headerHeight: CGFloat = usesCompactHeader ? 30 : 88
        let bottomBreathingRoom: CGFloat = isKeyboardVisible ? 0 : 12
        let reservedHeight = verticalPadding * 2 + (isWide ? 0 : headerHeight + sectionSpacing) + bottomBreathingRoom
        let availableHeight = height - reservedHeight

        hidesBottomRow = isCleanMode && isKeyboardVisible

        if isCleanMode {
            // Rangées de boutons réellement affichées autour du trackpad
            // (Android TV : power + rangée du haut + rangée du bas).
            let buttonRows = CGFloat((hasPowerRow || (isWide && splitsPowerRowWhenWide) ? 3 : 2) - (hidesBottomRow ? 1 : 0))
            if isWide {
                // Boutons en colonne à gauche (4 de large), trackpad à droite sur toute la hauteur.
                let widthLimitedButton = (contentWidth * 0.42 - 48) / 4
                let heightLimitedButton = (availableHeight - headerHeight - controlSpacing * (buttonRows + 1)) / buttonRows
                buttonSize = min(maximumButton, max(36, min(widthLimitedButton, heightLimitedButton)))
                touchPadHeight = max(96, availableHeight - 8)
            } else {
                let widthLimitedButton = (contentWidth - 84) / 5
                let desiredButton = min(maximumButton, max(40, widthLimitedButton))
                let minimumTouchPadHeight: CGFloat = isKeyboardVisible ? 72 : 96
                let heightLimitedButton = (availableHeight - minimumTouchPadHeight - controlSpacing * buttonRows) / buttonRows
                buttonSize = min(desiredButton, max(36, heightLimitedButton))

                let availableTouchPadHeight = availableHeight - buttonSize * buttonRows - controlSpacing * buttonRows
                let maximumTouchPadHeight = (height < 600 && !isKeyboardVisible ? 330 : 360) * buttonSize / 62
                let outerBreathingRoom: CGFloat = isKeyboardVisible ? 0 : 10
                touchPadHeight = min(
                    maximumTouchPadHeight,
                    max(minimumTouchPadHeight, availableTouchPadHeight - outerBreathingRoom * 2)
                )
            }
        } else if isWide {
            // À gauche : power, VOL / croix / CH (≈ 4 boutons de haut, 5 de large).
            // À droite : navigation + pavé numérique (5 boutons de haut, 3 de large).
            let widthLimitedButton = (contentWidth - 160) / 8
            let heightLimitedButton = (availableHeight - headerHeight - 50) / 5.3
            buttonSize = min(maximumButton, max(36, min(widthLimitedButton, heightLimitedButton)))
            touchPadHeight = 0
        } else {
            // Classic mode contains nine button-heights plus the labels and row gaps.
            // Solving that layout against the live container prevents vertical overlap.
            // The classic surface is five buttons wide once the D-pad and glass chrome
            // paddings are included. Width, not a device name, is the reliable limit.
            let widthLimitedButton = (contentWidth - 84) / 5
            let fixedControlHeight: CGFloat = 60
            let heightLimitedButton = (availableHeight - fixedControlHeight - controlSpacing * 3) / 9
            buttonSize = min(maximumButton, max(36, min(widthLimitedButton, heightLimitedButton)))
            touchPadHeight = 0
        }

        maxContentWidth = isWide ? min(contentWidth, buttonSize * 13 + 200) : 520 * max(1, buttonSize / 62)
    }
}

struct ControlSurface: View {
    var keypad: [[OrangeKey]]
    var buttonSize: CGFloat
    var spacing: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var kind: DeviceKind
    var power: PowerActions
    var toggleClean: () -> Void
    var isWide = false
    var wideHeader: AnyView?
    var sourceMenu: SourceMenu?

    var body: some View {
        if isWide {
            HStack(alignment: .center, spacing: buttonSize * 0.8) {
                VStack(spacing: spacing) {
                    wideHeader
                    mainControls
                }
                    .frame(maxWidth: buttonSize * 5 + 110)
                VStack(spacing: spacing) { numberControls }
                    .fixedSize()
            }
        } else {
            VStack(spacing: spacing) {
                mainControls
                numberControls
            }
        }
    }

    @ViewBuilder
    private var mainControls: some View {
            HStack(spacing: 10) {
                PowerCluster(size: buttonSize, power: power)
                Spacer(minLength: 8)
                if !kind.isTelevision {
                    RemoteButton(systemName: "record.circle", size: buttonSize) { send(.record) }
                } else if kind.supportsInput {
                    SourceButton(size: buttonSize, menu: sourceMenu) { send(.input) }
                }
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

                DirectionPad(buttonSize: buttonSize, send: send, sendDirection: sendDirection, kind: kind)
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
    }

    private var numberControls: some View {
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
            .offset(y: isWide ? 0 : -4)
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

struct CleanControlSurface: View {
    var buttonSize: CGFloat
    var spacing: CGFloat
    var touchPadHeight: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var sendText: (String) -> Void
    var toggleClassic: () -> Void
    var kind: DeviceKind
    var power: PowerActions
    var showsBottomRow: Bool = true
    @Binding var isKeyboardVisible: Bool
    @State private var textFieldText = ""
    @State private var isTextFieldPresented = false

    var isWide = false
    var wideHeader: AnyView?
    var sourceMenu: SourceMenu?
    /// Rangées vides ajoutées au-dessus des boutons pour aligner le trackpad sur l'autre moitié (mode double).
    var paddingRows = 0

    var body: some View {
        Group {
            if isWide {
                // Grand écran large : nom et boutons en colonne à gauche, trackpad à droite.
                HStack(alignment: .center, spacing: spacing * 2) {
                    VStack(spacing: spacing) {
                        wideHeader
                        topControls
                        bottomRow
                    }
                    .frame(width: buttonSize * 4 + 48)
                    touchPad
                }
            } else {
                VStack(spacing: spacing) {
                    if paddingRows > 0 {
                        Color.clear.frame(height: (buttonSize + spacing) * CGFloat(paddingRows) - spacing)
                    }
                    topControls
                    touchPad
                    bottomRow
                }
            }
        }
        .onChange(of: isKeyboardVisible) { _, isActive in
            if isActive {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isTextFieldPresented = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            isKeyboardVisible = false
            withAnimation(.easeInOut(duration: 0.18)) {
                isTextFieldPresented = false
                textFieldText = ""
            }
        }
    }

    @ViewBuilder
    private var topControls: some View {
            if kind.supportsKeyboard {
                powerRow

                if isTextFieldPresented {
                    HStack(spacing: 10) {
                        Button {
                            sendText("\u{1B}")
                            isKeyboardVisible = false
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
                                isKeyboardVisible = false
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
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isTextFieldPresented = true
                            }
                            isKeyboardVisible = true
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
            } else if isWide && power.extra != nil {
                // Colonne de 4 boutons : deux power + volume ne tiennent pas sur une ligne.
                powerRow
                HStack(spacing: 10) {
                    RemoteButton(systemName: "minus", size: buttonSize) { send(.volumeDown) }
                    RemoteButton(systemName: "plus", size: buttonSize) { send(.volumeUp) }
                    RemoteButton(systemName: "speaker.slash.fill", size: buttonSize) { send(.mute) }
                }
            } else {
                HStack(spacing: 10) {
                    PowerCluster(size: buttonSize, power: power)
                    RemoteButton(systemName: "minus", size: buttonSize) { send(.volumeDown) }
                    RemoteButton(systemName: "plus", size: buttonSize) { send(.volumeUp) }
                    RemoteButton(systemName: "speaker.slash.fill", size: buttonSize) { send(.mute) }
                }
            }
    }

    /// Power(s) à gauche, Source à droite, alignés sur la grille de 4 boutons.
    private var powerRow: some View {
        HStack(spacing: 10) {
            PowerCluster(size: buttonSize, power: power)
            if kind.supportsInput {
                Spacer(minLength: 0)
                SourceButton(size: buttonSize, menu: sourceMenu) { send(.input) }
            }
        }
        .frame(width: kind.supportsInput ? buttonSize * 4 + 30 : nil)
    }

    private var touchPad: some View {
            TouchPad(
                buttonSize: buttonSize,
                height: touchPadHeight,
                send: send,
                sendDirection: sendDirection,
                kind: kind
            )
    }

    @ViewBuilder
    private var bottomRow: some View {
            if showsBottomRow {
                HStack(spacing: 10) {
                    RemoteButton(systemName: "arrow.uturn.backward", size: buttonSize) { send(.back) }
                    RemoteButton(systemName: "playpause.fill", size: buttonSize) { send(.playPause) }
                    RemoteButton(systemName: "house.fill", size: buttonSize) { send(.menu) }
                    RemoteButton(systemName: "square.grid.3x3", size: buttonSize) { toggleClassic() }
                }
                .transition(.opacity)
            }
    }
}

struct TouchPad: View {
    var buttonSize: CGFloat
    var height: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var kind: DeviceKind = .orange

    @State private var isActive = false
    @State private var dragTranslation: CGSize = .zero
    @State private var touchTask: Task<Void, Never>?
    @State private var didSendDown = false
    @State private var didLongPress = false

    private let swipeThreshold: CGFloat = 30
    private let swipeDetection: Duration = .milliseconds(80)
    private let longPressDuration: Duration = .milliseconds(800)

    var body: some View {
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
                            if kind.supportsLongPress {
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
                        } else if kind.supportsLongPress {
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

struct DirectionPad: View {
    var buttonSize: CGFloat
    var send: (OrangeKey) -> Void
    var sendDirection: (OrangeKey, Int32) -> Void
    var kind: DeviceKind

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: buttonSize, height: buttonSize)
                RemoteButton(systemName: "chevron.up", size: buttonSize) { send(.up) }
                Color.clear.frame(width: buttonSize, height: buttonSize)
            }
            GridRow {
                RemoteButton(systemName: "chevron.left", size: buttonSize) { send(.left) }
                if kind.supportsLongPress {
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

struct LongPressOkButton: View {
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

/// Boutons power : celui de l'appareil de l'onglet, plus éventuellement celui d'un autre onglet.
/// Menu Source : la liste des entrées fournie par la TV.
struct SourceMenu {
    var sources: [InputSource]
    var currentID: String?
    var load: () -> Void
    var select: (InputSource) -> Void
}

/// Bouton Source : ouvre la liste des entrées quand la TV la donne, sinon envoie la touche Source.
struct SourceButton: View {
    @Environment(\.buttonShape) private var buttonShape
    var size: CGFloat
    var menu: SourceMenu?
    var fallback: () -> Void

    var body: some View {
        Group {
            if let menu, !menu.sources.isEmpty {
                Menu {
                    ForEach(menu.sources) { source in
                        Button {
                            menu.select(source)
                        } label: {
                            if source.id == menu.currentID {
                                Label(source.label, systemImage: "checkmark")
                            } else if !source.isConnected {
                                Text(source.label)
                                Text("Rien de branché")
                            } else {
                                Text(source.label)
                            }
                        }
                    }
                } label: {
                    icon
                }
                .menuStyle(.button)
                .buttonStyle(RemoteGlassButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { menu.load() })
            } else {
                Button(action: fallback) { icon }
                    .buttonStyle(RemoteGlassButtonStyle())
            }
        }
        .accessibilityLabel(Text("Source"))
        .onAppear { menu?.load() }
    }

    private var icon: some View {
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: size * 0.34, weight: .semibold))
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: buttonShape == .circle ? size / 2 : 20, style: .continuous))
    }
}

struct PowerActions {
    var primary: () -> Void
    var primaryBadge: String = ""
    var extra: (() -> Void)?
    var extraBadge: String = ""
}

struct PowerCluster: View {
    var size: CGFloat
    var power: PowerActions

    var body: some View {
        HStack(spacing: 10) {
            RemoteButton(systemName: "power", size: size, tint: .orange, badge: power.extra == nil ? nil : power.primaryBadge, action: power.primary)
            if let extra = power.extra {
                RemoteButton(systemName: "power", size: size, badge: power.extraBadge, action: extra)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
    }
}

struct VerticalPair: View {
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

struct RemoteButton: View {
    @Environment(\.buttonShape) private var buttonShape
    var title: String?
    var systemName: String?
    var size: CGFloat
    var prominent = false
    var tint: Color?
    var badge: String?
    var action: () -> Void

    init(title: String, size: CGFloat, prominent: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemName = nil
        self.size = size
        self.prominent = prominent
        self.tint = tint
        self.action = action
    }

    init(systemName: String, size: CGFloat, prominent: Bool = false, tint: Color? = nil, badge: String? = nil, action: @escaping () -> Void) {
        self.title = nil
        self.systemName = systemName
        self.size = size
        self.prominent = prominent
        self.tint = tint
        self.badge = badge
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
            .overlay(alignment: .bottom) {
                if let badge {
                    Text(badge)
                        .font(.system(size: max(8, size * 0.15), weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.bottom, size * 0.1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
        }
        .buttonStyle(RemoteGlassButtonStyle(prominent: prominent))
        .tint(tint)
        .accessibilityLabel(title ?? systemName ?? String(localized: "Commande"))
    }
}

struct RemoteGlassButtonStyle: ButtonStyle {
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

struct RemoteGlassButtonChrome: ViewModifier {
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

struct PhotoPickerLabel: View {
    var hasImage: Bool

    var body: some View {
        Label(hasImage ? String(localized: "Changer la photo") : String(localized: "Choisir une photo"),
              systemImage: "photo.fill")
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
    }
}

struct WallpaperDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    let targetPixelSize: CGSize
}

struct WallpaperPhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage, CGSize) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: WallpaperPhotoPicker

        init(parent: WallpaperPhotoPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let selectedImage = info[.originalImage] as? UIImage else {
                parent.onCancel()
                return
            }

            parent.onPick(selectedImage, picker.wallpaperPixelSize)
        }
    }
}

struct WallpaperCropView: View {
    let image: UIImage
    let targetPixelSize: CGSize
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1

    private var normalizedImage: UIImage {
        image
    }

    private var targetAspect: CGFloat {
        guard targetPixelSize.width > 0, targetPixelSize.height > 0 else { return 9 / 19.5 }
        return targetPixelSize.width / targetPixelSize.height
    }

    var body: some View {
        GeometryReader { proxy in
            let cropSize = cropSize(in: proxy.size)

            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: normalizedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cropSize.width, height: cropSize.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .clipped()
                    .frame(width: cropSize.width, height: cropSize.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .gesture(dragGesture(cropSize: cropSize))
                    .simultaneousGesture(magnificationGesture(cropSize: cropSize))

                CropGridOverlay(size: cropSize)
                    .frame(width: cropSize.width, height: cropSize.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                VStack {
                    HStack {
                        Button("Annuler") {
                            onCancel()
                        }
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        Button("Utiliser") {
                            if let cropped = cropImage(cropSize: cropSize) {
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
                    .padding(.top, 54)

                    Spacer()
                }
            }
            .onAppear {
                clampOffset(cropSize: cropSize)
            }
            .onChange(of: proxy.size) {
                clampOffset(cropSize: cropSize)
            }
        }
        .ignoresSafeArea()
    }

    private func cropSize(in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }

        let containerAspect = container.width / container.height
        if containerAspect > targetAspect {
            return CGSize(width: container.height * targetAspect, height: container.height)
        }

        return CGSize(width: container.width, height: container.width / targetAspect)
    }

    private func dragGesture(cropSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    ),
                    cropSize: cropSize,
                    scale: scale
                )
            }
            .onEnded { _ in
                offset = clamped(offset, cropSize: cropSize, scale: scale)
                lastOffset = offset
            }
    }

    private func magnificationGesture(cropSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, lastScale * value)
                offset = clamped(offset, cropSize: cropSize, scale: scale)
            }
            .onEnded { _ in
                scale = max(1, scale)
                offset = clamped(offset, cropSize: cropSize, scale: scale)
                lastScale = scale
                lastOffset = offset
            }
    }

    private func clampOffset(cropSize: CGSize) {
        offset = clamped(offset, cropSize: cropSize, scale: scale)
        lastOffset = offset
    }

    private func clamped(_ proposed: CGSize, cropSize: CGSize, scale: CGFloat) -> CGSize {
        let imageSize = normalizedImage.size
        guard imageSize.width > 0, imageSize.height > 0, cropSize.width > 0, cropSize.height > 0 else {
            return .zero
        }

        let baseScale = max(cropSize.width / imageSize.width, cropSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * baseScale * scale, height: imageSize.height * baseScale * scale)
        let maxX = max(0, (displayedSize.width - cropSize.width) / 2)
        let maxY = max(0, (displayedSize.height - cropSize.height) / 2)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func cropImage(cropSize: CGSize) -> UIImage? {
        guard let cgImage = normalizedImage.cgImage else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let baseScale = max(cropSize.width / imageSize.width, cropSize.height / imageSize.height)
        let totalScale = baseScale * scale
        guard totalScale > 0 else { return nil }

        let visiblePixels = CGSize(width: cropSize.width / totalScale, height: cropSize.height / totalScale)
        let clampedOffset = clamped(offset, cropSize: cropSize, scale: scale)
        let cropRect = CGRect(
            x: (imageSize.width - visiblePixels.width) / 2 - clampedOffset.width / totalScale,
            y: (imageSize.height - visiblePixels.height) / 2 - clampedOffset.height / totalScale,
            width: visiblePixels.width,
            height: visiblePixels.height
        )

        return WallpaperImageProcessor.renderWallpaper(from: normalizedImage, cropRect: cropRect, targetPixelSize: targetPixelSize)
    }
}

struct CropGridOverlay: View {
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
        .stroke(.white.opacity(0.38), lineWidth: 0.5)
        .background(Color.clear)
        .overlay {
            Rectangle()
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private extension UIViewController {
    var wallpaperPixelSize: CGSize {
        if let screen = view.window?.windowScene?.screen {
            let nativeBounds = screen.nativeBounds
            if nativeBounds.width > 0, nativeBounds.height > 0 {
                return CGSize(width: min(nativeBounds.width, nativeBounds.height), height: max(nativeBounds.width, nativeBounds.height))
            }

            let bounds = screen.bounds
            let pixelWidth = bounds.width * screen.scale
            let pixelHeight = bounds.height * screen.scale
            return CGSize(width: min(pixelWidth, pixelHeight), height: max(pixelWidth, pixelHeight))
        }

        let fallbackBounds = view.bounds
        let fallbackScale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        let pixelWidth = fallbackBounds.width * fallbackScale
        let pixelHeight = fallbackBounds.height * fallbackScale
        return CGSize(width: min(pixelWidth, pixelHeight), height: max(pixelWidth, pixelHeight))
    }
}

enum WallpaperImageProcessor {
    static func renderWallpaper(from image: UIImage, cropRect: CGRect, targetPixelSize: CGSize) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let safeCropRect = cropRect.integral.intersection(imageBounds)
        guard safeCropRect.width > 0, safeCropRect.height > 0,
              let cropped = cgImage.cropping(to: safeCropRect) else {
            return nil
        }

        let outputSize = CGSize(
            width: max(1, targetPixelSize.width.rounded()),
            height: max(1, targetPixelSize.height.rounded())
        )
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        return UIGraphicsImageRenderer(size: outputSize, format: rendererFormat).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }

    static func normalizedImage(from image: UIImage) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = false

        return UIGraphicsImageRenderer(size: pixelSize, format: rendererFormat).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}

struct VisibleTextField: UIViewRepresentable {
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

class BackspaceReportingTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        onDeleteBackward?()
        super.deleteBackward()
    }
}

struct TintedGlassPanelModifier: ViewModifier {
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

extension View {
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

struct GlassTintKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

extension EnvironmentValues {
    var glassTint: Double {
        get { self[GlassTintKey.self] }
        set { self[GlassTintKey.self] = newValue }
    }
}

struct ButtonShapeKey: EnvironmentKey {
    static let defaultValue: ButtonShape = .squircle
}

extension EnvironmentValues {
    var buttonShape: ButtonShape {
        get { self[ButtonShapeKey.self] }
        set { self[ButtonShapeKey.self] = newValue }
    }
}

struct DisableStretchKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var disableStretch: Bool {
        get { self[DisableStretchKey.self] }
        set { self[DisableStretchKey.self] = newValue }
    }
}
