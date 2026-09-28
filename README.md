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
- **kitty, Nautilus et les outils en verre** : fond translucide et flouté, **texte toujours net**, et le même liseré de verre sur le bord des fenêtres.
- **Prompt Starship en capsules** : distribution + utilisateur, dossier, git, langages, durée, erreurs et heure dans des capsules Catppuccin Mocha reliées par une ligne.
- **Les couleurs suivent ton fond d'écran** : tout est régénéré automatiquement à chaque changement de thème.

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
- **Mission Control** (`Super + Tab` ou **3 doigts vers le haut**) : tes fenêtres glissent en grille, tes bureaux s'affichent en haut, et un clic t'y emmène.
- **Spotlight** (`Super + Espace`) : **lance tes apps** (la meilleure en grand, Entrée pour l'ouvrir), actions du système (verrouiller, veille, éteindre, paramètres, Horloge…), **fichiers** de ton dossier perso, calculs et conversions, puis suggestions Google, fiche Wikipédia et résultats web.
- **Calculatrice** (`Super + O`) : le résultat s'affiche pendant que tu tapes (`12,5 × 4 + 20 %`), et Entrée le copie.
- **Horloge** (`Super + Maj + O`) : minuteur avec anneau, chronomètre à cadran et tours, pomodoro automatique et alarmes. Tout tourne dans la Dynamic Island : le minuteur continue et l'alarme sonne même app fermée.
- **Aperçu rapide** : dans Nautilus, sélectionne un fichier et appuie sur **Espace**.
- **Indicateur de bureau** en verre pendant les changements de bureau.
- **Animations façon macOS** : ressorts courts et nets, léger rebond, glissade visible entre les bureaux. Consommation identique au Caelestia d'origine.

### ⌨️ Outils intégrés
| Outil | Raccourci |
|---|---|
| **Tous les raccourcis** (fenêtre de recherche) | `Super + H` |
| Presse-papiers (texte, images, liens, favoris) | `Super + V` |
| Emojis et symboles | `Super + .` |
| Choix de l'affichage (écran externe, dupliquer…) | `Super + P` |
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

Appuie sur **`Super + H`** : une fenêtre en verre liste **tous** les raccourcis du système, avec une recherche.

### Essentiels
| Raccourci | Action |
|---|---|
| `Super` | Lanceur d'applications |
| `Super + Espace` | Recherche façon Spotlight |
| `Super + O` | Calculatrice |
| `Super + Maj + O` | Horloge (minuteur, chrono, pomodoro, alarmes) |
| `Super + Tab` | Mission Control |
| `Super + H` | Tous les raccourcis |
| `Super + I` | Paramètres de Caelestia |
| `Super + A` | Centre de contrôle |
| `Super + Maj + N` | Notes rapides (synchronisées avec AetherNotes) |
| `Super + Maj + T` | Tâches synchronisées avec AuraTask |
| `Super + Retour arrière` | Éteindre / redémarrer / verrouiller |
| `Super + Maj + R` | Recharger Hyprland et le shell |

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

| Tu veux… | Où |
|---|---|
| Retirer le verre des panneaux (les notifications restent en verre) | `~/.config/quickshell/caelestia/services/Glass.qml` → `panels: false` |
| Revenir aux animations d'origine de Caelestia | `~/.config/quickshell/caelestia/services/Motion.qml` → `enabled: false` |
| Changer d'applis par défaut, de raccourcis, d'espacement | `~/.config/caelestia/hypr-vars.lua` |
| Ajouter tes propres réglages Hyprland | à la fin de `~/.config/caelestia/hypr-user.lua` |
| Changer le style de tous les outils d'un coup | `~/.config/caelestia/tools-base.css` |
| Rendre kitty plus ou moins transparent | `~/.config/kitty/liquid-glass.conf` → `background_opacity` |
| Changer ta photo (écran de connexion, tableau de bord) | remplace l'image `~/.face` |

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

**Ma version de caelestia-shell est différente.**
Liquid Glass remplace le shell de Caelestia par une version modifiée, prévue pour `caelestia-shell` 2.3. Avec une autre version, l'installateur te prévient avant de continuer. En cas de problème, `./uninstall` remet tout comme avant.

**Le verre de Nautilus a disparu après un changement de fond d'écran.**
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
