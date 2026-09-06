-- RequiemRaidTools — src/tests/Lint_Test.lua
-- Statische Quellcode-Prüfung gegen die zwei Muster, die nachweislich Taint erzeugt haben.
--
-- Anders als die übrigen Suites testet diese kein Verhalten, sondern liest die
-- ausgelieferten Quelldateien vom Dateisystem. Läuft deshalb nur unter busted
-- (io.* ist in WoW nicht verfügbar) und überspringt sich sonst still.
--
-- Hintergrund: Zwei Taint-Bugs in Folge, beide mit derselben Wirkung — ein Blizzard-Global
-- trägt unseren Addon-Stempel, Blizzard_PlayerChoice liest es beim Nachladen, und ab da
-- scheitert jedes ESC an ClearTarget():
--   1. UIDropDownMenu_Initialize() schreibt UIDROPDOWNMENU_MENU_LEVEL
--   2. `StaticPopupDialogs = StaticPopupDialogs or {}` schreibt das Global selbst
-- Beide wären hier aufgefallen.

if not WoWUnit then return end
-- Dateizugriff gibt es nur im busted-Lauf, nicht im Spiel.
if not (io and io.open) then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Lint")

    local IsTrue   = WoWUnit.IsTrue
    local AreEqual = WoWUnit.AreEqual

    -- Globals, die das Addon setzen DARF.
    -- GuildLoot: eigener Namespace. SLASH_*: Blizzard-Konvention zum Registrieren von
    -- Slash-Commands, ohne Alternative — im taint.log tun BugSack und !BugGrabber dasselbe,
    -- folgenlos, weil der Chat-Parser nichts Geschütztes aufruft.
    local ALLOWED_GLOBALS = {
        GuildLoot = true,
        SLASH_REQUIEMRAIDTOOLS1 = true,
        SLASH_REQUIEMRAIDTOOLS2 = true,
    }

    --- Liest eine Datei zeilenweise. Gibt nil zurück wenn sie nicht existiert.
    local function ReadLines(path)
        local fh = io.open(path, "r")
        if not fh then return nil end
        local lines = {}
        for line in fh:lines() do lines[#lines + 1] = line end
        fh:close()
        return lines
    end

    --- Die ausgelieferten Lua-Dateien — aus der TOC gelesen, nicht hartkodiert.
    --- Damit prüft der Wächter automatisch jede Datei, die jemand neu aufnimmt, und
    --- ignoriert alles, was nicht ins Release geht (z.B. UI_PlayerTab.lua).
    local function ShippedFiles()
        local lines = ReadLines("RequiemRaidTools.toc")
        if not lines then return nil end
        local files = {}
        for _, line in ipairs(lines) do
            local path = line:match("^%s*([%w_/%.%-]+%.lua)%s*$")
            if path then files[#files + 1] = path end
        end
        return files
    end

    --- Sammelt Regelverstöße über alle ausgelieferten Dateien.
    --- @param check   fun(line:string):boolean  true = Verstoß
    --- @param exempt  table|nil  Pfade, die die Regel bewusst verletzen dürfen
    --- @return table Liste aus "pfad:zeile: inhalt"
    local function Scan(check, exempt)
        local hits = {}
        local files = ShippedFiles() or {}
        for _, path in ipairs(files) do
            local lines = (not (exempt and exempt[path])) and ReadLines(path) or nil
            if lines then
                for n, line in ipairs(lines) do
                    -- Kommentare sind nie ein Verstoß
                    if not line:match("^%s*%-%-") and check(line) then
                        hits[#hits + 1] = path .. ":" .. n .. ": " .. line:match("^%s*(.-)%s*$")
                    end
                end
            end
        end
        return hits
    end

    -- Sicherung der Sicherung: findet der Scanner keine Dateien, wäre jeder Test
    -- trivial grün und die Prüfung wertlos.
    function Tests:testTocFilesAreFound()
        local files = ShippedFiles()
        IsTrue(files ~= nil and #files > 10,
            "TOC nicht lesbar oder unerwartet kurz — Lint-Prüfungen wären wirkungslos")
    end

    --- Zuweisung an ein fremdes Global auf Spaltenposition 0.
    --- Bewusst nur ohne Einrückung: eingerückte `NAME = wert,`-Zeilen sind fast immer
    --- Tabellenfelder in einem Konstruktor und würden massenhaft Fehlalarme erzeugen.
    --- `StaticPopupDialogs["KEY"] = {}` matcht nicht (nach dem Namen folgt "["), was
    --- korrekt ist: Slot-Writes sind unbedenklich, nur die Zuweisung des Globals selbst
    --- ist das Problem.
    function Tests:testNoWritesToForeignGlobals()
        local hits = Scan(function(line)
            local name = line:match("^([A-Z][%w_]*)%s*=[^=]")
            return name ~= nil and not ALLOWED_GLOBALS[name]
        end)
        AreEqual(0, #hits,
            "Zuweisung an fremdes Global (taintet es für alle Leser): " .. table.concat(hits, " | "))
    end

    --- Blizzards altes Dropdown-System arbeitet über globalen Zustand und taintet
    --- schon beim Aufbau. Ersatz: UI.CreateDropdown / UI.CreateOptionDropdown.
    function Tests:testNoLegacyDropdownApi()
        local hits = Scan(function(line)
            return line:match("UIDropDownMenu") ~= nil
        end)
        AreEqual(0, #hits,
            "Legacy-Dropdown-API verwenden (taintet UIDROPDOWNMENU_*): " .. table.concat(hits, " | "))
    end

    -- ============================================================
    -- Fenster-Position: die Regeln aus b589c9d / 7f8caaa / a843d6b festhalten
    -- ============================================================

    -- Der gemeinsame Positions-Code lebt in UI_Common.lua. Das Dock-Tab klebt am
    -- Bildschirmrand und merkt sich nur seine Y-Position — es hat bewusst seinen
    -- eigenen, viel einfacheren Weg.
    local MOVE_EXEMPT = {
        ["src/ui/UI_Common.lua"]  = true,
        ["src/ui/UI_DockTab.lua"] = true,
    }

    --- Regel A: Verschieben läuft über UI.RegisterMovableFrame, nicht von Hand.
    --- RegisterForDrag und StartSizing auf demselben Frame blockieren sich gegenseitig
    --- (a843d6b) — deshalb baut der Helper einen eigenen Mover-Streifen, und niemand
    --- sonst verdrahtet Bewegung selbst.
    ---
    --- Geprüft wird allein StartMoving: ohne diesen Aufruf bewegt sich kein Fenster.
    --- RegisterForDrag wäre der falsche Marker — UI_DropPanel.lua nutzt es, um per
    --- OnReceiveDrag ein Item entgegenzunehmen, was mit Fensterposition nichts zu tun hat.
    function Tests:testNoHandWrittenFrameMoving()
        local hits = Scan(function(line)
            return line:match("StartMoving%s*%(") ~= nil
        end, MOVE_EXEMPT)
        AreEqual(0, #hits,
            "Fenster von Hand verschiebbar gemacht statt UI.RegisterMovableFrame: "
            .. table.concat(hits, " | "))
    end

    --- Regel B: Umankern auf TOPLEFT/UIParent passiert nur in UI.NormalizeFrameAnchor.
    --- Kopiert jemand die Zeile in einen Resize-Handler, fehlt dort früher oder später
    --- wieder das SetSize danach — genau so ging 7f8caaa verloren.
    function Tests:testNoDuplicateAnchorNormalization()
        local hits = Scan(function(line)
            return line:match('SetPoint%s*%(%s*"TOPLEFT"%s*,%s*UIParent%s*,%s*"TOPLEFT"') ~= nil
        end, { ["src/ui/UI_Common.lua"] = true })
        AreEqual(0, #hits,
            "Anker-Normalisierung dupliziert statt UI.NormalizeFrameAnchor zu rufen: "
            .. table.concat(hits, " | "))
    end
end)
