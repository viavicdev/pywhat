# PyWhat

Native SwiftUI-menylinjeapp som viser *hva* prosessene på maskinen faktisk er —
ikke bare «Python», «node» eller 20 anonyme «Chrome Helper» som i Aktivitetsmonitor.
Samme designspråk som TankeGeni / Ny Mappe 7: mørkt panel, kort med runde hjørner,
rounded font, egne SVG-ikoner og SF Symbols (ingen emojis).

Menylinja viser `antall · totalminne` for **dev-prosessene** (Apper-seksjonen
telles ikke med der — den er kontekst).

## Seksjoner

| Seksjon | Ikon | Hva |
| --- | --- | --- |
| Agenter | `agents.svg` | claude/codex-CLI-økter, navngitt med prosjekt via arbeidsmappe (`claude · Podcast ×2`) |
| Cursor | `cursor.svg` | Extension-hosts per Cursor-prosjekt, med rolle-chip (user / agent-exec / retrieval / always-local) |
| Python | SF Symbol | Alle Python-prosesser — scriptnavn, `-m`-moduler, uvicorn-apper |
| Node | `node.svg` | Node/Bun/Deno — prosjektnavn fra `package.json`, MCP-servere, electron |
| Verktøy | SF Symbol | ollama, ffmpeg, ffprobe, yt-dlp, redis, postgres, mysql, colima, streamlit |
| Apper | SF Symbol | Alt annet som bruker RAM — gruppert per app-bundle (Chrome + alle helpers = én rad). Viser ≥100 MB, topp 15, sortert på minne |
| Docker | SF Symbol | Kjørende containere med porter (kun når daemon er oppe) |

## Interaksjon

- **Kollaps seksjoner**: klikk på seksjonsheaderen — tilstanden huskes mellom omstarter.
- **Utvid grupper**: klikk på en gruppert rad (`Playwright MCP ×27`) for PID-rader
  med rolle, minne, alder (`3d`/`5t`/`42m`) og ✕-knapp per prosess.
- **Høyreklikk** på rad: «Stopp» / «Stopp alle» / «Kopier kommando».
  Hold musa over en rad for hele kommandolinja.
- **Footer**: «Vis alle» slipper løs småprosessene som filtreres bort som standard.
- **Header**: oppdater-knapp, Aktivitetsmonitor, avslutt. Auto-refresh hvert 5. sek.

## Navne-logikk (ProcessScanner.swift)

- claude/codex-økter og anonyme prosesser (`python -c`, script uten sti) navngis
  med **arbeidsmappen** sin (batchet `lsof -d cwd`).
- Node-prosesser får prosjektnavn fra nærmeste `package.json`.
- Generiske scriptnavn (`server.py`) får mappe-prefiks (`victoria-mcp/server.py`).
- `known`-mappen gir visningsnavn (f.eks. `agent_bridge.py` → «Synapse Bridge»).
- `projectCaps` tvinger casing på prosjektnavn (ink → INK, kit → KIT, vps → VPS).
- Porter parses fra `lsof -iTCP -sTCP:LISTEN`; alder fra `ps etime`.

## Mappe

```text
apps/pywhat/
├── PyWhat/
│   ├── PyWhatApp.swift       # app + AppState (5 s refresh-timer)
│   ├── ProcessScanner.swift  # ps/lsof/docker + all navne-logikk
│   ├── DesignTokens.swift    # TankeGeni-tokens + seksjonsdefinisjoner
│   └── PanelView.swift       # panelet (kort, rader, kollaps)
├── Assets/
│   ├── AppIcon.icns          # app-ikon (generert)
│   └── agents.svg / node.svg / cursor.svg   # seksjonsikoner (Victorias)
├── build.sh                  # swiftc → .app → /Applications (TankeGeni-mønster)
├── pywhat_menubar.py         # LEGACY: gammel rumps-versjon (fallback)
└── start.sh                  # LEGACY: manuell start av python-versjonen
```

## Bygge på nytt

```bash
./apps/pywhat/build.sh
launchctl kickstart -k gui/$(id -u)/no.synapse.pywhat
```

## Drift (utenfor denne mappa)

| Fil | Rolle |
| --- | --- |
| `~/bin/synapse-pywhat.sh` | LaunchAgent-wrapper — exec'er `/Applications/PyWhat.app/Contents/MacOS/PyWhat` |
| `~/Library/LaunchAgents/no.synapse.pywhat.plist` | Auto-start ved login (KeepAlive) |
| `/tmp/synapse-pywhat.log` | Logg |

## Utvide

- **Nytt verktøy**: legg binærnavnet i `toolBinaries` i `ProcessScanner.swift`.
- **Penere navn**: legg inn i `known`-mappen (script-/pakkenavn → visningsnavn).
- **Prosjekt-casing**: legg inn i `projectCaps` (mappenavn → visningsnavn).
- **Bytte seksjonsikon**: legg en monokrom SVG i `Assets/` og sett
  `asset: "filnavn.svg"` på seksjonen i `DesignTokens.swift` — den tintes
  automatisk med seksjonsfargen. (SVG-en må ha absolutte width/height, ikke `1em`.)

Historikk: startet som rumps/Python-app (Cursor-generert) 19. juli 2026, samme dag
utvidet med Node/agenter/Cursor/cwd-labels og skrevet om til native SwiftUI.
