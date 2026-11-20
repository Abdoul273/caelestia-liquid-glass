"""Vérifications automatiques de l'internationalisation FR/EN du shell QML."""

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
QS = ROOT / "config" / "quickshell" / "caelestia"
I18N_QML = QS / "services" / "I18n.qml"
I18N_EN_JS = QS / "services" / "I18nEn.js"

TR_PAT = re.compile(
    r'\bI18n\.tr\(\s*(?:"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'|`((?:[^`\\]|\\.)*)`)\s*\)'
)
FR_ACCENTS = re.compile(r"[éèêëàâäçùûüôöîïÉÈÊÀÂÇÙÛÔÎœŒ«»]")


def _load_en_strings() -> dict[str, str]:
    text = I18N_EN_JS.read_text(encoding="utf-8")
    match = re.search(r"var strings\s*=\s*(\{.*?\});", text, re.DOTALL)
    assert match, "var strings = {...}; introuvable dans I18nEn.js"
    return json.loads(match.group(1))


def _unescape(s: str) -> str:
    return (
        s.replace("\\n", "\n")
        .replace("\\t", "\t")
        .replace('\\"', '"')
        .replace("\\'", "'")
        .replace("\\\\", "\\")
    )


def _strip_line_comment(line: str) -> str:
    in_q = None
    esc = False
    for i, ch in enumerate(line):
        if esc:
            esc = False
            continue
        if ch == "\\":
            esc = True
            continue
        if in_q:
            if ch == in_q:
                in_q = None
        else:
            if ch in ('"', "'", "`"):
                in_q = ch
            elif ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
                return line[:i]
    return line


def test_i18n_files_exist_and_parse():
    assert I18N_QML.is_file()
    assert I18N_EN_JS.is_file()
    strings = _load_en_strings()
    assert len(strings) >= 1000


def test_no_stray_qstr_or_hardcoded_fr_locale():
    stray_qstr = []
    stray_locale = []
    for qml in sorted(QS.rglob("*.qml")):
        rel = qml.relative_to(QS)
        for lineno, raw in enumerate(qml.read_text(encoding="utf-8").splitlines(), 1):
            code = _strip_line_comment(raw)
            if re.search(r"\bqsTr\(", code):
                stray_qstr.append(f"{rel}:{lineno}: {code.strip()}")
            if rel != pathlib.Path("services/I18n.qml") and 'Qt.locale("fr_FR")' in code:
                stray_locale.append(f"{rel}:{lineno}: {code.strip()}")
    assert not stray_qstr, "Appels qsTr() restants :\n" + "\n".join(stray_qstr[:20])
    assert not stray_locale, "Qt.locale(\"fr_FR\") en dur :\n" + "\n".join(stray_locale[:20])


def test_i18n_imports_present():
    missing_import = []
    for qml in sorted(QS.rglob("*.qml")):
        rel = qml.relative_to(QS)
        if rel.parts[0] == "services":
            continue
        text = qml.read_text(encoding="utf-8")
        if re.search(r"\bI18n\.", text) and "import qs.services" not in text:
            missing_import.append(str(rel))
    assert not missing_import, "Import qs.services manquant dans : " + ", ".join(missing_import)


def test_all_french_tr_keys_have_english_translations():
    en = _load_en_strings()
    missing = set()
    for qml in sorted(QS.rglob("*.qml")):
        text = qml.read_text(encoding="utf-8")
        for m in TR_PAT.finditer(text):
            raw = next(g for g in m.groups() if g is not None)
            key = _unescape(raw)
            if key in en:
                continue
            # If the key contains French accents/guillemets, it must have an English translation
            if FR_ACCENTS.search(key):
                missing.add(key)
    assert not missing, "Clés françaises absentes de I18nEn.js :\n" + "\n".join(sorted(missing))


def test_placeholders_match_between_fr_and_en():
    en = _load_en_strings()
    bad = []
    for fr, target in en.items():
        p_fr = sorted(set(re.findall(r"%[0-9n]+", fr)))
        p_en = sorted(set(re.findall(r"%[0-9n]+", target)))
        if p_fr != p_en:
            bad.append(f"{fr!r} ({p_fr}) -> {target!r} ({p_en})")
    assert not bad, "Placeholders incohérents :\n" + "\n".join(bad)
