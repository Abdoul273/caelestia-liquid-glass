#!/usr/bin/env python3
"""Paroles synchronisées pour la Dynamic Island.

Usage : island-lyrics.py TITRE ARTISTE DUREE_S URL
Sortie (stdout) : {"lines": [[secondes, "texte"], ...]} — liste vide si rien trouvé.

Ordre de recherche :
  1. Onde (morceau retrouvé dans sa base : cache de paroles, sinon son API locale qui
     applique les mêmes variantes artiste/titre que l'app, sinon le .lrc) ;
  2. cache de paroles d'Aura (morceau retrouvé dans sa base par chemin ou par titre) ;
  3. fichier .lrc à côté du morceau ;
  4. LRCLIB en ligne (résultat mis en cache, y compris « rien trouvé »).
"""

import contextlib
import hashlib
import json
import os
import re
import shutil
import socket
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home()
AURA_DB = HOME / ".local/share/com.abdoul273.aura/aura.db"
AURA_LYRICS = HOME / ".cache/com.abdoul273.aura/lyrics"
ONDE_DATA = Path(os.getenv("XDG_DATA_HOME", HOME / ".local/share")) / "onde"
ONDE_DB = ONDE_DATA / "onde.db"
ONDE_LYRICS = ONDE_DATA / "paroles"
ONDE_API = f"http://127.0.0.1:{os.getenv('ONDE_PORT', '5070')}/api/paroles/"
ONDE_CLI_SOCK = f"/tmp/onde_cli_ctrl_{os.getuid()}.sock"
CACHE = HOME / ".cache/caelestia/island-lyrics"
TAG = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")


def parse_lrc(text: str) -> list:
    lines = []
    for raw in text.splitlines():
        stamps = TAG.findall(raw)
        if not stamps:
            continue
        words = TAG.sub("", raw)
        words = re.sub(r"<\d+:\d+(?:\.\d+)?>", "", words).strip()
        for m, s in stamps:
            lines.append([int(m) * 60 + float(s.replace(":", ".")), words])
    lines.sort(key=lambda l: l[0])
    return lines


def clean_title(title: str) -> str:
    t = re.sub(r"[\(\[][^\)\]]*(official|video|audio|lyric|clip|visuali[sz]er|remaster|hd|4k)[^\)\]]*[\)\]]", "", title, flags=re.IGNORECASE)
    t = re.sub(r"\b(official\s+)?(music\s+)?(video|audio|lyrics?|clip officiel|clip)\b", "", t, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", t).strip(" -|")


def split_artist(title: str, artist: str) -> tuple:
    if (not artist or artist.lower() in ("unknown", "artiste inconnu")) and " - " in title:
        a, t = title.split(" - ", 1)
        return clean_title(t), a.strip()
    return clean_title(title), artist


def from_aura(title: str, artist: str, url: str) -> list | None:
    if not AURA_DB.exists():
        return None
    try:
        db = sqlite3.connect(f"file:{AURA_DB}?mode=ro", uri=True, timeout=1)
        row = None
        if url.startswith("file://"):
            path = urllib.parse.unquote(url[7:])
            row = db.execute("select id, path from tracks where path = ?", (path,)).fetchone()
        if not row:
            rows = db.execute("select id, path, artist from tracks where lower(title) = lower(?)", (title,)).fetchall()
            if artist:
                rows = [r for r in rows if artist.lower() in r[2].lower()] or rows
            row = rows[0][:2] if rows else None
        db.close()
    except sqlite3.Error:
        return None
    if not row:
        return None
    track_id, path = row
    for version in ("v4", "v3", "v2"):
        f = AURA_LYRICS / f"{version}-{track_id}.json"
        if f.exists():
            try:
                data = json.loads(f.read_text())
                if data.get("synced") and data.get("text"):
                    return parse_lrc(data["text"])
            except (OSError, ValueError):
                pass
    lrc = Path(path).with_suffix(".lrc")
    if lrc.exists():
        return parse_lrc(lrc.read_text(errors="ignore"))
    return None


def preparer_lignes_onde(synchro: list, mots_liste: list | None = None) -> list:
    """Aligne les lignes et pauses instrumentales (♪) exactement comme Onde CLI (`preparer_synchro_cli`)."""
    if not synchro:
        return []
    groupes = []
    for i, item in enumerate(synchro):
        if not item or len(item) < 2:
            continue
        t, l = float(item[0]), str(item[1] or "").strip()
        if groupes and abs(groupes[-1]["t"] - t) < 0.05:
            if l and l not in groupes[-1]["textes"]:
                groupes[-1]["textes"].append(l)
                groupes[-1]["mots"] = None
        else:
            m = mots_liste[i] if mots_liste and i < len(mots_liste) else None
            groupes.append({"t": t, "textes": [l], "mots": m})

    out = []
    if groupes and groupes[0]["t"] > 2.0:
        out.append([0.0, "♪"])

    for i, grp in enumerate(groupes):
        t = grp["t"]
        suiv_t = groupes[i + 1]["t"] if i + 1 < len(groupes) else t + 7.0
        txt = " / ".join(filter(None, grp["textes"]))
        if not txt or all(c in "♪♫·. \t\n\r" for c in txt):
            if suiv_t - t >= 2.5:
                out.append([round(t, 3), "♪"])
            continue

        reperes = grp["mots"]
        fin_chant = suiv_t
        if reperes and len(reperes) > 1:
            dernier = reperes[-1]
            if len(dernier) >= 2 and not str(dernier[1]).strip() and t < float(dernier[0]) < suiv_t:
                fin_chant = float(dernier[0])

        out.append([round(t, 3), txt])
        if suiv_t - fin_chant >= 3.0:
            out.append([round(fin_chant, 3), "♪"])
    return out


def from_onde_cli(title: str) -> list | None:
    """Interroge l'instance Onde CLI active en direct via son socket UNIX."""
    if not os.path.exists(ONDE_CLI_SOCK):
        return None
    deadline = time.monotonic() + 3.5
    while time.monotonic() < deadline:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.settimeout(0.8)
                s.connect(ONDE_CLI_SOCK)
                s.sendall(json.dumps({"action": "lyrics", "arg": title}).encode("utf-8"))
                chunks = []
                while True:
                    b = s.recv(8192)
                    if not b:
                        break
                    chunks.append(b)
                    if b"\n" in b:
                        break
                rep = json.loads(b"".join(chunks).decode("utf-8", errors="ignore"))
        except (OSError, ValueError):
            return None
        if not isinstance(rep, dict) or not rep.get("ok"):
            return None
        rep_titre = (rep.get("titre") or "").strip().lower()
        if title and rep_titre and rep_titre != title.strip().lower():
            return None
        if rep.get("en_chargement"):
            time.sleep(0.15)
            continue
        lines = rep.get("lines")
        if isinstance(lines, list) and lines:
            return lines
        break
    return None


def from_onde(title: str, artist: str, duration: float, url: str) -> list | None:
    """Paroles telles qu'Onde les affiche (même morceau, même source et alignement acoustique)."""
    lines_cli = from_onde_cli(title)
    if lines_cli:
        return lines_cli

    if not ONDE_DB.exists():
        return None
    try:
        db = sqlite3.connect(f"file:{ONDE_DB}?mode=ro", uri=True, timeout=1)
        rows = []
        if url.startswith("file://"):
            rows = db.execute("select id, chemin, artiste, duree from pistes where chemin = ?",
                              (urllib.parse.unquote(url[7:]),)).fetchall()
        if not rows:
            rows = db.execute("select id, chemin, artiste, duree from pistes where titre = ?", (title,)).fetchall()
        if not rows:
            rows = db.execute("select id, chemin, artiste, duree from pistes where lower(titre) = lower(?)", (title,)).fetchall()
        db.close()
    except sqlite3.Error:
        return None
    if not rows:
        return None
    if artist:
        rows = [r for r in rows if (r[2] or "").lower() == artist.lower()] or rows
    if duration > 0:
        rows.sort(key=lambda r: abs((r[3] or 0) - duration))
    track_id, path = rows[0][:2]

    cached = ONDE_LYRICS / f"{track_id}.json"
    if cached.exists():
        try:
            data_c = json.loads(cached.read_text())
            synced = data_c.get("synchro") or []
            if synced:
                return preparer_lignes_onde(synced, data_c.get("mots"))
        except (OSError, ValueError):
            pass
    lrc = Path(path).with_suffix(".lrc")
    if lrc.exists():
        lines = parse_lrc(lrc.read_text(errors="ignore"))
        if lines:
            return preparer_lignes_onde(lines)
    # pas encore en cache : on demande à Onde Web (s'il tourne)
    with contextlib.suppress(Exception), urllib.request.urlopen(ONDE_API + str(track_id), timeout=6) as r:
        data_api = json.loads(r.read())
        synced = data_api.get("synchro") or []
        if synced:
            return preparer_lignes_onde(synced, data_api.get("mots"))
        return []
    # ou directement via le moteur Python d'Onde (même si seul onde-cli tourne)
    cli_bin = shutil.which("onde-cli") or str(HOME / ".local/bin/onde-cli")
    if os.path.exists(cli_bin):
        with contextlib.suppress(Exception):
            onde_repo = Path(cli_bin).resolve().parent
            if (onde_repo / "onde").is_dir():
                if str(onde_repo) not in sys.path:
                    sys.path.insert(0, str(onde_repo))
                from onde import paroles as onde_paroles
                res_p = onde_paroles.paroles(track_id)
                if res_p and res_p.get("synchro"):
                    return preparer_lignes_onde(res_p["synchro"], res_p.get("mots"))
    return None


def fetch(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "caelestia-island (github.com/Abdoul273/caelestia-liquid-glass)"})
    with urllib.request.urlopen(req, timeout=6) as r:
        return json.loads(r.read())


def from_lrclib(title: str, artist: str, duration: float) -> list:
    q = {"track_name": title}
    if artist:
        q["artist_name"] = artist
    if duration > 0:
        q["duration"] = round(duration)
    with contextlib.suppress(Exception):
        data = fetch("https://lrclib.net/api/get?" + urllib.parse.urlencode(q))
        if data.get("syncedLyrics"):
            return parse_lrc(data["syncedLyrics"])
    with contextlib.suppress(Exception):
        results = fetch("https://lrclib.net/api/search?" + urllib.parse.urlencode({"q": f"{artist} {title}".strip()}))
        for r in results:
            if r.get("syncedLyrics") and (duration <= 0 or abs((r.get("duration") or duration) - duration) < 8):
                return parse_lrc(r["syncedLyrics"])
    return []


def main() -> None:
    title, artist, duration, url = (sys.argv[1:] + ["", "", "0", ""])[:4]
    try:
        duration = float(duration)
    except ValueError:
        duration = 0
    if not title:
        print('{"lines": []}')
        return

    lines = from_onde(title, artist, duration, url)
    if lines is not None:  # morceau d'Onde : on affiche exactement ce qu'il affiche
        print(json.dumps({"lines": lines}, ensure_ascii=False))
        return

    lines = from_aura(title, artist, url)
    if not lines:
        t, a = split_artist(title, artist)
        lines = from_aura(t, a, "")
        if not lines:
            key = hashlib.sha1(f"{t}|{a}|{round(duration)}".lower().encode()).hexdigest()[:16]
            cached = CACHE / f"{key}.json"
            if cached.exists():
                lines = json.loads(cached.read_text())
            else:
                lines = from_lrclib(t, a, duration)
                CACHE.mkdir(parents=True, exist_ok=True)
                cached.write_text(json.dumps(lines))
    print(json.dumps({"lines": lines or []}, ensure_ascii=False))


if __name__ == "__main__":
    main()
