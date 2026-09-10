import Foundation

/// Le protocole d'éclairage du Nommo V2 en Bluetooth : un canal à opcodes compact,
/// sans rapport avec le rapport HID USB de 90 octets.
///
/// Les commandes partent vers `416D0000…`, les réponses arrivent en notification sur
/// `416D0001…` sous la forme `[opcode][type][longueur][valeur…]`.
///
/// Le firmware valide la longueur : un SET dont la longueur ne correspond pas à celle
/// que renvoie le GET correspondant est ignoré sans réponse. D'où la règle : lire un
/// opcode avant de l'écrire.
enum NommoBLE {
    /// Une requête de lecture tient sur cinq octets, les quatre derniers à zéro.
    static let requestSize = 5

    /// Luminosité, le seul opcode dont l'effet visuel soit confirmé.
    static let brightnessOpcode: UInt8 = 0x13

    /// Les opcodes de lecture occupent 0x00–0x7F ; l'écriture réutilise le même
    /// numéro avec le bit de poids fort armé.
    static let readableRange: ClosedRange<UInt8> = 0x00...0x7F

    static func get(_ opcode: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0, count: requestSize)
        bytes[0] = opcode
        return Data(bytes)
    }

    /// Dispositions candidates pour une écriture. Le format de lecture est confirmé,
    /// celui d'écriture ne l'est pas : aucune source publique ne l'a établi, donc on
    /// les propose toutes les trois plutôt que d'en figer une au hasard.
    enum SetLayout: String, CaseIterable, Identifiable {
        case padded
        case compact
        case tagged

        var id: String { rawValue }

        var label: String {
            switch self {
            case .padded: return "5 octets [op|80][val][0][0][0]"
            case .compact: return "Compact [op|80][val…]"
            case .tagged: return "Balisé [op|80][01][len][val…]"
            }
        }
    }

    static func set(_ opcode: UInt8, value: [UInt8], layout: SetLayout) -> Data {
        let opcode = opcode | 0x80
        switch layout {
        case .padded:
            var bytes = [UInt8](repeating: 0, count: requestSize)
            bytes[0] = opcode
            for (offset, byte) in value.prefix(requestSize - 1).enumerated() {
                bytes[1 + offset] = byte
            }
            return Data(bytes)
        case .compact:
            return Data([opcode] + value)
        case .tagged:
            return Data([opcode, 0x01, UInt8(value.count)] + value)
        }
    }

    struct Reply {
        enum Kind: UInt8 {
            case reply = 0x01
            case stateChange = 0x02
        }

        let opcode: UInt8
        let kind: Kind?
        let value: [UInt8]

        var description: String {
            let nature: String
            switch kind {
            case .reply: nature = "réponse"
            case .stateChange: nature = "changement d'état"
            case nil: nature = "type inconnu"
            }
            return "opcode \(hex(opcode)) — \(nature) : \(hexList(value))"
        }

        private func hex(_ byte: UInt8) -> String { String(format: "%02X", byte) }

        private func hexList(_ bytes: [UInt8]) -> String {
            bytes.isEmpty ? "(vide)" : bytes.map { hex($0) }.joined(separator: " ")
        }
    }

    static func parse(_ data: Data) -> Reply? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3 else { return nil }
        let declared = Int(bytes[2])
        return Reply(
            opcode: bytes[0],
            kind: Reply.Kind(rawValue: bytes[1]),
            value: Array(bytes.dropFirst(3).prefix(declared))
        )
    }
}
