# Attendance Phase 1a + 1c — In-Game Test-Checkliste

**Branch:** `feat/attendance`
**TOC:** 1.0.3.57
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

**Erwartet ohne Season:** Leerzustand „Noch keine Season angelegt. / Oben auf \"New Season\"."

---

## 2 — Season-Kopfzeile

Die Kopfzeile hat jetzt dieselben Knöpfe wie der Raid-Tab, und der Dropdown **wählt** eine
Season nur aus, statt sie zu öffnen — beendete Seasons lassen sich damit ansehen, ohne sie
wieder aufzunehmen.

- [ ] **Alle Knöpfe liegen innerhalb des Fensterrahmens** — mit zehn Knöpfen (inkl. Export/
      Import) reichte eine Zeile nicht mehr. Zeile 1: Dropdown, Start, Ende, `[New Season]`,
      `[Resume]`, `[Rename]`. Zeile 2: links der Kader-Block, rechts davon ab `New Seasons`
      linker Kante `[Export]` `[Import]` `[Delete]` `[Roster lesen]`. Nichts schwebt über
      den Rand hinaus
- [ ] Mit aktivem orangem „→ Roster lesen"-Hinweis: der Kader-Zähler stößt **nicht** mit
      `[Export]` zusammen (beide teilen sich Zeile 2, links/rechts) — falls doch, Bescheid geben

- [ ] **[New Season]** → Popup, Name vorbelegt mit `Season JJJJ-MM` → Anlegen; die neue Season
      ist danach ausgewählt
- [ ] Läuft eine Season, heißt der Knopf **[Close Season]** und beendet sie; die Ansicht bleibt
      auf derselben Season stehen und zeigt sie als `(beendet)`
- [ ] Season-Dropdown zeigt alle Seasons, neueste zuerst, beendete mit `(beendet)`;
      die **laufende** Season ist orange hervorgehoben — seit der Dropdown nur auswählt,
      wäre sonst nicht erkennbar, in welche gerade aufgezeichnet wird
- [ ] Eine **beendete** Season auswählen zeigt ihre Matrix — **ohne** Rückfrage und ohne sie
      zu öffnen (früher kam sofort „Wieder aufnehmen?")
- [ ] **[Resume]** ist nur bei einer ausgewählten, beendeten Season aktiv → fragt
      „Wieder aufnehmen?" und beendet dabei die laufende
- [ ] Bei einer **beendeten** Season ohne Kader baut sich die Liste **aus den Sessions** —
      alle, die im Zeitraum geraidet haben, als ein Block ohne Kader/Gast-Trennung
- [ ] Der orange Hinweis „→ Roster lesen" erscheint dort **nicht** mehr (kein Mangel)
- [ ] **[Roster lesen]** funktioniert trotzdem auch bei einer beendeten Season — der Kader landet
      in genau der ausgewählten. Ohne das hätte eine nachgetragene alte Season gar keinen.
      Der Roster ist dann zwangsläufig der von heute.
- [ ] **Startdatum** links neben [Neue Season] ist klickbar → Popup „TT.MM.JJJJ",
      vorbelegt mit dem ältesten vorhandenen Raid
- [ ] Unsinniges Datum (z. B. `32.13.2026`) → Print „Datum bitte als TT.MM.JJJJ angeben.",
      nichts ändert sich
- [ ] **Enddatum** rechts daneben: bei der laufenden Season steht dort `bis offen` —
      das ist der Normalfall, ein Enddatum ist **nicht** nötig
- [ ] Klick darauf setzt ein Enddatum; die Season gilt danach als beendet und der Dropdown
      zeigt `(beendet)`
- [ ] Ein Raid **am** Enddatum zählt noch dazu (das Ende liegt auf 23:59:59)
- [ ] Ende **vor** dem Start wird abgewiesen: „Enddatum konnte nicht gesetzt werden…"
- [ ] Nachtrag-Fall: alte Season anlegen, Startdatum aufs Vorjahr, Enddatum aufs Ende jener
      Season → sie sammelt keine jüngeren Raids mehr ein
- [ ] **[Rename]** → Popup mit dem aktuellen Namen vorbelegt und markiert; OK oder Enter
      übernimmt, der Dropdown zeigt den neuen Namen sofort
- [ ] Leerer Name (oder nur Leerzeichen) wird abgewiesen, der alte bleibt stehen
- [ ] Ohne Season sind **[Rename]** und **[Delete]** ausgegraut
- [ ] Session umbenennen im **Raid-Tab** funktioniert unverändert — beide nutzen jetzt
      denselben Dialog (`UI.ShowRenameDialog`)
- [ ] **[Delete]** erster Klick → roter Text `Sure?`; **nicht** klicken, 3 s warten →
      springt auf `Delete` zurück
- [ ] [Delete] zweimal schnell → Season weg. **Raid-Sessions und Loot bleiben erhalten**
      (im Raid-Tab gegenprüfen!)
- [ ] Ohne Season ist [Delete] ausgegraut

---

## 3 — Rang-Dropdown

Kein „Kader:"-Label mehr davor — die Zeile beginnt direkt mit dem Dropdown, linksbündig zur
Season-Zeile darüber. Die „Ab Rang (und höher)"-Kurzform ist entfallen, nur noch Einzelauswahl.

- [ ] Dropdown hat **nur noch einen Abschnitt**: „Einzeln an/aus" — kein zweiter Titel darüber
- [ ] Häkchen togglet einen einzelnen Rang, Menü bleibt offen (Mehrfachauswahl in einem Zug)
- [ ] Nach jeder Filteränderung erscheint rechts vom Zähler der orange Hinweis
      **„→ Roster lesen"** — und der Kader ändert sich **noch nicht** (gewollt)
- [ ] Nach frischem Login steht kurz „lädt…" im Dropdown, bis die Rang-Namen da sind
- [ ] Dropdown und Zähler-Zeile sind **linksbündig** unter der Season-Zeile ausgerichtet

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
- [ ] **BIS-Stern**: Item mit Prio 1 vergeben → in der Zeile des Gewinners erscheint ein
      kleine **Krone** in der Zelle (dieselbe wie beim Raidleiter), in der **Bossspalte** und in der **Abend-Spalte**
- [ ] Item mit Prio 2 (OS) erzeugt **keinen** Stern
- [ ] Der Stern wird nicht gespeichert, sondern beim Zeichnen aus dem Loot-Log abgeleitet:
      ein **nachträglich** vergebenes Item erscheint sofort, ohne dass der Kill angefasst wird
- [ ] Beim Blättern bleiben keine Sterne in wiederverwendeten Zeilen stehen
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
- [ ] **Tooltip** auf einer Bossspalte zeigt den vollen Bossnamen, Datum, Uhrzeit und
      den Schwierigkeitsgrad (`N`/`H`/`M`)
- [ ] Bossköpfe sind nach Schwierigkeitsgrad **dezent hinterlegt**: N grün, H blau, M lila.
      Erkennbar wenn man hinsieht, aber kein Blickfang — falls zu kräftig oder zu blass,
      sind es die Werte in `DIFF_BG` (letzter Wert je Zeile = Deckkraft)
- [ ] Abend mit **gemischten** Difficulties (H→M gewechselt): die eingeklappte Spalte hat
      **keine** Tönung, erst die aufgeklappten Bossspalten zeigen ihre je eigene
- [ ] Über der aufgeklappten Gruppe steht der **Session-Name in Langform**; ist er breiter
      als die Gruppe, wird er gekürzt und der Tooltip zeigt ihn ganz
- [ ] Klick auf den Session-Namen klappt die Gruppe wieder zu
- [ ] Beim Auf- und Zuklappen **springt die Matrix nicht** — das Namensband bleibt stehen
- [ ] Tooltip auf einer eingeklappten Spalte sagt „N Bosse — klicken zum Aufklappen"
- [ ] Der aufgeklappte Abend rutscht ans **linke Ende** des Fensters (sonst schöbe er seine
      eigenen Spalten aus dem Sichtbereich)
- [ ] Senkrechte **Trennstriche** laufen durch die ganze Tabelle, nicht nur im Kopf:
      kräftig beim Wechsel des Raid-Tags, heller beim Wechsel der **Raidinstanz**
      innerhalb eines Abends (z. B. Dazar'alor → Castle Nathria)
- [ ] Mehrere Durchläufe **derselben** Instanz auf N/H/M bekommen **keinen** Strich —
      die unterscheidet die Tönung
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

## 9 — Export & Import (Raids nachtragen)

Export liefert eine CSV mit **einer Zeile je Teilnehmer und Bosskill**. Der Import ordnet über
das **Datum** zu — nicht über die ausgewählte Season.

- [ ] **[Export]** öffnet das Textfenster; die erste Spalte sagt den Zeilentyp:
      `Season,<Name>,<Start>,<Ende>,<Gilde>`, dann `Rank,<Index>`, `Roster,<Name>,<Klasse>`
      und `Kill,<Datum>,<Zeit>,<Instanz>,<Diff>,<Boss>,<Spieler>,<BIS>`
- [ ] Die Season-Stammdaten stehen wirklich drin — ohne sie ließe sich die Season anderswo
      nicht wiederherstellen; „Mark All" + Strg+C kopiert alles
- [ ] Ein BIS-Gewinn steht als `x` in der letzten Spalte
- [ ] **[Import]** öffnet dasselbe Fenster leer mit einem [Import]-Knopf
- [ ] Export in eine **frische DB** (oder zu einem Gildenkollegen) einspielen → die Season
      wird angelegt, mit Fenster, Rang-Filter und Kader; die **laufende** Season bleibt offen
- [ ] Exportierten Text unverändert wieder einfügen → Chat meldet `0 Bosskills`, alles
      übersprungen; die Matrix ändert sich nicht
- [ ] Eine Zeile duplizieren, Datum auf einen neuen Tag setzen, importieren → neue Spalte
      erscheint, der Spieler bekommt seine Zelle
- [ ] `x` in der BIS-Spalte einer nachgetragenen Zeile → Krone erscheint, obwohl die
      importierte Session **keinen** Loot-Log hat
- [ ] Kaputte Zeilen (Datum, Zeit oder Spieler fehlt) werden gezählt und gemeldet, nicht
      importiert
- [ ] Importierte Abende tauchen auch im **Raid-Tab** auf, als Session `Import <Datum>`
      ohne Loot
- [ ] Liegt das Datum außerhalb jedes Season-Fensters, erscheint der Abend nirgends —
      Startdatum der Season entsprechend zurücksetzen

## 10 — Einträge löschen (Testleichen aufräumen)

Löschen läuft zweistufig über **zwei verschiedene Tasten**: Rechtsklick auf den Spaltenkopf fragt
(`Sure?` in Rot), ein **Linksklick** innerhalb von 4 s führt aus. Zwei gleiche Klicks ließen sich
versehentlich durchziehen, ein Tastenwechsel nicht. Nichts davon fasst den **Loot** an.

- [ ] Rechtsklick auf eine **Bossspalte** → `Sure?`; 4 s warten → Beschriftung kommt zurück
- [ ] Rechtsklick, dann **Linksklick** → genau dieser Bosskill verschwindet, die anderen bleiben
- [ ] Zweiter **Rechtsklick** statt Linksklick nimmt die Frage zurück, löscht nicht
- [ ] War jemand **nur** bei diesem Kill dabei, ist er danach auch aus der Abend-Spalte raus
- [ ] Letzter Kill eines Raids gelöscht → die ganze Spalte verschwindet
- [ ] **Loot bleibt**: Session im Raid-Tab gegenprüfen, der Loot-Log ist unverändert
- [ ] Rechtsklick auf eine **Datumsspalte ohne Bosskills** (abgebrochener Abend, Testleiche)
      → nach Bestätigung ist die Session weg
- [ ] Hat diese Session Loot, bleibt sie stehen und der Chat nennt den Grund
      („Session kept — it has loot.")
- [ ] Die **laufende** Session lässt sich nicht löschen („session is running")
- [ ] **Altdaten ohne Bosskill-Tracking** (Raids von vor Phase 1b): die Spalte ist nicht
      aufklappbar, lässt sich aber direkt löschen — dahinter steht genau ein Eintrag
- [ ] Rechtsklick auf eine eingeklappte Spalte mit **mehreren** Kills tut nichts (mehrdeutig) —
      erst aufklappen, dann die einzelne Bossspalte löschen
- [ ] Linksklick funktioniert unverändert zum Auf- und Zuklappen
- [ ] Tooltip nennt den Rechtsklick, wo er möglich ist

## 11 — Blättern & Leerzustände

- [ ] Bei mehr Abenden als Spalten passen: `<` / `>` erscheinen mit Anzeige `1–8/14`
- [ ] `<` ist auf der ersten Seite ausgegraut, `>` auf der letzten
- [ ] Fenster **schmaler ziehen** → weniger Spalten, Blättern passt sich an
- [ ] Season wechseln → Blätter-Position springt auf die neuesten Abende zurück
- [ ] Leerzustand nur noch, wenn wirklich niemand da ist: „Niemand in dieser Season."
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
