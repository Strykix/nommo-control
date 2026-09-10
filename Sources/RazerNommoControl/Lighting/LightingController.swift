import AppKit
import Combine
import Foundation
import SwiftUI

/// Turns the UI's colour/effect choices into bytes and hands them to a characteristic.
///
/// Two encodings are offered because the device's real protocol is unknown: the Razer
/// HID report (a hypothesis worth testing first) and a free-form template you edit as
/// you learn what the speaker actually accepts.
final class LightingController: ObservableObject {
    enum Encoding: String, CaseIterable, Identifiable {
        case razerReport
        case template

        var id: String { rawValue }

        var label: String {
            switch self {
            case .razerReport: return "Rapport Razer (90 o)"
            case .template: return "Modèle personnalisé"
            }
        }
    }

    enum Effect: String, CaseIterable, Identifiable {
        case off, solid, breathing, spectrum, wave

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: return "Éteint"
            case .solid: return "Couleur fixe"
            case .breathing: return "Respiration"
            case .spectrum: return "Spectre"
            case .wave: return "Vague"
            }
        }

        var usesColor: Bool {
            self == .solid || self == .breathing
        }
    }

    @Published var encoding: Encoding = .razerReport
    @Published var effect: Effect = .solid
    @Published var color: Color = .purple
    @Published var brightness: Double = 100
    @Published var ledID: RazerReport.LEDID = .backlight
    @Published var waveClockwise = true
    @Published var writeWithResponse = true
    @Published var fragmentToMTU = true
    @Published var targetCharacteristicID: String?

    @Published var bleBrightness: Double = 255
    @Published var setLayout: NommoBLE.SetLayout = .padded

    /// Placeholders are substituted before the string is parsed as hex.
    @Published var template = "0F 02 01 05 06 00 00 01 {R} {G} {B}"

    private let defaults = UserDefaults.standard
    private static let templateKey = "lighting.template"
    private static let targetKey = "lighting.target"

    init() {
        if let saved = defaults.string(forKey: Self.templateKey) {
            template = saved
        }
        targetCharacteristicID = defaults.string(forKey: Self.targetKey)
    }

    func persist() {
        defaults.set(template, forKey: Self.templateKey)
        defaults.set(targetCharacteristicID, forKey: Self.targetKey)
    }

    var rgb: RGB {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return RGB(
            red: UInt8(clamping: Int(resolved.redComponent * 255)),
            green: UInt8(clamping: Int(resolved.greenComponent * 255)),
            blue: UInt8(clamping: Int(resolved.blueComponent * 255))
        )
    }

    var brightnessByte: UInt8 {
        UInt8(clamping: Int(brightness * 255 / 100))
    }

    /// Nil when the custom template does not parse as hex.
    func effectPayload() -> Data? {
        switch encoding {
        case .razerReport:
            return razerReport().encoded()
        case .template:
            return Hex.decode(expandedTemplate())
        }
    }

    func brightnessPayload() -> Data? {
        guard encoding == .razerReport else { return nil }
        return RazerReport.brightness(brightnessByte, led: ledID).encoded()
    }

    func expandedTemplate() -> String {
        let color = rgb
        return template
            .replacingOccurrences(of: "{R}", with: String(format: "%02X", color.red))
            .replacingOccurrences(of: "{G}", with: String(format: "%02X", color.green))
            .replacingOccurrences(of: "{B}", with: String(format: "%02X", color.blue))
            .replacingOccurrences(of: "{BRIGHTNESS}", with: String(format: "%02X", brightnessByte))
    }

    private func razerReport() -> RazerReport {
        switch effect {
        case .off:
            return .off(led: ledID)
        case .solid:
            return .staticColor(rgb, led: ledID)
        case .breathing:
            return .breathing(rgb, led: ledID)
        case .spectrum:
            return .spectrum(led: ledID)
        case .wave:
            return .wave(led: ledID, clockwise: waveClockwise)
        }
    }
}
