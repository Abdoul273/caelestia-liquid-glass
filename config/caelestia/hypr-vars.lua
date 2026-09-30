-- ============================================================================
--  Caelestia Liquid Glass — variables Hyprland
--  Référence de toutes les variables : ~/.config/hypr/variables.lua
-- ============================================================================
return {
    -- Applications par défaut
    terminal     = "kitty",
    fileExplorer = "nautilus",
    -- browser   = "firefox",   -- décommente et mets ton navigateur
    -- editor    = "code",      -- décommente et mets ton éditeur

    -- Raccourcis
    kbSession   = "SUPER + Backspace",   -- menu éteindre / redémarrer / verrouiller
    kbPinWindow = "SUPER + SHIFT + P",   -- Super + P ouvre maintenant le choix d'affichage

    -- Espace entre les fenêtres et les bords de l'écran
    windowGapsOut       = 8,
    singleWindowGapsOut = 12,

    -- Gestes façon macOS : 3 doigts pour les bureaux et Mission Control.
    -- Les gestes d'origine du bureau spécial passent sur 5 doigts ; ils sont
    -- remplacés par 4 doigts dans hypr-user.lua.
    workspaceSwipeFingers = 3,
    gestureFingers        = 5,

    -- Curseur façon macOS (apple_cursor)
    cursorTheme = "macOS",
    cursorSize  = 24,
}
