# RequiemRaidTools – Findings

## in Raid Testing
### Reassign Loon nicht möglich (Bug ID:0001 )
#### Szenario
- Alleine in einem Dragonflight Raid, ohne Party auf Mythic
- devmode = off
- Session Aktiv
- Boss 1 getötet Loot verteile
    RaidID,Tier,Difficulty,Track,Date,Status,Player,Item,Category,Prio,Timestamp
    2026-W16-69e35769,,M,Mythic,18.04.2026 12:05,Assigned,Kalinea,[Branch of the Tormented Ancient],Trinket,,18.04.2026 12:37
    2026-W16-69e35769,,M,Mythic,18.04.2026 12:05,Assigned,Kalinea,[Silent Tormentor's Hood],Other,,18.04.2026 12:37
    2026-W16-69e35769,,M,Mythic,18.04.2026 12:05,Assigned,Kalinea,[Defender of the Ancient],Weapon,,18.04.2026 12:37
    2026-W16-69e35769,,M,Mythic,18.04.2026 12:05,Assigned,Kalinea,[Gnarlroot's Bonecrusher],Weapon,,18.04.2026 12:37
    2026-W16-69e35769,,M,Mythic,18.04.2026 12:05,Assigned,Kalinea,[Staff of Incandescent Torment],Weapon,,18.04.2026 12:38
#### Finding
- Loot reassing funktioniert nicht, drücken von << im Lootlog hat keine funktion, left dock panel geht nicht auf,
#### weitere Infos
- der Bug wurde auch in einem echten Raid festgestellt


## Relevante Lua Fehler
