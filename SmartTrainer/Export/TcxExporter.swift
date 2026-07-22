import Foundation

// Exports a recorded ride as a Garmin TCX (Training Center XML) activity file.
// TCX is plain XML — no binary encoding — and is accepted by Strava,
// TrainingPeaks, and Garmin Connect for manual upload. Chosen over .fit for v1
// specifically to avoid porting the web app's custom FIT binary writer.

enum TcxExporter {
    static func export(_ recording: RideRecording) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let startTime = iso.string(from: recording.startedAt)

        var trackpoints = ""
        for sample in recording.samples {
            let time = iso.string(from: recording.startedAt.addingTimeInterval(Double(sample.tSec)))
            var tp = "        <Trackpoint>\n"
            tp += "          <Time>\(time)</Time>\n"
            if let hr = sample.heartRateBpm {
                tp += "          <HeartRateBpm><Value>\(hr)</Value></HeartRateBpm>\n"
            }
            if let cad = sample.cadenceRpm {
                tp += "          <Cadence>\(Int(cad.rounded()))</Cadence>\n"
            }
            // Power lives in the TPX extension, which is what Strava/TP read.
            if let power = sample.powerWatts {
                tp += "          <Extensions>\n"
                tp += "            <ns3:TPX xmlns:ns3=\"http://www.garmin.com/xmlschemas/ActivityExtension/v2\">\n"
                tp += "              <ns3:Watts>\(power)</ns3:Watts>\n"
                tp += "            </ns3:TPX>\n"
                tp += "          </Extensions>\n"
            }
            tp += "        </Trackpoint>\n"
            trackpoints += tp
        }

        let totalSeconds = recording.durationSec
        let notes = recording.workoutName.map { xmlEscape($0) } ?? "SmartTrainer ride"

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase
          xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
          xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
          <Activities>
            <Activity Sport="Biking">
              <Id>\(startTime)</Id>
              <Lap StartTime="\(startTime)">
                <TotalTimeSeconds>\(totalSeconds)</TotalTimeSeconds>
                <DistanceMeters>\(Int((recording.distanceMiles * 1609.34).rounded()))</DistanceMeters>
                <Calories>0</Calories>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>
        \(trackpoints)        </Track>
              </Lap>
              <Notes>\(notes)</Notes>
              <Creator xsi:type="Device_t">
                <Name>SmartTrainer</Name>
                <UnitId>0</UnitId>
                <ProductID>0</ProductID>
              </Creator>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """
    }

    /// Writes the TCX to a temp file and returns its URL, for the share sheet.
    static func writeToTempFile(_ recording: RideRecording) throws -> URL {
        let xml = export(recording)
        let safeName = (recording.workoutName ?? "ride")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        let filename = "\(df.string(from: recording.startedAt))_\(safeName).tcx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try xml.data(using: .utf8)?.write(to: url)
        return url
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
