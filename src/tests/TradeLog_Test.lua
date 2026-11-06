-- RequiemRaidTools — src/tests/TradeLog_Test.lua
-- Unit-Tests für Loot_TradeLog.lua (Auto-Trade-Zustand je Zuteilung)
--
-- VORAUSSETZUNGEN
--   devMode aktiv (wie alle Suites); läuft über busted (spec/reqrt_spec.lua).
--
-- HINWEIS
--   Jeder Test bekommt über WithSession eine frische aktive Raid Session.
--   Zeit wird explizit übergeben (now), damit das 2h-Fenster deterministisch ist.

if not WoWUnit then return end

local _loader = CreateFrame("Frame")
_loader:RegisterEvent("ADDON_LOADED")
_loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "RequiemRaidTools" then return end
    self:UnregisterAllEvents()
    if not (GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.devMode) then return end

    local Tests    = WoWUnit("ReqRT.TradeLog")
    local GL       = GuildLoot
    local Loot     = GL.Loot
    local TradeLog = GL.TradeLog

    local AreEqual = WoWUnit.AreEqual
    local IsTrue   = WoWUnit.IsTrue
    local IsFalse  = WoWUnit.IsFalse
    local Exists   = WoWUnit.Exists

    local NOW  = 1800000000
    local HOUR = 3600

    --- Frische aktive Session; DB, Queue-Spiegel und Protokoll werden danach wiederhergestellt.
    local function WithSession(fn)
        local db = GuildLootDB
        local saved = {
            containers = db.raidContainers, idx = db.activeContainerIdx,
            trace = db.tradeTrace, players = db.players,
            pending = Loot._pendingTrades, inTrade = Loot._inTradeItems, orphans = TradeLog._orphans,
            isML = db.settings and db.settings.isMasterLooter,
        }
        -- TradeLog ist das ML-seitige Modul; WarnExpiring prüft die Rolle. Explizit
        -- setzen, damit die Suite nicht von der Testreihenfolge abhängt.
        if db.settings then db.settings.isMasterLooter = true end
        local session = { id = "tl-test", lootLog = {}, manualTrades = {} }
        db.raidContainers     = { session }
        db.activeContainerIdx = 1
        db.tradeTrace         = {}
        db.players            = {}
        Loot._pendingTrades   = {}
        Loot._inTradeItems    = {}
        TradeLog._orphans     = {}
        local ok, err = pcall(fn, session)
        db.raidContainers, db.activeContainerIdx = saved.containers, saved.idx
        db.tradeTrace, db.players = saved.trace, saved.players
        Loot._pendingTrades, Loot._inTradeItems, TradeLog._orphans = saved.pending, saved.inTrade, saved.orphans
        if db.settings then db.settings.isMasterLooter = saved.isML end
        if not ok then error(err, 0) end
    end

    --- lootLog-Eintrag wie AssignLootConfirm ihn schreibt, plus Track().
    local function Assign(session, itemID, player, ts)
        local e = {
            itemID = itemID, player = player, timestamp = ts or (NOW - 60),
            link = "|Hitem:" .. itemID .. "::|h[Item " .. itemID .. "]|h",
        }
        table.insert(session.lootLog, e)
        TradeLog.Track(e)
        return e
    end

    -- --------------------------------------------------------
    -- Zuteilung
    -- --------------------------------------------------------

    function Tests:testTrackQueues()
        WithSession(function(session)
            local e = Assign(session, 1, "Barbossbär-Malfurion")
            AreEqual("queued", e.trade.status)
            AreEqual(0,        e.trade.attempts)
            IsTrue(TradeLog.IsOpen(e, NOW))
        end)
    end

    -- B5: Mit sich selbst kann man nicht handeln (UnitName-Stub liefert "TestPlayer")
    function Tests:testTrackSelfIsNotQueued()
        WithSession(function(session)
            local e = Assign(session, 2, "TestPlayer-TestRealm")
            AreEqual("self", e.trade.status)
            AreEqual(0, #TradeLog.BuildQueue(NOW))
        end)
    end

    -- --------------------------------------------------------
    -- B1: Reassign im Log-Tab — Auto-Trade folgt dem neuen Spieler
    -- --------------------------------------------------------
    function Tests:testReassignFollowsPlayer()
        WithSession(function(session)
            local e = Assign(session, 3, "Alpha-Malfurion")
            AreEqual(1, #TradeLog.EntriesFor("Alpha", NOW))

            local old = e.player
            e.player = "Beta-Malfurion"           -- so schreibt UI_LogTab den Reassign
            TradeLog.OnReassign(e, old, e.player)

            AreEqual(0, #TradeLog.EntriesFor("Alpha", NOW))
            AreEqual(1, #TradeLog.EntriesFor("Beta",  NOW))
        end)
    end

    -- --------------------------------------------------------
    -- B2: Queue überlebt /reload — sie kommt aus den gespeicherten Einträgen
    -- --------------------------------------------------------
    function Tests:testQueueSurvivesReload()
        WithSession(function(session)
            local e = Assign(session, 4, "Barbossbär-Malfurion")
            Loot._pendingTrades = {}              -- so sieht der Laufzeit-Zustand nach /reload aus

            TradeLog.OnLogin(NOW)

            AreEqual(1, #Loot._pendingTrades)
            AreEqual(4, Loot._pendingTrades[1].itemID)
            AreEqual(e, Loot._pendingTrades[1].entry)
        end)
    end

    -- Was gerade im Handelsfenster liegt, gehört nicht in den Spiegel
    function Tests:testMirrorSkipsStagedItems()
        WithSession(function(session)
            local a = Assign(session, 5, "Barbossbär")
            Assign(session, 6, "Barbossbär")
            Loot._inTradeItems = { { itemID = 5, entry = a } }

            TradeLog.SyncMirror(NOW)

            AreEqual(1, #Loot._pendingTrades)
            AreEqual(6, Loot._pendingTrades[1].itemID)
        end)
    end

    -- --------------------------------------------------------
    -- 2h-Handelsfenster
    -- --------------------------------------------------------

    function Tests:testExpireStale()
        WithSession(function(session)
            local old   = Assign(session, 7, "Barbossbär", NOW - 3 * HOUR)
            local fresh = Assign(session, 8, "Barbossbär", NOW - HOUR)

            AreEqual(1, TradeLog.ExpireStale(NOW))

            AreEqual("expired", old.trade.status)
            AreEqual("queued",  fresh.trade.status)
            AreEqual(1, #TradeLog.BuildQueue(NOW))
        end)
    end

    -- Altdaten ohne entry.trade kommen nie automatisch in die Queue
    function Tests:testLegacyEntriesIgnored()
        WithSession(function(session)
            table.insert(session.lootLog, { itemID = 9, player = "Barbossbär", timestamp = NOW - 60 })

            AreEqual(0, #TradeLog.BuildQueue(NOW))
            local rows = TradeLog.Rows(session, NOW)
            AreEqual(1,   #rows)
            AreEqual(nil, rows[1].status)
        end)
    end

    function Tests:testEntriesForLimitedToSixSlots()
        WithSession(function(session)
            for i = 1, 8 do Assign(session, 100 + i, "Barbossbär", NOW - 600 + i) end
            local list = TradeLog.EntriesFor("Barbossbär", NOW)
            AreEqual(6,   #list)
            AreEqual(101, list[1].itemID)  -- älteste zuerst: deren Fenster läuft zuerst ab
        end)
    end

    -- --------------------------------------------------------
    -- Manuelle Eingriffe
    -- --------------------------------------------------------

    function Tests:testRedirectOnlyChangesTradeRecipient()
        WithSession(function(session)
            local e = Assign(session, 10, "Alpha-Malfurion")

            TradeLog.Redirect(e, "Gamma-Malfurion", NOW)

            AreEqual("Alpha-Malfurion", e.player)           -- Zuteilung bleibt
            AreEqual("Gamma-Malfurion", TradeLog.Recipient(e))
            AreEqual(1, #TradeLog.EntriesFor("Gamma", NOW))
            AreEqual(0, #TradeLog.EntriesFor("Alpha", NOW))
        end)
    end

    function Tests:testRedirectBackClearsOverride()
        WithSession(function(session)
            local e = Assign(session, 11, "Alpha-Malfurion")
            TradeLog.Redirect(e, "Gamma-Malfurion", NOW)
            TradeLog.Redirect(e, "Alpha-Malfurion", NOW)
            AreEqual(nil, e.trade.recipient)
        end)
    end

    function Tests:testRedirectReopensTradedEntry()
        WithSession(function(session)
            local e = Assign(session, 12, "Alpha-Malfurion", NOW - 3 * HOUR)
            TradeLog.SetStatus(e, "traded", NOW)

            TradeLog.Redirect(e, "Gamma-Malfurion", NOW)

            AreEqual("queued", e.trade.status)
            IsTrue(TradeLog.IsOpen(e, NOW))  -- 2h-Fenster startet mit dem Umleiten neu
        end)
    end

    function Tests:testMarkDone()
        WithSession(function(session)
            local e = Assign(session, 13, "Barbossbär")
            TradeLog.MarkDone(e, NOW)
            AreEqual("traded", e.trade.status)
            IsTrue(e.trade.manualDone)
            AreEqual(0, #TradeLog.BuildQueue(NOW))
        end)
    end

    function Tests:testRequeueRestartsWindow()
        WithSession(function(session)
            local e = Assign(session, 14, "Barbossbär", NOW - 3 * HOUR)
            TradeLog.ExpireStale(NOW)
            AreEqual("expired", e.trade.status)

            TradeLog.Requeue(e, NOW)

            AreEqual("queued", e.trade.status)
            IsTrue(TradeLog.IsOpen(e, NOW))
        end)
    end

    -- Eigenes Item: "Wieder in Queue" darf keinen Handel mit sich selbst einplanen
    function Tests:testRequeueSelfStaysSelf()
        WithSession(function(session)
            local e = Assign(session, 25, "TestPlayer-TestRealm")
            TradeLog.Requeue(e, NOW)
            AreEqual("self", e.trade.status)
            AreEqual(0, #TradeLog.BuildQueue(NOW))
        end)
    end

    function Tests:testRemoveAssignmentKeepsLootLog()
        WithSession(function(session)
            local e = Assign(session, 15, "Barbossbär")
            TradeLog.Remove(e, NOW)
            AreEqual("removed", e.trade.status)
            AreEqual(1, #session.lootLog)
            AreEqual(0, #TradeLog.BuildQueue(NOW))
        end)
    end

    function Tests:testAddManual()
        WithSession(function(session)
            local link = "|Hitem:16::|h[Manuell]|h"
            local e = TradeLog.AddManual(link, "Barbossbär-Malfurion", NOW)

            AreEqual(1,        #session.manualTrades)
            AreEqual(0,        #session.lootLog)       -- keine Zuteilung
            AreEqual(nil,      next(GuildLootDB.players)) -- keine Historie, keine Prio-Zähler
            AreEqual(16,       e.itemID)
            AreEqual("queued", e.trade.status)
            AreEqual(1, #TradeLog.EntriesFor("Barbossbär", NOW))
        end)
    end

    -- Manuell vorbereitete Trades laufen nicht ab
    function Tests:testManualEntryNeverExpires()
        WithSession(function(session)
            local e = TradeLog.AddManual("|Hitem:17::|h[x]|h", "Barbossbär", NOW - 5 * HOUR)
            AreEqual(0, TradeLog.ExpireStale(NOW))
            IsTrue(TradeLog.IsOpen(e, NOW))
        end)
    end

    function Tests:testRemoveManualDeletesEntry()
        WithSession(function(session)
            local e = TradeLog.AddManual("|Hitem:18::|h[x]|h", "Barbossbär", NOW)
            TradeLog.Remove(e, NOW)
            AreEqual(0, #session.manualTrades)
        end)
    end

    -- Ohne Raid Session: Eintrag nur zur Laufzeit, aber im Auto-Trade dabei
    function Tests:testAddManualWithoutSession()
        WithSession(function()
            GuildLootDB.activeContainerIdx = nil
            local e = TradeLog.AddManual("|Hitem:19::|h[x]|h", "Barbossbär", NOW)
            AreEqual(1, #TradeLog._orphans)
            IsTrue(e._orphan)
            AreEqual(1, #TradeLog.EntriesFor("Barbossbär", NOW))
        end)
    end

    -- --------------------------------------------------------
    -- Anzeige
    -- --------------------------------------------------------

    function Tests:testRowsNewestFirstWithRemaining()
        WithSession(function(session)
            Assign(session, 20, "Barbossbär", NOW - HOUR)
            local newer = Assign(session, 21, "Barbossbär", NOW - 600)
            TradeLog.Redirect(newer, "Gamma-Malfurion", NOW)

            local rows = TradeLog.Rows(session, NOW)

            AreEqual(2,       #rows)
            AreEqual(newer,   rows[1].entry)
            IsTrue(rows[1].redirected)
            AreEqual("Gamma-Malfurion", rows[1].recipient)
            AreEqual("Barbossbär",      rows[1].assigned)
            AreEqual(HOUR,    rows[2].remaining)
        end)
    end

    function Tests:testQueueSummary()
        WithSession(function(session)
            Assign(session, 22, "Barbossbär")
            local s = Assign(session, 23, "Barbossbär")
            TradeLog.SetStatus(s, "staged", NOW)
            local waiting, staged = TradeLog.QueueSummary(NOW)
            AreEqual(1, waiting)
            AreEqual(1, staged)
        end)
    end

    -- Jede manuelle Änderung landet im Protokoll
    function Tests:testManualActionsAreTraced()
        WithSession(function(session)
            local e = Assign(session, 24, "Alpha")
            TradeLog.Redirect(e, "Gamma", NOW)
            TradeLog.MarkDone(e, NOW)
            local manual = 0
            for _, ev in ipairs(GuildLootDB.tradeTrace) do
                if ev.kind == "manual" then manual = manual + 1 end
            end
            AreEqual(2, manual)
        end)
    end

    -- --------------------------------------------------------
    -- 2h-Fenster: Startzeitpunkt
    -- --------------------------------------------------------

    -- WoW rechnet die zwei Stunden ab dem Looten. Item vor 90 Min gelootet, gerade
    -- erst zugeteilt → nach weiteren 40 Min ist das Fenster zu, obwohl die
    -- Zuweisung erst eine Minute alt ist. Vorher zählte das Addon ab der Zuweisung
    -- und hielt das Item noch fast zwei Stunden für handelbar.
    function Tests:testWindowStartsAtLootTime()
        WithSession(function(session)
            local e = Assign(session, 30, "Alpha", NOW - 60)
            e.lootedAt = NOW - 90 * 60

            AreEqual(NOW - 90 * 60, TradeLog.WindowStart(e))
            IsTrue(TradeLog.IsOpen(e, NOW), "innerhalb des Fensters bereits zu")
            IsFalse(TradeLog.IsOpen(e, NOW + 40 * 60), "Fenster nach 2h ab Looten noch offen")
        end)
    end

    -- Altdaten ohne lootedAt verhalten sich wie bisher: ab Zuweisungszeit.
    function Tests:testFallsBackToTimestampWithoutLootedAt()
        WithSession(function(session)
            local e = Assign(session, 31, "Alpha", NOW - 60)

            AreEqual(NOW - 60, TradeLog.WindowStart(e))
            IsTrue(TradeLog.IsOpen(e, NOW + HOUR))
            IsFalse(TradeLog.IsOpen(e, NOW + 3 * HOUR))
        end)
    end

    -- Ein manueller Requeue startet das Fenster neu und überstimmt lootedAt.
    function Tests:testRequeueOverridesLootTime()
        WithSession(function(session)
            local e = Assign(session, 32, "Alpha", NOW - 60)
            e.lootedAt = NOW - 90 * 60
            TradeLog.Requeue(e, NOW)

            AreEqual(NOW, TradeLog.WindowStart(e))
            IsTrue(TradeLog.IsOpen(e, NOW + HOUR))
        end)
    end

    -- --------------------------------------------------------
    -- Vorwarnung zum Fensterende
    -- --------------------------------------------------------

    -- Zwei Items für Alpha, eines für Beta, alle kurz vor Ablauf → zwei Gruppen,
    -- Alpha mit count 2. Die Gruppe nennt die KLEINSTE Restzeit.
    function Tests:testExpiringSoonGroupsByRecipient()
        WithSession(function(session)
            local soon = NOW - (2 * HOUR - 10 * 60)   -- 10 Min Restzeit
            local a1 = Assign(session, 40, "Alpha", soon)
            local a2 = Assign(session, 41, "Alpha", NOW - (2 * HOUR - 5 * 60))  -- 5 Min
            local b1 = Assign(session, 42, "Beta",  soon)
            AreEqual(3, #TradeLog.BuildQueue(NOW))

            local groups = TradeLog.ExpiringSoon(NOW)
            AreEqual(2, #groups)
            local byName = {}
            for _, g in ipairs(groups) do byName[g.name] = g end
            Exists(byName.Alpha)
            Exists(byName.Beta)
            AreEqual(2, byName.Alpha.count)
            AreEqual(1, byName.Beta.count)
            AreEqual(5 * 60, byName.Alpha.remaining)  -- kleinste Restzeit der Gruppe
        end)
    end

    -- Items mit viel Restzeit tauchen in der Vorwarnung nicht auf.
    function Tests:testExpiringSoonIgnoresFreshEntries()
        WithSession(function(session)
            Assign(session, 43, "Alpha", NOW - 60)
            AreEqual(0, #TradeLog.ExpiringSoon(NOW))
        end)
    end

    -- Der Minutentakt darf nicht spammen: nur der erste Aufruf warnt.
    function Tests:testWarnsOnlyOnce()
        WithSession(function(session)
            local e = Assign(session, 44, "Alpha", NOW - (2 * HOUR - 10 * 60))

            AreEqual(1, TradeLog.WarnExpiring(NOW))
            IsTrue(e.trade.warned, "warned-Markierung fehlt")
            AreEqual(0, TradeLog.WarnExpiring(NOW))
        end)
    end

    -- Nach einem manuellen Requeue darf erneut gewarnt werden.
    function Tests:testRequeueClearsWarnedFlag()
        WithSession(function(session)
            local e = Assign(session, 45, "Alpha", NOW - (2 * HOUR - 10 * 60))
            AreEqual(1, TradeLog.WarnExpiring(NOW))

            TradeLog.Requeue(e, NOW)
            IsFalse(e.trade.warned or false, "warned nach Requeue noch gesetzt")
        end)
    end

end)
