-- Spiellogik ohne GUI: Einsatz, Chance, Dreh, Auszahlung.
--
-- Der Einsatz liegt in einem 1-Slot-Inventar pro Spieler (game.create_inventory).
-- Das Fenster öffnet dieses Inventar wie eine Kiste: Factorio zeigt daneben das
-- eigene Inventar, Klicken, Rechtsklick, Shift-Klick usw. funktionieren wie überall.
-- Ein Slot heißt automatisch: höchstens ein Stack.

local values = require("scripts.values")
local reel = require("scripts.reel")

local gamble = {}

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
  data.stake_count = nil
  data.location = nil
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
    data = { count = 1 }
    storage.players[player_index] = data
  end
  if not (data.stake_inventory and data.stake_inventory.valid) then
    data.stake_inventory = game.create_inventory(1, { "item-gamble.stake-inventory-title" })
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

-- Einsatz zurück ins Inventar (beim Schließen)
function gamble.return_stake(player, data)
  local inventory = data.stake_inventory
  local slot = inventory and inventory.valid and inventory[1]
  if slot and slot.valid_for_read then
    give(player, slot)
    slot.clear()
  end
end

-- Alles, was das Fenster anzeigt und der Dreh braucht.
-- problem: nil oder "no-stake", "stake-no-value", "stake-equipment", "no-target",
-- "target-no-value", "lower" (Ziel billiger als Einsatz) oder "below-min".
function gamble.evaluate(data)
  local state = {}

  local slot = data.stake_inventory[1]
  if slot.valid_for_read then
    state.stake = {
      name = slot.name,
      quality = slot.quality.name,
      count = slot.count,
      spoil = slot.spoil_percent,
    }
    if values.is_selectable(slot.name) and not has_equipment(slot) then
      state.stake_value = values.stack(slot.name, slot.quality.name, slot.count, slot.spoil_percent)
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

  data.stake_inventory[1].clear()
  local won = storage.rng() < state.chance
  data.last = nil
  data.spin = {
    won = won,
    chance = state.chance,
    name = data.target.name,
    quality = data.target.quality,
    count = state.count,
    stake = state.stake,
    frame = 0,
    reel = reel.plan(storage.rng, won, state.chance),
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
  if result.won then
    result.spilled = give(player, { name = result.name, quality = result.quality, count = result.count })
  end
  data.last = result
  return result
end

function gamble.remove_player(player_index)
  local data = storage.players[player_index]
  if data and data.stake_inventory and data.stake_inventory.valid then
    data.stake_inventory.destroy()
  end
  storage.players[player_index] = nil
  storage.spins[player_index] = nil
end

return gamble
