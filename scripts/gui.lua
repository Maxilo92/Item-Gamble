-- Eigenes Fenster, aufgebaut wie ein Kistenfenster: links das eigene Inventar, rechts
-- das Glücksrad (Einsatz-Slot als Vorrat mit Menge pro Dreh, Ziel-Slot mit Menge,
-- Chance, Walze, Gewinn-Bereich), unten Multiplikator und Drehen. Das Fenster ist
-- player.opened, E und Esc schließen es wie jedes andere.
--
-- Factorios eigenes Inventarfenster lässt sich nicht einbetten: ein geöffnetes
-- Script-Inventar zeichnet immer einen Inventarkasten daneben, das Spielfigur-Fenster
-- bringt Logistik und Herstellung mit. Das Inventar-Raster hier zeigt deshalb das
-- echte Inventar und bewegt echte Items mit der Vanilla-Bedienung (gamble.click_inventory),
-- inklusive Hand-Markierung des Slots, aus dem man einen Stack genommen hat.
--
-- Das Ziel wählt man in einem Dialog nach dem Vorbild von „Signal auswählen“
-- (dieselben Vanilla-Styles, Suche über übersetzte Namen). Den Original-Dialog
-- können Mods nicht öffnen, er gehört zu Kombinator- und Anforderungsslots.
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

local WINDOW = "item_gamble_window"
local PICKER = "item_gamble_picker"
local INVENTORY_COLUMNS = 10
local INVENTORY_ROWS = 10    -- mehr Zeilen scrollen
local OUTPUT_ROWS = 8        -- Gewinn-Bereich: mehr Zeilen scrollen
local PICKER_COLUMNS = 11   -- 6 Gruppen-Tabs à 75 px sind so breit wie 11 Slots
local PICKER_ROWS = 10
local NAMES = {
  close = "item_gamble_close",
  stake = "item_gamble_stake",
  stake_slider = "item_gamble_stake_slider",
  stake_amount = "item_gamble_stake_amount",
  target = "item_gamble_target",
  target_slider = "item_gamble_target_slider",
  target_amount = "item_gamble_target_amount",
  multi = "item_gamble_multi",
  spin = "item_gamble_spin",
  picker_close = "item_gamble_picker_close",
  picker_search_button = "item_gamble_picker_search_button",
  picker_search = "item_gamble_picker_search",
}
local TAGS = {
  inventory = "item_gamble_inventory_slot",
  group = "item_gamble_group",
  item = "item_gamble_item",
  quality = "item_gamble_quality",
  output = "item_gamble_output_slot",
}

-- Was noch fehlt: normale Schrift statt rot
local HINT_KEYS = {
  ["no-stake"] = "item-gamble.hint-no-stake",
  ["no-target"] = "item-gamble.hint-no-target",
}
local PROBLEM_KEYS = {
  ["stake-no-value"] = "item-gamble.problem-stake-no-value",
  ["stake-equipment"] = "item-gamble.problem-stake-equipment",
  ["target-no-value"] = "item-gamble.problem-target-no-value",
  ["output-blocked"] = "item-gamble.problem-output-blocked",
  ["lower"] = "item-gamble.problem-lower",
  ["below-min"] = "item-gamble.problem-below-min",
}

local MULTIPLIERS = { 1, 5, 10, 20, 50, 100 }

-- Nächste Stufe (back: vorherige), soweit der Vorrat reicht; am Ende geht es von vorn los.
-- current ist der tatsächliche Multiplikator, max nil heißt: noch kein Einsatz.
local function step_multiplier(current, max, back)
  local steps = {}
  for _, step in ipairs(MULTIPLIERS) do
    if step <= (max or gamble.MAX_MULTI) then
      steps[#steps + 1] = step
    end
  end
  local index = 1
  for k, step in ipairs(steps) do
    if step <= current then
      index = k
    end
  end
  if back then
    -- Zwischen zwei Stufen (Vorrat knapp) ist die untere schon die vorherige
    if steps[index] == current then
      index = index - 1
    end
  else
    index = index + 1
  end
  if index < 1 then
    index = #steps
  elseif index > #steps then
    index = 1
  end
  return steps[index]
end

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
  label.style.maximal_width = reel.VISIBLE * reel.PITCH
end

-- ── Fenster ─────────────────────────────────────────────────────────────────

local function build_window(player, data)
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

  local columns = window.add({ type = "flow", direction = "horizontal" })
  columns.style.horizontal_spacing = 12

  -- Links: das eigene Inventar, wie die linke Hälfte eines Kistenfensters
  local inventory_frame = columns.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local inventory_scroll = inventory_frame.add({
    type = "scroll-pane",
    style = "naked_scroll_pane",
    horizontal_scroll_policy = "never",
  })
  inventory_scroll.style.maximal_height = INVENTORY_ROWS * 40
  local inventory_slots_frame = inventory_scroll.add({ type = "frame", style = "slot_button_deep_frame" })
  local inventory = inventory_slots_frame.add({ type = "table", style = "slot_table", column_count = INVENTORY_COLUMNS })
  local no_inventory = inventory_frame.add({ type = "label", caption = { "item-gamble.problem-no-inventory" } })
  no_inventory.style.single_line = false
  no_inventory.style.maximal_width = INVENTORY_COLUMNS * 40

  -- Rechts: Glücksrad. Werte stehen im Tooltip der Chance.
  local content = columns.add({
    type = "frame",
    style = "inside_shallow_frame_with_padding_and_vertical_spacing",
    direction = "vertical",
  })
  content.style.vertically_stretchable = true

  -- Bezeichnung | Slot | Menge (Slider + Zahl) | Gesamtmenge mit Multiplikator
  local slots = content.add({ type = "table", column_count = 4 })
  slots.style.horizontal_spacing = 12
  slots.style.vertical_spacing = 4
  slots.style.vertical_align = "center"

  local function amount(slider_name, field_name, tooltip)
    local row = slots.add({ type = "flow", direction = "horizontal" })
    row.style.vertical_align = "center"
    row.style.horizontal_spacing = 8
    local slider = row.add({
      type = "slider",
      name = slider_name,
      minimum_value = 0,
      maximum_value = 1,
      value = 0,
      value_step = 1,
      tooltip = tooltip,
    })
    slider.style.width = 120
    local field = row.add({
      type = "textfield",
      name = field_name,
      style = "slider_value_textfield",
      numeric = true,
      allow_decimal = false,
      allow_negative = false,
      lose_focus_on_confirm = true,
      tooltip = tooltip,
    })
    return slider, field
  end

  local function total()
    local label = slots.add({ type = "label", style = "bold_label" })
    label.style.minimal_width = 72
    return label
  end

  slots.add({ type = "label", style = "caption_label", caption = { "item-gamble.stake" } })
  local stake = slots.add({ type = "sprite-button", name = NAMES.stake, style = "inventory_slot", tooltip = { "item-gamble.stake-tooltip" } })
  local stake_slider, stake_amount = amount(NAMES.stake_slider, NAMES.stake_amount, { "item-gamble.stake-amount-tooltip" })
  local stake_total = total()

  slots.add({ type = "label", style = "caption_label", caption = { "item-gamble.target" } })
  local target = slots.add({ type = "sprite-button", name = NAMES.target, style = "slot_button", tooltip = { "item-gamble.target-tooltip" } })
  local target_slider, target_amount = amount(NAMES.target_slider, NAMES.target_amount, { "item-gamble.count-tooltip" })
  local target_total = total()

  content.add({ type = "line" })

  -- Chance (oder was den Dreh verhindert), Walze, Ergebnis, Gewinn - mittig untereinander
  local reel_box = content.add({ type = "flow", direction = "vertical" })
  reel_box.style.horizontal_align = "center"
  reel_box.style.horizontally_stretchable = true
  reel_box.style.vertical_spacing = 0
  local chance = reel_box.add({ type = "label", style = "heading_2_label" })
  chance.style.bottom_margin = 4
  local reel_frame = reel_box.add({ type = "frame", style = "deep_frame_in_shallow_frame" })
  local viewport = reel_frame.add({
    type = "scroll-pane",
    style = "naked_scroll_pane",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "never",
  })
  viewport.style.width = reel.VISIBLE * reel.PITCH
  viewport.style.height = reel.SLOT
  viewport.style.padding = 0
  local strip = viewport.add({ type = "flow", direction = "horizontal", ignored_by_interaction = true })
  strip.style.horizontal_spacing = reel.GAP
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
  local result = reel_box.add({ type = "label" })
  result.style.single_line = false
  result.style.maximal_width = reel.VISIBLE * reel.PITCH

  -- Gewinn-Bereich: Reihen so breit wie die Walze, so viele wie belegt sind
  -- (gamble.fit_output). Erst ab OUTPUT_ROWS Reihen wird gescrollt.
  local output_scroll = reel_box.add({
    type = "scroll-pane",
    style = "naked_scroll_pane",
    horizontal_scroll_policy = "never",
  })
  output_scroll.style.top_margin = 8
  output_scroll.style.maximal_height = OUTPUT_ROWS * 40
  local output_frame = output_scroll.add({ type = "frame", style = "slot_button_deep_frame" })
  local output_table = output_frame.add({ type = "table", style = "slot_table", column_count = gamble.OUTPUT_COLUMNS })

  local buttons = window.add({ type = "flow", style = "dialog_buttons_horizontal_flow" })
  local filler = buttons.add({ type = "empty-widget", style = "draggable_space", ignored_by_interaction = true })
  filler.style.horizontally_stretchable = true
  filler.style.height = 32
  filler.drag_target = window
  -- Multiplikator: Klick schaltet weiter, Rechtsklick zurück. So hoch und fett wie Drehen.
  local multi = buttons.add({
    type = "button",
    name = NAMES.multi,
    style = "green_button",
    tooltip = { "item-gamble.multi-tooltip" },
  })
  multi.style.height = 32
  multi.style.minimal_width = 64
  multi.style.font = "default-dialog-button"
  local spin = buttons.add({
    type = "button",
    name = NAMES.spin,
    style = "confirm_button_without_tooltip",
    caption = { "item-gamble.spin" },
  })

  if data.window_location then
    window.location = data.window_location
  else
    window.auto_center = true
  end

  data.elems = {
    window = window,
    inventory = inventory,
    inventory_buttons = {},
    no_inventory = no_inventory,
    stake = stake,
    stake_slider = stake_slider,
    stake_amount = stake_amount,
    stake_total = stake_total,
    target = target,
    target_slider = target_slider,
    target_amount = target_amount,
    target_total = target_total,
    output_table = output_table,
    output_buttons = {},
    chance = chance,
    reel_slots = reel_slots,
    result = result,
    multi = multi,
    spin = spin,
  }
end

-- Das Inventar-Raster zeigt den echten Inhalt: Item, Qualität, Anzahl, und den Slot,
-- aus dem die Hand gerade einen Stack trägt. Die Knöpfe bleiben stehen und werden
-- nur aktualisiert; neu gebaut wird nur, wenn sich die Inventargröße ändert.
local function refresh_inventory(player, elems)
  local inventory = player.get_main_inventory()
  elems.no_inventory.visible = inventory == nil
  local buttons = elems.inventory_buttons
  local size = inventory and #inventory or 0
  if #buttons ~= size then
    elems.inventory.clear()
    buttons = {}
    for index = 1, size do
      buttons[index] = elems.inventory.add({
        type = "sprite-button",
        style = "inventory_slot",
        tags = { [TAGS.inventory] = index },
      })
    end
    elems.inventory_buttons = buttons
  end
  if not inventory then
    return
  end
  local hand = player.hand_location
  local hand_slot = hand and hand.inventory == inventory.index and hand.slot
  for index = 1, size do
    local stack = inventory[index]
    local button = buttons[index]
    if stack.valid_for_read then
      button.sprite = "item/" .. stack.name
      button.quality = stack.quality.name
      button.number = stack.count
      button.elem_tooltip = { type = "item-with-quality", name = stack.name, quality = stack.quality.name }
    else
      button.sprite = index == hand_slot and "utility/hand" or ""
      button.quality = nil
      button.number = nil
      button.elem_tooltip = nil
    end
  end
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
      local prize = plan and reel.prize(plan, first + k - 1)
      if plan and reel.is_win(plan, first + k - 1) then
        button.style = "yellow_slot_button"
        button.sprite = "item/" .. shown.name
        button.quality = shown.quality
        button.number = shown.count
      elseif prize then
        button.style = "slot_button"
        button.sprite = "item/" .. prize.name
        button.quality = prize.quality
        -- Planfelder tragen einfache Mengen, ausgezahlt wird mal Multiplikator
        button.number = prize.count * (shown.multi or 1)
      else
        button.style = "slot_button"
        button.sprite = ""
        button.quality = nil
        button.number = nil
      end
      button.style.size = reel.SLOT
    end
  end
  -- Jede Zelle ist Feld + Lücke, das Feld sitzt mittig darin
  slots[1].style.left_margin = math.floor(reel.GAP / 2) - offset
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
    return { PROBLEM_KEYS[problem], chance_caption(state.chance),
      chance_caption(settings.global["item-gamble-min-chance"].value) }
  end
  return { PROBLEM_KEYS[problem] }
end

-- Ein Dreh: Gewinn (Menge schon mal Multiplikator), Trostpreis oder Niete.
-- Ergebnisse aus 0.13/0.14 mit mehreren Drehs zeigen die Summe ihrer Gewinne.
local function result_caption(last)
  local wins = last.wins or (last.won and 1 or 0)
  local prizes = last.prizes or (last.prize and { last.prize }) or {}
  local spilled = (last.spilled or 0) + (last.prize_spilled or 0)
  local text, style
  if wins > 0 then
    text = { "item-gamble.result-won", wins * last.count, rich_item(last.name, last.quality) }
    style = "bold_green_label"
  elseif #prizes > 0 then
    text = { "item-gamble.result-consolation", prizes[1].count, rich_item(prizes[1].name, prizes[1].quality) }
    style = "bold_label"
  else
    return { "item-gamble.result-lost" }, "bold_red_label"
  end
  if spilled > 0 then
    text = { "", text, " ", { "item-gamble.result-spilled", spilled } }
  end
  return text, style
end

local function show_stack(button, stack)
  if stack.valid_for_read then
    button.sprite = "item/" .. stack.name
    button.quality = stack.quality.name
    button.number = stack.count
    button.elem_tooltip = { type = "item-with-quality", name = stack.name, quality = stack.quality.name }
  else
    button.sprite = ""
    button.quality = nil
    button.number = nil
    button.elem_tooltip = nil
  end
end

-- Gewinn-Slots: neu gebaut nur, wenn der Bereich gewachsen oder geschrumpft ist
local function refresh_output(data, elems)
  local output = data.output_inventory
  local buttons = elems.output_buttons
  if #buttons ~= #output then
    elems.output_table.clear()
    buttons = {}
    for i = 1, #output do
      buttons[i] = elems.output_table.add({
        type = "sprite-button",
        style = "inventory_slot",
        tags = { [TAGS.output] = i },
        tooltip = { "item-gamble.output-tooltip" },
      })
    end
    elems.output_buttons = buttons
  end
  for i, button in ipairs(buttons) do
    show_stack(button, output[i])
  end
end

-- Slider und Zahl einer Mengenwahl. max nil = nichts zu wählen.
local function show_amount(slider, field, value, max, enabled, typing)
  if max and max > 1 then
    slider.set_slider_minimum_maximum(1, max)
    slider.slider_value = value
    slider.enabled = enabled
  else
    -- Minimum und Maximum dürfen nicht gleich sein
    slider.set_slider_minimum_maximum(0, 1)
    slider.slider_value = max and 1 or 0
    slider.enabled = false
  end
  field.enabled = enabled and max ~= nil
  if not typing then
    field.text = max and tostring(value) or ""
  end
end

-- typing: Name des Feldes, in dem gerade getippt wird (wird nicht überschrieben)
function gui.refresh(player, typing)
  local data = storage.players[player.index]
  local elems = data and data.elems
  if not (elems and elems.window.valid) then
    return
  end
  refresh_inventory(player, elems)
  gamble.track_stake(data)
  show_stack(elems.stake, data.stake_inventory[1])
  local state = gamble.evaluate(data)
  if gamble.fit_output(data) then
    state = gamble.evaluate(data)
  end
  refresh_output(data, elems)
  local spinning = data.spin ~= nil
  -- Gespeicherte Mengen auf den gültigen Bereich ziehen, außer während des Tippens
  if state.stake and typing ~= NAMES.stake_amount then
    data.stake_count = state.stake.count
  end
  if state.count and typing ~= NAMES.target_amount then
    data.count = state.count
  end
  -- data.multi bleibt die gewählte Stufe; reicht der Vorrat nicht, zeigt der Knopf weniger

  local stake = state.stake
  show_amount(elems.stake_slider, elems.stake_amount, stake and stake.count, stake and stake.available,
    not spinning, typing == NAMES.stake_amount)

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
  show_amount(elems.target_slider, elems.target_amount, state.count, state.max_count,
    not spinning, typing == NAMES.target_amount)

  -- Multiplikator: vervielfacht Einsatz und Gewinn, die Gesamtmengen stehen neben den Slots
  local multi = spinning and (data.spin.multi or 1) or state.multi
    or math.max(1, math.min(math.floor(data.multi or 1), gamble.MAX_MULTI))
  elems.multi.caption = "×" .. multi
  elems.multi.enabled = not spinning
  local show_totals = multi > 1 and not spinning
  elems.stake_total.caption = show_totals and stake and { "item-gamble.total", multi, stake.count * multi } or ""
  elems.target_total.caption = show_totals and state.count and { "item-gamble.total", multi, state.count * multi } or ""

  -- Über der Walze: die Chance, rot was den Dreh verhindert, oder was noch fehlt.
  -- Die Werte (mal Multiplikator) im Tooltip.
  local chance = elems.chance
  if spinning then
    set_label(chance, chance_caption(data.spin.chance), "heading_2_label")
  elseif PROBLEM_KEYS[state.problem] then
    set_label(chance, problem_caption(state, data), "bold_red_label")
  elseif HINT_KEYS[state.problem] then
    set_label(chance, { HINT_KEYS[state.problem] }, "label")
  elseif state.chance then
    set_label(chance, chance_caption(state.chance), "heading_2_label")
  else
    set_label(chance, { "item-gamble.chance-none" }, "heading_2_label")
  end
  chance.style.bottom_margin = 4
  if state.stake_value and state.target_value and not spinning then
    local stake_value = format_number(state.stake_value * multi)
    if stake.spoil > 0 then
      stake_value = { "item-gamble.value-fresh", stake_value, string.format("%.0f", (1 - stake.spoil) * 100) }
    end
    chance.tooltip = { "item-gamble.chance-tooltip", stake_value, format_number(state.target_value * multi) }
  else
    chance.tooltip = ""
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

-- Alle Qualitäten wie in „Signal auswählen“, auch noch nicht erforschte
local function all_qualities()
  local list = {}
  for name, quality in pairs(prototypes.quality) do
    if not quality.hidden then
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

-- Qualitätsknöpfe und Qualitätsanzeige der Items an die Auswahl anpassen
local function refresh_picker(pick)
  local elems = pick.elems
  for name, button in pairs(elems.quality_buttons) do
    button.toggled = name == pick.quality
  end
  for name, button in pairs(elems.item_buttons) do
    button.quality = pick.quality
    button.elem_tooltip = { type = "item-with-quality", name = name, quality = pick.quality }
  end
end

-- Die Zielauswahl ist beim Öffnen player.opened, damit Esc wie im Spiel erst sie
-- schließt. Danach bekommt das Glücksspiel-Fenster die Rolle zurück.
local function close_picker(player, data)
  local frame = player.gui.screen[PICKER]
  if frame then
    frame.destroy()
  end
  if data then
    data.picker = nil
    local window = data.elems and data.elems.window
    local opened = player.opened_gui_type
    -- Nur zurückgeben, wenn nichts anderes geöffnet ist (bzw. nur die alte Auswahl)
    if data.open and window and window.valid
      and (opened == defines.gui_type.none or (opened == defines.gui_type.custom and player.opened ~= window)) then
      player.opened = window
    end
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
  for _, quality in ipairs(all_qualities()) do
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

  pick.elems = {
    frame = frame,
    search = search,
    items = items,
    group_buttons = group_buttons,
    item_buttons = {},
    quality_buttons = quality_buttons,
  }
  if not quality_buttons[pick.quality] then
    pick.quality = "normal"
  end
  fill_picker_items(player.index, pick)
  refresh_picker(pick)
  frame.bring_to_front()
  -- Das Fenster darunter wird dabei "geschlossen" gemeldet - das ist hier keins
  data.switching = true
  player.opened = frame
  data.switching = false
end

-- Klick auf ein Item übernimmt es mit der gewählten Qualität
local function choose_target(player, data, name)
  local pick = data.picker
  data.target = { name = name, quality = pick.quality }
  local stack_size = prototypes.item[name].stack_size
  data.count = math.max(1, math.min(data.count or 1, stack_size))
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
  local old = player.gui.screen[WINDOW]
  if old then
    old.destroy()
  end
  build_window(player, data)
  data.open = true
  gui.refresh(player)
  player.opened = data.elems.window
end

-- Einsatz und Gewinn zurück ins Inventar, Rest auf den Boden. Läuft gerade ein
-- Dreh, wird sofort ausgezahlt und das Ergebnis im Chat gemeldet.
local function cleanup(player)
  local data = storage.players[player.index]
  if data then
    local result = gamble.finish(player, data)
    if result then
      announce(player, result)
    end
    gamble.return_items(player, data)
    data.open = false
    data.elems = nil
    data.last = nil
  end
  close_picker(player, data)
  local window = player.gui.screen[WINDOW]
  if window then
    window.destroy()
  end
end

function gui.close(player)
  cleanup(player)
end

function gui.toggle(player)
  if player.gui.screen[WINDOW] then
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

  if tags[TAGS.inventory] then
    gamble.click_inventory(player, data, tags[TAGS.inventory], event)
    gui.refresh(player)
  elseif name == NAMES.close then
    gui.close(player)
  elseif name == NAMES.stake then
    gamble.click_slot(player, data.stake_inventory[1], event, true)
    gui.refresh(player)
  elseif tags[TAGS.output] then
    -- Der Bereich kann seit dem Aufbau geschrumpft sein
    local index = tags[TAGS.output]
    if index <= #data.output_inventory then
      gamble.click_slot(player, data.output_inventory[index], event, false)
    end
    gui.refresh(player)
  elseif name == NAMES.multi then
    if data.spin then
      return
    end
    local state = gamble.evaluate(data)
    local current = state.multi or math.max(1, math.min(math.floor(data.multi or 1), gamble.MAX_MULTI))
    data.multi = step_multiplier(current, state.max_multi, event.button == defines.mouse_button_type.right)
    gui.refresh(player)
  elseif name == NAMES.spin then
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
    choose_target(player, data, tags[TAGS.item])
  elseif tags[TAGS.quality] then
    pick.quality = tags[TAGS.quality]
    refresh_picker(pick)
  end
end

-- Mengenfelder und Suche
local function on_text_changed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local player = game.get_player(event.player_index)
  local data = storage.players[event.player_index]
  if not data then
    return
  end
  local name = element.name
  if name == NAMES.stake_amount then
    data.stake_count = math.max(1, math.floor(tonumber(element.text) or 1))
    gui.refresh(player, name)
  elseif name == NAMES.target_amount then
    data.count = math.max(1, math.floor(tonumber(element.text) or 1))
    gui.refresh(player, name)
  elseif name == NAMES.picker_search and data.picker then
    data.picker.search = string.lower(element.text)
    fill_picker_items(event.player_index, data.picker)
    refresh_picker(data.picker)
  end
end

local function on_value_changed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local data = storage.players[event.player_index]
  if not data then
    return
  end
  local value = math.max(1, math.floor(element.slider_value + 0.5))
  if element.name == NAMES.stake_slider then
    data.stake_count = value
  elseif element.name == NAMES.target_slider then
    data.count = value
  else
    return
  end
  gui.refresh(game.get_player(event.player_index))
end

-- Enter oder Fokusverlust: Mengenfeld auf den gültigen Bereich setzen
local function on_confirmed(event)
  local element = event.element
  if element and element.valid and (element.name == NAMES.stake_amount or element.name == NAMES.target_amount) then
    gui.refresh(game.get_player(event.player_index))
  end
end

-- E oder Esc: Factorio fragt das geöffnete Fenster zu schließen
local function on_closed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local player = game.get_player(event.player_index)
  local data = storage.players[event.player_index]
  if element.name == PICKER then
    close_picker(player, data)
  elseif element.name == WINDOW and not (data and data.switching) then
    gui.close(player)
  end
end

local function on_location_changed(event)
  local element = event.element
  if element and element.valid and element.name == WINDOW then
    gamble.get(event.player_index).window_location = element.location
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
      local panel_open = elems ~= nil and elems.window.valid
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
        -- Klick genau in dem Frame, in dem ein Feld den Pfeil passiert. Beim schnellen
        -- Durchrauschen höchstens jeden zweiten Frame, das klingt wie ein Rattern.
        local center = reel.center_index(position)
        if center ~= spin.center and spin.frame - (spin.click_frame or -10) >= 2 then
          spin.click_frame = spin.frame
          player.play_sound({ path = "utility/inventory_click" })
        end
        spin.center = center
      end
    end
  end
end

-- Hand oder Inventar ändern sich, wenn Items in Slots wandern
local function on_inventory_event(event)
  local data = storage.players[event.player_index]
  if data and data.open then
    gui.refresh(game.get_player(event.player_index))
  end
end

-- Nach einem Mod-Update: Panels neu aufbauen, die alten Elemente sind vergessen
function gui.reopen_all()
  for _, player in pairs(game.players) do
    -- Angehängtes Panel aus 0.6.0 bis 0.10.0
    local panel = player.gui.relative["item_gamble_panel"]
    if panel then
      panel.destroy()
    end
    local picker = player.gui.screen[PICKER]
    if picker then
      picker.destroy()
    end
    local window = player.gui.screen[WINDOW]
    if window then
      window.destroy()
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
  script.on_event(defines.events.on_gui_location_changed, on_location_changed)
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
