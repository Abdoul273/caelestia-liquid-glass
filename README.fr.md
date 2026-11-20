<div align="center">

# 🫧 Caelestia · Liquid Glass

**Le « liquid glass » de macOS sur Hyprland, construit sur [Caelestia](https://github.com/caelestia-dots/caelestia).**

Verre translucide partout, Dynamic Island (9 pages + agents IA), Centre de contrôle, Dock, Mission Control, Spotlight, animations et gestes façon macOS — installé en **une seule commande**.

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=archlinux&logoColor=white)](https://archlinux.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-0.56+-58E1FF?style=flat)](https://hyprland.org)
[![Caelestia](https://img.shields.io/badge/caelestia--shell-2.3-e6c093?style=flat)](https://github.com/caelestia-dots/caelestia)
[![Licence](https://img.shields.io/badge/licence-GPL--3.0-blue?style=flat)](LICENSE)
[![CI](https://github.com/Abdoul273/caelestia-liquid-glass/actions/workflows/ci.yml/badge.svg)](https://github.com/Abdoul273/caelestia-liquid-glass/actions/workflows/ci.yml)

**🇫🇷 Français** · [🇬🇧 English](README.md)

</div>

---

## ✨ Ce que tu obtiens

### 🫧 Liquid glass partout
- **Tout le shell en verre** : barre, cadre de l'écran, barre latérale, tableau de bord, lanceur, menus, OSD volume/luminosité, menu de session, écran de verrouillage, paramètres.
- **Une seule pièce de verre** : les panneaux sortent du cadre et s'y fondent, avec un **liseré lumineux** qui suit toutes les courbes et un **reflet qui suit la souris**.
- **Shaders écrits sur mesure** (biseau éclairé, légère aberration chromatique, reflet spéculaire, contrôles bombés en verre), le flou venant de Hyprland.
- **Notifications en verre**, avec piles rétractables par appli, filtres et arrivée en douceur.
- **Écran de connexion façon macOS** (SDDM) : ton fond d'écran avec une grande horloge, puis, à la première touche, un flou, ta photo et un champ de mot de passe en verre. Le fond d'écran et la photo se synchronisent tout seuls avec ton bureau.
- **kitty, les applis GTK et les outils en verre** : Nautilus, Calculatrice, Éditeur de texte, Loupe, pavucontrol, Thunar, sélecteur de fichiers… fond translucide et flouté, **texte toujours net**, barre latérale flottante façon Finder et le même liseré de verre sur le bord des fenêtres.
- **kitty survitaminé** : barre d'onglets en pilules (icône du programme, disposition, batterie, heure), terminal déroulant (``Super + ` ``), splits au clavier, recherche floue dans l'historique, sortie de la dernière commande, hints (liens, chemins, `fichier:ligne` → nvim), diffusion dans tous les panneaux, sessions, notification quand une longue commande finit, palette de commandes (`Ctrl + Maj + Alt + P`).
- **Prompt Starship en capsules** : distribution + utilisateur, dossier, git, langages, durée, erreurs et heure dans des capsules Catppuccin Mocha reliées par une ligne.
- **Les couleurs suivent ton fond d'écran** : tout est régénéré automatiquement à chaque changement de thème.
- **Économie d'énergie automatique** : dès le débranchement, le verre et Hyprland s'allègent automatiquement ; les fonds d'écran vidéo (`.mp4`, `.webm`, GIF via `caelestia-animwall`) se jouent uniquement sur secteur et basculent sur une image fixe sur batterie.

### 🪟 Façon macOS
- **Dock qui se cache**, pensé pour le tiling : il ne prend aucune place, sort du bas de l'écran quand la souris touche le bord (et reste sur un bureau vide), icônes qui grossissent au survol, point sous les apps ouvertes, glisser-déposer pour réorganiser, rebond au lancement, clic droit pour épingler / quitter.
- **Centre de contrôle façon macOS 27** (`Super + A`), qui descend du haut à droite dans le même verre : Wi-Fi (liste des réseaux, mot de passe directement dedans), Bluetooth (appareils, batterie), VPN, Concentration, éclairage de nuit, apparence claire/sombre, lecteur, luminosité, volume et choix de la sortie audio, raccourcis rapides (caféine, mode jeu, micro, capture, horloge, calculatrice), **enregistrement de l'écran** (plein écran ou zone, son PC/micro, compte à rebours dans l'île), **batterie détaillée** (watts, santé, graphe adaptatif, processus gourmands, profils d'énergie), icônes système, session.
- **Démarrage façon Mac** (optionnel, Plymouth) : logo blanc et fine barre de progression sur fond noir, au lieu du texte qui défile.
- **Curseur macOS** ([apple_cursor](https://github.com/ful1e5/apple_cursor)), jusque sur l'écran de connexion.
- **Dynamic Island** en liquid glass, fondue dans le cadre avec **9 pages navigables** (molette / pavé tactile / clic) :
  - **Au repos** : date, heure centrée, batterie façon barre de menus macOS, icônes d'état (micro/caméra, Bluetooth, Concentration, étagère).
  - **Musique & spectre Cava** : visualiseur audio liquide, halo réactif aux basses, lecteur complet au survol et **paroles en direct** (synchronisation [Onde](https://github.com/Abdoul273/onde) / [Aura](https://github.com/Abdoul273/aura), fichiers `.lrc`, ou [LRCLIB](https://lrclib.net)).
  - **Animations matérielles** : chargeur MagSafe plasma avec télémétrie en watts, balise radar Wi-Fi vectorielle, connexion d'écouteurs façon AirPods (ondes + anneau batterie), captures d'écran avec flash et actions rapides, transferts de fichiers, appels.
  - **Centre de notifications** (`Super + N` ou clic sur l'île) : piles rétractables par appli, filtres, Ne pas déranger.
  - **Performances système** : anneaux CPU + fréquence, température + ventilateur, RAM, disque et débit réseau en direct.
  - **Minuteur, chronomètre, Pomodoro & alarmes** (`Super + Maj + O` ou Spotlight `minuteur 5 min`), étagère glisser-déposer.
  - **Agents IA** (Claude Code, Codex) : suivi en direct dans l'île (projet + outil actif), page listant les agents, notification de fin, et **demandes de permission Claude Code** avec **Autoriser / Refuser** via ce hook dans `~/.claude/settings.json` :
    ```json
    "hooks": { "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.local/bin/caelestia-agents hook", "timeout": 120 }] }] }
    ```
- **Écouteurs 3D** (`Super + Maj + B` ou automatique à la connexion) : goutte de verre avec rendu 3D temps réel façon AirPodsDesktop (boîtier qui s'ouvre au ressort, rotation avec inertie, LEDs selon la batterie, jauges Gauche / Boîtier / Droite, volume et reconnexion Bluetooth).
- **Mission Control** (`Super + Tab` ou **3 doigts vers le haut**) : fenêtres en grille, bureaux en haut, navigation directe.
- **Spotlight** (`Super + Espace`) : lanceur d'applications, actions système, fichiers locaux, notes/tâches, calculs et conversions, suggestions et recherche web.
- **Calculatrice** (`Super + O`) : une ligne dans le verre de l'île (`12,5 × 4 + 20 %`), Entrée copie, ↑ historique.
- **Outils IA optionnels (Gemini)** :
  - **Assistant vocal** (`Super + Maj + Espace`) : interface conversationnelle façon Siri (Gemini Live audio natif, texte par défaut + micro à la demande, reprise de session, contrôle système). Configuration dans `~/.config/caelestia-siri/config.json`.
  - **Dictée** (`Super + Maj + D`) : transcription en direct dans l'île et saisie dans le champ actif (`~/.config/caelestia-dictate/config.json` ou `GEMINI_API_KEY`).
  - **Outils d'écriture** (`Super + Maj + W`) : corriger, reformuler, résumer, ton pro/amical ou consigne libre sur le texte sélectionné.
  - **Traduction rapide** (`Super + Alt + T`) : traduction instantanée depuis la sélection ou la saisie (`~/.config/caelestia-write/config.json` ou `GEMINI_API_KEY`).
- **Aperçu rapide** : dans Nautilus, sélectionne un fichier et appuie sur **Espace** (`sushi`).
- **Bureaux dynamiques** et **animations façon macOS** : ressorts courts et nets, glissade fluide, consommation identique au Caelestia d'origine.

### ⌨️ Outils intégrés
| Outil | Raccourci |
|---|---|
| **Tous les raccourcis** (recherche, Entrée déclenche) | `Super + H` |
| Presse-papiers (texte, images, liens, favoris) | `Super + V` |
| Emojis et symboles | `Super + .` |
| Projection (écran PC, dupliquer, étendre, 2ᵉ écran, sans fil Miracast/Chromecast) | `Super + P` |
| Paramètres de Caelestia | `Super + I` |

### 🎧 Petits plus
- **Bascule audio Bluetooth automatique** : sortie et entrée basculent dès la connexion des écouteurs.
- **Interface bilingue automatique (FR / EN)** : détecte la langue du système (`LANG=fr_*` → français, anglais sinon), commutable en direct dans **Paramètres (`Super + I`) → Langue et région** (`~/.config/caelestia/lang.json`).
- **Sons originaux** libres de droits pour les notifications, minuteurs, alarmes et branchements.

---

## 📋 Prérequis

- **Arch Linux** ou dérivée (EndeavourOS, CachyOS, Manjaro…)
- **Hyprland 0.56 ou plus récent** (configuration Lua)
- **Caelestia installé et fonctionnel**

> [!IMPORTANT]
> **Installe d'abord Caelestia**, puis connecte-toi une fois à ta session Hyprland avant d'installer Liquid Glass :
>
> ```sh
> paru -S caelestia-cli     # ou : yay -S caelestia-cli
> caelestia install
> ```
>
> Si Caelestia n'est pas détecté, l'installateur te le signalera et pourra l'installer pour toi.

---

## 🚀 Installation

```sh
git clone https://github.com/Abdoul273/caelestia-liquid-glass.git
cd caelestia-liquid-glass
./install
```

L'installateur :

1. **vérifie** ton système (Arch, version de Hyprland, présence et version de Caelestia) ;
2. **installe les paquets nécessaires** (mot de passe demandé une seule fois) ;
3. **sauvegarde toute ta configuration actuelle** avant toute modification ;
4. installe le shell Liquid Glass, les réglages Hyprland, les outils, kitty et les apps GTK en verre ;
5. **active les services utilisateur** (bascule audio Bluetooth, verre GTK) ;
6. **propose les fonds d'écran macOS 27 « Golden Gate »** (téléchargés à la demande, non inclus dans le dépôt) ;
7. installe le **curseur macOS** et **propose l'écran de connexion en verre** (SDDM) ;
8. **propose l'écran de démarrage façon Mac** (Plymouth, non coché par défaut, réversible) ;
9. **recharge ton bureau** immédiatement.

Options :

```sh
./install --dry-run   # montre ce qui serait fait, sans rien modifier
./install --yes       # répond « oui » à tout
./install --no-deps   # n'installe aucun paquet
```

> [!NOTE]
> L'installateur **ne modifie jamais `~/.config/hypr/`**, comme le recommande Caelestia. Tous les réglages vont dans `~/.config/caelestia/hypr-user.lua` et `hypr-vars.lua`, donc les mises à jour de Caelestia restent sans conflit.

---

## ⌨️ Raccourcis et gestes

Appuie sur **`Super + H`** : cherche un raccourci (ou tape « tout ») et appuie sur **Entrée** pour le déclencher.

### Essentiels
| Raccourci | Action |
|---|---|
| `Super` | Lanceur d'applications |
| `Super + Espace` | Recherche façon Spotlight |
| `Super + O` | Calculatrice |
| `Super + Maj + Espace` | Assistant vocal |
| `Super + Maj + D` | Dictée dans le champ actif |
| `Super + Maj + W` | Outils d'écriture (sélection) |
| `Super + Alt + T` | Traduction rapide |
| `Super + Maj + O` | Horloge (minuteur, chrono, pomodoro, alarmes) |
| `Super + Maj + B` | Écouteurs 3D (animation 3D, batterie, connexion) |
| `Super + Tab` | Mission Control |
| `Super + H` | Tous les raccourcis |
| `Super + I` | Paramètres de Caelestia |
| `Super + A` | Centre de contrôle |
| `Super + N` | Centre de notifications (Dynamic Island) |
| `Super + Maj + N` | Notes rapides |
| `Super + Maj + T` | Tâches rapides |
| `Super + Maj + Q` | Quitter complètement l'app active (`Super + Q` ferme juste la fenêtre) |
| `Super + Maj + F` | Concentration (Ne pas déranger, Travail, Sommeil) |
| `Super + Retour arrière` | Éteindre / redémarrer / verrouiller |
| `Super + Maj + R` | Recharger Hyprland et le shell |
| ``Super + ` `` | Terminal kitty déroulant |
| `Ctrl + Maj + Alt + P` (dans kitty) | Palette de toutes les actions kitty |

### Pavé tactile
| Geste | Action |
|---|---|
| 3 doigts ← → | Changer de bureau |
| 3 doigts ↑ | Mission Control |
| 3 doigts ↓ | Fermer Mission Control |
| 4 doigts ← → | Changer de bureau |
| 4 doigts ↑ | Bureau spécial |

---

## 🎛️ Personnaliser

- **Façon macOS** : Paramètres (`Super + I`) → **Façon macOS** — interrupteurs individuels (Dynamic Island, notifications, bureaux, paroles, micro/caméra, horloge au repos, Centre de contrôle, Dock…), stockés dans `~/.config/caelestia/island.json`.
- **Liquid glass** : Paramètres (`Super + I`) → **Fond d'écran et style** → **Liquid glass** (`~/.config/caelestia/glass.json`) :
  - **Style du verre** : *Classique* (par défaut), *Verre plein* (façon iOS 26/27) ou *Désactivé* ;
  - **Applis GTK** : *Nautilus* (par défaut), *Toutes* (inclut le portail Ouvrir/Enregistrer) ou *Aucune* (`caelestia-glass-gtk nautilus|complet|off`) ;
  - **Intensité du verre** : curseur continu pour le shell et GTK.

| Tu veux… | Où |
|---|---|
| Revenir aux animations d'origine de Caelestia | `~/.config/quickshell/caelestia/services/Motion.qml` → `enabled: false` |
| Changer d'applis par défaut, raccourcis, espacement | `~/.config/caelestia/hypr-vars.lua` |
| Ajouter tes propres réglages Hyprland | à la fin de `~/.config/caelestia/hypr-user.lua` |
| Changer le style de tous les outils d'un coup | `~/.config/caelestia/tools-base.css` |
| Opacité de kitty | `~/.config/kitty/liquid-glass.conf` (`background_opacity`) |
| Raccourcis, couleurs, barre d'onglets kitty | `~/.config/kitty/keys.conf`, `theme.conf`, `tab_bar.py` |
| Photo de profil (SDDM, écran de verrouillage) | `~/.face` |
| Sonneries personnalisées | `~/Documents/Sons Caelestia` |

Après modification : `Super + Maj + R` pour recharger.

---

## 🧹 Désinstaller

```sh
./uninstall
```

Retire tout ce que l'installateur a posé et **restaure ta configuration d'avant** depuis `~/.local/share/caelestia-liquid-glass/backups/`. Les paquets installés sont conservés.

---

## ❓ Questions fréquentes

**Est-ce que ça ralentit mon PC ?**
Non. Les shaders ne calculent presque rien hors des bords du verre (~7 % d'un cœur au repos, identique au Caelestia d'origine), et les effets s'allègent automatiquement sur batterie.

**Comment garder le dépôt synchronisé avec le shell installé ?**
`tools/synchroniser` liste les écarts (`--appliquer` les recopie). `tools/verifier-francais` repère les chaînes non traduites.

**Ma version de `caelestia-shell` est différente.**
Prévu pour `caelestia-shell` 2.3. L'installateur t'avertit si la version diffère et `./uninstall` restaure ton état précédent.

**Le verre GTK a disparu après un changement de fond d'écran.**
Vérifie le service : `systemctl --user status caelestia-glass-gtk.path`.

**Comment retirer l'écran de démarrage Plymouth ?**
`sudo config/plymouth/install-boot-splash --remove` restaure `/etc/kernel/cmdline` depuis `/var/backups/caelestia-liquid-glass`.

---

## 🙏 Crédits

- **[Caelestia](https://github.com/caelestia-dots)** par soramanew et ses contributeurs (GPL-3.0).
- **Google Sans Flex** (SIL Open Font License), fournie avec Caelestia.
- **[apple_cursor](https://github.com/ful1e5/apple_cursor)** par ful1e5 (GPL-3.0), téléchargé à l'installation.
- Fonds d'écran macOS 27 : © Apple, non inclus dans ce dépôt.

## 📄 Licence

[GPL-3.0](LICENSE), comme Caelestia dont ce projet est dérivé.
