import SwiftUI

struct WorkoutDetailsView: View {
    let stored: StoredWorkout
    let ftpWatts: Int
    let onStart: () -> Void
    let onSaveSteps: ([WorkoutStep]) -> Void
    let onRemove: () -> Void
    let onMove: (String) -> Void

    @State private var editing = false
    @State private var editSteps: [EditableStep] = []
    @State private var showingMove = false
    @State private var moveTarget = ""

    private var grouped: [GroupedStep] {
        GroupSteps.group(stored.steps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editing {
                editView
            } else {
                summaryView
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Summary (read-only)

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(grouped) { g in
                ForEach(Array(g.steps.enumerated()), id: \.offset) { _, step in
                    HStack {
                        Text(g.count > 1 ? "\(g.count)× \(step.name ?? "Step")" : (step.name ?? "Step"))
                            .font(.callout)
                        Spacer()
                        Text("\(TimeFormat.clock(step.durationSec)) · \(step.formatTarget(ftpWatts: Double(ftpWatts)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Start this workout", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Edit steps") {
                    editSteps = stored.steps.map { EditableStep(from: $0, ftpWatts: ftpWatts) }
                    editing = true
                }
                .controlSize(.small)
            }
            .padding(.top, 4)

            HStack(spacing: 12) {
                Button("Move") { moveTarget = stored.folder; showingMove = true }
                    .controlSize(.small)
                Button("Remove", role: .destructive, action: onRemove)
                    .controlSize(.small)
            }
            .font(.caption)
        }
        .alert("Move to folder", isPresented: $showingMove) {
            TextField("Folder", text: $moveTarget)
            Button("Move") { onMove(moveTarget) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Edit mode

    private var editView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($editSteps) { $step in
                VStack(spacing: 6) {
                    TextField("Name", text: $step.name)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        LabeledField(label: "min", value: $step.minutes)
                        LabeledField(label: "W low", value: $step.wattsLow)
                        LabeledField(label: "W high", value: $step.wattsHigh)
                        Toggle("free", isOn: $step.isFreeRide).labelsHidden()
                        Button(role: .destructive) {
                            editSteps.removeAll { $0.id == step.id }
                        } label: { Image(systemName: "trash") }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }

            HStack(spacing: 12) {
                Button("Save") {
                    onSaveSteps(editSteps.map { $0.toWorkoutStep() })
                    editing = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Cancel") { editing = false }
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, value: $value, format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.center)
                .frame(width: 56)
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// An edit-friendly flattening of a WorkoutStep — always in explicit watts,
/// minutes instead of seconds. Editing fixes a step to a wattage (matching the
/// web app's documented behavior).
private struct EditableStep: Identifiable {
    let id = UUID()
    var name: String
    var minutes: Double
    var wattsLow: Double
    var wattsHigh: Double
    var isFreeRide: Bool

    init(from step: WorkoutStep, ftpWatts: Int) {
        name = step.name ?? "Step"
        minutes = (step.durationSec / 60 * 100).rounded() / 100
        wattsLow = step.watts(value: step.powerLow, ftpWatts: Double(ftpWatts)).rounded()
        wattsHigh = step.watts(value: step.powerHigh, ftpWatts: Double(ftpWatts)).rounded()
        isFreeRide = step.isFreeRide
    }

    func toWorkoutStep() -> WorkoutStep {
        WorkoutStep(
            name: name.isEmpty ? nil : name,
            durationSec: max(0, minutes * 60),
            powerLow: wattsLow,
            powerHigh: wattsHigh,
            powerUnit: .watts,
            isFreeRide: isFreeRide
        )
    }
}
