# Changelog

All notable changes to **Caelestia · Liquid Glass** are documented in this file.

## [1.1.0] - 2026-11-20

### Added
- **Automatic Bilingual UI (English & French)**: new `services/I18n.qml` singleton and `services/I18nEn.js` catalog (~1,238 strings) covering the entire QML shell (Dynamic Island, Control Center, Dock, Mission Control, Spotlight, Lock Screen, Nexus Settings, Weather, and system panels).
- **Live Language Switcher**: switch between *Automatic (system)*, *Français*, and *English* on the fly in **Settings (`Super + I`) → Language & region** (`~/.config/caelestia/lang.json` or `CAELESTIA_LANG=en|fr`).
- **Locale-aware Dates**: replaced hardcoded `fr_FR` dates on the Lock Screen and Dynamic Island with `I18n.locale`.
- **i18n Test Suite**: added `tests/test_i18n.py` enforced by GitHub Actions CI to verify complete FR → EN coverage, placeholder consistency, and clean imports.

## [1.0.0] - 2026-11-20

First tagged public release of Caelestia · Liquid Glass for Hyprland ≥ 0.56 and `caelestia-shell` 2.3.

### Highlights
- **Liquid Glass Shell & Shaders**: custom Qt6 GLSL shaders (`glassblob`, `liquidios`, `glasscontrol`), continuous glass border morphing, specular cursor highlight, and adaptive density settings (`glass.json`).
- **9-Page Dynamic Island**: idle status pill, Cava liquid audio visualizer with bass halo and synchronized lyrics, MagSafe plasma charging animation with wattage telemetry, vector Wi-Fi radar, collapsible notification stacks, live performance HUD, clock/timer/Pomodoro/alarms, file shelf, and live AI Coding Agents HUD with Claude Code permission prompts.
- **macOS 27 Control Center & Auto-Hiding Dock**: full Control Center (`Super + A`) with Wi-Fi, Bluetooth, VPN, Focus modes, Night Light, screen recorder, detailed battery analytics, and drag-and-drop auto-hiding Dock.
- **Desktop Workflows**: Mission Control (`Super + Tab` / 3-finger swipe), Spotlight (`Super + Space`), inline calculator (`Super + O`), searchable shortcuts palette (`Super + H`), 3D Earbuds HUD (`Super + Shift + B`), wireless Miracast/Chromecast projection (`Super + P`), and optional Gemini voice/dictation/writing/translation tools.
- **System Theming & Power**: GTK4/GTK3 glass (including file chooser portal), kitty glass & pill tab bar, Starship prompt, SDDM login theme, optional Plymouth boot splash, animated wallpapers with battery auto-pause, and automatic low-power glass scaling when unplugged.
- **Safe Installer & CI**: one-command `./install` with automatic backups, clean `./uninstall`, and GitHub Actions CI checks.
