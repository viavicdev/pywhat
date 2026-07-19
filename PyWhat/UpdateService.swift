import Foundation
import AppKit

/// Auto-oppdatering fra GitHub Releases.
/// Sjekker ved oppstart + hver 6. time. Finner den en nyere `vX.Y.Z`-release,
/// lastes PyWhat.zip ned, appen byttes ut på disk og relanseres.
final class UpdateService {
    static let shared = UpdateService()

    private let repo = "viavicdev/pywhat"
    private let assetName = "PyWhat.zip"
    private var timer: Timer?

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        // Bare auto-oppdater installerte kopier — ikke dev-builds fra .build/
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            log("dev-build (\(Bundle.main.bundlePath)) — hopper over auto-oppdatering")
            return
        }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func check() {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("PyWhat-updater", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else { return }
            let tag = release.tag_name
            guard self.isNewer(tag, than: self.currentVersion),
                  let asset = release.assets.first(where: { $0.name == self.assetName }),
                  let dlURL = URL(string: asset.browser_download_url) else {
                self.log("ingen nyere versjon (siste: \(tag), kjører: \(self.currentVersion))")
                return
            }
            self.log("ny versjon \(tag) funnet — laster ned")
            self.download(dlURL, version: tag)
        }.resume()
    }

    private func download(_ url: URL, version: String) {
        URLSession.shared.downloadTask(with: url) { [weak self] local, _, err in
            guard let self, let local, err == nil else { return }
            do { try self.install(zip: local, version: version) }
            catch { self.log("oppdatering feilet: \(error.localizedDescription)") }
        }.resume()
    }

    private func install(zip: URL, version: String) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("pywhat-update-\(version)")
        try? fm.removeItem(at: tmp)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, tmp.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            log("utpakking feilet"); return
        }

        let newApp = tmp.appendingPathComponent("PyWhat.app")
        let newBinary = newApp.appendingPathComponent("Contents/MacOS/PyWhat")
        guard fm.fileExists(atPath: newBinary.path) else {
            log("ugyldig oppdateringspakke"); return
        }

        let dest = Bundle.main.bundlePath
        guard dest.hasSuffix("PyWhat.app") else { return }
        try? fm.removeItem(atPath: dest)
        do {
            try fm.moveItem(atPath: newApp.path, toPath: dest)
        } catch {
            try fm.copyItem(atPath: newApp.path, toPath: dest)
        }
        log("oppdatert til \(version) — relanserer")
        DispatchQueue.main.async { self.relaunch() }
    }

    private func relaunch() {
        // Under launchd (KeepAlive): bare avslutt, launchd starter oss på nytt.
        if getppid() == 1 { exit(0) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(Bundle.main.bundlePath)\""]
        try? p.run()
        exit(0)
    }

    func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func log(_ msg: String) {
        print("[UpdateService] \(msg)")
    }
}
