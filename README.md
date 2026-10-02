<div align="center">

# 🫧 Caelestia · Liquid Glass

**Le « liquid glass » de macOS sur Hyprland, construit sur [Caelestia](https://github.com/caelestia-dots/caelestia).**

Verre translucide partout, Mission Control, Spotlight, animations fluides façon macOS, gestes du pavé tactile — installé en **une seule commande**.

![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=archlinux&logoColor=white)
![Hyprland](https://img.shields.io/badge/Hyprland-0.56+-58E1FF?style=flat)
![Caelestia](https://img.shields.io/badge/caelestia--shell-2.3-e6c093?style=flat)
![Licence](https://img.shields.io/badge/licence-GPL--3.0-blue?style=flat)

[English summary below](#-english)

</div>

---

## ✨ Ce que tu obtiens

### 🫧 Liquid glass partout
- **Tout le shell en verre** : barre, cadre de l'écran, barre latérale, tableau de bord, lanceur, menus, OSD volume/luminosité, menu de session, écran de verrouillage, paramètres.
- **Une seule pièce de verre** : les panneaux sortent du cadre et s'y fondent, avec un **liseré lumineux** qui suit toutes les courbes et un **reflet qui suit la souris**.
- **Deux shaders écrits sur mesure** (biseau éclairé, légère aberration chromatique, reflet spéculaire), le flou venant de Hyprland.
- **Notifications en verre**, avec une arrivée en douceur.
- **Écran de connexion façon macOS** (SDDM) : ton fond d'écran avec une grande horloge, puis, à la première touche, un flou, ta photo et un champ de mot de passe en verre. Le fond d'écran et la photo se synchronisent tout seuls avec ton bureau.
- **kitty, les applis GTK et les outils en verre** : Nautilus, Calculatrice, Éditeur de texte, Loupe, pavucontrol, Thunar, sélecteur de fichiers… fond translucide et flouté, **texte toujours net**, barre latérale flottante façon Finder et le même liseré de verre sur le bord des fenêtres.
- **kitty survitaminé** : barre d'onglets en pilules (icône du programme, disposition, batterie, heure), terminal déroulant (``Super + ` ``), splits au clavier, recherche floue dans l'historique, sortie de la dernière commande, hints (liens, chemins, `fichier:ligne` → nvim), diffusion dans tous les panneaux, sessions, notification quand une longue commande finit, palette de commandes (`Ctrl + Maj + Alt + P`).
- **Prompt Starship en capsules** : distribution + utilisateur, dossier, git, langages, durée, erreurs et heure dans des capsules Catppuccin Mocha reliées par une ligne.
- **Les couleurs suivent ton fond d'écran** : tout est régénéré automatiquement à chaque changement de thème.
- **Fond d'écran animé qui épargne la batterie** : mets une vidéo (`.mp4`, `.webm`…) dans ton dossier de fonds d'écran, elle apparaît dans le sélecteur avec un badge ▶ (ou `caelestia-animwall video.mp4`, qui accepte aussi un GIF) ; elle se joue en boucle **seulement sur secteur**. Dès que tu débranches, la vidéo est arrêtée et déchargée, et une image tirée de la vidéo prend le relais ; elle repart quand tu rebranches. `caelestia-animwall off` (ou choisir une image dans le sélecteur) revient à l'image seule.

### 🪟 Façon macOS
- **Dock qui se cache**, pensé pour le tiling : il ne prend aucune place, sort du bas de l'écran quand la souris touche le bord (et reste sur un bureau vide), icônes qui grossissent au survol, point sous les apps ouvertes, rebond au lancement, clic droit pour épingler / fermer.
- **Centre de contrôle façon macOS 27** (`Super + A`), qui descend du haut à droite dans le même verre : Wi-Fi (liste des réseaux, mot de passe directement dedans), Bluetooth (appareils, batterie), VPN, Concentration, apparence claire/sombre, lecteur, luminosité, volume et choix de la sortie audio, raccourcis rapides (caféine, mode jeu, micro, capture, horloge, calculatrice, tableau de bord), **enregistrement de l'écran** (plein écran ou zone, son de l'ordinateur et/ou micro ou sans son, compte à rebours dans l'île, pause et arrêt depuis l'île), batterie et profils d'énergie, icônes système, session. **La barre de gauche et le panneau du coin bas-droit sont retirés** : le cadre est fin et uniforme, tout passe par le Centre de contrôle.
- **Démarrage façon Mac** (optionnel) : logo blanc et fine barre de progression sur fond noir, au lieu du texte qui défile.
- **Curseur macOS** ([apple_cursor](https://github.com/ful1e5/apple_cursor)), jusque sur l'écran de connexion.
- **Dynamic Island** en liquid glass, fondue dans le cadre (le bord du haut disparaît, elle sort directement de l'écran) : musique avec visualiseur, lecteur complet au survol (pochette, progression cliquable, commandes), volume et luminosité façon macOS (jauge glissable), **connexion des écouteurs façon AirPods** (ondes + anneau de batterie), **chargeur branché/débranché** (batterie qui se remplit, éclair, temps restant), **captures d'écran** (miniature avec flash, Annoter / Enregistrer / Dossier), **notifications** (file d'attente, actions au survol), charge, enregistrement d'écran. Molette = volume, clic = lecture/pause.
  - **Au repos** : date, heure et batterie façon barre de menus macOS (verte avec un éclair en charge, rouge et pourcentage sous 20 %, pulse sous 10 %).
  - **Centre de notifications** : clic sur l'heure (ou `Super + N`) : l'île se déroule avec tes notifications (Tout effacer, Ne pas déranger, × au survol). L'ancien volet latéral est retiré.
  - **Tout passe par elle** : bulles de Caelestia (Ne pas déranger, batterie faible, thème…), changement de bureau, Verr. Maj, Wi-Fi et VPN.
  - **Micro et caméra** : point orange ou vert à côté de l'heure quand une app les utilise, comme sur macOS.
  - **Paroles en direct** sous le titre (cache du lecteur [Aura](https://github.com/Abdoul273/aura), fichier `.lrc`, sinon [LRCLIB](https://lrclib.net)).
  - **Minuteur et chronomètre** : tape `minuteur 5 min` ou `chrono` dans Spotlight (ou `qs -c caelestia ipc call island timer 5m`).
  - **Gestes** : glisser ← → sur la musique pour changer de morceau, ↑ pour chasser une notification.
  - **Étagère** : dépose un fichier sur l'île pour le garder sous la main, reprends-le en le glissant ailleurs.
  - **Agents IA** (Claude Code, Codex) : l'anneau tourne dans l'île pendant qu'un agent travaille (projet + outil en cours), une page liste tes agents (clic = son terminal), l'île te prévient quand un agent a fini, et les **demandes de permission de Claude Code** s'affichent avec **Autoriser / Refuser**. Pour les permissions, ajoute ce hook dans `~/.claude/settings.json` :
    ```json
    "hooks": { "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.local/bin/caelestia-agents hook", "timeout": 120 }] }] }
    ```
- **Mission Control** (`Super + Tab` ou **3 doigts vers le haut**) : tes fenêtres glissent en grille, tes bureaux s'affichent en haut, et un clic t'y emmène.
- **Spotlight** (`Super + Espace`) : **lance tes apps** (la meilleure en grand, Entrée pour l'ouvrir), actions du système (verrouiller, veille, éteindre, paramètres, Horloge…), **fichiers** de ton dossier perso, calculs et conversions, puis suggestions Google, fiche Wikipédia et résultats web.
- **Calculatrice** (`Super + O`) : une seule ligne dans le verre de l'île ; le résultat apparaît en grand pendant que tu tapes (`12,5 × 4 + 20 %`), Entrée le copie, ↑ rappelle l'historique.
- **Assistant vocal** (`Super + Maj + Espace`) : un Siri dans le verre de l'île. Une orbe réagit à ta voix, il répond à voix haute (Gemini Live audio natif : `gemini-3.8-live` → `3.1-flash-live` → `2.5 native-audio`, voix Charon) et contrôle tout l'ordinateur avec les actions d'ANO-GPT quand il est installé (ouvrir/fermer des applis, terminal, fenêtres, réglages, navigateur, fichiers, mails, agenda, rappels, météo, YouTube, musique… ; les actions sensibles se valident par le bouton Confirmer d'une notification), regarder l'écran et répondre dessus, veille/extinction, minuteur dans l'île, musique, volume, luminosité, Ne pas déranger, verrouiller, écrire un texte dans le champ actif, recherche web (si ANO-GPT est installé). Reprise de session et compression de contexte : la conversation continue d'une ouverture à l'autre (15 min) et ne s'arrête pas sur une longue discussion. Micro coupé par défaut, comme « Écrire à Siri » : on écrit sa demande, ou on active le micro (bouton ou Tab) pour une demande vocale, puis il se recoupe. Échap coupe la parole, puis ferme. `"micro_par_defaut": true` dans la config pour un mode mains libres (micro ouvert et fermeture automatique). Réglages : `~/.config/caelestia-siri/config.json` (`api_key`, `voice`, `name`, `models`).
- **Dictée** (`Super + Maj + D`) : clique dans un champ, appuie sur le raccourci et parle ; le texte s'affiche en direct dans le verre de l'île, puis Entrée (ou le même raccourci) le tape dans le champ, Échap annule. Reconnaissance Gemini (`gemini-3.5-transcribe-live`, ponctuation automatique) : mettre la clé dans `~/.config/caelestia-dictate/config.json` (`{"api_key": "…"}`) ou la variable `GEMINI_API_KEY`. Il faut `python-google-genai`, `wtype` et `pw-record`.
- **Outils d'écriture** (`Super + Maj + W`) : sélectionne du texte n'importe où ; la goutte propose Corriger, Reformuler, Professionnel, Amical, Concis, Résumer, Points clés, En anglais, ou une consigne libre (« ajoute un emoji »…). Le résultat arrive en direct, Entrée remplace la sélection, Ctrl+C copie.
- **Traduction** (`Super + Alt + T`) : une ligne comme Spotlight, reprend la sélection, traduit pendant que tu tapes (Auto = français ↔ anglais, Tab pour une autre langue) ; Entrée insère la traduction dans le champ. Mêmes réglages Gemini que la dictée (`~/.config/caelestia-write/config.json` ou `GEMINI_API_KEY`).
- **Horloge** (`Super + Maj + O`) : minuteur avec anneau, chronomètre à cadran et tours, pomodoro automatique et alarmes. Tout tourne dans la Dynamic Island : le minuteur continue et l'alarme sonne même app fermée.
- **Aperçu rapide** : dans Nautilus, sélectionne un fichier et appuie sur **Espace**.
- **Indicateur de bureau** en verre pendant les changements de bureau.
- **Bureaux dynamiques** : `Super + Page ↑/↓` va aussi loin que tu veux, et les points de l'île s'effacent dès que tu reviens en arrière (seuls les bureaux occupés et les 3 de base restent).
- **Animations façon macOS** : ressorts courts et nets, léger rebond, glissade visible entre les bureaux. Consommation identique au Caelestia d'origine.

### ⌨️ Outils intégrés
| Outil | Raccourci |
|---|---|
| **Tous les raccourcis** (recherche, Entrée les déclenche) | `Super + H` |
| Presse-papiers (texte, images, liens, favoris) | `Super + V` |
| Emojis et symboles | `Super + .` |
| Projection (écran du PC, dupliquer, étendre, deuxième écran) | `Super + P` |
| Paramètres de Caelestia | `Super + I` |

### 🎧 Petits plus
- **Bascule audio Bluetooth automatique** : tes écouteurs deviennent la sortie et l'entrée dès qu'ils se connectent.
- **Tout le shell en français**.
- **Sons originaux** (libres de droits) pour les notifications et les branchements.

---

## 📋 Prérequis

- **Arch Linux** ou une dérivée (EndeavourOS, CachyOS, Manjaro…)
- **Hyprland 0.56 ou plus récent** (configuration en Lua)
- **Caelestia installé et fonctionnel**

> [!IMPORTANT]
> **Installe d'abord Caelestia**, puis connecte-toi une fois à ta session Hyprland avant d'installer Liquid Glass :
>
> ```sh
> paru -S caelestia-cli     # ou : yay -S caelestia-cli
> caelestia install
> ```
>
> Si Caelestia n'est pas détecté, l'installateur te le dira et pourra l'installer pour toi.

---

## 🚀 Installation

```sh
git clone https://github.com/Abdoul273/caelestia-liquid-glass.git
cd caelestia-liquid-glass
./install
```

C'est tout. L'installateur :

1. **vérifie** ton système (Arch, version de Hyprland, présence et version de Caelestia) ;
2. **installe les paquets nécessaires** (ton mot de passe est demandé une seule fois) ;
3. **sauvegarde toute ta configuration actuelle** avant de toucher à quoi que ce soit ;
4. installe le shell Liquid Glass, les réglages Hyprland, les outils, kitty et Nautilus en verre ;
5. **active les services** (bascule audio Bluetooth, verre de Nautilus) ;
6. **te propose les fonds d'écran macOS 27 « Golden Gate »** ;
7. installe le **curseur macOS** et **te propose l'écran de connexion en verre** (si tu utilises SDDM) ;
8. **te propose l'écran de démarrage façon Mac** (non coché par défaut, car il modifie le démarrage ; réversible) ;
9. **recharge ton bureau** : tout est actif immédiatement.

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

Appuie sur **`Super + H`** : une ligne de recherche façon Spotlight tombe de l'île ; tape ce que tu cherches (« capture », « bureau »…), les touches s'affichent, et **Entrée déclenche le raccourci**.

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
| `Super + Tab` | Mission Control |
| `Super + H` | Tous les raccourcis |
| `Super + I` | Paramètres de Caelestia |
| `Super + A` | Centre de contrôle |
| `Super + Maj + N` | Notes rapides (synchronisées avec AetherNotes) |
| `Super + Maj + T` | Tâches synchronisées avec AuraTask ; l’œil (ou « surveille … ») crée une surveillance vérifiée sur internet (clé Gemini dans `~/.config/caelestia/gemini-api-key`) |
| `Super + Maj + Q` | Quitter complètement l'app active (Super + Q ferme juste la fenêtre) |
| `Super + Maj + F` | Concentration : active / arrête le dernier mode (Ne pas déranger, Travail, Sommeil) |
| `Super + Retour arrière` | Éteindre / redémarrer / verrouiller |
| `Super + Maj + R` | Recharger Hyprland et le shell |
| ``Super + ` `` | Terminal kitty déroulant |
| `Ctrl + Maj + Alt + P` (dans kitty) | Palette de toutes les actions kitty |

### Pavé tactile
| Geste | Action |
|---|---|
| 3 doigts ← → | Changer de bureau (la page suit le doigt) |
| 3 doigts ↑ | Mission Control |
| 3 doigts ↓ | Fermer Mission Control |
| 4 doigts ← → | Changer de bureau |
| 4 doigts ↑ | Bureau spécial |

---

## 🎛️ Personnaliser

**Façon macOS** : Paramètres (`Super + I`) → **Façon macOS** — un interrupteur pour chaque fonction (Dynamic Island, notifications et messages dans l'île, bureaux, paroles, micro/caméra, date/heure et batterie au repos, bord haut, Centre de contrôle, barre de gauche, Dock). Tout s'applique immédiatement ; réglages dans `~/.config/caelestia/island.json`.

**Liquid glass** : Paramètres (`Super + I`) → **Fond d'écran et style** → **Liquid glass** — appliqué immédiatement, enregistré dans `~/.config/caelestia/glass.json` :
- **Style du verre** : *Classique* (verre teinté et flouté, le compromis, par défaut), *Verre plein* (verre clair façon iOS 26) ou *Désactivé* (panneaux opaques, les notifications restent en verre) ;
- **Applis GTK en verre** : *Nautilus* (par défaut), *Toutes* (Calculatrice, Éditeur de texte, Loupe, Thunar…) ou *Aucune*. En terminal : `caelestia-glass-gtk nautilus|complet|off`. Le verre GTK reprend les couleurs du thème Caelestia : il suit le thème clair ou sombre et le fond d'écran.
- Les fenêtres **Ouvrir / Enregistrer** (Chrome, Electron, applis GTK 4) passent aussi en verre en mode *Toutes* : un thème rien qu'au portail GTK, Chrome lui-même n'est pas touché.
- **Intensité du verre** : un curseur, de *très transparent* à *très dense* (au milieu = réglage d'origine), pour le shell et les applis GTK en même temps.

| Tu veux… | Où |
|---|---|
| Revenir aux animations d'origine de Caelestia | `~/.config/quickshell/caelestia/services/Motion.qml` → `enabled: false` |
| Changer d'applis par défaut, de raccourcis, d'espacement | `~/.config/caelestia/hypr-vars.lua` |
| Ajouter tes propres réglages Hyprland | à la fin de `~/.config/caelestia/hypr-user.lua` |
| Changer le style de tous les outils d'un coup | `~/.config/caelestia/tools-base.css` |
| Rendre kitty plus ou moins transparent | `~/.config/kitty/liquid-glass.conf` → `background_opacity` (ou `Ctrl + Maj + A` puis `M` / `L` à la volée) |
| Raccourcis, couleurs, barre d'onglets de kitty | `~/.config/kitty/keys.conf`, `theme.conf`, `tab_bar.py` |
| Changer ta photo (écran de connexion, tableau de bord) | remplace l'image `~/.face` |
| Changer les sonneries (minuteur, alarme, Pomodoro, rappels, transferts) | remplace les `.ogg` du dossier `~/Documents/Sons Caelestia` (voir son `LISEZ-MOI.txt`) |

Après une modification : `Super + Maj + R` pour tout recharger.

---

## 🧹 Désinstaller

```sh
./uninstall
```

Retire tout ce que l'installateur a posé et **restaure ta configuration d'avant** depuis la sauvegarde (`~/.local/share/caelestia-liquid-glass/backups/`). Les paquets installés sont conservés.

---

## ❓ Questions fréquentes

**Est-ce que ça ralentit mon PC ?**
Non. Les shaders ne calculent presque rien en dehors des bords du verre. Mesuré : même consommation que le Caelestia d'origine, environ 7 % d'un cœur au repos.

**J'ai modifié le shell ou ajouté des textes : comment garder le dépôt à jour ?**
`tools/synchroniser` montre les écarts entre `~/.config/quickshell/caelestia` et le dépôt (`--appliquer` les recopie). `tools/verifier-francais` liste les textes qui semblent encore en anglais.

**Ma version de caelestia-shell est différente.**
Liquid Glass remplace le shell de Caelestia par une version modifiée, prévue pour `caelestia-shell` 2.3. Avec une autre version, l'installateur te prévient avant de continuer. En cas de problème, `./uninstall` remet tout comme avant.

**Le verre des applis GTK (Nautilus…) a disparu après un changement de fond d'écran.**
Un petit service le remet automatiquement. Vérifie qu'il est actif : `systemctl --user status caelestia-glass-gtk.path`.

**Comment retirer l'écran de démarrage ?**
`sudo config/plymouth/install-boot-splash --remove` : la ligne de démarrage d'origine est restaurée depuis la sauvegarde (`/var/backups/caelestia-liquid-glass`).

**Ma disposition de clavier / ma langue est différente.**
Rien n'est imposé : ta disposition reste celle de ta config Hyprland, et les dossiers de captures suivent tes dossiers utilisateur (Images, Pictures…).

---

## 🙏 Crédits

- **[Caelestia](https://github.com/caelestia-dots)** par soramanew et ses contributeurs : le shell et les dotfiles sur lesquels tout repose (GPL-3.0).
- **Google Sans Flex** (SIL Open Font License), fournie avec Caelestia.
- **[apple_cursor](https://github.com/ful1e5/apple_cursor)** par ful1e5 (GPL-3.0), téléchargé à l'installation.
- Fonds d'écran macOS 27 : © Apple. Ils **ne sont pas inclus** dans ce dépôt ; l'installateur propose seulement de les télécharger depuis leur source publique.

## 📄 Licence

[GPL-3.0](LICENSE), comme Caelestia dont ce projet est dérivé.

---

## 🇬🇧 English

**Caelestia · Liquid Glass** brings a macOS-style liquid glass look to Hyprland, on top of the [Caelestia](https://github.com/caelestia-dots/caelestia) shell. You get:
- the whole shell in glass (two custom shaders, a light rim and a highlight that follows the cursor) ;
- a Dynamic Island at the top (music, volume, brightness, notifications, charging) ;
- Mission Control and a Spotlight-style search ;
- a live calculator, clipboard, emoji and display pickers ;
- a searchable shortcuts window (`Super + H`) ;
- macOS-like animations and trackpad gestures ;
- kitty and Nautilus in glass ;
- automatic Bluetooth audio switching.

The interface is in French.

**Requirements:** Arch Linux, Hyprland ≥ 0.56, and **Caelestia already installed** (`paru -S caelestia-cli && caelestia install`).

**Install:**
```sh
git clone https://github.com/Abdoul273/caelestia-liquid-glass.git
cd caelestia-liquid-glass
./install
```
The installer checks your system, installs dependencies, **backs up your current config**, installs everything (never touching `~/.config/hypr/`) and reloads your desktop. Run `./uninstall` to restore your previous setup.
