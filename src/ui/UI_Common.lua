-- GuildLoot – UI_Common.lua
-- Gemeinsame UI-Konstanten und Helpers: BACKDROPS, COLORS, CreateBackdropFrame.
-- Muss VOR UI.lua geladen werden (TOC-Reihenfolge).

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.UI = GL.UI or {}
local UI = GL.UI

-- ============================================================
-- Backdrop-Definitionen (BackdropTemplate)
-- ============================================================

--- Benannte Backdrop-Configs für alle UI-Frames.
--- Verwendung: frame:SetBackdrop(UI.BACKDROPS.TOOLTIP)
---             oder UI.CreateBackdropFrame("TOOLTIP", name, parent)
UI.BACKDROPS = {
    --- Standard-Panel mit schmalem Tooltip-Rand (edgeSize 6).
    TOOLTIP = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left=2, right=2, top=2, bottom=2 },
    },
    --- Großes Fenster mit Dialog-Rand, Kachel-Hintergrund (edgeSize 32).
    DIALOG = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    },
    --- Kleines Popup mit Dialog-Rand (edgeSize 16).
    DIALOG_SM = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets   = { left=4, right=4, top=4, bottom=4 },
    },
    --- Dunkle Drop-Zone mit Tooltip-Rand (edgeSize 10).
    DARK = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left=3, right=3, top=3, bottom=3 },
    },
}

-- ============================================================
-- Farb-Konstanten (für SetColorTexture / SetTextColor)
-- ============================================================

--- Häufig verwendete RGBA-Farben als {r,g,b,a}-Tabellen.
UI.COLORS = {
    DIVIDER         = { 0.4,  0.4,  0.4,  1    },  -- Trennlinien
    BG_AWARDED      = { 0,    0.4,  0.05, 0.22 },  -- Awarded-Zeilen-Hintergrund
    HIGHLIGHT_HOVER = { 1,    0.8,  0,    0.15 },  -- Hover/Selection-Highlight
}

-- ============================================================
-- Helper
-- ============================================================

--- Erstellt ein Frame mit BackdropTemplate und setzt den benannten Backdrop.
--- @param backdropKey string  Schlüssel in UI.BACKDROPS
--- @param name        string|nil  Globaler Frame-Name (oder nil)
--- @param parent      Frame
--- @return Frame
function UI.CreateBackdropFrame(backdropKey, name, parent)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetBackdrop(UI.BACKDROPS[backdropKey])
    return f
end
