import SwiftUI
import PhotosUI

struct RemoteView: View {
    @StateObject private var model = RemoteViewModel()
    @State private var selectedTab: AppTab = .remote

    private let keypad: [[OrangeKey]] = [
        [.one, .two, .three],
        [.four, .five, .six],
        [.seven, .eight, .nine],
        [.zero]
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            RemoteTab(
                status: model.status,
                keypad: keypad,
                send: model.send,
                bgColor1: model.bgColor1,
                bgColor2: model.bgColor2,
                bgImageData: model.bgImageData,
                bgWeight: model.bgWeight,
                bgSpread: model.bgSpread
            )
            .tabItem {
                Label(AppTab.remote.rawValue, systemImage: AppTab.remote.systemName)
            }
            .tag(AppTab.remote)

            SettingsTab(
                decoderIP: $model.decoderIP,
                status: model.status,
                isScanning: model.isScanning,
                foundDecoders: model.foundDecoders,
                testAction: model.testConnection,
                scanAction: model.scanLocalNetwork,
                selectAction: { model.decoderIP = $0 },
                bgColor1: $model.bgColor1,
                bgColor2: $model.bgColor2,
                bgImageData: $model.bgImageData,
                bgWeight: $model.bgWeight,
                bgSpread: $model.bgSpread
            )
            .tabItem {
                Label(AppTab.settings.rawValue, systemImage: AppTab.settings.systemName)
            }
            .tag(AppTab.settings)
        }
        .tint(.orange)
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case remote = "Remote"
    case settings = "Settings"

    var id: String { rawValue }

    var systemName: String {
        switch self {
        case .remote: "dot.radiowaves.left.and.right"
        case .settings: "gearshape"
        }
    }

}

private struct HeaderView: View {
    var status: ConnectionStatus

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tv")
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(status.title)
                .font(.headline)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }
}

private struct RemoteTab: View {
    var status: ConnectionStatus
    var keypad: [[OrangeKey]]
    var send: (OrangeKey) -> Void
    var bgColor1: Color
    var bgColor2: Color
    var bgImageData: Data?
    var bgWeight: Double
    var bgSpread: Double

    var body: some View {
        ZStack {
            BackgroundView(color1: bgColor1, color2: bgColor2, imageData: bgImageData, weight: bgWeight, spread: bgSpread)

            GeometryReader { proxy in
                let widthSize = (proxy.size.width - 78) / 5
                let heightSize = (proxy.size.height - 114) / 10.8
                let buttonSize = min(62, max(48, min(widthSize, heightSize)))

                VStack(spacing: 12) {
                    Spacer(minLength: 0)

                    HeaderView(status: status)
                        .offset(y: -10)

                    ControlSurface(
                        keypad: keypad,
                        buttonSize: buttonSize,
                        send: send
                    )

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .offset(y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct SettingsTab: View {
    @Binding var decoderIP: String
    var status: ConnectionStatus
    var isScanning: Bool
    var foundDecoders: [String]
    var testAction: () -> Void
    var scanAction: () -> Void
    var selectAction: (String) -> Void
    @Binding var bgColor1: Color
    @Binding var bgColor2: Color
    @Binding var bgImageData: Data?
    @Binding var bgWeight: Double
    @Binding var bgSpread: Double

    var body: some View {
        ZStack {
            BackgroundView(color1: bgColor1, color2: bgColor2, imageData: bgImageData, weight: bgWeight, spread: bgSpread)

            ScrollView {
                VStack(spacing: 20) {
                    Color.clear
                        .frame(height: 40)
                        .accessibilityHidden(true)

                    HeaderView(status: status)

                    AddressPanel(
                        decoderIP: $decoderIP,
                        isScanning: isScanning,
                        foundDecoders: foundDecoders,
                        testAction: testAction,
                        scanAction: scanAction,
                        selectAction: selectAction
                    )

                    BackgroundSettingsPanel(
                        color1: $bgColor1,
                        color2: $bgColor2,
                        imageData: $bgImageData,
                        weight: $bgWeight,
                        spread: $bgSpread
                    )
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

private struct AddressPanel: View {
    @Binding var decoderIP: String
    @FocusState private var addressFocused: Bool
    var isScanning: Bool
    var foundDecoders: [String]
    var testAction: () -> Void
    var scanAction: () -> Void
    var selectAction: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.headline)
                TextField("IP du décodeur", text: $decoderIP)
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
                    testAction()
                } label: {
                    Label("Tester", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }

                Button {
                    addressFocused = false
                    scanAction()
                } label: {
                    Label(isScanning ? "Connexion" : "Connecter", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .disabled(isScanning)
            }
            .buttonStyle(RemoteGlassButtonStyle(prominent: true))

            if !foundDecoders.isEmpty {
                HStack {
                    ForEach(foundDecoders, id: \.self) { ip in
                        Button(ip) {
                            selectAction(ip)
                            addressFocused = false
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .buttonStyle(RemoteGlassButtonStyle())
            }
        }
    }
}

private struct ControlSurface: View {
    var keypad: [[OrangeKey]]
    var buttonSize: CGFloat
    var send: (OrangeKey) -> Void

    var body: some View {
        VStack(spacing: 14) {
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
                        title: "VOL",
                        buttonSize: buttonSize,
                        topAction: { send(.volumeUp) },
                        bottomAction: { send(.volumeDown) }
                    )
                    RemoteButton(systemName: "speaker.slash.fill", size: buttonSize) { send(.mute) }
                }

                Spacer(minLength: 8)

                DirectionPad(buttonSize: buttonSize, send: send)
                    .padding(.horizontal, 8)
                    .offset(y: -(buttonSize * 0.3))

                Spacer(minLength: 8)

                VStack(spacing: 16) {
                    VerticalPair(
                        topIcon: "chevron.up",
                        bottomIcon: "chevron.down",
                        title: "CH",
                        buttonSize: buttonSize,
                        topAction: { send(.channelUp) },
                        bottomAction: { send(.channelDown) }
                    )
                    RemoteButton(systemName: "playpause.fill", size: buttonSize) { send(.playPause) }
                }
            }

            HStack(spacing: 10) {
                RemoteButton(systemName: "arrow.uturn.backward", size: buttonSize) { send(.back) }
                RemoteButton(systemName: "house.fill", size: buttonSize) { send(.menu) }
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

private struct DirectionPad: View {
    var buttonSize: CGFloat
    var send: (OrangeKey) -> Void

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: buttonSize, height: buttonSize)
                RemoteButton(systemName: "chevron.up", size: buttonSize) { send(.up) }
                Color.clear.frame(width: buttonSize, height: buttonSize)
            }
            GridRow {
                RemoteButton(systemName: "chevron.left", size: buttonSize) { send(.left) }
                RemoteButton(title: "OK", size: buttonSize, prominent: true) { send(.ok) }
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
            .contentShape(.rect)
        }
        .buttonStyle(RemoteGlassButtonStyle(prominent: prominent))
        .tint(tint)
        .accessibilityLabel(title ?? systemName ?? "Commande")
    }
}

private struct RemoteGlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 4)
            .modifier(RemoteGlassButtonChrome(prominent: prominent))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
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
    var prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        } else {
            if prominent {
                content
                    .background(
                        .orange.opacity(0.52),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
            } else {
                content
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
            }
        }
    }
}

private struct BackgroundSettingsPanel: View {
    @Binding var color1: Color
    @Binding var color2: Color
    @Binding var imageData: Data?
    @Binding var weight: Double
    @Binding var spread: Double
    @State private var mode: BackgroundMode = .gradient
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var showCropSheet = false

    private enum BackgroundMode: String, CaseIterable, Identifiable {
        case gradient = "Dégradé"
        case image = "Photo"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "paintpalette.fill")
                    .font(.headline)
                Text("Fond d'écran")
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(.white)

            Picker("Mode", selection: $mode) {
                ForEach(BackgroundMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if mode == .gradient {
                VStack(spacing: 12) {
                    ColorPicker("Couleur 1", selection: $color1, supportsOpacity: false)
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
                            .tint(.orange)
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
                            .tint(.orange)
                    }

                    ColorPicker("Couleur 2", selection: $color2, supportsOpacity: false)
                        .foregroundStyle(.white)
                }
            } else {
                PhotosPicker(selection: $photosPickerItem, matching: .images) {
                    PhotoPickerLabel(hasImage: imageData != nil)
                }
                .buttonStyle(RemoteGlassButtonStyle(prominent: true))

                if imageData != nil {
                    Button(role: .destructive) {
                        imageData = nil
                    } label: {
                        Label("Supprimer la photo", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RemoteGlassButtonStyle())
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
        .sheet(isPresented: $showCropSheet) {
            if let data = selectedImageData, let uiImage = UIImage(data: data) {
                CropView(image: uiImage) { cropped in
                    if let jpeg = cropped.jpegData(compressionQuality: 0.95) {
                        imageData = jpeg
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
        Label(hasImage ? "Changer la photo" : "Choisir une photo",
              systemImage: "photo.fill")
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
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
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
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
    var color1: Color
    var color2: Color
    var imageData: Data?
    var weight: Double = 0.5
    var spread: Double = 0.5

    var body: some View {
        ZStack {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                let s = max(0, weight - (0.01 + spread * 0.49))
                let e = min(1, weight + (0.01 + spread * 0.49))

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: color1, location: 0),
                        .init(color: color1, location: s),
                        .init(color: color2, location: e),
                        .init(color: color2, location: 1),
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
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
