import Foundation
import Combine

enum ErgEngineStatus {
    case idle, running, paused, finished
}

/// Seconds of zero power+cadence before the ride auto-pauses itself.
private let autoPauseStillSeconds = 5

/// Drives ERG-mode execution of a structured workout: ticks once per second,
/// computes target watts for "now" (ramps via interpolation, %FTP→watts),
/// pushes changes to the trainer, records samples, and handles the manual
/// nudge, ERG on/off, auto-pause, distance, and an external HR feed.
@MainActor
final class ErgEngine: ObservableObject {
    // Published live state the ride view binds to.
    @Published private(set) var status: ErgEngineStatus = .idle
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var elapsedInStepSec = 0
    @Published private(set) var totalElapsedSec = 0
    @Published private(set) var targetWatts: Int?
    @Published private(set) var manualOffsetWatts = 0
    @Published private(set) var ergEnabled = true
    @Published private(set) var autoPaused = false
    @Published private(set) var live = IndoorBikeSample()
    @Published private(set) var totalDistanceMiles = 0.0
    @Published private(set) var sampleCount = 0

    let workout: Workout
    let ftpWatts: Double
    let totalDurationSec: Int

    private let trainer: TrainerLike
    private var samples: [RideSample] = []
    private var startedAt: Date?
    private var lastSentTargetWatts: Int?
    private var stillSeconds = 0
    private var externalHeartRateBpm: Int?
    private var latestLive = IndoorBikeSample()
    private var timer: Timer?
    private var unsubscribeData: (() -> Void)?

    init(trainer: TrainerLike, workout: Workout, ftpWatts: Double) {
        self.trainer = trainer
        self.workout = workout
        self.ftpWatts = ftpWatts
        self.totalDurationSec = Int(workout.durationSec.rounded())
    }

    var currentStep: WorkoutStep? {
        workout.steps.indices.contains(currentStepIndex) ? workout.steps[currentStepIndex] : nil
    }

    func recordedSamples() -> [RideSample] { samples }

    // MARK: Locating position in the workout

    private func locate(_ tSec: Int) -> (index: Int, elapsedInStep: Int) {
        var acc = 0
        for (i, step) in workout.steps.enumerated() {
            if Double(tSec) < Double(acc) + step.durationSec {
                return (i, tSec - acc)
            }
            acc += Int(step.durationSec)
        }
        return (workout.steps.count, 0)
    }

    private func cumulativeStart(of index: Int) -> Int {
        var acc = 0
        for i in 0..<min(index, workout.steps.count) { acc += Int(workout.steps[i].durationSec) }
        return acc
    }

    private func computeTargetWatts(step: WorkoutStep?, elapsedInStep: Int) -> Int? {
        guard let step, !step.isFreeRide else { return nil }
        let base = step.watts(value: step.power(atElapsed: Double(elapsedInStep)), ftpWatts: ftpWatts)
        return max(0, Int((base + Double(manualOffsetWatts)).rounded()))
    }

    private func liveWithExternalHR() -> IndoorBikeSample {
        guard let bpm = externalHeartRateBpm else { return latestLive }
        var s = latestLive
        s.heartRateBpm = bpm
        return s
    }

    // MARK: External inputs

    func setExternalHeartRate(_ bpm: Int?) {
        externalHeartRateBpm = bpm
    }

    func nudgeTarget(_ deltaWatts: Int) {
        manualOffsetWatts += deltaWatts
        refreshPublished()
        // Push the new target immediately rather than waiting for the next
        // 1s tick, so the nudge buttons feel instant.
        guard ergEnabled, let target = targetWatts, target != lastSentTargetWatts else { return }
        lastSentTargetWatts = target
        Task {
            do {
                try await trainer.setTargetPower(watts: target)
            } catch {
                print("ERG: nudge setTargetPower(\(target)W) failed: \(error)")
            }
        }
    }

    func setErgEnabled(_ enabled: Bool) async {
        guard enabled != ergEnabled else { return }
        ergEnabled = enabled
        do {
            if enabled {
                try await trainer.startResistance()
                lastSentTargetWatts = nil // force resend on next tick
            } else {
                try await trainer.stopResistance()
            }
        } catch {
            print("Failed to toggle ERG mode: \(error)")
        }
        refreshPublished()
    }

    // MARK: Lifecycle

    func start() async throws {
        startedAt = Date()
        totalElapsedSec = 0
        samples = []
        lastSentTargetWatts = nil
        totalDistanceMiles = 0
        stillSeconds = 0
        autoPaused = false
        status = .running

        unsubscribeData = trainer.onData { [weak self] sample in
            guard let self else { return }
            self.latestLive = sample
            // Subscription stays live through a pause, so resumed pedaling can
            // lift an auto-pause even while the tick loop is stopped.
            if self.autoPaused && ((sample.powerWatts ?? 0) > 0 || (sample.cadenceRpm ?? 0) > 0) {
                self.resume()
            }
        }

        try await trainer.requestControl()
        try await trainer.startResistance()

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        guard status == .running else { return }
        status = .paused
        timer?.invalidate()
        timer = nil
        Task { try? await trainer.stopResistance() }
        refreshPublished()
    }

    func resume() {
        guard status == .paused else { return }
        autoPaused = false
        status = .running
        Task { try? await trainer.startResistance() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        refreshPublished()
    }

    func skipStep() {
        let (index, _) = locate(totalElapsedSec)
        totalElapsedSec = cumulativeStart(of: min(index + 1, workout.steps.count))
        tick()
    }

    func stop() async -> RideRecording {
        timer?.invalidate()
        timer = nil
        unsubscribeData?()
        unsubscribeData = nil
        status = .finished
        try? await trainer.stopResistance()
        refreshPublished()
        return RideRecording(
            startedAt: startedAt ?? Date(),
            workoutName: workout.name,
            samples: samples
        )
    }

    // MARK: Tick

    private func tick() {
        let (index, elapsedInStep) = locate(totalElapsedSec)

        if index >= workout.steps.count {
            Task { _ = await stop() }
            return
        }

        let step = workout.steps[index]
        if ergEnabled && !step.isFreeRide {
            if let target = computeTargetWatts(step: step, elapsedInStep: elapsedInStep), target != lastSentTargetWatts {
                lastSentTargetWatts = target
                print("ERG: sending target power \(target)W for step \(index) at \(elapsedInStep)s elapsed")
                Task {
                    do {
                        try await trainer.setTargetPower(watts: target)
                        print("ERG: target power \(target)W confirmed by trainer")
                    } catch {
                        print("ERG: setTargetPower(\(target)W) failed: \(error)")
                    }
                }
            }
        }

        samples.append(RideSample(
            tSec: totalElapsedSec,
            powerWatts: latestLive.powerWatts,
            cadenceRpm: latestLive.cadenceRpm,
            heartRateBpm: externalHeartRateBpm ?? latestLive.heartRateBpm,
            speedKmh: latestLive.speedKmh
        ))

        let isStill = (latestLive.powerWatts ?? 0) == 0 && (latestLive.cadenceRpm ?? 0) == 0
        if isStill {
            stillSeconds += 1
            if stillSeconds >= autoPauseStillSeconds {
                stillSeconds = 0
                autoPaused = true
                pause() // refreshes on its own
                return
            }
        } else {
            stillSeconds = 0
        }

        if status == .running {
            if let speed = latestLive.speedKmh {
                totalDistanceMiles += (speed / 3600) * 0.621371
            }
            totalElapsedSec += 1
        }

        refreshPublished()
    }

    private func refreshPublished() {
        let (index, elapsedInStep) = locate(totalElapsedSec)
        currentStepIndex = index
        elapsedInStepSec = elapsedInStep
        let step = workout.steps.indices.contains(index) ? workout.steps[index] : nil
        targetWatts = computeTargetWatts(step: step, elapsedInStep: elapsedInStep)
        live = liveWithExternalHR()
        sampleCount = samples.count
    }
}
