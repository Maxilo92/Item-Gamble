-- Fenster wie bei einer Kiste: Geöffnet wird das 1-Slot-Einsatzinventar, Factorio
-- zeigt daneben das eigene Inventar mit der gewohnten Bedienung. Rechts daran hängt
-- das Glücksspiel-Panel (relative GUI): Ziel, Chance, Walze, Drehen.
-- Das Ziel wählt man über einen Slot wie beim Konstanten Kombinator: Klick öffnet
-- einen Auswahldialog nach dem Vorbild von „Signal auswählen“ (dieselben Vanilla-
-- Styles: Gruppen-Tabs, Slot-Raster, Qualität, Slider, Mengenfeld, grüner Haken,
-- Suche über übersetzte Namen). Den Original-Dialog können Mods nicht öffnen, er
-- gehört zu Kombinator- und Anforderungsslots von Gebäuden.
--
-- Die Walze ist ein Scroll-Bereich ohne Scrollbalken, der überstehende Felder
-- abschneidet. Darin liegt eine Reihe Slots; das erste bekommt einen negativen
-- linken Rand, so wandert die Reihe pixelweise. Ist ein Feld durch, rücken die
-- Symbole eins weiter und der Rand springt zurück.

local gamble = require("scripts.gamble")
local values = require("scripts.values")
local reel = require("scripts.reel")
local translate = require("scripts.translate")

local gui = {}

local PANEL = "item_gamble_panel"
local PICKER = "item_gamble_picker"
local PICKER_COLUMNS = 11   -- 6 Gruppen-Tabs à 75 px sind so breit wie 11 Slots
local PICKER_ROWS = 10
local NAMES = {
  target = "item_gamble_target",
  spin = "item_gamble_spin",
  picker_close = "item_gamble_picker_close",
  picker_search_button = "item_gamble_picker_search_button",
  picker_search = "item_gamble_picker_search",
  picker_slider = "item_gamble_picker_slider",
  picker_count = "item_gamble_picker_count",
  picker_confirm = "item_gamble_picker_confirm",
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
    style = "slot_button",
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
  local function by_order(a, b)
    return a.order < b.order or (a.order == b.order and (a.name or "") < (b.name or ""))
  end
  local groups = {}
  for _, entry in pairs(by_group) do
    local subgroups = {}
    for _, sub in pairs(entry.subgroups) do
      table.sort(sub.items, by_order)
      subgroups[#subgroups + 1] = sub
    end
    table.sort(subgroups, by_order)
    entry.subgroups = subgroups
    groups[#groups + 1] = entry
  end
  table.sort(groups, by_order)
  return groups
end

-- Qualitäten wie im Spiel: nur die, die die eigene Fraktion schon erforscht hat
local function unlocked_qualities(player)
  local list = {}
  for name, quality in pairs(prototypes.quality) do
    if not quality.hidden and player.force.is_quality_unlocked(name) then
      list[#list + 1] = { name = name, level = quality.level, order = quality.order }
    end
  end
  table.sort(list, function(a, b) return a.level < b.level or (a.level == b.level and a.order < b.order) end)
  return list
end

local function group_has_match(player_index, group, needle)
  if needle == "" then
    return true
  end
  for _, sub in ipairs(group.subgroups) do
    for _, item in ipairs(sub.items) do
      if translate.matches(player_index, item.name, needle) then
        return true
      end
    end
  end
  return false
end

-- Slots der aktuellen Gruppe neu füllen, eine Zeile pro Untergruppe wie im Spiel
local function fill_picker_items(player_index, pick)
  local elems = pick.elems
  elems.items.clear()
  elems.item_buttons = {}
  local needle = pick.search

  -- Tabs ohne Treffer werden wie im Spiel ausgegraut; steht man auf so einem,
  -- springt die Auswahl zur ersten Gruppe mit Treffern
  local current, first_match
  for _, group in ipairs(pick.groups) do
    local match = group_has_match(player_index, group, needle)
    elems.group_buttons[group.name].enabled = match
    if match then
      first_match = first_match or group
      if group.name == pick.group then
        current = group
      end
    end
  end
  current = current or first_match
  if current then
    pick.group = current.name
  end
  for name, button in pairs(elems.group_buttons) do
    button.toggled = name == pick.group
  end
  if not current then
    return
  end

  for _, sub in ipairs(current.subgroups) do
    local row
    for _, item in ipairs(sub.items) do
      if needle == "" or translate.matches(player_index, item.name, needle) then
        if not row then
          row = elems.items.add({ type = "table", style = "slot_table", column_count = PICKER_COLUMNS })
        end
        elems.item_buttons[item.name] = row.add({
          type = "sprite-button",
          style = item.name == pick.item and "yellow_slot_button" or "slot_button",
          sprite = "item/" .. item.name,
          quality = pick.quality,
          elem_tooltip = { type = "item-with-quality", name = item.name, quality = pick.quality },
          tags = { [TAGS.item] = item.name },
        })
      end
    end
  end
end

-- Qualität, Slider und Menge an die Auswahl anpassen
local function refresh_picker(pick)
  local elems = pick.elems
  for name, button in pairs(elems.quality_buttons) do
    button.toggled = name == pick.quality
  end
  for name, button in pairs(elems.item_buttons) do
    button.quality = pick.quality
    button.elem_tooltip = { type = "item-with-quality", name = name, quality = pick.quality }
  end

  local stack_size = pick.item and prototypes.item[pick.item].stack_size or 1
  pick.count = math.max(1, math.min(pick.count, stack_size))
  local slider = elems.slider
  if stack_size > 1 then
    slider.set_slider_minimum_maximum(1, stack_size)
    slider.enabled = pick.item ~= nil
  else
    -- Minimum und Maximum dürfen nicht gleich sein
    slider.set_slider_minimum_maximum(0, 1)
    slider.enabled = false
  end
  slider.slider_value = pick.count
  if not pick.typing then
    elems.count.text = tostring(pick.count)
  end
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
  local pick = {
    groups = groups,
    group = current and prototypes.item[current.name].group.name or (groups[1] and groups[1].name),
    item = current and current.name,
    quality = current and current.quality or "normal",
    count = data.count or 1,
    search = "",
  }
  data.picker = pick
  if not next(storage.translations[player.index] or {}) then
    translate.request(player)
  end

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
  local search = titlebar.add({ type = "textfield", name = NAMES.picker_search, style = "search_popup_textfield", visible = false })
  titlebar.add({
    type = "sprite-button",
    name = NAMES.picker_search_button,
    style = "frame_action_button",
    sprite = "utility/search",
    tooltip = { "gui.search" },
  })
  titlebar.add({
    type = "sprite-button",
    name = NAMES.picker_close,
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = { "gui.close" },
  })

  local tabs_frame = frame.add({ type = "frame", style = "inside_deep_frame" })
  local tabs = tabs_frame.add({ type = "table", style = "editor_mode_selection_table", column_count = 6 })
  local group_buttons = {}
  for _, group in ipairs(groups) do
    group_buttons[group.name] = tabs.add({
      type = "sprite-button",
      style = "filter_group_button_tab_slightly_larger",
      sprite = "item-group/" .. group.name,
      tooltip = prototypes.item_group[group.name].localised_name,
      tags = { [TAGS.group] = group.name },
    })
  end

  local body = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  body.style.top_margin = 8
  local scroll = body.add({ type = "scroll-pane", style = "deep_slots_scroll_pane", horizontal_scroll_policy = "never" })
  scroll.style.width = PICKER_COLUMNS * 40 + 12
  scroll.style.height = PICKER_ROWS * 40
  local items = scroll.add({ type = "flow", direction = "vertical" })
  items.style.vertical_spacing = 0

  local quality_row = body.add({ type = "flow", direction = "horizontal" })
  quality_row.style.top_margin = 8
  quality_row.style.horizontal_spacing = 0
  local quality_buttons = {}
  for _, quality in ipairs(unlocked_qualities(player)) do
    local button = quality_row.add({
      type = "sprite-button",
      style = "slot_button",
      sprite = "quality/" .. quality.name,
      tooltip = prototypes.quality[quality.name].localised_name,
      tags = { [TAGS.quality] = quality.name },
    })
    button.style.size = 28
    quality_buttons[quality.name] = button
  end

  local count_frame = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "horizontal" })
  count_frame.style.top_margin = 8
  count_frame.style.vertical_align = "center"
  count_frame.style.horizontal_spacing = 8
  local slider = count_frame.add({
    type = "slider",
    name = NAMES.picker_slider,
    minimum_value = 0,
    maximum_value = 1,
    value = 1,
    value_step = 1,
  })
  slider.style.horizontally_stretchable = true
  local count = count_frame.add({
    type = "textfield",
    name = NAMES.picker_count,
    style = "slider_value_textfield",
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    lose_focus_on_confirm = true,
    tooltip = { "item-gamble.count-tooltip" },
  })
  local confirm = count_frame.add({
    type = "sprite-button",
    name = NAMES.picker_confirm,
    style = "item_and_count_select_confirm",
    sprite = "utility/check_mark_white",
    tooltip = { "item-gamble.picker-confirm" },
  })

  pick.elems = {
    frame = frame,
    search = search,
    items = items,
    group_buttons = group_buttons,
    item_buttons = {},
    quality_buttons = quality_buttons,
    slider = slider,
    count = count,
    confirm = confirm,
  }
  -- Ist die bisher gewählte Qualität nicht (mehr) erforscht, auf normal zurück
  if not quality_buttons[pick.quality] then
    pick.quality = "normal"
  end
  fill_picker_items(player.index, pick)
  refresh_picker(pick)
  frame.bring_to_front()
end

local function confirm_picker(player, data)
  local pick = data.picker
  if not (pick and pick.item) then
    return
  end
  data.target = { name = pick.item, quality = pick.quality }
  data.count = pick.count
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
  local name = element.name
  local tags = element.tags
  local pick = data.picker

  if name == NAMES.spin then
    gamble.spin(player, data)
    -- Angehaltene Zeit (z.B. im Editor): ohne Ticks keine Animation, gleich auflösen
    if data.spin and game.tick_paused then
      local result = gamble.finish(player, data)
      if result.won then
        player.play_sound({ path = "utility/achievement_unlocked" })
      end
    end
    gui.refresh(player)
  elseif name == NAMES.target then
    if data.spin then
      return
    end
    -- Wie ein Kombinator-Slot: links wählen, rechts leeren
    if event.button == defines.mouse_button_type.right then
      data.target = nil
      data.last = nil
      close_picker(player, data)
      gui.refresh(player)
    else
      open_picker(player, data)
    end
  elseif not pick then
    return
  elseif name == NAMES.picker_close then
    close_picker(player, data)
  elseif name == NAMES.picker_confirm then
    confirm_picker(player, data)
  elseif name == NAMES.picker_search_button then
    local search = pick.elems.search
    search.visible = not search.visible
    if search.visible then
      search.focus()
    elseif pick.search ~= "" then
      search.text = ""
      pick.search = ""
      fill_picker_items(player.index, pick)
      refresh_picker(pick)
    end
  elseif tags[TAGS.group] then
    pick.group = tags[TAGS.group]
    fill_picker_items(player.index, pick)
    refresh_picker(pick)
  elseif tags[TAGS.item] then
    local old = pick.item and pick.elems.item_buttons[pick.item]
    if old and old.valid then
      old.style = "slot_button"
    end
    -- Doppelklick übernimmt gleich
    local double = pick.item == tags[TAGS.item] and event.tick - (pick.click_tick or -100) <= 20
    pick.item = tags[TAGS.item]
    pick.click_tick = event.tick
    element.style = "yellow_slot_button"
    refresh_picker(pick)
    if double then
      confirm_picker(player, data)
    end
  elseif tags[TAGS.quality] then
    pick.quality = tags[TAGS.quality]
    refresh_picker(pick)
  end
end

local function on_text_changed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local data = storage.players[event.player_index]
  local pick = data and data.picker
  if not pick then
    return
  end
  if element.name == NAMES.picker_search then
    pick.search = string.lower(element.text)
    fill_picker_items(event.player_index, pick)
    refresh_picker(pick)
  elseif element.name == NAMES.picker_count then
    pick.count = math.floor(tonumber(element.text) or 1)
    -- Während des Tippens das Feld nicht überschreiben, nur den Slider nachziehen
    pick.typing = true
    refresh_picker(pick)
    pick.typing = false
  end
end

local function on_value_changed(event)
  local element = event.element
  if not (element and element.valid and element.name == NAMES.picker_slider) then
    return
  end
  local data = storage.players[event.player_index]
  local pick = data and data.picker
  if pick then
    pick.count = math.floor(element.slider_value + 0.5)
    refresh_picker(pick)
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

local function on_closed(event)
  if event.gui_type == defines.gui_type.script_inventory then
    local data = storage.players[event.player_index]
    if data and data.open then
      cleanup(game.get_player(event.player_index))
    end
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
        -- Klick genau in dem Frame, in dem ein Feld den Pfeil passiert. Rauscht die
        -- Walze schneller als ein Feld alle 3 Frames, bleibt es still - sonst würden
        -- Klicks verschluckt und klängen versetzt.
        local center = reel.center_index(position)
        if center ~= spin.center then
          if spin.frame - (spin.cross_frame or -10) >= 3 then
            player.play_sound({ path = "utility/inventory_click" })
          end
          spin.cross_frame = spin.frame
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
  script.on_event(defines.events.on_gui_text_changed, on_text_changed)
  script.on_event(defines.events.on_gui_value_changed, on_value_changed)
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
