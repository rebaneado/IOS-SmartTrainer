import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var trainer: FtmsTrainer
    @ObservedObject private var hrSensor: HeartRateSensor
    @ObservedObject private var library: Library
    @ObservedObject private var settings: Settings
    @ObservedObject private var stravaAuth: StravaAuth

    @State private var showingImporter = false
    @State private var showingLibraryImporter = false
    @State private var showingLibraryExporter = false
    @State private var importError: String?
    @State private var libraryMessage: String?
    @State private var expandedIds: Set<UUID> = []
    @State private var editingStravaCredentials = false

    init(model: AppModel) {
        self.model = model
        self.trainer = model.trainer
        self.hrSensor = model.hrSensor
        self.library = model.library
        self.settings = model.settings
        self.stravaAuth = model.stravaAuth
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                trainerCard
                hrCard
                settingsCard
                stravaCard
                libraryCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: workoutTypes,
            allowsMultipleSelection: true
        ) { handleImport($0) }
        .fileImporter(
            isPresented: $showingLibraryImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { handleLibraryImport($0) }
        .fileExporter(
            isPresented: $showingLibraryExporter,
            document: LibraryDocument(data: library.exportData() ?? Data()),
            contentType: .json,
            defaultFilename: "smarttrainer-library"
        ) { _ in }
    }

    // Custom UTTypes for the workout extensions the app accepts.
    private var workoutTypes: [UTType] {
        var types: [UTType] = [.xml, .data]
        for ext in ["erg", "mrc", "zwo"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    // MARK: Cards

    private var trainerCard: some View {
        Card(title: "Trainer") {
            HStack(spacing: 12) {
                StatusPill(text: trainer.state == .connected ? "Connected: \(trainer.deviceName ?? "trainer")" : trainer.state.rawValue,
                           color: pillColor(trainer.state == .connected, connecting: trainer.state == .connecting))
                Spacer()
                if trainer.state == .connected {
                    Button("Disconnect") { trainer.disconnect() }
                } else {
                    Button("Connect Saris H3") {
                        Task { await model.connectTrainer() }
                    }
                    .disabled(trainer.state == .connecting)
                }
            }
            if trainer.state != .connected {
                Text("No trainer? You can still start any workout below in trial mode — it runs with simulated numbers so you can preview the app.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var hrCard: some View {
        Card(title: "Heart rate sensor (optional)") {
            HStack(spacing: 12) {
                StatusPill(text: hrSensor.state == .connected ? "Connected: \(hrSensor.deviceName ?? "sensor")" : hrSensor.state.rawValue,
                           color: pillColor(hrSensor.state == .connected, connecting: hrSensor.state == .connecting))
                Spacer()
                if hrSensor.state == .connected {
                    Button("Disconnect") { hrSensor.disconnect() }
                } else {
                    Button("Connect strap") { Task { await model.connectHr() } }
                        .disabled(hrSensor.state == .connecting)
                }
            }
            Text("Any standard Bluetooth strap works (Garmin HRM, Wahoo TICKR, Polar). Connect it separately from the trainer if your trainer doesn't report heart rate itself.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var settingsCard: some View {
        Card(title: "Settings") {
            HStack {
                Text("FTP (watts)")
                Spacer()
                TextField("FTP", value: $settings.ftpWatts, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .textFieldStyle(.roundedBorder)
            }

            Divider().padding(.vertical, 4)

            Text("HEART RATE ZONES (BPM)").font(.caption2).foregroundStyle(.secondary)
            hrZoneField("Z1 top (Warm Up ends)", $settings.hrZ1Top)
            hrZoneField("Z2 top (Easy ends)", $settings.hrZ2Top)
            hrZoneField("Z3 top (Aerobic ends)", $settings.hrZ3Top)
            hrZoneField("Z4 top (Threshold ends)", $settings.hrZ4Top)
            Text("Z5 (Maximum) is anything above Z4's top. Set these to your own zones — from a lab test, TrainingPeaks, or your watch's estimate.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func hrZoneField(_ label: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
        }
        .font(.callout)
    }

    private var stravaCard: some View {
        Card(title: "Strava") {
            if !stravaAuth.isConfigured || editingStravaCredentials {
                Text("Two one-time setup steps — see strava-proxy/README.md for the 5-minute walkthrough:")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("1. Client ID from strava.com/settings/api (Authorization Callback Domain: \(StravaAuth.callbackScheme)).\n2. Token proxy URL, after deploying strava-proxy/worker.js (holds your Client Secret so it never ships in this app).")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Client ID", text: $stravaAuth.clientId)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                TextField("Token proxy URL (https://...)", text: $stravaAuth.proxyURL)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("Save") { editingStravaCredentials = false }
                    .disabled(!stravaAuth.isConfigured)
            } else if stravaAuth.connected {
                HStack(spacing: 12) {
                    StatusPill(text: stravaAuth.athleteName.map { "Connected: \($0)" } ?? "Connected",
                               color: .green)
                    Spacer()
                    Button("Disconnect") { stravaAuth.disconnect() }
                }
                Button("Edit Client ID / proxy URL") { editingStravaCredentials = true }
                    .font(.footnote)
            } else {
                HStack(spacing: 12) {
                    StatusPill(text: "Not connected", color: .secondary)
                    Spacer()
                    Button(stravaAuth.isBusy ? "Connecting…" : "Connect to Strava") { stravaAuth.connect() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(stravaAuth.isBusy)
                }
                Text("One-time sign-in. After that, every ride's summary screen gets a \"Log ride to Strava\" button.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Edit Client ID / proxy URL") { editingStravaCredentials = true }
                    .font(.footnote)
            }
            if let error = stravaAuth.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var libraryCard: some View {
        Card(title: "Workout library") {
            Text("A starter Ironman-distance bike plan (84 workouts, ordered by date) loads automatically — delete it any time. TrainingPeaks doesn't offer direct account sync for independent apps, so bring in your own plan by exporting workouts from TrainingPeaks as .zwo/.erg/.mrc and importing them below.")
                .font(.footnote).foregroundStyle(.secondary)

            HStack {
                Button("Import workout") { showingImporter = true }
                    .buttonStyle(.borderedProminent)
                Button("Reload plan") {
                    let n = library.loadBundledPlan()
                    libraryMessage = n > 0 ? "Loaded \(n) planned workouts." : "Couldn't find the bundled plan."
                }
                Spacer()
            }

            HStack {
                Button("Export library") { showingLibraryExporter = true }
                    .disabled(library.workouts.isEmpty)
                Button("Import library") { showingLibraryImporter = true }
            }
            .font(.callout)

            if let importError {
                Text(importError).font(.footnote).foregroundStyle(.red)
            }
            if let libraryMessage {
                Text(libraryMessage).font(.footnote).foregroundStyle(.secondary)
            }

            if library.workouts.isEmpty {
                Text("No workouts imported yet.").font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(library.folders.filter { !library.workouts(inFolder: $0).isEmpty }, id: \.self) { folder in
                VStack(alignment: .leading, spacing: 8) {
                    Text(folder.uppercased())
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(library.workouts(inFolder: folder)) { w in
                        workoutRow(w)
                        Divider()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func workoutRow(_ w: StoredWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    if expandedIds.contains(w.id) { expandedIds.remove(w.id) } else { expandedIds.insert(w.id) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expandedIds.contains(w.id) ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text(w.name).fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button(trainer.state == .connected ? "Start" : "Start (trial)") {
                    Task { await model.start(w) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Text("\(TimeFormat.clock(w.durationSec)) · \(w.source?.rawValue ?? "workout")")
                .font(.caption).foregroundStyle(.secondary)

            if expandedIds.contains(w.id) {
                WorkoutDetailsView(
                    stored: w,
                    ftpWatts: settings.ftpWatts,
                    onStart: { Task { await model.start(w) } },
                    onSaveSteps: { steps in library.updateSteps(w.id, steps: steps) },
                    onRemove: { library.remove(w.id) },
                    onMove: { folder in library.move(w.id, toFolder: folder) }
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func pillColor(_ connected: Bool, connecting: Bool) -> Color {
        if connected { return .green }
        if connecting { return Palette.warning }
        return .secondary
    }

    // MARK: Import handlers

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            var newIds: [UUID] = []
            for url in urls {
                do {
                    let workout = try ImportWorkout.from(url: url)
                    let stored = library.add(workout)
                    newIds.append(stored.id)
                } catch {
                    importError = error.localizedDescription
                }
            }
            expandedIds.formUnion(newIds)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func handleLibraryImport(_ result: Result<[URL], Error>) {
        importError = nil
        libraryMessage = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        do {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let count = try library.importData(data)
            libraryMessage = "Imported \(count) workout\(count == 1 ? "" : "s")."
        } catch {
            importError = error.localizedDescription
        }
    }
}

// A trivial FileDocument so .fileExporter can write the library JSON.
struct LibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: Shared small components

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(0.5)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.capitalized)
            .font(.footnote)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(Capsule().stroke(color, lineWidth: 1))
            .foregroundStyle(color)
    }
}
