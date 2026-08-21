import Foundation
import HealthKit

/// Keeps an active indoor ride eligible for iOS workout background execution.
///
/// The app's own ride recording remains the source of truth. HealthKit is used
/// only for the temporary system workout session and its builder is discarded
/// when the rider ends the workout, so SmartTrainer does not save a Health
/// workout record.
@MainActor
final class WorkoutRuntime: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var desiredStatus: ErgEngineStatus = .idle
    private var isRequestInFlight = false

    func start() {
        desiredStatus = .running
        startSessionIfSupported()
    }

    func update(for status: ErgEngineStatus) {
        desiredStatus = status

        guard #available(iOS 26.0, *) else { return }
        guard let session else {
            if status == .running { startSessionIfSupported() }
            return
        }

        synchronize(session)
    }

    func end() {
        update(for: .finished)
    }

    private func startSessionIfSupported() {
        guard #available(iOS 26.0, *) else { return }
        guard HKHealthStore.isHealthDataAvailable(), session == nil, !isRequestInFlight else { return }

        isRequestInFlight = true
        Task { @MainActor [weak self] in
            await self?.requestAuthorizationAndStart()
        }
    }

    /// iPhone workout-session background execution is available in iOS 26.
    /// Authorization is intentionally limited to the workout type; the
    /// associated builder is discarded rather than saved at the end of a ride.
    @available(iOS 26.0, *)
    private func requestAuthorizationAndStart() async {
        defer { isRequestInFlight = false }

        do {
            let workoutType = HKObjectType.workoutType()
            try await healthStore.requestAuthorization(toShare: [workoutType], read: [])

            guard desiredStatus != .finished, session == nil else { return }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .cycling
            configuration.locationType = .indoor

            let workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            workoutSession.delegate = self
            session = workoutSession

            let startDate = Date()
            let builder = workoutSession.associatedWorkoutBuilder()
            workoutSession.prepare()
            workoutSession.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
        } catch {
#if DEBUG
            print("HealthKit workout session did not start: \(error.localizedDescription)")
#endif
            if let session {
                desiredStatus = .finished
                synchronize(session)
            }
        }
    }

    @available(iOS 26.0, *)
    private func synchronize(_ workoutSession: HKWorkoutSession) {
        switch desiredStatus {
        case .running:
            if workoutSession.state == .paused { workoutSession.resume() }

        case .paused:
            if workoutSession.state == .running { workoutSession.pause() }

        case .finished, .idle:
            switch workoutSession.state {
            case .running:
                workoutSession.stopActivity(with: Date())
            case .paused:
                // A session must be active before it can be stopped cleanly.
                workoutSession.resume()
            case .stopped:
                workoutSession.associatedWorkoutBuilder().discardWorkout()
                workoutSession.end()
            case .ended:
                session = nil
            case .notStarted, .prepared:
                workoutSession.end()
            @unknown default:
                workoutSession.end()
            }
        }
    }

    @available(iOS 26.0, *)
    private func sessionDidChange(
        _ workoutSession: HKWorkoutSession,
        to state: HKWorkoutSessionState
    ) {
        guard session === workoutSession else { return }

        if state == .ended {
            session = nil
            return
        }

        synchronize(workoutSession)
    }

    @available(iOS 26.0, *)
    private func sessionDidFail(_ workoutSession: HKWorkoutSession, error: Error) {
#if DEBUG
        print("HealthKit workout session failed: \(error.localizedDescription)")
#endif
        guard session === workoutSession else { return }
        session = nil
    }
}

extension WorkoutRuntime: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard #available(iOS 26.0, *) else { return }
        Task { @MainActor [weak self] in
            self?.sessionDidChange(workoutSession, to: toState)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        guard #available(iOS 26.0, *) else { return }
        Task { @MainActor [weak self] in
            self?.sessionDidFail(workoutSession, error: error)
        }
    }
}
