-- Debug-Befehle zum Prüfen der Werte im Spiel.
--   /gamble-values [suche]  schreibt alle Werte nach script-output/item-gamble/values.txt
--                           und zeigt Treffer zur Suche im Chat
--   /gamble-recalc          rechnet die Werte neu (nach Änderungen an base-values.lua)

local values = require("scripts.values")
local gui = require("scripts.gui")

local debug_commands = {}

local OUTPUT_FILE = "item-gamble/values.txt"
local MAX_CHAT_LINES = 25

-- Sanity-Check aus dem Plan: soll ungefähr bei der Minimalchance landen
local SANITY_STAKE = { name = "automation-science-pack", count = 1 }
local SANITY_TARGET = { name = "promethium-science-pack", count = 100 }

local function format_value(v)
  return string.format("%.4g", v)
end

local function format_chance(chance)
  if chance >= 0.01 then
    return string.format("%.2f %%", chance * 100)
  end
  return string.format("%.4g %% (1:%d)", chance * 100, math.floor(1 / chance + 0.5))
end

local function format_source(source)
  if source == "base" then
    return "Grundwert"
  elseif source == "auto" then
    return "auto (Rohstoff ohne Grundwert)"
  end
  return "Rezept " .. source
end

local function localised_source(source)
  if source == "base" then
    return { "item-gamble.source-base" }
  elseif source == "auto" then
    return { "item-gamble.source-auto" }
  end
  return { "item-gamble.source-recipe", source }
end

local function sorted_entries(type)
  local entries = {}
  local list = type == "item" and prototypes.item or prototypes.fluid
  for name, prototype in pairs(list) do
    entries[#entries + 1] = {
      type = type,
      name = name,
      prototype = prototype,
      value = values.unit(type, name),
      progress = values.progress(type, name),
      source = values.source(type, name),
    }
  end
  table.sort(entries, function(a, b)
    if (a.value ~= nil) ~= (b.value ~= nil) then
      return a.value ~= nil
    end
    if a.value and a.value ~= b.value then
      return a.value > b.value
    end
    return a.name < b.name
  end)
  return entries
end

local function sanity()
  local stake = values.stack(SANITY_STAKE.name, "normal", SANITY_STAKE.count)
  local target = values.stack(SANITY_TARGET.name, "normal", SANITY_TARGET.count)
  if not stake or not target then
    return nil
  end
  local chance, r, reason = values.chance(stake, target)
  return { chance = chance, r = r, reason = reason }
end

local function build_report()
  local data = storage.values
  local weight = settings.global["item-gamble-progression-weight"].value
  local lines = {}
  local function add(line)
    lines[#lines + 1] = line
  end
  local function row(entry)
    local progress = entry.progress or 0
    add(string.format("%12s  x%-5.2f %7.1f h  %-45s %s", format_value(entry.value),
      values.progress_factor(progress, weight), progress / 3600, entry.name, format_source(entry.source)))
  end

  add("Item Gamble - Itemwerte (berechnet bei Tick " .. data.tick .. ")")
  add("Einheit: 1 = ein Eisenerz. Flüssigkeiten pro Einheit. Normale Qualität, frisch.")
  add(string.format("Spalten: Wert, Fortschrittsfaktor (Gewicht %g), Forschungszeit bis herstellbar, Name, Quelle.", weight))
  add(string.format("%d Rezepte genutzt, %d ignoriert (Recycling, Fässer, versteckt).",
    data.recipe_count, data.ignored_count))
  add("")

  local check = sanity()
  if check and check.chance then
    add(string.format("Test: 1x %s -> 100x %s: Wertverhältnis %s, Chance %s%s",
      SANITY_STAKE.name, SANITY_TARGET.name, format_value(check.r), format_chance(check.chance),
      check.reason == "below-min" and " (unter der Minimalchance)" or ""))
    add("")
  end

  local items = sorted_entries("item")
  local selectable, hidden, missing = {}, {}, {}
  for _, entry in ipairs(items) do
    if not entry.value then
      missing[#missing + 1] = entry
    elseif values.is_selectable(entry.name) then
      selectable[#selectable + 1] = entry
    else
      hidden[#hidden + 1] = entry
    end
  end

  add("== Items, wählbar (" .. #selectable .. "), teuerste zuerst ==")
  for _, entry in ipairs(selectable) do
    row(entry)
  end
  add("")
  add("== Items mit Wert, aber versteckt und nicht wählbar (" .. #hidden .. ") ==")
  for _, entry in ipairs(hidden) do
    row(entry)
  end
  add("")
  add("== Flüssigkeiten, pro Einheit ==")
  for _, entry in ipairs(sorted_entries("fluid")) do
    if entry.value then
      row(entry)
    end
  end
  add("")
  -- Versteckte Items nur zählen: Mods wie Textplates bringen davon über tausend
  local hidden_missing = 0
  add("== Items ohne berechenbaren Wert, nicht wählbar (" .. #missing .. ") ==")
  for _, entry in ipairs(missing) do
    if entry.prototype.hidden then
      hidden_missing = hidden_missing + 1
    else
      add(string.format("%12s  %s", "-", entry.name))
    end
  end
  if hidden_missing > 0 then
    add(string.format("%12s  dazu %d versteckte Items", "", hidden_missing))
  end
  add("")
  add("== Rezepte wegen Schleifen ausgeschlossen (" .. #data.excluded .. ") ==")
  for _, name in ipairs(data.excluded) do
    add("              " .. name)
  end

  return table.concat(lines, "\n"), #selectable + #hidden, #missing
end

local function chat_line(entry)
  local icon = "[" .. entry.type .. "=" .. entry.name .. "]"
  return { "", icon, " ", entry.prototype.localised_name, " = ", format_value(entry.value),
    "  (", localised_source(entry.source), ")" }
end

local function print_matches(print_to, filter)
  local needle = filter:lower()
  local matches = {}
  for _, type in pairs({ "item", "fluid" }) do
    for _, entry in ipairs(sorted_entries(type)) do
      if entry.value and entry.name:lower():find(needle, 1, true) then
        matches[#matches + 1] = entry
      end
    end
  end
  if #matches == 0 then
    print_to({ "item-gamble.no-matches", filter })
    return
  end
  print_to({ "item-gamble.matches", filter, #matches })
  for i = 1, math.min(#matches, MAX_CHAT_LINES) do
    print_to(chat_line(matches[i]))
  end
  if #matches > MAX_CHAT_LINES then
    print_to({ "item-gamble.more", #matches - MAX_CHAT_LINES })
  end
end

local function printer(command)
  local player = command.player_index and game.get_player(command.player_index)
  if player then
    return function(message) player.print(message) end
  end
  return function(message) game.print(message) end
end

local function print_summary(print_to, valued, missing)
  print_to({ "item-gamble.summary", valued, missing, "script-output/" .. OUTPUT_FILE })
  local check = sanity()
  if check and check.chance then
    local key = check.reason == "below-min" and "item-gamble.sanity-below-min" or "item-gamble.sanity"
    print_to({ key, format_value(check.r), format_chance(check.chance) })
  end
  if #storage.values.excluded > 0 then
    print_to({ "item-gamble.excluded", #storage.values.excluded })
  end
end

-- player_index nil schreibt auf dem Server bzw. im Einzelspieler
function debug_commands.write_report(player_index)
  local report, valued, missing = build_report()
  helpers.write_file(OUTPUT_FILE, report, false, player_index)
  return valued, missing
end

local function on_values_command(command)
  local print_to = printer(command)
  local valued, missing = debug_commands.write_report(command.player_index)
  print_summary(print_to, valued, missing)
  if command.parameter and command.parameter ~= "" then
    print_matches(print_to, command.parameter)
  end
end

local function on_recalc_command(command)
  local print_to = printer(command)
  local player = command.player_index and game.get_player(command.player_index)
  if player and not player.admin then
    print_to({ "item-gamble.admin-only" })
    return
  end
  values.rebuild()
  gui.refresh_all()
  game.print({ "item-gamble.recalc-done" })
end

function debug_commands.register_commands()
  commands.add_command("gamble-values", { "item-gamble.command-values-help" }, on_values_command)
  commands.add_command("gamble-recalc", { "item-gamble.command-recalc-help" }, on_recalc_command)
end

return debug_commands
