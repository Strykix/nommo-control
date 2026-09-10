import CoreBluetooth
import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            List(bluetooth.visibleDevices) { device in
                DeviceRow(device: device)
                    .contentShape(Rectangle())
                    .onTapGesture { bluetooth.connect(device) }
            }
            .listStyle(.sidebar)
            .overlay {
                if bluetooth.visibleDevices.isEmpty {
                    emptyState
                }
            }

            Divider()
            connectionFooter
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(bluetooth.state == .poweredOn ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(bluetooth.stateDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(bluetooth.isScanning ? "Arrêter" : "Scanner") {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                }
                .disabled(bluetooth.state != .poweredOn)

                if bluetooth.isScanning {
                    ProgressView().controlSize(.small)
                }
            }

            Toggle("Razer uniquement", isOn: $bluetooth.onlyRazerDevices)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Aucun appareil BLE")
                .font(.callout)
            Text("Le Nommo peut n'être visible qu'en Bluetooth classique — voir l'onglet dédié.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    @ViewBuilder
    private var connectionFooter: some View {
        if let peripheral = bluetooth.connectedPeripheral {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(peripheral.name ?? "Connecté")
                        .font(.caption.bold())
                    Text("\(bluetooth.services.count) service(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Déconnecter") { bluetooth.disconnect() }
                    .controlSize(.small)
            }
            .padding(12)
        } else {
            Text("Non connecté")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }
}

private struct DeviceRow: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.looksLikeRazer ? "hifispeaker.fill" : "dot.radiowaves.left.and.right")
                .foregroundStyle(device.looksLikeRazer ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(device.rssi) dBm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
