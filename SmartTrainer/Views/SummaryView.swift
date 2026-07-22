import SwiftUI

struct SummaryView: View {
    let recording: RideRecording
    let ftpWatts: Int
    let onDone: () -> Void

    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(recording.workoutName ?? "Ride complete")
                    .font(.title2).fontWeight(.semibold)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    stat("Duration", TimeFormat.clock(Double(recording.durationSec)))
                    stat("Distance", String(format: "%.2f mi", recording.distanceMiles))
                    stat("Avg power", recording.avgPower.map { "\($0) W" } ?? "--")
                    stat("Max power", recording.maxPower.map { "\($0) W" } ?? "--")
                    stat("Avg HR", recording.avgHeartRate.map { "\($0) bpm" } ?? "--")
                    stat("Samples", "\(recording.samples.count)")
                }

                HrZoneBreakdown(samples: recording.samples)

                VStack(spacing: 10) {
                    Button {
                        exportAndShare()
                    } label: {
                        Label("Export / share ride (.tcx)", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("The .tcx file uploads to Strava, TrainingPeaks, or Garmin Connect.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let exportError {
                        Text(exportError).font(.footnote).foregroundStyle(.red)
                    }

                    Button("Done", action: onDone)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingShare) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).fontWeight(.semibold).monospacedDigit()
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func exportAndShare() {
        exportError = nil
        do {
            shareURL = try TcxExporter.writeToTempFile(recording)
            showingShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}
