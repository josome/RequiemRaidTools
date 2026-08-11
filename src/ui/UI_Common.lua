-- GuildLoot – UI_Common.lua
-- Gemeinsame UI-Konstanten und Helpers: BACKDROPS, COLORS, CreateBackdropFrame.
-- Muss VOR UI.lua geladen werden (TOC-Reihenfolge).

GuildLoot = GuildLoot or {}
local GL = GuildLoot
GL.UI = GL.UI or {}
local UI = GL.UI

-- ============================================================
-- Tab-Registry
-- ============================================================

--- Benannte Tab-IDs. Split-Dateien lesen über UI.TAB_LOOT etc.
--- (Backward-compat-Aliases werden in UI.lua gesetzt.)
UI.TABS = { LOOT=1, LOG=2, RAID=3, ROLL=4, PLAYER=5 }

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

-- ============================================================
-- Dropdowns
-- ============================================================

--- Erzeugt ein Dropdown auf Basis von Blizzards Menu-System.
---
--- Bewusst NICHT UIDropDownMenuTemplate: dessen UIDropDownMenu_Initialize schreibt
--- auf den globalen UIDROPDOWNMENU_MENU_LEVEL und stempelt ihn mit dem Addon-Taint.
--- Der Taint wandert von dort in PlayerChoiceFrame und blockiert am Ende ClearTarget()
--- bei jedem ESC-Druck — nachgewiesen im taint.log, siehe CHANGELOG zu 1.0.4.2-beta.
---
--- @param parent    Frame
--- @param width     number
--- @param generator fun(rootDescription)  baut die Menüeinträge auf
--- @return Frame    DropdownButton (Text via :OverrideText(), Menü via :GenerateMenu())
function UI.CreateDropdown(parent, width, generator)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    dd:SetupMenu(function(_, rootDescription) generator(rootDescription) end)
    return dd
end

--- Dropdown für eine feste Werteliste mit Einfachauswahl.
--- Setzt die Beschriftung selbst — beim Aufbau und nach jeder Auswahl.
--- @param parent   Frame
--- @param width    number
--- @param entries  table  Liste aus { value=..., label=... }
--- @param getValue fun():any        liefert den aktuell gespeicherten Wert
--- @param onSelect fun(value:any)   speichert den gewählten Wert
--- @return Frame
function UI.CreateOptionDropdown(parent, width, entries, getValue, onSelect)
    local dd
    local function labelFor(value)
        for _, e in ipairs(entries) do
            if e.value == value then return e.label end
        end
        return nil
    end

    dd = UI.CreateDropdown(parent, width, function(root)
        for _, e in ipairs(entries) do
            root:CreateRadio(e.label,
                function() return getValue() == e.value end,
                function()
                    onSelect(e.value)
                    dd:OverrideText(e.label)
                end)
        end
    end)

    dd:OverrideText(labelFor(getValue()) or "")
    return dd
end

-- ============================================================
-- Frame-Pool
-- ============================================================

--- Erstellt einen Frame-Pool für Listen-Rows. WoW-Frames werden nie
--- garbage-collected — Refreshes müssen Rows wiederverwenden statt
--- neu zu erzeugen. Muster pro Refresh:
---   pool:ReleaseAll()
---   für jede Zeile: local row = pool:Acquire(); <populate>
---
--- Die Factory ist Frame-API-agnostisch: sie ruft selbst nie Hide/
--- ClearAllPoints — alles Frame-Berührende gehört in createFn/resetFn.
--- @param createFn fun(pool):Frame  Erzeugt eine neue Row (nur wenn Free-List leer)
--- @param resetFn  fun(pool, frame) Setzt eine Row zurück (Hide, ClearAllPoints, Scripts nillen)
function UI.CreateFramePool(createFn, resetFn)
    local pool = { _free = {}, _active = {} }

    function pool:Acquire()
        local frame = table.remove(self._free)
        if not frame then
            frame = createFn(self)
        end
        table.insert(self._active, frame)
        return frame
    end

    function pool:ReleaseAll()
        for i = #self._active, 1, -1 do
            local frame = self._active[i]
            self._active[i] = nil
            resetFn(self, frame)
            table.insert(self._free, frame)
        end
    end

    function pool:GetNumActive()
        return #self._active
    end

    return pool
end

-- ============================================================
-- Umbenennen-Dialog
-- ============================================================

-- Ein einziger StaticPopup-Eintrag für alle Umbenennungen. Ohne das schreibt jeder Aufrufer
-- seinen eigenen Dialog und dupliziert die Logik dabei zweimal — einmal in OnAccept und
-- nochmal in EditBoxOnEnterPressed, weil WoW beide getrennt aufruft.
--
-- ACHTUNG: Hier NIE `StaticPopupDialogs = StaticPopupDialogs or {}` schreiben. Das setzt die
-- globale Variable und stempelt sie mit unserem Addon-Taint; Blizzard_PlayerChoice liest sie
-- beim Nachladen, vererbt den Taint an PlayerChoiceFrame und ab da scheitert jedes ESC an
-- ClearTarget(). Einzelne Schlüssel zu setzen ist dagegen unbedenklich. Blizzard definiert
-- die Tabelle ohnehin immer — die Absicherung war wirkungslos.
local RENAME_DIALOG = "REQRT_RENAME"
-- Was gerade umbenannt wird; von UI.ShowRenameDialog vor dem Öffnen gesetzt.
local renameState = nil

local function ApplyRename(text)
    local state = renameState
    if not state then return end
    -- Trimmen gehört hierher, nicht in jeden Aufrufer
    local name = tostring(text or ""):match("^%s*(.-)%s*$")
    if name == "" then return end
    state.apply(name)
end

StaticPopupDialogs[RENAME_DIALOG] = {
    text       = "%s",
    button1    = "OK",
    button2    = "Abbrechen",
    hasEditBox = true,
    maxLetters = 48,
    OnShow     = function(self)
        self.EditBox:SetWidth(260)
        self.EditBox:SetText((renameState and renameState.current) or "")
        self.EditBox:HighlightText()
    end,
    OnAccept   = function(self) ApplyRename(self.EditBox:GetText()) end,
    EditBoxOnEnterPressed = function(self)
        ApplyRename(self:GetText())
        StaticPopup_Hide(RENAME_DIALOG)
    end,
    OnHide     = function() renameState = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

--- Öffnet den Umbenennen-Dialog.
--- @param title   string    Überschrift, z. B. "Session umbenennen:"
--- @param current string    aktueller Name, vorbelegt und markiert
--- @param apply   function  bekommt den getrimmten, nicht-leeren Namen
function UI.ShowRenameDialog(title, current, apply)
    if type(apply) ~= "function" then return end
    renameState = { current = current or "", apply = apply }
    StaticPopup_Show(RENAME_DIALOG, title or "Umbenennen:")
end

-- ============================================================
-- Größenänderung
-- ============================================================

--- Ruft fn im nächsten Frame auf, wenn frame seine Größe ändert oder eingeblendet wird.
---
--- Panels, deren Layout von der Fensterbreite abhängt, rechnen ihre Aufteilung erst beim
--- Zeichnen aus. Ohne diesen Haken bliebe die Anzeige beim Aufziehen des Fensters stehen,
--- bis irgendetwas anderes ein Neuzeichnen auslöst.
---
--- Zwei Feinheiten, die den Helper rechtfertigen:
---   * OnSizeChanged feuert während des Ziehens in JEDEM Frame — die Aufrufe werden auf
---     genau einen je Frame zusammengefasst.
---   * OnShow gehört dazu, weil ein ausgeblendetes Panel beim Vergrößern kein
---     OnSizeChanged bekommt; sein Layout wäre beim Einblenden sonst veraltet.
---
--- @param frame Frame     beobachteter Frame
--- @param fn    function  wird höchstens einmal je Frame gerufen
--- @return function       der Auslöser selbst, für manuelles Anstoßen
function UI.RefreshOnResize(frame, fn)
    if not (frame and fn) then return end
    local pending = false
    local function Schedule()
        if pending then return end
        pending = true
        C_Timer.After(0, function()
            pending = false
            fn()
        end)
    end
    frame:HookScript("OnSizeChanged", Schedule)
    frame:HookScript("OnShow",        Schedule)
    return Schedule
end
