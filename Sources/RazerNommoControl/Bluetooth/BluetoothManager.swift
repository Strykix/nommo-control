import Combine
import CoreBluetooth
import Foundation

/// Drives CoreBluetooth. All delegate callbacks are delivered on the main queue
/// (`CBCentralManager` is created with a nil queue), so published state is safe to
/// mutate directly from them.
final class BluetoothManager: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var services: [ServiceNode] = []
    @Published private(set) var connectedPeripheral: CBPeripheral?
    @Published private(set) var isScanning = false
    @Published private(set) var log: [LogEntry] = []
    @Published var onlyRazerDevices = true

    private var central: CBCentralManager!
    private var subscribed: Set<String> = []

    private static let logLimit = 500

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var stateDescription: String {
        switch state {
        case .poweredOn: return "Bluetooth actif"
        case .poweredOff: return "Bluetooth désactivé"
        case .unauthorized: return "Autorisation Bluetooth refusée"
        case .unsupported: return "Bluetooth non supporté"
        case .resetting: return "Réinitialisation…"
        default: return "État inconnu"
        }
    }

    var visibleDevices: [DiscoveredDevice] {
        let list = onlyRazerDevices ? devices.filter(\.looksLikeRazer) : devices
        return list.sorted { $0.rssi > $1.rssi }
    }

    // MARK: - Scanning

    func startScan() {
        guard state == .poweredOn else {
            append(.error, "Impossible de scanner : \(stateDescription)")
            return
        }
        devices.removeAll()
        // allowDuplicates keeps RSSI fresh, which helps locate the right speaker.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        append(.info, "Scan BLE démarré")
    }

    func stopScan() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        append(.info, "Scan arrêté")
    }

    // MARK: - Connection

    func connect(_ device: DiscoveredDevice) {
        stopScan()
        disconnect()
        append(.info, "Connexion à \(device.name)…")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Characteristic I/O

    func write(_ data: Data, to node: CharacteristicNode, withResponse: Bool, fragment: Bool = true) {
        guard let peripheral = connectedPeripheral else {
            append(.error, "Aucun appareil connecté")
            return
        }
        let supportsWithResponse = node.characteristic.properties.contains(.write)
        let supportsWithoutResponse = node.characteristic.properties.contains(.writeWithoutResponse)
        guard supportsWithResponse || supportsWithoutResponse else {
            append(.error, "\(node.uuidString) n'accepte aucune écriture")
            return
        }
        // Fall back to whichever write type the characteristic actually offers: Razer's
        // BLE command channel is write-without-response only, and refusing the write
        // there would close the one command path the speaker exposes.
        let useResponse = withResponse ? supportsWithResponse : !supportsWithoutResponse
        let type: CBCharacteristicWriteType = useResponse ? .withResponse : .withoutResponse
        if useResponse != withResponse {
            append(.info, "\(short(node.characteristic.uuid)) : bascule en écriture \(useResponse ? "avec" : "sans") réponse")
        }

        // A 90-byte Razer frame does not fit in a default ATT MTU, so split it unless
        // the caller wants the frame delivered whole.
        let limit = peripheral.maximumWriteValueLength(for: type)
        let chunks: [Data] = (fragment && data.count > limit)
            ? stride(from: 0, to: data.count, by: limit).map { offset in
                data.subdata(in: offset..<min(offset + limit, data.count))
            }
            : [data]

        if chunks.count > 1 {
            append(.info, "Trame de \(data.count) o fragmentée en \(chunks.count) écritures (MTU \(limit) o)")
        }
        for chunk in chunks {
            peripheral.writeValue(chunk, for: node.characteristic, type: type)
            append(.tx, "\(short(node.characteristic.uuid)) ← \(Hex.encode(chunk))")
        }
    }

    func read(_ node: CharacteristicNode) {
        guard let peripheral = connectedPeripheral else { return }
        peripheral.readValue(for: node.characteristic)
    }

    func toggleNotify(_ node: CharacteristicNode) {
        guard let peripheral = connectedPeripheral else { return }
        let enabled = !node.characteristic.isNotifying
        peripheral.setNotifyValue(enabled, for: node.characteristic)
        append(.info, "Notifications \(enabled ? "activées" : "désactivées") sur \(short(node.characteristic.uuid))")
    }

    /// Every writable characteristic on the device, for the lighting panel's target picker.
    var writableCharacteristics: [CharacteristicNode] {
        services.flatMap(\.characteristics).filter(\.isWritable)
    }

    // MARK: - Log

    func append(_ kind: LogEntry.Kind, _ message: String) {
        log.append(LogEntry(kind: kind, message: message))
        if log.count > Self.logLimit {
            log.removeFirst(log.count - Self.logLimit)
        }
    }

    func clearLog() {
        log.removeAll()
    }

    func logAsText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return log
            .map { "\(formatter.string(from: $0.date)) \($0.prefix) \($0.message)" }
            .joined(separator: "\n")
    }

    private func short(_ uuid: CBUUID) -> String {
        uuid.uuidString
    }

    private func resetConnectionState() {
        connectedPeripheral = nil
        services = []
        subscribed = []
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        append(.info, stateDescription)
        if state != .poweredOn {
            isScanning = false
            resetConnectionState()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Sans nom"
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        if let index = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[index].rssi = RSSI.intValue
            devices[index].lastSeen = Date()
            devices[index].name = name
            if let manufacturer { devices[index].manufacturerData = manufacturer }
        } else {
            let device = DiscoveredDevice(
                id: peripheral.identifier,
                peripheral: peripheral,
                name: name,
                rssi: RSSI.intValue,
                lastSeen: Date(),
                manufacturerData: manufacturer
            )
            devices.append(device)
            if device.looksLikeRazer {
                append(.info, "Appareil Razer probable détecté : \(name)")
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        services = []
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        append(.info, "Connecté à \(peripheral.name ?? peripheral.identifier.uuidString)")
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        append(.error, "Échec de connexion : \(error?.localizedDescription ?? "raison inconnue")")
        resetConnectionState()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if let error {
            append(.error, "Déconnecté : \(error.localizedDescription)")
        } else {
            append(.info, "Déconnecté")
        }
        resetConnectionState()
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            append(.error, "Découverte des services : \(error.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] {
            services.append(ServiceNode(id: service.uuid.uuidString, service: service, characteristics: []))
            peripheral.discoverCharacteristics(nil, for: service)
        }
        append(.info, "\(services.count) service(s) découvert(s)")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            append(.error, "Découverte des caractéristiques : \(error.localizedDescription)")
            return
        }
        guard let index = services.firstIndex(where: { $0.service === service }) else { return }
        let nodes = (service.characteristics ?? []).map { characteristic in
            CharacteristicNode(
                id: "\(service.uuid.uuidString)/\(characteristic.uuid.uuidString)",
                characteristic: characteristic,
                lastValue: characteristic.value
            )
        }
        services[index].characteristics = nodes

        append(.info, "Service \(short(service.uuid))")
        for node in nodes {
            let marker = node.isRazerCommandChannel ? "  <<< canal Razer" : ""
            append(.info, "   \(short(node.characteristic.uuid)) [\(node.propertyLabels.joined(separator: " "))]\(marker)")
            // Razer answers every command with a status frame. Without this subscription
            // the reply never surfaces, and an accepted frame looks exactly like a
            // rejected one.
            if node.characteristic.properties.contains(.notify)
                || node.characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: node.characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            append(.error, "Lecture \(short(characteristic.uuid)) : \(error.localizedDescription)")
            return
        }
        let value = characteristic.value ?? Data()
        for (serviceIndex, service) in services.enumerated() {
            guard let charIndex = service.characteristics.firstIndex(where: { $0.characteristic === characteristic })
            else { continue }
            services[serviceIndex].characteristics[charIndex].lastValue = value
        }
        append(.rx, "\(short(characteristic.uuid)) → \(Hex.encode(value))")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            append(.error, "Écriture \(short(characteristic.uuid)) : \(error.localizedDescription)")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            append(.error, "Notifications \(short(characteristic.uuid)) : \(error.localizedDescription)")
        } else {
            // Logged on success too: without it, an absent reply is indistinguishable
            // from a subscription that never took effect.
            let state = characteristic.isNotifying ? "activées" : "désactivées"
            append(.info, "Notifications \(state) sur \(short(characteristic.uuid))")
        }
    }
}
