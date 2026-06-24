import Foundation
import Combine

/// Polls the GitHub releases API every 2 hours and publishes whether a newer
/// version than the running app is available.
///
/// The check is best-effort and silent: any network/parse failure simply
/// leaves the published state unchanged so the UI never surfaces errors.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// Latest release version found, e.g. "1.2.3" (tag prefix "v" stripped).
    @Published private(set) var latestVersion: String?
    /// HTML URL of the latest release (download page).
    @Published private(set) var latestReleaseURL: URL?
    /// Last successful check timestamp.
    @Published private(set) var lastChecked: Date?

    /// GitHub repo path used for the API calls.
    private let repo = "thuupx/UVieKey"
    /// Poll interval — 2 hours.
    private let interval: TimeInterval = 2 * 60 * 60
    private var timer: Timer?

    private init() {}

    /// True when `latestVersion` is strictly newer than the running app version.
    var hasUpdate: Bool {
        guard let latest = latestVersion else { return false }
        return Self.compare(latest, AppVersion.version) > 0
    }

    /// Starts the periodic check and fires one immediate check.
    func start() {
        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkNow() }
        }
    }

    /// Triggers a single fetch (also used manually from the About pane).
    func checkNow() {
        Task { @MainActor in
            await fetchLatestRelease()
        }
    }

    // MARK: - Fetch

    private func fetchLatestRelease() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Avoid caching stale release info.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String,
                  let html = obj["html_url"] as? String,
                  let htmlURL = URL(string: html) else { return }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            latestVersion = version
            latestReleaseURL = htmlURL
            lastChecked = Date()
        } catch {
            // Silent — leave existing state untouched.
        }
    }

    // MARK: - Version comparison

    /// Returns positive if `a` is newer than `b`, negative if older, 0 if equal.
    /// Compares dot-separated numeric segments (semver-ish).
    static func compare(_ a: String, _ b: String) -> Int {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let n = max(aParts.count, bParts.count)
        for i in 0..<n {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av - bv }
        }
        return 0
    }
}
