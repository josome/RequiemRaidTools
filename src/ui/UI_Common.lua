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
-- Fenster-Position
-- ============================================================

-- Alle frei verschiebbaren Fenster teilen sich diesen Code. Ausnahme ist bewusst
-- das Dock-Tab (src/ui/UI_DockTab.lua): es klebt am Bildschirmrand und merkt sich
-- nur seine Y-Position.
--
-- Zwei Regeln stecken hier drin, beide aus Bugs entstanden, die schon behoben und
-- danach wieder verlorengegangen sind:
--
--   Regel A — Verschoben wird immer über einen eigenen Mover-Streifen mit
--   OnMouseDown/OnMouseUp, nie per RegisterForDrag auf dem Fenster selbst.
--   RegisterForDrag und StartSizing auf demselben Frame blockieren sich gegenseitig
--   (Commit a843d6b). Der Streifen liegt über der Titelzeile und verschluckt die
--   Knöpfe darin — die müssen mit UI.RaiseAboveMover angehoben werden.
--
--   Regel B — Umankern heißt IMMER: Größe merken, ClearAllPoints, SetPoint TOPLEFT,
--   Größe zurücksetzen. Ein CENTER-Anker lässt das Fenster nach StopMovingOrSizing()
--   springen (b589c9d), und ClearAllPoints wirft die von StartSizing gesetzten Anker
--   weg, wodurch die Größe verlorengeht (7f8caaa). Deshalb steht das Umankern nur an
--   einer Stelle: UI.NormalizeFrameAnchor.
--
-- Der TOPLEFT-Anker löst nebenbei das Popup-Problem: ein Fenster, das per SetWidth
-- schmaler oder breiter wird, wächst damit nach rechts statt symmetrisch — die linke
-- obere Ecke bleibt stehen, wo der Benutzer sie hingezogen hat.

-- key → Frame, für UI.SaveAllFramePositions beim Ausloggen.
local movableFrames = {}
-- key → opts aus UI.RegisterMovableFrame (size, minW, minH)
local movableOpts = {}

--- Liefert GuildLootDB.settings.framePositions, legt die Tabelle bei Bedarf an.
local function PositionStore()
    local s = GuildLootDB and GuildLootDB.settings
    if not s then return nil end
    s.framePositions = s.framePositions or {}
    return s.framePositions
end

--- Hält gespeicherte Offsets innerhalb des Bildschirms.
---
--- Reine Rechenfunktion ohne Frame-Zugriff — damit unter busted testbar. Sie ist der
--- Grund, warum eine Position auch einen Auflösungs- oder UI-Scale-Wechsel übersteht:
--- ohne sie läge ein Fenster nach dem Wechsel auf einen kleineren Bildschirm außerhalb
--- und wäre nicht mehr greifbar.
---
--- @param x       number  TOPLEFT-Offset nach rechts (≥ 0)
--- @param y       number  TOPLEFT-Offset nach unten (≤ 0)
--- @param frameW  number
--- @param frameH  number
--- @param screenW number  UIParent-Breite
--- @param screenH number  UIParent-Höhe
--- @return number|nil x, number|nil y  geklemmte Offsets, nil bei fehlenden Eingaben
function UI.ClampFrameOffsets(x, y, frameW, frameH, screenW, screenH)
    if not (x and y and frameW and frameH and screenW and screenH) then return nil end
    local maxX =  math.max(0, screenW - frameW)
    local minY = -math.max(0, screenH - frameH)
    if     x < 0    then x = 0
    elseif x > maxX then x = maxX end
    if     y > 0    then y = 0
    elseif y < minY then y = minY end
    return x, y
end

--- Regel B: bringt frame auf genau einen Anker TOPLEFT → UIParent TOPLEFT.
---
--- Muss nach jedem StopMovingOrSizing() laufen. Die Skalierung wird mitgerechnet,
--- damit ein Fenster mit abweichendem Scale nicht bei jedem Speichern wegdriftet.
---
--- @param frame Frame
--- @return number|nil x, number|nil y  nil wenn frame noch nie gezeichnet wurde
function UI.NormalizeFrameAnchor(frame)
    if not frame or not frame.GetLeft then return nil end
    local left = frame:GetLeft()
    if not left then return nil end

    -- Größe VOR ClearAllPoints sichern: das Verwerfen der Anker, die StartSizing
    -- gesetzt hat, nimmt sonst die neue Größe mit (7f8caaa).
    local w, h  = frame:GetSize()
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = left            * ratio - UIParent:GetLeft()
    local y = frame:GetTop()  * ratio - UIParent:GetTop()

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    frame:SetSize(w, h)
    return x, y
end

--- Schreibt Position (und bei size=true die Größe) von frame in die SavedVariables.
--- Ankert dabei über UI.NormalizeFrameAnchor um.
--- @param frame Frame
--- @param key   string  Schlüssel unter settings.framePositions
function UI.SaveFramePosition(frame, key)
    if not (frame and key) then return end
    -- Ein verstecktes Fenster steht dort, wo sein Aufbau-Code es hingesetzt hat, nicht
    -- dort, wo der Benutzer es zuletzt hatte. Es zu sichern hieße, die gespeicherte
    -- Position durch den Default zu ersetzen — beim angedockten Hauptfenster wäre das
    -- bei jedem Ausloggen der Fall.
    -- Ein verstecktes Fenster steht dort, wo sein Aufbau-Code es hingesetzt hat, nicht
    -- dort, wo der Benutzer es zuletzt hatte. Es zu sichern hieße, die gespeicherte
    -- Position durch den Default zu ersetzen — beim angedockten Hauptfenster wäre das
    -- bei jedem Ausloggen der Fall.
    if frame.IsShown and not frame:IsShown() then return end
    local x, y = UI.NormalizeFrameAnchor(frame)
    if not x then return end
    local store = PositionStore()
    if not store then return end

    local entry = { x = x, y = y }
    local opts  = movableOpts[key]
    if opts and opts.size then
        entry.w, entry.h = frame:GetSize()
    end
    store[key] = entry
end

--- Stellt die gespeicherte Position (und ggf. Größe) von frame wieder her.
---
--- Ist nichts gespeichert, wird der vom Aufrufer gesetzte Default-Anker einmalig in
--- die TOPLEFT-Form überführt — damit ist auch das allererste Öffnen gegen spätere
--- Größenwechsel immun.
--- @param frame Frame
--- @param key   string
function UI.RestoreFramePosition(frame, key)
    if not (frame and key) then return end
    local store = PositionStore()
    local pos   = store and store[key]
    if not pos then
        UI.NormalizeFrameAnchor(frame)
        return
    end

    local opts = movableOpts[key]
    if opts and opts.size and pos.w and pos.h then
        frame:SetSize(math.max(pos.w, opts.minW or 1), math.max(pos.h, opts.minH or 1))
    end

    local w, h = frame:GetSize()
    local x, y = UI.ClampFrameOffsets(pos.x, pos.y, w, h, UIParent:GetWidth(), UIParent:GetHeight())
    if not x then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    frame:SetSize(w, h)
end

--- Macht frame verschiebbar und lässt es seine Position merken.
---
--- Baut den Mover-Streifen nach Regel A selbst und gibt ihn zurück; die Knöpfe der
--- Titelzeile liegen danach unter ihm und müssen per UI.RaiseAboveMover angehoben
--- werden, sonst nehmen sie keine Klicks mehr an.
---
--- @param frame Frame
--- @param key   string      Schlüssel unter settings.framePositions
--- @param opts  table|nil   { size=bool, minW=number, minH=number, moverHeight=number }
--- @return Frame  der Mover-Streifen
function UI.RegisterMovableFrame(frame, key, opts)
    if not (frame and key) then return nil end
    opts = opts or {}
    movableFrames[key] = frame
    movableOpts[key]   = opts

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    local mover = CreateFrame("Frame", nil, frame)
    mover:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    mover:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    mover:SetHeight(opts.moverHeight or 22)
    mover:SetFrameLevel(frame:GetFrameLevel() + 1)
    mover:EnableMouse(true)
    mover:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        frame:StartMoving()
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        frame:StopMovingOrSizing()
        UI.SaveFramePosition(frame, key)
    end)

    -- Nur wiederherstellen, nicht beim Verstecken sichern. CreateFrame liefert ein
    -- sichtbares Frame, das die Aufbau-Funktionen anschließend verstecken — ein
    -- OnHide-Hook liefe also mitten im Konstruktor, während das Fenster noch auf
    -- seinem Default-Anker steht, und überschriebe die gespeicherte Position mit dem
    -- Default. Gesichert wird stattdessen beim Loslassen des Streifens und beim
    -- Ausloggen; öfter ändert sich eine Position nicht.
    frame:HookScript("OnShow", function() UI.RestoreFramePosition(frame, key) end)

    return mover
end

--- Hebt Titelzeilen-Widgets über den Mover-Streifen, damit sie klickbar bleiben.
--- @param mover Frame  Rückgabewert von UI.RegisterMovableFrame
--- @param ...   Frame  beliebig viele Widgets in der Titelzeile
function UI.RaiseAboveMover(mover, ...)
    if not mover then return end
    local level = mover:GetFrameLevel() + 1
    for i = 1, select("#", ...) do
        local widget = select(i, ...)
        if widget and widget.SetFrameLevel then widget:SetFrameLevel(level) end
    end
end

--- Sichert die Position aller registrierten Fenster. Aufruf bei PLAYER_LOGOUT.
function UI.SaveAllFramePositions()
    for key, frame in pairs(movableFrames) do
        UI.SaveFramePosition(frame, key)
    end
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
