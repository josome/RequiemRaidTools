-- RequiemRaidTools — src/tests/Probe_Test.lua
-- Smoke-Test: stellt sicher dass WoWUnit korrekt läuft und Assertions funktionieren.

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Probe")

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue

    -- Prüft: WoWUnit läuft und Assertions funktionieren
    function Tests:testSmokeGreen()
        AreEqual(1, 1)
        IsTrue(true)
    end

end)
