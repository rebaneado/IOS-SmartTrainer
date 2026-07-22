import Foundation
import Combine

/// UserDefaults-backed rider settings.
@MainActor
final class Settings: ObservableObject {
    @Published var ftpWatts: Int {
        didSet { UserDefaults.standard.set(ftpWatts, forKey: "smarttrainer.ftp") }
    }

    init() {
        let saved = UserDefaults.standard.integer(forKey: "smarttrainer.ftp")
        ftpWatts = saved > 0 ? saved : 250 // matches the rider's threshold power
    }
}
