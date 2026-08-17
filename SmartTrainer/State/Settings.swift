import Foundation
import Combine

/// UserDefaults-backed rider settings. Defaults are generic starting points,
/// not any specific rider's data — everything here is editable in the app.
@MainActor
final class Settings: ObservableObject {
    @Published var ftpWatts: Int {
        didSet { UserDefaults.standard.set(ftpWatts, forKey: "smarttrainer.ftp") }
    }

    @Published var hrZ1Top: Int {
        didSet { UserDefaults.standard.set(hrZ1Top, forKey: "smarttrainer.hrz1") }
    }
    @Published var hrZ2Top: Int {
        didSet { UserDefaults.standard.set(hrZ2Top, forKey: "smarttrainer.hrz2") }
    }
    @Published var hrZ3Top: Int {
        didSet { UserDefaults.standard.set(hrZ3Top, forKey: "smarttrainer.hrz3") }
    }
    @Published var hrZ4Top: Int {
        didSet { UserDefaults.standard.set(hrZ4Top, forKey: "smarttrainer.hrz4") }
    }

    var hrZones: HrZones {
        HrZones(z1Top: hrZ1Top, z2Top: hrZ2Top, z3Top: hrZ3Top, z4Top: hrZ4Top)
    }

    init() {
        let defaults = UserDefaults.standard
        let savedFtp = defaults.integer(forKey: "smarttrainer.ftp")
        ftpWatts = savedFtp > 0 ? savedFtp : 200 // generic starting-point FTP; edit to your own

        let z1 = defaults.integer(forKey: "smarttrainer.hrz1")
        let z2 = defaults.integer(forKey: "smarttrainer.hrz2")
        let z3 = defaults.integer(forKey: "smarttrainer.hrz3")
        let z4 = defaults.integer(forKey: "smarttrainer.hrz4")
        // Generic five-zone split around a ~185 max HR; edit to your own zones.
        hrZ1Top = z1 > 0 ? z1 : 120
        hrZ2Top = z2 > 0 ? z2 : 140
        hrZ3Top = z3 > 0 ? z3 : 158
        hrZ4Top = z4 > 0 ? z4 : 174
    }
}
