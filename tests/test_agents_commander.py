"""Tests unitaires rapides pour le Commandant Katana AI (caelestia-agents)."""

from __future__ import annotations

import importlib.machinery
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AGENTS_BIN = ROOT / "bin" / "caelestia-agents"


def _load_agents():
    loader = importlib.machinery.SourceFileLoader("agents_under_test", str(AGENTS_BIN))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def _check_gemini_schema(node: dict) -> None:
    assert node.get("type") in {"OBJECT", "STRING", "INTEGER", "NUMBER", "BOOLEAN", "ARRAY"}
    if node["type"] == "OBJECT":
        props = node.get("properties")
        assert isinstance(props, dict) and len(props) > 0, f"OBJECT sans properties : {node}"
        for child in props.values():
            _check_gemini_schema(child)
    elif node["type"] == "ARRAY":
        assert isinstance(node.get("items"), dict), f"ARRAY sans items : {node}"
        _check_gemini_schema(node["items"])


def test_workspace_normalization():
    mod = _load_agents()
    assert mod._norm_ws("2") == "2"
    assert mod._norm_ws("bureau 2") == "2"
    assert mod._norm_ws("deuxième") == "2"
    assert mod._norm_ws("suivant") == "+1"
    assert mod._norm_ws("précédent") == "-1"
    assert mod._norm_ws("special") == "special"


def test_failure_detection():
    mod = _load_agents()
    assert mod._looks_like_failure("Aucune fenêtre ne correspond à '2'.") is True
    assert mod._looks_like_failure("Erreur hypr_orchestrator: introuvable") is True
    assert mod._looks_like_failure("Changement vers le bureau 2 non confirmé.") is True
    assert mod._looks_like_failure("Bureau actif confirmé : 2.") is False
    assert mod._looks_like_failure("Compilation terminée : 0 erreur.") is False


def test_native_tool_declarations_valid_for_gemini():
    mod = _load_agents()
    decls = mod._native_tool_declarations()
    names = {d["name"] for d in decls}
    for required in (
        "hypr_workspace",
        "hypr_windows",
        "shell_control",
        "system_control",
        "run_shell",
        "agent_dispatch",
        "agent_send",
        "agent_close",
        "agent_detail",
        "memory_save",
        "memory_search",
    ):
        assert required in names, f"Outil natif manquant : {required}"
    for d in decls:
        assert d.get("description")
        if "parameters" in d:
            _check_gemini_schema(d["parameters"])


def test_sanitize_schema_handles_empty_objects_and_arrays():
    mod = _load_agents()
    bad_obj = mod._sanitize_schema({"type": "object", "properties": {}, "additionalProperties": True})
    assert bad_obj["type"] == "STRING"
    arr = mod._sanitize_schema({"type": "array"})
    assert arr["type"] == "ARRAY" and arr["items"]["type"] == "STRING"


def test_run_shell_blocks_catastrophic_commands():
    mod = _load_agents()
    ok, msg = mod.tool_run_shell("rm -rf /")
    assert ok is False
    assert "bloquée" in msg.lower()


def test_standalone_memory_roundtrip(tmp_path, monkeypatch):
    mod = _load_agents()
    monkeypatch.setattr(mod, "ANO_DIR", tmp_path / "absent-ano")
    monkeypatch.setattr(mod, "CHAT_HISTORY", tmp_path / "chat.json")
    ok, _ = mod.ano_memory_save("editeur", "Neovim", "preferences")
    assert ok is True
    found = mod.ano_memory_search("Neovim")
    assert "Neovim" in found
