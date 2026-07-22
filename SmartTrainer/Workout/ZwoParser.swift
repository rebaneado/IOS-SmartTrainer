import Foundation

// Zwift .zwo workout XML parser. Uses Foundation's event-driven XMLParser
// (no DOM on iOS) to walk the <workout> children into our step model.

enum ZwoParseError: LocalizedError {
    case notWellFormed
    case missingWorkout
    case noSteps

    var errorDescription: String? {
        switch self {
        case .notWellFormed: return "Invalid .zwo file: not well-formed XML"
        case .missingWorkout: return "Invalid .zwo file: missing <workout> element"
        case .noSteps: return "Invalid .zwo file: no workout steps found"
        }
    }
}

enum ZwoParser {
    static func parse(_ xmlText: String) throws -> Workout {
        guard let data = xmlText.data(using: .utf8) else { throw ZwoParseError.notWellFormed }
        let delegate = ZwoDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        if !parser.parse() || delegate.failed { throw ZwoParseError.notWellFormed }
        guard delegate.sawWorkout else { throw ZwoParseError.missingWorkout }
        if delegate.steps.isEmpty { throw ZwoParseError.noSteps }
        let name = delegate.workoutName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Imported workout"
        return Workout(name: name, steps: delegate.steps, source: .zwo)
    }
}

private final class ZwoDelegate: NSObject, XMLParserDelegate {
    var steps: [WorkoutStep] = []
    var workoutName: String?
    var sawWorkout = false
    var failed = false

    private var insideWorkout = false
    private var capturingName = false
    private var nameBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "name":
            capturingName = true
            nameBuffer = ""
        case "workout":
            sawWorkout = true
            insideWorkout = true
        default:
            if insideWorkout {
                steps.append(contentsOf: stepsFrom(element: elementName, attrs: attributeDict))
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingName { nameBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "name" {
            capturingName = false
            if workoutName == nil { workoutName = nameBuffer }
        } else if elementName == "workout" {
            insideWorkout = false
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failed = true
    }

    private func num(_ attrs: [String: String], _ key: String, _ fallback: Double = 0) -> Double {
        guard let raw = attrs[key], let v = Double(raw) else { return fallback }
        return v
    }

    private func stepsFrom(element: String, attrs: [String: String]) -> [WorkoutStep] {
        let cadence: Double? = attrs["Cadence"].flatMap { Double($0) }

        switch element {
        case "Warmup", "Ramp":
            return [WorkoutStep(
                name: element,
                durationSec: num(attrs, "Duration"),
                powerLow: num(attrs, "PowerLow"),
                powerHigh: num(attrs, "PowerHigh"),
                cadenceTarget: cadence
            )]
        case "Cooldown":
            return [WorkoutStep(
                name: "Cooldown",
                durationSec: num(attrs, "Duration"),
                powerLow: num(attrs, "PowerLow"),
                powerHigh: num(attrs, "PowerHigh"),
                cadenceTarget: cadence
            )]
        case "SteadyState":
            let power = num(attrs, "Power")
            return [WorkoutStep(
                name: "SteadyState",
                durationSec: num(attrs, "Duration"),
                powerLow: power,
                powerHigh: power,
                cadenceTarget: cadence
            )]
        case "IntervalsT":
            let repeatCount = max(1, Int(num(attrs, "Repeat", 1).rounded()))
            let onDuration = num(attrs, "OnDuration")
            let offDuration = num(attrs, "OffDuration")
            let onPower = num(attrs, "OnPower")
            let offPower = num(attrs, "OffPower")
            let offCadence: Double? = attrs["CadenceResting"].flatMap { Double($0) } ?? cadence
            var out: [WorkoutStep] = []
            for _ in 0..<repeatCount {
                out.append(WorkoutStep(
                    name: "Interval (on)",
                    durationSec: onDuration,
                    powerLow: onPower,
                    powerHigh: onPower,
                    cadenceTarget: cadence
                ))
                if offDuration > 0 {
                    out.append(WorkoutStep(
                        name: "Interval (off)",
                        durationSec: offDuration,
                        powerLow: offPower,
                        powerHigh: offPower,
                        cadenceTarget: offCadence
                    ))
                }
            }
            return out
        case "FreeRide":
            return [WorkoutStep(
                name: "Free ride",
                durationSec: num(attrs, "Duration"),
                powerLow: 0,
                powerHigh: 0,
                isFreeRide: true
            )]
        default:
            return []
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
