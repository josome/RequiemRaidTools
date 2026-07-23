-- RequiemRaidTools — src/tests/Pool_Test.lua
-- Unit-Tests für UI.CreateFramePool (src/ui/UI_Common.lua) via WoWUnit.
--
-- VORAUSSETZUNGEN
--   1. WoWUnit-Addon installiert (OptionalDep in der TOC).
--   2. devMode aktiv: /reqrt devmode → /reload
-- Läuft auch standalone über busted (spec/reqrt_spec.lua).
--
-- Die Factory ist Frame-API-agnostisch: createFn/resetFn kapseln alles
-- Frame-Berührende. Die Tests nutzen daher plain Lua-Tables als "Frames".

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests = WoWUnit("ReqRT.Pool")
    local UI    = GuildLoot.UI

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue

    --- Test-Pool mit Zählern: "Frames" sind plain Tables { id = n }.
    local function NewCountingPool()
        local stats = { created = 0, resets = 0 }
        local pool = UI.CreateFramePool(
            function()
                stats.created = stats.created + 1
                return { id = stats.created }
            end,
            function(_, frame)
                stats.resets = stats.resets + 1
                frame.wasReset = true
            end
        )
        return pool, stats
    end

    function Tests:testAcquire_EmptyPool_CallsCreateExactlyOnce()
        local pool, stats = NewCountingPool()
        local frame = pool:Acquire()
        AreEqual(1, stats.created)
        AreEqual(1, frame.id)
        AreEqual(1, pool:GetNumActive())
    end

    function Tests:testReleaseAll_ResetsEachActiveFrame_ActiveDropsToZero()
        local pool, stats = NewCountingPool()
        pool:Acquire()
        pool:Acquire()
        pool:Acquire()
        pool:ReleaseAll()
        AreEqual(3, stats.resets)
        AreEqual(0, pool:GetNumActive())
    end

    function Tests:testAcquire_AfterReleaseAll_ReusesSameObject()
        local pool, stats = NewCountingPool()
        local first = pool:Acquire()
        pool:ReleaseAll()
        local second = pool:Acquire()
        IsTrue(first == second)
        AreEqual(1, stats.created)  -- kein zweiter createFn-Aufruf
    end

    function Tests:testLeakPrevention_TotalCreationsBoundedByPeak()
        local pool, stats = NewCountingPool()
        -- Simuliert wiederholte Refreshes: 5 Rows pro Durchlauf, 4 Durchläufe
        for _ = 1, 4 do
            pool:ReleaseAll()
            for _ = 1, 5 do pool:Acquire() end
        end
        AreEqual(5, stats.created)  -- nur der Peak, nicht 20
        AreEqual(5, pool:GetNumActive())
    end

    function Tests:testTwoPools_AreIsolated()
        local poolA, statsA = NewCountingPool()
        local poolB, statsB = NewCountingPool()
        local a = poolA:Acquire()
        poolA:ReleaseAll()
        local b = poolB:Acquire()
        IsTrue(a ~= b)
        AreEqual(1, statsA.created)
        AreEqual(1, statsB.created)
    end

    function Tests:testReleaseAll_EmptyPool_IsNoOp()
        local pool, stats = NewCountingPool()
        pool:ReleaseAll()
        AreEqual(0, stats.resets)
        AreEqual(0, pool:GetNumActive())
    end
end)
