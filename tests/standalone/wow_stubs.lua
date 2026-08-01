-- tests/standalone/wow_stubs.lua
-- WoW-API-Stubs für standalone Lua-Tests (busted, kein Game-Client nötig).
-- Definiert alle Globals die Source-Dateien beim Laden brauchen als No-Op-Stubs.
-- Tests mocken darüber hinaus selbst via Mock()/MockRestore().

-- ── Namespace ────────────────────────────────────────────────────────────────

GuildLoot = {}

-- ── Standard-Lua-Aliases (WoW überschreibt diese) ────────────────────────────

date    = os.date
time    = os.time
math.randomseed(os.time())

-- ── Event-System ─────────────────────────────────────────────────────────────

local _eventFrames = {}  -- event → { frame, ... }

local function _registerEvent(event, frame)
    _eventFrames[event] = _eventFrames[event] or {}
    table.insert(_eventFrames[event], frame)
end

local function _unregisterAll(frame)
    for _, frames in pairs(_eventFrames) do
        for i = #frames, 1, -1 do
            if frames[i] == frame then table.remove(frames, i) end
        end
    end
end

function FireEvent(event, ...)
    -- Kopie der Liste: UnregisterAllEvents innerhalb eines Handlers
    -- darf die Original-Liste nicht während der Iteration verändern.
    local frames = {}
    for _, f in ipairs(_eventFrames[event] or {}) do
        table.insert(frames, f)
    end
    for _, frame in ipairs(frames) do
        if frame._scripts and frame._scripts["OnEvent"] then
            frame._scripts["OnEvent"](frame, event, ...)
        end
    end
end

-- ── CreateFrame ───────────────────────────────────────────────────────────────

function CreateFrame(frameType, name, parent, template)
    local f = { _scripts = {}, _type = frameType }
    function f:RegisterEvent(e)       _registerEvent(e, self)  end
    function f:UnregisterAllEvents()  _unregisterAll(self)      end
    function f:UnregisterEvent(e)
        local list = _eventFrames[e] or {}
        for i = #list, 1, -1 do
            if list[i] == self then table.remove(list, i) end
        end
    end
    function f:SetScript(t, fn)  self._scripts[t] = fn   end
    function f:GetScript(t)      return self._scripts[t]  end
    function f:Hide()            self._shown = false       end
    function f:Show()            self._shown = true        end
    function f:IsShown()         return self._shown or false end
    function f:SetParent()       end
    function f:SetSize()         end
    function f:SetPoint()        end
    function f:SetWidth()        end
    function f:SetHeight()       end
    function f:SetAlpha()        end
    function f:SetText()         end
    function f:GetText()         return "" end
    function f:SetChecked()      end
    function f:GetChecked()      return false end
    function f:SetFrameLevel()   end
    function f:GetFrameLevel()   return 0 end
    function f:CreateTexture()   return f end
    function f:CreateFontString() return f end
    function f:SetFontObject()   end
    function f:SetTextColor()    end
    function f:SetTexture()      end
    function f:SetColorTexture() end
    function f:SetGradient()     end
    function f:SetAtlas()        end
    function f:SetNormalFontObject() end
    function f:GetStringWidth()  return 0 end
    function f:SetPushedTextOffset() end
    function f:SetNormalTexture() end
    function f:SetPushedTexture() end
    function f:SetHighlightTexture() end
    function f:SetDisabledFontObject() end
    function f:SetHighlightFontObject() end
    function f:SetOwner()        end
    function f:ClearLines()      end
    function f:SetItemByID()     end
    function f:NumLines()        return 0 end
    function f:AddLine()         end
    function f:GetLeft()         return nil end
    function f:HookScript(t, fn)
        local prev = self._scripts[t]
        self._scripts[t] = function(...)
            if prev then prev(...) end
            fn(...)
        end
    end
    return f
end

-- ── WoW-Tabellen (C_*) ───────────────────────────────────────────────────────

C_Timer = {
    After      = function(d, fn) end,
    NewTimer   = function(d, fn) return { Cancel = function() end } end,
    NewTicker  = function(d, fn, n) return { Cancel = function() end } end,
}

C_ChatInfo = {
    SendAddonMessage            = function() end,
    RegisterAddonMessagePrefix  = function() return true end,
}

C_Item = {
    GetItemSetID = function() return nil end,
}

C_Container = {
    GetContainerNumSlots  = function() return 0 end,
    GetContainerItemInfo  = function() return nil end,
    PickupContainerItem   = function() end,
}

C_AddOns = {
    GetAddOnMetadata = function(name, field)
        if field == "Version" then return "0.5.9.11" end
        return nil
    end,
}

-- ── Globale WoW-Funktionen ────────────────────────────────────────────────────

function GetAddOnMetadata(name, field)
    return C_AddOns.GetAddOnMetadata(name, field)
end

function GetItemInfo()          return nil end
function IsInRaid()             return false end
function IsInGroup()            return false end
function GetNumGroupMembers()   return 0 end
function GetRaidRosterInfo()    return nil end
function UnitName()             return "TestPlayer", nil end
-- Rückgabe: lokalisierter Klassenname, classFileName
function UnitClass()           return "Krieger", "WARRIOR" end
function UnitIsConnected()     return true end
function UnitAffectingCombat()  return false end
function UnitIsRaidOfficer()    return false end
function UnitIsGroupLeader()    return false end
function GetInstanceInfo()      return "test","none",0,"",0,0,false,0,0 end
function GetRealmName()         return "TestRealm" end
function GetTime()              return os.clock() end
function IsUsableItem()         return false end
function GetTradePlayerItemInfo() return nil end
function ClearCursor()          end
function ClickTradeButton()     end
function SendChatMessage()      end

-- Gilden-API (Tests mocken darüber; Defaults = keine Gilde)
function IsInGuild()               return false end
function GetNumGuildMembers()      return 0 end
function GetGuildRosterInfo()      return nil end
function GuildControlGetNumRanks() return 0 end
function GuildControlGetRankName(i) return "Rank" .. tostring(i) end
-- Roster-Filter "Offline anzeigen": beeinflusst, welche Zeilen GetGuildRosterInfo liefert.
local _showOffline = true
function GetGuildRosterShowOffline()  return _showOffline end
function SetGuildRosterShowOffline(v) _showOffline = v and true or false end
C_GuildInfo = C_GuildInfo or {}
function C_GuildInfo.GuildRoster() end

function strtrim(s)
    return (s:match("^%s*(.-)%s*$"))
end

function CopyTable(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and CopyTable(v) or v
    end
    return copy
end

TradeFrameRecipientNameText = CreateFrame("Frame")

WorldFrame = CreateFrame("Frame")

-- ── GuildLootDB Initialzustand ────────────────────────────────────────────────
-- devMode=true damit die Test-Guards in *_Test.lua passieren.
-- Core.lua überschreibt nur wenn GuildLootDB == nil.

GuildLootDB = {
    players            = {},
    raidHistory        = {},
    raidContainers     = {},
    activeContainerIdx = nil,
    unassignedRaids    = {},
    lastLogout         = 0,
    currentRaid = {
        id="", startedAt=0, tier="", difficulty="", mlName="",
        participants={}, absent={}, pendingLoot={},
        sessionHidden={}, sessionChecked={}, currentKillParticipants={},
        lastBoss=nil,
    },
    settings = {
        postToChat=true, chatChannel="AUTO", isMasterLooter=false,
        minQuality=4, prioSeconds=15, rollSeconds=15,
        framePos=nil, minimized=true, minimapAngle=45, lastTab=nil,
        raidWarnItem=true, danceEmptyState=true, whisperWinner=true,
        exportFormat="JSON", commLoopback=false,
        devMode=true,   -- muss true sein damit Test-Guards passieren
        filterNonEquip=true,
        filterCategories={ weapons=true, trinket=true, setItems=true, other=true },
        priorities={
            [1]={active=true,  shortName="BIS",     description="Best In Slot"},
            [2]={active=true,  shortName="OS",       description="Off-Spec"},
            [3]={active=false, shortName="",         description=""},
            [4]={active=true,  shortName="Transmog", description="Transmog"},
            [5]={active=false, shortName="",         description=""},
        },
        announceFilter={
            cloth=true, leather=true, mail=true, plate=true,
            nonUsableWeapon=true, trinket=true, ring=true, neck=true, other=true,
        },
        popupEnabled=nil,
    },
}

GuildLootDBBackup = {}

-- Slash-Command-System
SlashCmdList = {}
SLASH_REQUIEMRAIDTOOLS1 = "/reqrt"
SLASH_REQUIEMRAIDTOOLS2 = "/requiemraidtools"
