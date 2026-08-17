import SwiftUI

// Heart-rate zones (BPM), configurable per-rider in Settings so the app
// carries no one person's physiology by default. These are display-only —
// workouts are driven by power, not HR — but they let the ride screen colour
// the live BPM by zone and the summary show time-in-zone.
//
// Colours are a cool→hot progression (blue → aqua → yellow → orange → red).
// The zone's number/name is always shown alongside the colour, so identity
// never rests on colour alone.

struct HrZone: Identifiable {
    let index: Int
    let name: String
    let short: String
    /// Inclusive lower bound in BPM.
    let minBpm: Int
    /// Inclusive upper bound in BPM (Int.max for the top zone).
    let maxBpm: Int
    let color: Color

    var id: Int { index }

    var rangeLabel: String {
        maxBpm == Int.max ? ">\(minBpm - 1)" : "\(minBpm)–\(maxBpm)"
    }
}

/// Built from a rider's four zone-top boundaries (Z1 top, Z2 top, Z3 top,
/// Z4 top in BPM) — Z5 is everything above Z4's top.
struct HrZones {
    let all: [HrZone]

    init(z1Top: Int, z2Top: Int, z3Top: Int, z4Top: Int) {
        all = [
            HrZone(index: 1, name: "Warm Up", short: "Z1", minBpm: 0, maxBpm: z1Top,
                   color: Color(red: 0.427, green: 0.655, blue: 0.925)),   // #6da7ec
            HrZone(index: 2, name: "Easy", short: "Z2", minBpm: z1Top + 1, maxBpm: z2Top,
                   color: Color(red: 0.106, green: 0.686, blue: 0.478)),   // #1baf7a
            HrZone(index: 3, name: "Aerobic", short: "Z3", minBpm: z2Top + 1, maxBpm: z3Top,
                   color: Color(red: 0.929, green: 0.631, blue: 0.0)),     // #eda100
            HrZone(index: 4, name: "Threshold", short: "Z4", minBpm: z3Top + 1, maxBpm: z4Top,
                   color: Color(red: 0.922, green: 0.408, blue: 0.204)),   // #eb6834
            HrZone(index: 5, name: "Maximum", short: "Z5", minBpm: z4Top + 1, maxBpm: Int.max,
                   color: Color(red: 0.890, green: 0.286, blue: 0.282)),   // #e34948
        ]
    }

    /// The zone a BPM reading falls in, or nil when there's no reading.
    func zone(for bpm: Int?) -> HrZone? {
        guard let bpm, bpm > 0 else { return nil }
        return all.first { bpm >= $0.minBpm && bpm <= $0.maxBpm } ?? all.last
    }
}
