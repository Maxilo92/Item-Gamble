-- Übersetzte Item-Namen pro Spieler, damit die Suche in der Zielauswahl wie im Spiel
-- funktioniert ("zahnrad" findet das Zahnrad). Factorio liefert Übersetzungen nur
-- asynchron über on_string_translated und nur für verbundene Spieler; bis sie da
-- sind, sucht die Auswahl über die internen Namen.

local values = require("scripts.values")

local translate = {}

function translate.init()
  storage.translations = storage.translations or {}
  storage.translation_requests = storage.translation_requests or {}
end

-- Fordert die Namen aller wählbaren Items für einen Spieler (neu) an
function translate.request(player)
  if not player.connected then
    return
  end
  local names, strings = {}, {}
  for name, item in pairs(prototypes.item) do
    if values.is_selectable(name) then
      names[#names + 1] = name
      strings[#strings + 1] = item.localised_name
    end
  end
  local ids = player.request_translations(strings)
  if not ids then
    return
  end
  local pending = {}
  for i, id in ipairs(ids) do
    pending[id] = names[i]
  end
  storage.translation_requests[player.index] = pending
  storage.translations[player.index] = storage.translations[player.index] or {}
end

function translate.request_all()
  for _, player in pairs(game.connected_players) do
    translate.request(player)
  end
end

local function on_translated(event)
  local pending = storage.translation_requests[event.player_index]
  local name = pending and pending[event.id]
  if not name then
    return
  end
  pending[event.id] = nil
  if event.translated then
    storage.translations[event.player_index][name] = string.lower(event.result)
  end
end

-- Passt ein Item zur Suche? Übersetzung und interner Name zählen beide.
function translate.matches(player_index, name, needle)
  local translated = storage.translations[player_index]
  local text = translated and translated[name]
  if text and string.find(text, needle, 1, true) then
    return true
  end
  return string.find(name, needle, 1, true) ~= nil
end

function translate.register_events()
  script.on_event(defines.events.on_string_translated, on_translated)
  script.on_event(defines.events.on_player_joined_game, function(event)
    translate.request(game.get_player(event.player_index))
  end)
  script.on_event(defines.events.on_player_locale_changed, function(event)
    storage.translations[event.player_index] = {}
    translate.request(game.get_player(event.player_index))
  end)
end

return translate
