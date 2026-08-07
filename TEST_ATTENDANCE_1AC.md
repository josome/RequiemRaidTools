# Attendance Phase 1a + 1c — In-Game Test-Checkliste

**Branch:** `feat/attendance`
**TOC:** 1.0.3.17
**Was neu ist:** Season-Datenmodell (`Core_Season`), Gilden-/Season-Roster (`Core_Guild`),
Attendance-Aggregat (`Core_Attendance`), Attendance-Tab + Season-Kopfzeile
(`UI_AttendanceTab`, `UI_SeasonControls`). Tab-Slot 5 heißt jetzt **Attendance** —
`UI_PlayerTab.lua` ist dafür aus der TOC genommen.
Dazu Phase 1b: `GL.RecordKillAttendance` zeichnet jeden Bosskill einzeln auf und zieht
Nachrücker in die Abend-Liste nach (Punkt 6). Und die Boss-Spalten im Tab: eine Abend-Spalte
lässt sich per Klick in ihre Bosskills aufklappen (Punkt 7).

---

## Zwei Stolpersteine vorab

Beide führen zu einem **leeren Tab, der wie ein Defekt aussieht** — sind aber gewolltes Verhalten:

1. **„Roster lesen" muss gedrückt werden.** `season.roster` ist ein Schnappschuss.
   `GetSeasonRoster` liest nur daraus und fasst die Gilden-API nicht an. Ohne Knopfdruck
   ist der Kader leer.
2. **Die Session muss im Season-Zeitfenster liegen.** Eine frisch angelegte Season startet
   heute und schließt damit alle älteren Raids aus. Fix: aufs **Startdatum** in der Kopfzeile
   klicken — es ist mit dem ältesten vorhandenen Raid vorbelegt, ein Klick auf „Setzen" reicht.

---

## Vorbereitung

- [ ] Branch `feat/attendance` ist ausgecheckt (Symlink Repo → AddOns), `/reload`
- [ ] `/reqrt devmode` an — schaltet die Diagnose-Ausgabe „gemeldet/gelesen/Kader" frei
- [ ] Im **Gildenfenster** „Offline-Mitglieder anzeigen" **aktivieren**
      (sonst schneidet der Client den Roster ab — genau das prüft Punkt 4)

---

## 1 — Smoke-Test

- [ ] `/reload` läuft ohne Lua-Error durch (BugSack prüfen)
- [ ] `/reqrt` öffnet das Hauptfenster
- [ ] Tab-Slot 5 heißt **Attendance** und öffnet
- [ ] Die anderen Tabs (Loot · Log · Raid · Roll) öffnen weiterhin fehlerfrei

**Erwartet ohne Season:** Leerzustand „Keine Season aktiv. / Oben eine anlegen."

---

## 2 — Season-Kopfzeile

- [ ] **[Neue Season]** → Popup, Name vorbelegt mit `Season JJJJ-MM` → Anlegen
- [ ] Season-Dropdown zeigt die neue Season; ältere Seasons darunter, neueste zuerst
- [ ] Eine **beendete** Season im Dropdown ist mit `(beendet)` markiert; Auswahl fragt
      „Wieder aufnehmen?" nach (die laufende wird dabei beendet)
- [ ] **Startdatum** links neben [Neue Season] ist klickbar → Popup „TT.MM.JJJJ",
      vorbelegt mit dem ältesten vorhandenen Raid
- [ ] Unsinniges Datum (z. B. `32.13.2026`) → Print „Datum bitte als TT.MM.JJJJ angeben.",
      nichts ändert sich
- [ ] **[Delete]** erster Klick → roter Text `Sure?`; **nicht** klicken, 3 s warten →
      springt auf `Delete` zurück
- [ ] [Delete] zweimal schnell → Season weg. **Raid-Sessions und Loot bleiben erhalten**
      (im Raid-Tab gegenprüfen!)
- [ ] Ohne Season ist [Delete] ausgegraut

---

## 3 — Rang-Dropdown („Kader:")

- [ ] Dropdown hat **zwei Abschnitte**: oben „Ab Rang (und höher)", darunter „Einzeln an/aus"
- [ ] Klick auf einen Rang oben setzt diesen Rang **und alles darüber** (GM/Offiziere stehen
      über Raider und müssen mit drin sein)
- [ ] Der Dropdown-Text zeigt danach den **niedrigsten** aktiven Rang
- [ ] „Einzeln an/aus": Häkchen togglet einen einzelnen Rang, Menü bleibt offen
- [ ] Nach jeder Filteränderung erscheint rechts vom Zähler der orange Hinweis
      **„→ Roster lesen"** — und der Kader ändert sich **noch nicht** (gewollt)
- [ ] Nach frischem Login steht kurz „lädt…" im Dropdown, bis die Rang-Namen da sind

---

## 4 — „Roster lesen" *(der interessanteste Punkt)*

- [ ] Klick auf **[Roster lesen]** → Chat: `Gildenroster gelesen: N Mitglieder, Kader: M.`
- [ ] Der orange Hinweis „→ Roster lesen" verschwindet, der Zähler „Kader N · weitere M" stimmt
- [ ] devMode-Zeile im Chat: `[Guild] gemeldet: A | gelesen: B | Kader: C`

> **Hier bitte die Zahlen notieren.** `gemeldet` (`GetNumGuildMembers`) vs. `gelesen`
> (tatsächlich gelieferte Zeilen) ist der bisher **unverifizierte** Punkt: ob der
> Client-Roster-Filter die API beschneidet, weiß niemand. Sind beide gleich → Entwarnung.

- [ ] Test mit **ausgeschaltetem** „Offline-Mitglieder anzeigen": kommt die orange Warnung
      „Gildenroster unvollständig gelesen: B von A Mitgliedern."? (Sie kommt **einmal pro
      Session** — für einen zweiten Versuch `/reload`.)
- [ ] Ohne aktive Season: „Gildenroster gelesen: N Mitglieder. Keine aktive Season — kein Kader gesetzt."

---

## 5 — Matrix

- [ ] Spaltenköpfe: `Raider` · `Att.%` · `Trial`, danach Datums-Spalten `TT.MM`
- [ ] **Kader-Block** oben, darunter der Trenner „weitere Teilnehmer", darunter der **Gast-Block**
      (hat in der Season geraidet, fällt aber nicht in den Kader)
- [ ] Klassenfarben stimmen — **auch bei aus der Gilde Ausgetretenen** (kommen aus
      `db.players[name].class`, nicht aus dem Gildenroster)
- [ ] Grüne Zelle = anwesend, dunkle Zelle = abwesend; `Att.%` passt zur Zeile
- [ ] **Trial-Checkbox** togglet und überlebt einen `/reload`
      (noch ohne Loot-Wirkung, das ist Phase 2)
- [ ] Trial-Spieler hat in Bosskills, die er **als Trial** bestritten hat, **türkise** statt
      grüner Zellen
- [ ] Haken **abnehmen** (= befördert): bereits aufgezeichnete Kills bleiben türkis,
      erst neue Kills sind grün — nach der Regel „kein Trial mehr nach 3 Raids" darf die
      Beförderung ältere Raids der Season nicht umdeuten
- [ ] Haken **setzen** färbt **nichts** rückwirkend um: Kills von vor dem Haken bleiben grün.
      Nur Kills ab jetzt werden türkis

---

## 6 — Bosskill landet in der Matrix *(Regressionstest)*

Der Bug war: solo blieb `currentRaid.participants` leer, der Kill hatte keine Teilnehmer und
tauchte in der Matrix gar nicht auf. Gefixt durch `GL.EnsureRaidParticipants`.

- [ ] **Solo** in eine Raid-Instanz, Session starten, einen Boss legen
- [ ] Attendance-Tab: eigene Zeile hat eine **grüne Zelle** in der Spalte von heute
- [ ] Falls die Spalte fehlt: liegt die Session vor dem Season-Start? → Startdatum zurücksetzen

Seit Phase 1b wird jeder Bosskill einzeln aufgezeichnet und Nachrücker werden nachgezogen:

- [ ] **Zwei Bosse** hintereinander legen → beide landen in `raidMeta[id].kills`
      (SavedVariables oder `/reqrt dbinfo`)
- [ ] **Nachrücker**: jemand kommt erst zum zweiten Boss dazu → er ist in der Abend-Spalte
      **grün** (früher fehlte er den ganzen Abend)
- [ ] Wer nach dem ersten Boss **geht**, bleibt in der Abend-Spalte grün — die Liste ist kumulativ

---

## 7 — Boss-Spalten (aufklappen)

- [ ] Klick auf eine **Datums-Spalte** mit mehreren Bosskills klappt sie in Bossspalten auf
- [ ] Bossspalten sind **breiter** und zeigen den gekürzten Bossnamen (`Bloodbo…`)
- [ ] **Tooltip** auf einer Bossspalte zeigt den vollen Bossnamen, Datum und Uhrzeit
- [ ] Tooltip auf einer eingeklappten Spalte sagt „N Bosse — klicken zum Aufklappen"
- [ ] Der aufgeklappte Abend rutscht ans **linke Ende** des Fensters (sonst schöbe er seine
      eigenen Spalten aus dem Sichtbereich)
- [ ] Senkrechter **Trennstrich** im Kopf zeigt, wo ein Abend anfängt
- [ ] Nachrücker: in der **ersten** Bossspalte dunkel, ab seinem Kill grün — die Abend-Spalte
      des Nachbarabends bleibt unberührt
- [ ] Erneuter Klick klappt zu
- [ ] Abend **ohne** aufgezeichnete Kills (Altdaten) ist gedämpft dargestellt, Klick tut nichts,
      Tooltip sagt „Keine einzelnen Bosskills aufgezeichnet"
- [ ] **Season-Wechsel** setzt alle aufgeklappten Abende zurück
- [ ] Blättern mit aufgeklappten Spalten: Pager-Zählung (`1–8/14`) stimmt

## 8 — Raid-Tage statt Sessions

Eine Spalte ist ein **Raid-Tag**, nicht eine Session. Tagesgrenze ist der Raid-Reset um 7 Uhr.

- [ ] Session am **Folgetag fortsetzen** (anderer Raid) → **zwei** Spalten mit je eigenem Datum,
      nicht eine
- [ ] `Att.%` zählt beide Tage: wer nur an Tag 2 dabei war, hat 50 % statt 100 %
- [ ] **Zwei Raids an einem Tag** → **eine** Spalte, egal ob in einer oder zwei Sessions;
      beim Aufklappen stehen die Bosse beider Raids nebeneinander
- [ ] Fallen zwei Sessions auf einen Tag, nennt der Tooltip **beide** Namen (`Vormittag · Abend`)
- [ ] Kill **nach Mitternacht** (z. B. 01:30) landet noch in der Spalte des Vorabends
- [ ] Tooltip einer Bossspalte zeigt das Datum des **Kills**, nicht das des Abends —
      bei einer über Mitternacht laufenden Session also den Folgetag

## 9 — Blättern & Leerzustände

- [ ] Bei mehr Abenden als Spalten passen: `<` / `>` erscheinen mit Anzeige `1–8/14`
- [ ] `<` ist auf der ersten Seite ausgegraut, `>` auf der letzten
- [ ] Fenster **schmaler ziehen** → weniger Spalten, Blättern passt sich an
- [ ] Season wechseln → Blätter-Position springt auf die neuesten Abende zurück
- [ ] Leerzustand **kein Rang gewählt**: „Kein Rang für den Kader gewählt."
- [ ] Leerzustand **Season ohne Raids**: „Noch keine Raid-Abende in dieser Season. / Liegen die
      Raids davor? Dann das Startdatum der Season zurücksetzen."

---

## Ergebnis

- [ ] Alles grün → weiter mit **Phase 1b** (`RecordKillAttendance`: Nachrücker + Boss-Ebene)
- [ ] Sonst: Fundstellen hier notieren

### Gefunden

_(Zahlen aus Punkt 4 und alles Auffällige hier eintragen)_

| # | Was | Erwartet | Beobachtet |
|---|-----|----------|------------|
|   |     |          |            |
