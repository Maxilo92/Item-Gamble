-- Fenster wie bei einer Kiste: Geöffnet wird das 1-Slot-Einsatzinventar, Factorio
-- zeigt daneben das eigene Inventar mit der gewohnten Bedienung. Rechts daran hängt
-- das Glücksspiel-Panel (relative GUI): Ziel, Chance, Walze, Drehen.
-- Das Ziel wählt man im Vanilla-Item-Auswähler (choose-elem-button mit Qualität,
-- inklusive Suche über die übersetzten Namen), die Menge im Feld daneben.
--
-- Die Walze ist ein Scroll-Bereich ohne Scrollbalken, der überstehende Felder
-- abschneidet. Darin liegt eine Reihe Slots; das erste bekommt einen negativen
-- linken Rand, so wandert die Reihe pixelweise. Ist ein Feld durch, rücken die
-- Symbole eins weiter und der Rand springt zurück.

local gamble = require("scripts.gamble")
local values = require("scripts.values")
local reel = require("scripts.reel")

local gui = {}

local PANEL = "item_gamble_panel"
local NAMES = {
  target = "item_gamble_target",
  count = "item_gamble_count",
  spin = "item_gamble_spin",
}

local PROBLEM_KEYS = {
  ["no-stake"] = "item-gamble.problem-no-stake",
  ["no-target"] = "item-gamble.problem-no-target",
  ["stake-no-value"] = "item-gamble.problem-stake-no-value",
  ["stake-equipment"] = "item-gamble.problem-stake-equipment",
  ["target-no-value"] = "item-gamble.problem-target-no-value",
  ["lower"] = "item-gamble.problem-lower",
  ["below-min"] = "item-gamble.problem-below-min",
}
-- Hinweise statt Fehler: normale Schrift statt rot
local HINTS = {
  ["no-stake"] = true,
  ["no-target"] = true,
}

local function format_number(v)
  if v >= 1e6 then
    return string.format("%.2fM", v / 1e6)
  elseif v >= 1e4 then
    return string.format("%.1fk", v / 1e3)
  elseif v >= 100 then
    return string.format("%.0f", v)
  elseif v >= 10 then
    return string.format("%.1f", v)
  end
  return string.format("%.2f", v)
end

local function chance_caption(chance)
  if chance >= 0.01 then
    return { "item-gamble.chance-percent", string.format("%.1f", chance * 100) }
  end
  return { "item-gamble.chance-one-in", string.format("%.3g", chance * 100), string.format("%d", math.floor(1 / chance + 0.5)) }
end

local function rich_item(name, quality)
  if quality and quality ~= "normal" then
    return "[item=" .. name .. ",quality=" .. quality .. "]"
  end
  return "[item=" .. name .. "]"
end

local function set_label(label, caption, style)
  label.caption = caption
  label.style = style
  label.style.single_line = false
  label.style.maximal_width = reel.VISIBLE * reel.SLOT
end

-- ── Panel ───────────────────────────────────────────────────────────────────

local function selectable_names()
  local names = {}
  for name in pairs(prototypes.item) do
    if values.is_selectable(name) then
      names[#names + 1] = name
    end
  end
  return names
end

local function build_panel(player, data)
  local panel = player.gui.relative.add({
    type = "frame",
    name = PANEL,
    direction = "vertical",
    caption = { "item-gamble.window-title" },
    anchor = {
      gui = defines.relative_gui_type.script_inventory_gui,
      position = defines.relative_gui_position.right,
    },
  })

  local content = panel.add({
    type = "frame",
    style = "inside_shallow_frame_with_padding_and_vertical_spacing",
    direction = "vertical",
  })

  local stake_row = content.add({ type = "flow", direction = "horizontal" })
  stake_row.style.vertical_align = "center"
  stake_row.add({ type = "label", style = "caption_label", caption = { "item-gamble.stake" } })
  local stake_value = stake_row.add({ type = "label" })

  local target_row = content.add({ type = "flow", direction = "horizontal" })
  target_row.style.vertical_align = "center"
  target_row.style.horizontal_spacing = 8
  target_row.add({ type = "label", style = "caption_label", caption = { "item-gamble.target" } })
  local target = target_row.add({
    type = "choose-elem-button",
    name = NAMES.target,
    elem_type = "item-with-quality",
    tooltip = { "item-gamble.target-tooltip" },
  })
  -- Nur Items mit Wert anbieten. Der name-Filter ist laut Doku für verschachtelte
  -- Filter gedacht; falls er hier nicht greift, bleibt die Prüfung beim Auswählen.
  local filtered = pcall(function()
    target.elem_filters = { { filter = "name", name = selectable_names() } }
  end)
  if not filtered then
    target.elem_filters = { { filter = "hidden", invert = true } }
  end
  if data.target then
    target.elem_value = { name = data.target.name, quality = data.target.quality }
  end
  local count = target_row.add({
    type = "textfield",
    name = NAMES.count,
    text = tostring(data.count or 1),
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    lose_focus_on_confirm = true,
    tooltip = { "item-gamble.count-tooltip" },
  })
  count.style.width = 64
  local max_count = target_row.add({ type = "label" })
  local target_value = target_row.add({ type = "label" })

  content.add({ type = "line" })

  local chance_row = content.add({ type = "flow", direction = "horizontal" })
  chance_row.style.vertical_align = "center"
  chance_row.add({ type = "label", style = "bold_label", caption = { "item-gamble.chance-label" } })
  local chance = chance_row.add({ type = "label", style = "heading_2_label" })

  local reel_box = content.add({ type = "flow", direction = "vertical" })
  reel_box.style.horizontal_align = "center"
  reel_box.style.horizontally_stretchable = true
  reel_box.style.vertical_spacing = 0
  local reel_frame = reel_box.add({ type = "frame", style = "deep_frame_in_shallow_frame" })
  local viewport = reel_frame.add({
    type = "scroll-pane",
    style = "naked_scroll_pane",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "never",
  })
  viewport.style.width = reel.VISIBLE * reel.SLOT
  viewport.style.height = reel.SLOT
  viewport.style.padding = 0
  local strip = viewport.add({ type = "flow", direction = "horizontal", ignored_by_interaction = true })
  strip.style.horizontal_spacing = 0
  strip.style.padding = 0
  local reel_slots = {}
  for i = 1, reel.VISIBLE + 1 do
    local slot = strip.add({ type = "sprite-button", style = "slot_button" })
    slot.style.size = reel.SLOT
    reel_slots[i] = slot
  end
  local pointer = reel_box.add({ type = "sprite", sprite = "utility/indication_arrow" })
  pointer.style.width = 24
  pointer.style.height = 24
  pointer.style.stretch_image_to_widget_size = true

  local message = content.add({ type = "label" })
  local result = content.add({ type = "label" })

  local buttons = panel.add({ type = "flow", style = "dialog_buttons_horizontal_flow" })
  local filler = buttons.add({ type = "empty-widget" })
  filler.style.horizontally_stretchable = true
  local spin = buttons.add({
    type = "button",
    name = NAMES.spin,
    style = "confirm_button",
    caption = { "item-gamble.spin" },
    tooltip = { "item-gamble.spin-tooltip" },
  })

  data.elems = {
    panel = panel,
    stake_value = stake_value,
    target = target,
    count = count,
    max_count = max_count,
    target_value = target_value,
    chance = chance,
    reel_slots = reel_slots,
    message = message,
    result = result,
    spin = spin,
  }
end

-- Walze auf eine Position zeichnen. plan nil = leere Walze.
-- Symbole und Styles werden nur neu gesetzt, wenn ein Feld weitergerückt ist.
local function draw_reel(elems, plan, shown, position)
  local first, offset = reel.window(position)
  local slots = elems.reel_slots
  if elems.reel_first ~= first or elems.reel_plan ~= plan then
    elems.reel_first = first
    elems.reel_plan = plan
    for k, button in ipairs(slots) do
      if plan and reel.is_win(plan, first + k - 1) then
        button.style = "yellow_slot_button"
        button.sprite = "item/" .. shown.name
        button.quality = shown.quality
        button.number = shown.count
      else
        button.style = "slot_button"
        button.sprite = ""
        button.quality = nil
        button.number = nil
      end
      button.style.size = reel.SLOT
    end
  end
  slots[1].style.left_margin = -offset
end

-- Außerhalb eines Drehs zeigt die Walze, wo der letzte Dreh stehen blieb
local function draw_idle_reel(elems, data)
  local last = data.last
  if last and last.reel then
    draw_reel(elems, last.reel, last, last.reel.travel)
  else
    draw_reel(elems, nil, nil, 0)
  end
end

local function problem_caption(state, data)
  local problem = state.problem
  if problem == "stake-no-value" then
    return { PROBLEM_KEYS[problem], rich_item(state.stake.name, state.stake.quality) }
  elseif problem == "target-no-value" then
    return { PROBLEM_KEYS[problem], rich_item(data.target.name, data.target.quality) }
  elseif problem == "below-min" then
    return { PROBLEM_KEYS[problem], chance_caption(settings.global["item-gamble-min-chance"].value) }
  end
  return { PROBLEM_KEYS[problem] }
end

local function result_caption(last)
  if not last.won then
    return { "item-gamble.result-lost" }, "bold_red_label"
  end
  local icon = rich_item(last.name, last.quality)
  if last.spilled and last.spilled > 0 then
    return { "item-gamble.result-won-spilled", last.count, icon, last.spilled }, "bold_green_label"
  end
  return { "item-gamble.result-won", last.count, icon }, "bold_green_label"
end

function gui.refresh(player)
  local data = storage.players[player.index]
  local elems = data and data.elems
  if not (elems and elems.panel.valid) then
    return
  end
  local state = gamble.evaluate(data)
  local spinning = data.spin ~= nil

  if state.stake_value then
    if state.stake.spoil > 0 then
      elems.stake_value.caption = { "item-gamble.value-fresh", format_number(state.stake_value),
        string.format("%.0f", (1 - state.stake.spoil) * 100) }
    else
      elems.stake_value.caption = { "item-gamble.value", format_number(state.stake_value) }
    end
  else
    elems.stake_value.caption = ""
  end

  elems.target.enabled = not spinning
  elems.count.enabled = not spinning
  elems.max_count.caption = state.max_count and { "item-gamble.max-count", state.max_count } or ""
  elems.target_value.caption = state.target_value and { "item-gamble.value", format_number(state.target_value) } or ""

  if spinning then
    elems.chance.caption = chance_caption(data.spin.chance)
    elems.chance.style = "heading_2_label"
  elseif state.chance then
    elems.chance.caption = chance_caption(state.chance)
    elems.chance.style = state.ok and "heading_2_label" or "bold_red_label"
  else
    elems.chance.caption = { "item-gamble.chance-none" }
    elems.chance.style = "heading_2_label"
  end

  local show_problem = state.problem ~= nil and not spinning
  elems.message.visible = show_problem
  if show_problem then
    set_label(elems.message, problem_caption(state, data), HINTS[state.problem] and "label" or "bold_red_label")
  end

  elems.result.visible = data.last ~= nil
  if data.last then
    set_label(elems.result, result_caption(data.last))
  end

  elems.spin.enabled = state.ok and not spinning
  elems.spin.caption = spinning and { "item-gamble.spinning" } or { "item-gamble.spin" }
  if not spinning then
    draw_idle_reel(elems, data)
  end
end

function gui.refresh_all()
  for _, player in pairs(game.players) do
    gui.refresh(player)
  end
end

-- ── Öffnen, Schließen ───────────────────────────────────────────────────────

local function announce(player, result)
  player.print((result_caption(result)))
end

function gui.open(player)
  local data = gamble.get(player.index)
  local old = player.gui.relative[PANEL]
  if old then
    old.destroy()
  end
  build_panel(player, data)
  data.open = true
  player.opened = data.stake_inventory
  gui.refresh(player)
end

-- Einsatz zurück ins Inventar. Läuft gerade ein Dreh, wird sofort ausgezahlt
-- und das Ergebnis im Chat gemeldet.
local function cleanup(player)
  local data = storage.players[player.index]
  if data then
    local result = gamble.finish(player, data)
    if result then
      announce(player, result)
    end
    gamble.return_stake(player, data)
    data.open = false
    data.elems = nil
    data.last = nil
  end
  local panel = player.gui.relative[PANEL]
  if panel then
    panel.destroy()
  end
end

function gui.close(player)
  local data = storage.players[player.index]
  if data and data.open and player.opened_gui_type == defines.gui_type.script_inventory then
    player.opened = nil
  end
  cleanup(player)
end

function gui.toggle(player)
  local data = storage.players[player.index]
  if data and data.open then
    gui.close(player)
  else
    gui.open(player)
  end
end

-- ── Ereignisse ──────────────────────────────────────────────────────────────

local function on_click(event)
  local element = event.element
  -- Klicks in Fenstern anderer Mods gehen uns nichts an
  if not (element and element.valid and element.get_mod() == script.mod_name) then
    return
  end
  if element.name ~= NAMES.spin then
    return
  end
  local player = game.get_player(event.player_index)
  local data = gamble.get(player.index)
  gamble.spin(player, data)
  -- Angehaltene Zeit (z.B. im Editor): ohne Ticks keine Animation, gleich auflösen
  if data.spin and game.tick_paused then
    local result = gamble.finish(player, data)
    if result.won then
      player.play_sound({ path = "utility/achievement_unlocked" })
    end
  end
  gui.refresh(player)
end

local function on_elem_changed(event)
  local element = event.element
  if not (element and element.valid and element.name == NAMES.target) then
    return
  end
  local player = game.get_player(event.player_index)
  local data = gamble.get(player.index)
  local value = element.elem_value
  if data.spin then
    element.elem_value = data.target and { name = data.target.name, quality = data.target.quality } or nil
    return
  end
  if not value then
    data.target = nil
  elseif values.is_selectable(value.name) then
    data.target = { name = value.name, quality = gamble.quality_name(value.quality) }
    local stack_size = prototypes.item[value.name].stack_size
    if (data.count or 1) > stack_size then
      data.count = stack_size
      data.elems.count.text = tostring(stack_size)
    end
  else
    player.create_local_flying_text({
      text = { PROBLEM_KEYS["target-no-value"], rich_item(value.name, gamble.quality_name(value.quality)) },
      create_at_cursor = true,
    })
    element.elem_value = nil
    data.target = nil
  end
  data.last = nil
  gui.refresh(player)
end

local function on_text_changed(event)
  local element = event.element
  if not (element and element.valid and element.name == NAMES.count) then
    return
  end
  local player = game.get_player(event.player_index)
  gamble.get(player.index).count = tonumber(element.text) or 1
  gui.refresh(player)
end

local function on_closed(event)
  if event.gui_type == defines.gui_type.script_inventory then
    local data = storage.players[event.player_index]
    if data and data.open then
      cleanup(game.get_player(event.player_index))
    end
  end
end

-- Enter oder Fokusverlust: Mengenfeld auf den gültigen Bereich zurücksetzen
local function on_confirmed(event)
  local element = event.element
  if not (element and element.valid and element.name == NAMES.count) then
    return
  end
  local player = game.get_player(event.player_index)
  local data = gamble.get(player.index)
  local count = gamble.evaluate(data).count or math.max(1, math.floor(tonumber(element.text) or 1))
  data.count = count
  element.text = tostring(count)
  gui.refresh(player)
end

-- Jeden Tick: laufende Walzen bewegen, fertige auszahlen. Gezählt werden eigene
-- Frames statt Spielticks, damit ein geladener Spielstand dort weitermacht.
function gui.tick()
  local spins = storage.spins
  if not (spins and next(spins)) then
    return
  end
  for index in pairs(spins) do
    local player = game.get_player(index)
    local data = storage.players[index]
    if not (player and data and data.spin) then
      spins[index] = nil
    else
      local spin = data.spin
      spin.frame = spin.frame + 1
      local elems = data.elems
      local panel_open = elems ~= nil and elems.panel.valid
      if spin.frame >= spin.reel.duration then
        local result = gamble.finish(player, data)
        if result.won then
          player.play_sound({ path = "utility/achievement_unlocked" })
        end
        if panel_open then
          gui.refresh(player)
        else
          announce(player, result)
        end
      elseif panel_open then
        local position = reel.position(spin.reel, spin.frame)
        draw_reel(elems, spin.reel, spin, position)
        -- Leises Klicken, wenn ein Feld den Pfeil passiert (höchstens alle 4 Frames)
        local center = reel.center_index(position)
        if center ~= spin.center and spin.frame - (spin.click_frame or -10) >= 4 then
          spin.click_frame = spin.frame
          player.play_sound({ path = "utility/inventory_click" })
        end
        spin.center = center
      end
    end
  end
end

-- Einsatz ändert sich durch Vanilla-Bedienung: Inventar oder Hand ändern sich mit
local function on_inventory_event(event)
  local data = storage.players[event.player_index]
  if data and data.open then
    gui.refresh(game.get_player(event.player_index))
  end
end

-- Nach einem Mod-Update: Panels neu aufbauen, die alten Elemente sind vergessen
function gui.reopen_all()
  for _, player in pairs(game.players) do
    local panel = player.gui.relative[PANEL]
    if panel then
      panel.destroy()
    end
    -- Eigene Zielauswahl aus 0.6.0
    local picker = player.gui.screen["item_gamble_picker"]
    if picker then
      picker.destroy()
    end
    -- Fenster aus 0.3.0 bis 0.5.0
    local old_window = player.gui.screen["item_gamble_window"]
    if old_window then
      old_window.destroy()
    end
    local data = storage.players[player.index]
    if data and data.open then
      gui.open(player)
    end
  end
end

function gui.register_events()
  script.on_event(defines.events.on_tick, gui.tick)
  script.on_event(defines.events.on_gui_click, on_click)
  script.on_event(defines.events.on_gui_closed, on_closed)
  script.on_event(defines.events.on_gui_elem_changed, on_elem_changed)
  script.on_event(defines.events.on_gui_text_changed, on_text_changed)
  script.on_event(defines.events.on_gui_confirmed, on_confirmed)
  script.on_event(defines.events.on_player_main_inventory_changed, on_inventory_event)
  script.on_event(defines.events.on_player_cursor_stack_changed, on_inventory_event)
  script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "item-gamble-toggle" then
      gui.toggle(game.get_player(event.player_index))
    end
  end)
  script.on_event("item-gamble-toggle", function(event)
    gui.toggle(game.get_player(event.player_index))
  end)
  script.on_event(defines.events.on_pre_player_left_game, function(event)
    gui.close(game.get_player(event.player_index))
  end)
  script.on_event(defines.events.on_player_removed, function(event)
    gamble.remove_player(event.player_index)
  end)
end

return gui
