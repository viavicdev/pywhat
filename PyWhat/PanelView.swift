import SwiftUI
import AppKit

enum IconCache {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let c = cache[name] { return c }
        guard let path = Bundle.main.path(forResource: name, ofType: nil),
              let img = NSImage(contentsOfFile: path) else { return nil }
        img.isTemplate = true
        cache[name] = img
        return img
    }
}

struct SectionIcon: View {
    let section: Design.Section
    var body: some View {
        if let asset = section.asset, let img = IconCache.image(asset) {
            Image(nsImage: img)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13)
                .foregroundColor(section.color)
        } else {
            Image(systemName: section.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(section.color)
        }
    }
}

struct ProcGroup: Identifiable {
    let name: String
    let sectionKey: String
    let procs: [ProcEntry]
    var id: String { "\(sectionKey)|\(name)" }
    var memKB: Int { procs.reduce(0) { $0 + $1.rssKB } }
    var ports: [Int] { Array(Set(procs.flatMap(\.ports))).sorted() }
    var isVisible: Bool {
        if sectionKey == "apps" { return memKB >= 100 * 1024 }
        return procs.contains(where: \.isInteresting)
            || procs.count >= ProcScan.groupAlwaysShow
            || memKB >= ProcScan.minKBAnon
    }
}

struct PanelView: View {
    @EnvironmentObject var state: AppState
    @State private var expanded: Set<String> = []
    @AppStorage("collapsedSections") private var collapsedRaw = ""

    private var collapsed: Set<String> {
        Set(collapsedRaw.split(separator: ",").map(String.init))
    }

    private func toggleSection(_ key: String) {
        var s = collapsed
        if s.contains(key) { s.remove(key) } else { s.insert(key) }
        withAnimation(.easeInOut(duration: 0.15)) {
            collapsedRaw = s.sorted().joined(separator: ",")
        }
    }

    private var devProcs: [ProcEntry] { state.procs.filter { $0.category != "apps" } }
    private var totalKB: Int { devProcs.reduce(0) { $0 + $1.rssKB } }

    private func groups(for sectionKey: String) -> [ProcGroup] {
        let catProcs = state.procs.filter { $0.category == sectionKey }
        var order: [String] = []
        var byName: [String: [ProcEntry]] = [:]
        for p in catProcs {
            if byName[p.name] == nil { order.append(p.name) }
            byName[p.name, default: []].append(p)
        }
        var result = order
            .map { ProcGroup(name: $0, sectionKey: sectionKey, procs: byName[$0]!) }
            .filter { state.showAll || $0.isVisible }
        if sectionKey == "apps" {
            result.sort { $0.memKB > $1.memKB }
            if !state.showAll { result = Array(result.prefix(15)) }
        }
        return result
    }

    private var shownCount: Int {
        Design.procSections.reduce(0) { acc, s in
            acc + groups(for: s.key).reduce(0) { $0 + $1.procs.count }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Design.dividerColor)
            ScrollView {
                VStack(spacing: Design.sectionSpacing) {
                    ForEach(Design.procSections, id: \.key) { section in
                        let g = groups(for: section.key)
                        if !g.isEmpty {
                            sectionCard(section, groups: g)
                        }
                    }
                    if !state.docker.isEmpty {
                        dockerCard
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 540)
            Divider().overlay(Design.dividerColor)
            footer
        }
        .frame(width: 400)
        .background(Design.panelBackground)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PYWHAT")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(Design.subtleText)
                Text("\(devProcs.count) dev-prosesser  ·  \(Fmt.mem(kb: totalKB))")
                    .font(Design.headingFont)
                    .foregroundColor(Design.primaryText)
                    .monospacedDigit()
            }
            Spacer()
            Button { state.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(Design.IconButtonStyle())
            .help("Oppdater nå")
            Button {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: {
                Image(systemName: "gauge.with.needle")
            }
            .buttonStyle(Design.IconButtonStyle())
            .help("Åpne Aktivitetsmonitor")
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(Design.IconButtonStyle())
            .help("Avslutt PyWhat")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Seksjonskort

    private func sectionCard(_ section: Design.Section, groups: [ProcGroup]) -> some View {
        let count = groups.reduce(0) { $0 + $1.procs.count }
        let memKB = groups.reduce(0) { $0 + $1.memKB }
        let isCollapsed = collapsed.contains(section.key)
        return VStack(alignment: .leading, spacing: isCollapsed ? 0 : 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(section.color.opacity(0.16))
                    SectionIcon(section: section)
                }
                .frame(width: 22, height: 22)
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(Design.subtleText)
                Spacer()
                Text("\(count)  ·  \(Fmt.mem(kb: memKB))")
                    .font(Design.captionFont)
                    .foregroundColor(Design.subtleText)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Design.subtleText)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleSection(section.key) }
            if !isCollapsed {
                VStack(spacing: 1) {
                    ForEach(groups) { group in
                        groupRow(group, color: section.color)
                        if expanded.contains(group.id) && group.procs.count > 1 {
                            ForEach(group.procs) { p in
                                nestedRow(p, color: section.color)
                            }
                        }
                    }
                }
            }
        }
        .padding(Design.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius)
                .fill(Design.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius)
                .stroke(Design.borderColor, lineWidth: 1)
        )
    }

    // MARK: Rader

    private func groupRow(_ group: ProcGroup, color: Color) -> some View {
        let multi = group.procs.count > 1
        let single = group.procs.first!
        return HStack(spacing: 6) {
            if multi {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Design.subtleText)
                    .rotationEffect(.degrees(expanded.contains(group.id) ? 90 : 0))
            }
            Text(group.name)
                .font(Design.labelFont)
                .foregroundColor(Design.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            if multi {
                Text("×\(group.procs.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            Spacer(minLength: 8)
            if !group.ports.isEmpty {
                Text(":" + group.ports.prefix(3).map(String.init).joined(separator: ","))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.12)))
            }
            Text(Fmt.mem(kb: group.memKB))
                .font(Design.captionFont)
                .foregroundColor(Design.subtleText)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            if !multi && !single.age.isEmpty {
                Text(single.age)
                    .font(Design.captionFont)
                    .foregroundColor(Design.subtleText)
                    .frame(width: 26, alignment: .trailing)
            } else if multi {
                Spacer().frame(width: 26)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard multi else { return }
            withAnimation(.easeInOut(duration: 0.12)) {
                if expanded.contains(group.id) { expanded.remove(group.id) }
                else { expanded.insert(group.id) }
            }
        }
        .contextMenu {
            if multi {
                Button("Stopp alle (\(group.procs.count))") {
                    state.kill(pids: group.procs.map(\.pid))
                }
            } else {
                Button("Stopp \(group.name)") { state.kill(pids: [single.pid]) }
                Button("Kopier kommando") { state.copyToClipboard(single.command) }
            }
        }
        .help(multi ? "\(group.procs.count) prosesser — klikk for detaljer" : single.command)
    }

    private func nestedRow(_ p: ProcEntry, color: Color) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 14)
            if !p.detail.isEmpty {
                Text(p.detail)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.12)))
            }
            Text("PID \(String(p.pid))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Design.subtleText)
            Spacer(minLength: 8)
            Text(p.memStr)
                .font(Design.captionFont)
                .foregroundColor(Design.subtleText)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            Text(p.age)
                .font(Design.captionFont)
                .foregroundColor(Design.subtleText)
                .frame(width: 26, alignment: .trailing)
            Button { state.kill(pids: [p.pid]) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Design.subtleText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Stopp PID \(String(p.pid))")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Stopp PID \(String(p.pid))") { state.kill(pids: [p.pid]) }
            Button("Kopier kommando") { state.copyToClipboard(p.command) }
        }
        .help(p.command)
    }

    private var dockerCard: some View {
        let section = Design.dockerSection
        let isCollapsed = collapsed.contains(section.key)
        return VStack(alignment: .leading, spacing: isCollapsed ? 0 : 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(section.color.opacity(0.16))
                    SectionIcon(section: section)
                }
                .frame(width: 22, height: 22)
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(Design.subtleText)
                Spacer()
                Text("\(state.docker.count)")
                    .font(Design.captionFont)
                    .foregroundColor(Design.subtleText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Design.subtleText)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleSection(section.key) }
            if !isCollapsed {
                dockerRows
            }
        }
        .padding(Design.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius)
                .fill(Design.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius)
                .stroke(Design.borderColor, lineWidth: 1)
        )
    }

    private var dockerRows: some View {
        let section = Design.dockerSection
        return VStack(spacing: 1) {
                ForEach(state.docker) { c in
                    HStack(spacing: 6) {
                        Text(c.name)
                            .font(Design.labelFont)
                            .foregroundColor(Design.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if !c.ports.isEmpty {
                            Text(c.ports)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(section.color)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(section.color.opacity(0.12)))
                        }
                        Text(c.status)
                            .font(Design.captionFont)
                            .foregroundColor(Design.subtleText)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            let hidden = max(0, state.procs.count - shownCount)
            Button(state.showAll ? "Vis bare viktige" : "Vis alle (\(hidden) skjult)") {
                state.showAll.toggle()
            }
            .buttonStyle(Design.PillButtonStyle())
            Spacer()
            Text("v\(UpdateService.shared.currentVersion) · auto-oppdatering")
                .font(Design.captionFont)
                .foregroundColor(Design.subtleText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
