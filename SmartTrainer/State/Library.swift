import Foundation
import Combine

/// UserDefaults-backed workout library (survives app restarts, per-device).
@MainActor
final class Library: ObservableObject {
    @Published private(set) var workouts: [StoredWorkout] = []

    private let storageKey = "smarttrainer.library.v1"

    init() { load() }

    var folders: [String] {
        var names = [defaultFolder]
        for w in workouts where !names.contains(w.folder) { names.append(w.folder) }
        return names
    }

    func workouts(inFolder folder: String) -> [StoredWorkout] {
        workouts.filter { $0.folder == folder }
    }

    @discardableResult
    func add(_ workout: Workout, folder: String = defaultFolder) -> StoredWorkout {
        let stored = StoredWorkout(workout: workout, folder: folder)
        workouts.insert(stored, at: 0)
        persist()
        return stored
    }

    func remove(_ id: UUID) {
        workouts.removeAll { $0.id == id }
        persist()
    }

    func move(_ id: UUID, toFolder folder: String) {
        let clean = folder.trimmingCharacters(in: .whitespaces)
        guard let idx = workouts.firstIndex(where: { $0.id == id }) else { return }
        workouts[idx].folder = clean.isEmpty ? defaultFolder : clean
        persist()
    }

    func updateSteps(_ id: UUID, steps: [WorkoutStep]) {
        guard let idx = workouts.firstIndex(where: { $0.id == id }) else { return }
        workouts[idx].steps = steps
        persist()
    }

    // MARK: Export / import (JSON, for backup or moving between devices)

    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(workouts)
    }

    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([StoredWorkout].self, from: data)
        guard !imported.isEmpty else { return 0 }
        // Fresh ids so re-importing is safe (may duplicate, never collides).
        let reidentified = imported.map { w -> StoredWorkout in
            var copy = w
            copy.id = UUID()
            return copy
        }
        workouts.insert(contentsOf: reidentified, at: 0)
        persist()
        return reidentified.count
    }

    // MARK: Persistence

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(workouts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([StoredWorkout].self, from: data) {
            workouts = decoded.map { w in
                var copy = w
                if copy.folder.isEmpty { copy.folder = defaultFolder }
                return copy
            }
        }
    }
}
