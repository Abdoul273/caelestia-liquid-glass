# Contributing to Caelestia · Liquid Glass

Thank you for your interest in contributing! Both **English** and **French** are welcome in issues and pull requests.

## How You Can Help

- **Report bugs** with your Arch derivative, Hyprland version, `caelestia-shell` version, and relevant logs (`journalctl --user`, `qs -c caelestia`).
- **Localization (i18n)**: the QML shell supports automatic **English & French** via `config/quickshell/caelestia/services/I18n.qml` and `I18nEn.js` (validated by `tests/test_i18n.py`). PRs adding new languages or translating companion tools in `bin/` are very welcome.
- **Hardware & multi-monitor testing**: NVIDIA GPUs, HiDPI/fractional scaling, multiple displays, and different Bluetooth devices.
- **Companion scripts & tests**: improvements to `bin/*` utilities, installer portability, and unit tests in `tests/`.

## Repository Layout

- `install` / `uninstall` — interactive installer with automatic backup and restore.
- `config/quickshell/caelestia/` — modified Caelestia QML shell and custom GLSL shaders (`assets/shaders/`).
- `config/caelestia/` — public Hyprland Lua overrides (`hypr-user.lua`, `hypr-vars.lua`), CSS base, and templates.
- `config/gtk-glass/`, `config/kitty/`, `config/sddm/`, `config/plymouth/`, `config/systemd/` — theming and user services.
- `bin/` — standalone companion tools (Spotlight, Control Center helpers, AI agents watcher, Bluetooth switcher, etc.).
- `tools/` — maintainer scripts (`synchroniser`, `verifier-francais`, `generate-sounds.py`).
- `tests/` — offline pytest checks.

## Guidelines

1. **Keep personal data out of the repo**: never commit hardcoded `/home/<user>` paths, API keys, personal configs, or copyrighted wallpapers. Use `@HOME@` placeholders where `./install` performs substitution.
2. **Never modify `~/.config/hypr/`**: Hyprland customizations must go through `config/caelestia/hypr-user.lua` or `hypr-vars.lua`.
3. **Syncing local shell edits**: if you test edits live in `~/.config/quickshell/caelestia`, run:
   ```sh
   ./tools/synchroniser           # inspect differences
   ./tools/synchroniser --appliquer
   ```
4. **Recompiling shaders**: if you modify a `.frag` shader under `config/quickshell/caelestia/assets/shaders/`, recompile its `.qsb` binary with Qt6's `qsb`:
   ```sh
   /usr/lib/qt6/bin/qsb --qt6 -o shader.frag.qsb shader.frag
   ```

## Local Checks Before Opening a PR

Run these fast checks locally (also enforced by GitHub Actions CI):

```sh
# Shell syntax
bash -n install uninstall config/sddm/install-login-screen config/plymouth/install-boot-splash tools/synchroniser bin/bt-audio-autoswitch bin/caelestia-quit-app
sh -n bin/caelestia-animwall bin/caelestia-logout bin/swappy

# Python syntax & tests
python3 -m py_compile bin/caelestia-agents bin/caelestia-spotlight bin/caelestia-siri bin/caelestia-glass-gtk
pytest -q tests/
```

## License

By contributing to this repository, you agree that your contributions will be licensed under the **GNU General Public License v3.0** ([LICENSE](LICENSE)).
