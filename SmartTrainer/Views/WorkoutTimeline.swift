import SwiftUI

/// Full-workout completion bar: each step is a segment colored by intensity,
/// the elapsed portion is dimmed, and a marker shows current position.
struct WorkoutTimeline: View {
    let workout: Workout
    let ftpWatts: Double
    let elapsedSec: Int

    private var totalSec: Double { max(1, workout.durationSec) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 1) {
                    ForEach(Array(workout.steps.enumerated()), id: \.offset) { _, step in
                        segmentColor(step)
                            .frame(width: max(1, width * (step.durationSec / totalSec)))
                    }
                }
                // Dim the completed portion.
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: width * min(1, Double(elapsedSec) / totalSec))
                // Position marker.
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: width * min(1, Double(elapsedSec) / totalSec) - 1)
            }
        }
    }

    private func segmentColor(_ step: WorkoutStep) -> Color {
        if step.isFreeRide { return .secondary.opacity(0.4) }
        let mid = (step.powerLow + step.powerHigh) / 2
        let frac = step.powerFraction(value: mid, ftpWatts: ftpWatts)
        return Palette.powerFractionColor(frac)
    }
}
