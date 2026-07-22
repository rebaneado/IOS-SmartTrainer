import Foundation

struct GroupedStep: Identifiable {
    let id = UUID()
    /// The repeating block (length 1 for a plain step, 2+ for an on/off pair).
    let steps: [WorkoutStep]
    let count: Int
}

enum GroupSteps {
    private static func stepsEqual(_ a: WorkoutStep, _ b: WorkoutStep) -> Bool {
        a.durationSec == b.durationSec &&
        a.powerLow == b.powerLow &&
        a.powerHigh == b.powerHigh &&
        a.powerUnit == b.powerUnit &&
        a.isFreeRide == b.isFreeRide &&
        a.name == b.name
    }

    private static func blocksEqual(_ a: ArraySlice<WorkoutStep>, _ b: [WorkoutStep]) -> Bool {
        guard a.count == b.count else { return false }
        for (offset, s) in a.enumerated() where !stepsEqual(s, b[offset]) { return false }
        return true
    }

    /// Collapses repeated runs of steps into grouped rows for a readable
    /// interval summary — e.g. 8 flattened on/off steps become one "4x" row.
    /// Prefers the smallest repeating block so "4x(on,off)" wins over
    /// "2x(on,off,on,off)".
    static func group(_ steps: [WorkoutStep], maxBlockLen: Int = 4) -> [GroupedStep] {
        var groups: [GroupedStep] = []
        var i = 0

        while i < steps.count {
            var chosenBlockLen = 1
            var chosenCount = 1
            let upperBound = min(maxBlockLen, steps.count - i)

            for blockLen in 1...max(1, upperBound) {
                let block = Array(steps[i..<(i + blockLen)])
                var count = 1
                var j = i + blockLen
                while j + blockLen <= steps.count && blocksEqual(steps[j..<(j + blockLen)], block) {
                    count += 1
                    j += blockLen
                }
                if count > 1 {
                    chosenBlockLen = blockLen
                    chosenCount = count
                    break
                }
            }

            groups.append(GroupedStep(steps: Array(steps[i..<(i + chosenBlockLen)]), count: chosenCount))
            i += chosenBlockLen * chosenCount
        }

        return groups
    }
}
