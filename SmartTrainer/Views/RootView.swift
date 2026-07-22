import SwiftUI

enum AppScreen {
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
        self.engine = engine
        activeWorkout = stored
        isTrial = trial
        screen = .ride
    }

    func finishRide(_ recording: RideRecording) {
        engine = nil
        lastRecording = recording
        screen = .summary
    }

    func doneSummary() {
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
                        RideView(engine: engine, isTrial: model.isTrial) { recording in
                            model.finishRide(recording)
                        }
                    }
                case .summary:
                    if let recording = model.lastRecording {
                        SummaryView(recording: recording, ftpWatts: model.settings.ftpWatts) {
                            model.doneSummary()
                        }
                    }
                }
            }
            .navigationTitle("SmartTrainer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
