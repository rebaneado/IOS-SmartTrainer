import Foundation

/// A single live sample decoded from FTMS Indoor Bike Data (or synthesized in trial mode).
struct IndoorBikeSample {
    var speedKmh: Double?
    var cadenceRpm: Double?
    var powerWatts: Int?
    var heartRateBpm: Int?
    var elapsedTimeSec: Int?
}

// Parses the FTMS "Indoor Bike Data" (0x2AD2) notification payload.
// Field presence is flag-driven, and every present field must be walked in
// spec order even when unused, since later field offsets depend on it.
enum IndoorBikeDataParser {
    private enum Flag {
        static let moreData = 1 << 0 // inverted: 0 means Instantaneous Speed IS present
        static let avgSpeed = 1 << 1
        static let instCadence = 1 << 2
        static let avgCadence = 1 << 3
        static let totalDistance = 1 << 4
        static let resistanceLevel = 1 << 5
        static let instPower = 1 << 6
        static let avgPower = 1 << 7
        static let expendedEnergy = 1 << 8
        static let heartRate = 1 << 9
        static let metabolicEquivalent = 1 << 10
        static let elapsedTime = 1 << 11
        static let remainingTime = 1 << 12
    }

    static func parse(_ data: Data) -> IndoorBikeSample {
        let bytes = [UInt8](data)
        var offset = 0
        var sample = IndoorBikeSample()

        func u16() -> Int {
            guard offset + 1 < bytes.count else { return 0 }
            let v = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
            return v
        }
        func i16() -> Int {
            let raw = u16()
            return raw >= 0x8000 ? raw - 0x10000 : raw
        }

        guard bytes.count >= 2 else { return sample }
        let flags = Int(bytes[0]) | (Int(bytes[1]) << 8)
        offset = 2

        if (flags & Flag.moreData) == 0 {
            sample.speedKmh = Double(u16()) * 0.01
        }
        if flags & Flag.avgSpeed != 0 { offset += 2 }
        if flags & Flag.instCadence != 0 {
            sample.cadenceRpm = Double(u16()) * 0.5
        }
        if flags & Flag.avgCadence != 0 { offset += 2 }
        if flags & Flag.totalDistance != 0 { offset += 3 } // uint24
        if flags & Flag.resistanceLevel != 0 { offset += 2 }
        if flags & Flag.instPower != 0 {
            sample.powerWatts = i16()
        }
        if flags & Flag.avgPower != 0 { offset += 2 }
        if flags & Flag.expendedEnergy != 0 { offset += 5 }
        if flags & Flag.heartRate != 0 {
            if offset < bytes.count {
                sample.heartRateBpm = Int(bytes[offset])
                offset += 1
            }
        }
        if flags & Flag.metabolicEquivalent != 0 { offset += 1 }
        if flags & Flag.elapsedTime != 0 {
            sample.elapsedTimeSec = u16()
        }
        if flags & Flag.remainingTime != 0 { offset += 2 }

        return sample
    }
}
