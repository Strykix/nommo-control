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
                nommoSection
                Divider()
                workbenchSection
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
            "L'éclairage du Nommo V2 passe par le canal à opcodes compact, pas par le rapport Razer de 90 octets, que le firmware ignore. La luminosité est la seule commande dont l'effet visuel soit établi ; l'opcode qui porte la couleur reste à trouver.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var nommoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Protocole Nommo BLE").font(.headline)
            Text("Le format de lecture est confirmé. Le sondage interroge les 128 opcodes en lecture seule : il ne modifie rien et les réponses décodées apparaissent dans le journal.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let channel = razerChannel {
                Text("Canal : \(channel.uuidString)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    "Canal Razer introuvable. Connectez le Nommo : cette section écrit toujours sur 416D0000, indépendamment du sélecteur ci-dessus.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button("Sonder les opcodes") { probeOpcodes() }
                Button("Lire la luminosité") { sendGet(NommoBLE.brightnessOpcode) }
            }
            .disabled(razerChannel == nil)

            HStack(spacing: 12) {
                Text("Luminosité").font(.callout)
                Slider(value: $lighting.bleBrightness, in: 0...255)
                Text("\(Int(lighting.bleBrightness))")
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
                Button("Appliquer") { sendNommoBrightness() }
                    .disabled(razerChannel == nil)
            }

            Picker("Disposition d'écriture", selection: $lighting.setLayout) {
                ForEach(NommoBLE.SetLayout.allCases) { layout in
                    Text(layout.label).tag(layout)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    private var workbenchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Établi à opcodes").font(.headline)
            Text("La méthode pour trouver la couleur : lire un opcode pour connaître la longueur exacte de sa valeur, puis la réécrire modifiée. Une écriture de longueur différente est ignorée sans réponse. L'opcode 10 est le principal suspect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Opcode").font(.callout)
                TextField("10", text: $lighting.workbenchOpcode)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 56)
                Button("Lire") { readWorkbenchOpcode() }

                if let value = workbenchCurrentValue {
                    Text("lu : \(Hex.encode(Data(value))) (\(value.count) o)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("Reprendre") { lighting.workbenchValue = Hex.encode(Data(value)) }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Valeur").font(.callout)
                TextField("FF 00 00 00", text: $lighting.workbenchValue)
                    .font(.system(.body, design: .monospaced))
                Button("Écrire") { writeWorkbenchOpcode() }
            }

            if let warning = workbenchWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
        }
        .disabled(razerChannel == nil)
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
                        Text("\(node.uuidString) [\(node.propertyLabels.joined(separator: ", "))]"
                            + (node.isRazerCommandChannel ? "  ★ canal Razer" : ""))
                            .tag(String?.some(node.id))
                    }
                }
                .labelsHidden()
                .onChange(of: lighting.targetCharacteristicID) { _ in lighting.persist() }
                .onAppear { preferRazerChannel() }
                .onChange(of: writable.map(\.id)) { _ in preferRazerChannel() }
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

    /// The compact protocol is meaningful only on Razer's own characteristic, so this
    /// section resolves it directly instead of following the generic target picker,
    /// which may still hold a characteristic chosen during earlier exploration.
    private var razerChannel: CharacteristicNode? {
        bluetooth.writableCharacteristics.first { $0.isRazerCommandChannel }
    }

    private func probeOpcodes() {
        guard let node = razerChannel else { return reportMissingChannel() }
        bluetooth.probeOpcodes(on: node)
    }

    private func sendGet(_ opcode: UInt8) {
        guard let node = razerChannel else { return reportMissingChannel() }
        bluetooth.write(NommoBLE.get(opcode), to: node, withResponse: false, fragment: false)
    }

    private func sendNommoBrightness() {
        guard let node = razerChannel else { return reportMissingChannel() }
        let payload = NommoBLE.set(
            NommoBLE.brightnessOpcode,
            value: [UInt8(clamping: Int(lighting.bleBrightness))],
            layout: lighting.setLayout
        )
        bluetooth.write(payload, to: node, withResponse: false, fragment: false)
    }

    private var workbenchOpcode: UInt8? {
        UInt8(lighting.workbenchOpcode.trimmingCharacters(in: .whitespaces), radix: 16)
    }

    private var workbenchCurrentValue: [UInt8]? {
        workbenchOpcode.flatMap { bluetooth.opcodeValues[$0] }
    }

    private var workbenchWarning: String? {
        guard let expected = workbenchCurrentValue,
              let typed = Hex.decode(lighting.workbenchValue),
              typed.count != expected.count
        else { return nil }
        return "Valeur de \(typed.count) o alors que l'opcode en annonce \(expected.count) : le firmware ignorera l'écriture."
    }

    private func readWorkbenchOpcode() {
        guard let opcode = workbenchOpcode else {
            bluetooth.append(.error, "Opcode illisible : deux chiffres hexadécimaux attendus")
            return
        }
        sendGet(opcode)
    }

    private func writeWorkbenchOpcode() {
        guard let node = razerChannel else { return reportMissingChannel() }
        guard let opcode = workbenchOpcode else {
            bluetooth.append(.error, "Opcode illisible : deux chiffres hexadécimaux attendus")
            return
        }
        guard let value = Hex.decode(lighting.workbenchValue) else {
            bluetooth.append(.error, "Valeur hexadécimale invalide")
            return
        }
        bluetooth.write(
            NommoBLE.set(opcode, value: [UInt8](value), layout: lighting.setLayout),
            to: node,
            withResponse: false,
            fragment: false
        )
    }

    private func reportMissingChannel() {
        bluetooth.append(.error, "Canal Razer (416D0000) absent — appareil déconnecté ?")
    }

    /// Only fills an empty selection, so a deliberate choice of another channel survives.
    private func preferRazerChannel() {
        guard lighting.targetCharacteristicID == nil,
              let razer = bluetooth.writableCharacteristics.first(where: { $0.isRazerCommandChannel })
        else { return }
        lighting.targetCharacteristicID = razer.id
        lighting.persist()
    }

    private func sendEffect() {
        guard let node = targetNode else {
            bluetooth.append(.error, "Aucune caractéristique cible sélectionnée")
            return
        }
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
        guard let node = targetNode else {
            bluetooth.append(.error, "Aucune caractéristique cible sélectionnée")
            return
        }
        guard let payload = lighting.brightnessPayload() else {
            bluetooth.append(.error, "La luminosité n'existe que pour l'encodage Rapport Razer")
            return
        }
        bluetooth.write(
            payload,
            to: node,
            withResponse: lighting.writeWithResponse,
            fragment: lighting.fragmentToMTU
        )
    }
}
