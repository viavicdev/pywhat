#!/usr/bin/env python3
"""
PyWhat — menubar that shows WHAT your background processes actually are.

Activity Monitor only says "Python" or "node". This shows script/project name,
memory and listening ports — for Python, Node/Bun/Deno and common dev tools
(ollama, ffmpeg, yt-dlp, redis, postgres), plus Docker containers when the
daemon is up.
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
from collections import defaultdict
from dataclasses import dataclass, field

import rumps

REFRESH_SEC = 5
SELF_HINTS = ("pywhat_menubar.py",)
# Default view: skip tiny anonymous helpers unless they listen on a port
MIN_MB_DEFAULT = 8
MIN_MB_ANON = 30
# N+ identical procs = show the group even if each member is tiny (zombie MCPs!)
GROUP_ALWAYS_SHOW = 3

ICON_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.png")

SECTIONS = [
    ("agents", "🤖 AGENTER"),
    ("cursor", "🖱 CURSOR"),
    ("python", "🐍 PYTHON"),
    ("node", "🟩 NODE"),
    ("tools", "🧰 VERKTØY"),
]

AGENT_BINARIES = {"claude", "codex", "cursor-agent"}

# "Cursor Helper (Plugin): extension-host (user) Synapse [2-5]" → prosjektnavn
CURSOR_HOST_RE = re.compile(
    r"^(?:Cursor|Code) Helper \(Plugin\): extension-host \(([^)]*)\)\s*(.*)$"
)

TOOL_BINARIES = {
    "ollama", "ffmpeg", "ffprobe", "yt-dlp", "streamlit",
    "redis-server", "postgres", "mysqld", "colima",
}

KNOWN = {
    # Python
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
    # Node
    "playwright-mcp": "Playwright MCP",
    "dev-dashboard": "Synapse Dashboard",
    # Tools
    "ollama": "Ollama",
    "skyvern": "Skyvern",
    "skyvern-agent": "Skyvern Agent",
}

GENERIC_PY = {"server.py", "main.py", "app.py", "run.py", "start.py",
              "index.py", "__main__.py", "manage.py"}
GENERIC_JS = {"index.js", "server.js", "main.js", "app.js", "start.js",
              "cli.js", "index.mjs"}


@dataclass
class Proc:
    pid: int
    rss_kb: int
    command: str
    category: str
    name: str
    age: str = ""
    detail: str = ""
    ports: list[int] = field(default_factory=list)

    @property
    def label(self) -> str:
        return self.name or _short_cmd(self.command)

    @property
    def mem_str(self) -> str:
        return _fmt_mem(self.rss_kb)

    @property
    def port_str(self) -> str:
        if not self.ports:
            return ""
        return "  ·  :" + ",".join(str(p) for p in self.ports[:4])

    @property
    def is_interesting(self) -> bool:
        if self.ports:
            return True
        if self.name in KNOWN.values():
            return True
        if self.name and not self.name.endswith("(app-intern)"):
            return self.rss_kb >= MIN_MB_DEFAULT * 1024
        return self.rss_kb >= MIN_MB_ANON * 1024


def _fmt_mem(rss_kb: int) -> str:
    mb = rss_kb / 1024
    if mb >= 1024:
        return f"{mb / 1024:.1f} GB"
    if mb >= 10:
        return f"{mb:.0f} MB"
    return f"{mb:.1f} MB"


def _fmt_age(etime: str) -> str:
    """ps etime ([[dd-]hh:]mm:ss) → kort alder: 3d / 5t / 42m."""
    etime = etime.strip()
    if "-" in etime:
        return etime.split("-")[0].lstrip("0") + "d"
    parts = etime.split(":")
    if len(parts) == 3:
        h = int(parts[0])
        return f"{h}t" if h else f"{int(parts[1])}m"
    if len(parts) == 2:
        mins = int(parts[0])
        return f"{mins}m" if mins else "<1m"
    return ""


def _short_cmd(cmd: str) -> str:
    cmd = re.sub(r"\s+", " ", cmd).strip()
    if len(cmd) > 60:
        return cmd[:57] + "…"
    return cmd or "(ukjent)"


def _is_noise_dir(name: str) -> bool:
    return (not name or name.startswith(".") or name.startswith("_")
            or re.fullmatch(r"[0-9a-f]{8,}", name) is not None
            or name in ("bin", "src", "lib", "dist", "build", "scripts"))


def _app_bundle(cmd: str) -> str:
    m = re.search(r"/([^/]+)\.app/Contents/", cmd)
    return m.group(1) if m else ""


def _dir_label(path: str) -> str:
    """Kort prosjektnavn fra en mappesti (siste meningsfulle segment)."""
    if not path or path == "/":
        return ""
    if path == os.path.expanduser("~"):
        return "~"
    b = os.path.basename(path.rstrip("/"))
    if _is_noise_dir(b):
        parent = os.path.basename(os.path.dirname(path.rstrip("/")))
        return parent or b
    return b


def cwd_by_pid(pids: list[int]) -> dict[int, str]:
    """Arbeidsmappe per PID via én batchet lsof — avslører hvilket prosjekt
    f.eks. en claude-økt kjører i."""
    if not pids:
        return {}
    try:
        r = subprocess.run(
            ["lsof", "-a", "-d", "cwd", "-p", ",".join(map(str, pids)), "-Fn"],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except Exception:
        return {}
    res: dict[int, str] = {}
    cur: int | None = None
    for line in r.stdout.splitlines():
        if line.startswith("p"):
            try:
                cur = int(line[1:])
            except ValueError:
                cur = None
        elif line.startswith("n") and cur is not None:
            res[cur] = line[1:]
    return res


_pkg_cache: dict[str, str] = {}


def _pkg_name(start_dir: str) -> str:
    """Nearest package.json "name" walking upwards. Cached per dir."""
    if start_dir in _pkg_cache:
        return _pkg_cache[start_dir]
    d = start_dir
    for _ in range(6):
        if not d or d == "/":
            break
        try:
            with open(os.path.join(d, "package.json")) as f:
                name = json.load(f).get("name") or ""
            _pkg_cache[start_dir] = name
            return name
        except (OSError, ValueError):
            pass
        d = os.path.dirname(d)
    _pkg_cache[start_dir] = ""
    return ""


def _python_name(cmd: str) -> str:
    m = re.search(r"(/[^\s]+\.py)\b", cmd)
    path = m.group(1) if m else ""
    base = os.path.basename(path) if path else ""
    if not base:
        m = re.search(r"\b([A-Za-z0-9_.-]+\.py)\b", cmd)
        if m:
            base = m.group(1)
    if not base:
        m = re.search(r"\buvicorn\s+([A-Za-z0-9_.:]+)", cmd)
        if m:
            base = m.group(1).split(":")[0]
    if not base:
        m = re.search(r"(?:^|\s)-m\s+([A-Za-z0-9_.]+)", cmd)
        if m:
            base = m.group(1)
    if not base:
        # Script uten .py-endelse, "-" (stdin) eller "-c" (inline kode)
        args = cmd.split()[1:]
        if "-c" in args[:3]:
            return "(python -c)"
        for t in args:
            if t == "-":
                return "(python stdin)"
            if t.startswith("-"):
                continue
            b = os.path.basename(t.rstrip("/"))
            if b and not b.lower().startswith("python"):
                parent = os.path.basename(os.path.dirname(t))
                if len(b) <= 3 and parent and not _is_noise_dir(parent):
                    return f"{parent}/{b}"
                return KNOWN.get(b, b)
            break
        return ""
    if base in KNOWN:
        return KNOWN[base]
    if base in GENERIC_PY and path:
        parent = os.path.basename(os.path.dirname(path))
        if parent and not _is_noise_dir(parent):
            return f"{parent}/{base}"
    return base


def _node_name(cmd: str) -> str:
    toks = cmd.split()
    target = ""
    for t in toks[1:]:
        if t.startswith("-"):
            continue
        target = t
        break
    if not target or target == ".":
        return "(node)"
    base = os.path.basename(target.rstrip("/"))
    if base in ("npm-cli.js", "npx-cli.js"):
        idx = toks.index(target)
        rest = " ".join(toks[idx + 1:idx + 3])
        return f"npm {rest}".strip()

    project = ""
    if "/node_modules/" in target:
        cand = os.path.basename(target.split("/node_modules/")[0])
        if not _is_noise_dir(cand):
            project = cand
    elif target.startswith("/"):
        project = _pkg_name(os.path.dirname(target))
        if not project:
            parent = os.path.basename(os.path.dirname(target))
            if not _is_noise_dir(parent):
                project = parent
    project = KNOWN.get(project, project)

    if base == "electron":
        return f"{project} (electron)" if project else "electron"
    if base in GENERIC_JS:
        return project or base
    base = KNOWN.get(base, base)
    if project and project.lower() not in base.lower():
        return f"{base} · {project}"
    return base


def list_procs() -> list[Proc]:
    try:
        out = subprocess.check_output(
            ["ps", "-axo", "pid=,rss=,etime=,command="],
            text=True,
            errors="replace",
        )
    except subprocess.CalledProcessError:
        return []

    procs: list[Proc] = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        try:
            pid = int(parts[0])
            rss = int(parts[1])
        except ValueError:
            continue
        age = _fmt_age(parts[2])
        cmd = parts[3]
        if not cmd.split():
            continue

        hostm = CURSOR_HOST_RE.match(cmd)
        if hostm:
            proj = re.sub(r"\s*\[[\d\-]+\]\s*$", "", hostm.group(2)).strip()
            procs.append(Proc(
                pid=pid, rss_kb=rss, command=cmd, category="cursor",
                name=proj or f"extension-host ({hostm.group(1)})",
                age=age, detail=hostm.group(1),
            ))
            continue

        base = os.path.basename(cmd.split()[0]).lower()

        if base.startswith("python"):
            category = "python"
        elif base in ("node", "bun", "deno"):
            category = "node"
        elif base in AGENT_BINARIES:
            category = "agents"
        elif base in TOOL_BINARIES:
            category = "tools"
        else:
            continue

        if any(h in cmd for h in SELF_HINTS):
            continue
        if "Cursor Helper" in cmd or "Code Helper" in cmd:
            continue
        if category == "agents":
            # Claude.app-interne prosesser heter også "claude" — hopp over,
            # vi vil bare ha CLI-øktene (navngis med prosjekt via cwd under)
            if _app_bundle(cmd):
                continue
            procs.append(Proc(pid=pid, rss_kb=rss, command=cmd,
                              category="agents", name=base, age=age))
            continue

        # NB: framework-Python kjører alltid via Python.app-bundle — script-navnet
        # må trekkes ut først, ellers blir alt "Python (app-intern)"
        bundle = _app_bundle(cmd)
        name = ""
        if category == "python":
            name = _python_name(cmd)
        elif category == "node" and not (bundle and bundle != "Python"):
            name = _node_name(cmd)
        elif category == "tools":
            name = KNOWN.get(base, base)
        if (not name or name == "(node)") and bundle and bundle != "Python":
            name = f"{bundle} (app-intern)"

        procs.append(Proc(pid=pid, rss_kb=rss, command=cmd,
                          category=category, name=name, age=age))

    # Berik anonyme prosesser med arbeidsmappe (= prosjekt)
    need_cwd = [
        p for p in procs
        if p.category == "agents"
        or p.name in ("", "(python -c)", "(python stdin)", "(node)")
        or (p.category == "node"
            and re.fullmatch(r"[\w.-]+\.(js|mjs|cjs|ts)", p.name or ""))
    ]
    cwds = cwd_by_pid([p.pid for p in need_cwd][:60])
    for p in need_cwd:
        lbl = _dir_label(cwds.get(p.pid, ""))
        if not lbl:
            continue
        p.name = f"{p.name} · {lbl}" if p.name else f"(python) · {lbl}"

    procs.sort(key=lambda p: p.rss_kb, reverse=True)
    return procs


def listening_ports_by_pid() -> dict[int, list[int]]:
    try:
        out = subprocess.check_output(
            ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN"],
            text=True,
            errors="replace",
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}

    by_pid: dict[int, list[int]] = {}
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 9:
            continue
        try:
            pid = int(parts[1])
        except ValueError:
            continue
        # Siste kolonne er "(LISTEN)" — adressen står i nest siste
        addr = parts[-2] if parts[-1] == "(LISTEN)" else parts[-1]
        m = re.search(r":(\d+)$", addr)
        if not m:
            continue
        port = int(m.group(1))
        by_pid.setdefault(pid, [])
        if port not in by_pid[pid]:
            by_pid[pid].append(port)
    for pid in by_pid:
        by_pid[pid].sort()
    return by_pid


_docker_bin: str | None = None


def _find_docker() -> str:
    global _docker_bin
    if _docker_bin is not None:
        return _docker_bin
    for cand in ("/opt/homebrew/bin/docker", "/usr/local/bin/docker", "docker"):
        if cand == "docker" or os.path.exists(cand):
            _docker_bin = cand
            return cand
    _docker_bin = ""
    return ""


def docker_containers() -> list[tuple[str, str, str]]:
    """(name, port_str, status) per running container. Empty if daemon down."""
    docker = _find_docker()
    if not docker:
        return []
    try:
        out = subprocess.check_output(
            [docker, "ps", "--format", "{{.Names}}\t{{.Ports}}\t{{.Status}}"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except Exception:
        return []
    rows = []
    for line in out.splitlines():
        cols = line.split("\t")
        if not cols or not cols[0].strip():
            continue
        ports_raw = cols[1] if len(cols) > 1 else ""
        status = cols[2] if len(cols) > 2 else ""
        host_ports = sorted({int(p) for p in re.findall(r":(\d+)->", ports_raw)})
        pstr = "  ·  :" + ",".join(map(str, host_ports[:4])) if host_ports else ""
        rows.append((cols[0].strip(), pstr, status))
    return rows


def kill_pid(pid: int) -> str:
    try:
        os.kill(pid, signal.SIGTERM)
        return f"Stoppet PID {pid}"
    except ProcessLookupError:
        return f"PID {pid} finnes ikke lenger"
    except PermissionError:
        return f"Ingen tillatelse til å stoppe PID {pid}"
    except OSError as e:
        return f"Feil: {e}"


def _notify(subtitle: str, message: str) -> None:
    try:
        rumps.notification("PyWhat", subtitle, message)
    except Exception:
        pass


class PyWhatApp(rumps.App):
    def __init__(self) -> None:
        icon = ICON_PATH if os.path.exists(ICON_PATH) else None
        super().__init__("PyWhat", title="…", icon=icon,
                         template=True, quit_button=None)
        self.show_all = False
        self.menu = ["Laster…"]
        rumps.Timer(self.refresh, REFRESH_SEC).start()
        self.refresh(None)

    def refresh(self, _sender=None) -> None:
        procs = list_procs()
        ports = listening_ports_by_pid()
        for p in procs:
            # Cursor-hosts lytter på tilfeldige IPC-porter — bare støy
            p.ports = [] if p.category == "cursor" else ports.get(p.pid, [])
        containers = docker_containers()

        total_mb = sum(p.rss_kb for p in procs) / 1024
        mem_short = f"{total_mb / 1024:.1f}G" if total_mb >= 1024 else f"{total_mb:.0f}M"
        self.title = f" {len(procs)} · {mem_short}" if procs else " 0"

        items: list = []
        if not procs and not containers:
            items.append(rumps.MenuItem("Ingen dev-prosesser funnet"))
        else:
            header = rumps.MenuItem(
                f"{len(procs)} prosesser  ·  {_fmt_mem(int(total_mb * 1024))}"
            )
            header.set_callback(None)
            items.append(header)

        shown_count = 0
        for cat_key, cat_title in SECTIONS:
            cat_procs = [p for p in procs if p.category == cat_key]
            if not cat_procs:
                continue

            # Group identical labels (e.g. 28× playwright-mcp)
            groups: dict[str, list[Proc]] = defaultdict(list)
            order: list[str] = []
            for p in cat_procs:
                if p.label not in groups:
                    order.append(p.label)
                groups[p.label].append(p)

            visible_keys = []
            for key in order:
                g = groups[key]
                if (self.show_all
                        or any(p.is_interesting for p in g)
                        or len(g) >= GROUP_ALWAYS_SHOW
                        or sum(p.rss_kb for p in g) >= MIN_MB_ANON * 1024):
                    visible_keys.append(key)
            if not visible_keys:
                continue

            cat_mb = sum(p.rss_kb for p in cat_procs) / 1024
            items.append(None)
            sec = rumps.MenuItem(
                f"{cat_title}  —  {len(cat_procs)} · {_fmt_mem(int(cat_mb * 1024))}"
            )
            sec.set_callback(None)
            items.append(sec)

            for key in visible_keys:
                group = groups[key]
                shown_count += len(group)
                if len(group) == 1:
                    items.append(self._proc_menu(group[0]))
                else:
                    gmem = sum(x.rss_kb for x in group)
                    gports = sorted({pt for x in group for pt in x.ports})
                    port_bit = (
                        "  ·  :" + ",".join(str(p) for p in gports[:4])
                        if gports else ""
                    )
                    parent = rumps.MenuItem(
                        f"{key}  ×{len(group)}   {_fmt_mem(gmem)}{port_bit}"
                    )
                    parent.add(rumps.MenuItem(
                        f"Stopp alle ({len(group)})",
                        callback=self._make_kill_group_cb(
                            [x.pid for x in group], key),
                    ))
                    parent.add(None)
                    for p in group:
                        parent.add(self._proc_menu(p, nested=True))
                    items.append(parent)

        if containers:
            items.append(None)
            sec = rumps.MenuItem(f"🐳 DOCKER  —  {len(containers)}")
            sec.set_callback(None)
            items.append(sec)
            for cname, cports, cstatus in containers:
                ci = rumps.MenuItem(f"{cname}{cports}   ({cstatus})")
                ci.set_callback(None)
                items.append(ci)

        hidden = len(procs) - shown_count
        items.append(None)
        if hidden > 0 and not self.show_all:
            items.append(rumps.MenuItem(
                f"Vis alle ({hidden} skjult)…", callback=self._toggle_all))
        elif self.show_all:
            items.append(rumps.MenuItem(
                "Vis bare viktige", callback=self._toggle_all))
        items.append(rumps.MenuItem("Oppdater nå", callback=self.refresh))
        items.append(rumps.MenuItem(
            "Åpne Aktivitetsmonitor", callback=self._open_activity))
        items.append(None)
        items.append(rumps.MenuItem("Avslutt PyWhat", callback=self._quit))

        self.menu.clear()
        for it in items:
            self.menu.add(it)

    def _proc_menu(self, p: Proc, nested: bool = False) -> rumps.MenuItem:
        if nested:
            kind = f"{p.detail}  ·  " if p.detail else ""
            age = f" · {p.age}" if p.age else ""
            title = f"{kind}PID {p.pid}   {p.mem_str}{age}{p.port_str}"
        else:
            title = f"{p.label}   {p.mem_str}{p.port_str}"
        parent = rumps.MenuItem(title)
        info_bits = [f"PID {p.pid}"]
        if p.detail:
            info_bits.append(p.detail)
        if p.age:
            info_bits.append(f"oppe {p.age}")
        detail = rumps.MenuItem(" · ".join(info_bits))
        detail.set_callback(None)
        parent.add(detail)
        cmd_item = rumps.MenuItem(
            p.command if len(p.command) <= 90 else p.command[:87] + "…"
        )
        cmd_item.set_callback(None)
        parent.add(cmd_item)
        parent.add(None)
        parent.add(
            rumps.MenuItem("Kopier kommando", callback=self._make_copy_cb(p.command))
        )
        parent.add(
            rumps.MenuItem(
                f"Stopp ({p.label})",
                callback=self._make_kill_cb(p.pid, p.label),
            )
        )
        return parent

    def _toggle_all(self, _):
        self.show_all = not self.show_all
        self.refresh(None)

    def _make_kill_cb(self, pid: int, label: str):
        def _cb(_):
            _notify(label, kill_pid(pid))
            self.refresh(None)

        return _cb

    def _make_kill_group_cb(self, pids: list[int], label: str):
        def _cb(_):
            results = [kill_pid(p) for p in pids]
            ok = sum(1 for r in results if r.startswith("Stoppet"))
            _notify(label, f"Stoppet {ok} av {len(pids)}")
            self.refresh(None)

        return _cb

    def _make_copy_cb(self, text: str):
        def _cb(_):
            try:
                subprocess.run(["pbcopy"], input=text.encode(), check=True)
                _notify("Kopiert", "Kommandoen er i utklippstavlen")
            except Exception as e:
                _notify("Feil", str(e))

        return _cb

    def _open_activity(self, _):
        subprocess.Popen(["open", "-a", "Activity Monitor"])

    def _quit(self, _):
        rumps.quit_application()


def main() -> None:
    # Kjør som ren menylinje-app — ellers vises Python-rakettikonet i Dock
    try:
        import AppKit
        AppKit.NSApplication.sharedApplication().setActivationPolicy_(
            AppKit.NSApplicationActivationPolicyAccessory
        )
    except Exception:
        pass
    PyWhatApp().run()


if __name__ == "__main__":
    main()
