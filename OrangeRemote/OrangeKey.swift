import Foundation

enum OrangeKey: String, CaseIterable, Identifiable {
    case power
    case zero
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case channelUp
    case channelDown
    case volumeUp
    case volumeDown
    case mute
    case up
    case down
    case left
    case right
    case ok
    case back
    case menu
    case playPause
    case record

    var id: String { rawValue }

    var code: Int {
        switch self {
        case .power: 116
        case .zero: 512
        case .one: 513
        case .two: 514
        case .three: 515
        case .four: 516
        case .five: 517
        case .six: 518
        case .seven: 519
        case .eight: 520
        case .nine: 521
        case .channelUp: 402
        case .channelDown: 403
        case .volumeUp: 115
        case .volumeDown: 114
        case .mute: 113
        case .up: 103
        case .down: 108
        case .left: 105
        case .right: 106
        case .ok: 352
        case .back: 158
        case .menu: 139
        case .playPause: 164
        case .record: 167
        }
    }
}
