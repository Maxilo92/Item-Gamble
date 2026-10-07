-- Fenster wie bei einer Kiste: Geöffnet wird das 1-Slot-Einsatzinventar, Factorio
-- zeigt daneben das eigene Inventar mit der gewohnten Bedienung. Rechts daran hängt
-- das Glücksspiel-Panel (relative GUI): Ziel, Chance, Walze, Drehen.
-- Das Ziel wird in einer eigenen Auswahl gewählt, ähnlich dem Konstanten Kombinator:
-- Gruppen-Tabs, Items, Qualität und Menge, dann Übernehmen.
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
local PICKER = "item_gamble_picker"
local COLUMNS = 10
local NAMES = {
  target = "item_gamble_target",
  spin = "item_gamble_spin",
  picker_close = "item_gamble_picker_close",
  picker_confirm = "item_gamble_picker_confirm",
  picker_count = "item_gamble_picker_count",
}
local TAGS = {
  group = "item_gamble_group",
  item = "item_gamble_item",
  quality = "item_gamble_quality",
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
    type = "sprite-button",
    name = NAMES.target,
    style = "inventory_slot",
    tooltip = { "item-gamble.target-tooltip" },
  })
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

  local target = elems.target
  if data.target then
    target.sprite = "item/" .. data.target.name
    target.quality = data.target.quality
    target.number = state.count
    target.elem_tooltip = { type = "item-with-quality", name = data.target.name, quality = data.target.quality }
  else
    target.sprite = ""
    target.quality = nil
    target.number = nil
    target.elem_tooltip = nil
  end
  target.enabled = not spinning
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

-- ── Zielauswahl ─────────────────────────────────────────────────────────────

-- Items mit Wert, nach Gruppe und Untergruppe sortiert wie im Spiel
local function selectable_groups()
  local by_group = {}
  for name, item in pairs(prototypes.item) do
    if values.is_selectable(name) then
      local group, subgroup = item.group, item.subgroup
      local entry = by_group[group.name]
      if not entry then
        entry = { name = group.name, order = group.order, subgroups = {} }
        by_group[group.name] = entry
      end
      local sub = entry.subgroups[subgroup.name]
      if not sub then
        sub = { order = subgroup.order, items = {} }
        entry.subgroups[subgroup.name] = sub
      end
      sub.items[#sub.items + 1] = { name = name, order = item.order }
    end
  end
  local groups = {}
  for _, entry in pairs(by_group) do
    local subgroups = {}
    for _, sub in pairs(entry.subgroups) do
      table.sort(sub.items, function(a, b) return a.order < b.order or (a.order == b.order and a.name < b.name) end)
      subgroups[#subgroups + 1] = sub
    end
    table.sort(subgroups, function(a, b) return a.order < b.order end)
    entry.subgroups = subgroups
    groups[#groups + 1] = entry
  end
  table.sort(groups, function(a, b) return a.order < b.order or (a.order == b.order and a.name < b.name) end)
  return groups
end

local function picker_qualities()
  local list = {}
  for name, quality in pairs(prototypes.quality) do
    if not quality.hidden then
      list[#list + 1] = { name = name, level = quality.level, order = quality.order }
    end
  end
  table.sort(list, function(a, b) return a.level < b.level or (a.level == b.level and a.order < b.order) end)
  return list
end

local function fill_picker_items(data)
  local pick = data.picker
  local elems = pick.elems
  local list = elems.items
  list.clear()
  elems.item_buttons = {}
  local group
  for _, entry in ipairs(pick.groups) do
    if entry.name == pick.group then
      group = entry
    end
  end
  if not group then
    return
  end
  for _, sub in ipairs(group.subgroups) do
    local table_element = list.add({ type = "table", style = "filter_slot_table", column_count = COLUMNS })
    for _, item in ipairs(sub.items) do
      local button = table_element.add({
        type = "sprite-button",
        style = item.name == pick.item and "yellow_slot_button" or "slot_button",
        sprite = "item/" .. item.name,
        quality = pick.quality,
        elem_tooltip = { type = "item-with-quality", name = item.name, quality = pick.quality },
        tags = { [TAGS.item] = item.name },
      })
      elems.item_buttons[item.name] = button
    end
  end
  for name, button in pairs(elems.group_buttons) do
    button.style = name == pick.group and "image_tab_selected_slot" or "image_tab_slot"
  end
end

local function refresh_picker(data)
  local pick = data.picker
  local elems = pick.elems
  for name, button in pairs(elems.quality_buttons) do
    button.style = name == pick.quality and "yellow_slot_button" or "slot_button"
  end
  for name, button in pairs(elems.item_buttons) do
    button.quality = pick.quality
    button.elem_tooltip = { type = "item-with-quality", name = name, quality = pick.quality }
  end
  local stack_size = pick.item and prototypes.item[pick.item].stack_size
  elems.max_count.caption = stack_size and { "item-gamble.max-count", stack_size } or ""
  elems.confirm.enabled = pick.item ~= nil
end

local function close_picker(player, data)
  local frame = player.gui.screen[PICKER]
  if frame then
    frame.destroy()
  end
  if data then
    data.picker = nil
  end
end

local function open_picker(player, data)
  close_picker(player, data)
  local groups = selectable_groups()
  local current = data.target
  local start_group = groups[1] and groups[1].name
  if current then
    start_group = prototypes.item[current.name].group.name
  end
  local pick = {
    groups = groups,
    group = start_group,
    item = current and current.name,
    quality = current and current.quality or "normal",
  }
  data.picker = pick

  local frame = player.gui.screen.add({ type = "frame", name = PICKER, direction = "vertical" })
  frame.auto_center = true
  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.style.horizontal_spacing = 8
  titlebar.add({ type = "label", style = "frame_title", caption = { "item-gamble.picker-title" }, ignored_by_interaction = true })
  local drag = titlebar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.style.right_margin = 4
  titlebar.add({
    type = "sprite-button",
    name = NAMES.picker_close,
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = { "gui.close" },
  })

  local content = frame.add({ type = "frame", style = "inside_deep_frame", direction = "vertical" })
  local group_table = content.add({ type = "table", column_count = 6 })
  group_table.style.horizontal_spacing = 0
  group_table.style.vertical_spacing = 0
  local group_buttons = {}
  for _, entry in ipairs(groups) do
    group_buttons[entry.name] = group_table.add({
      type = "sprite-button",
      style = "image_tab_slot",
      sprite = "item-group/" .. entry.name,
      tooltip = prototypes.item_group[entry.name].localised_name,
      tags = { [TAGS.group] = entry.name },
    })
  end

  local scroll = content.add({ type = "scroll-pane", style = "deep_scroll_pane", horizontal_scroll_policy = "never" })
  scroll.style.width = COLUMNS * 40 + 12
  scroll.style.height = 40 * 8
  local items = scroll.add({ type = "flow", direction = "vertical" })
  items.style.vertical_spacing = 0

  local settings_frame = frame.add({
    type = "frame",
    style = "inside_shallow_frame_with_padding_and_vertical_spacing",
    direction = "vertical",
  })
  settings_frame.style.top_margin = 8
  local quality_row = settings_frame.add({ type = "flow", direction = "horizontal" })
  quality_row.style.vertical_align = "center"
  quality_row.add({ type = "label", style = "caption_label", caption = { "item-gamble.picker-quality" } })
  local quality_buttons = {}
  for _, quality in ipairs(picker_qualities()) do
    quality_buttons[quality.name] = quality_row.add({
      type = "sprite-button",
      style = "slot_button",
      sprite = "quality/" .. quality.name,
      tooltip = prototypes.quality[quality.name].localised_name,
      tags = { [TAGS.quality] = quality.name },
    })
  end
  local count_row = settings_frame.add({ type = "flow", direction = "horizontal" })
  count_row.style.vertical_align = "center"
  count_row.add({ type = "label", style = "caption_label", caption = { "item-gamble.picker-count" } })
  local count = count_row.add({
    type = "textfield",
    name = NAMES.picker_count,
    text = tostring(data.count or 1),
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    lose_focus_on_confirm = true,
    tooltip = { "item-gamble.count-tooltip" },
  })
  count.style.width = 80
  local max_count = count_row.add({ type = "label" })

  local buttons = frame.add({ type = "flow", style = "dialog_buttons_horizontal_flow" })
  local filler = buttons.add({ type = "empty-widget", style = "draggable_space", ignored_by_interaction = true })
  filler.style.horizontally_stretchable = true
  filler.style.height = 32
  filler.drag_target = frame
  local confirm = buttons.add({
    type = "button",
    name = NAMES.picker_confirm,
    style = "confirm_button",
    caption = { "item-gamble.picker-confirm" },
  })

  pick.elems = {
    frame = frame,
    items = items,
    group_buttons = group_buttons,
    item_buttons = {},
    quality_buttons = quality_buttons,
    count = count,
    max_count = max_count,
    confirm = confirm,
  }
  fill_picker_items(data)
  refresh_picker(data)
  frame.bring_to_front()
end

local function confirm_picker(player, data)
  local pick = data.picker
  if not (pick and pick.item) then
    return
  end
  local stack_size = prototypes.item[pick.item].stack_size
  data.target = { name = pick.item, quality = pick.quality }
  data.count = math.max(1, math.min(math.floor(tonumber(pick.elems.count.text) or 1), stack_size))
  data.last = nil
  close_picker(player, data)
  gui.refresh(player)
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
  close_picker(player, data)
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
  local player = game.get_player(event.player_index)
  local data = gamble.get(player.index)
  local tags = element.tags

  if element.name == NAMES.target then
    if not data.spin then
      open_picker(player, data)
    end
  elseif element.name == NAMES.spin then
    gamble.spin(player, data)
    -- Angehaltene Zeit (z.B. im Editor): ohne Ticks keine Animation, gleich auflösen
    if data.spin and game.tick_paused then
      local result = gamble.finish(player, data)
      if result.won then
        player.play_sound({ path = "utility/achievement_unlocked" })
      end
    end
    gui.refresh(player)
  elseif element.name == NAMES.picker_close then
    close_picker(player, data)
  elseif element.name == NAMES.picker_confirm then
    confirm_picker(player, data)
  elseif data.picker and tags[TAGS.group] then
    data.picker.group = tags[TAGS.group]
    fill_picker_items(data)
    refresh_picker(data)
  elseif data.picker and tags[TAGS.item] then
    local pick = data.picker
    local old = pick.item and pick.elems.item_buttons[pick.item]
    if old and old.valid then
      old.style = "slot_button"
    end
    -- Doppelklick wie im Spiel: gleich übernehmen
    local double = pick.item == tags[TAGS.item] and event.tick - (pick.click_tick or -100) <= 20
    pick.item = tags[TAGS.item]
    pick.click_tick = event.tick
    element.style = "yellow_slot_button"
    refresh_picker(data)
    if double then
      confirm_picker(player, data)
    end
  elseif data.picker and tags[TAGS.quality] then
    data.picker.quality = tags[TAGS.quality]
    refresh_picker(data)
  end
end

local function on_closed(event)
  if event.gui_type == defines.gui_type.script_inventory then
    local data = storage.players[event.player_index]
    if data and data.open then
      cleanup(game.get_player(event.player_index))
    end
  end
end

-- Enter im Mengenfeld übernimmt die Auswahl
local function on_confirmed(event)
  local element = event.element
  if element and element.valid and element.name == NAMES.picker_count then
    local player = game.get_player(event.player_index)
    confirm_picker(player, gamble.get(player.index))
  end
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
      if spin.frame >= reel.DURATION then
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
    local picker = player.gui.screen[PICKER]
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
