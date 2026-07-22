import Foundation

struct RideSample {
    /// Seconds elapsed since the ride started.
    var tSec: Int
    var powerWatts: Int?
    var cadenceRpm: Double?
    var heartRateBpm: Int?
    var speedKmh: Double?
}

struct RideRecording {
    var startedAt: Date
    var workoutName: String?
    var samples: [RideSample]
}

extension RideRecording {
    var durationSec: Int { samples.last?.tSec ?? 0 }

    var avgPower: Int? {
        let vals = samples.compactMap { $0.powerWatts }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / vals.count
    }

    var maxPower: Int? { samples.compactMap { $0.powerWatts }.max() }

    var avgHeartRate: Int? {
        let vals = samples.compactMap { $0.heartRateBpm }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / vals.count
    }

    var distanceMiles: Double {
        var km = 0.0
        // Trapezoidal integration of speed (km/h) over 1s ticks.
        for i in 1..<max(1, samples.count) {
            let dt = Double(samples[i].tSec - samples[i - 1].tSec)
            let v = ((samples[i].speedKmh ?? 0) + (samples[i - 1].speedKmh ?? 0)) / 2
            km += v / 3600 * dt
        }
        return km * 0.621371
    }
}
