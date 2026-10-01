-- ============================================================================
--  Caelestia Liquid Glass — réglages Hyprland
--  https://github.com/Abdoul273/caelestia-liquid-glass
--
--  Ce fichier est chargé par la config Hyprland de Caelestia. On n'y modifie
--  jamais ~/.config/hypr/ directement (sinon les mises à jour de Caelestia
--  entrent en conflit) : tout passe par ici et par hypr-vars.lua.
-- ============================================================================

local home = os.getenv("HOME") or ""
local bin = home .. "/.local/bin/"
local started = os.time()

-- Liseré de verre : lumineux en haut à gauche, reflet en bas à droite
local glass_border = "rgba(ffffff70) rgba(ffffff0d) rgba(ffffff0d) rgba(ffffff30) 135deg "
    .. "rgba(ffffff26) rgba(ffffff05) rgba(ffffff14) 135deg"

-- Remplace un raccourci existant au lieu de l'ajouter en double
local function rebind(keys, action, opts)
    pcall(hl.unbind, keys)
    hl.bind(keys, action, opts)
end

-- Dossiers XDG de l'utilisateur (Images, Vidéos… dans sa langue)
local function xdg_dir(kind, fallback)
    local handle = io.popen("xdg-user-dir " .. kind .. " 2>/dev/null")
    local dir = handle and handle:read("*l") or nil
    if handle then handle:close() end
    if not dir or dir == "" or dir == home then
        return home .. "/" .. fallback
    end
    return dir
end


-- ---------------------------------------------------------------------------
--  Dossiers des captures et enregistrements
-- ---------------------------------------------------------------------------
local pictures = xdg_dir("PICTURES", "Pictures")
local videos = xdg_dir("VIDEOS", "Videos")
hl.env("XDG_PICTURES_DIR", pictures)
hl.env("CAELESTIA_SCREENSHOTS_DIR", pictures .. "/Captures")
hl.env("XDG_VIDEOS_DIR", videos)
hl.env("CAELESTIA_RECORDINGS_DIR", videos .. "/Enregistrements écran")


-- ---------------------------------------------------------------------------
--  Écrans : dernière disposition choisie avec Super + P
-- ---------------------------------------------------------------------------
local layout = home .. "/.local/state/caelestia-display-pro/layout.lua"
local file = io.open(layout, "r")
if file then
    file:close()
    pcall(dofile, layout)
end

hl.on("hyprland.start", function()
    hl.exec_cmd("sleep 2 && " .. bin .. "caelestia-display-pro --apply-saved")
end)

-- Pas de notification pour l'écran intégré au démarrage, seulement pour un branchement
hl.on("monitor.added", function(...)
    if os.time() - started < 8 then
        return
    end
    hl.exec_cmd("notify-send -u low -a Caelestia -i video-display "
        .. "'Écran détecté' 'Super + P pour choisir comment l’afficher'")
end)


-- ---------------------------------------------------------------------------
--  Liquid glass : fenêtres translucides, texte net, liseré de verre
-- ---------------------------------------------------------------------------
hl.config({
    decoration = {
        blur = {
            vibrancy = 0.18,
            noise    = 0.012,
        },
    },
})

-- Texte toujours net : c'est l'application qui gère la transparence de son fond
local glass_apps = {
    "kitty",
    "org.gnome.Nautilus",
    "caelestia-(clipboard|display|emoji)-pro|io.caelestia.(ClipboardPro|DisplayPro|EmojiPro)",
}
for _, class in ipairs(glass_apps) do
    hl.window_rule({
        match        = { class = class },
        opacity      = "1.0 override 1.0 override",
        border_size  = 2,
        border_color = glass_border,
    })
end

-- Fenêtres de Caelestia (paramètres, choix de fichier) : taguées « opaque » par
-- défaut, on les autorise à être translucides
hl.window_rule({
    match        = { class = "org.quickshell" },
    opaque       = false,
    opacity      = "1.0 override 1.0 override",
    border_size  = 2,
    border_color = glass_border,
})


-- ---------------------------------------------------------------------------
--  Outils : presse-papiers, emojis, projection, recherche, calculatrice, aide
-- ---------------------------------------------------------------------------
local function tool_window(class, size, extra)
    local rule = {
        match       = { class = class },
        float       = true,
        size        = size,
        center      = true,
        animation   = "popin 90%",
    }
    for k, v in pairs(extra or {}) do
        rule[k] = v
    end
    hl.window_rule(rule)
end

tool_window("caelestia-clipboard-pro|io.caelestia.ClipboardPro", "1120 700", { dim_around = true, stay_focused = true })
tool_window("caelestia-display-pro|io.caelestia.DisplayPro", "540 720", { dim_around = true, stay_focused = true })
tool_window("caelestia-emoji-pro|io.caelestia.EmojiPro", "760 620", { dim_around = true, stay_focused = true })
tool_window("io.caelestia.Shortcuts", "1120 760", {
    opacity = "1.0 override 1.0 override", border_size = 2, border_color = glass_border,
})

-- Recherche et calculatrice : en haut de l'écran, comme Spotlight
hl.window_rule({
    match        = { class = "io.caelestia.Spotlight" },
    float        = true,
    size         = "720 640",
    move         = "(monitor_w*0.5-360) (monitor_h*0.14)",
    opacity      = "1.0 override 1.0 override",
    border_size  = 2,
    border_color = glass_border,
    animation    = "popin 90%",
})
-- Horloge : minuteur, chrono, pomodoro, alarmes, reliée à la Dynamic Island
hl.window_rule({
    match        = { class = "io.caelestia.Clock" },
    float        = true,
    size         = "440 700",
    move         = "(monitor_w*0.5-220) (monitor_h*0.1)",
    opacity      = "1.0 override 1.0 override",
    border_size  = 2,
    border_color = glass_border,
    animation    = "popin 90%",
})
hl.window_rule({
    match        = { class = "io.caelestia.Calc" },
    float        = true,
    size         = "380 640",
    move         = "(monitor_w*0.5-190) (monitor_h*0.16)",
    opacity      = "1.0 override 1.0 override",
    border_size  = 2,
    border_color = glass_border,
    animation    = "popin 90%",
})

rebind("SUPER + V", hl.dsp.global("caelestia:clipboard")) -- Presse-papiers dans le verre du shell
rebind("SUPER + Period", hl.dsp.global("caelestia:emoji")) -- Emojis dans le verre du shell
rebind("SUPER + P", hl.dsp.global("caelestia:display")) -- Projection dans le verre du shell
rebind("SUPER + Space", hl.dsp.global("caelestia:spotlight")) -- Spotlight dans le verre du shell
rebind("SUPER + O", hl.dsp.global("caelestia:calculator")) -- Calculatrice dans le verre du shell
-- Terminal kitty déroulant (Super + `) : réglages dans ~/.config/kitty/quick-access-terminal.conf
hl.layer_rule({ match = { namespace = "kitty-quick-access" }, blur = true, ignore_alpha = 0, animation = "slide top" })
rebind("SUPER + grave", hl.dsp.exec_cmd("kitten quick-access-terminal"))

rebind("SUPER + SHIFT + O", hl.dsp.exec_cmd(bin .. "caelestia-clock"))
rebind("SUPER + H", hl.dsp.global("caelestia:keyhelp")) -- Raccourcis façon Spotlight dans le verre du shell


-- ---------------------------------------------------------------------------
--  Raccourcis du shell
-- ---------------------------------------------------------------------------
rebind("SUPER + I", hl.dsp.global("caelestia:nexus"))              -- paramètres
rebind("SUPER + A", hl.dsp.global("caelestia:dashboard"))          -- tableau de bord
rebind("SUPER + SHIFT + N", hl.dsp.global("caelestia:quicknotes"))  -- notes rapides
rebind("SUPER + SHIFT + T", hl.dsp.global("caelestia:quicktasks"))  -- tâches AuraTask
rebind("SUPER + SHIFT + Q", hl.dsp.exec_cmd(home .. "/.local/bin/caelestia-quit-app --active"))  -- quitter complètement l'app
rebind("SUPER + SHIFT + F", hl.dsp.exec_cmd("qs -c caelestia ipc call focus toggle"))  -- concentration
rebind("SUPER + Tab", hl.dsp.global("caelestia:missionControl"))   -- Mission Control
rebind("SUPER + SHIFT + R", hl.dsp.exec_cmd(
    "hyprctl reload && (caelestia shell -k; sleep 0.2; caelestia shell -d) & "
    .. "notify-send -a Caelestia 'Système actualisé' 'Hyprland et Caelestia ont été rechargés'"
), { release = true })
rebind("CTRL + SUPER + R", hl.dsp.exec_cmd("caelestia record -m"))
rebind("CTRL + ALT + M", hl.dsp.exec_cmd("caelestia record -s -m"))


-- ---------------------------------------------------------------------------
--  Mission Control et indicateur de bureau
-- ---------------------------------------------------------------------------
hl.layer_rule({ match = { namespace = "caelestia-missioncontrol" }, blur = true, ignore_alpha = 0, animation = "fade" })
hl.layer_rule({ match = { namespace = "caelestia-wshud" }, blur = true, ignore_alpha = 0.1, no_anim = true })


-- ---------------------------------------------------------------------------
--  Gestes du pavé tactile façon macOS
--    3 doigts ← → : bureaux (suit le doigt)      3 doigts ↑ : Mission Control
--    3 doigts ↓   : fermer Mission Control         4 doigts ← → : bureaux aussi
--    4 doigts ↑   : bureau spécial                 4 doigts ↓ : veille (Caelestia)
--  (les gestes d'origine sont déplacés via hypr-vars.lua)
-- ---------------------------------------------------------------------------
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({
    fingers   = 3,
    direction = "up",
    action    = function()
        hl.dispatch(hl.dsp.global("caelestia:missionControlOpen"))
    end,
})
hl.gesture({
    fingers   = 3,
    direction = "down",
    action    = function()
        hl.dispatch(hl.dsp.global("caelestia:missionControlClose"))
    end,
})
hl.gesture({ fingers = 4, direction = "up", action = "special", workspace_name = "special" })

-- Changement de bureau fluide : moins de distance, un geste vif suffit,
-- glissade visible du début à la fin (0,55 s) et espace entre les bureaux
hl.config({
    gestures = {
        workspace_swipe_distance           = 420,
        workspace_swipe_cancel_ratio       = 0.2,
        workspace_swipe_min_speed_to_force = 12,
        workspace_swipe_create_new         = false,
    },
    general = {
        gaps_workspaces = 60,
    },
})
hl.curve("macSpace", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5.5, bezier = "macSpace", style = "slide" })


-- ---------------------------------------------------------------------------
--  Tiling : les nouvelles fenêtres se placent à côté des autres
-- ---------------------------------------------------------------------------
-- Ignore les demandes « maximiser » des applis (kitty, Chrome…) : sinon chaque
-- nouvelle fenêtre s'ouvre maximisée et cache les autres au lieu de se placer à côté
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })


-- ---------------------------------------------------------------------------
--  Tes propres réglages : ajoute-les ci-dessous
-- ---------------------------------------------------------------------------
