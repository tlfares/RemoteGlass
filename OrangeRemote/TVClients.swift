import Foundation
import Network
import os

// MARK: - WebSocket local (certificats auto-signés des TV acceptés)

/// Les TV exposent du wss:// avec un certificat auto-signé : on ne l'accepte que pour des adresses du réseau local.
final class LocalNetworkTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = LocalNetworkTrustDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              Self.isPrivateHost(challenge.protectionSpace.host) else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }

    static func isPrivateHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return host.hasSuffix(".local") }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, let b) where (16...31).contains(b): return true
        default: return false
        }
    }
}

let localNetworkSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 4
    config.httpMaximumConnectionsPerHost = 4
    config.waitsForConnectivity = false
    return URLSession(configuration: config, delegate: LocalNetworkTrustDelegate.shared, delegateQueue: nil)
}()

/// Petit wrapper async autour de URLSessionWebSocketTask.
final class LocalWebSocket: @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let lock = OSAllocatedUnfairLock()
    private var _isOpen = true

    var isOpen: Bool {
        lock.withLock { _isOpen && task.state == .running }
    }

    init(url: URL, protocols: [String] = []) {
        task = protocols.isEmpty
            ? localNetworkSession.webSocketTask(with: url)
            : localNetworkSession.webSocketTask(with: url, protocols: protocols)
        task.maximumMessageSize = 4 * 1024 * 1024
        task.resume()
    }

    func send(_ text: String) async throws {
        do {
            try await task.send(.string(text))
        } catch {
            close()
            throw error
        }
    }

    func receive() async throws -> String {
        do {
            switch try await task.receive() {
            case .string(let text): return text
            case .data(let data): return String(decoding: data, as: UTF8.self)
            @unknown default: return ""
            }
        } catch {
            close()
            throw error
        }
    }

    func receive(timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RemoteControllerError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw RemoteControllerError.timedOut }
            return first
        }
    }

    /// Ping WebSocket : confirme que la poignée de main a abouti.
    func sendPing(timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.task.sendPing { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RemoteControllerError.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    func close() {
        lock.withLock { _isOpen = false }
        task.cancel(with: .goingAway, reason: nil)
    }
}

private func jsonString(_ object: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

/// Dictionnaire JSON immuable transmis entre tâches.
struct JSONPayload: @unchecked Sendable {
    let value: [String: Any]
}

private func jsonObject(_ text: String) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
}

// MARK: - Wake-on-LAN

enum WakeOnLAN {
    /// Envoie le « magic packet ». Note : la diffusion broadcast nécessite l'entitlement
    /// com.apple.developer.networking.multicast pour une app publiée ; on tente aussi en unicast.
    static func wake(mac: String, lastKnownIP: String?) async {
        let hex = mac.filter(\.isHexDigit)
        guard hex.count == 12 else { return }
        var macBytes: [UInt8] = []
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            macBytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: macBytes) }

        var targets = ["255.255.255.255"]
        if let ip = lastKnownIP {
            let parts = ip.split(separator: ".")
            if parts.count == 4 { targets.append(parts.prefix(3).joined(separator: ".") + ".255") }
            targets.append(ip)
        }
        for target in targets {
            for port: UInt16 in [9, 7] {
                await sendUDP(packet, host: target, port: port)
            }
        }
    }

    private static func sendUDP(_ data: Data, host: String, port: UInt16) async {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable () -> Void = {
                let shouldResume = done.withLock { state -> Bool in
                    if state { return false }
                    state = true
                    return true
                }
                if shouldResume {
                    connection.cancel()
                    continuation.resume()
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { _ in finish() })
                case .failed, .cancelled:
                    finish()
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { finish() }
        }
    }
}

// MARK: - LG webOS (SSAP)

final class LGWebOSClient: RemoteController, @unchecked Sendable {
    let host: String
    private let lock = OSAllocatedUnfairLock()
    private var clientKey: String?
    private var mac: String?
    private var socket: LocalWebSocket?
    private var pointer: LocalWebSocket?
    private var pending: [String: CheckedContinuation<JSONPayload, Error>] = [:]
    private var counter = 0
    private var receiveTask: Task<Void, Never>?
    private var isPlaying = true
    /// Abonnement à l'app au premier plan : la TV renvoie une réponse à chaque changement.
    private var foregroundSubscriptionID: String?
    private var foregroundObserver: (@Sendable (String) -> Void)?

    /// Appelé quand la TV délivre une nouvelle client-key (première connexion acceptée).
    var onCredentials: (@Sendable (_ clientKey: String?, _ mac: String?) -> Void)?

    init(host: String, clientKey: String?, mac: String?) {
        self.host = host
        self.clientKey = clientKey
        self.mac = mac
    }

    // MARK: RemoteController

    func send(_ key: OrangeKey, direction: Int32) async throws {
        // LG n'a pas d'appui long via le socket pointeur : on n'envoie qu'au relâchement / tap.
        guard direction != 1 else { return }
        switch key {
        case .power:
            try await togglePower()
        case .playPause:
            let playing = lock.withLock { () -> Bool in isPlaying.toggle(); return isPlaying }
            try await request(playing ? "ssap://media.controls/play" : "ssap://media.controls/pause")
        case .input:
            // Sélecteur d'entrées natif (TV récentes) ; l'app propose sinon son propre menu Source.
            try await request("ssap://system.launcher/launch", payload: ["id": "com.webos.app.inputpicker"])
        default:
            guard let name = Self.buttonName(for: key) else { throw RemoteControllerError.unsupportedKey }
            try await sendButton(name)
        }
    }

    func sendText(_ text: String) async throws {
        switch text {
        case "\u{8}":
            try await request("ssap://com.webos.service.ime/deleteCharacters", payload: ["count": 1])
        case "\n":
            try await request("ssap://com.webos.service.ime/sendEnterKey")
        case "\u{1B}":
            break
        default:
            try await request("ssap://com.webos.service.ime/insertText", payload: ["text": text, "replace": 0])
        }
    }

    func togglePower() async throws {
        do {
            _ = try await ensureRegistered(timeout: 3)
            let state = try? await request("ssap://com.webos.service.tvpower/power/getPowerState")
            let power = state?["state"] as? String ?? "Active"
            if power == "Active" {
                try await request("ssap://system/turnOff")
            } else {
                // Veille active (Quick Start+) : on rallume l'écran.
                try await request("ssap://com.webos.service.tvpower/power/turnOnScreen")
            }
        } catch {
            guard let mac = lock.withLock({ mac }) else { throw error }
            await WakeOnLAN.wake(mac: mac, lastKnownIP: host)
        }
    }

    func ping() async -> Bool {
        (try? await ensureRegistered(timeout: 4)) != nil
    }

    /// Première connexion : laisse le temps d'accepter la demande sur la TV.
    func pair() async throws {
        _ = try await ensureRegistered(timeout: 60)
    }

    func disconnect() {
        receiveTask?.cancel()
        let (s, p, waiting) = lock.withLock { () -> (LocalWebSocket?, LocalWebSocket?, [CheckedContinuation<JSONPayload, Error>]) in
            let waiting = Array(pending.values)
            pending = [:]
            // La connexion tombe : les abonnements aussi. Le prochain appel les recrée.
            foregroundSubscriptionID = nil
            defer { socket = nil; pointer = nil }
            return (socket, pointer, waiting)
        }
        s?.close()
        p?.close()
        waiting.forEach { $0.resume(throwing: RemoteControllerError.notConnected) }
    }

    // MARK: Connexion

    private func ensureRegistered(timeout: TimeInterval) async throws -> LocalWebSocket {
        if let existing = lock.withLock({ socket }), existing.isOpen { return existing }
        disconnect()

        var lastError: Error = RemoteControllerError.notConnected
        // Les firmwares récents n'acceptent que wss:3001, les anciens ws:3000.
        for url in ["wss://\(host):3001/", "ws://\(host):3000/"].compactMap(URL.init(string:)) {
            let ws = LocalWebSocket(url: url)
            do {
                try await register(on: ws, timeout: timeout)
                lock.withLock { socket = ws }
                startReceiving(ws)
                Task { await self.fetchMACIfNeeded() }
                return ws
            } catch RemoteControllerError.unauthorized {
                ws.close()
                throw RemoteControllerError.unauthorized
            } catch {
                ws.close()
                lastError = error
            }
        }
        throw lastError
    }

    private func register(on ws: LocalWebSocket, timeout: TimeInterval) async throws {
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": Self.manifest,
        ]
        if let key = lock.withLock({ clientKey }) { payload["client-key"] = key }
        try await ws.send(jsonString(["type": "register", "id": "register_0", "payload": payload]))

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let message = try await ws.receive(timeout: max(0.5, deadline.timeIntervalSinceNow))
            guard let json = jsonObject(message) else { continue }
            let type = json["type"] as? String
            if type == "registered" {
                let key = (json["payload"] as? [String: Any])?["client-key"] as? String
                if let key {
                    lock.withLock { clientKey = key }
                    onCredentials?(key, nil)
                }
                return
            }
            if type == "error" {
                throw RemoteControllerError.unauthorized
            }
            // type == "response" avec pairingType PROMPT : la TV affiche la demande, on attend.
        }
        throw RemoteControllerError.timedOut
    }

    private func startReceiving(_ ws: LocalWebSocket) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let message = try? await ws.receive() else { break }
                guard let self, let json = jsonObject(message), let id = json["id"] as? String else { continue }
                let observer = self.lock.withLock { id == self.foregroundSubscriptionID ? self.foregroundObserver : nil }
                if let observer {
                    if let appID = (json["payload"] as? [String: Any])?["appId"] as? String, !appID.isEmpty { observer(appID) }
                    continue
                }
                let continuation = self.lock.withLock { self.pending.removeValue(forKey: id) }
                if json["type"] as? String == "error" {
                    continuation?.resume(throwing: RemoteControllerError.unsupportedKey)
                } else {
                    continuation?.resume(returning: JSONPayload(value: json["payload"] as? [String: Any] ?? [:]))
                }
            }
            self?.disconnect()
        }
    }

    @discardableResult
    private func request(_ uri: String, payload: [String: Any]? = nil) async throws -> [String: Any] {
        let ws = try await ensureRegistered(timeout: 4)
        let id = lock.withLock { () -> String in counter += 1; return "req_\(counter)" }
        var message: [String: Any] = ["type": "request", "id": id, "uri": uri]
        if let payload { message["payload"] = payload }
        let text = jsonString(message)

        let result = try await withThrowingTaskGroup(of: JSONPayload.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.lock.withLock { self.pending[id] = continuation }
                    Task {
                        do { try await ws.send(text) } catch {
                            let c = self.lock.withLock { self.pending.removeValue(forKey: id) }
                            c?.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                let c = self.lock.withLock { self.pending.removeValue(forKey: id) }
                c?.resume(throwing: RemoteControllerError.timedOut)
                throw RemoteControllerError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next() ?? JSONPayload(value: [:])
        }
        return result.value
    }

    // MARK: Entrées (menu Source)

    private static let liveTVID = "LIVE_TV"

    func inputSources() async throws -> (sources: [InputSource], currentID: String?) {
        let list = try await request("ssap://tv/getExternalInputList")
        var sources = [InputSource(id: Self.liveTVID, label: String(localized: "TV"), appID: "com.webos.app.livetv")]
        for device in list["devices"] as? [[String: Any]] ?? [] {
            guard let id = device["id"] as? String else { continue }
            sources.append(InputSource(
                id: id,
                label: device["label"] as? String ?? id,
                appID: device["appId"] as? String,
                isConnected: device["connected"] as? Bool ?? true
            ))
        }
        let foreground = (try? await request("ssap://com.webos.applicationManager/getForegroundAppInfo"))?["appId"] as? String
        let current = sources.first { $0.appID != nil && $0.appID == foreground }?.id
        return (sources, current)
    }

    func setVolume(_ level: Int) async throws {
        try await request("ssap://audio/setVolume", payload: ["volume": max(0, min(100, level))])
    }

    func volume() async throws -> Int {
        let payload = try await request("ssap://audio/getVolume")
        // webOS récents : { volumeStatus: { volume } } ; anciens : { volume }.
        if let level = (payload["volumeStatus"] as? [String: Any])?["volume"] as? Int ?? payload["volume"] as? Int { return level }
        throw RemoteControllerError.unsupportedKey
    }

    func observeForegroundApp(_ onChange: @escaping @Sendable (String) -> Void) async throws {
        let ws = try await ensureRegistered(timeout: 4)
        let id = lock.withLock { () -> String? in
            foregroundObserver = onChange
            guard foregroundSubscriptionID == nil else { return nil }
            counter += 1
            foregroundSubscriptionID = "sub_\(counter)"
            return foregroundSubscriptionID
        }
        guard let id else { return }
        do {
            try await ws.send(jsonString([
                "type": "subscribe", "id": id,
                "uri": "ssap://com.webos.applicationManager/getForegroundAppInfo",
            ]))
        } catch {
            lock.withLock { foregroundSubscriptionID = nil }
            throw error
        }
    }

    func selectInput(_ source: InputSource) async throws {
        if source.id == Self.liveTVID {
            try await request("ssap://system.launcher/launch", payload: ["id": "com.webos.app.livetv"])
        } else {
            try await request("ssap://tv/switchInput", payload: ["inputId": source.id])
        }
    }

    private func sendButton(_ name: String) async throws {
        let socket = try await ensurePointer()
        do {
            try await socket.send("type:button\nname:\(name)\n\n")
        } catch {
            lock.withLock { pointer = nil }
            try await ensurePointer().send("type:button\nname:\(name)\n\n")
        }
    }

    private func ensurePointer() async throws -> LocalWebSocket {
        if let existing = lock.withLock({ pointer }), existing.isOpen { return existing }
        let payload = try await request("ssap://com.webos.service.networkinput/getPointerInputSocket")
        guard let path = payload["socketPath"] as? String, let url = URL(string: path) else {
            throw RemoteControllerError.notConnected
        }
        let ws = LocalWebSocket(url: url)
        lock.withLock { pointer = ws }
        return ws
    }

    private func fetchMACIfNeeded() async {
        guard lock.withLock({ mac }) == nil else { return }
        guard let info = try? await request("ssap://com.webos.service.update/getCurrentSWInformation"),
              let deviceID = info["device_id"] as? String,
              deviceID.filter(\.isHexDigit).count == 12 else { return }
        let formatted = deviceID.uppercased()
        lock.withLock { mac = formatted }
        onCredentials?(nil, formatted)
    }

    private static func buttonName(for key: OrangeKey) -> String? {
        switch key {
        case .up: "UP"
        case .down: "DOWN"
        case .left: "LEFT"
        case .right: "RIGHT"
        case .ok, .enter: "ENTER"
        case .back: "BACK"
        case .menu: "HOME"
        case .volumeUp: "VOLUMEUP"
        case .volumeDown: "VOLUMEDOWN"
        case .mute: "MUTE"
        case .channelUp: "CHANNELUP"
        case .channelDown: "CHANNELDOWN"
        case .record: "RECORD"
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
        case .power, .playPause, .input, .keyboard: nil
        }
    }

    /// Manifeste public de l'app « LG Remote » utilisé par les clients SSAP open source.
    nonisolated(unsafe) private static let manifest: [String: Any] = [
        "manifestVersion": 1,
        "appVersion": "1.1",
        "signed": [
            "created": "20140509",
            "appId": "com.lge.test",
            "vendorId": "com.lge",
            "localizedAppNames": ["": "LG Remote App", "ko-KR": "리모컨 앱", "zxx-XX": "ЛГ Rэмotэ AПП"],
            "localizedVendorNames": ["": "LG Electronics"],
            "permissions": [
                "TEST_SECURE", "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD", "READ_INSTALLED_APPS",
                "READ_LGE_SDX", "READ_NOTIFICATIONS", "SEARCH", "WRITE_SETTINGS", "WRITE_NOTIFICATION_ALERT",
                "CONTROL_POWER", "READ_CURRENT_CHANNEL", "READ_RUNNING_APPS", "READ_UPDATE_INFO",
                "UPDATE_FROM_REMOTE_APP", "READ_LGE_TV_INPUT_EVENTS", "READ_TV_CURRENT_TIME",
            ],
            "serial": "2f930e2d2cfe083771f68e4fe7bb07",
        ] as [String: Any],
        "permissions": [
            "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE", "TEST_OPEN", "TEST_PROTECTED", "CONTROL_AUDIO",
            "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK", "CONTROL_INPUT_MEDIA_RECORDING",
            "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV", "CONTROL_POWER", "READ_APP_STATUS",
            "READ_CURRENT_CHANNEL", "READ_INPUT_DEVICE_LIST", "READ_NETWORK_STATE", "READ_RUNNING_APPS",
            "READ_TV_CHANNEL_LIST", "WRITE_NOTIFICATION_TOAST", "READ_POWER_STATE", "READ_COUNTRY_INFO",
            "READ_SETTINGS", "CONTROL_TV_SCREEN", "CONTROL_TV_STANBY", "CONTROL_FAVORITE_GROUP",
            "CONTROL_USER_INFO", "CHECK_BLUETOOTH_DEVICE", "CONTROL_BLUETOOTH", "CONTROL_TIMER_INFO",
            "STB_INTERNAL_CONNECTION", "CONTROL_RECORDING", "READ_RECORDING_STATE", "WRITE_RECORDING_LIST",
            "READ_RECORDING_LIST", "READ_RECORDING_SCHEDULE", "WRITE_RECORDING_SCHEDULE",
            "READ_STORAGE_DEVICE_LIST", "READ_TV_PROGRAM_INFO", "CONTROL_BOX_CHANNEL",
            "READ_TV_ACR_AUTH_TOKEN", "READ_TV_CONTENT_STATE", "READ_TV_CURRENT_TIME",
            "ADD_LAUNCHER_CHANNEL", "SET_CHANNEL_SKIP", "RELEASE_CHANNEL_SKIP", "CONTROL_CHANNEL_BLOCK",
            "DELETE_SELECT_CHANNEL", "CONTROL_CHANNEL_GROUP", "SCAN_TV_CHANNELS", "CONTROL_TV_POWER",
            "CONTROL_WOL",
        ],
        "signatures": [
            [
                "signatureVersion": 1,
                "signature": "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw==",
            ] as [String: Any],
        ],
    ]
}

// MARK: - Samsung Tizen

final class SamsungTVClient: RemoteController, @unchecked Sendable {
    let host: String
    private let lock = OSAllocatedUnfairLock()
    private var token: String?
    private let mac: String?
    private var socket: LocalWebSocket?
    private var drainTask: Task<Void, Never>?

    var onToken: (@Sendable (String) -> Void)?

    init(host: String, token: String?, mac: String?) {
        self.host = host
        self.token = token
        self.mac = mac
    }

    func send(_ key: OrangeKey, direction: Int32) async throws {
        if key == .power {
            guard direction != 1 else { return }
            try await togglePower()
            return
        }
        guard let code = Self.keyCode(for: key) else { throw RemoteControllerError.unsupportedKey }
        let command = switch direction {
        case 1: "Press"
        case 2: "Release"
        default: "Click"
        }
        try await sendKey(code, command: command)
    }

    func sendText(_ text: String) async throws {
        switch text {
        case "\u{8}":
            try await sendKey("KEY_BACKSPACE", command: "Click")
        case "\n":
            try await sendJSON(["method": "ms.remote.control", "params": ["TypeOfRemote": "SendInputEnd"]])
        case "\u{1B}":
            break
        default:
            let encoded = Data(text.utf8).base64EncodedString()
            try await sendJSON([
                "method": "ms.remote.control",
                "params": ["Cmd": encoded, "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"],
            ])
        }
    }

    func togglePower() async throws {
        do {
            _ = try await ensureConnected(timeout: 3)
            try await sendKey("KEY_POWER", command: "Click")
        } catch {
            guard let mac else { throw error }
            await WakeOnLAN.wake(mac: mac, lastKnownIP: host)
        }
    }

    func ping() async -> Bool {
        (try? await ensureConnected(timeout: 4)) != nil
    }

    func pair() async throws {
        _ = try await ensureConnected(timeout: 45)
    }

    func disconnect() {
        drainTask?.cancel()
        let s = lock.withLock { () -> LocalWebSocket? in defer { socket = nil }; return socket }
        s?.close()
    }

    private func sendKey(_ code: String, command: String) async throws {
        try await sendJSON([
            "method": "ms.remote.control",
            "params": ["Cmd": command, "DataOfCmd": code, "Option": "false", "TypeOfRemote": "SendRemoteKey"],
        ])
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        let text = jsonString(object)
        do {
            try await ensureConnected(timeout: 4).send(text)
        } catch {
            disconnect()
            try await ensureConnected(timeout: 4).send(text)
        }
    }

    private func ensureConnected(timeout: TimeInterval) async throws -> LocalWebSocket {
        if let existing = lock.withLock({ socket }), existing.isOpen { return existing }
        disconnect()

        let name = Data("RemoteGlass".utf8).base64EncodedString()
        var urls: [String] = []
        var secure = "wss://\(host):8002/api/v2/channels/samsung.remote.control?name=\(name)"
        if let token = lock.withLock({ token }) { secure += "&token=\(token)" }
        urls.append(secure)
        urls.append("ws://\(host):8001/api/v2/channels/samsung.remote.control?name=\(name)")

        var lastError: Error = RemoteControllerError.notConnected
        for url in urls.compactMap(URL.init(string:)) {
            let ws = LocalWebSocket(url: url)
            do {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    let message = try await ws.receive(timeout: max(0.5, deadline.timeIntervalSinceNow))
                    guard let json = jsonObject(message) else { continue }
                    let event = json["event"] as? String
                    if event == "ms.channel.connect" {
                        if let newToken = (json["data"] as? [String: Any])?["token"] as? String {
                            lock.withLock { token = newToken }
                            onToken?(newToken)
                        }
                        lock.withLock { socket = ws }
                        startDraining(ws)
                        return ws
                    }
                    if event == "ms.channel.unauthorized" || event == "ms.channel.timeOut" {
                        throw RemoteControllerError.unauthorized
                    }
                }
                throw RemoteControllerError.timedOut
            } catch RemoteControllerError.unauthorized {
                ws.close()
                throw RemoteControllerError.unauthorized
            } catch {
                ws.close()
                lastError = error
            }
        }
        throw lastError
    }

    /// Vide les messages entrants pour garder le socket vivant et détecter sa fermeture.
    private func startDraining(_ ws: LocalWebSocket) {
        drainTask?.cancel()
        drainTask = Task {
            while !Task.isCancelled {
                guard (try? await ws.receive()) != nil else { break }
            }
        }
    }

    private static func keyCode(for key: OrangeKey) -> String? {
        switch key {
        case .up: "KEY_UP"
        case .down: "KEY_DOWN"
        case .left: "KEY_LEFT"
        case .right: "KEY_RIGHT"
        case .ok, .enter: "KEY_ENTER"
        case .back: "KEY_RETURN"
        case .menu: "KEY_HOME"
        case .volumeUp: "KEY_VOLUP"
        case .volumeDown: "KEY_VOLDOWN"
        case .mute: "KEY_MUTE"
        case .channelUp: "KEY_CHUP"
        case .channelDown: "KEY_CHDOWN"
        case .playPause: "KEY_PLAY_BACK"
        case .record: "KEY_REC"
        case .input: "KEY_SOURCE"
        case .zero: "KEY_0"
        case .one: "KEY_1"
        case .two: "KEY_2"
        case .three: "KEY_3"
        case .four: "KEY_4"
        case .five: "KEY_5"
        case .six: "KEY_6"
        case .seven: "KEY_7"
        case .eight: "KEY_8"
        case .nine: "KEY_9"
        case .power: "KEY_POWER"
        case .keyboard: nil
        }
    }
}

// MARK: - Roku (External Control Protocol)

final class RokuClient: RemoteController, @unchecked Sendable {
    let host: String

    init(host: String) { self.host = host }

    func send(_ key: OrangeKey, direction: Int32) async throws {
        guard let name = Self.keyName(for: key) else { throw RemoteControllerError.unsupportedKey }
        let action = switch direction {
        case 1: "keydown"
        case 2: "keyup"
        default: "keypress"
        }
        try await post("/\(action)/\(name)")
    }

    func sendText(_ text: String) async throws {
        switch text {
        case "\u{8}": try await post("/keypress/Backspace")
        case "\n": try await post("/keypress/Enter")
        case "\u{1B}": break
        default:
            for character in text {
                let encoded = String(character).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                try await post("/keypress/Lit_\(encoded)")
            }
        }
    }

    func ping() async -> Bool {
        await RokuClient.deviceInfo(ip: host, timeout: 2) != nil
    }

    func disconnect() {}

    /// Les Roku TV exposent leurs entrées comme des « apps » de type tvin (tvinput.hdmi1, tvinput.dtv…),
    /// avec le nom choisi par l'utilisateur sur la TV. Les box et clés Roku n'en ont pas.
    func inputSources() async throws -> (sources: [InputSource], currentID: String?) {
        let apps = Self.apps(in: try await get("/query/apps"))
        let sources = apps.filter { $0.type == "tvin" }.map { app in
            InputSource(id: app.id, label: app.name.isEmpty ? Self.fallbackLabel(for: app.id) : app.name, appID: app.id, isConnected: true)
        }
        guard !sources.isEmpty else { throw RemoteControllerError.unsupportedKey }
        let current = Self.apps(in: (try? await get("/query/active-app")) ?? "").first?.id
        return (sources, current)
    }

    func selectInput(_ source: InputSource) async throws {
        let id = source.appID ?? source.id
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw URLError(.badURL) }
        try await post("/launch/\(encoded)")
    }

    private func get(_ path: String) async throws -> String {
        guard let url = URL(string: "http://\(host):8060\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let (data, _) = try await localNetworkSession.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }

    /// `<app id="tvinput.hdmi1" type="tvin" version="1.0.0">Console</app>`
    private static func apps(in xml: String) -> [(id: String, type: String, name: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"<app\s+([^>]*?)/?>(?:([^<]*)</app>)?"#) else { return [] }
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let attributes = ns.substring(with: match.range(at: 1))
            func attribute(_ name: String) -> String? {
                guard let range = attributes.range(of: #"\#(name)="([^"]*)""#, options: .regularExpression) else { return nil }
                return String(attributes[range].dropFirst(name.count + 2).dropLast())
            }
            guard let id = attribute("id") else { return nil }
            let name = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
            return (id, attribute("type") ?? "", Self.unescape(name).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func fallbackLabel(for id: String) -> String {
        let suffix = id.replacingOccurrences(of: "tvinput.", with: "")
        if suffix == "dtv" { return String(localized: "TV") }
        return suffix.uppercased()
    }

    private func post(_ path: String) async throws {
        guard let url = URL(string: "http://\(host):8060\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        let (_, response) = try await localNetworkSession.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw RemoteControllerError.unauthorized
        }
    }

    struct DeviceInfo: Sendable {
        var name: String?
        var mac: String?
    }

    static func deviceInfo(ip: String, timeout: TimeInterval) async -> DeviceInfo? {
        guard let url = URL(string: "http://\(ip):8060/query/device-info") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await localNetworkSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let xml = String(decoding: data, as: UTF8.self)
        guard xml.contains("<device-info") else { return nil }
        func tag(_ name: String) -> String? {
            guard let start = xml.range(of: "<\(name)>"), let end = xml.range(of: "</\(name)>", range: start.upperBound..<xml.endIndex) else { return nil }
            let value = String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return DeviceInfo(
            name: tag("user-device-name") ?? tag("friendly-device-name") ?? tag("model-name"),
            mac: tag("wifi-mac") ?? tag("ethernet-mac")
        )
    }

    private static func keyName(for key: OrangeKey) -> String? {
        switch key {
        case .power: "Power"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .ok: "Select"
        case .enter: "Enter"
        case .back: "Back"
        case .menu: "Home"
        case .playPause: "Play"
        case .volumeUp: "VolumeUp"
        case .volumeDown: "VolumeDown"
        case .mute: "VolumeMute"
        case .channelUp: "ChannelUp"
        case .channelDown: "ChannelDown"
        case .record: "InstantReplay"
        case .input: "InputTuner"
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine:
            "Lit_\(key.digit)"
        case .keyboard: nil
        }
    }
}

extension OrangeKey {
    var digit: String {
        switch self {
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

// MARK: - Hisense / Toshiba VIDAA (MQTT local)

enum HisenseError: LocalizedError {
    case rejected

    var errorDescription: String? {
        String(localized: "Ce modèle Hisense n'autorise pas les télécommandes tierces (il exige un certificat propriétaire). Si ta TV tourne sous Google TV, ajoute-la plutôt en mode Google TV.")
    }
}

struct HisenseMessage: Sendable {
    let topic: String
    let payload: Data
}

/// Les TV VIDAA embarquent un broker MQTT sur le port 36669 (TLS auto-signé sur les modèles récents,
/// en clair sur les plus anciens). Certains firmwares récents exigent un certificat client propriétaire :
/// dans ce cas la connexion est refusée et on l'explique clairement.
final class HisenseVIDAAClient: RemoteController, @unchecked Sendable {
    static let port: UInt16 = 36669

    let host: String
    let clientID: String
    private let mac: String?
    private let queue = DispatchQueue(label: "remoteglass.hisense")
    private let connectLock = OSAllocatedUnfairLock<Task<Void, Error>?>(initialState: nil)

    // Accédés uniquement sur `queue`.
    private var connection: NWConnection?
    private var buffer: [UInt8] = []
    private var connected = false
    private var sawTLSFailure = false
    private var connackWaiter: CheckedContinuation<Void, Error>?
    private var waiters: [UUID: (match: (String) -> Bool, continuation: CheckedContinuation<HisenseMessage, Error>)] = [:]
    private var pingTimer: DispatchSourceTimer?
    private var packetID: UInt16 = 1

    init(host: String, clientID: String?, mac: String?) {
        self.host = host
        self.clientID = clientID ?? "RemoteGlass-" + UUID().uuidString.prefix(8)
        self.mac = mac
    }

    // MARK: RemoteController

    func send(_ key: OrangeKey, direction: Int32) async throws {
        guard direction != 2 else { return }
        if key == .power {
            try await togglePower()
            return
        }
        guard let name = Self.keyName(for: key) else { throw RemoteControllerError.unsupportedKey }
        try await publish(service: "remote_service", action: "sendkey", payload: name)
    }

    func togglePower() async throws {
        do {
            try await ensureConnected(timeout: 3)
            try await publish(service: "remote_service", action: "sendkey", payload: "KEY_POWER")
        } catch {
            guard let mac else { throw error }
            await WakeOnLAN.wake(mac: mac, lastKnownIP: host)
        }
    }

    func ping() async -> Bool {
        (try? await ensureConnected(timeout: 3)) != nil
    }

    func disconnect() {
        queue.async {
            if let connection = self.connection, self.connected {
                connection.send(content: Data([0xE0, 0x00]), completion: .idempotent)
            }
            self.teardown(error: RemoteControllerError.notConnected)
        }
    }

    // MARK: Appairage

    /// Renvoie true si la TV affiche un code à 4 chiffres à saisir.
    func startPairing() async throws -> Bool {
        try await ensureConnected(timeout: 8)
        try await publish(
            service: "ui_service", action: "vidaa_app_connect",
            payload: #"{"app_version":2,"connect_result":0,"device_type":"Mobile App"}"#
        )
        do {
            let message = try await request(service: "ui_service", action: "gettvstate", payload: "", timeout: 6) { topic in
                topic.hasSuffix("/authentication") || topic.hasSuffix("/state")
            }
            return message.topic.hasSuffix("/authentication")
        } catch RemoteControllerError.timedOut {
            // Connexion acceptée mais pas de réponse : les anciens firmwares n'ont pas d'étape de code.
            return false
        }
    }

    func confirm(code: String) async throws {
        let digits = code.filter(\.isNumber)
        let message = try await request(
            service: "ui_service", action: "authenticationcode",
            payload: #"{"authNum":\#(Int(digits) ?? 0)}"#, timeout: 8
        ) { $0.hasSuffix("/authenticationcode") }
        let json = try? JSONSerialization.jsonObject(with: message.payload) as? [String: Any]
        let result = json?["result"]
        guard (result as? Int) == 1 || (result as? String) == "1" else { throw RemoteControllerError.unauthorized }
        try? await publish(service: "ui_service", action: "authenticationcodeclose", payload: "")
    }

    // MARK: Publication

    private func topic(_ service: String, _ action: String) -> String {
        "/remoteapp/tv/\(service)/\(clientID)/actions/\(action)"
    }

    private func publish(service: String, action: String, payload: String) async throws {
        try await ensureConnected(timeout: 4)
        let topic = topic(service, action)
        queue.async { self.rawPublish(topic: topic, payload: payload) }
    }

    private func request(
        service: String, action: String, payload: String, timeout: TimeInterval,
        match: @escaping @Sendable (String) -> Bool
    ) async throws -> HisenseMessage {
        try await ensureConnected(timeout: 4)
        let topic = topic(service, action)
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.connected else {
                    continuation.resume(throwing: RemoteControllerError.notConnected)
                    return
                }
                self.waiters[id] = (match, continuation)
                self.rawPublish(topic: topic, payload: payload)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.waiters.removeValue(forKey: id)?.continuation.resume(throwing: RemoteControllerError.timedOut)
                }
            }
        }
    }

    private func rawPublish(topic: String, payload: String) {
        guard let connection, connected else { return }
        connection.send(content: Self.packet(0x30, Self.encode(topic) + Array(payload.utf8)), completion: .idempotent)
    }

    // MARK: Connexion

    private func ensureConnected(timeout: TimeInterval) async throws {
        if queue.sync(execute: { connected }) { return }
        let task = connectLock.withLock { current -> Task<Void, Error> in
            if let current { return current }
            let task = Task { try await self.connectAny(timeout: timeout) }
            current = task
            return task
        }
        defer { connectLock.withLock { $0 = nil } }
        try await task.value
    }

    private func connectAny(timeout: TimeInterval) async throws {
        queue.sync { sawTLSFailure = false }
        var lastError: Error = RemoteControllerError.notConnected
        for tls in [true, false] {
            do {
                try await open(tls: tls, timeout: timeout)
                return
            } catch HisenseError.rejected {
                throw HisenseError.rejected
            } catch {
                lastError = error
            }
        }
        // Le port répond mais aucune poignée de main n'aboutit : certificat client exigé.
        if queue.sync(execute: { sawTLSFailure }) { throw HisenseError.rejected }
        throw lastError
    }

    private func open(tls: Bool, timeout: TimeInterval) async throws {
        let parameters: NWParameters
        if tls {
            let options = NWProtocolTLS.Options()
            let host = self.host
            sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in
                complete(LocalNetworkTrustDelegate.isPrivateHost(host))
            }, queue)
            sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv10)
            parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        } else {
            parameters = .tcp
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: Self.port)!, using: parameters)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.teardown(error: RemoteControllerError.notConnected)
                self.connection = connection
                self.buffer = []
                self.connackWaiter = continuation
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self, self.connection === connection else { return }
                    switch state {
                    case .ready:
                        connection.send(content: self.connectPacket(), completion: .idempotent)
                        self.receive(on: connection)
                    case .failed(let error), .waiting(let error):
                        if case .tls = error { self.sawTLSFailure = true }
                        self.teardown(error: RemoteControllerError.notConnected)
                    default:
                        break
                    }
                }
                connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    guard self.connection === connection, !self.connected else { return }
                    self.teardown(error: RemoteControllerError.timedOut)
                }
            }
        }
    }

    private func connectPacket() -> Data {
        var body = Self.encode("MQTT")
        body += [4, 0xC2, 0, 30] // MQTT 3.1.1, identifiants + session propre, keep-alive 30 s
        body += Self.encode(clientID) + Self.encode("hisenseservice") + Self.encode("multimqttservice")
        return Self.packet(0x10, body)
    }

    private func subscribe(_ topics: [String]) {
        guard let connection else { return }
        for topic in topics {
            packetID = packetID &+ 1
            let body = [UInt8(packetID >> 8), UInt8(packetID & 0xFF)] + Self.encode(topic) + [0]
            connection.send(content: Self.packet(0x82, body), completion: .idempotent)
        }
    }

    private func startPing() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 20, repeating: 20)
        timer.setEventHandler { [weak self] in
            self?.connection?.send(content: Data([0xC0, 0x00]), completion: .idempotent)
        }
        timer.resume()
        pingTimer = timer
    }

    private func teardown(error: Error) {
        pingTimer?.cancel()
        pingTimer = nil
        connackWaiter?.resume(throwing: error)
        connackWaiter = nil
        let pending = waiters
        waiters = [:]
        for waiter in pending.values { waiter.continuation.resume(throwing: error) }
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        connected = false
        buffer = []
    }

    // MARK: Réception

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, self.connection === connection else { return }
            if let data { self.buffer.append(contentsOf: data) }
            self.parsePackets()
            guard self.connection === connection else { return }
            if isComplete || error != nil {
                self.teardown(error: RemoteControllerError.notConnected)
                return
            }
            self.receive(on: connection)
        }
    }

    private func parsePackets() {
        while let (header, body, consumed) = Self.nextPacket(in: buffer) {
            buffer.removeFirst(consumed)
            handle(header: header, body: body)
            guard connection != nil else { return }
        }
    }

    private func handle(header: UInt8, body: [UInt8]) {
        switch header >> 4 {
        case 2: // CONNACK
            let code = body.count >= 2 ? body[1] : 0xFF
            guard code == 0 else {
                teardown(error: HisenseError.rejected)
                return
            }
            connected = true
            subscribe(["/remoteapp/mobile/\(clientID)/#", "/remoteapp/mobile/broadcast/#"])
            startPing()
            connackWaiter?.resume()
            connackWaiter = nil
        case 3: // PUBLISH
            guard body.count >= 2 else { return }
            let length = Int(body[0]) << 8 | Int(body[1])
            guard body.count >= 2 + length else { return }
            let topic = String(decoding: body[2..<(2 + length)], as: UTF8.self)
            let qos = (header >> 1) & 0x03
            var offset = 2 + length
            if qos > 0, body.count >= offset + 2 {
                connection?.send(content: Data([0x40, 0x02, body[offset], body[offset + 1]]), completion: .idempotent)
                offset += 2
            }
            let message = HisenseMessage(topic: topic, payload: Data(body[min(offset, body.count)...]))
            for (id, waiter) in waiters where waiter.match(topic) {
                waiters.removeValue(forKey: id)
                waiter.continuation.resume(returning: message)
            }
        default:
            break
        }
    }

    // MARK: Encodage MQTT

    private static func encode(_ string: String) -> [UInt8] {
        let bytes = Array(string.utf8)
        return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
    }

    private static func packet(_ header: UInt8, _ body: [UInt8]) -> Data {
        var out: [UInt8] = [header]
        var length = body.count
        repeat {
            var byte = UInt8(length % 128)
            length /= 128
            if length > 0 { byte |= 0x80 }
            out.append(byte)
        } while length > 0
        return Data(out + body)
    }

    private static func nextPacket(in bytes: [UInt8]) -> (UInt8, [UInt8], Int)? {
        guard bytes.count >= 2 else { return nil }
        var multiplier = 1
        var length = 0
        var index = 1
        while true {
            guard index < bytes.count, index <= 4 else { return nil }
            let byte = Int(bytes[index])
            index += 1
            length += (byte & 0x7F) * multiplier
            if byte & 0x80 == 0 { break }
            multiplier *= 128
        }
        guard bytes.count >= index + length else { return nil }
        return (bytes[0], Array(bytes[index..<(index + length)]), index + length)
    }

    private static func keyName(for key: OrangeKey) -> String? {
        switch key {
        case .up: "KEY_UP"
        case .down: "KEY_DOWN"
        case .left: "KEY_LEFT"
        case .right: "KEY_RIGHT"
        case .ok, .enter: "KEY_OK"
        case .back: "KEY_RETURNS"
        case .menu: "KEY_HOME"
        case .volumeUp: "KEY_VOLUMEUP"
        case .volumeDown: "KEY_VOLUMEDOWN"
        case .mute: "KEY_MUTE"
        case .channelUp: "KEY_CHANNELUP"
        case .channelDown: "KEY_CHANNELDOWN"
        case .playPause: "KEY_PLAY"
        case .power: "KEY_POWER"
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine: "KEY_" + key.digit
        case .record, .keyboard, .input: nil
        }
    }

    /// Détection : le broker MQTT répond sur le port 36669.
    static func isListening(ip: String, timeout: TimeInterval) async -> Bool {
        await isTCPPortOpen(ip: ip, port: port, timeout: timeout)
    }
}

/// Vrai si une connexion TCP aboutit sur ce port avant le délai.
func isTCPPortOpen(ip: String, port: UInt16, timeout: TimeInterval) async -> Bool {
    let connection = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        let done = OSAllocatedUnfairLock(initialState: false)
        let finish: @Sendable (Bool) -> Void = { value in
            let first = done.withLock { state -> Bool in
                defer { state = true }
                return !state
            }
            guard first else { return }
            connection.cancel()
            continuation.resume(returning: value)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .waiting, .cancelled: finish(false)
            default: break
            }
        }
        connection.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
    }
}

// MARK: - Décodeurs SFR (WebSocket local, port 7682)

/// Protocole de l'app SFR TV (documenté par la communauté : sfrtvctl, sfr-tv-box-remote).
/// STB7 (« Décodeur TV 4K ») et LaBox partagent le même format JSON mais pas les mêmes codes de touches ;
/// le décodeur Box 8 utilise un autre format.
enum SFRVariant: String, Sendable {
    case stb7
    case labox
    case stb8

    var label: String {
        switch self {
        case .stb7: "Décodeur TV SFR (STB7)"
        case .labox: "LaBox"
        case .stb8: "Décodeur Box 8"
        }
    }
}

final class SFRDecoderClient: RemoteController, @unchecked Sendable {
    static let port: UInt16 = 7682

    let host: String
    private(set) var variant: SFRVariant
    private let mac: String?
    private let lock = OSAllocatedUnfairLock()
    private var socket: LocalWebSocket?
    private var drainTask: Task<Void, Never>?

    /// Identifiant stable de cette app auprès des décodeurs.
    private static let deviceID: String = {
        let key = "sfrDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    init(host: String, variant: SFRVariant?, mac: String?) {
        self.host = host
        self.variant = variant ?? .stb7
        self.mac = mac
    }

    func send(_ key: OrangeKey, direction: Int32) async throws {
        guard direction != 2 else { return }
        if key == .power {
            try await togglePower()
            return
        }
        try await sendKey(key)
    }

    func togglePower() async throws {
        do {
            try await sendKey(.power)
        } catch {
            guard let mac else { throw error }
            await WakeOnLAN.wake(mac: mac, lastKnownIP: host)
        }
    }

    func ping() async -> Bool {
        (try? await ensureConnected(timeout: 3)) != nil
    }

    func disconnect() {
        drainTask?.cancel()
        let s = lock.withLock { () -> LocalWebSocket? in defer { socket = nil }; return socket }
        s?.close()
    }

    /// Ouvre la connexion et devine le modèle quand la détection ne l'a pas donné.
    func identify() async throws -> SFRVariant {
        let ws = try await ensureConnected(timeout: 4)
        try await ws.send(Self.json(statusRequest(for: variant)))
        if let reply = try? await ws.receive(timeout: 2.5) {
            let lower = reply.lowercased()
            if lower.contains("labox") || lower.contains("numericable") { variant = .labox }
            else if reply.contains("\"remoteResponseCode\"") { variant = .stb8 }
        }
        startDraining(ws)
        return variant
    }

    private func sendKey(_ key: OrangeKey) async throws {
        guard let payload = message(for: key) else { throw RemoteControllerError.unsupportedKey }
        let text = Self.json(payload)
        do {
            try await ensureConnected(timeout: 3).send(text)
        } catch {
            disconnect()
            try await ensureConnected(timeout: 3).send(text)
        }
    }

    private func message(for key: OrangeKey) -> [String: Any]? {
        switch variant {
        case .stb8:
            guard let name = Self.stb8Key(key) else { return nil }
            return [
                "action": "buttonEvent",
                "deviceId": Self.deviceID,
                "requestId": Int(Date().timeIntervalSince1970 * 1000),
                "params": ["key": name],
            ]
        case .stb7, .labox:
            guard let code = variant == .labox ? Self.laboxCode(key) : Self.stb7Code(key) else { return nil }
            var params = Self.lanParams(action: "ButtonEvent")
            params["Press"] = [code]
            return ["Params": params]
        }
    }

    private func statusRequest(for variant: SFRVariant) -> [String: Any] {
        switch variant {
        case .stb8:
            ["action": "getStatus", "deviceId": Self.deviceID, "requestId": Int(Date().timeIntervalSince1970 * 1000)]
        case .stb7, .labox:
            ["Params": Self.lanParams(action: "GetVersions")]
        }
    }

    private static func lanParams(action: String) -> [String: Any] {
        [
            "Token": "LAN",
            "Action": action,
            "DeviceModel": "iPhone",
            "DeviceSoftVersion": "11.2.2",
            "DeviceId": deviceID,
        ]
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func ensureConnected(timeout: TimeInterval) async throws -> LocalWebSocket {
        if let existing = lock.withLock({ socket }), existing.isOpen { return existing }
        disconnect()
        // STB7 / LaBox : racine + sous-protocole libwebsockets ; Box 8 : chemin /ws.
        let attempts: [(path: String, protocols: [String])] = variant == .stb8
            ? [("/ws", []), ("/", ["lws-bidirectional-protocol"])]
            : [("/", ["lws-bidirectional-protocol"]), ("/ws", [])]
        guard await isTCPPortOpen(ip: host, port: Self.port, timeout: min(timeout, 2)) else {
            throw RemoteControllerError.notConnected
        }
        var lastError: Error = RemoteControllerError.notConnected
        for attempt in attempts {
            guard let url = URL(string: "ws://\(host):\(Self.port)\(attempt.path)") else { continue }
            let ws = LocalWebSocket(url: url, protocols: attempt.protocols)
            do {
                // Le décodeur n'envoie rien à l'ouverture : un ping WebSocket confirme la poignée de main.
                try await ws.sendPing(timeout: timeout)
                lock.withLock { socket = ws }
                startDraining(ws)
                return ws
            } catch {
                ws.close()
                lastError = error
            }
        }
        throw lastError
    }

    private func startDraining(_ ws: LocalWebSocket) {
        drainTask?.cancel()
        drainTask = Task {
            while !Task.isCancelled {
                guard (try? await ws.receive()) != nil else { break }
            }
        }
    }

    private static func stb7Code(_ key: OrangeKey) -> Int? {
        switch key {
        case .volumeUp: 308
        case .volumeDown: 307
        case .channelUp: 290
        case .channelDown: 291
        case .menu: 292
        case .back: 27
        case .power: 303
        case .playPause: 306
        case .record: 309
        case .mute: 302
        case .up: 297
        case .left: 293
        case .right: 222
        case .down: 294
        case .ok, .enter: 13
        case .input: 301 // touche Options / Info
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine: 48 + (Int(key.digit) ?? 0)
        case .keyboard: nil
        }
    }

    private static func laboxCode(_ key: OrangeKey) -> Int? {
        switch key {
        case .volumeUp: 63234
        case .volumeDown: 63235
        case .channelUp: 63237
        case .channelDown: 63236
        case .menu: 63270
        case .back: 63271
        case .power: 63232
        case .playPause: 63241
        case .record: 63242
        case .mute: 63233
        case .up: 38
        case .left: 37
        case .right: 39
        case .down: 40
        case .ok, .enter: 13
        case .input: 63273
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine: 48 + (Int(key.digit) ?? 0)
        case .keyboard: nil
        }
    }

    private static func stb8Key(_ key: OrangeKey) -> String? {
        switch key {
        case .volumeUp: "volUp"
        case .volumeDown: "volDown"
        case .channelUp: "channelUp"
        case .channelDown: "channelDown"
        case .menu: "home"
        case .back: "back"
        case .power: "power"
        case .playPause: "playPause"
        case .record: "record"
        case .mute: "mute"
        case .up: "up"
        case .left: "left"
        case .right: "right"
        case .down: "down"
        case .ok, .enter: "ok"
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine: key.digit
        case .input, .keyboard: nil
        }
    }
}

// MARK: - Freebox Player (télécommande réseau)

/// API historique des Freebox Player Révolution, Crystal, Delta et One :
/// GET http://<player>/pub/remote_control?code=<code>&key=<touche>.
/// Le code s'affiche sur la TV : Réglages › Système › Informations Freebox Player et Server.
final class FreeboxPlayerClient: RemoteController, @unchecked Sendable {
    let host: String
    private let code: String

    init(host: String, code: String) {
        self.host = host
        self.code = code.filter(\.isNumber)
    }

    func send(_ key: OrangeKey, direction: Int32) async throws {
        guard direction != 2 else { return }
        guard let name = Self.keyName(for: key) else { throw RemoteControllerError.unsupportedKey }
        try await press(name)
    }

    func ping() async -> Bool {
        await isTCPPortOpen(ip: host, port: 80, timeout: 2)
    }

    func disconnect() {}

    /// Vérifie le code sans déclencher d'action visible (touche vide).
    func validate() async throws {
        try await press("")
    }

    private func press(_ name: String, long: Bool = false) async throws {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = "/pub/remote_control"
        components.queryItems = [URLQueryItem(name: "code", value: code), URLQueryItem(name: "key", value: name)]
        if long { components.queryItems?.append(URLQueryItem(name: "long", value: "true")) }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (_, response) = try await localNetworkSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || status == 401 { throw RemoteControllerError.unauthorized }
        if status == 404 { throw RemoteControllerError.notConnected }
    }

    private static func keyName(for key: OrangeKey) -> String? {
        switch key {
        case .power: "power"
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        case .ok, .enter: "ok"
        case .back: "back"
        case .menu: "home"
        case .volumeUp: "vol_inc"
        case .volumeDown: "vol_dec"
        case .mute: "mute"
        case .channelUp: "prgm_inc"
        case .channelDown: "prgm_dec"
        case .playPause: "play"
        case .record: "rec"
        case .input: "tv"
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine: key.digit
        case .keyboard: nil
        }
    }

    /// Sur le réseau Free, hd1.freebox.fr (hd2 pour un 2e Player) pointe vers l'IP locale du Player.
    static func discover() async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for name in ["hd1.freebox.fr", "hd2.freebox.fr"] {
                group.addTask { await resolveIPv4(name) }
            }
            var ips: [String] = []
            for await ip in group {
                if let ip, LocalNetworkTrustDelegate.isPrivateHost(ip), !ips.contains(ip) { ips.append(ip) }
            }
            return ips
        }
    }
}

/// Résolution DNS IPv4 simple (sans cache) hors du thread principal.
func resolveIPv4(_ name: String) async -> String? {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                                 ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else {
                continuation.resume(returning: nil)
                return
            }
            defer { freeaddrinfo(result) }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let ip: String? = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addr in
                var address = addr.pointee.sin_addr
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            continuation.resume(returning: ip)
        }
    }
}
