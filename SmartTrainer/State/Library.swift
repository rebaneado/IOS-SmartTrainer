import Foundation
import Combine

/// UserDefaults-backed workout library (survives app restarts, per-device).
@MainActor
final class Library: ObservableObject {
    @Published private(set) var workouts: [StoredWorkout] = []

    private let storageKey = "smarttrainer.library.v1"
    private let seededKey = "smarttrainer.seededIronman2026"

    init() {
        load()
        seedBundledPlanIfNeeded()
    }

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

    // MARK: Bundled Ironman 2026 plan

    /// Shape of the bundled plan file (no id/importedAt — those are generated here).
    private struct SeedWorkout: Decodable {
        let name: String
        let steps: [WorkoutStep]
        let source: WorkoutSource?
        let folder: String?
    }

    /// On the very first launch (empty library), loads the bundled Ironman 2026
    /// plan so the workouts are already there. Runs once — if the rider later
    /// deletes workouts, it won't re-seed.
    private func seedBundledPlanIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        // Only seed into an empty library, so we never stomp on existing workouts.
        if workouts.isEmpty { loadBundledPlan() }
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Adds the bundled plan's workouts (earliest date first). Returns how many.
    @discardableResult
    func loadBundledPlan() -> Int {
        guard let url = Bundle.main.url(forResource: "ironman-2026-plan", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seeds = try? JSONDecoder().decode([SeedWorkout].self, from: data) else {
            return 0
        }
        let stored = seeds.map { seed in
            StoredWorkout(
                workout: Workout(name: seed.name, steps: seed.steps, source: seed.source),
                folder: seed.folder ?? defaultFolder
            )
        }
        workouts.insert(contentsOf: stored, at: 0)
        persist()
        return stored.count
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
