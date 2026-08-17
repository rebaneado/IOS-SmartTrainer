import SwiftUI

struct SummaryView: View {
    let recording: RideRecording
    let ftpWatts: Int
    let hrZones: HrZones
    @ObservedObject var stravaAuth: StravaAuth
    let onDone: () -> Void

    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var exportError: String?

    @State private var stravaUploading = false
    @State private var stravaResult: StravaUploader.Result?
    @State private var stravaError: String?

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

                HrZoneBreakdown(samples: recording.samples, hrZones: hrZones)

                VStack(spacing: 10) {
                    if stravaAuth.connected {
                        Button {
                            uploadToStrava()
                        } label: {
                            Label(stravaUploading ? "Uploading…" : "Log ride to Strava", systemImage: "figure.outdoor.cycle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(stravaUploading || stravaResult != nil)

                        if let stravaResult {
                            Link("View on Strava ↗", destination: stravaResult.url)
                                .font(.footnote)
                        }
                        if let stravaError {
                            Text(stravaError).font(.footnote).foregroundStyle(.red)
                        }
                    }

                    Button {
                        exportAndShare()
                    } label: {
                        Label("Export / share ride (.tcx)", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("The .tcx file also uploads to TrainingPeaks or Garmin Connect.")
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

    private func uploadToStrava() {
        stravaError = nil
        stravaUploading = true
        Task {
            do {
                let token = try await stravaAuth.validAccessToken()
                let result = try await StravaUploader.upload(recording, accessToken: token)
                stravaResult = result
            } catch {
                stravaError = error.localizedDescription
            }
            stravaUploading = false
        }
    }
}
