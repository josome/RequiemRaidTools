# RequiemRaidTools — Design Decisions

Warum bestimmte Dinge so gebaut wurden wie sie sind.

---

## Datenmodell

### `raidContainers` statt `currentRaid.lootLog`
Loot-Daten liegen in `GuildLootDB.raidContainers[i].lootLog`, nicht im flachen `currentRaid`.
**Grund:** Mehrere Raid-Sessions pro Woche (z.B. Mythic + Heroic) müssen getrennt speicherbar
sein. `currentRaid` ist transient und wird bei jedem Reset geleert.

### `pendingLoot` in der Session, nicht in `currentRaid`
`raidContainers[i].pendingLoot` überlebt einen ML-Reload (Resume-Fall).
**Grund:** Items die beim Boss gedroppt sind, aber noch nicht verteilt wurden, sollen nach
einem `/reload` des ML weiterhin vorhanden sein.

### `sessionHidden` / `sessionChecked` in `currentRaid`, nicht in der Session
Nur transiente UI-State-Daten (welche Session-Loot-Rows sind abgehakt/versteckt).
**Grund:** Wird beim Session-Ende ohnehin zurückgesetzt; soll nicht in SavedVariables landen.

---

## Observer-Sync

### Addon-Messages via `"RequiemRLT"`-Prefix, kein SAY/Whisper-Bypass
Alle ML→Observer-Nachrichten gehen über `C_ChatInfo.SendAddonMessage` (RAID/PARTY-Kanal).
**Grund:** Unsichtbar für andere Spieler, kein Spam, kein Chat-Missbrauch.
SAY-Kanal wird nur für `PostToRaid`-Chatnachrichten als Solo-Fallback verwendet —
nicht für Sync-Daten.

### `activeContainerIdx` immer in `OnCommSessionStart` setzen
Wenn der Observer eine bekannte Session empfängt, wird `activeContainerIdx` immer
gesetzt — nicht nur beim Resume einer geschlossenen Session.
**Grund:** Nach Observer-`/reload` oder spätem Beitritt existiert die Session in
`raidContainers`, aber `activeContainerIdx` kann nil sein. Ohne diesen Fix wurden
alle ASSIGN-Nachrichten still gedroppt.

### Observer sieht Pending Loot über `OnCommItemActivate`
Wenn der ML ein Item aktiviert (ITEM_ON), fügt der Observer es lokal zu `pendingLoot` ein.
**Grund:** Der Observer öffnet das Loot-Fenster nicht selbst (`OnLootOpened` hat ML-Guard).
So sieht er trotzdem was gerade verteilt wird.

### `commLoopback`-Setting für Same-Character-Tests
`/reqrt loopback` erlaubt es, eigene Addon-Nachrichten zu empfangen (werden sonst gefiltert).
**Grund:** Entwicklertests auf einem Charakter ohne zweiten Account. Im Live-Betrieb immer off.

---

## UI

### Frame-Pool in `RefreshSessionLoot`
Session-Loot-Rows werden nicht bei jedem Refresh neu erstellt, sondern aus einem Pool
wiederverwendet (`sessionLootPool`).
**Grund:** WoW-Frames können nicht garbage-collected werden. Ohne Pool akkumulieren
tausende versteckte Frames → "script ran too long" bei ENCOUNTER_END.

### Kein End-Raid-Button
Es gibt keinen separaten "Raid beenden"-Button.
**Grund:** Ein aktiver Raid ohne offene Session ist kein valider Zustand. Session schließen
= Raid beenden. Der Workflow ist: Session öffnen → verteilen → Session schließen.

### ML-Checkbox nur für Raid-Leader/Assistenten sichtbar
`UI.RefreshMLButton` blendet die Checkbox für normale Raid-Mitglieder aus.
**Grund:** Verhindert unbefugten ML-Claim. Nur wer theoretisch ML sein könnte (RL/RA),
sieht die Option überhaupt.

---

## Item-Erkennung

### Curio-Erkennung per case-insensitivem Namenscheck
`GetItemCategory` erkennt Curios per `itemName:lower():find("curio"/"kuriosit")`.
**Grund:** Deutsche Komposita wie "Leerenkuriosität" haben "kuriosit" kleingeschrieben
in der Wortmitte — case-sensitiver Check würde sie verpassen.
