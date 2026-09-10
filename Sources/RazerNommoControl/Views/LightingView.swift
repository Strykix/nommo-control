import SwiftUI

struct LightingView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var lighting: LightingController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                disclaimer
                targetSection
                Divider()
                encodingSection
                Divider()
                effectSection
                Divider()
                previewSection
            }
            .padding(4)
        }
    }

    private var disclaimer: some View {
        Label(
            "Le protocole d'éclairage du Nommo V2 Pro n'est pas documenté. Ces trames sont des hypothèses : si rien ne se passe, utilisez l'explorateur GATT pour trouver la bonne caractéristique.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Caractéristique cible").font(.headline)

            let writable = bluetooth.writableCharacteristics
            if writable.isEmpty {
                Text("Aucune caractéristique inscriptible. Connectez un appareil BLE d'abord.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Cible", selection: $lighting.targetCharacteristicID) {
                    Text("— choisir —").tag(String?.none)
                    ForEach(writable) { node in
                        Text("\(node.uuidString) [\(node.propertyLabels.joined(separator: ", "))]")
                            .tag(String?.some(node.id))
                    }
                }
                .labelsHidden()
                .onChange(of: lighting.targetCharacteristicID) { _ in lighting.persist() }
            }

            HStack(spacing: 16) {
                Toggle("Écriture avec réponse", isOn: $lighting.writeWithResponse)
                Toggle("Fragmenter selon le MTU", isOn: $lighting.fragmentToMTU)
            }
            .toggleStyle(.checkbox)
            .font(.caption)
        }
    }

    private var encodingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Encodage").font(.headline)
            Picker("Encodage", selection: $lighting.encoding) {
                ForEach(LightingController.Encoding.allCases) { encoding in
                    Text(encoding.label).tag(encoding)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if lighting.encoding == .template {
                Text("Modèle hexadécimal — {R} {G} {B} {BRIGHTNESS} sont remplacés à l'envoi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Modèle", text: $lighting.template, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...5)
                    .onSubmit { lighting.persist() }
            } else {
                Picker("LED", selection: $lighting.ledID) {
                    ForEach(RazerReport.LEDID.allCases, id: \.self) { led in
                        Text(led.label).tag(led)
                    }
                }
                .frame(maxWidth: 260)
            }
        }
    }

    private var effectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effet").font(.headline)

            Picker("Effet", selection: $lighting.effect) {
                ForEach(LightingController.Effect.allCases) { effect in
                    Text(effect.label).tag(effect)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if lighting.effect.usesColor {
                ColorPicker("Couleur", selection: $lighting.color, supportsOpacity: false)
                    .frame(maxWidth: 260)
            }

            if lighting.effect == .wave {
                Toggle("Sens horaire", isOn: $lighting.waveClockwise)
                    .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Luminosité : \(Int(lighting.brightness)) %")
                    .font(.caption)
                Slider(value: $lighting.brightness, in: 0...100, step: 1)
                    .frame(maxWidth: 320)
            }

            HStack(spacing: 10) {
                Button("Appliquer l'effet") { sendEffect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(targetNode == nil)

                Button("Appliquer la luminosité") { sendBrightness() }
                    .disabled(targetNode == nil || lighting.encoding != .razerReport)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trame qui sera envoyée").font(.headline)
            ScrollView(.horizontal) {
                Text(previewText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 90)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var previewText: String {
        guard let payload = lighting.effectPayload() else {
            return "Modèle invalide : il faut un nombre pair de chiffres hexadécimaux."
        }
        return Hex.encode(payload)
    }

    private var targetNode: CharacteristicNode? {
        guard let id = lighting.targetCharacteristicID else { return nil }
        return bluetooth.writableCharacteristics.first { $0.id == id }
    }

    private func sendEffect() {
        guard let node = targetNode else { return }
        guard let payload = lighting.effectPayload() else {
            bluetooth.append(.error, "Modèle hexadécimal invalide")
            return
        }
        bluetooth.write(
            payload,
            to: node,
            withResponse: lighting.writeWithResponse,
            fragment: lighting.fragmentToMTU
        )
    }

    private func sendBrightness() {
        guard let node = targetNode, let payload = lighting.brightnessPayload() else { return }
        bluetooth.write(
            payload,
            to: node,
            withResponse: lighting.writeWithResponse,
            fragment: lighting.fragmentToMTU
        )
    }
}
