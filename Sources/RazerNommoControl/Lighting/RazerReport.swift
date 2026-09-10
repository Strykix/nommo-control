import Foundation

/// The 90-byte report Razer uses for Chroma control on its USB HID peripherals.
///
/// The Nommo V2 Pro's *Bluetooth* protocol is not documented, and this frame is a
/// hypothesis, not a confirmed fact: Razer devices that expose a control channel over
/// BLE have historically tunnelled this same structure, so it is the first thing worth
/// trying against a writable characteristic. If it does nothing, use the Explorer tab to
/// capture what the device actually accepts.
struct RazerReport {
    enum VarStore: UInt8 {
        case noStore = 0x00
        case varStore = 0x01
    }

    /// LED identifiers vary per device; these are the values that show up most often.
    enum LEDID: UInt8, CaseIterable {
        case zero = 0x00
        case scrollWheel = 0x01
        case logo = 0x04
        case backlight = 0x05

        var label: String {
            switch self {
            case .zero: return "Zero (0x00)"
            case .scrollWheel: return "Scroll (0x01)"
            case .logo: return "Logo (0x04)"
            case .backlight: return "Backlight (0x05)"
            }
        }
    }

    enum ExtendedEffect: UInt8 {
        case off = 0x00
        case wave = 0x01
        case reactive = 0x02
        case breathing = 0x03
        case spectrum = 0x04
        case customFrame = 0x05
        case solid = 0x06
    }

    var status: UInt8 = 0x00
    var transactionID: UInt8 = 0x3F
    var remainingPackets: UInt16 = 0x0000
    var protocolType: UInt8 = 0x00
    var dataSize: UInt8
    var commandClass: UInt8
    var commandID: UInt8
    var arguments: [UInt8]

    static let argumentCount = 80
    static let totalSize = 90

    func encoded() -> Data {
        var bytes = [UInt8](repeating: 0, count: Self.totalSize)
        bytes[0] = status
        bytes[1] = transactionID
        bytes[2] = UInt8((remainingPackets >> 8) & 0xFF)
        bytes[3] = UInt8(remainingPackets & 0xFF)
        bytes[4] = protocolType
        bytes[5] = dataSize
        bytes[6] = commandClass
        bytes[7] = commandID
        for (offset, value) in arguments.prefix(Self.argumentCount).enumerated() {
            bytes[8 + offset] = value
        }
        // CRC is the XOR of every byte between the header and the checksum itself.
        var crc: UInt8 = 0
        for index in 2...87 {
            crc ^= bytes[index]
        }
        bytes[88] = crc
        bytes[89] = 0x00
        return Data(bytes)
    }

    // MARK: - Builders

    static func extendedMatrixEffect(
        _ effect: ExtendedEffect,
        led: LEDID,
        varStore: VarStore = .varStore,
        payload: [UInt8] = []
    ) -> RazerReport {
        let arguments = [varStore.rawValue, led.rawValue, effect.rawValue] + payload
        return RazerReport(
            dataSize: UInt8(arguments.count),
            commandClass: 0x0F,
            commandID: 0x02,
            arguments: arguments
        )
    }

    static func staticColor(_ color: RGB, led: LEDID, varStore: VarStore = .varStore) -> RazerReport {
        // Trailing 0x00 0x00 0x01 is the "one colour follows" descriptor used by the
        // extended matrix static effect.
        extendedMatrixEffect(
            .solid,
            led: led,
            varStore: varStore,
            payload: [0x00, 0x00, 0x01, color.red, color.green, color.blue]
        )
    }

    static func breathing(_ color: RGB, led: LEDID, varStore: VarStore = .varStore) -> RazerReport {
        extendedMatrixEffect(
            .breathing,
            led: led,
            varStore: varStore,
            payload: [0x01, 0x00, 0x01, color.red, color.green, color.blue]
        )
    }

    static func spectrum(led: LEDID, varStore: VarStore = .varStore) -> RazerReport {
        extendedMatrixEffect(.spectrum, led: led, varStore: varStore, payload: [0x00, 0x00, 0x00])
    }

    static func wave(led: LEDID, clockwise: Bool, varStore: VarStore = .varStore) -> RazerReport {
        extendedMatrixEffect(.wave, led: led, varStore: varStore, payload: [clockwise ? 0x01 : 0x02, 0x28])
    }

    static func off(led: LEDID, varStore: VarStore = .varStore) -> RazerReport {
        extendedMatrixEffect(.off, led: led, varStore: varStore, payload: [0x00, 0x00, 0x00])
    }

    static func brightness(_ level: UInt8, led: LEDID, varStore: VarStore = .varStore) -> RazerReport {
        RazerReport(
            dataSize: 0x03,
            commandClass: 0x0F,
            commandID: 0x04,
            arguments: [varStore.rawValue, led.rawValue, level]
        )
    }
}

struct RGB: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    static let white = RGB(red: 255, green: 255, blue: 255)
}
