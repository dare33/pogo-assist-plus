import SwiftUI
import PogoBox
import PogoReader

/// What the "Make scans better" button needs from the app: the configuration, the network and the device facts. Networking lives here, in
/// the app target only; the broadcast extension never links it.
enum ReportSupport {
    /// The upload store, from Info.plist (filled from the git-ignored Signing.local.xcconfig); nil when either value is missing or a placeholder.
    /// The UI test passes `-uitest-reports-enabled` to show the button; that build can never send (its transport refuses).
    static var config: ReportConfig? {
        if CommandLine.arguments.contains("-uitest-reports-enabled") { return ReportConfig(urlText: "https://reports.example.test", keyText: "test-key") }
        let info = Bundle.main.infoDictionary
        return ReportConfig(urlText: info?["ScanReportURL"] as? String, keyText: info?["ScanReportKey"] as? String)
    }

    static var transport: ReportTransport { CommandLine.arguments.contains("-uitest-reports-enabled") ? RefusingTransport() : URLSessionTransport() }

    static var appInfo: ScanReport.AppInfo {
        let info = Bundle.main.infoDictionary
        return ScanReport.AppInfo(version: info?["CFBundleShortVersionString"] as? String ?? "?", build: info?["CFBundleVersion"] as? String ?? "?")
    }

    /// The kind of device, never which one: hardware model, system version, screen in points and language.
    @MainActor static var deviceInfo: ScanReport.DeviceInfo {
        var system = utsname(); uname(&system)
        let machine = withUnsafePointer(to: &system.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
        let b = UIScreen.main.bounds
        return ScanReport.DeviceInfo(model: model, os: UIDevice.current.systemVersion, screenWidth: Double(b.width), screenHeight: Double(b.height), locale: Locale.current.identifier)
    }
}

struct URLSessionTransport: ReportTransport {
    func send(_ post: HTTPPost) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: post.url, timeoutInterval: post.timeout)
        request.httpMethod = "POST"
        for (k, v) in post.headers { request.setValue(v, forHTTPHeaderField: k) }
        // One attempt: an ephemeral session keeps no cache or cookies, and nothing is retried in the background.
        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.upload(for: request, from: post.body)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

struct RefusingTransport: ReportTransport {
    func send(_ post: HTTPPost) async throws -> (status: Int, body: Data) { throw URLError(.notConnectedToInternet) }
}

/// The daily limit's memory, in UserDefaults (the last 50 send times).
final class DefaultsLedger: UploadLedger {
    private let key = "reportSentTimes"
    var sentTimes: [Date] { (UserDefaults.standard.array(forKey: key) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) } }
    func record(_ date: Date) {
        let all = ((UserDefaults.standard.array(forKey: key) as? [Double]) ?? []) + [date.timeIntervalSince1970]
        UserDefaults.standard.set(Array(all.suffix(50)), forKey: key)
    }
}
