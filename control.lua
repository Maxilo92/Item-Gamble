local values = require("scripts.values")
local gamble = require("scripts.gamble")
local gui = require("scripts.gui")
local commands_debug = require("scripts.debug")

commands_debug.register_commands()
gui.register_events()

script.on_init(function()
  gamble.init()
  values.rebuild()
end)

-- Neue oder geänderte Mods können neue Items und Rezepte bringen
script.on_configuration_changed(function()
  gamble.init()
  values.rebuild()
  gui.reopen_all()
end)

-- Der Fortschritt steckt in den gespeicherten Werten, Qualität und Chancen nicht
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "item-gamble-progression-weight" then
    values.rebuild()
  end
  gui.refresh_all()
end)
