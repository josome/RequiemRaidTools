-- tests/standalone/loader.lua
-- Lädt Source-Dateien in TOC-Reihenfolge (wie WoW es tut).
-- Pfade relativ zum Repo-Root (busted von dort starten).

dofile("src/Util.lua")
dofile("src/Core.lua")
dofile("src/Comm.lua")
dofile("src/loot/Loot.lua")
dofile("src/loot/Loot_Roll.lua")
dofile("src/loot/Loot_Assign.lua")
dofile("src/loot/Loot_Trade.lua")

-- UI-Stubs: UI-Dateien werden nicht geladen, Tests mocken darüber hinaus selbst
GuildLoot.UI = GuildLoot.UI or {}
GuildLoot.UI.Refresh        = GuildLoot.UI.Refresh        or function() end
GuildLoot.UI.RefreshLootTab = GuildLoot.UI.RefreshLootTab or function() end
