import SwiftUI

struct ClassicDevicesView: View {
    @EnvironmentObject private var classic: ClassicBluetoothScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "CoreBluetooth ne voit que le BLE. Une enceinte appairée en audio utilise le Bluetooth classique : cette liste montre ce que macOS en sait, y compris les canaux RFCOMM éventuels.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Rafraîchir") { classic.refresh() }

            List(classic.devices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.name).font(.callout.bold())
                        if device.isConnected {
                            Text("connecté")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(device.address)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)

                    ForEach(device.services) { service in
                        HStack(spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(service.name).font(.caption)
                            if let channel = service.rfcommChannel {
                                Text("RFCOMM \(channel)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if classic.devices.isEmpty {
                    Text("Aucun appareil appairé trouvé.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { classic.refresh() }
    }
}
