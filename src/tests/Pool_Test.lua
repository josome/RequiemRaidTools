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

    -- ========================================================
    -- UI.RefreshOnResize
    -- ========================================================

    --- Fake-Frame, der Skripte sammelt und auf Kommando feuert. C_Timer.After wird auf
    --- "sofort ausführen" gesetzt, damit die Verzögerung im Test nicht im Weg steht.
    local function ResizeHarness()
        local scripts = {}
        local frame = {}
        function frame:HookScript(kind, fn)
            local prev = scripts[kind]
            scripts[kind] = function(...) if prev then prev(...) end fn(...) end
        end
        local calls = { fn = 0, scheduled = 0 }
        local origAfter = C_Timer.After
        C_Timer.After = function(_, fn)
            calls.scheduled = calls.scheduled + 1
            fn()
        end
        local trigger = UI.RefreshOnResize(frame, function() calls.fn = calls.fn + 1 end)
        return frame, scripts, calls, trigger, function() C_Timer.After = origAfter end
    end

    function Tests:testRefreshOnResize_HooksSizeAndShow()
        local _, scripts, calls, _, restore = ResizeHarness()
        IsTrue(scripts.OnSizeChanged ~= nil)
        IsTrue(scripts.OnShow ~= nil)
        scripts.OnSizeChanged()
        AreEqual(1, calls.fn)
        -- OnShow zählt eigenständig: ein verstecktes Panel bekommt kein OnSizeChanged
        scripts.OnShow()
        AreEqual(2, calls.fn)
        restore()
    end

    function Tests:testRefreshOnResize_CoalescesWithinOneFrame()
        local _, scripts, calls, _, restore = ResizeHarness()
        -- OnSizeChanged feuert beim Ziehen pro Frame — hier bewusst ohne zwischenzeitliches
        -- Ausführen des Timers, indem der Timer erst am Ende läuft
        local pendingFns = {}
        C_Timer.After = function(_, fn) table.insert(pendingFns, fn) end
        scripts.OnSizeChanged()
        scripts.OnSizeChanged()
        scripts.OnSizeChanged()
        AreEqual(1, #pendingFns)      -- nur EIN geplanter Durchlauf
        pendingFns[1]()
        AreEqual(1, calls.fn)
        restore()
    end

    function Tests:testRefreshOnResize_ReschedulesAfterRun()
        local _, scripts, calls, _, restore = ResizeHarness()
        scripts.OnSizeChanged()
        AreEqual(1, calls.fn)
        -- nach dem Durchlauf muss der nächste Resize wieder greifen
        scripts.OnSizeChanged()
        AreEqual(2, calls.fn)
        restore()
    end

    function Tests:testRefreshOnResize_NilArgsAreNoOp()
        AreEqual(nil, UI.RefreshOnResize(nil, function() end))
        AreEqual(nil, UI.RefreshOnResize({}, nil))
    end
end)
