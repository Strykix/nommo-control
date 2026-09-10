import SwiftUI

/// Holds what would normally be `@State`. In recent SDKs `@State` expands through the
/// SwiftUIMacros plugin, which ships with Xcode but not with the Command Line Tools, so
/// an ObservableObject keeps the app buildable with either toolchain.
private final class ExplorerSelection: ObservableObject {
    @Published var manualPayload = ""
    @Published var selectedID: String?
}

struct ExplorerView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @StateObject private var selection = ExplorerSelection()

    var body: some View {
        HSplitView {
            servicesList
                .frame(minWidth: 320)
            manualWritePanel
                .frame(minWidth: 300)
        }
    }

    private var servicesList: some View {
        List {
            ForEach(bluetooth.services) { service in
                Section(service.id) {
                    ForEach(service.characteristics) { node in
                        CharacteristicRow(node: node, isSelected: node.id == selection.selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { selection.selectedID = node.id }
                    }
                }
            }
        }
        .overlay {
            if bluetooth.services.isEmpty {
                Text("Connectez un appareil pour explorer ses services GATT.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var manualWritePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Écriture manuelle").font(.headline)

            if let node = selectedNode {
                Text(node.uuidString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text(node.propertyLabels.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("Octets hexadécimaux, ex. 00 3F 00 00", text: $selection.manualPayload, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3...8)

                HStack {
                    Button("Écrire (réponse)") { write(withResponse: true) }
                        .disabled(!node.characteristic.properties.contains(.write) || parsed == nil)
                    Button("Écrire (sans réponse)") { write(withResponse: false) }
                        .disabled(!node.characteristic.properties.contains(.writeWithoutResponse) || parsed == nil)
                }

                HStack {
                    Button("Lire") { bluetooth.read(node) }
                        .disabled(!node.characteristic.properties.contains(.read))
                    Button(node.characteristic.isNotifying ? "Stop notify" : "Notify") {
                        bluetooth.toggleNotify(node)
                    }
                    .disabled(
                        !node.characteristic.properties.contains(.notify)
                            && !node.characteristic.properties.contains(.indicate)
                    )
                }

                if let value = node.lastValue, !value.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dernière valeur").font(.caption.bold())
                        Text(Hex.encode(value))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } else {
                Text("Sélectionnez une caractéristique à gauche.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
    }

    private var selectedNode: CharacteristicNode? {
        bluetooth.services.flatMap(\.characteristics).first { $0.id == selection.selectedID }
    }

    private var parsed: Data? {
        Hex.decode(selection.manualPayload)
    }

    private func write(withResponse: Bool) {
        guard let node = selectedNode, let data = parsed else { return }
        bluetooth.write(data, to: node, withResponse: withResponse, fragment: false)
    }
}

private struct CharacteristicRow: View {
    let node: CharacteristicNode
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(node.uuidString)
                .font(.system(.caption, design: .monospaced))
            Text(node.propertyLabels.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
}
