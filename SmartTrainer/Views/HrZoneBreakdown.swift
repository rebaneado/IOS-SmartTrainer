import SwiftUI

/// Time-in-heart-rate-zone breakdown for the ride summary: a stacked
/// proportion bar plus a per-zone row (range, time, percent). Each zone is
/// labelled, so colour is never the sole signal. Renders nothing if the ride
/// recorded no heart rate.
struct HrZoneBreakdown: View {
    let samples: [RideSample]

    // Samples are recorded ~1/second, so counting them per zone == seconds in zone.
    private var secondsByZone: [Int: Int] {
        var out: [Int: Int] = [:]
        for s in samples {
            guard let z = HrZones.zone(for: s.heartRateBpm) else { continue }
            out[z.index, default: 0] += 1
        }
        return out
    }

    var body: some View {
        let byZone = secondsByZone
        let total = byZone.values.reduce(0, +)
        if total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("TIME IN HEART RATE ZONES")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary).tracking(0.5)

                // Stacked proportion bar.
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(HrZones.all) { z in
                            let sec = byZone[z.index] ?? 0
                            if sec > 0 {
                                z.color.frame(width: max(2, geo.size.width * CGFloat(sec) / CGFloat(total)))
                            }
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                // Per-zone rows.
                VStack(spacing: 8) {
                    ForEach(HrZones.all) { z in
                        let sec = byZone[z.index] ?? 0
                        let pct = Int((Double(sec) / Double(total) * 100).rounded())
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(z.color).frame(width: 14, height: 14)
                            Text("\(z.short) \(z.name)").fontWeight(.semibold)
                            Text("\(z.rangeLabel) bpm").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(TimeFormat.clock(Double(sec))).foregroundStyle(.secondary).monospacedDigit()
                            Text("\(pct)%").fontWeight(.semibold).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
