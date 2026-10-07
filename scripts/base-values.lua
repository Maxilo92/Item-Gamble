-- Grundwerte für Rohstoffe. Alles andere rechnet die Mod aus den Rezepten aus.
--
-- Zum Nachjustieren einfach die Zahlen ändern, Spiel neu laden und im Spiel
-- /gamble-recalc eingeben (ohne den Befehl bleiben die alten Werte im Spielstand).
--
-- Einheit: 1 = ein Stück Eisenerz. Flüssigkeiten zählen pro Einheit (nicht pro Fass).
-- Grundwerte sind fest: Ein Rezept, das z.B. Eisenerz herstellt, überschreibt sie nicht.

return {
  -- Aufschlag pro Sekunde Craftzeit (bei Craftgeschwindigkeit 1)
  time_value = 0.1,

  -- Fortschritt: Wert × (1 + Gewicht × log10(1 + Forschungszeit / progress_scale)).
  -- Forschungszeit = Laborsekunden aller Technologien bis zum Rezept und seinem Gebäude.
  -- Das Gewicht ist eine Mod-Einstellung, die Skala steht hier.
  progress_scale = 1000,

  -- Mindestwerte (Endwert inkl. Fortschritt). Greifen nur, wenn die Rezepte zu billig sind,
  -- z.B. bei Wissenschaftspaketen, die kaum Rohstoffe brauchen (5 Weltraumpakete aus 2 Eisen,
  -- 1 Kohlenstoff, 1 Eis). Reihenfolge soll stimmen: Chemie 105 < Weltraum < Produktion/Nutzen ~470 < Kryo.
  min_value = {
    ["item/space-science-pack"] = 250,
    ["item/agricultural-science-pack"] = 200,
    ["item/cryogenic-science-pack"] = 700,
  },

  -- Rohstoffe aus anderen Mods, die hier fehlen und für die es kein Rezept gibt
  -- (abbaubare Ressourcen, Bäume, Pflanzen, Fische, Asteroidenbrocken, Flüssigkeiten von Böden)
  auto_item = 1,
  auto_fluid = 0.01,

  item = {
    -- Nauvis
    ["iron-ore"] = 1,
    ["copper-ore"] = 1,
    ["coal"] = 1,
    ["stone"] = 1,
    ["uranium-ore"] = 2,
    ["wood"] = 0.5,
    ["raw-fish"] = 5,

    -- Vulcanus
    ["tungsten-ore"] = 3,
    ["calcite"] = 2,

    -- Fulgora
    ["scrap"] = 0.5,
    ["holmium-ore"] = 8,

    -- Gleba
    ["yumako"] = 1,
    ["jellynut"] = 1,
    ["spoilage"] = 0.05,
    -- Erste Eier kommen von den Eiflößen, das Zuchtrezept braucht schon eine Biokammer
    ["pentapod-egg"] = 20,

    -- Nauvis-Biter (Gefangener Spawner: das Rezept hat keine Zutaten)
    ["biter-egg"] = 165,

    -- Samen: 2 % Ausbeute aus einer Frucht ergab ~126, das ist viel zu viel
    -- (zum Vergleich: Baumsamen ~5,5). Als Grundwert sind sie ein günstiges Nebenprodukt.
    ["yumako-seed"] = 10,
    ["jellynut-seed"] = 10,

    -- Weltraum
    ["metallic-asteroid-chunk"] = 5,
    ["carbonic-asteroid-chunk"] = 5,
    ["oxide-asteroid-chunk"] = 5,
    ["promethium-asteroid-chunk"] = 165,
  },

  fluid = {
    ["water"] = 0.01,
    ["steam"] = 0.02,
    ["crude-oil"] = 0.05,
    ["lava"] = 0.06, -- so teuer, dass Gießen aus Lava etwa beim Erz-Weg landet
    ["ammoniacal-solution"] = 0.1,
    ["lithium-brine"] = 0.05,
    ["fluorine"] = 0.1,
  },

  -- Rezepte, die nie für Werte zählen
  ignored_categories = {
    ["recycling"] = true,
    ["recycling-or-hand-crafting"] = true, -- Schrott-Recycling, sonst wird alles fast gratis
  },
  -- Fässer füllen zählt (gefülltes Fass = Fass + Flüssigkeit), Leeren nicht:
  -- sonst bekäme die Flüssigkeit ihren Wert aus dem Fass und umgekehrt.
  ignored_subgroups = {
    ["empty-barrel"] = true,
  },
  ignored_recipes = {},
}
