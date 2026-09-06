-- RequiemRaidTools — src/tests/Frame_Test.lua
-- Unit-Tests für die gemeinsame Fenster-Positionierung:
--   UI.ClampFrameOffsets (src/ui/UI_Common.lua)
--   GL.MigrateFramePositions (src/core/Core_DB.lua)
--
-- VORAUSSETZUNGEN
--   devMode aktiv: /reqrt devmode → /reload
-- Läuft auch standalone über busted (spec/reqrt_spec.lua).
--
-- Getestet wird bewusst nur der rechnende Teil. Das Umankern selbst
-- (UI.NormalizeFrameAnchor) fasst echte Frames an und ist unter busted nicht
-- sinnvoll nachzubilden — deshalb steckt die ganze Bildschirm-Arithmetik in
-- ClampFrameOffsets, das ohne jeden Frame-Zugriff auskommt.

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Frame")
    local GL    = GuildLoot
    local UI    = GuildLoot.UI

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue

    -- Bildschirm 1600x900 für alle Fälle
    local SW, SH = 1600, 900

    -- ============================================================
    -- ClampFrameOffsets
    -- ============================================================

    function Tests:testClamp_InsideScreen_ReturnsUnchanged()
        local x, y = UI.ClampFrameOffsets(300, -200, 720, 560, SW, SH)
        AreEqual(300,  x)
        AreEqual(-200, y)
    end

    function Tests:testClamp_TooFarRight_StopsAtRightEdge()
        local x = UI.ClampFrameOffsets(1500, -100, 720, 560, SW, SH)
        AreEqual(SW - 720, x)
    end

    function Tests:testClamp_TooFarDown_StopsAtBottomEdge()
        local _, y = UI.ClampFrameOffsets(0, -800, 720, 560, SW, SH)
        AreEqual(-(SH - 560), y)
    end

    function Tests:testClamp_NegativeX_StopsAtLeftEdge()
        local x = UI.ClampFrameOffsets(-250, -100, 720, 560, SW, SH)
        AreEqual(0, x)
    end

    function Tests:testClamp_PositiveY_StopsAtTopEdge()
        local _, y = UI.ClampFrameOffsets(100, 250, 720, 560, SW, SH)
        AreEqual(0, y)
    end

    --- Nach einem Wechsel auf eine kleinere Auflösung ist das Fenster breiter als der
    --- Bildschirm. Dann gibt es keine gültige Position außer der linken oberen Ecke —
    --- sonst wäre die Titelzeile nicht mehr greifbar.
    function Tests:testClamp_FrameLargerThanScreen_PinsToTopLeft()
        local x, y = UI.ClampFrameOffsets(500, -400, 2000, 1200, SW, SH)
        AreEqual(0, x)
        AreEqual(0, y)
    end

    function Tests:testClamp_MissingInput_ReturnsNil()
        AreEqual(nil, UI.ClampFrameOffsets(nil, -100, 720, 560, SW, SH))
        AreEqual(nil, UI.ClampFrameOffsets(100, nil, 720, 560, SW, SH))
        AreEqual(nil, UI.ClampFrameOffsets(100, -100, 720, 560, SW, nil))
    end

    -- ============================================================
    -- SaveFramePosition: nur sichtbare Fenster sichern
    -- ============================================================

    -- Die echten Einstellungen des Testlaufs bleiben unberührt.
    local savedSettings

    local function WithSettings(settings)
        savedSettings = GuildLootDB.settings
        GuildLootDB.settings = settings
    end

    local function RestoreSettings()
        if savedSettings then
            GuildLootDB.settings = savedSettings
            savedSettings = nil
        end
    end

    --- Frame mit gesetzter linker oberer Ecke. Anker wertet der Stub nicht aus —
    --- für diese Tests zählt nur, ob überhaupt in den Speicher geschrieben wird.
    local function FakeWindow(left, top)
        local f = CreateFrame("Frame")
        f:SetSize(340, 380)
        f._left, f._top = left, top
        return f
    end

    local function StoreFor(key)
        return GuildLootDB.settings.framePositions
           and GuildLootDB.settings.framePositions[key]
    end

    --- Der Bug: CreateFrame liefert ein sichtbares Frame, das die Aufbau-Funktionen
    --- anschließend verstecken. Ein OnHide-Hook lief damit mitten im Konstruktor,
    --- während das Fenster noch auf seinem Default-Anker stand — und ersetzte die
    --- gespeicherte Position durch diesen Default. Symptom: Popup nach /reload
    --- wieder in der Bildschirmmitte.
    function Tests:testHideDuringBuild_DoesNotOverwriteStoredPosition()
        WithSettings({ framePositions = { buildTest = { x = 500, y = -300 } } })
        local f = FakeWindow(20, 880)          -- irgendwo anders als der gespeicherte Wert
        UI.RegisterMovableFrame(f, "buildTest")
        f:Hide()                                -- genau das tut BuildPopup nach dem Erzeugen
        AreEqual(500,  StoreFor("buildTest").x)
        AreEqual(-300, StoreFor("buildTest").y)
        RestoreSettings()
    end

    --- Gleiche Ursache auf dem Logout-Pfad: das angedockte Hauptfenster ist versteckt
    --- und steht auf seinem Default. SaveAllFramePositions darf es nicht sichern.
    function Tests:testSaveWhileHidden_KeepsStoredPosition()
        WithSettings({ framePositions = { hiddenTest = { x = 700, y = -100 } } })
        local f = FakeWindow(20, 880)
        f:Hide()
        UI.SaveFramePosition(f, "hiddenTest")
        AreEqual(700, StoreFor("hiddenTest").x)
        RestoreSettings()
    end

    function Tests:testSaveWhileShown_WritesCurrentPosition()
        WithSettings({ framePositions = { shownTest = { x = 700, y = -100 } } })
        local f = FakeWindow(20, 880)
        f:Show()
        UI.SaveFramePosition(f, "shownTest")
        AreEqual(20,  StoreFor("shownTest").x)   -- GetLeft
        AreEqual(-20, StoreFor("shownTest").y)   -- GetTop 880 - UIParent-Top 900
        RestoreSettings()
    end

    --- Größe gehört nur zu Fenstern, die der Benutzer skalieren kann. Beim Loot-Popup
    --- kommt die Breite aus dem Widget und darf nicht gegen einen gespeicherten Wert
    --- kämpfen.
    function Tests:testSaveWithoutSizeOption_StoresNoSize()
        WithSettings({})
        local f = FakeWindow(20, 880)
        UI.RegisterMovableFrame(f, "noSize")
        f:Show()
        UI.SaveFramePosition(f, "noSize")
        AreEqual(nil, StoreFor("noSize").w)
        AreEqual(nil, StoreFor("noSize").h)
        RestoreSettings()
    end

    function Tests:testSaveWithSizeOption_StoresSize()
        WithSettings({})
        local f = FakeWindow(20, 880)
        UI.RegisterMovableFrame(f, "withSize", { size = true })
        f:Show()
        UI.SaveFramePosition(f, "withSize")
        AreEqual(340, StoreFor("withSize").w)
        AreEqual(380, StoreFor("withSize").h)
        RestoreSettings()
    end

    -- ============================================================
    -- MigrateFramePositions
    -- ============================================================

    function Tests:testMigrate_LegacyFields_MoveToMainEntry()
        WithSettings({
            framePos  = { x = 120, y = -80 },
            frameSize = { w = 900, h = 640 },
        })
        GL.MigrateFramePositions()
        local main = GuildLootDB.settings.framePositions.main
        AreEqual(120, main.x)
        AreEqual(-80, main.y)
        AreEqual(900, main.w)
        AreEqual(640, main.h)
        AreEqual(nil, GuildLootDB.settings.framePos)
        AreEqual(nil, GuildLootDB.settings.frameSize)
        RestoreSettings()
    end

    function Tests:testMigrate_RunTwice_ChangesNothing()
        WithSettings({
            framePos  = { x = 10, y = -20 },
            frameSize = { w = 800, h = 600 },
        })
        GL.MigrateFramePositions()
        GL.MigrateFramePositions()
        local main = GuildLootDB.settings.framePositions.main
        AreEqual(10,  main.x)
        AreEqual(800, main.w)
        RestoreSettings()
    end

    --- Ein bereits im neuen Format gespeicherter Eintrag gewinnt: sonst würde ein
    --- liegengebliebenes Altfeld die aktuelle Position bei jedem Login überschreiben.
    function Tests:testMigrate_ExistingMainEntry_IsKept()
        WithSettings({
            framePos       = { x = 1, y = -1 },
            frameSize      = { w = 100, h = 100 },
            framePositions = { main = { x = 500, y = -300, w = 1000, h = 700 } },
        })
        GL.MigrateFramePositions()
        local main = GuildLootDB.settings.framePositions.main
        AreEqual(500,  main.x)
        AreEqual(1000, main.w)
        AreEqual(nil, GuildLootDB.settings.framePos)
        RestoreSettings()
    end

    function Tests:testMigrate_NoLegacyFields_CreatesEmptyStore()
        WithSettings({})
        GL.MigrateFramePositions()
        IsTrue(type(GuildLootDB.settings.framePositions) == "table")
        AreEqual(nil, GuildLootDB.settings.framePositions.main)
        RestoreSettings()
    end
end)
