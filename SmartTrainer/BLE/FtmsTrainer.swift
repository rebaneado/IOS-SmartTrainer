import Foundation
import CoreBluetooth
import Combine

enum TrainerConnectionState: String {
    case disconnected
    case connecting
    case connected
    case unauthorized // Bluetooth permission denied / powered off
}

// Bluetooth SIG Fitness Machine Service (FTMS) constants.
enum FTMS {
    static let service = CBUUID(string: "1826")
    static let indoorBikeData = CBUUID(string: "2AD2")
    static let controlPoint = CBUUID(string: "2AD9")

    enum OpCode: UInt8 {
        case requestControl = 0x00
        case setTargetPower = 0x05
        case startOrResume = 0x07
        case stopOrPause = 0x08
        case responseCode = 0x80
    }

    enum ResultCode: UInt8 {
        case success = 0x01
        case opCodeNotSupported = 0x02
        case invalidParameter = 0x03
        case operationFailed = 0x04
        case controlNotPermitted = 0x05

        var name: String {
            switch self {
            case .success: return "success"
            case .opCodeNotSupported: return "opCodeNotSupported"
            case .invalidParameter: return "invalidParameter"
            case .operationFailed: return "operationFailed"
            case .controlNotPermitted: return "controlNotPermitted"
            }
        }
    }
}

enum FtmsError: LocalizedError {
    case notConnected
    case bluetoothUnavailable
    case controlPointTimeout(UInt8)
    case unexpectedResponse
    case controlFailed(op: UInt8, result: String)
    case connectTimeout
    case noDeviceFound

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Trainer not connected."
        case .bluetoothUnavailable: return "Bluetooth is off or not permitted. Enable it in Settings."
        case .controlPointTimeout(let op): return "Trainer command 0x\(String(op, radix: 16)) timed out."
        case .unexpectedResponse: return "Unexpected response from the trainer."
        case .controlFailed(let op, let result): return "Trainer command 0x\(String(op, radix: 16)) failed: \(result)"
        case .connectTimeout: return "Connecting to the trainer timed out after 20s."
        case .noDeviceFound: return "No FTMS trainer found nearby. Make sure it's powered on and awake."
        }
    }
}

/// CoreBluetooth client for an FTMS smart trainer. Exposes
/// ERG-mode control (target power) plus live power/cadence/speed/HR data.
/// `@MainActor` so all published state and listener callbacks land on the main
/// thread, safe to bind directly from SwiftUI.
@MainActor
final class FtmsTrainer: NSObject, ObservableObject, TrainerLike {
    @Published private(set) var state: TrainerConnectionState = .disconnected
    @Published private(set) var deviceName: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlPoint: CBCharacteristic?
    private var dataListeners: [UUID: (IndoorBikeSample) -> Void] = [:]

    private var hasControl = false
    private var pendingControl: CheckedContinuation<Data, Error>?
    private var pendingControlOp: UInt8?
    private var scanTimeout: Task<Void, Never>?

    // Bridges the async connect() call to the CoreBluetooth delegate callbacks.
    private var connectContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    @discardableResult
    func onData(_ listener: @escaping (IndoorBikeSample) -> Void) -> () -> Void {
        let id = UUID()
        dataListeners[id] = listener
        return { [weak self] in self?.dataListeners.removeValue(forKey: id) }
    }

    // MARK: Connection

    /// Scans for and connects to the first FTMS trainer found. 20s overall timeout.
    func connect() async throws {
        guard central.state == .poweredOn else {
            state = central.state == .unauthorized ? .unauthorized : .disconnected
            throw FtmsError.bluetoothUnavailable
        }
        state = .connecting
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                connectContinuation = cont
                central.scanForPeripherals(withServices: [FTMS.service])
                scanTimeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    guard let self, !Task.isCancelled else { return }
                    if self.state == .connecting {
                        self.central.stopScan()
                        self.finishConnect(.failure(FtmsError.connectTimeout))
                    }
                }
            }
            state = .connected
        } catch {
            cleanupAfterFailure()
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

    private func cleanupAfterFailure() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        controlPoint = nil
        hasControl = false
        state = .disconnected
    }

    // MARK: Control point commands

    private func send(_ op: FTMS.OpCode, payload: [UInt8] = []) async throws {
        guard let cp = controlPoint, let peripheral else { throw FtmsError.notConnected }
        var bytes: [UInt8] = [op.rawValue]
        bytes.append(contentsOf: payload)

        let response: Data = try await withCheckedThrowingContinuation { cont in
            pendingControl = cont
            pendingControlOp = op.rawValue
            peripheral.writeValue(Data(bytes), for: cp, type: .withResponse)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, let pending = self.pendingControl, self.pendingControlOp == op.rawValue else { return }
                self.pendingControl = nil
                self.pendingControlOp = nil
                pending.resume(throwing: FtmsError.controlPointTimeout(op.rawValue))
            }
        }

        let responseBytes = [UInt8](response)
        guard responseBytes.count >= 3,
              responseBytes[0] == FTMS.OpCode.responseCode.rawValue,
              responseBytes[1] == op.rawValue else {
            throw FtmsError.unexpectedResponse
        }
        let result = FTMS.ResultCode(rawValue: responseBytes[2])
        if result != .success {
            throw FtmsError.controlFailed(op: op.rawValue, result: result?.name ?? "unknown(0x\(String(responseBytes[2], radix: 16)))")
        }
    }

    func requestControl() async throws {
        try await send(.requestControl)
        hasControl = true
    }

    func startResistance() async throws {
        try await ensureControl()
        try await send(.startOrResume)
    }

    func stopResistance() async throws {
        try await ensureControl()
        try await send(.stopOrPause, payload: [0x01])
    }

    func setTargetPower(watts: Int) async throws {
        try await ensureControl()
        let clamped = Int16(max(0, min(watts, Int(Int16.max))))
        let payload = [UInt8(truncatingIfNeeded: clamped), UInt8(truncatingIfNeeded: clamped >> 8)]
        try await send(.setTargetPower, payload: payload)
    }

    private func ensureControl() async throws {
        if !hasControl { try await requestControl() }
    }
}

// CoreBluetooth delegates hop to the main actor since the manager runs on the main queue.
extension FtmsTrainer: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state != .poweredOn, self.state == .connected || self.state == .connecting {
                self.cleanupAfterFailure()
            }
        }
    }

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
        Task { @MainActor in
            peripheral.discoverServices([FTMS.service])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.finishConnect(.failure(error ?? FtmsError.noDeviceFound))
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.hasControl = false
            self.controlPoint = nil
            self.peripheral = nil
            self.state = .disconnected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == FTMS.service }) else {
                self.finishConnect(.failure(FtmsError.noDeviceFound))
                return
            }
            peripheral.discoverCharacteristics([FTMS.indoorBikeData, FTMS.controlPoint], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            for ch in service.characteristics ?? [] {
                if ch.uuid == FTMS.indoorBikeData {
                    peripheral.setNotifyValue(true, for: ch)
                } else if ch.uuid == FTMS.controlPoint {
                    self.controlPoint = ch
                    peripheral.setNotifyValue(true, for: ch)
                }
            }
            // Both characteristics found → connection is usable.
            if self.controlPoint != nil {
                self.finishConnect(.success(()))
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let value = characteristic.value else { return }
        let uuid = characteristic.uuid
        Task { @MainActor in
            if uuid == FTMS.indoorBikeData {
                let sample = IndoorBikeDataParser.parse(value)
                for listener in self.dataListeners.values { listener(sample) }
            } else if uuid == FTMS.controlPoint {
                if let pending = self.pendingControl {
                    self.pendingControl = nil
                    self.pendingControlOp = nil
                    pending.resume(returning: value)
                }
            }
        }
    }
}
