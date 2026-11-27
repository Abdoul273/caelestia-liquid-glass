#!/usr/bin/env python3
"""Synchronise les fichiers partagés entre caelestia-liquid-glass, ano-shell et le shell local.

Usage :
  python3 tools/sync-repos.py --check          # détecte les dérives sans rien modifier
  python3 tools/sync-repos.py --apply          # propage shaders, composants et agents
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

HOME = Path.home()
LOCAL_QS = HOME / ".config/quickshell/caelestia"
LOCAL_AGENTS = HOME / ".local/bin/caelestia-agents"
CLG_ROOT = HOME / "development/caelestia-liquid-glass"
ANO_ROOT = HOME / "development/ano-shell"

# Fichiers strictement identiques entre local, caelestia-liquid-glass et ano-shell
IDENTICAL_SHELL_FILES = (
    "assets/shaders/liquidios.frag",
    "assets/shaders/liquidios.frag.qsb",
    "assets/shaders/liquidios-fast.frag",
    "assets/shaders/liquidios-fast.frag.qsb",
    "assets/shaders/liquidglass.frag",
    "assets/shaders/liquidglass.frag.qsb",
    "assets/shaders/glassblob.frag",
    "assets/shaders/glassblob.frag.qsb",
    "assets/shaders/glasscontrol.frag",
    "assets/shaders/glasscontrol.frag.qsb",
    "components/StyledRect.qml",
    "components/effects/GlassBlob.qml",
    "components/effects/GlassControl.qml",
    "components/effects/LiquidGlass.qml",
    "components/containers/VerticalFadeFlickable.qml",
    "components/containers/VerticalFadeListView.qml",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else ""


def adapt_agents_for_ano(text: str) -> str:
    return (
        text.replace("  caelestia-agents ", "  ano-agents ")
        .replace(".local/state/caelestia/agent-perms", ".local/state/ano-shell/agent-perms")
        .replace(".local/state/caelestia/agentos-chat.json", ".local/state/ano-shell/agentos-chat.json")
        .replace('print(f"caelestia-agents: {e}"', 'print(f"ano-agents: {e}"')
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Synchronise caelestia-liquid-glass et ano-shell.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Vérifie uniquement les dérives")
    mode.add_argument("--apply", action="store_true", help="Applique la synchronisation")
    args = parser.parse_args()

    clg_qs = CLG_ROOT / "config/quickshell/caelestia"
    ano_qs = ANO_ROOT / "shell"
    drifts: list[str] = []

    for rel in IDENTICAL_SHELL_FILES:
        src = LOCAL_QS / rel if LOCAL_QS.is_dir() else clg_qs / rel
        if not src.is_file():
            continue
        src_h = sha256(src)
        for label, dst in (("caelestia-liquid-glass", clg_qs / rel), ("ano-shell", ano_qs / rel)):
            if not dst.parent.is_dir():
                continue
            if sha256(dst) != src_h:
                drifts.append(f"{label}: {rel}")
                if args.apply:
                    shutil.copy2(src, dst)

    # Synchronisation caelestia-agents -> CLG + ano-agents
    agents_src = LOCAL_AGENTS if LOCAL_AGENTS.is_file() else CLG_ROOT / "bin/caelestia-agents"
    if agents_src.is_file():
        src_text = agents_src.read_text(encoding="utf-8")
        clg_agents = CLG_ROOT / "bin/caelestia-agents"
        ano_agents = ANO_ROOT / "bin/ano-agents"
        if clg_agents.parent.is_dir() and (not clg_agents.is_file() or clg_agents.read_text(encoding="utf-8") != src_text):
            drifts.append("caelestia-liquid-glass: bin/caelestia-agents")
            if args.apply:
                clg_agents.write_text(src_text, encoding="utf-8")
                clg_agents.chmod(0o755)
        expected_ano = adapt_agents_for_ano(src_text)
        if ano_agents.parent.is_dir() and (not ano_agents.is_file() or ano_agents.read_text(encoding="utf-8") != expected_ano):
            drifts.append("ano-shell: bin/ano-agents")
            if args.apply:
                ano_agents.write_text(expected_ano, encoding="utf-8")
                ano_agents.chmod(0o755)

    if not drifts:
        print("Synchronisation OK : aucune dérive détectée.")
        return 0

    verb = "Synchronisés" if args.apply else "Dérives détectées"
    print(f"{verb} ({len(drifts)}) :")
    for item in drifts:
        print(f"  - {item}")
    return 0 if args.apply else 1


if __name__ == "__main__":
    sys.exit(main())
