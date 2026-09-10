import Foundation
import IOBluetooth

/// CoreBluetooth only sees Bluetooth Low Energy. A speaker that pairs as an audio
/// device uses classic Bluetooth (BR/EDR) and is invisible there, so this lists the
/// paired classic devices and their SDP records — that's how you find out whether the
/// Nommo exposes any vendor channel at all beyond the audio profiles.
final class ClassicBluetoothScanner: ObservableObject {
    struct ServiceRecord: Identifiable {
        let id = UUID()
        let name: String
        let rfcommChannel: UInt8?
    }

    struct ClassicDevice: Identifiable {
        let id: String
        let name: String
        let address: String
        let isConnected: Bool
        let isPaired: Bool
        let services: [ServiceRecord]
    }

    @Published private(set) var devices: [ClassicDevice] = []

    func refresh() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        devices = paired.map { device in
            let records = (device.services as? [IOBluetoothSDPServiceRecord] ?? []).map { record -> ServiceRecord in
                var channel: BluetoothRFCOMMChannelID = 0
                let hasChannel = record.getRFCOMMChannelID(&channel) == kIOReturnSuccess
                return ServiceRecord(
                    name: record.getServiceName() ?? "Service sans nom",
                    rfcommChannel: hasChannel ? channel : nil
                )
            }
            return ClassicDevice(
                id: device.addressString ?? UUID().uuidString,
                name: device.name ?? "Sans nom",
                address: device.addressString ?? "??",
                isConnected: device.isConnected(),
                isPaired: device.isPaired(),
                services: records
            )
        }
    }
}
