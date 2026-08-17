import Foundation

/// Uploads a completed ride's .tcx to Strava's Uploads API and polls until
/// Strava finishes processing it into an activity.
enum StravaUploader {
    private static let uploadsURL = URL(string: "https://www.strava.com/api/v3/uploads")!

    struct Result {
        let activityId: Int
        let url: URL
    }

    private struct UploadStatus: Decodable {
        let id: Int
        let error: String?
        let status: String
        let activity_id: Int?
    }

    static func upload(_ recording: RideRecording, accessToken: String,
                        pollInterval: UInt64 = 1_500_000_000, maxPolls: Int = 20) async throws -> Result {
        let tcxURL = try TcxExporter.writeToTempFile(recording)
        defer { try? FileManager.default.removeItem(at: tcxURL) }
        let tcxData = try Data(contentsOf: tcxURL)
        let name = recording.workoutName ?? "SmartTrainer ride"

        let uploadId = try await createUpload(tcxData: tcxData, name: name, accessToken: accessToken)

        for _ in 0..<maxPolls {
            try await Task.sleep(nanoseconds: pollInterval)
            let status = try await checkStatus(uploadId: uploadId, accessToken: accessToken)
            if let error = status.error, !error.isEmpty {
                throw StravaError.requestFailed(error)
            }
            if let activityId = status.activity_id {
                return Result(activityId: activityId, url: URL(string: "https://www.strava.com/activities/\(activityId)")!)
            }
        }
        throw StravaError.requestFailed("still processing — check strava.com in a minute")
    }

    private static func createUpload(tcxData: Data, name: String, accessToken: String) async throws -> Int {
        let boundary = "SmartTrainer-\(UUID().uuidString)"
        var req = URLRequest(url: uploadsURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        addField("data_type", "tcx")
        addField("name", name)
        addField("trainer", "1")
        addField("activity_type", "virtualride")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name).tcx\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(tcxData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StravaError.requestFailed(String(data: data, encoding: .utf8) ?? "upload failed")
        }
        return try JSONDecoder().decode(UploadStatus.self, from: data).id
    }

    private static func checkStatus(uploadId: Int, accessToken: String) async throws -> UploadStatus {
        var req = URLRequest(url: uploadsURL.appendingPathComponent("\(uploadId)"))
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StravaError.requestFailed(String(data: data, encoding: .utf8) ?? "status check failed")
        }
        return try JSONDecoder().decode(UploadStatus.self, from: data)
    }
}
