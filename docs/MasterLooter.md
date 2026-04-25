# RequiemRaidTools — Master Looter Verhalten

Dokumentiert das aktuell implementierte ML-Verhalten. Dient als Referenz für Live-Tests
und als Grundlage für automatische Tests.

---

## Inhaltsverzeichnis

- [3-Layer System](#3-layer-system)
- [Privilegien](#privilegien)
  - [Master Looter](#master-looter)
  - [Observer](#observer)
  - [Player (geplant)](#player-geplant-noch-nicht-implementiert)
- [ML-Erkennung](#ml-erkennung)
- [ML-exklusive Aktionen](#ml-exklusive-aktionen)
- [ML-Handover Flow](#ml-handover-flow)
- [Bekannte Probleme](#bekannte-probleme)
- [UI-Anzeige](#ui-anzeige)
- [currentItem bei ML-Wechsel](#currentitem-bei-ml-wechsel)
- [Live-Test Checkliste](#live-test-checkliste)

---

## 3-Layer System

| Rolle | Wer | Status |
|-------|-----|--------|
| **Master Looter (ML)** | Genau ein Spieler pro Raid — muss Raid-Leader oder Raid-Assist sein | ✅ Implementiert |
| **Observer (OBS)** | Alle anderen Raid-Leader/Assists mit installiertem Addon | ✅ Implementiert |
| **Player** | Alle übrigen Raid-Mitglieder (ohne Addon-Fenster) | 🔲 Geplant |

---

## Privilegien

### Master Looter
- Vollzugriff auf das Addon-Fenster (alle Tabs)
- Item freigeben (`ReleaseItem`) und abbrechen
- Prio-Phase starten, Roll-Phase starten
- Gewinner bestätigen (`AssignLoot`)
- Session starten, schließen, umbenennen
- Loot als Trash markieren
- ML-Rolle an anderen Spieler übergeben
- Sendet alle Sync-Nachrichten an die Gruppe

### Observer
- Lese-Zugriff auf alle Tabs (Loot, Spieler, Log, Verlauf)
- Sieht aktives Item, Kandidaten, Roll-Ergebnisse, Session-Log in Echtzeit
- Kann keine Aktionen auslösen (alle Buttons deaktiviert oder ausgeblendet)
- Kann ML-Rolle beantragen (nur wenn Raid-Leader oder Raid-Assist — ML-Checkbox wird für normale Mitglieder ausgeblendet)
- Empfängt alle Sync-Nachrichten vom ML und aktualisiert lokalen State

### Player *(geplant, noch nicht implementiert)*
- Kein Addon-Fenster
- Minimales Popup erscheint automatisch wenn ML ein Item freigibt
- Zeigt aktuelles Item mit Tooltip
- Prio-Buttons (klick → postet automatisch ins Raid-Chat)
- Roll-Button (führt `/roll` aus)
- Interaktion nur über Chat — Addon parst Eingaben selbst

---

## ML-Erkennung

**Funktion:** `GL.IsMasterLooter()` — `src/Util.lua:210`

```lua
function GL.IsMasterLooter()
    if GuildLootDB.settings.isMasterLooter == true then return true end
    if GuildLootDB.settings.dungeonMode    == true then return true end
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" and not IsInGroup() then return true end
    return false
end
```

| Bedingung | Ergebnis |
|-----------|----------|
| `settings.isMasterLooter = true` | ML |
| `settings.dungeonMode = true` | ML (Dungeon-Modus) |
| Solo in Raid-Instanz | ML (automatisch) |
| Sonst | Observer |

---

## ML-exklusive Aktionen

Nur ML kann diese Funktionen aufrufen (Guard: `if not GL.IsMasterLooter() then return end`):

- `Loot.ReleaseItem` — Item freigeben
- `Loot.AssignLoot` / `Loot.AssignLootConfirm` — Loot zuweisen
- `Loot.AssignAllWinners` — Alle Gewinner zuweisen
- `GL.StartContainer` / `GL.CloseContainer` — Session starten/schließen
- `GL.EnsureRaidMeta` — RaidMeta-Eintrag anlegen (Comm-Broadcast)
- Alle `Comm.Send*`-Funktionen werden nur vom ML aufgerufen

---

## ML-Handover Flow

### Schritt 1 — Observer beantragt ML

Observer klickt ML-Checkbox → `GL.TryClaimML()` → `Comm.SendMLRequest(claimantName)`

```
Observer → RAID/PARTY: ML_REQUEST <claimantName>
```

### Schritt 2a — Aktueller ML akzeptiert

ML sieht Popup "X möchte ML werden. Übergeben?" → klickt "Ja":

```lua
-- Core.lua:780 (OnCommMLRequest → OnAccept)
GuildLootDB.settings.isMasterLooter = false
GL.Comm.SendMLAnnounce(claimantName)
```

```
ML → RAID/PARTY: ML_ANNOUNCE <claimantName>
```

**Wichtig:** ML setzt `isMasterLooter = false` lokal, BEVOR die Announce rausgeht.
Die eigene Announce-Nachricht wird durch den Self-Filter blockiert — ML empfängt
`OnCommMLAnnounce` **nicht** für sich selbst.

### Schritt 2b — Aktueller ML lehnt ab

ML klickt "Nein" → `Comm.SendMLDeny(claimantName)`

```
ML → RAID/PARTY: ML_DENY <claimantName>
```

Observer empfängt `OnCommMLDeny` → `settings.isMasterLooter = false`, `GL.UI.Refresh()`

### Schritt 3 — Alle empfangen ML_ANNOUNCE

`OnCommMLAnnounce(newMLName)` — `src/Core.lua:746`:

```lua
GuildLootDB.currentRaid.mlName = newMLName
if UnitName("player") == newMLName then
    GuildLootDB.settings.isMasterLooter = true
else
    GuildLootDB.settings.isMasterLooter = false
end
GL.UI.Refresh()
```

| Empfänger | isMasterLooter | mlName | UI |
|-----------|---------------|--------|-----|
| Neuer ML | `true` | newMLName | Refresh |
| Alter ML | `false` | newMLName | Refresh |
| Andere OBS | `false` | newMLName | Refresh |

**Ausnahme:** Alter ML hat Self-Filter aktiv → empfängt ML_ANNOUNCE nicht →
`OnCommMLAnnounce` wird für ihn **nicht** ausgeführt.

---

## Bekannte Probleme

### Bug: Alter ML zeigt sich noch als ML im Titel

**Ursache:** Alter ML sendet `ML_ANNOUNCE`, filtert die eigene Nachricht aber heraus
(Self-Filter). `OnCommMLAnnounce` wird nicht ausgeführt → `settings.isMasterLooter`
bleibt `true` → UI zeigt ihn weiterhin als ML.

**Workaround aktuell:** Keiner — ML muss Addon manuell neu öffnen oder `/reload`.

**Möglicher Fix:** ML setzt `isMasterLooter = false` und ruft `GL.UI.Refresh()` direkt
im `OnAccept`-Handler auf, bevor `SendMLAnnounce` geschickt wird. Dann braucht er
die eigene Announce-Nachricht nicht zu empfangen.

---

### Bug: Neuer ML muss Addon neu öffnen

**Ursache:** Unklar — `OnCommMLAnnounce` beim neuen ML sollte `isMasterLooter = true`
setzen und `GL.UI.Refresh()` aufrufen. Zu bestätigen im Live-Test ob die Nachricht
ankommt und der Refresh greift.

---

## UI-Anzeige

**ML-Checkbox Label** — `UI.RefreshMLButton()` — `src/ui/UI.lua:608`

| Zustand | Anzeige |
|---------|---------|
| Spieler ist ML | Checkbox gecheckt, Label "ML" |
| Anderer Spieler ist ML | Checkbox ungecheckt, Label "ML: \<Name\>" |
| Kein ML bekannt | Checkbox ungecheckt, Label "ML" |

ML-Name kommt aus `GuildLootDB.currentRaid.mlName` (wird in `OnCommMLAnnounce` gesetzt).

---

## currentItem bei ML-Wechsel

`currentItem` wird bei ML-Handover **nicht automatisch geleert**. Es bleibt erhalten
bis ein neuer Assign, Trash oder manuelles Clear erfolgt. Der neue ML sieht das
aktive Item erst nach einem Refresh oder wenn der alte ML es explizit neu aktiviert.

---

## Live-Test Checkliste

Zu prüfen mit zwei Clients (ML + OBS):

- [ ] ML gibt ML ab → alter ML: isMasterLooter sofort false? UI aktuell?
- [ ] ML gibt ML ab → neuer ML: isMasterLooter sofort true? UI aktuell?
- [ ] ML gibt ML ab → andere OBS: mlName korrekt im Label?
- [ ] OBS beantragt ML → ML sieht Popup?
- [ ] ML lehnt ab → OBS: Meldung erscheint?
- [ ] ML akzeptiert → beide Seiten sofort korrekt ohne Reload?
- [ ] currentItem aktiv während Handover → was passiert?
