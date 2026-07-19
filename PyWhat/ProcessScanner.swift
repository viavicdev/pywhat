import Foundation

// MARK: - Modeller

struct ProcEntry: Identifiable, Hashable {
    let pid: Int32
    let rssKB: Int
    let command: String
    let category: String
    var name: String
    var age: String = ""
    var detail: String = ""
    var ports: [Int] = []

    var id: Int32 { pid }
    var memStr: String { Fmt.mem(kb: rssKB) }

    var isInteresting: Bool {
        if !ports.isEmpty { return true }
        if ProcScan.knownNames.contains(name) { return true }
        if !name.isEmpty && !name.hasSuffix("(app-intern)") {
            return rssKB >= ProcScan.minKBDefault
        }
        return rssKB >= ProcScan.minKBAnon
    }
}

struct DockerRow: Identifiable, Hashable {
    let name: String
    let ports: String
    let status: String
    var id: String { name }
}

enum Fmt {
    static func mem(kb: Int) -> String {
        let mb = Double(kb) / 1024
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        if mb >= 10 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f MB", mb)
    }

    static func memShort(kb: Int) -> String {
        let mb = Double(kb) / 1024
        if mb >= 1024 { return String(format: "%.1fG", mb / 1024) }
        return String(format: "%.0fM", mb)
    }
}

// MARK: - Regex-hjelpere (cachet NSRegularExpression)

private var rxCache: [String: NSRegularExpression] = [:]

private func rx(_ pattern: String) -> NSRegularExpression {
    if let c = rxCache[pattern] { return c }
    let r = try! NSRegularExpression(pattern: pattern)
    rxCache[pattern] = r
    return r
}

private func rxFirst(_ pattern: String, _ text: String) -> [String]? {
    let range = NSRange(text.startIndex..., in: text)
    guard let m = rx(pattern).firstMatch(in: text, range: range) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        guard let r = Range(m.range(at: i), in: text) else { return "" }
        return String(text[r])
    }
}

private func rxAll(_ pattern: String, _ text: String) -> [String] {
    let range = NSRange(text.startIndex..., in: text)
    return rx(pattern).matches(in: text, range: range).compactMap { m in
        guard let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

// MARK: - Scanner

enum ProcScan {
    static let minKBDefault = 8 * 1024
    static let minKBAnon = 30 * 1024
    static let groupAlwaysShow = 3

    static let selfHints = ["pywhat_menubar.py", "PyWhat.app"]
    static let agentBinaries: Set<String> = ["claude", "codex", "cursor-agent"]
    static let toolBinaries: Set<String> = [
        "ollama", "ffmpeg", "ffprobe", "yt-dlp", "streamlit",
        "redis-server", "postgres", "mysqld", "colima",
    ]

    static let known: [String: String] = [
        "chatterbox_tts_server.py": "Chatterbox TTS",
        "gadgets_launcher.py": "Gadgets Launcher",
        "scripts.gadgets_launcher": "Gadgets Launcher",
        "agent_bridge.py": "Synapse Bridge",
        "scripts.agent_bridge": "Synapse Bridge",
        "margen.py": "Margen",
        "synops.py": "SynOps",
        "disk_agent.py": "Disk Agent",
        "tts_server.py": "TTS Server",
        "kontekst_app.py": "Kontekst",
        "playwright-mcp": "Playwright MCP",
        "dev-dashboard": "Synapse Dashboard",
        "ollama": "Ollama",
        "skyvern": "Skyvern",
        "skyvern-agent": "Skyvern Agent",
    ]
    static let knownNames: Set<String> = Set(known.values)

    static let genericPy: Set<String> = [
        "server.py", "main.py", "app.py", "run.py", "start.py",
        "index.py", "__main__.py", "manage.py",
    ]
    static let genericJS: Set<String> = [
        "index.js", "server.js", "main.js", "app.js", "start.js",
        "cli.js", "index.mjs",
    ]
    static let noiseDirs: Set<String> = ["bin", "src", "lib", "dist", "build", "scripts"]

    // Prosjektnavn som skal vises med riktig casing uansett mappenavn
    static let projectCaps: [String: String] = ["ink": "INK", "kit": "KIT", "vps": "VPS"]

    static func prettyProject(_ name: String) -> String {
        projectCaps[name.lowercased()] ?? name
    }

    private static var pkgCache: [String: String] = [:]

    // MARK: Kommandokjøring

    @discardableResult
    static func runCmd(_ path: String, _ args: [String], timeout: Double = 3) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }

        var data = Data()
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = sem.wait(timeout: .now() + 1)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Navne-hjelpere

    static func isNoiseDir(_ name: String) -> Bool {
        if name.isEmpty || name.hasPrefix(".") || name.hasPrefix("_") { return true }
        if rxFirst("^[0-9a-f]{8,}$", name) != nil { return true }
        return noiseDirs.contains(name)
    }

    static func appBundle(_ cmd: String) -> String {
        rxFirst("/([^/]+)\\.app/Contents/", cmd)?[1] ?? ""
    }

    static func dirLabel(_ path: String) -> String {
        if path.isEmpty || path == "/" { return "" }
        if path == NSHomeDirectory() { return "~" }
        let ns = path.hasSuffix("/") ? String(path.dropLast()) : path
        let base = (ns as NSString).lastPathComponent
        if isNoiseDir(base) {
            let parent = ((ns as NSString).deletingLastPathComponent as NSString).lastPathComponent
            return parent.isEmpty ? base : prettyProject(parent)
        }
        return prettyProject(base)
    }

    static func pkgName(_ startDir: String) -> String {
        if let c = pkgCache[startDir] { return c }
        var d = startDir
        for _ in 0..<6 {
            if d.isEmpty || d == "/" { break }
            let pj = (d as NSString).appendingPathComponent("package.json")
            if let data = FileManager.default.contents(atPath: pj),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = obj["name"] as? String {
                pkgCache[startDir] = name
                return name
            }
            d = (d as NSString).deletingLastPathComponent
        }
        pkgCache[startDir] = ""
        return ""
    }

    static func ageString(_ etime: String) -> String {
        let e = etime.trimmingCharacters(in: .whitespaces)
        if e.contains("-") {
            let days = e.split(separator: "-")[0]
            return "\(Int(days) ?? 0)d"
        }
        let parts = e.split(separator: ":")
        if parts.count == 3 {
            let h = Int(parts[0]) ?? 0
            return h > 0 ? "\(h)t" : "\(Int(parts[1]) ?? 0)m"
        }
        if parts.count == 2 {
            let m = Int(parts[0]) ?? 0
            return m > 0 ? "\(m)m" : "<1m"
        }
        return ""
    }

    static func pythonName(_ cmd: String) -> String {
        var path = ""
        var base = ""
        if let g = rxFirst("(/[^ ]+\\.py)\\b", cmd) {
            path = g[1]
            base = (path as NSString).lastPathComponent
        }
        if base.isEmpty, let g = rxFirst("\\b([A-Za-z0-9_.-]+\\.py)\\b", cmd) { base = g[1] }
        if base.isEmpty, let g = rxFirst("\\buvicorn +([A-Za-z0-9_.:]+)", cmd) {
            base = String(g[1].split(separator: ":")[0])
        }
        if base.isEmpty, let g = rxFirst("(?:^| )-m +([A-Za-z0-9_.]+)", cmd) { base = g[1] }
        if base.isEmpty {
            // Script uten .py-endelse, "-" (stdin) eller "-c" (inline kode)
            let args = cmd.split(separator: " ").dropFirst().map(String.init)
            if args.prefix(3).contains("-c") { return "(python -c)" }
            for t in args {
                if t == "-" { return "(python stdin)" }
                if t.hasPrefix("-") { continue }
                let b = (t as NSString).lastPathComponent
                if !b.isEmpty && !b.lowercased().hasPrefix("python") {
                    let parent = ((t as NSString).deletingLastPathComponent as NSString).lastPathComponent
                    if b.count <= 3 && !parent.isEmpty && !isNoiseDir(parent) {
                        return "\(parent)/\(b)"
                    }
                    return known[b] ?? b
                }
                break
            }
            return ""
        }
        if let k = known[base] { return k }
        if genericPy.contains(base) && !path.isEmpty {
            let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if !parent.isEmpty && !isNoiseDir(parent) { return "\(parent)/\(base)" }
        }
        return base
    }

    static func nodeName(_ cmd: String) -> String {
        let toks = cmd.split(separator: " ").map(String.init)
        var target = ""
        for t in toks.dropFirst() where !t.hasPrefix("-") {
            target = t
            break
        }
        if target.isEmpty || target == "." { return "(node)" }
        var base = (target as NSString).lastPathComponent
        if base == "npm-cli.js" || base == "npx-cli.js" {
            if let idx = toks.firstIndex(of: target) {
                let rest = toks.dropFirst(idx + 1).prefix(2).joined(separator: " ")
                return rest.isEmpty ? "npm" : "npm \(rest)"
            }
            return "npm"
        }

        var project = ""
        if let range = target.range(of: "/node_modules/") {
            let before = String(target[..<range.lowerBound])
            let cand = (before as NSString).lastPathComponent
            if !isNoiseDir(cand) { project = cand }
        } else if target.hasPrefix("/") {
            project = pkgName((target as NSString).deletingLastPathComponent)
            if project.isEmpty {
                let parent = ((target as NSString).deletingLastPathComponent as NSString).lastPathComponent
                if !isNoiseDir(parent) { project = parent }
            }
        }
        project = known[project] ?? prettyProject(project)

        if base == "electron" {
            return project.isEmpty ? "electron" : "\(project) (electron)"
        }
        if genericJS.contains(base) {
            return project.isEmpty ? base : project
        }
        base = known[base] ?? base
        if !project.isEmpty && !base.lowercased().contains(project.lowercased()) {
            return "\(base) · \(project)"
        }
        return base
    }

    // MARK: Prosess-skann

    static func listProcs() -> [ProcEntry] {
        let out = runCmd("/bin/ps", ["-axo", "pid=,rss=,etime=,command="], timeout: 5)
        var procs: [ProcEntry] = []

        for line in out.split(separator: "\n") {
            guard let g = rxFirst("^\\s*(\\d+)\\s+(\\d+)\\s+(\\S+)\\s+(.+)$", String(line)),
                  let pid = Int32(g[1]), let rss = Int(g[2]) else { continue }
            let age = ageString(g[3])
            let cmd = g[4]

            // "Cursor Helper (Plugin): extension-host (user) Synapse [2-5]"
            if let host = rxFirst(
                "^(?:Cursor|Code) Helper \\(Plugin\\): extension-host \\(([^)]*)\\)\\s*(.*)$", cmd
            ) {
                var proj = host[2].replacingOccurrences(
                    of: "\\s*\\[[\\d\\-]+\\]\\s*$", with: "", options: .regularExpression
                ).trimmingCharacters(in: .whitespaces)
                proj = prettyProject(proj)
                if proj.isEmpty { proj = "extension-host (\(host[1]))" }
                procs.append(ProcEntry(pid: pid, rssKB: rss, command: cmd,
                                       category: "cursor", name: proj,
                                       age: age, detail: host[1]))
                continue
            }

            guard let firstTok = cmd.split(separator: " ").first else { continue }
            let base = (String(firstTok) as NSString).lastPathComponent.lowercased()
            let bundle = appBundle(cmd)

            let category: String
            if base.hasPrefix("python") { category = "python" }
            else if base == "node" || base == "bun" || base == "deno" { category = "node" }
            else if agentBinaries.contains(base) {
                // Claude.app-interne prosesser heter også "claude" — CLI-øktene er
                // agenter, app-prosessene grupperes under Apper
                category = bundle.isEmpty ? "agents" : "apps"
            }
            else if toolBinaries.contains(base) { category = "tools" }
            else { category = "apps" }

            if selfHints.contains(where: { cmd.contains($0) }) { continue }
            if category != "apps" && (cmd.contains("Cursor Helper") || cmd.contains("Code Helper")) { continue }

            if category == "apps" {
                // Alt annet som bruker RAM — grupperes per app-bundle
                var name = bundle
                var detail = ""
                if !bundle.isEmpty {
                    let all = rxAll("/([^/]+)\\.app/", cmd)
                    if let last = all.last, last != name {
                        detail = last.hasPrefix(name)
                            ? String(last.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
                            : last
                    }
                } else {
                    name = (String(firstTok) as NSString).lastPathComponent
                }
                if name.isEmpty { continue }
                procs.append(ProcEntry(pid: pid, rssKB: rss, command: cmd,
                                       category: "apps", name: name,
                                       age: age, detail: detail))
                continue
            }

            if category == "agents" {
                procs.append(ProcEntry(pid: pid, rssKB: rss, command: cmd,
                                       category: "agents", name: base, age: age))
                continue
            }

            var name = ""
            if category == "python" { name = pythonName(cmd) }
            else if category == "node" && (bundle.isEmpty || bundle == "Python") { name = nodeName(cmd) }
            else if category == "tools" { name = known[base] ?? base }
            if (name.isEmpty || name == "(node)") && !bundle.isEmpty && bundle != "Python" {
                name = "\(bundle) (app-intern)"
            }

            procs.append(ProcEntry(pid: pid, rssKB: rss, command: cmd,
                                   category: category, name: name, age: age))
        }

        // Berik anonyme prosesser med arbeidsmappe (= prosjekt)
        var needCwd: [Int] = []
        for (i, p) in procs.enumerated() {
            let anonNames = ["", "(python -c)", "(python stdin)", "(node)"]
            let relJS = p.category == "node" && rxFirst("^[\\w.-]+\\.(js|mjs|cjs|ts)$", p.name) != nil
            if p.category == "agents" || anonNames.contains(p.name) || relJS {
                needCwd.append(i)
            }
        }
        if !needCwd.isEmpty {
            let cwds = cwdByPid(needCwd.prefix(60).map { procs[$0].pid })
            for i in needCwd {
                guard let cwd = cwds[procs[i].pid] else { continue }
                let lbl = dirLabel(cwd)
                if lbl.isEmpty { continue }
                let old = procs[i].name
                procs[i].name = old.isEmpty ? "(python) · \(lbl)" : "\(old) · \(lbl)"
            }
        }

        return procs.sorted { $0.rssKB > $1.rssKB }
    }

    static func listeningPorts() -> [Int32: [Int]] {
        let out = runCmd("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"], timeout: 5)
        var byPid: [Int32: [Int]] = [:]
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 9, let pid = Int32(parts[1]) else { continue }
            // Siste kolonne er "(LISTEN)" — adressen står i nest siste
            let addr = parts[parts.count - 1] == "(LISTEN)" ? parts[parts.count - 2] : parts[parts.count - 1]
            guard let g = rxFirst(":(\\d+)$", addr), let port = Int(g[1]) else { continue }
            if byPid[pid]?.contains(port) != true {
                byPid[pid, default: []].append(port)
            }
        }
        for k in byPid.keys { byPid[k]?.sort() }
        return byPid
    }

    static func cwdByPid(_ pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let out = runCmd("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", list, "-Fn"], timeout: 3)
        var res: [Int32: String] = [:]
        var cur: Int32?
        for line in out.split(separator: "\n") {
            if line.hasPrefix("p") { cur = Int32(line.dropFirst()) }
            else if line.hasPrefix("n"), let c = cur { res[c] = String(line.dropFirst()) }
        }
        return res
    }

    static func dockerContainers() -> [DockerRow] {
        let candidates = ["/opt/homebrew/bin/docker", "/usr/local/bin/docker"]
        guard let docker = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return [] }
        let out = runCmd(docker, ["ps", "--format", "{{.Names}}\t{{.Ports}}\t{{.Status}}"], timeout: 2)
        var rows: [DockerRow] = []
        for line in out.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let name = cols.first, !name.isEmpty else { continue }
            let portsRaw = cols.count > 1 ? cols[1] : ""
            let status = cols.count > 2 ? cols[2] : ""
            let hostPorts = Set(rxAll(":(\\d+)->", portsRaw).compactMap(Int.init)).sorted()
            let pstr = hostPorts.isEmpty ? "" : ":" + hostPorts.prefix(4).map(String.init).joined(separator: ",")
            rows.append(DockerRow(name: name, ports: pstr, status: status))
        }
        return rows
    }

    static func scan() -> (procs: [ProcEntry], docker: [DockerRow]) {
        var procs = listProcs()
        let ports = listeningPorts()
        for i in procs.indices {
            // Cursor-hosts lytter på tilfeldige IPC-porter — bare støy
            procs[i].ports = procs[i].category == "cursor" ? [] : (ports[procs[i].pid] ?? [])
        }
        return (procs, dockerContainers())
    }
}
