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
    icon = "__item-gamble__/graphics/shortcut-x56.png",
    icon_size = 56,
    small_icon = "__item-gamble__/graphics/shortcut-x24.png",
    small_icon_size = 24,
  },
})
