import SwiftUI
import AppKit
import Combine

final class AppState: ObservableObject {
    @Published var procs: [ProcEntry] = []
    @Published var docker: [DockerRow] = []
    @Published var showAll = false

    private var timer: Timer?
    private var scanning = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = ProcScan.scan()
            DispatchQueue.main.async {
                self?.procs = result.procs
                self?.docker = result.docker
                self?.scanning = false
            }
        }
    }

    func kill(pids: [Int32]) {
        for pid in pids { Darwin.kill(pid, SIGTERM) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@main
struct PyWhatApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(state)
        } label: {
            // Menylinja teller dev-prosessene — Apper-seksjonen er kontekst
            let dev = state.procs.filter { $0.category != "apps" }
            let totalKB = dev.reduce(0) { $0 + $1.rssKB }
            Image(systemName: "chart.bar.fill")
            Text("\(dev.count) · \(Fmt.memShort(kb: totalKB))")
        }
        .menuBarExtraStyle(.window)
    }
}
