import SwiftUI

struct RideView: View {
    @ObservedObject var engine: ErgEngine
    let isTrial: Bool
    let hrZones: HrZones
    let onFinish: (RideRecording) -> Void

    private let nudgeStep = 5
    private let upcomingShown = 3

    private var step: WorkoutStep? { engine.currentStep }

    private var upcoming: [WorkoutStep] {
        let start = engine.currentStepIndex + 1
        guard start < engine.workout.steps.count else { return [] }
        let end = min(start + upcomingShown, engine.workout.steps.count)
        return Array(engine.workout.steps[start..<end])
    }

    private var stepRemaining: Double {
        guard let step else { return 0 }
        return max(0, step.durationSec - Double(engine.elapsedInStepSec))
    }

    private var stepProgress: Double {
        guard let step, step.durationSec > 0 else { return 1 }
        return min(1, Double(engine.elapsedInStepSec) / step.durationSec)
    }

    private var stepColor: Color {
        guard let step, !step.isFreeRide else { return .secondary }
        let frac = step.powerFraction(value: step.power(atElapsed: Double(engine.elapsedInStepSec)), ftpWatts: engine.ftpWatts)
        return Palette.powerFractionColor(frac)
    }

    private var speedMph: Double? {
        engine.live.speedKmh.map { $0 * 0.621371 }
    }

    private var hrZone: HrZone? {
        hrZones.zone(for: engine.live.heartRateBpm)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isTrial {
                    banner("Trial mode — no trainer connected, numbers below are simulated.", color: Palette.warning, dashed: true)
                }
                if engine.autoPaused {
                    banner("Auto-paused — no pedaling detected. Start pedaling to resume.", color: .red, dashed: true)
                }

                stepHeader
                WorkoutTimeline(workout: engine.workout, ftpWatts: engine.ftpWatts, elapsedSec: engine.totalElapsedSec)
                    .frame(height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if !upcoming.isEmpty { upNext }
                primaryNumbers
                secondaryNumbers
                controls
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func banner(_ text: String, color: Color, dashed: Bool) -> some View {
        Text(text)
            .font(.footnote)
            .frame(maxWidth: .infinity)
            .padding(8)
            .foregroundStyle(color)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4] : []))
            )
    }

    private var stepHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("STEP \(engine.currentStepIndex + 1) OF \(engine.workout.steps.count)")
                Spacer()
                Text("\(TimeFormat.clock(Double(engine.totalElapsedSec))) / \(TimeFormat.clock(Double(engine.totalDurationSec))) TOTAL")
            }
            .font(.caption2).foregroundStyle(.secondary)

            Text(step?.name ?? "Step")
                .font(.title3).fontWeight(.semibold)

            Text(TimeFormat.clock(stepRemaining))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(stepColor)
                .monospacedDigit()

            ProgressView(value: stepProgress)
                .tint(stepColor)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(stepColor.opacity(0.6), lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UP NEXT").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name ?? "Step").font(.body).fontWeight(.semibold)
                            Text("\(s.formatWattsShort(ftpWatts: engine.ftpWatts)) · \(TimeFormat.clock(s.durationSec))")
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var primaryNumbers: some View {
        HStack(spacing: 16) {
            NumberTile(value: engine.live.powerWatts.map(String.init) ?? "--", label: "watts", big: true)
            VStack(spacing: 8) {
                NumberTile(
                    value: !engine.ergEnabled ? "OFF" : (step?.isFreeRide == true ? "free" : engine.targetWatts.map(String.init) ?? "--"),
                    label: engine.manualOffsetWatts != 0 ? "target (\(engine.manualOffsetWatts > 0 ? "+" : "")\(engine.manualOffsetWatts)W)" : "target",
                    big: true,
                    borderColor: Palette.power
                )
                HStack(spacing: 10) {
                    Button("−\(nudgeStep)W") { engine.nudgeTarget(-nudgeStep) }
                        .frame(maxWidth: .infinity)
                    Button("+\(nudgeStep)W") { engine.nudgeTarget(nudgeStep) }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .font(.body.weight(.semibold))
            }
        }
    }

    private var secondaryNumbers: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 14)], spacing: 14) {
            NumberTile(value: engine.live.cadenceRpm.map { String(Int($0)) } ?? "--", label: "rpm", color: Palette.cadence)
            NumberTile(
                value: engine.live.heartRateBpm.map(String.init) ?? "--",
                label: hrZone.map { "\($0.short) · bpm" } ?? "bpm",
                color: hrZone?.color ?? Palette.heartRate
            )
            NumberTile(value: speedMph.map { String(format: "%.1f", $0) } ?? "--", label: "mph", color: Palette.speed)
            NumberTile(value: String(format: "%.2f", engine.totalDistanceMiles), label: "miles", color: Palette.distance)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if engine.status == .running {
                    Button("Pause") { engine.pause() }
                }
                if engine.status == .paused {
                    Button("Resume") { engine.resume() }.buttonStyle(.borderedProminent)
                }
                Button(engine.ergEnabled ? "ERG off" : "ERG on") {
                    Task { await engine.setErgEnabled(!engine.ergEnabled) }
                }
                Button("Skip") { engine.skipStep() }
            }
            Button("End ride", role: .destructive) {
                Task {
                    let recording = await engine.stop()
                    onFinish(recording)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }
}

struct NumberTile: View {
    let value: String
    let label: String
    var big: Bool = false
    var color: Color? = nil
    var borderColor: Color? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: big ? 44 : 26, weight: .bold, design: .rounded))
                .foregroundStyle(color ?? .primary)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.caption2).foregroundStyle(.secondary).tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .top) {
            Rectangle().fill(color ?? borderColor ?? .clear).frame(height: 3)
        }
        .overlay {
            if let borderColor {
                RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
