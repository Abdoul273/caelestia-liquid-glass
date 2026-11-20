<div align="center">

# 🫧 Caelestia · Liquid Glass

**macOS-style Liquid Glass desktop for Hyprland, built on [Caelestia](https://github.com/caelestia-dots/caelestia).**

Custom Qt6 liquid-glass shaders, a 9-page Dynamic Island with live AI agent monitoring, macOS 27 Control Center, auto-hiding Dock, Mission Control, Spotlight, 3D Earbuds HUD, SDDM & Plymouth themes — installed in **one command**, with automatic backup and clean uninstall.

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=archlinux&logoColor=white)](https://archlinux.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-0.56+-58E1FF?style=flat)](https://hyprland.org)
[![Caelestia](https://img.shields.io/badge/caelestia--shell-2.3-e6c093?style=flat)](https://github.com/caelestia-dots/caelestia)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue?style=flat)](LICENSE)
[![CI](https://github.com/Abdoul273/caelestia-liquid-glass/actions/workflows/ci.yml/badge.svg)](https://github.com/Abdoul273/caelestia-liquid-glass/actions/workflows/ci.yml)

**🇬🇧 English** · [🇫🇷 Français](README.fr.md)

</div>

---

> [!TIP]
> **Automatic English & French UI:** The shell automatically follows your system locale (`fr_*` → French, everything else → English) and can be switched live anytime in **Settings (`Super + I`) → Language & region** (or `~/.config/caelestia/lang.json` / `CAELESTIA_LANG=en|fr`). Contributions for additional languages are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## ✨ Highlights

### 🫧 Liquid Glass Everywhere
- **Unified liquid-glass shell**: panels morph seamlessly out of the screen border into a single continuous piece of glass with a luminous rim and a cursor-tracking specular highlight.
- **Custom Qt6 GLSL shaders**: beveled refractive edges, subtle chromatic dispersion, specular sheen, and convex lens controls — paired with Hyprland's native blur for low idle overhead (~7% of a single core).
- **Adaptive glass & power awareness**: automatically tones down glass and Hyprland effects on battery; animated video/GIF wallpapers (`caelestia-animwall`) pause to a static frame when unplugged and resume on AC.
- **Glass apps & terminal**: themed **kitty** (pill tab bar, dropdown terminal, fuzzy history, hints, command palette), **Starship** Catppuccin Mocha pill prompt, and translucent **GTK4/GTK3** apps (Nautilus with Finder-like floating sidebar, Calculator, Text Editor, Thunar, file chooser portal) automatically synced to your wallpaper palette.
- **macOS-inspired SDDM login & Plymouth boot**: glass login screen synced with your current wallpaper and `~/.face`, macOS cursor ([apple_cursor](https://github.com/ful1e5/apple_cursor)), and optional minimal boot splash.

### 🏝️ 9-Page Dynamic Island
Merged into the top border with smooth spring physics and trackpad/scroll navigation:
- **Idle pill**: date, centered clock, macOS-style battery glyph, and live status indicators (mic/camera privacy dots, Bluetooth, Focus mode, file shelf).
- **Music & Cava liquid spectrum**: live audio visualizer, bass-reactive glow, full hover player, and synchronized lyrics (local `.lrc`, [LRCLIB](https://lrclib.net), or local players).
- **Hardware & system animations**: MagSafe-style plasma charging ring with real-time wattage telemetry, vector Wi-Fi radar beacon, AirPods-style Bluetooth connect animation, screenshot preview with quick actions, file transfer progress, and active call controls.
- **Notification Center (`Super + N`)**: collapsible stacks grouped by app, filters, and Do Not Disturb.
- **Live Performance HUD**: CPU + frequency, temperature + fan RPM, RAM, disk space, and live network throughput.
- **Clock & Shelf**: timers, stopwatch, Pomodoro, alarms, and drag-and-drop file shelf.
- **AI Coding Agents HUD (Claude Code & Codex)**: live spinning indicator showing active project & tool, click-to-focus agent terminal, completion alerts, and interactive **Allow / Deny** prompts for Claude Code permissions via `~/.claude/settings.json`:
  ```json
  "hooks": {
    "PermissionRequest": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "~/.local/bin/caelestia-agents hook", "timeout": 120 }]
    }]
  }
  ```

### 🪟 macOS-Style Desktop Workflows
- **Control Center (`Super + A`)**: slides out of the top-right corner in matching glass — Wi-Fi with inline passwords, Bluetooth, VPN, Focus modes, Night Light, Light/Dark toggle, media, brightness/audio routing, screen recorder (area/fullscreen, system audio/mic, island countdown), detailed battery monitor (watts, health, adaptive graph, top power-hungry apps), system tray, and session controls.
- **Auto-hiding Dock**: zero wasted tiling space; slides up on bottom-edge hover (or empty workspace), hover magnification, running indicators, drag-and-drop reordering, and right-click pin/quit.
- **Mission Control (`Super + Tab` or 3-finger swipe up)**: live window overview grid + workspace bar.
- **Spotlight (`Super + Space`)**: app launcher, system actions, local files, notes/tasks, inline math & unit conversion, and web search.
- **Live Calculator (`Super + O`)**: single-line glass calculator right under the island with instant copy and history.
- **3D Earbuds HUD (`Super + Shift + B`)**: AirPodsDesktop-style interactive 3D glass popup with inertia rotation, case animation, battery LEDs, and Bluetooth controls.
- **Optional Gemini AI Tools**: voice assistant (`Super + Shift + Space`), live dictation (`Super + Shift + D`), writing tools (`Super + Shift + W`), and instant translation (`Super + Alt + T`) using your own Gemini API key (`GEMINI_API_KEY` or per-tool config).

### ⌨️ Built-in Utilities
| Tool | Shortcut |
|---|---|
| **Searchable Shortcuts Palette** (Enter runs the action) | `Super + H` |
| Clipboard Manager (text, images, links, favorites) | `Super + V` |
| Emoji & Symbols Picker | `Super + .` |
| Display Projection (mirror, extend, wireless Miracast/Chromecast) | `Super + P` |
| Caelestia Settings | `Super + I` |

---

## 📋 Requirements

- **Arch Linux** or an Arch-based distro (EndeavourOS, CachyOS, Manjaro…)
- **Hyprland ≥ 0.56** (Lua configuration)
- **Caelestia installed and working** (`caelestia-shell` 2.3)

> [!IMPORTANT]
> Install **Caelestia** first and log into Hyprland once before running the Liquid Glass installer:
>
> ```sh
> paru -S caelestia-cli     # or: yay -S caelestia-cli
> caelestia install
> ```
>
> If Caelestia is not detected, `./install` will warn you and offer to install it.

---

## 🚀 Installation

```sh
git clone https://github.com/Abdoul273/caelestia-liquid-glass.git
cd caelestia-liquid-glass
./install
```

What `./install` does:
1. Checks your system (Arch, Hyprland version, Caelestia installation).
2. Installs required packages (prompts for `sudo` once).
3. **Backs up your existing configuration** to `~/.local/share/caelestia-liquid-glass/backups/` before changing anything.
4. Installs the Liquid Glass shell, Hyprland Lua overrides, companion tools, kitty, and GTK glass styling.
5. Enables user services (`bt-audio-autoswitch`, `caelestia-glass-gtk.path`).
6. Optionally downloads wallpapers (not bundled in this repo), installs the macOS cursor, and offers SDDM login & Plymouth boot themes.
7. Reloads your desktop immediately.

Useful flags:
```sh
./install --dry-run   # preview changes without modifying anything
./install --yes       # accept all prompts non-interactively
./install --no-deps   # skip package installation
```

> [!NOTE]
> The installer **never touches `~/.config/hypr/`**, following Caelestia's guidelines. All overrides live in `~/.config/caelestia/hypr-user.lua` and `hypr-vars.lua`, keeping upstream Caelestia updates conflict-free.

---

## ⌨️ Keybindings & Trackpad Gestures

Press **`Super + H`** anytime to search and trigger any shortcut.

| Shortcut | Action |
|---|---|
| `Super` | App launcher |
| `Super + Space` | Spotlight search |
| `Super + O` | Inline calculator |
| `Super + Tab` | Mission Control |
| `Super + A` | Control Center |
| `Super + N` | Notification Center (Dynamic Island) |
| `Super + I` | Caelestia Settings |
| `Super + H` | Searchable shortcuts list |
| `Super + Shift + O` | Clock (timer, stopwatch, Pomodoro, alarms) |
| `Super + Shift + B` | 3D Earbuds HUD |
| `Super + Shift + F` | Focus mode (DND / Work / Sleep) |
| `Super + Shift + N` / `T` | Quick Notes / Quick Tasks |
| `Super + Shift + Q` | Quit entire app (`Super + Q` closes window only) |
| `Super + Shift + R` | Reload Hyprland and shell |
| `Super + Backspace` | Power / lock menu |
| ``Super + ` `` | Dropdown kitty terminal |
| `Super + Shift + Space` / `D` / `W` | Optional AI Voice / Dictation / Writing tools |
| `Super + Alt + T` | Optional quick translation |

| Trackpad Gesture | Action |
|---|---|
| 3-finger swipe ← → | Switch workspaces |
| 3-finger swipe ↑ / ↓ | Open / close Mission Control |
| 4-finger swipe ← → | Switch workspaces |
| 4-finger swipe ↑ | Special workspace |

---

## 🎛️ Customization

- **macOS features**: Settings (`Super + I`) → **Façon macOS** (`~/.config/caelestia/island.json`) — toggle Dynamic Island, Control Center, Dock, lyrics, privacy dots, and more live.
- **Liquid Glass**: Settings (`Super + I`) → **Fond d'écran et style** → **Liquid glass** (`~/.config/caelestia/glass.json`):
  - **Shell style**: *Classic* (balanced blur & tint, default), *Full Glass* (iOS 26/27-style refraction), or *Off*;
  - **GTK glass**: *Nautilus* (default), *All* (including Open/Save file portal), or *Off* (`caelestia-glass-gtk nautilus|complet|off`);
  - **Glass density**: continuous slider applied to both shell and GTK apps.
- **Hyprland & tools**: edit `~/.config/caelestia/hypr-vars.lua`, `~/.config/caelestia/hypr-user.lua`, `~/.config/caelestia/tools-base.css`, or `~/.config/kitty/liquid-glass.conf`, then press `Super + Shift + R`.

---

## 🧹 Uninstall

```sh
./uninstall
```

Removes installed files and **restores your previous configuration** from `~/.local/share/caelestia-liquid-glass/backups/`. Installed system packages are left untouched.

To remove the optional Plymouth boot splash:
```sh
sudo config/plymouth/install-boot-splash --remove
```

---

## 🤝 Contributing

Contributions, bug reports, and feature ideas are welcome! See **[CONTRIBUTING.md](CONTRIBUTING.md)** to get started.

High-impact areas where help is especially appreciated:
- **Additional languages (i18n)**: English & French are built in (`services/I18n.qml`, `services/I18nEn.js`); PRs for more languages are welcome;
- **Testing on additional Arch setups** (multi-monitor, NVIDIA, different Hyprland/caelestia-shell versions);
- **Shader & performance refinements**.

---

## 🙏 Credits

- **[Caelestia](https://github.com/caelestia-dots)** by soramanew and contributors — the upstream shell and dotfiles (GPL-3.0).
- **Google Sans Flex** (SIL Open Font License), bundled with Caelestia.
- **[apple_cursor](https://github.com/ful1e5/apple_cursor)** by ful1e5 (GPL-3.0), downloaded during install.
- macOS wallpapers: © Apple — **not** included in this repository.

## 📄 License

Licensed under **[GPL-3.0](LICENSE)**, matching upstream Caelestia.
