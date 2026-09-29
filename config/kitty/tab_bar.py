# Barre d'onglets kitty : pilules arrondies avec icône du programme,
# et à droite : disposition, batterie, heure.
import os
from datetime import datetime
from glob import glob

from kitty.boss import get_boss
from kitty.fast_data_types import Screen, add_timer, get_options, wcswidth
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb, draw_title
from kitty.utils import color_as_int

LEFT, RIGHT = '', ''

ICONS = {
    'nvim': '', 'vim': '', 'vi': '', 'hx': '󰅴', 'nano': '',
    'git': '', 'lazygit': '', 'gh': '',
    'python': '', 'python3': '', 'ipython': '',
    'node': '', 'npm': '', 'pnpm': '', 'bun': '', 'deno': '',
    'cargo': '', 'rustc': '', 'go': '', 'flutter': '', 'dart': '',
    'ssh': '󰣀', 'kitten': '󰣀', 'docker': '', 'lazydocker': '',
    'btop': '', 'htop': '', 'top': '',
    'man': '', 'less': '', 'bat': '', 'yazi': '', 'ranger': '',
    'claude': '󰚩', 'make': '', 'paru': '', 'yay': '', 'pacman': '',
    'sudo': '', 'mpv': '', 'fastfetch': '',
}
SHELLS = {'fish', 'bash', 'zsh', 'sh'}

LAYOUT_ICONS = {
    'splits': '󰕰', 'tall': '', 'fat': '', 'grid': '󰕰',
    'horizontal': '󰕭', 'vertical': '󰕮', 'stack': '󰊓',
}

_timer_id = None


def _redraw(_timer_id: int) -> None:
    for tm in get_boss().all_tab_managers:
        tm.mark_tab_bar_dirty()


def _icon(tab: TabBarData) -> str:
    title = (tab.title or '').strip()
    first = title.split()[0] if title else ''
    prog = os.path.basename(first).lower()
    if prog in ICONS:
        return ICONS[prog]
    if prog in SHELLS or title.startswith(('~', '/')):
        return ''
    for name, icon in ICONS.items():
        if title.lower().startswith(name):
            return icon
    return ''


def _battery() -> str:
    for bat in sorted(glob('/sys/class/power_supply/BAT*')):
        try:
            with open(f'{bat}/capacity') as f:
                cap = int(f.read().strip())
            with open(f'{bat}/status') as f:
                status = f.read().strip()
        except (OSError, ValueError):
            continue
        if status == 'Charging':
            icon = '󰂄'
        else:
            icon = '󰁺󰁻󰁼󰁽󰁾󰁿󰂀󰂁󰂂󰁹'[min(cap // 10, 9)]
        return f'{icon} {cap}%'
    return ''


def _pill(screen: Screen, text: str, fg: int, bg: int, outer: int, bold: bool = False) -> None:
    screen.cursor.bold = False
    screen.cursor.fg, screen.cursor.bg = bg, outer
    screen.draw(LEFT)
    screen.cursor.fg, screen.cursor.bg = fg, bg
    screen.cursor.bold = bold
    screen.draw(text)
    screen.cursor.bold = False
    screen.cursor.fg, screen.cursor.bg = bg, outer
    screen.draw(RIGHT)


def _draw_status(draw_data: DrawData, screen: Screen, tab: TabBarData) -> None:
    opts = get_options()
    outer = as_rgb(color_as_int(draw_data.default_bg))
    dark = as_rgb(color_as_int(opts.background))
    muted = as_rgb(color_as_int(draw_data.inactive_bg))
    muted_fg = as_rgb(color_as_int(draw_data.inactive_fg))

    pills = []
    if tab.active_session_name:
        pills.append((f' 󰆍 {tab.active_session_name} ', muted_fg, muted))
    layout = tab.layout_name or ''
    pills.append((f' {LAYOUT_ICONS.get(layout, "󰕰")} {layout} ', muted_fg, muted))
    bat = _battery()
    if bat:
        pills.append((f' {bat} ', muted_fg, muted))
    pills.append((f' 󰥔 {datetime.now():%H:%M} ', dark, as_rgb(color_as_int(opts.color4))))

    width = sum(wcswidth(t) + 3 for t, _, _ in pills)
    if screen.cursor.x + width + 2 > screen.columns:
        return
    screen.cursor.bg = outer
    screen.draw(' ' * (screen.columns - screen.cursor.x - width))
    for text, fg, bg in pills:
        _pill(screen, text, fg, bg, outer, bold=bg != muted)
        screen.cursor.bg = outer
        screen.draw(' ')


def draw_tab(
    draw_data: DrawData, screen: Screen, tab: TabBarData,
    before: int, max_title_length: int, index: int, is_last: bool,
    extra_data: ExtraData,
) -> int:
    global _timer_id
    if _timer_id is None:
        _timer_id = add_timer(_redraw, 15.0, True)

    outer = as_rgb(color_as_int(draw_data.default_bg))
    tab_bg = as_rgb(draw_data.tab_bg(tab))
    tab_fg = as_rgb(draw_data.tab_fg(tab))

    if screen.cursor.x == 0:
        screen.cursor.bg = outer
        screen.draw(' ')

    screen.cursor.fg, screen.cursor.bg = tab_bg, outer
    screen.draw(LEFT)
    screen.cursor.fg, screen.cursor.bg = tab_fg, tab_bg
    screen.draw(f'{_icon(tab)} ')
    draw_title(draw_data, screen, tab, index, max_title_length)
    if tab.num_windows > 1:
        screen.draw(f' ·{tab.num_windows}')
    if tab.num_of_windows_with_progress:
        pct = tab.total_progress // tab.num_of_windows_with_progress
        screen.draw(f' 󰔟 {pct}%')
    screen.cursor.bold = False
    screen.cursor.fg, screen.cursor.bg = tab_bg, outer
    screen.draw(RIGHT)
    screen.draw(' ')
    end = screen.cursor.x

    if is_last:
        _draw_status(draw_data, screen, tab if tab.is_active else _active(tab))
    return end


def _active(fallback: TabBarData) -> TabBarData:
    # Le statut à droite montre la disposition de l'onglet actif
    tm = get_boss().active_tab_manager
    if tm is not None and tm.active_tab is not None:
        t = tm.active_tab
        return fallback._replace(layout_name=t.current_layout.name)
    return fallback
