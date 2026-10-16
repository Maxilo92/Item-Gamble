data:extend({
  {
    type = "custom-input",
    name = "item-gamble-toggle",
    key_sequence = "ALT + G",
    action = "lua",
  },
  {
    type = "shortcut",
    name = "item-gamble-toggle",
    order = "z[item-gamble]",
    action = "lua",
    associated_control_input = "item-gamble-toggle",
    technology_to_unlock = "item-gamble",
    unavailable_until_unlocked = true,
    icon = "__item-gamble__/graphics/shortcut-x56.png",
    icon_size = 56,
    small_icon = "__item-gamble__/graphics/shortcut-x24.png",
    small_icon_size = 24,
  },
})

-- Glücksspiel gibt es erst mit grüner Wissenschaft, damit man das frühe Spiel nicht
-- überspringt. Später verbessert eine unendliche Forschung die Chancen ein klein wenig
-- (je Stufe +1 % der Chance, nie über die Höchstchance von 50 %).
data:extend({
  {
    type = "technology",
    name = "item-gamble",
    icon = "__item-gamble__/graphics/technology/item-gamble.png",
    icon_size = 256,
    effects = {
      { type = "nothing", effect_description = { "technology-effect.item-gamble" } },
    },
    prerequisites = { "logistic-science-pack" },
    unit = {
      count = 100,
      ingredients = {
        { "automation-science-pack", 1 },
        { "logistic-science-pack", 1 },
      },
      time = 15,
    },
  },
  {
    type = "technology",
    name = "item-gamble-luck",
    icon = "__item-gamble__/graphics/technology/item-gamble-luck.png",
    icon_size = 256,
    effects = {
      { type = "nothing", effect_description = { "technology-effect.item-gamble-luck" }, use_icon_overlay_constant = false },
    },
    prerequisites = { "item-gamble", "space-science-pack" },
    unit = {
      count_formula = "500*2^(L-1)",
      ingredients = {
        { "automation-science-pack", 1 },
        { "logistic-science-pack", 1 },
        { "chemical-science-pack", 1 },
        { "production-science-pack", 1 },
        { "utility-science-pack", 1 },
        { "space-science-pack", 1 },
      },
      time = 60,
    },
    max_level = "infinite",
    upgrade = true,
  },
})
