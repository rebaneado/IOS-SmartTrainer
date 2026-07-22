import Foundation

// .erg/.mrc ("CompuTrainer"-style) course files: a plain-text time-series of
// (minutes, power) breakpoints, linearly interpolated between consecutive
// points. No named steps or repeat-block encoding, which sidesteps the whole
// class of ambiguity FIT's repeat markers have. Format verified against
// GoldenCheetah's reference parser and real TrainingPeaks exports.

enum ErgParseError: LocalizedError {
    case noData
    case tooFewPoints
    case noSegments

    var errorDescription: String? {
        switch self {
        case .noData: return "Invalid .erg/.mrc file: no [COURSE DATA] section found"
        case .tooFewPoints: return "Invalid .erg/.mrc file: fewer than 2 usable data points"
        case .noSegments: return "Invalid .erg/.mrc file: no usable segments (all points at the same timestamp?)"
        }
    }
}

private struct ErgPoint {
    var timeMin: Double
    var rawValue: Double
    /// This row was written with a trailing "%" — overrides the file-level unit for this point.
    var isPercent: Bool
}

enum ErgFileParser {
    static func parse(_ text: String) throws -> Workout {
        let lines = text.components(separatedBy: CharacterSet.newlines)

        let headerLines = extractSection(lines, start: "[COURSE HEADER]", end: "[END COURSE HEADER]")
        let dataLines = extractSection(lines, start: "[COURSE DATA]", end: "[END COURSE DATA]")

        if dataLines.isEmpty { throw ErgParseError.noData }

        var description: String?
        var fileName: String?
        var declaredFtp: Double?
        var filePercentMode = false

        for raw in headerLines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            let upper = line.uppercased()
            if matchesFormat(upper, keyword: "WATTS") {
                filePercentMode = false
                continue
            }
            if matchesFormat(upper, keyword: "PERCENT") || matchesFormat(upper, keyword: "FTP") {
                filePercentMode = true
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces).uppercased()
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "DESCRIPTION": description = value
            case "FILE NAME": fileName = value
            case "FTP": declaredFtp = Double(value)
            default: break
            }
        }

        var points: [ErgPoint] = []
        for raw in dataLines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            guard let p = parseDataRow(line) else { continue }
            points.append(p)
        }

        if points.count < 2 { throw ErgParseError.tooFewPoints }

        // Percent values are 0-100 of FTP, so /100 gives our fraction directly.
        // Absolute-watt values with a declared file FTP are converted to a
        // fraction of THAT FTP so they rescale to the rider's current FTP —
        // matching how real ERG software (GoldenCheetah) rescales these files.
        func convert(_ point: ErgPoint) -> (value: Double, unit: PowerUnit) {
            if point.isPercent || filePercentMode {
                return (point.rawValue / 100, .pctFtp)
            }
            if let ftp = declaredFtp, ftp > 0 {
                return (point.rawValue / ftp, .pctFtp)
            }
            return (point.rawValue, .watts)
        }

        var steps: [WorkoutStep] = []
        for i in 0..<(points.count - 1) {
            let durationSec = (points[i + 1].timeMin - points[i].timeMin) * 60
            // Consecutive points at the same timestamp are an instant value-jump
            // marker (a sharp step change), not a real step.
            if durationSec <= 0 { continue }
            let from = convert(points[i])
            let to = convert(points[i + 1])
            steps.append(WorkoutStep(
                durationSec: durationSec,
                powerLow: from.value,
                powerHigh: to.value,
                powerUnit: from.unit
            ))
        }

        if steps.isEmpty { throw ErgParseError.noSegments }

        // TrainingPeaks puts the workout title in DESCRIPTION and a filename
        // slug in FILE NAME — confirmed by comparing real .fit/.erg exports.
        let name = description?.nonEmpty ?? fileName?.nonEmpty ?? "Imported workout"
        return Workout(name: name, steps: steps, source: .erg)
    }

    private static func extractSection(_ lines: [String], start: String, end: String) -> [String] {
        guard let startIdx = lines.firstIndex(where: { $0.uppercased().contains(start) }) else { return [] }
        guard let endIdx = lines[(startIdx + 1)...].firstIndex(where: { $0.uppercased().contains(end) }) else { return [] }
        return Array(lines[(startIdx + 1)..<endIdx])
    }

    /// Matches header lines like "MINUTES WATTS" / "MINUTES PERCENT" / "MINUTES FTP",
    /// tolerating a leading ";" and arbitrary internal whitespace.
    private static func matchesFormat(_ upper: String, keyword: String) -> Bool {
        let cleaned = upper.trimmingCharacters(in: CharacterSet(charactersIn: "; \t"))
        let parts = cleaned.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 2 else { return false }
        return parts[0] == "MINUTES" && parts[1] == keyword
    }

    private static func parseDataRow(_ line: String) -> ErgPoint? {
        let hasPercent = line.hasSuffix("%")
        let body = hasPercent ? String(line.dropLast()) : line
        let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 2, let t = Double(parts[0]), let v = Double(parts[1]) else { return nil }
        return ErgPoint(timeMin: t, rawValue: v, isPercent: hasPercent)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
