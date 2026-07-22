import Foundation

enum PowerUnit: String, Codable {
    case pctFtp
    case watts
}

enum WorkoutSource: String, Codable {
    case zwo
    case erg
    case fit
}

/// A single block of a structured workout.
struct WorkoutStep: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String?
    var durationSec: Double
    /// Target power at the start of the step. Unit is given by `powerUnit`.
    var powerLow: Double
    /// Target power at the end of the step. Equal to `powerLow` for steady steps.
    var powerHigh: Double
    /// `.pctFtp` (fraction where 1.0 == 100% FTP) or `.watts` (absolute).
    var powerUnit: PowerUnit = .pctFtp
    var cadenceTarget: Double?
    /// Free ride / open step: rider controls resistance, no ERG target is pushed.
    var isFreeRide: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, durationSec, powerLow, powerHigh, powerUnit, cadenceTarget, isFreeRide
    }

    init(
        id: UUID = UUID(),
        name: String? = nil,
        durationSec: Double,
        powerLow: Double,
        powerHigh: Double,
        powerUnit: PowerUnit = .pctFtp,
        cadenceTarget: Double? = nil,
        isFreeRide: Bool = false
    ) {
        self.id = id
        self.name = name
        self.durationSec = durationSec
        self.powerLow = powerLow
        self.powerHigh = powerHigh
        self.powerUnit = powerUnit
        self.cadenceTarget = cadenceTarget
        self.isFreeRide = isFreeRide
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name)
        durationSec = try c.decode(Double.self, forKey: .durationSec)
        powerLow = try c.decode(Double.self, forKey: .powerLow)
        powerHigh = try c.decode(Double.self, forKey: .powerHigh)
        powerUnit = try c.decodeIfPresent(PowerUnit.self, forKey: .powerUnit) ?? .pctFtp
        cadenceTarget = try c.decodeIfPresent(Double.self, forKey: .cadenceTarget)
        isFreeRide = try c.decodeIfPresent(Bool.self, forKey: .isFreeRide) ?? false
    }
}

struct Workout: Codable, Equatable {
    var name: String
    var steps: [WorkoutStep]
    var source: WorkoutSource?
}

extension Workout {
    var durationSec: Double {
        steps.reduce(0) { $0 + $1.durationSec }
    }
}

extension WorkoutStep {
    /// Linear power interpolation within a step, given seconds elapsed since it started. Same unit as the step.
    func power(atElapsed elapsedSec: Double) -> Double {
        guard durationSec > 0 else { return powerLow }
        let t = min(1, max(0, elapsedSec / durationSec))
        return powerLow + (powerHigh - powerLow) * t
    }

    /// Converts a step's power value to target watts given the athlete's FTP.
    func watts(value: Double, ftpWatts: Double) -> Double {
        powerUnit == .watts ? value : value * ftpWatts
    }

    /// Same-unit power fraction of FTP, for visual/comparative purposes (chart intensity color).
    func powerFraction(value: Double, ftpWatts: Double) -> Double {
        powerUnit == .watts ? value / ftpWatts : value
    }

    /// Human-readable target, e.g. "88% FTP (176W)" or "175→196W (88→98% FTP)".
    func formatTarget(ftpWatts: Double) -> String {
        if isFreeRide { return "Free ride" }
        let wattsLow = Int(watts(value: powerLow, ftpWatts: ftpWatts).rounded())
        let wattsHigh = Int(watts(value: powerHigh, ftpWatts: ftpWatts).rounded())
        let pctLow = Int((powerFraction(value: powerLow, ftpWatts: ftpWatts) * 100).rounded())
        let pctHigh = Int((powerFraction(value: powerHigh, ftpWatts: ftpWatts) * 100).rounded())

        if powerUnit == .watts {
            return wattsLow == wattsHigh
                ? "\(wattsLow)W (\(pctLow)% FTP)"
                : "\(wattsLow)→\(wattsHigh)W (\(pctLow)→\(pctHigh)% FTP)"
        }
        return pctLow == pctHigh
            ? "\(pctLow)% FTP (\(wattsLow)W)"
            : "\(pctLow)→\(pctHigh)% FTP (\(wattsLow)→\(wattsHigh)W)"
    }

    /// Compact watts-only target, e.g. "176W" or "150→180W" — for tight spaces like an upcoming-steps list.
    func formatWattsShort(ftpWatts: Double) -> String {
        if isFreeRide { return "free ride" }
        let wattsLow = Int(watts(value: powerLow, ftpWatts: ftpWatts).rounded())
        let wattsHigh = Int(watts(value: powerHigh, ftpWatts: ftpWatts).rounded())
        return wattsLow == wattsHigh ? "\(wattsLow)W" : "\(wattsLow)→\(wattsHigh)W"
    }
}

enum TimeFormat {
    /// Hour-aware clock: "5:03" or "1:05:03".
    static func clock(_ totalSeconds: Double) -> String {
        let s = Int(max(0, totalSeconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
}
