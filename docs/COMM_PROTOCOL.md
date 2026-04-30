# RequiemRaidTools — Comm-Protokoll

Alle Gruppen-Nachrichten werden via `C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)` verschickt.
Format: `addonVersion|CMD|feld1|feld2|...` (Trennzeichen: `|`)

SESSION_SYNC ist eine Whisper-Serie (1:1) und kein Broadcast.

---

## Auslöser → Telegramme

| Auslöser | Seite | Telegramme |
|---|---|---|
| `PLAYER_LOGIN` (3s verzögert, kein ML, keine Session) | Observer | [`RAID_QUERY`](#raid_query) |
| `GROUP_ROSTER_UPDATE` / `RAID_ROSTER_UPDATE` (ML, Session aktiv) | ML | [`SESSION_START`](#session_start) |
| `GROUP_ROSTER_UPDATE` / `RAID_ROSTER_UPDATE` (kein ML, keine Session, max 1×/5s) | Observer | [`RAID_QUERY`](#raid_query) |
| `ENCOUNTER_END` (success=1, ML, Session aktiv) | ML | [`RAID_META`](#raid_meta) + [`ML_ANNOUNCE`](#ml_announce) |
| `PLAYER_REGEN_ENABLED` (ML, ausstehende Sync-Requests) | ML | [`SESSION_SYNC`](#session_sync-whisper-serie) (Whisper je Observer) |
| `PLAYER_REGEN_ENABLED` (Observer, pendingRaidQuery) | Observer | [`RAID_QUERY`](#raid_query) |
| ML startet Session (Button / `/reqrt start`) | ML | [`SESSION_START`](#session_start) + [`ML_ANNOUNCE`](#ml_announce) |
| ML schließt Session | ML | [`SESSION_END`](#session_end) |
| ML aktiviert Item (Loot-Fenster / Button) | ML | [`ITEM_ON`](#item_on) |
| ML bricht Item ab | ML | [`ITEM_OFF`](#item_off) |
| ML startet Roll | ML | [`ROLL_START`](#roll_start) |
| ML weist Loot zu | ML | [`ASSIGN`](#assign) |
| ML trasht Item | ML | [`LOOT_TRASH`](#loot_trash) |
| Spieler beantragt ML-Übernahme | Kandidat | [`ML_REQUEST`](#ml_request) |
| ML bestätigt Übernahme | ML | [`ML_ANNOUNCE`](#ml_announce) |
| ML verweigert Übernahme | ML | [`ML_DENY`](#ml_deny) |
| Observer empfängt `RAID_QUERY` (ML, kein Kampf) | ML | [`SESSION_SYNC`](#session_sync-whisper-serie) (Whisper) + [`ML_ANNOUNCE`](#ml_announce) |
| Observer empfängt `RAID_QUERY` (ML oder OBS im Kampf) | ML | *(Request gequeued bis `PLAYER_REGEN_ENABLED`)* |

---

## Gruppen-Telegramme

### ITEM_ON
**Richtung:** ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|ITEM_ON|link|category`  
**Größe:** ~80–120 Byte  
**Auslöser (Receiver):** `Loot.OnCommItemActivate(link, category)` → Player-Popup + Roll-Tab anzeigen

| Feld | Typ | Beispiel |
|---|---|---|
| link | Item-Link | `\|Hitem:212426\|h[Egg]\|h\|r` |
| category | string | `armor`, `weapons`, `trinket`, `other` |

---

### ITEM_OFF
**Richtung:** ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|ITEM_OFF`  
**Größe:** ~20 Byte  
**Auslöser (Receiver):** `Loot.OnCommItemClear()` → Popup + Roll-Tab leeren

---

### ROLL_START
**Richtung:** ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|ROLL_START|seconds|name1,name2,...`  
**Größe:** ~50–200 Byte  
**Auslöser (Receiver):** `Loot.OnCommRollStart(seconds, players)` → Roll-Button aktivieren, Countdown starten

| Feld | Typ | Beispiel |
|---|---|---|
| seconds | number | `30` |
| players | Kommaliste Kurznamen | `Myriella,Thorondis` |

---

### ASSIGN
**Richtung:** ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|ASSIGN|player|diff|link|category|quality|prio|boss|sessionID|raidID`  
**Größe:** ~150–250 Byte  
**Auslöser (Receiver):** `Loot.OnCommAssign(...)` → Gewinner anzeigen, Observer-DB aktualisieren

| Feld | Typ | Beispiel |
|---|---|---|
| player | realm-qualifiziert | `Myriella-Malfurion` |
| diff | string | `H`, `M`, `N` |
| link | Item-Link | `\|Hitem:212426\|h[Egg]\|h\|r` |
| category | string | `armor` |
| quality | number | `4` (Epic) |
| prio | number | `1` |
| boss | string | `Ulgrax the Devourer` |
| sessionID | string | `sess-01` |
| raidID | string | `raid-42` |

---

### RAID_QUERY
**Richtung:** Observer (Late-Joiner) → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|RAID_QUERY|inCombat`  
**Größe:** ~25 Byte  
**Auslöser (Receiver):** `GL.OnCommRaidQuery(sender, inCombat)` → ML antwortet mit SESSION_SYNC-Whisper + ML_ANNOUNCE

| Feld | Typ | Beispiel |
|---|---|---|
| inCombat | `0` / `1` | `0` |

---

### SESSION_START
**Richtung:** ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|SESSION_START|sessionID|label|startedAt|prioCfg`  
**Größe:** ~100–200 Byte  
**Auslöser (Receiver):** `GL.OnCommSessionStart(sessionID, label, startedAt, sender, prioCfg)` → Observer legt neue Session an

| Feld | Typ | Beispiel |
|---|---|---|
| sessionID | string | `sess-01` |
| label | string | `KW 18 2026` |
| startedAt | Unix-Timestamp | `1745964000` |
| prioCfg | serialisiert (s.u.) | `1:BiS:Best in Slot;1:Upgr:Upgrade;0::;0::;0::` |

**Prio-Config Format:** 5 Einträge durch `;` getrennt, je `active:shortName:description`  
Beispiel: `1:BiS:Best in Slot;1:Upgr:Upgrade;0::;0::;0::` (~50 Byte)

---

### SESSION_END
**Richtung:** ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|SESSION_END|sessionID|closedAt`  
**Größe:** ~55 Byte  
**Auslöser (Receiver):** `GL.OnCommSessionEnd(sessionID, closedAt)` → Observer schließt Session

---

### RAID_META
**Richtung:** ML → alle (nach Boss-Kill)  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|RAID_META|sessionID|raidID|tier|diff|startedAt|closedAt|participants|prioCfg`  
**Größe:** ~200–900 Byte (participants-abhängig)  
**Auslöser (Receiver):** `GL.OnCommRaidMeta(sessionID, raidID, meta, prioCfg)` → Observer speichert Kill-Daten, aktualisiert Prio-Config

| Feld | Typ | Beispiel |
|---|---|---|
| sessionID | string | `sess-01` |
| raidID | string | `raid-42` |
| tier | string | `Nerub-ar Palace` |
| diff | string | `H` |
| startedAt | Unix-Timestamp | `1745964000` |
| closedAt | Unix-Timestamp oder leer | `1745967600` |
| participants | Kommaliste realm-qualifiziert | `Myriella-Malfurion,Thorondis-Malfurion,...` |
| prioCfg | serialisiert (optional) | `1:BiS:Best in Slot;1:Upgr:Upgrade;0::;0::;0::` |

> **Hinweis:** `prioCfg` ist Feld 9 (optional). Fehlt es (ältere Addon-Version), bleibt die bestehende Config unverändert.

---

### LOOT_TRASH
**Richtung:** ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|LOOT_TRASH|link|sessionID|raidID`  
**Größe:** ~100–150 Byte  
**Auslöser (Receiver):** direkter DB-Eintrag in `trashedLoot` der Ziel-Session

---

### ML_ANNOUNCE
**Richtung:** aktueller oder neuer ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|ML_ANNOUNCE|mlName`  
**Größe:** ~45 Byte  
**Auslöser (Receiver):** `GL.OnCommMLAnnounce(mlName)` → alle setzen `mlName` in DB + Titelleiste

---

### ML_REQUEST
**Richtung:** ML-Kandidat → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|ML_REQUEST|claimantName`  
**Größe:** ~45 Byte  
**Auslöser (Receiver):** `GL.OnCommMLRequest(claimantName, sender)` → aktueller ML bekommt Übernahme-Anfrage

---

### ML_DENY
**Richtung:** aktueller ML → alle  
**Transport:** RAID / PARTY / SAY  
**Format:** `version|ML_DENY|claimantName`  
**Größe:** ~40 Byte  
**Auslöser (Receiver):** `GL.OnCommMLDeny(claimantName)` → Kandidat bekommt Absage

---

## SESSION_SYNC (Whisper-Serie)

**Richtung:** ML → einzelner Observer (1:1 Whisper)  
**Ausgelöst durch:** RAID_QUERY → `OnCommRaidQuery` auf ML-Seite  
**Nachfolge-Broadcast:** ML sendet danach `ML_ANNOUNCE` an die Gruppe

Die Serie besteht aus mehreren Whisper-Nachrichten im gleichen Format wie die Gruppen-Telegramme:

| Nachricht | Beschreibung |
|---|---|
| `SESSION_START` | Session-Metadaten + Prio-Config |
| `RAID_META` (1×) | pro gespeichertem Kill |
| `ASSIGN` (n×) | pro vergebenem Loot-Eintrag |
| `LOOT_TRASH` (n×) | pro weggetrashtem Item |

**Gesamtgröße:** ~500–5000 Byte (abhängig von Session-Länge)

---

## Bekannte Einschränkungen

| Problem | Status |
|---|---|
| `RAID_META` trug bis v0.5.5.5 keine Prio-Config | behoben ab v0.5.5.6 |
| `RAID_QUERY` antwortete ohne ML_ANNOUNCE | behoben ab v0.5.5.6 |
