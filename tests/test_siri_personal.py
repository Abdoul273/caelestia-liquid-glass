"""Vérifications ciblées sans démarrer Siri ni toucher aux services du bureau."""

import ast
import asyncio
import datetime as dt
import json
import re
import tempfile
import threading
import time
import unicodedata
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from urllib.parse import urlsplit

import pytest


@pytest.fixture
def siri(tmp_path):
    # Le script redirige stdout à l'import : ne charger que ses définitions pures.
    source = ast.parse((Path(__file__).parents[1] / "bin/caelestia-siri").read_text())
    nodes = [node for node in source.body if isinstance(node, ast.FunctionDef)]
    nodes += [method for node in source.body if isinstance(node, ast.ClassDef) and node.name == "Assistant"
              for method in node.body if isinstance(method, ast.AsyncFunctionDef)
              and method.name in {"run_routine", "_call_tool"}]
    nodes += [node for node in source.body if isinstance(node, ast.Assign)
              and any(isinstance(target, ast.Name) and target.id in {"TOOLS", "ARG_NAMES"} for target in node.targets)]
    namespace = {
        "asyncio": asyncio, "dt": dt, "json": json, "re": re, "tempfile": tempfile,
        "threading": threading, "time": time, "unicodedata": unicodedata, "Path": Path,
        "urlsplit": urlsplit, "LOCAL_LOCK": threading.RLock(), "ANO_RUNTIME": object(),
        "MUSIC_UNIT": "test-siri-sleep", "emit": Mock(), "run": Mock(), "qs_ipc": Mock(),
        "ANO_TOOLS": {}, "ANO_RELAYED": set(),
    }
    exec(compile(ast.Module(body=nodes, type_ignores=[]), "siri-fonctions", "exec"), namespace)  # noqa: S102 — définitions du dépôt, sans initialisation
    # Toutes les commandes sont simulées, même les lectures.
    namespace.update(run=Mock(), qs_ipc=Mock(), emit=Mock())
    for key in ("MEMORY_FILE", "UNDO_FILE", "ALARMS_FILE", "ROUTINES_FILE"):
        namespace[key] = tmp_path / (key + ".json")
    return namespace


def test_preferences_persistantes_et_effacement(siri):
    assert siri["t_memory"]("retenir", "sommeil_reveil", "07:00")["ok"]
    assert siri["t_memory"]("lire")["preferences"] == {"sommeil_reveil": "07:00"}
    assert siri["MEMORY_FILE"].stat().st_mode & 0o777 == 0o600
    assert siri["t_memory"]("oublier", "sommeil_reveil")["ok"]
    assert siri["preferences"]() == {}
    siri["t_memory"]("retenir", "ville", "Conakry")
    assert siri["t_memory"]("effacer_tout")["ok"]
    assert siri["preferences"]() == {}


def test_memoire_corrompue_conservee(siri):
    siri["MEMORY_FILE"].write_text("invalide")
    with pytest.raises(ValueError):
        siri["t_memory"]("retenir", "ville", "Conakry")
    assert siri["MEMORY_FILE"].read_text() == "invalide"


@pytest.mark.parametrize("delay", ["0s", "25h", "-5m", "demain", "nan", "1m puis 30s"])
def test_delais_invalides(siri, delay):
    with pytest.raises(ValueError):
        siri["duration_seconds"](delay)


def test_arret_musical_cible_et_verifie(siri):
    siri["run"] = Mock(side_effect=["inactive", "onde\nchrome", "Playing", "", "active"])
    result = siri["t_music_sleep"]("programmer", "30m")
    assert result["ok"] and result["programme"]
    command = siri["run"].call_args_list[3].args
    assert "--on-active=1800.0s" in command
    assert command[-3:] == ("playerctl", "--player=onde", "pause")


def test_pas_de_remplacement_silencieux_du_delai(siri):
    siri["run"] = Mock(return_value="active")
    assert not siri["t_music_sleep"]("programmer", "30m")["ok"]
    assert siri["run"].call_count == 1


def test_annulation_arret_musical(siri):
    siri["run"] = Mock(side_effect=["active", "", "inactive"])
    result = siri["t_music_sleep"]("annuler")
    assert result["ok"] and not result["programme"]


def test_erreur_scheduler_ne_confirme_pas(siri):
    siri["run"] = Mock(side_effect=["inactive", "onde", "Playing", "erreur : refusé"])
    assert not siri["t_music_sleep"]("programmer", "30m")["ok"]


def test_sans_musique_pas_de_programmation(siri):
    siri["run"] = Mock(side_effect=["inactive", "erreur : code 1 : No players found"])
    result = siri["t_music_sleep"]("programmer", "30m")
    assert result["ok"] and result["verifie"] and not result["programme"]
    assert siri["run"].call_count == 2


def test_etat_scheduler_inchange_ne_confirme_pas(siri):
    siri["run"] = Mock(side_effect=["inactive", "onde", "Playing", "", "inactive"])
    assert not siri["t_music_sleep"]("programmer", "30m")["ok"]


def test_reveil_conserve_les_autres_alarmes(siri):
    existing = {"id": "personnel", "time": "08:00", "days": [1], "enabled": True}
    siri["write_json"](siri["ALARMS_FILE"], [existing])
    siri["qs_ipc"] = Mock(return_value="ok")
    hour = (dt.datetime.now().astimezone() + dt.timedelta(hours=2)).strftime("%H:%M")
    result = siri["t_alarm"]("programmer", hour)
    assert result["ok"] and result["programme"]
    alarms = json.loads(siri["ALARMS_FILE"].read_text())
    assert existing in alarms
    assert sum(a["id"] == "siri-reveil" for a in alarms) == 1
    assert siri["t_alarm"]("programmer", hour)["ok"]
    assert len(json.loads(siri["ALARMS_FILE"].read_text())) == 2
    assert siri["t_alarm"]("annuler")["ok"]
    assert json.loads(siri["ALARMS_FILE"].read_text()) == [existing]


@pytest.mark.parametrize("hour", ["25:00", "07:99", "demain", "7:00"])
def test_reveil_invalide_sans_ecriture(siri, hour):
    assert not siri["t_alarm"]("programmer", hour)["ok"]
    assert not siri["ALARMS_FILE"].exists()


def test_reveil_refuse_shell_absent(siri):
    siri["qs_ipc"] = Mock(return_value="erreur : shell indisponible")
    hour = (dt.datetime.now().astimezone() + dt.timedelta(hours=2)).strftime("%H:%M")
    assert not siri["t_alarm"]("programmer", hour)["ok"]
    assert not siri["ALARMS_FILE"].exists()


def test_reunion_signale_micro_coupe(siri):
    siri["run"] = Mock(return_value="Volume: 0.50 [MUTED]")
    siri["call_ano"] = Mock(return_value="Site ouvert dans Google Chrome : https://example.org.")
    result = siri["t_meeting"]("https://example.org")
    assert result["ok"] and not result["micro_pret"]
    assert siri["run"].call_count == 1  # aucune réactivation automatique


def test_reunion_refuse_micro_illisible(siri):
    siri["run"] = Mock(return_value="erreur : absent")
    siri["call_ano"] = Mock()
    assert not siri["t_meeting"]("https://example.org")["ok"]
    siri["call_ano"].assert_not_called()


@pytest.mark.parametrize("link", ["file:///etc/passwd", "javascript:alert(1)", "https://user:pass@example.org", "invalide"])
def test_lien_reunion_invalide(siri, link):
    siri["run"] = Mock()
    assert not siri["t_meeting"](link)["ok"]
    siri["run"].assert_not_called()


def test_annulation_volume_et_muet(siri):
    state = {"niveau": 20, "muet": True}

    def volume(action="lire", level=None):
        if action == "regler":
            state["niveau"] = level
        elif action in {"couper", "retablir"}:
            state["muet"] = action == "couper"
        return {"ok": True, "verifie": True, **state}

    siri["t_volume"] = volume
    assert siri["run_setting"]("volume", {"action": "regler", "level": 60})["ok"]
    assert siri["t_undo"]()["ok"]
    assert state == {"niveau": 20, "muet": True}
    assert json.loads(siri["UNDO_FILE"].read_text()) == []


def test_annulation_refuse_reglage_change_manuellement(siri):
    state = {"niveau": 20, "muet": False}

    def brightness(action="lire", level=None):
        if action == "regler":
            state["niveau"] = level
        return {"ok": True, "verifie": True, **state}

    siri["t_brightness"] = brightness
    siri["run_setting"]("luminosite", {"action": "regler", "level": 60})
    state["niveau"] = 80
    assert not siri["t_undo"]()["ok"]
    assert state["niveau"] == 80


def test_personnalisation_preserve_autres_etapes(siri):
    result = siri["personalize_routine"]({"nom": "travail", "niveau": 30, "applications": '["Chrome", "Kitty"]'})
    assert result["ok"]
    result = siri["personalize_routine"]({"nom": "travail", "niveau": 40})
    assert [s["arguments"]["name"] for s in result["etapes"] if s["outil"] == "open_app"] == ["Chrome", "Kitty"]
    assert result["etapes"][0]["outil"] == "ne_pas_deranger"


def test_sommeil_manquant_ne_modifie_rien(siri):
    assistant = SimpleNamespace(call_tool=AsyncMock())
    result = asyncio.run(siri["run_routine"](assistant, {"action": "lancer", "nom": "sommeil"}))
    assert result["configuration_requise"]
    assert set(result["champs_manquants"]) == {"delai", "heure"}
    assistant.call_tool.assert_not_called()


def test_sommeil_complete_depuis_memoire(siri):
    siri["t_memory"]("retenir", "sommeil_delai", "30m")
    siri["t_memory"]("retenir", "sommeil_reveil", "07:00")
    plan = siri["complete_routine"](siri["routine_store"]("lancer", "sommeil"), {})
    assert plan["etapes"][1]["arguments"]["delai"] == "30m"
    assert plan["etapes"][2]["arguments"]["heure"] == "07:00"
    plan = siri["complete_routine"](siri["routine_store"]("lancer", "sommeil"), {"heure": "08:00"})
    assert plan["etapes"][2]["arguments"]["heure"] == "08:00"
    assert siri["preferences"]()["sommeil_reveil"] == "07:00"


def test_routine_arretee_au_premier_echec(siri):
    assistant = SimpleNamespace(call_tool=AsyncMock(side_effect=[{"ok": True, "verifie": True}, {"ok": False}]))
    result = asyncio.run(siri["run_routine"](assistant, {"action": "lancer", "nom": "sommeil", "delai": "30m", "heure": "07:00"}))
    assert not result["ok"] and len(result["bilan"]) == 2 and len(result["restantes"]) == 1
    assert assistant.call_tool.await_count == 2


def test_routine_refuse_exec_arbitraire(siri):
    with pytest.raises(ValueError):
        siri["routine_steps"]('[{"outil":"shell_exec","arguments":{"command":"test"}}]')


def test_personnalisation_sans_nom_refusee(siri):
    assistant = SimpleNamespace(call_tool=AsyncMock())
    result = asyncio.run(siri["run_routine"](assistant, {"action": "personnaliser", "niveau": 30}))
    assert not result["ok"]
    assert not siri["ROUTINES_FILE"].exists()


@pytest.mark.parametrize(("tool", "arguments", "expected"), [
    ("reveil", {"action": "programmer", "heure": "07:00"}, {"action": "programmer", "time_": "07:00"}),
    ("arret_musique", {"action": "programmer", "delai": "30m"}, {"action": "programmer", "delay": "30m"}),
    ("preparer_reunion", {"lien": "https://example.org"}, {"link": "https://example.org"}),
])
def test_dispatch_parametres_francais(siri, tool, arguments, expected):
    mock = Mock(return_value={"ok": True})
    spec = siri["TOOLS"][tool]
    siri["TOOLS"][tool] = (mock, *spec[1:])
    assert asyncio.run(siri["_call_tool"](SimpleNamespace(), tool, arguments))["ok"]
    mock.assert_called_once_with(**expected)
