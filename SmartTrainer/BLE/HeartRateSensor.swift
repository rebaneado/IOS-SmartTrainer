import Foundation
import CoreBluetooth

enum HrConnectionState: String {
    case disconnected
    case connecting
    case connected
    case unauthorized
}

/// Standard Bluetooth SIG Heart Rate Service (0x180D) client — any BLE strap
/// (Garmin HRM, Wahoo TICKR, Polar H10). Kept independent of the trainer so
/// either can connect/drop without affecting the other.
@MainActor
final class HeartRateSensor: NSObject, ObservableObject {
    static let service = CBUUID(string: "180D")
    static let measurement = CBUUID(string: "2A37")

    @Published private(set) var state: HrConnectionState = .disconnected
    @Published private(set) var deviceName: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var listeners: [UUID: (Int) -> Void] = [:]
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var scanTimeout: Task<Void, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    @discardableResult
    func onHeartRate(_ listener: @escaping (Int) -> Void) -> () -> Void {
        let id = UUID()
        listeners[id] = listener
        return { [weak self] in self?.listeners.removeValue(forKey: id) }
    }

    func connect() async throws {
        guard central.state == .poweredOn else {
            state = central.state == .unauthorized ? .unauthorized : .disconnected
            throw FtmsError.bluetoothUnavailable
        }
        state = .connecting
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                connectContinuation = cont
                central.scanForPeripherals(withServices: [Self.service])
                scanTimeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    guard let self, !Task.isCancelled, self.state == .connecting else { return }
                    self.central.stopScan()
                    self.finishConnect(.failure(FtmsError.connectTimeout))
                }
            }
            state = .connected
        } catch {
            if let p = peripheral { central.cancelPeripheralConnection(p) }
            peripheral = nil
            state = .disconnected
            throw error
        }
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    private func finishConnect(_ result: Result<Void, Error>) {
        scanTimeout?.cancel()
        scanTimeout = nil
        guard let cont = connectContinuation else { return }
        connectContinuation = nil
        cont.resume(with: result)
    }

    private static func parse(_ data: Data) -> Int {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return 0 }
        let is16Bit = (bytes[0] & 0x01) != 0
        if is16Bit {
            guard bytes.count >= 3 else { return 0 }
            return Int(bytes[1]) | (Int(bytes[2]) << 8)
        }
        return bytes.count >= 2 ? Int(bytes[1]) : 0
    }
}

extension HeartRateSensor: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard self.peripheral == nil else { return }
            self.central.stopScan()
            self.peripheral = peripheral
            self.deviceName = peripheral.name
            peripheral.delegate = self
            self.central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in peripheral.discoverServices([Self.service]) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.finishConnect(.failure(error ?? FtmsError.noDeviceFound)) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.peripheral = nil
            self.state = .disconnected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
                self.finishConnect(.failure(FtmsError.noDeviceFound))
                return
            }
            peripheral.discoverCharacteristics([Self.measurement], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let ch = service.characteristics?.first(where: { $0.uuid == Self.measurement }) else {
                self.finishConnect(.failure(FtmsError.noDeviceFound))
                return
            }
            peripheral.setNotifyValue(true, for: ch)
            self.finishConnect(.success(()))
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        Task { @MainActor in
            let bpm = Self.parse(value)
            if bpm > 0 { for listener in self.listeners.values { listener(bpm) } }
        }
    }
}
