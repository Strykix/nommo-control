import CoreBluetooth
import Foundation

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var lastSeen: Date
    var manufacturerData: Data?

    /// Razer's Bluetooth SIG company identifier, little-endian in the advertisement.
    static let razerCompanyID: UInt16 = 0x0157

    var looksLikeRazer: Bool {
        if name.range(of: "razer", options: .caseInsensitive) != nil { return true }
        if name.range(of: "nommo", options: .caseInsensitive) != nil { return true }
        guard let data = manufacturerData, data.count >= 2 else { return false }
        let company = UInt16(data[0]) | (UInt16(data[1]) << 8)
        return company == Self.razerCompanyID
    }
}

struct ServiceNode: Identifiable {
    let id: String
    let service: CBService
    var characteristics: [CharacteristicNode]
}

struct CharacteristicNode: Identifiable {
    let id: String
    let characteristic: CBCharacteristic
    var lastValue: Data?

    var uuidString: String { characteristic.uuid.uuidString }

    var isWritable: Bool {
        characteristic.properties.contains(.write)
            || characteristic.properties.contains(.writeWithoutResponse)
    }

    /// Razer's own BLE channel spells the ASCII string "-RazerBLE" inside its UUID
    /// (2D 52 61 7A 65 72 42 4C 45), which is what distinguishes it from the unrelated
    /// vendor services the speaker also advertises.
    static let razerSignature = "2D52-617A-6572-424C45"

    var isRazerCommandChannel: Bool {
        uuidString.uppercased().contains(Self.razerSignature)
    }

    var propertyLabels: [String] {
        let props = characteristic.properties
        var labels: [String] = []
        if props.contains(.read) { labels.append("read") }
        if props.contains(.write) { labels.append("write") }
        if props.contains(.writeWithoutResponse) { labels.append("writeNR") }
        if props.contains(.notify) { labels.append("notify") }
        if props.contains(.indicate) { labels.append("indicate") }
        return labels
    }
}

struct LogEntry: Identifiable {
    enum Kind {
        case info, tx, rx, error
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let message: String

    var prefix: String {
        switch kind {
        case .info: return "··"
        case .tx: return "→"
        case .rx: return "←"
        case .error: return "!!"
        }
    }
}

enum Hex {
    static func encode(_ data: Data, separator: String = " ") -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: separator)
    }

    /// Parses "0F 03 1A", "0f031a" or "0x0F,0x03" into bytes. Returns nil on malformed input.
    static func decode(_ string: String) -> Data? {
        let cleaned = string
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { $0.isHexDigit }
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
