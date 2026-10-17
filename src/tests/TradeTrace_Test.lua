-- RequiemRaidTools — src/tests/TradeTrace_Test.lua
-- Unit-Tests für Loot_TradeTrace.lua (dauerhaftes Auto-Trade-Ereignisprotokoll)
--
-- VORAUSSETZUNGEN
--   devMode aktiv (wie alle Suites); läuft über busted (spec/reqrt_spec.lua).

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests      = WoWUnit("ReqRT.TradeTrace")
    local GL         = GuildLoot
    local TradeTrace = GL.TradeTrace

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue

    --- Leeres Protokoll, devMode-Chatausgabe stummgeschaltet; alles danach wiederhergestellt.
    local function WithEmptyTrace(fn)
        local savedTrace, savedMax, savedPrint = GuildLootDB.tradeTrace, TradeTrace.MAX_ENTRIES, GL.Print
        GuildLootDB.tradeTrace = nil
        GL.Print = function() end
        local ok, err = pcall(fn)
        GuildLootDB.tradeTrace, TradeTrace.MAX_ENTRIES, GL.Print = savedTrace, savedMax, savedPrint
        if not ok then error(err, 0) end
    end

    -- Legt die Tabelle beim ersten Eintrag selbst an (Altdaten haben kein tradeTrace)
    function Tests:testAddCreatesStoreAndAppends()
        WithEmptyTrace(function()
            TradeTrace.Add("show", "Partner=%s", "Barbossbär")
            AreEqual(1, #GuildLootDB.tradeTrace)
            AreEqual("show", GuildLootDB.tradeTrace[1].kind)
            AreEqual("Partner=Barbossbär", GuildLootDB.tradeTrace[1].text)
            IsTrue(GuildLootDB.tradeTrace[1].ts > 0)
        end)
    end

    -- Ringpuffer: das älteste Ereignis fällt heraus
    function Tests:testRingBufferDropsOldest()
        WithEmptyTrace(function()
            TradeTrace.MAX_ENTRIES = 3
            for i = 1, 5 do TradeTrace.Add("item", "n=%d", i) end
            AreEqual(3,     #GuildLootDB.tradeTrace)
            AreEqual("n=3", GuildLootDB.tradeTrace[1].text)
            AreEqual("n=5", GuildLootDB.tradeTrace[3].text)
        end)
    end

    -- Falsche Format-Argumente dürfen den Trade-Ablauf nie abbrechen
    function Tests:testBadFormatArgsDoNotThrow()
        WithEmptyTrace(function()
            TradeTrace.Add("item", "%d Items", "keine Zahl")
            AreEqual(1, #GuildLootDB.tradeTrace)
            AreEqual("%d Items", GuildLootDB.tradeTrace[1].text)
        end)
    end

    -- Anzeige: neueste zuerst; Export: chronologisch
    function Tests:testEntriesNewestFirstAndTextChronological()
        WithEmptyTrace(function()
            TradeTrace.Add("assign", "erstes")
            TradeTrace.Add("close", "zweites")

            local entries = TradeTrace.Entries()
            AreEqual("zweites", entries[1].text)

            local text = TradeTrace.AsText()
            IsTrue(text:find("erstes", 1, true) < text:find("zweites", 1, true))
            IsTrue(text:find("[assign]", 1, true) ~= nil)
        end)
    end

    function Tests:testClear()
        WithEmptyTrace(function()
            TradeTrace.Add("show", "x")
            TradeTrace.Clear()
            AreEqual(0, #GuildLootDB.tradeTrace)
        end)
    end

end)
