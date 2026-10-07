# Factorio Gamble Mod

Factorio 2.0 Mod mit Space Age. Der Spieler setzt ein Item ein (bis zu 1 Stack), wählt ein Zielitem plus Menge, und ein Glücksrad-Fenster entscheidet ob er gewinnt. Kommunikation mit dem User auf Deutsch, locker und kurz. Er reagiert lieber auf Zwischenstände als alles vorher festzulegen.

## Spielregeln (entschieden)

- Einsatz: beliebiges Item, maximal 1 Stack
- Ziel: beliebiges Item + frei wählbare Menge, **maximal 1 Stack** (Stackgröße des Zielitems)
- **Der Einsatz ist immer weg**, egal ob Gewinn oder Niete. Bei Gewinn gibt es das Ziel.
- Tausch von höherwertig zu niedrigerwertig ist **nicht möglich** (z.B. Stack Inserter → Landfill gesperrt)
- Chance sinkt je größer der Wertunterschied ist, Mengen mit eingerechnet

## Chance

```
r = (Wert Ziel × Menge Ziel) / (Wert Einsatz × Menge Einsatz)

r < 1          → gesperrt
Chance = MAX / r
```

- MAX Standard 0,75, MIN Standard 1/100.000
- Beide sind **Mod-Einstellungen** (runtime-global), der User will sie später anpassen können
- Weil der Einsatz immer weg ist, verliert man mit `MAX / r` im Schnitt immer gleich viel (bei 0,75 also 25 % vom Einsatzwert). Das ist gewollt.
- Optional: Hausvorteil als eigene Einstellung statt über MAX

## Itemwerte

Factorio hat keine Itemwerte, die Mod berechnet sie selbst beim Laden (on_init / on_configuration_changed) und speichert sie in `storage`. Muss auch mit Items aus anderen Mods klappen.

1. Rohstoffe bekommen Grundwerte: Erze, Kohle, Stein, Holz, Fisch, Wasser, Rohöl, Space Age: Asteroidenbrocken, Gleba-Früchte usw. Grundwerte in einer gut editierbaren Tabelle, die werden im Spiel noch nachjustiert.
2. Iterativ über alle Rezepte: Wert Produkt = (Summe Zutatenwerte + Aufschlag für Craftzeit) / Ausgabemenge (Wahrscheinlichkeiten bei Produkten berücksichtigen). Wiederholen bis stabil.
   **Fortschritt (vom User gewünscht):** Spätere Items sind automatisch mehr wert. Zeit zum Freischalten zählt mit: Endwert = Materialwert × (1 + Gewicht × log10(1 + Forschungszeit / 1000 s)). Forschungszeit = Laborsekunden aller Technologien bis zum Rezept, inkl. Vorgänger, inkl. der Forschung für das benötigte Gebäude und die Zutaten (Maximum). Gewicht ist Mod-Einstellung (Standard 1,5). Weitergereicht wird nur der Materialwert, damit sich der Faktor nicht über Ketten aufmultipliziert.
3. Mehrere Rezepte für ein Item → billigstes nehmen (nach Endwert, also inkl. Fortschritt: Gießerei-Rezepte verlieren dadurch gegen die Nauvis-Rezepte)
4. Ignorieren: Recycling-Rezepte (inkl. Schrott-Recycling), Fässer leeren, versteckte Rezepte, Rezepte ohne Zutaten, alles was Schleifen erzeugt. Fässer **füllen** zählt (sonst hätten gefüllte Fässer keinen Wert, Schleife entsteht erst durchs Leeren)
5. Items ohne berechenbaren Wert sind nicht wählbar
6. **Qualität:** Multiplikator pro Stufe
7. **Frische (Spoilage):** linear. 100 % frisch = 100 % Wert, 25 % frisch = 25 % Wert. Ein Stack hat einen gemeinsamen Frischewert.
8. Debug-Befehl, der alle Werte ausgibt (Konsole oder Datei), damit der User prüfen kann ob die Werte sich richtig anfühlen

Grobes Gefühl: 1 rote Wissenschaft → 100 Promethium-Wissenschaft soll ungefähr bei der Minimalchance landen.

## Fenster

Eigenes GUI-Fenster:
- Slot für den Einsatz
- Zielitem-Auswahl + Mengenfeld
- Live-Anzeige der Chance (oder rot "Nicht möglich")
- Knopf "Drehen"
- Darunter die Glücksanimation

**Animation im Fenster, keine Kamera** (User mag die Kamera-Lösung nicht). Factorio-GUIs können keine Bilder drehen. Zur Wahl:
- **Walze** (Empfehlung): Reihe von Feldern rauscht seitlich durch wie beim Case Opening, Gewinnfelder zeigen das Zielitem, Nieten sind grau/leer, bremst ab
- **Balken:** grüner Bereich auf einem Balken, Zeiger rauscht drüber und bleibt stehen

Ergebnis wird **vor** der Animation festgelegt, die Animation ist nur Show. Zustand in `storage`, damit Speichern mitten im Dreh und Multiplayer nicht kaputt gehen. Zufall über `game.create_random_generator()`.

## Noch offen

- ~~Walze oder Balken?~~ → **Walze** (User: "weiter mit Schritt 4, der Walze")
- ~~Unter der Minimalchance~~ → **gesperrt** (User: "weiter" auf Empfehlung, 2026-10-07)
- Zugang: vorerst Shortcut-Leiste + Hotkey ALT+G. Eigenes Gebäude ("Glücksautomat") kann später dazukommen.

## Technik

- Factorio 2.0 API, `info.json` mit Abhängigkeit auf `space-age`
- 2.0 nutzt das globale `prototypes` (nicht mehr `game.item_prototypes`) und `storage` (nicht mehr `global`)
- API vor Benutzung gegen https://lua-api.factorio.com/latest/ prüfen, nicht aus dem Gedächtnis raten
- Mod-Ordner unter Windows: `%APPDATA%\Factorio\mods\`
- **Versionierung (User-Wunsch):** Jeder Stand, den der User testet, bekommt eine neue Version in `info.json`, einen Eintrag in `changelog.txt` (englisch, Factorio-Format wie bei kamikaze-robot) und einen Git-Commit „Version x.y.z“ mit Tag `vx.y.z`. Nie eine Versionsnummer wiederverwenden
- Installiert ist die Mod per Junction `%APPDATA%\Factorio\mods\item-gamble` → dieser Ordner
- Claude Code kann das Spiel nicht spielen, aber headless testen (eigene config.ini mit eigenem write-data, `--create` + `--benchmark`): Wertberechnung und Bericht laufen so ohne Spieler. GUI und Chat-Befehle testet der User im Spiel und schickt Fehler bzw. `factorio-current.log` zurück.

## Reihenfolge

1. Mod-Grundgerüst (info.json, control.lua, settings.lua)
2. Wertberechnung + Debug-Ausgabe, User prüft die Werte im Spiel
3. Fenster mit Einsatz, Ziel, Chance-Anzeige
4. Animation
5. Feintuning der Grundwerte und Chancen

## Stand (2026-10-07)

Schritt 1 + 2 fertig. 0.1.0 im Spiel getestet (läuft, auch mit Textplates/RateCalculator/MPP). 0.2.0 mit Fortschrittsfaktor headless getestet.

- `scripts/base-values.lua`: Grundwerte + Zeitaufschlag (0,1 pro Sekunde) + ignorierte Kategorien/Untergruppen
- `scripts/values.lua`: Berechnung (Bellman-Ford, billigstes Rezept), Nettomengen bei Katalysatoren (Kovarex, Pentapod-Ei), Nebenprodukte mit festem Grundwert und zurückgegebene Katalysatoren (heißes Fluoroketon beim Quantenprozessor) werden gutgeschrieben, sonst teilen sich Produkte die Kosten zu gleichen Teilen. Abfrage-API für Schritt 3: `unit`, `stack` (Qualität + Frische), `is_selectable`, `chance`
- Qualität: Wert × Einstellung^level (legendär = level 5), Standard 2
- Fortschritt: Faktoren bei Gewicht 1,5: Nauvis-Grundkram ×1, grün ×1,2, blau ×3,1, Planeten-Wissenschaft ×4,6, Kryo ×5,35, Promethium ×5,6. Ändert man das Gewicht im Spiel, wird automatisch neu gerechnet
- Henne-Ei bei Gebäuden: Pentapod-Ei hat Grundwert (Biokammer braucht Eier, Eier brauchen Biokammer), Biter-Ei ebenfalls (Rezept ohne Zutaten)
- Biter-Ei und Promethium-Brocken (je 165) sind so gewählt, dass 1 rot → 100 Promethium ≈ Minimalchance
- Rohstoffe aus anderen Mods ohne Rezept bekommen automatisch `auto_item`/`auto_fluid`
- `/gamble-values [suche]` schreibt `script-output/item-gamble/values.txt`, `/gamble-recalc` (Admin) rechnet neu
- Bekannte Kandidaten fürs Feintuning: Samen (≈ 126, weil 2 % Ausbeute die halben Kosten tragen), Kryo-Wissenschaft (≈ 38, billiger als Militär), Weltraum-Wissenschaft (≈ 4,9, kaum über rot), Fusion-Ausrüstung/Spidertron sehr teuer

### Schritt 3 (0.4.0): Fenster

User-Feedback zu 0.3.0: zwei Fenster (eigenes + Inventar) sind eins zu viel, und ein Stack musste komplett rein. **Keine Slider**, Bedienung wie im restlichen Spiel.

- Ein Fenster: links das eigene Inventar als Slot-Raster, rechts Einsatz, Ziel, Chance, Drehen. Ist `player.opened`, E/Esc schließen es
- Inventar-Slot: Linksklick = ganzen Stack einsetzen, Rechtsklick = ein Item. Einsatz-Slot: Linksklick = alles zurück, Rechtsklick = eins zurück. Andere Sorte/Qualität ersetzt den Einsatz
- Items bleiben bis zum Drehen im Inventar, das Raster zeigt die Restmenge und hebt beteiligte Slots hervor. Beim Drehen wird zuerst aus den angeklickten Slots genommen; die Frische ist der Durchschnitt genau dieser Items
- Items ohne Wert / Rüstung mit Ausrüstung sind im Raster ausgegraut (Tooltip nennt den Grund)
- Ziel: `choose-elem-button` mit Qualität + Zahlenfeld (max 1 Stack)
- `scripts/gamble.lua` ohne GUI: `add_stake`, `remove_stake`, `reserved`, `evaluate`, `spin` (Ergebnis in `data.last` bevor angezeigt wird, Grundlage für Schritt 4). Migration räumt das Einsatz-Inventar aus 0.3.0 ab und gibt Items zurück
- Drehen zeigt das Ergebnis vorerst sofort als Text, die Walze kommt in Schritt 4
- Headless getestet mit nachgebautem Spieler (Klicklogik, Stack-Grenze, Qualität, Frische, Abzug beim Drehen). GUI nur statisch geprüft

### Schritt 4 (0.5.0): Walze

- `scripts/reel.lua`: Planung (Symbole, Stopp-Feld, Weg) und Position pro Tick, kubisches Abbremsen über 270 Ticks, 50–64 Felder Weg. Gewinnfelder-Dichte nur Optik (8–45 %), bei Niete oft ein Gewinnfeld direkt daneben
- Pixelweises Laufen: Scroll-Pane ohne Scrollbalken schneidet ab, das erste Slot-Feld bekommt einen negativen `left_margin` (Vanilla nutzt negative Ränder selbst)
- `gamble.spin` zieht den Einsatz ab und würfelt, `gamble.finish` zahlt aus, wenn die Walze steht (`gui.tick` über `storage.spins`). Schließen mitten im Dreh zahlt sofort aus und meldet im Chat
- Nach einem Mod-Update werden offene Fenster neu aufgebaut (`gui.reopen_all`)
- Headless getestet: 2000 simulierte Drehs landen immer auf dem Ergebnisfeld, Dreh/Auszahlung mit nachgebautem Spieler. Ob das Abschneiden im Scroll-Pane wirklich so aussieht, zeigt erst der Test im Spiel

### 0.6.0: Bedienung wie Kiste, Zielwahl wie Kombinator

User-Feedback zu 0.5.0: Walze soll ganzzahlig bzw. in die nächste Feldmitte fallen; das Möchtegern-Inventar ist Mist, es soll wie eine Kiste/ein Gebäude eine Erweiterung des Inventars sein; Zielwahl wie beim Konstanten Kombinator mit Menge in der Auswahl; im Editor mit angehaltener Zeit friert alles ein; Gewinnfelder sollen gleichmäßigen Abstand haben.

- Einsatz = `game.create_inventory(1, titel)` pro Spieler, geöffnet über `player.opened`. Factorio zeigt das eigene Inventar daneben, Vanilla-Bedienung komplett. Das Panel hängt als `player.gui.relative` mit Anker `script_inventory_gui` rechts daran. Schließen (E/Esc/ALT+G) gibt den Einsatz zurück
- Refresh über `on_player_main_inventory_changed` + `on_player_cursor_stack_changed` (jede Vanilla-Bewegung ändert eins davon)
- Zielauswahl: eigenes Fenster mit Gruppen-Tabs (`image_tab_slot`), Item-Raster je Untergruppe (`filter_slot_table`), Qualitätsknöpfe, Mengenfeld, Übernehmen (auch Doppelklick/Enter). Keine Suche: ein Mod kann nur interne Namen durchsuchen, deutsche Begriffe würden nichts finden
- Walze: Gewinnfelder im festen Takt (`period` 2–5 je nach Chance, `phase`), Stopp exakt mittig, vorher bis 0,4 Felder daneben, dann 24 Frames Einrasten. Eigener Frame-Zähler statt Spieltick
- `game.tick_paused`: Dreh wird sofort aufgelöst (ohne Ticks keine Animation möglich)

### 0.6.1: Vanilla recyceln statt nachbauen

User: kein Gebäude zum Gamblen (zumindest noch nicht), aber so viel Vanilla wiederverwenden wie möglich; die eigene Zielauswahl sah trotz Kombinator-Optik selbstgemacht aus.

- Zielwahl wieder über `choose-elem-button` (`item-with-quality`): das ist der echte Vanilla-Auswähler, inkl. Suche über übersetzte Namen. Menge im Textfeld direkt daneben
- Menge im selben Dialog wie beim Kombinator gibt es nur für Entitäten (Anforderungs-/Kombinator-Slots); ohne Gebäude nicht möglich. Falls später doch ein „Glücksautomat“ kommt: `logistic-container` (requester) mit `inventory_size = 1`, `max_logistic_slots = 1` liefert Einsatz-Slot und Kombinator-Dialog komplett Vanilla, Anforderungen per `LuaLogisticPoint.enabled = false` abschalten

### 0.7.0: Spannung

User: spannender, aber nicht überladen; Near Misses, zufällige Spin-Zeiten; lange Spins sollen sich nach Gewinn anfühlen, kurze nach Niete.

- `reel.plan` wählt Art und Länge: Gewinn → 65 % lang / 35 % normal; Niete → 35 % „fast drauf“ (Gewinnfeld direkt dahinter), 20 % „gerade abgerutscht“ (Gewinnfeld direkt davor), 45 % klare Niete (75 % kurz)
- Stufen: kurz ~3,3 s, normal ~4,5 s, lang ~6,6 s (Auslaufen mit Potenz 4 = langes Kriechen)
- Knappe Fälle stehen 0,42–0,47 Felder daneben, hängen dort (lang 40, normal 12 Frames) und rasten dann ein. Unter 0,5 bleibt das Ergebnisfeld immer das nächstgelegene
- Gemessen (gemischte Chancen): lange Drehs ~58 % Gewinne. Bei kleinen Chancen sind lange Drehs fast immer Beinahe-Treffer (das klassische Necken)
- Keine zusätzlichen Effekte, nur Tempo, Pausen und die vorhandenen Klicks

### 0.8.0: Zielwahl nach „Signal auswählen“

User will genau den Vanilla-Dialog „Signal auswählen“ des Konstanten Kombinators (Screenshot) und fragte, ob man ihn nicht kopieren kann. Antwort: nein, der Dialog ist Engine-GUI und öffnet sich nur für Slots echter Gebäude (Kombinator, Anforderungen). Mods können nur seine Bausteine nutzen.

- Nachbau mit den Original-Styles: `editor_mode_selection_table` + `filter_group_button_tab_slightly_larger` (Gruppen-Tabs, `toggled` = ausgewählt), `deep_slots_scroll_pane` + `slot_table` (eine Zeile pro Untergruppe, Kachelhintergrund), Qualitätsknöpfe (nur erforschte, `force.is_quality_unlocked`), `slider` + `slider_value_textfield` + `item_and_count_select_confirm` mit `utility/check_mark_white`, Suche über Titelleisten-Lupe (`search_popup_textfield`)
- 6 Tabs à 75 px → Raster 11 Spalten breit statt 10 wie im Original
- Suche über übersetzte Namen: `scripts/translate.lua` (`request_translations`, `on_string_translated`, neu bei Sprachwechsel)
- Ziel im Panel ist ein Slot: links Dialog, rechts leeren
- Klick-Sound: genau beim Feldwechsel, still solange Felder schneller als alle 3 Frames wechseln (User: „nicht in sync“)
