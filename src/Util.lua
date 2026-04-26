-- GuildLoot – Util.lua
-- Hilfsfunktionen (keine WoW-Events, keine Frames)

GuildLoot = GuildLoot or {}
local GL = GuildLoot

-- ============================================================
-- Datum / Kalenderwoche
-- ============================================================

--- ISO-8601-Kalenderwoche für einen Timestamp (oder jetzt).
--- date("%V") ist auf Windows-WoW-Clients nicht zuverlässig.
function GL.ISOWeek(ts)
    local d = date("*t", ts)
    local dow = (d.wday == 1) and 7 or (d.wday - 1)  -- Mo=1 … So=7
    local w   = math.floor((d.yday - dow + 10) / 7)
    if w < 1 then
        -- letzte Woche des Vorjahres
        local prev = date("*t", time({year=d.year-1, month=12, day=31}))
        local pdow = (prev.wday == 1) and 7 or (prev.wday - 1)
        w = math.floor((prev.yday - pdow + 10) / 7)
    elseif w > 52 then
        local dec31 = date("*t", time({year=d.year, month=12, day=31}))
        local ddow  = (dec31.wday == 1) and 7 or (dec31.wday - 1)
        if math.floor((dec31.yday - ddow + 10) / 7) < w then w = 1 end
    end
    return w
end

-- ============================================================
-- Kategorie-Erkennung
-- ============================================================

local WEAPON_SLOTS = {
    INVTYPE_WEAPON         = true,
    INVTYPE_MAINHAND       = true,
    INVTYPE_OFFHAND        = true,
    INVTYPE_2HWEAPON       = true,
    INVTYPE_RANGED         = true,
    INVTYPE_RANGEDRIGHT    = true,
    INVTYPE_SHIELD         = true,
    INVTYPE_HOLDABLE       = true,
}

-- Temporärer unsichtbarer Tooltip für Tooltip-Scans
local scanTooltip = CreateFrame("GameTooltip", "GuildLootScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Prüft ob ein Item eine Klassen-Einschränkung im Tooltip hat (Token-Erkennung)
local function HasClassRestriction(itemID)
    scanTooltip:ClearLines()
    scanTooltip:SetItemByID(itemID)
    for i = 1, scanTooltip:NumLines() do
        local line = _G["GuildLootScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText() or ""
            -- DE: "Klassen:", EN: "Classes:"
            if text:find("[Kk]lassen:") or text:find("[Cc]lasses:") then
                return true
            end
        end
    end
    return false
end

--- Bestimmt die Loot-Kategorie eines Items.
--- @param itemID number
--- @param itemEquipLoc string  z.B. "INVTYPE_WEAPON"
--- @param quality number       Blizzard item quality (4=epic, 5=legendary)
--- @return string  "setItems"|"weapons"|"trinket"|"other"
function GL.GetItemCategory(itemID, itemEquipLoc, quality)
    -- 1. Direkte Tier-Teile (Set-Armor mit Set-ID)
    if C_Item and C_Item.GetItemSetID then
        local setID = C_Item.GetItemSetID(itemID)
        if setID and setID ~= 0 then
            return "setItems"
        end
    end

    -- 2. Nicht-ausrüstbare Token (kein Equip-Slot, Epic+)
    if (itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP_IGNORE" or itemEquipLoc == "INVTYPE_NON_EQUIP") and quality >= 4 then
        -- 2a. Omni-Settoken: Name enthält "curio" (EN) oder "kuriosit" (DE), case-insensitive
        local itemName = GetItemInfo(itemID)
        if itemName then
            local ln = itemName:lower()
            if ln:find("curio") or ln:find("kuriosit") then
                return "setItems"
            end
        end
        -- 2b. Klassen-Token: hat Klassen-Einschränkung im Tooltip
        if HasClassRestriction(itemID) then
            return "setItems"
        end
    end

    -- 3. Waffe
    if WEAPON_SLOTS[itemEquipLoc] then
        return "weapons"
    end

    -- 4. Trinket
    if itemEquipLoc == "INVTYPE_TRINKET" then
        return "trinket"
    end

    -- 5. Alles andere
    return "other"
end

-- ============================================================
-- Schwierigkeitsgrad-Erkennung
-- ============================================================

--- Wandelt eine WoW difficultyID in "N"/"H"/"M" um.
--- @return string|nil
function GL.DiffIDToString(id)
    id = tonumber(id)
    if not id then return nil end
    if id == 14 or id == 1  or id == 17 then return "N" end
    if id == 15 or id == 2              then return "H" end
    if id == 16 or id == 8              then return "M" end
    return nil
end

--- Erkennt N/H/M:
--- 1. Primär: GetInstanceInfo() difficultyID (zuverlässig wenn in Instanz)
--- @return string|nil  "N"|"H"|"M" oder nil
function GL.DetectDifficulty()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" or instanceType == "party" then
        return GL.DiffIDToString(difficultyID)
    end
    return nil
end

--- Gibt true zurück wenn das Addon in dieser Zone aktiv sein soll.
--- Aktiv: Open World ("none") oder Raid-Instanz ("raid").
--- Inaktiv: Dungeon ("party"), Delve/Tiefen ("scenario"), Arena, BG.
function GL.IsValidZone()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "none" or instanceType == "raid"
end

-- ============================================================
-- Prioritäten-Hilfsfunktionen
-- ============================================================

--- Gibt sortierte Liste aktiver Prio-Nummern (1-5) zurück.
--- Liest aus priorityConfig der aktiven Raid Session, Fallback auf settings.
function GL.GetActivePrios()
    local db  = GuildLootDB
    local cfg = (db.activeContainerIdx and db.raidContainers
                 and db.raidContainers[db.activeContainerIdx]
                 and db.raidContainers[db.activeContainerIdx].priorityConfig)
                or (db.settings and db.settings.priorities) or {}
    local result = {}
    for i = 1, 5 do
        if cfg[i] and cfg[i].active then table.insert(result, i) end
    end
    if #result == 0 then return {1, 2, 4} end  -- Failsafe
    return result
end

--- Gibt den Kurznamen einer Prio zurück (z.B. "BIS"); Fallback "Prio N".
--- Liest aus priorityConfig der aktiven Raid Session, Fallback auf settings.
function GL.GetPrioLabel(n)
    if not n then return "" end
    local db  = GuildLootDB
    local cfg = (db.activeContainerIdx and db.raidContainers
                 and db.raidContainers[db.activeContainerIdx]
                 and db.raidContainers[db.activeContainerIdx].priorityConfig)
                or (db.settings and db.settings.priorities) or {}
    local p = cfg[n]
    if p and p.shortName and p.shortName ~= "" then return p.shortName end
    return "Prio " .. tostring(n)
end

-- ============================================================
-- Chat-Parsing
-- ============================================================

--- Extrahiert die führende Prio-Zahl aus einer Chat-Nachricht.
--- Akzeptiert nur aktive Prioritäten der aktuellen Raid Session.
--- @param message string
--- @return number|nil
function GL.ParseLootInput(message)
    if not message then return nil end
    local digits = ""
    for _, p in ipairs(GL.GetActivePrios()) do digits = digits .. p end
    if digits == "" then return nil end
    local digit = message:match("^%s*([" .. digits .. "])")
    if digit then return tonumber(digit) end
    return nil
end

-- ============================================================
-- Hilfsfunktionen
-- ============================================================

--- Stellt sicher dass ein Name das Format "Name-Realm" hat.
--- WoW gibt auf gleichem Realm nur "Name" zurück; cross-realm enthält "-" bereits.
function GL.NormalizeName(name)
    if name and not name:find("-") then
        local realm = GetRealmName()
        if realm then name = name .. "-" .. realm end
    end
    return name
end

function GL.IsMasterLooter()
    if not GuildLootDB or not GuildLootDB.settings then return false end
    if GuildLootDB.settings.isMasterLooter == true then return true end
    if GuildLootDB.settings.dungeonMode    == true then return true end
    -- Auto: solo in einer Raid-Instanz (Legacy-Farming etc.)
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" and not IsInGroup() then return true end
    return false
end

--- Raid-Assist oder Raid-Lead, aber kein ML.
function GL.IsObserver()
    if GL.IsMasterLooter() then return false end
    return UnitIsRaidOfficer("player") or UnitIsGroupLeader("player") or false
end

--- Player Mode: aktiv im Raid, aber weder ML noch Assist/Lead.
--- Außerhalb eines Raids (solo, Party, Dungeon) → false → volles Fenster.
--- Ausnahme: forcePlayerMode = true (Dev-Test-Flag via /reqrt playermode).
function GL.IsPlayerMode()
    if GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.forcePlayerMode then
        return true
    end
    if not IsInRaid() then return false end
    if GL.IsMasterLooter() then return false end
    if GL.IsObserver() then return false end
    return true
end

--- Announce-Filter: soll dieses Item den Popup triggern?
--- skipUsableCheck = true: IsUsableItem-Prüfung überspringen (z.B. forcePlayerMode)
--- Gibt true zurück wenn Item-Daten noch nicht gecacht (false positive besser als verpasstes Item).
function GL.PopupFilterMatches(link, category, skipUsableCheck)
    local f = GuildLootDB and GuildLootDB.settings and GuildLootDB.settings.announceFilter
    if not f then return true end

    -- Waffen: usable → immer zeigen; nicht-usable → nonUsableWeapon-Filter
    if category == "weapons" then
        if not skipUsableCheck then
            local isUsable = IsUsableItem(link)
            if isUsable ~= false then return true end   -- usable oder noch nicht gecacht → zeigen
            return f.nonUsableWeapon ~= false            -- nicht-usable → Filter prüfen
        end
        return f.nonUsableWeapon ~= false
    end

    -- Trinkets haben eigenen Filter-Key
    if category == "trinket" then return f.trinket ~= false end

    -- Ring/Neck via equipLoc; Rüstungstyp via itemSubType.
    -- IsUsableItem wird hier bewusst NICHT verwendet:
    --   • Legacy-Items (z.B. Shadowlands in Midnight) sind auf fremden Clients oft nicht gecacht →
    --     GetItemInfo liefert nil, IsUsableItem liefert false → fälschlicherweise blockiert.
    --   • Die Checkbox-Filter (cloth/leather/mail/plate/other) sind die korrekte Steuerung.
    local _, _, _, _, _, _, itemSubType, _, itemEquipLoc = GetItemInfo(link)
    if itemEquipLoc == "INVTYPE_NECK"   then return f.neck    ~= false end
    if itemEquipLoc == "INVTYPE_FINGER" then return f.ring    ~= false end
    if itemSubType  == "Cloth"          then return f.cloth   ~= false end
    if itemSubType  == "Leather"        then return f.leather ~= false end
    if itemSubType  == "Mail"           then return f.mail    ~= false end
    if itemSubType  == "Plate"          then return f.plate   ~= false end

    -- Nicht klassifizierbar (Item noch nicht gecacht, Token, sonstiges) → other-Filter.
    -- Absichtlich kein IsUsableItem-Check: false-positive (Item wird gezeigt obwohl nicht nutzbar)
    -- ist besser als false-negative (Item wird nicht gezeigt obwohl der ML es announced hat).
    return f.other ~= false
end

function GL.IsPlayerInGroup(name)
    if not name then return false end
    name = GL.ShortName(name)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = GetRaidRosterInfo(i)
            if n and GL.ShortName(n) == name then return true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local n = UnitName("party" .. i)
            if n and GL.ShortName(n) == name then return true end
        end
    end
    return false
end

function GL.GetTimestamp()
    return time()
end

function GL.FormatTimestamp(ts)
    if not ts then return "" end
    return date("%d.%m.%Y %H:%M", ts)
end

--- Gibt den Namen in Klassenfarbe zurück (nutzt RAID_CLASS_COLORS wie native WoW-Addons)
function GL.ColoredName(name, classFileName)
    if not classFileName then return name end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName]
    if c then
        return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
    end
    return name
end

function GL.TableContains(t, value)
    for _, v in ipairs(t) do
        if v == value then return true end
    end
    return false
end

--- Gibt den kürzesten Spielernamen zurück (ohne Realm wenn gleicher Realm)
function GL.ShortName(fullName)
    if not fullName then return "" end
    -- pcall guard: sender-Strings aus Chat-Events können WoW-tainted sein
    local ok, name = pcall(string.match, fullName, "^([^%-]+)")
    return (ok and name) or fullName
end

-- ============================================================
-- Raid-ID
-- ============================================================

--- Erzeugt eine stabile 8-stellige Hex-ID aus Timestamp, Tier und Schwierigkeit.
--- Verwendet djb2-Hash (kein WoW-API nötig).
--- @param tier string
--- @param difficulty string
--- @param timestamp number  Unix-Timestamp (time())
--- @return string  z.B. "a3f2b891"
function GL.GenerateRaidID(tier, difficulty, timestamp)
    local raw = string.format("%d|%s|%s", timestamp or 0, tier or "", difficulty or "")
    local h = 5381
    for i = 1, #raw do
        h = (h * 33 + raw:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

-- ============================================================
-- JSON-Export
-- ============================================================

local function JsonVal(val, seen)
    local t = type(val)
    if t == "string" then
        return '"' .. val:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r') .. '"'
    elseif t == "number"  then return tostring(val)
    elseif t == "boolean" then return val and "true" or "false"
    elseif t == "table" then
        if seen[val] then return '"[circular]"' end
        seen[val] = true
        -- Array-Erkennung: ausschließlich integer-keys 1..#t
        local isArr = (#val > 0)
        if isArr then
            for k in pairs(val) do
                if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                    isArr = false; break
                end
            end
        end
        local parts = {}
        if isArr then
            for i = 1, #val do
                parts[i] = JsonVal(val[i], seen)
            end
            seen[val] = nil
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(val) do
                local key = type(k) == "string" and k or tostring(k)
                table.insert(parts, '"' .. key:gsub('"','\\"') .. '":' .. JsonVal(v, seen))
            end
            seen[val] = nil
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

--- Wandelt Raid-Schwierigkeit in WoW-Item-Track-Bezeichnung um.
function GL.DiffToTrack(diff)
    if diff == "N" then return "Normal"
    elseif diff == "H" then return "Hero"
    elseif diff == "M" then return "Mythic"
    else return diff or "" end
end

--- Serialisiert die relevanten GuildLootDB-Daten als JSON-String.
function GL.ExportJSON(raidData)
    local data = {
        exportedAt = GL.FormatTimestamp(time()),
        raid       = raidData or (function()
            local db  = GuildLootDB
            local idx = db.activeContainerIdx
            return (idx and db.raidContainers and db.raidContainers[idx]) or db.currentRaid
        end)(),
        players    = GuildLootDB.players,
    }
    return JsonVal(data, {})
end

--- Exportiert den Loot-Log eines Raids als CSV (Google-Sheets-kompatibel).
-- Enthält: zugewiesene Items (lootLog) + getrashte Items (trashedLoot).
function GL.ExportCSV(raidData)
    local db   = GuildLootDB
    local idx  = db.activeContainerIdx
    local raid = raidData or (idx and db.raidContainers and db.raidContainers[idx]) or db.currentRaid

    local CAT_LABEL  = { weapons="Weapon", trinket="Trinket", setItems="Set", other="Other" }

    local function esc(s)
        s = tostring(s or "")
        if s:find('[",\n]') then s = '"' .. s:gsub('"', '""') .. '"' end
        return s
    end

    local lines = {}
    local header = "RaidID,Tier,Difficulty,Track,Date,Status,Player,Item,Category,Prio,Timestamp"
    table.insert(lines, header)

    local raidDate = raid.startedAt and raid.startedAt > 0 and GL.FormatTimestamp(raid.startedAt) or ""
    local raidTrack = GL.DiffToTrack(raid.difficulty or "")

    -- Zugewiesene Items (lootLog)
    for _, entry in ipairs(raid.lootLog or {}) do
        local track = GL.DiffToTrack(entry.difficulty or raid.difficulty or "")
        local prio  = entry.winnerPrio and GL.GetPrioLabel(entry.winnerPrio) or ""
        local cat   = CAT_LABEL[entry.category] or (entry.category or "")
        table.insert(lines, table.concat({
            esc(raid.id or ""),
            esc(raid.tier or ""),
            esc(entry.difficulty or raid.difficulty or ""),
            esc(track),
            esc(raidDate),
            "Assigned",
            esc(GL.ShortName(entry.player or "")),
            esc(entry.item or ""),
            esc(cat),
            esc(prio),
            esc(entry.timestamp and GL.FormatTimestamp(entry.timestamp) or ""),
        }, ","))
    end

    -- Getrashte Items (trashedLoot)
    for _, entry in ipairs(raid.trashedLoot or {}) do
        local cat = CAT_LABEL[entry.category] or (entry.category or "")
        table.insert(lines, table.concat({
            esc(raid.id or ""),
            esc(raid.tier or ""),
            esc(raid.difficulty or ""),
            esc(raidTrack),
            esc(raidDate),
            "Trashed",
            "",
            esc(entry.item or entry.link or ""),
            esc(cat),
            "",
            "",
        }, ","))
    end

    return table.concat(lines, "\n")
end

--- Exportiert mehrere Raids als einen CSV-String (ein gemeinsamer Header).
function GL.ExportMultiCSV(raidsList)
    local parts = {}
    for i, raid in ipairs(raidsList) do
        local csv = GL.ExportCSV(raid)
        if i > 1 then
            -- Header-Zeile entfernen
            csv = csv:match("^[^\n]*\n(.*)$") or ""
        end
        if csv ~= "" then table.insert(parts, csv) end
    end
    return table.concat(parts, "\n")
end

--- Exportiert mehrere Raids als JSON-Array.
function GL.ExportMultiJSON(raidsList)
    return JsonVal({
        exportedAt = GL.FormatTimestamp(time()),
        raids      = raidsList,
        players    = GuildLootDB.players,
    }, {})
end
