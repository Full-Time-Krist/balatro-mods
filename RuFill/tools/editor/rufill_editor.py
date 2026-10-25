#!/usr/bin/env python3
"""RuFill translation editor.

Local web UI for translating the strings RuFill's dump found untranslated.
Translations are kept in one JSON file keyed by localization path, so they
survive new dumps; "Собрать" merges them into RuFill/localization/ru.lua.

Pure Python (no Lua needed), so the same files run on Linux and in the
portable Windows build.

    python3 rufill_editor.py [--port 8765] [--no-browser]
"""
import argparse
import http.server
import json
import os
import re
import shutil
import sys
import threading
import time
import webbrowser
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import luatable

HERE = Path(__file__).resolve().parent
PORTABLE = (HERE / "portable").exists()
if os.environ.get("RUFILL_WORK"):
    WORK = Path(os.environ["RUFILL_WORK"])
elif PORTABLE:
    WORK = HERE.parent / "data"
else:
    WORK = Path.home() / ".local/share/rufill-editor"
CHUNKS = WORK / "chunks"
TRANSLATIONS = WORK / "translations.json"
BACKUPS = WORK / "backups"
CONFIG = WORK / "config.json"

lock = threading.Lock()

LATIN2 = re.compile(r"[A-Za-z]{2}")
CYRILLIC = re.compile(r"[\u0400-\u04FF]")


# ---------------------------------------------------------------- paths

def load_config():
    if CONFIG.exists():
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    return {}


def save_config(cfg):
    WORK.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps(cfg, ensure_ascii=False, indent=1), encoding="utf-8")


def is_rufill(path):
    return path is not None and (Path(path) / "RuFill.json").exists()


def rufill_dir():
    cfg = load_config()
    candidates = [cfg.get("rufill_dir"), os.environ.get("RUFILL_DIR")]
    # editor living inside RuFill/tools/editor
    candidates.append(HERE.parent.parent)
    # portable editor folder dropped next to Balatro.exe (mods in <game>/Mods)
    candidates.append(HERE.parent.parent / "Mods" / "RuFill")
    candidates.append(HERE.parent / "Mods" / "RuFill")
    if os.environ.get("APPDATA"):
        candidates.append(Path(os.environ["APPDATA"]) / "Balatro" / "Mods" / "RuFill")
    for c in candidates:
        if c and is_rufill(c):
            return Path(c)
    return None


def save_dir():
    """Balatro's save folder: where rufill_dump.lua and the dump request live."""
    cfg = load_config()
    if cfg.get("save_dir"):
        return Path(cfg["save_dir"])
    if os.environ.get("APPDATA"):
        return Path(os.environ["APPDATA"]) / "Balatro"
    rf = rufill_dir()
    return rf.parent.parent if rf else None


# ---------------------------------------------------------------- data

def needs_translation(text):
    """Real English words and no Cyrillic, ignoring {tags}, #vars# and URLs."""
    t = re.sub(r"\{[^}]*\}", "", text)
    t = re.sub(r"#[^#]*#", "", t)
    t = re.sub(r"https?://\S+", "", t)
    return bool(LATIN2.search(t)) and not CYRILLIC.search(t)


def load_translations():
    if TRANSLATIONS.exists():
        return json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
    return {}


def save_translations(data):
    tmp = TRANSLATIONS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=0, sort_keys=True), encoding="utf-8")
    tmp.replace(TRANSLATIONS)


def parse_chunk(path):
    """[(header, [(relpath, text), ...]), ...] in file order."""
    blocks, cur = [], None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("="):
            cur = (line[1:], [])
            blocks.append(cur)
        elif cur is not None and "\t" in line:
            p, text = line.split("\t", 1)
            cur[1].append((p, text))
    return blocks


def chunk_files():
    return sorted(CHUNKS.glob("*.txt")) if CHUNKS.exists() else []


def file_summary(path, tr):
    total = done = 0
    labels = {}
    for header, lines in parse_chunk(path):
        for p, text in lines:
            if needs_translation(text):
                total += 1
                if tr.get(f"{header}|{p}", {}).get("ru"):
                    done += 1
        parts = header.split("|")
        key = parts[2] if parts[0] == "descriptions" and len(parts) > 2 else "|".join(parts[:2])
        m = re.match(r"^[a-z]+_([A-Za-z0-9]+)_", key)
        label = m.group(1) if m else key
        labels[label] = labels.get(label, 0) + 1
    top = sorted(labels.items(), key=lambda kv: -kv[1])[:3]
    return {"name": path.name, "total": total, "done": done, "labels": [k for k, _ in top]}


# ---------------------------------------------------------------- export (dump -> chunks)

def _esc(s):
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")


def _unesc(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "\\": "\\"}.get(m.group(1), m.group(0)), s)


def _key_order(k):
    return (0, k, "") if isinstance(k, (int, float)) else (1, 0, str(k).encode("utf-8"))


def _leaves(t, prefix, acc):
    if isinstance(t, str):
        acc.append(prefix + "\t" + _esc(t))
    elif isinstance(t, dict):
        for k in sorted(t, key=_key_order):
            if isinstance(k, str) and k.endswith("_parsed"):
                continue
            _leaves(t[k], str(k) if prefix == "" else f"{prefix}|{k}", acc)
    return acc


def _modkey(k):
    m = re.match(r"^[A-Za-z]+_([A-Za-z]+)_", k) or re.match(r"^([A-Za-z]+)_", k)
    return m.group(1) if m else k


def export_dump(dump_path, outdir, maxlines=600):
    """Flatten the dump into chunk files ("=header", then "relpath<TAB>text")."""
    d = luatable.load_file(dump_path)
    blocks = []
    desc = d.get("descriptions") or {}
    keys = [(s, k) for s, es in desc.items() if isinstance(es, dict) for k in es]
    keys.sort(key=lambda sk: (_modkey(str(sk[1])), str(sk[0]), str(sk[1])))
    for s, k in keys:
        blocks.append((f"descriptions|{s}|{k}", _leaves(desc[s][k], "", [])))
    for top in sorted(d, key=_key_order):
        v = d[top]
        if top == "descriptions" or str(top).endswith("_parsed") or not isinstance(v, dict):
            continue
        for k in sorted(v, key=_key_order):
            ls = _leaves(v[k], "", [])
            for i in range(0, len(ls), 150):
                blocks.append((f"{top}|{k}", ls[i:i + 150]))
    n, cnt, cur = 0, 0, None
    for header, lines in blocks:
        if not lines:
            continue
        if cur is None or cnt + len(lines) > maxlines:
            if cur:
                cur.close()
            n += 1
            cnt = 0
            cur = open(Path(outdir) / f"{n:03d}.txt", "w", encoding="utf-8", newline="\n")
        cur.write("=" + header + "\n")
        for line in lines:
            cur.write(line + "\n")
        cnt += len(lines) + 1
    if cur:
        cur.close()
    return n


def refresh_from_dump():
    sd = save_dir()
    dump = sd / "rufill_dump.lua" if sd else None
    if not dump or not dump.exists():
        raise RuntimeError(f"Нет файла выгрузки: {dump}")
    WORK.mkdir(parents=True, exist_ok=True)
    shutil.copy2(dump, WORK / "dump.lua")
    if CHUNKS.exists():
        shutil.rmtree(CHUNKS)
    CHUNKS.mkdir()
    return f"файлов: {export_dump(WORK / 'dump.lua', CHUNKS)}"


# ---------------------------------------------------------------- build (translations -> ru.lua)

def _merge(src, dst):
    """RuFill's merge: recurse into tables, replace string arrays (text = {...}) whole."""
    for k, v in src.items():
        if isinstance(v, dict) and not isinstance(v.get(1), str) and isinstance(dst.get(k), dict):
            _merge(v, dst[k])
        else:
            dst[k] = v


def _seg(s):
    return int(s) if re.fullmatch(r"-?\d+", s) else s


def build():
    rf = rufill_dir()
    if not rf:
        raise RuntimeError("Не найдена папка RuFill — укажите её кнопкой «Папка RuFill».")
    tr = load_translations()
    new, entries, lines_done = {}, 0, 0
    for path in chunk_files():
        for header, lines in parse_chunk(path):
            if not any(tr.get(f"{header}|{p}", {}).get("ru") for p, _ in lines):
                continue
            entries += 1
            for p, text in lines:
                ru = tr.get(f"{header}|{p}", {}).get("ru")
                if ru:
                    lines_done += 1
                segs = [_seg(s) for s in (header + "|" + p).split("|")]
                node = new
                for s in segs[:-1]:
                    node = node.setdefault(s, {})
                node[segs[-1]] = _unesc(ru or text)
    if not entries:
        return "Нечего собирать: ещё нет переведённых строк."
    ru_lua = rf / "localization" / "ru.lua"
    base = {}
    if ru_lua.exists():
        BACKUPS.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ru_lua, BACKUPS / f"ru-{time.strftime('%Y%m%d-%H%M%S')}.lua")
        for old in sorted(BACKUPS.glob("ru-*.lua"))[:-10]:
            old.unlink()
        base = luatable.load_file(ru_lua)
    _merge(new, base)
    ru_lua.parent.mkdir(parents=True, exist_ok=True)
    tmp = ru_lua.with_suffix(".tmp")
    luatable.save_file(tmp, base)
    tmp.replace(ru_lua)
    return f"Строк переведено: {lines_done}, записей: {entries}.\nГотово: {ru_lua}"


# ---------------------------------------------------------------- http

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        url = urlparse(self.path)
        try:
            if url.path == "/":
                body = (HERE / "index.html").read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif url.path == "/api/state":
                tr = load_translations()
                rf, sd = rufill_dir(), save_dir()
                dump = sd / "rufill_dump.lua" if sd else None
                self.send_json({
                    "files": [file_summary(p, tr) for p in chunk_files()],
                    "rufill_dir": str(rf) if rf else None,
                    "save_dir": str(sd) if sd else None,
                    "dump_exists": bool(dump and dump.exists()),
                    "request_pending": bool(sd and (sd / "rufill_dump_request").exists()),
                })
            elif url.path == "/api/file":
                name = parse_qs(url.query).get("name", [""])[0]
                path = CHUNKS / Path(name).name
                tr = load_translations()
                entries = []
                for header, lines in parse_chunk(path):
                    out = []
                    for p, text in lines:
                        rec = tr.get(f"{header}|{p}", {})
                        out.append({
                            "path": p, "en": text, "needs": needs_translation(text),
                            "ru": rec.get("ru", ""),
                            "stale": bool(rec.get("ru")) and rec.get("en") not in (None, text),
                        })
                    if any(l["needs"] for l in out):
                        entries.append({"header": header, "lines": out})
                self.send_json({"name": path.name, "entries": entries})
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def do_POST(self):
        url = urlparse(self.path)
        try:
            if url.path == "/api/save":
                items = self.read_json().get("items", [])
                with lock:
                    tr = load_translations()
                    for it in items:
                        if it.get("ru", "").strip():
                            tr[it["key"]] = {"en": it.get("en"), "ru": it["ru"]}
                        else:
                            tr.pop(it["key"], None)
                    save_translations(tr)
                self.send_json({"ok": True, "count": len(tr)})
            elif url.path == "/api/build":
                with lock:
                    self.send_json({"ok": True, "log": build()})
            elif url.path == "/api/refresh":
                with lock:
                    self.send_json({"ok": True, "log": refresh_from_dump()})
            elif url.path == "/api/request_dump":
                sd = save_dir()
                if not sd or not sd.exists():
                    raise RuntimeError(f"Нет папки сохранений Balatro: {sd}")
                (sd / "rufill_dump_request").touch()
                self.send_json({"ok": True})
            elif url.path == "/api/config":
                body = self.read_json()
                cfg = load_config()
                if "rufill_dir" in body:
                    p = Path(body["rufill_dir"].strip().strip('"'))
                    if p.name.lower() != "rufill" and is_rufill(p / "RuFill"):
                        p = p / "RuFill"
                    if not is_rufill(p):
                        raise RuntimeError(f"В папке нет RuFill.json: {p}")
                    cfg["rufill_dir"] = str(p)
                save_config(cfg)
                self.send_json({"ok": True})
            else:
                self.send_json({"error": "not found"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()
    url = f"http://127.0.0.1:{args.port}/"
    WORK.mkdir(parents=True, exist_ok=True)
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except OSError:
        print(f"Редактор уже запущен: {url}")
        if not args.no_browser:
            webbrowser.open(url)
        return
    if not chunk_files():
        sd = save_dir()
        if sd and (sd / "rufill_dump.lua").exists():
            print("Выгрузка:", refresh_from_dump())
    print(f"RuFill editor: {url}")
    print(f"Папка RuFill: {rufill_dir() or 'не найдена'}")
    print(f"Переводы: {TRANSLATIONS}")
    print("Не закрывайте это окно, пока переводите. Ctrl+C — выход.")
    if not args.no_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
