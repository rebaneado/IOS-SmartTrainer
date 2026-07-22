import Foundation

let defaultFolder = "General"

struct StoredWorkout: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var steps: [WorkoutStep]
    var source: WorkoutSource?
    var importedAt: Date
    var folder: String

    init(workout: Workout, folder: String = defaultFolder) {
        self.id = UUID()
        self.name = workout.name
        self.steps = workout.steps
        self.source = workout.source
        self.importedAt = Date()
        self.folder = folder.trimmingCharacters(in: .whitespaces).isEmpty ? defaultFolder : folder
    }

    var workout: Workout { Workout(name: name, steps: steps, source: source) }
    var durationSec: Double { steps.reduce(0) { $0 + $1.durationSec } }
}
