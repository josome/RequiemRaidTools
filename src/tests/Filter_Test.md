# Filter Testdokumentation

**Datei:** `src/tests/Filter_Test.lua`  
**Framework:** [WoWUnit](https://www.curseforge.com/wow/addons/wowunit) (läuft in-game, kein externer Lua-Runner)  
**Suite-Name im WoWUnit-Fenster:** `ReqRT.Filter`

---

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Testziel](#testziel)
- [Teststrategie](#teststrategie)
- [Testfälle](#testfälle)
- [Was diese Tests nicht abdecken](#was-diese-tests-nicht-abdecken)
- [Tests erweitern](#tests-erweitern)

---

## Voraussetzungen

| Bedingung | Warum |
|-----------|-------|
| WoWUnit installiert | Test-Framework; ohne es gibt `if not WoWUnit then return end` die Datei sofort frei |
| `/reqrt devmode` aktiv | Schützt Produktiv-Nutzer; Tests registrieren sich gar nicht wenn devMode aus ist |
| `/reload` nach devMode-Toggle | Damit `GuildLootDB` korrekt initialisiert ist |

---

## Testziel

Integrationstest des Popup-Filter-Flows für Observer/Player-Mode:

```
OnCommItemActivate(link, category)  →  PopupFilterMatches  →  ShowPlayerPopup aufgerufen?
```

Geprüft wird: Wird `GL.UI.ShowPlayerPopup` aufgerufen oder geblockt, abhängig von `announceFilter` und Item-Typ?

---

## Teststrategie

`GuildLootDB` wird pro Test durch einen minimalen Stub ersetzt. `GetItemInfo` und `IsUsableItem` werden als Globals gemockt damit kein WoW-Client benötigt wird. `ShowPlayerPopup` wird durch einen Spy ersetzt der nur `called = true` setzt.

```
1. Arrange — Setup(): minimales GuildLootDB, announceFilter setzen, GetItemInfo mocken
2. Act     — Run(category): OnCommItemActivate aufrufen, Spy auf ShowPlayerPopup
3. Assert  — IsTrue/IsFalse auf den Spy-Wert
4. Cleanup — Teardown(): ClearCurrentItem, GuildLootDB wiederherstellen, MockRestore
```

**Wichtig:** `GetItemInfo`-Mock muss an Position 7 (itemSubType) einen Nicht-nil-Wert zurückgeben, sonst geht `OnCommItemActivate` in den asynchronen Stale-Branch und zeigt das Popup nie sofort an. Ausnahme: `testStale` testet genau diesen Pfad.

---

## Testfälle

### `testNone`

**Testet:** Kein `announceFilter` gesetzt → alle Items werden angezeigt

**Setup:** `announceFilter = nil`, Cloth-Item  
**Erwartet:** `ShowPlayerPopup` aufgerufen

---

### `testCloth`

**Testet:** `cloth = false` blockiert Cloth-Rüstung

**Setup:** `{ cloth = false }`, `itemSubType = "Cloth"`  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen

---

### `testLeather`

**Testet:** `leather = false` blockiert Leather-Rüstung

**Setup:** `{ leather = false }`, `itemSubType = "Leather"`  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen

---

### `testMail`

**Testet:** `leather = false` lässt Mail-Rüstung durch (Filter sind unabhängig)

**Setup:** `{ leather = false }`, `itemSubType = "Mail"`  
**Erwartet:** `ShowPlayerPopup` aufgerufen

---

### `testPlate`

**Testet:** `plate = false` blockiert Plate-Rüstung

**Setup:** `{ plate = false }`, `itemSubType = "Plate"`  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen

---

### `testTrinket`

**Testet:** `trinket = false` blockiert Trinket-Kategorie

**Setup:** `{ trinket = false }`, `category = "trinket"`  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen

---

### `testTrinketOn`

**Testet:** Kein Trinket-Filter → Trinket wird angezeigt

**Setup:** `{}`, `category = "trinket"`  
**Erwartet:** `ShowPlayerPopup` aufgerufen

---

### `testWeaponOn`

**Testet:** `nonUsableWeapon = false` lässt benutzbare Waffe durch

**Setup:** `{ nonUsableWeapon = false }`, `IsUsableItem → true`, `category = "weapons"`  
**Erwartet:** `ShowPlayerPopup` aufgerufen

---

### `testWeaponOff`

**Testet:** `nonUsableWeapon = false` blockiert nicht-benutzbare Waffe

**Setup:** `{ nonUsableWeapon = false }`, `IsUsableItem → false`, `category = "weapons"`  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen

---

### `testNeck`

**Testet:** `neck = false` blockiert Halsschmuck (via `itemEquipLoc`)

**Setup:** `{ neck = false }`, `itemEquipLoc = "INVTYPE_NECK"`  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen

---

### `testRing`

**Testet:** `ring = false` blockiert Ring (via `itemEquipLoc`)

**Setup:** `{ ring = false }`, `itemEquipLoc = "INVTYPE_FINGER"`  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen

---

### `testOther`

**Testet:** Unbekannter Item-Typ fällt in den `other`-Fallback

**Setup:** `{ other = false }`, `itemSubType = "Token"` (kein bekannter Typ)  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen

---

### `testStale`

**Testet:** `GetItemInfo` gibt nil zurück (Item nicht gecacht) → kein Popup sofort

**Setup:** `{}`, `GetItemInfo → nil`  
**Erwartet:** `ShowPlayerPopup` nicht aufgerufen (Popup zurückgehalten bis `GET_ITEM_INFO_RECEIVED`)

---

## Was diese Tests nicht abdecken

| Bereich | Warum nicht abgedeckt |
|---------|-----------------------|
| Asynchroner Popup nach `GET_ITEM_INFO_RECEIVED` | Benötigt WoW-Eventloop |
| `popupEnabled`-Setting | Guard liegt in `ShowPlayerPopup`, nicht in `PopupFilterMatches` |
| Roll- und Prio-Phase | Zuständigkeit anderer Suiten |

---

## Tests erweitern

```lua
function Tests:testMeinFall()
    Setup({ meinFilter = false })
    MockItem("SubType", "INVTYPE_XYZ")
    IsFalse(Run("category"))  -- oder IsTrue
    Teardown()
end
```
