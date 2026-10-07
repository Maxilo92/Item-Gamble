-- Ein Fenster: links das eigene Inventar, rechts Einsatz, Ziel, Chance und Drehen.
--
-- Bedienung wie im Spiel: Linksklick auf einen Inventar-Slot legt den ganzen Stack
-- in den Einsatz, Rechtsklick ein einzelnes Item. Am Einsatz-Slot genauso zurück.
-- Die Items bleiben bis zum Drehen im Inventar; das Raster zeigt, was übrig bleibt.
--
-- Die Walze ist ein Scroll-Bereich ohne Scrollbalken, der überstehende Felder
-- abschneidet. Darin liegt eine Reihe Slots; das erste bekommt einen negativen
-- linken Rand, so wandert die Reihe pixelweise. Ist ein Feld durch, rücken die
-- Symbole eins weiter und der Rand springt zurück.

local gamble = require("scripts.gamble")
local values = require("scripts.values")
local reel = require("scripts.reel")

local gui = {}

local WINDOW = "item_gamble_window"
local COLUMNS = 10
local NAMES = {
  close = "item_gamble_close",
  stake = "item_gamble_stake",
  target = "item_gamble_target",
  count = "item_gamble_count",
  spin = "item_gamble_spin",
}
local SLOT_TAG = "item_gamble_slot"

local PROBLEM_KEYS = {
  ["no-inventory"] = "item-gamble.problem-no-inventory",
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

local function selectable_names()
  local names = {}
  for name in pairs(prototypes.item) do
    if values.is_selectable(name) then
      names[#names + 1] = name
    end
  end
  return names
end

local function wrapping_label(parent)
  local label = parent.add({ type = "label" })
  label.style.single_line = false
  label.style.maximal_width = 340
  return label
end

local function build(player, data)
  local window = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical" })

  local titlebar = window.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = window
  titlebar.style.horizontal_spacing = 8
  titlebar.add({ type = "label", style = "frame_title", caption = { "item-gamble.window-title" }, ignored_by_interaction = true })
  local drag = titlebar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.style.right_margin = 4
  titlebar.add({
    type = "sprite-button",
    name = NAMES.close,
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = { "gui.close-instruction" },
  })

  local body = window.add({ type = "flow", direction = "horizontal" })
  body.style.horizontal_spacing = 12

  -- Links: Inventar
  local inventory_frame = body.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  inventory_frame.add({ type = "label", style = "caption_label", caption = { "item-gamble.inventory" } })
  local scroll = inventory_frame.add({ type = "scroll-pane", style = "naked_scroll_pane", horizontal_scroll_policy = "never" })
  scroll.style.top_margin = 4
  scroll.style.maximal_height = 40 * 10
  local slots_frame = scroll.add({ type = "frame", style = "slot_button_deep_frame" })
  local slots = slots_frame.add({ type = "table", style = "slot_table", column_count = COLUMNS })
  local no_inventory = wrapping_label(inventory_frame)

  -- Rechts: Einsatz, Ziel, Chance
  local panel = body.add({
    type = "frame",
    style = "inside_shallow_frame_with_padding_and_vertical_spacing",
    direction = "vertical",
  })
  panel.style.minimal_width = reel.VISIBLE * reel.SLOT + 32
  panel.style.vertically_stretchable = true

  local grid = panel.add({ type = "table", column_count = 3 })
  grid.style.horizontal_spacing = 12
  grid.style.vertical_spacing = 8
  grid.style.column_alignments[3] = "right"

  grid.add({ type = "label", style = "caption_label", caption = { "item-gamble.stake" } })
  local stake = grid.add({ type = "sprite-button", name = NAMES.stake, style = "inventory_slot" })
  local stake_value = grid.add({ type = "label" })

  grid.add({ type = "label", style = "caption_label", caption = { "item-gamble.target" } })
  local target_row = grid.add({ type = "flow", direction = "horizontal" })
  target_row.style.vertical_align = "center"
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
  local target_value = grid.add({ type = "label" })

  panel.add({ type = "line" })

  local chance_row = panel.add({ type = "flow", direction = "horizontal" })
  chance_row.style.vertical_align = "center"
  chance_row.add({ type = "label", style = "bold_label", caption = { "item-gamble.chance-label" } })
  local chance = chance_row.add({ type = "label", style = "heading_2_label" })

  local reel_box = panel.add({ type = "flow", direction = "vertical" })
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
  local reel_slots = {}
  for i = 1, reel.VISIBLE + 1 do
    reel_slots[i] = strip.add({ type = "sprite-button", style = "slot_button" })
  end
  local pointer = reel_box.add({ type = "sprite", sprite = "utility/indication_arrow" })
  pointer.style.width = 24
  pointer.style.height = 24
  pointer.style.stretch_image_to_widget_size = true

  local message = wrapping_label(panel)
  local result = wrapping_label(panel)

  local buttons = window.add({ type = "flow", style = "dialog_buttons_horizontal_flow" })
  local filler = buttons.add({ type = "empty-widget", style = "draggable_space", ignored_by_interaction = true })
  filler.style.horizontally_stretchable = true
  filler.style.height = 32
  filler.drag_target = window
  local spin = buttons.add({
    type = "button",
    name = NAMES.spin,
    style = "confirm_button",
    caption = { "item-gamble.spin" },
    tooltip = { "item-gamble.spin-tooltip" },
  })

  if data.location then
    window.location = data.location
  else
    window.auto_center = true
  end

  data.elems = {
    window = window,
    slots = slots,
    no_inventory = no_inventory,
    stake = stake,
    stake_value = stake_value,
    target = target,
    count = count,
    max_count = max_count,
    target_value = target_value,
    chance = chance,
    message = message,
    result = result,
    spin = spin,
    reel_slots = reel_slots,
  }
end

-- Raster neu füllen: Zahl = was nach dem Einsatz übrig bleibt, Slots im Einsatz leuchten
local function refresh_inventory(player, data)
  local elems = data.elems
  local slots = elems.slots
  slots.clear()
  local inventory = player.get_main_inventory()
  elems.no_inventory.visible = inventory == nil
  if not inventory then
    elems.no_inventory.caption = { "item-gamble.problem-no-inventory" }
    return
  end
  local reserved = gamble.reserved(player, data)
  for index = 1, #inventory do
    local stack = inventory[index]
    local button = slots.add({ type = "sprite-button", style = "inventory_slot", tags = { [SLOT_TAG] = index } })
    if stack.valid_for_read then
      local left = stack.count - (reserved[index] or 0)
      button.toggled = (reserved[index] or 0) > 0
      if left > 0 then
        button.sprite = "item/" .. stack.name
        button.quality = stack.quality.name
        button.number = left
        local problem = gamble.stake_problem(stack)
        if problem then
          button.enabled = false
          button.tooltip = { PROBLEM_KEYS[problem], rich_item(stack.name, stack.quality.name) }
        else
          button.elem_tooltip = { type = "item-with-quality", name = stack.name, quality = stack.quality.name }
          button.tooltip = { "item-gamble.slot-tooltip" }
        end
      end
    end
  end
end

local function problem_caption(state, data)
  local problem = state.problem
  if problem == "target-no-value" then
    return { PROBLEM_KEYS[problem], rich_item(data.target.name, data.target.quality) }
  elseif problem == "below-min" then
    local min = settings.global["item-gamble-min-chance"].value
    return { PROBLEM_KEYS[problem], chance_caption(min) }
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

local function set_label(label, caption, style)
  label.caption = caption
  label.style = style
  label.style.single_line = false
  label.style.maximal_width = 340
end

-- Walze auf eine Position zeichnen. symbols nil = leere Walze.
-- Symbole und Styles werden nur neu gesetzt, wenn ein Feld weitergerückt ist.
local function draw_reel(elems, symbols, shown, position)
  local first, offset = reel.window(position)
  local slots = elems.reel_slots
  if elems.reel_first ~= first or elems.reel_symbols ~= symbols then
    elems.reel_first = first
    elems.reel_symbols = symbols
    for k, button in ipairs(slots) do
      if symbols and symbols[first + k - 1] then
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
    end
  end
  slots[1].style.left_margin = -offset
end

-- Was die Walze außerhalb eines Drehs zeigt: wo der letzte Dreh stehen blieb
local function draw_idle_reel(elems, data)
  local last = data.last
  if last and last.reel_end then
    draw_reel(elems, last.reel_end.symbols, last, last.reel_end.travel)
  else
    draw_reel(elems, nil, nil, 0)
  end
end

function gui.refresh(player)
  local data = storage.players[player.index]
  local elems = data and data.elems
  if not elems or not elems.window.valid then
    return
  end
  local state = gamble.evaluate(player, data)
  refresh_inventory(player, data)
  local spinning = data.spin ~= nil

  local stake = elems.stake
  if state.stake then
    stake.sprite = "item/" .. state.stake.name
    stake.quality = state.stake.quality
    stake.number = state.stake.count
    stake.elem_tooltip = { type = "item-with-quality", name = state.stake.name, quality = state.stake.quality }
    stake.tooltip = { "item-gamble.stake-tooltip" }
    if state.stake.spoil > 0 then
      elems.stake_value.caption = { "item-gamble.value-fresh", format_number(state.stake_value),
        string.format("%.0f", (1 - state.stake.spoil) * 100) }
    else
      elems.stake_value.caption = { "item-gamble.value", format_number(state.stake_value) }
    end
  else
    stake.sprite = ""
    stake.quality = nil
    stake.number = nil
    stake.elem_tooltip = nil
    stake.tooltip = { "item-gamble.stake-empty-tooltip" }
    elems.stake_value.caption = ""
  end

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

  elems.message.visible = state.problem ~= nil and not spinning
  if state.problem and not spinning then
    set_label(elems.message, problem_caption(state, data), HINTS[state.problem] and "label" or "bold_red_label")
  end

  elems.result.visible = data.last ~= nil
  if data.last then
    set_label(elems.result, result_caption(data.last))
  end

  elems.target.enabled = not spinning
  elems.count.enabled = not spinning
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

function gui.open(player)
  local data = gamble.get(player.index)
  local existing = player.gui.screen[WINDOW]
  if existing then
    existing.destroy()
  end
  build(player, data)
  gui.refresh(player)
  player.opened = data.elems.window
end

local function announce(player, result)
  player.print((result_caption(result)))
end

-- Der Einsatz liegt noch im Inventar, beim Schließen muss nichts zurück.
-- Läuft gerade ein Dreh, wird sofort ausgezahlt und das Ergebnis im Chat gemeldet.
function gui.close(player)
  local data = storage.players[player.index]
  if data then
    local result = gamble.finish(player, data)
    if result then
      announce(player, result)
    end
    data.elems = nil
    data.stake = nil
    data.stake_count = 0
    data.last = nil
  end
  local window = player.gui.screen[WINDOW]
  if window then
    window.destroy()
  end
end

function gui.toggle(player)
  if player.gui.screen[WINDOW] then
    gui.close(player)
  else
    gui.open(player)
  end
end

local function flying_text(player, text)
  player.create_local_flying_text({ text = text, create_at_cursor = true })
end

local function on_click(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local player = game.get_player(event.player_index)
  local whole = event.button == defines.mouse_button_type.left
  local slot = element.tags[SLOT_TAG]
  if gamble.get(player.index).spin and element.name ~= NAMES.close then
    return
  end
  if slot then
    local data = gamble.get(player.index)
    local problem = gamble.add_stake(player, data, slot, whole)
    if problem then
      local stack = player.get_main_inventory()[slot]
      flying_text(player, { PROBLEM_KEYS[problem], rich_item(stack.name, stack.quality.name) })
    end
    gui.refresh(player)
  elseif element.name == NAMES.close then
    gui.close(player)
  elseif element.name == NAMES.stake then
    gamble.remove_stake(gamble.get(player.index), whole)
    gui.refresh(player)
  elseif element.name == NAMES.spin then
    gamble.spin(player, gamble.get(player.index))
    gui.refresh(player)
  end
end

local function on_closed(event)
  local element = event.element
  if element and element.valid and element.name == WINDOW then
    gui.close(game.get_player(event.player_index))
  end
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
    flying_text(player, { PROBLEM_KEYS["target-no-value"], rich_item(value.name, gamble.quality_name(value.quality)) })
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

-- Enter oder Fokusverlust: Feld auf den gültigen Bereich zurücksetzen
local function on_confirmed(event)
  local element = event.element
  if not (element and element.valid and element.name == NAMES.count) then
    return
  end
  local player = game.get_player(event.player_index)
  local data = gamble.get(player.index)
  local state = gamble.evaluate(player, data)
  local count = state.count or math.max(1, math.floor(tonumber(element.text) or 1))
  data.count = count
  element.text = tostring(count)
  gui.refresh(player)
end

local function on_location_changed(event)
  local element = event.element
  if element and element.valid and element.name == WINDOW then
    gamble.get(event.player_index).location = element.location
  end
end

-- Jeden Tick: laufende Walzen bewegen, fertige auszahlen
function gui.tick(event)
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
      local elapsed = event.tick - spin.start
      local elems = data.elems
      local window_open = elems ~= nil and elems.window.valid
      if elapsed >= reel.DURATION then
        local result = gamble.finish(player, data)
        if result.won then
          player.play_sound({ path = "utility/achievement_unlocked" })
        end
        if window_open then
          gui.refresh(player)
        else
          announce(player, result)
        end
      elseif window_open then
        local position = reel.position(spin.reel, elapsed)
        draw_reel(elems, spin.reel.symbols, spin, position)
        -- Leises Klicken, wenn ein Feld den Pfeil passiert (höchstens alle 4 Ticks)
        local center = reel.center_index(position)
        if center ~= spin.center and event.tick - (spin.click_tick or 0) >= 4 then
          spin.click_tick = event.tick
          player.play_sound({ path = "utility/inventory_click" })
        end
        spin.center = center
      end
    end
  end
end

-- Nach einem Mod-Update: offene Fenster neu aufbauen, die alten Elemente sind vergessen
function gui.reopen_all()
  for _, player in pairs(game.players) do
    if player.gui.screen[WINDOW] then
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
  script.on_event(defines.events.on_gui_location_changed, on_location_changed)
  script.on_event(defines.events.on_player_main_inventory_changed, function(event)
    gui.refresh(game.get_player(event.player_index))
  end)
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
