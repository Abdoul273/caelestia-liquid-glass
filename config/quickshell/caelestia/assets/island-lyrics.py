#!/usr/bin/env python3
"""Paroles synchronisées pour la Dynamic Island.

Usage : island-lyrics.py TITRE ARTISTE DUREE_S URL
Sortie (stdout) : {"lines": [[secondes, "texte"], ...]} — liste vide si rien trouvé.

Ordre de recherche :
  1. cache de paroles d'Aura (morceau retrouvé dans sa base par chemin ou par titre) ;
  2. fichier .lrc à côté du morceau ;
  3. LRCLIB en ligne (résultat mis en cache, y compris « rien trouvé »).
"""

import hashlib
import json
import os
import re
import sqlite3
import sys
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home()
AURA_DB = HOME / ".local/share/com.abdoul273.aura/aura.db"
AURA_LYRICS = HOME / ".cache/com.abdoul273.aura/lyrics"
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
    t = re.sub(r"[\(\[][^\)\]]*(official|video|audio|lyric|clip|visuali[sz]er|remaster|hd|4k)[^\)\]]*[\)\]]", "", title, flags=re.I)
    t = re.sub(r"\b(official\s+)?(music\s+)?(video|audio|lyrics?|clip officiel|clip)\b", "", t, flags=re.I)
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
    try:
        data = fetch("https://lrclib.net/api/get?" + urllib.parse.urlencode(q))
        if data.get("syncedLyrics"):
            return parse_lrc(data["syncedLyrics"])
    except Exception:
        pass
    try:
        results = fetch("https://lrclib.net/api/search?" + urllib.parse.urlencode({"q": f"{artist} {title}".strip()}))
        for r in results:
            if r.get("syncedLyrics") and (duration <= 0 or abs((r.get("duration") or duration) - duration) < 8):
                return parse_lrc(r["syncedLyrics"])
    except Exception:
        pass
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
