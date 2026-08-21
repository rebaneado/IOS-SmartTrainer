import SwiftUI
import UIKit

enum AppScreen: Equatable {
    case dashboard
    case ride
    case summary
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: AppScreen = .dashboard
    @Published var engine: ErgEngine?
    @Published var activeWorkout: StoredWorkout?
    @Published var isTrial = false
    @Published var lastRecording: RideRecording?
    @Published var errorMessage: String?

    let trainer = FtmsTrainer()
    let hrSensor = HeartRateSensor()
    let library = Library()
    let settings = Settings()
    let stravaAuth = StravaAuth()
    private let workoutRuntime = WorkoutRuntime()

    private var hrUnsub: (() -> Void)?

    init() {
        // Feed HR readings into whichever engine is currently active.
        hrUnsub = hrSensor.onHeartRate { [weak self] bpm in
            self?.engine?.setExternalHeartRate(bpm)
        }
    }

    func connectTrainer() async {
        errorMessage = nil
        do { try await trainer.connect() }
        catch { errorMessage = error.localizedDescription }
    }

    func connectHr() async {
        errorMessage = nil
        do { try await hrSensor.connect() }
        catch { errorMessage = error.localizedDescription }
    }

    func start(_ stored: StoredWorkout) async {
        errorMessage = nil
        let trial = trainer.state != .connected
        let trainerLike: TrainerLike = trial ? SimulatedTrainer() : trainer
        let engine = ErgEngine(trainer: trainerLike, workout: stored.workout, ftpWatts: Double(settings.ftpWatts))
        do {
            try await engine.start()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        engine.onStatusChanged = { [weak self] status in
            self?.workoutRuntime.update(for: status)
        }
        self.engine = engine
        activeWorkout = stored
        isTrial = trial
        screen = .ride
        workoutRuntime.start()
    }

    func finishRide(_ recording: RideRecording) {
        workoutRuntime.end()
        engine?.onStatusChanged = nil
        engine = nil
        lastRecording = recording
        screen = .summary
    }

    func doneSummary() {
        workoutRuntime.end()
        lastRecording = nil
        activeWorkout = nil
        screen = .dashboard
    }
}

struct RootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.screen {
                case .dashboard:
                    DashboardView(model: model)
                case .ride:
                    if let engine = model.engine {
                        RideView(engine: engine, isTrial: model.isTrial, hrZones: model.settings.hrZones) { recording in
                            model.finishRide(recording)
                        }
                    }
                case .summary:
                    if let recording = model.lastRecording {
                        SummaryView(recording: recording, ftpWatts: model.settings.ftpWatts,
                                    hrZones: model.settings.hrZones, stravaAuth: model.stravaAuth) {
                            model.doneSummary()
                        }
                    }
                }
            }
            .navigationTitle("SmartTrainer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: updateIdleTimer)
        .onChange(of: model.screen) { _ in
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// An active ride is the one place where the screen needs to stay awake so
    /// the rider can see power, targets, and safety controls without tapping.
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = model.screen == .ride
    }
}
