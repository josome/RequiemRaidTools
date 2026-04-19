-- RequiemRaidTools — src/tests/Probe_Test.lua
-- Verifikationstest: stellt sicher dass WoWUnit Fehler korrekt als rot markiert.
-- Dieser Test muss immer rot sein — er ist kein echter Testfall sondern ein Sanity-Check.

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Probe")

    local AreEqual = WoWUnit.AreEqual

    -- Dieser Test muss rot bleiben — zeigt dass die Suite Fehler aufdecken kann
    function Tests:testRedProbe()
        AreEqual("FAIL-PROBE: WoWUnit Fail-Pfad funktioniert", false)
    end

end)
