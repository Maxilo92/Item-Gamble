-- Spiellogik ohne GUI: Einsatz, Chance, Dreh, Auszahlung.
--
-- Einsatz und Gewinn liegen in je einem 1-Slot-Inventar (game.create_inventory) und
-- werden im Glücksrad-Panel als Slots angezeigt, die sich wie Vanilla-Slots bedienen
-- lassen. Ein Slot heißt automatisch: höchstens ein Stack.
-- Der Einsatz-Slot ist ein Vorrat: pro Dreh wird nur die eingestellte Menge eingesetzt,
-- so kann man nach einer Niete sofort weiterdrehen. Gewinne landen im Gewinn-Slot.

local values = require("scripts.values")
local reel = require("scripts.reel")

local gamble = {}

gamble.OUTPUT_SLOTS = 10   -- Gewinn-Slots im Panel
gamble.MAX_SPINS = 100     -- Drehs pro Knopfdruck

-- Spieler bekommt Items, was nicht passt, fällt vor der Spielfigur auf den Boden.
-- stack ist ein LuaItemStack oder eine Tabelle {name, quality, count}.
local function give(player, stack)
  local count = stack.count
  local inserted = player.insert(stack)
  local rest = count - inserted
  if rest > 0 then
    if type(stack) == "table" then
      stack = { name = stack.name, quality = stack.quality, count = rest }
    else
      stack.count = rest
    end
    -- In der Fernsicht steht die Figur woanders als die Kamera
    local where = player.character or player
    where.surface.spill_item_stack({ position = where.position, stack = stack, allow_belts = false })
  end
  return rest
end

-- Ältere Versionen: 0.3.0 hatte ein Einsatz-Inventar unter anderem Namen (Items
-- zurückgeben), 0.4.0/0.5.0 merkten sich nur eine Auswahl im Inventar (verwerfen).
local function migrate(player_index, data)
  local old = data.inventory
  data.inventory = nil
  if old and old.valid then
    local player = game.get_player(player_index)
    if player and old[1].valid_for_read then
      give(player, old[1])
    end
    old.destroy()
  end
  data.stake = nil
  data.location = nil
  -- 0.9.0 öffnete ein leeres Inventar als Fenster
  if data.window_inventory and data.window_inventory.valid then
    data.window_inventory.destroy()
  end
  data.window_inventory = nil
end

function gamble.init()
  storage.players = storage.players or {}
  storage.rng = storage.rng or game.create_random_generator()
  storage.spins = storage.spins or {}
  for player_index, data in pairs(storage.players) do
    migrate(player_index, data)
    data.elems = nil
    data.picker = nil
    -- Walzenplan aus älterer Version ohne Dauer: im nächsten Tick auflösen
    if data.spin and not data.spin.reel.duration then
      data.spin.reel.duration = 0
    end
  end
end

function gamble.get(player_index)
  local data = storage.players[player_index]
  if not data then
    data = { count = 1, stake_count = 1 }
    storage.players[player_index] = data
  end
  if not (data.stake_inventory and data.stake_inventory.valid) then
    data.stake_inventory = game.create_inventory(1)
  end
  local output = data.output_inventory
  if not (output and output.valid) then
    data.output_inventory = game.create_inventory(gamble.OUTPUT_SLOTS)
  elseif #output ~= gamble.OUTPUT_SLOTS then
    -- Gewinn-Slot aus 0.12.0 und früher hatte nur einen Platz: Inhalt umziehen
    local bigger = game.create_inventory(gamble.OUTPUT_SLOTS)
    for i = 1, #output do
      if output[i].valid_for_read then
        bigger.insert(output[i])
      end
    end
    output.destroy()
    data.output_inventory = bigger
  end
  return data
end

local function quality_name(quality)
  if type(quality) == "table" then
    return quality.name
  end
  return quality or "normal"
end
gamble.quality_name = quality_name

local function has_equipment(stack)
  local item = stack.item
  return item ~= nil and item.grid ~= nil and item.grid.count() > 0
end

-- Einsatz und nicht abgeholter Gewinn zurück ins Inventar, Rest auf den Boden
function gamble.return_items(player, data)
  for _, inventory in pairs({ data.stake_inventory, data.output_inventory }) do
    if inventory and inventory.valid then
      for i = 1, #inventory do
        local slot = inventory[i]
        if slot.valid_for_read then
          give(player, slot)
          slot.clear()
        end
      end
    end
  end
end

local function same_item(a, b)
  return a.name == b.name and a.quality.name == b.quality.name
end

-- Liegt eine andere Sorte im Einsatz-Slot als beim letzten Mal, wird die Einsatzmenge
-- auf den ganzen Vorrat gesetzt - wie beim Einlegen eines Stacks erwartet.
function gamble.track_stake(data)
  local slot = data.stake_inventory[1]
  local key = slot.valid_for_read and (slot.name .. "/" .. slot.quality.name) or nil
  if key ~= data.stake_key then
    data.stake_key = key
    if key then
      data.stake_count = slot.count
    end
  end
end

-- Klick auf einen Slot im Panel, wie bei Vanilla-Slots:
--   Links: ablegen, aufnehmen, tauschen    Rechts: ein Item ablegen / halben Stack nehmen
--   Shift: ins Inventar
-- accepts_input = false für den Gewinn-Slot: dort kann man nur herausnehmen.
function gamble.click_slot(player, slot, event, accepts_input)
  local cursor = player.cursor_stack
  if not cursor then
    return
  end
  local right = event.button == defines.mouse_button_type.right

  if event.shift then
    -- Wie im Spiel: Shift ins Inventar, Shift + Rechtsklick nur den halben Stack
    local inventory = player.get_main_inventory()
    if slot.valid_for_read and inventory then
      local count = right and math.ceil(slot.count / 2) or slot.count
      local inserted
      if count >= slot.count then
        inserted = inventory.insert(slot)
      else
        inserted = inventory.insert({ name = slot.name, quality = slot.quality, count = count })
      end
      if inserted >= slot.count then
        slot.clear()
      elseif inserted > 0 then
        slot.count = slot.count - inserted
      end
    end
    return
  end

  if cursor.valid_for_read then
    if not accepts_input then
      -- Gleiches Item in der Hand: dazunehmen, wie bei einer Maschinenausgabe
      if slot.valid_for_read and same_item(slot, cursor) then
        cursor.transfer_stack(slot, right and math.ceil(slot.count / 2) or nil)
      end
    elseif right then
      if not slot.valid_for_read or same_item(slot, cursor) then
        slot.transfer_stack(cursor, 1)
      end
    elseif not slot.valid_for_read or same_item(slot, cursor) then
      slot.transfer_stack(cursor)
    else
      slot.swap_stack(cursor)
    end
  elseif slot.valid_for_read then
    if right then
      cursor.transfer_stack(slot, math.ceil(slot.count / 2))
    else
      cursor.transfer_stack(slot)
    end
  end
end

-- Klick auf einen Slot des eigenen Inventars im Fenster, wie im Spiel:
--   Links:        aufnehmen (der Slot wird mit der Hand markiert), ablegen, tauschen
--   Rechts:       halben Stack aufnehmen / ein Item ablegen
--   Shift:        Stack in den Einsatz (Shift+Rechts: die Hälfte)
--   Strg:         alle Items dieser Sorte in den Einsatz, bis der Stack voll ist
function gamble.click_inventory(player, data, index, event)
  local inventory = player.get_main_inventory()
  local cursor = player.cursor_stack
  if not (inventory and cursor and index <= #inventory) then
    return
  end
  local slot = inventory[index]
  local right = event.button == defines.mouse_button_type.right
  local stake = data.stake_inventory[1]

  if event.shift or event.control then
    if not slot.valid_for_read or (stake.valid_for_read and not same_item(stake, slot)) then
      return
    end
    if event.control then
      local name, quality = slot.name, slot.quality.name
      for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read and stack.name == name and stack.quality.name == quality then
          stake.transfer_stack(stack)
        end
      end
    else
      stake.transfer_stack(slot, right and math.ceil(slot.count / 2) or nil)
    end
    return
  end

  if cursor.valid_for_read then
    if right then
      if not slot.valid_for_read or same_item(slot, cursor) then
        slot.transfer_stack(cursor, 1)
      end
    elseif not slot.valid_for_read or same_item(slot, cursor) then
      slot.transfer_stack(cursor)
    else
      slot.swap_stack(cursor)
    end
  elseif slot.valid_for_read then
    if right then
      cursor.transfer_stack(slot, math.ceil(slot.count / 2))
    else
      cursor.transfer_stack(slot)
      -- Wie im Spiel: der leere Slot gehört weiter der Hand, Q legt dorthin zurück
      if cursor.valid_for_read and not slot.valid_for_read then
        player.hand_location = { inventory = inventory.index, slot = index }
      end
    end
  end
end

-- Kann der Gewinn-Bereich das Ziel noch annehmen? Gesperrt ist er nur, wenn kein
-- Slot mehr frei ist und kein Stapel des Ziels Platz hat - wie eine Maschine mit
-- voller Ausgabe. Was beim Gewinn nicht mehr hineinpasst, geht ins Inventar.
local function output_accepts(data, target)
  return data.output_inventory.can_insert({ name = target.name, quality = target.quality, count = 1 })
end

-- Alles, was das Fenster anzeigt und der Dreh braucht.
-- problem: nil oder "no-stake", "stake-no-value", "stake-equipment", "no-target",
-- "target-no-value", "output-blocked" (Gewinn-Slot belegt), "lower" (Ziel billiger
-- als Einsatz) oder "below-min".
function gamble.evaluate(data)
  local state = {}

  local slot = data.stake_inventory[1]
  if slot.valid_for_read then
    -- Pro Dreh eingesetzt wird die eingestellte Menge, höchstens der ganze Vorrat
    local count = math.max(1, math.min(math.floor(data.stake_count or 1), slot.count))
    state.stake = {
      name = slot.name,
      quality = slot.quality.name,
      count = count,
      available = slot.count,
      spoil = slot.spoil_percent,
    }
    -- Mehrere Drehs auf einmal, soweit der Vorrat reicht
    state.max_spins = math.max(1, math.min(gamble.MAX_SPINS, math.floor(slot.count / count)))
    state.spins = math.max(1, math.min(math.floor(data.multi or 1), state.max_spins))
    if values.is_selectable(slot.name) and not has_equipment(slot) then
      state.stake_value = values.stack(slot.name, slot.quality.name, count, slot.spoil_percent)
    end
  end

  local target = data.target
  if target then
    local prototype = prototypes.item[target.name]
    if prototype then
      state.max_count = prototype.stack_size
      state.count = math.max(1, math.min(math.floor(data.count or 1), prototype.stack_size))
      if values.is_selectable(target.name) then
        state.target_value = values.stack(target.name, target.quality, state.count)
      end
    end
  end

  if not state.stake then
    state.problem = "no-stake"
  elseif not state.stake_value then
    state.problem = has_equipment(slot) and "stake-equipment" or "stake-no-value"
  elseif not target then
    state.problem = "no-target"
  elseif not state.target_value then
    state.problem = "target-no-value"
  elseif not output_accepts(data, target) then
    state.problem = "output-blocked"
  else
    local chance, ratio, reason = values.chance(state.stake_value, state.target_value)
    state.chance, state.ratio, state.problem = chance, ratio, reason
  end
  state.ok = state.problem == nil
  return state
end

-- Startet einen Dreh. Der Einsatz ist sofort weg, das Ergebnis steht sofort fest
-- und liegt in data.spin. Ausgezahlt wird erst in gamble.finish, wenn die Walze
-- steht - sonst verriete das Inventar daneben den Gewinn vorher.
function gamble.spin(player, data)
  local state = gamble.evaluate(data)
  if not state.ok or data.spin then
    return state
  end

  local slot = data.stake_inventory[1]
  local spent = state.stake.count * state.spins
  if spent >= slot.count then
    slot.clear()
  else
    slot.count = slot.count - spent
  end

  -- Jeder Dreh würfelt einzeln: Gewinn, sonst eventuell ein Trostpreis
  local rng = storage.rng
  local density = settings.global["item-gamble-consolation-chance"].value
  local pick = values.prize_picker(rng, state.stake_value)
  local wins, prizes, by_key, first_prize = 0, {}, {}, nil
  for _ = 1, state.spins do
    if rng() < state.chance then
      wins = wins + 1
    elseif density > 0 and rng() < density then
      local prize = pick()
      if prize then
        first_prize = first_prize or prize
        local key = prize.name .. "/" .. prize.quality
        if by_key[key] then
          by_key[key].count = by_key[key].count + prize.count
        else
          by_key[key] = { name = prize.name, quality = prize.quality, count = prize.count }
          prizes[#prizes + 1] = by_key[key]
        end
      end
    end
  end
  local won = wins > 0

  -- Die Walze zeigt das Ergebnis: ein Gewinn, sonst ein Trostpreis oder ein leeres Feld
  local plan = reel.plan(rng, won, state.chance, { density = density, pick = pick })
  if not won and (first_prize or plan.fill) then
    plan.fill = plan.fill or {}
    plan.fill[plan.stop] = first_prize
  end
  data.last = nil
  data.spin = {
    won = won,
    wins = wins,
    spins = state.spins,
    chance = state.chance,
    name = data.target.name,
    quality = data.target.quality,
    count = state.count,
    stake = state.stake,
    frame = 0,
    reel = plan,
    prizes = prizes,
  }
  storage.spins[player.index] = true
  return state
end

-- Walze steht (oder der Dreh wird abgebrochen, z.B. beim Schließen): auszahlen.
-- Gibt das Ergebnis zurück, nil wenn kein Dreh lief.
function gamble.finish(player, data)
  local result = data.spin
  if not result then
    return nil
  end
  data.spin = nil
  storage.spins[player.index] = nil
  -- Gewinne und Trostpreise in den Gewinn-Bereich; was nicht passt (z.B. Abbruch beim
  -- Schließen, viele Drehs), ins Inventar, der Rest auf den Boden
  local function pay(paid)
    local stack = { name = paid.name, quality = paid.quality, count = paid.count }
    local inserted = data.output_inventory.insert(stack)
    if inserted < stack.count then
      stack.count = stack.count - inserted
      return give(player, stack)
    end
    return 0
  end
  local wins = result.wins or (result.won and 1 or 0)
  if wins > 0 then
    result.spilled = pay({ name = result.name, quality = result.quality, count = result.count * wins })
  end
  -- Trostpreise aus 0.12.0: ein einzelner Preis statt einer Liste
  local prizes = result.prizes or (result.prize and { result.prize }) or {}
  result.prizes = prizes
  result.prize_spilled = 0
  for _, prize in ipairs(prizes) do
    result.prize_spilled = result.prize_spilled + pay(prize)
  end
  data.last = result
  return result
end

function gamble.remove_player(player_index)
  local data = storage.players[player_index]
  if data then
    for _, key in pairs({ "stake_inventory", "output_inventory" }) do
      if data[key] and data[key].valid then
        data[key].destroy()
      end
    end
  end
  storage.players[player_index] = nil
  storage.spins[player_index] = nil
end

return gamble
