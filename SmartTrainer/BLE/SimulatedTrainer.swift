import Foundation

/// A fake trainer for "trial mode" — lets someone preview a workout with no
/// hardware. Generates plausible power/cadence/HR/speed numbers that track the
/// ERG engine's target.
@MainActor
final class SimulatedTrainer: TrainerLike {
    private var listeners: [UUID: (IndoorBikeSample) -> Void] = [:]
    private var targetWatts = 0
    private var simulatedHr = 95.0
    private var timer: Timer?

    @discardableResult
    func onData(_ listener: @escaping (IndoorBikeSample) -> Void) -> () -> Void {
        let id = UUID()
        listeners[id] = listener
        return { [weak self] in self?.listeners.removeValue(forKey: id) }
    }

    func requestControl() async throws {}

    func startResistance() async throws {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stopResistance() async throws {
        timer?.invalidate()
        timer = nil
    }

    func setTargetPower(watts: Int) async throws {
        targetWatts = watts
    }

    private func tick() {
        let power = targetWatts > 0
            ? max(0, Double(targetWatts) + Double.random(in: -8...8))
            : 90 + Double.random(in: 0...40)
        let cadence = power > 10 ? 85 + Double.random(in: 0...10) : 0
        let targetHr = min(185, max(90, 100 + power * 0.35))
        simulatedHr += (targetHr - simulatedHr) * 0.1
        let speedKmh = min(45, max(10, 15 + power * 0.09 + Double.random(in: -1...1)))

        let sample = IndoorBikeSample(
            speedKmh: speedKmh,
            cadenceRpm: cadence.rounded(),
            powerWatts: Int(power.rounded()),
            heartRateBpm: Int(simulatedHr.rounded())
        )
        for listener in listeners.values { listener(sample) }
    }
}
