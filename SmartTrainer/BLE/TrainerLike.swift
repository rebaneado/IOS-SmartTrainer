import Foundation

/// The subset of trainer behavior the ERG engine needs. Both the real
/// `FtmsTrainer` (CoreBluetooth) and `SimulatedTrainer` (trial mode) conform.
/// `@MainActor` so it composes with the main-actor engine and BLE clients.
@MainActor
protocol TrainerLike: AnyObject {
    /// Registers a live-data listener; returns a cancellation closure.
    @discardableResult
    func onData(_ listener: @escaping (IndoorBikeSample) -> Void) -> () -> Void
    func requestControl() async throws
    func startResistance() async throws
    func stopResistance() async throws
    func setTargetPower(watts: Int) async throws
}
