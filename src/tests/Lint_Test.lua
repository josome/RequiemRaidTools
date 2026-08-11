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
    --- @param check fun(line:string):boolean  true = Verstoß
    --- @return table Liste aus "pfad:zeile: inhalt"
    local function Scan(check)
        local hits = {}
        local files = ShippedFiles() or {}
        for _, path in ipairs(files) do
            local lines = ReadLines(path)
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
end)
