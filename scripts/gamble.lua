-- Spiellogik ohne GUI: Einsatz auswählen, Chance bewerten, drehen.
--
-- Der Einsatz bleibt bis zum Drehen im Inventar des Spielers. Gemerkt wird nur,
-- welches Item (mit Qualität), wie viele und aus welchen Slots (in Klick-Reihenfolge).
-- Bedienung wie im Spiel: Linksklick legt einen ganzen Stack ein, Rechtsklick ein Item.
-- Beim Drehen wird zuerst aus den angeklickten Slots genommen, dann aus weiteren
-- Stacks derselben Sorte. Die Frische ist der Durchschnitt genau dieser Items.

local values = require("scripts.values")
local reel = require("scripts.reel")

local gamble = {}

-- Bis 0.3.0 lag der Einsatz in einem eigenen Inventar. Was dort noch liegt,
-- geht an den Spieler zurück.
local function migrate_stake_inventory(player_index, data)
  local inventory = data.inventory
  data.inventory = nil
  if not (inventory and inventory.valid) then
    return
  end
  local player = game.get_player(player_index)
  local stack = inventory[1]
  if player and stack.valid_for_read then
    local inserted = player.insert(stack)
    if inserted < stack.count then
      stack.count = stack.count - inserted
      local where = player.character or player
      where.surface.spill_item_stack({ position = where.position, stack = stack, allow_belts = false })
    end
  end
  inventory.destroy()
end

function gamble.init()
  storage.players = storage.players or {}
  storage.rng = storage.rng or game.create_random_generator()
  storage.spins = storage.spins or {}
  for player_index, data in pairs(storage.players) do
    migrate_stake_inventory(player_index, data)
    data.elems = nil
  end
end

function gamble.get(player_index)
  local data = storage.players[player_index]
  if not data then
    data = { stake_count = 0, count = 1 }
    storage.players[player_index] = data
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

-- Warum ein Inventar-Stack nicht als Einsatz taugt, oder nil
function gamble.stake_problem(stack)
  if not values.is_selectable(stack.name) then
    return "stake-no-value"
  end
  if has_equipment(stack) then
    return "stake-equipment"
  end
end

-- Welche Stacks beim Drehen angefasst würden. Ohne Ausrüstung, angeklickte Slots zuerst.
-- Gibt die Liste {index, count}, die Gesamtmenge und den Verderbnisanteil (0..1) zurück.
local function plan_stake(inventory, stake, wanted)
  local takes, taken, fresh = {}, 0, 0
  local function take_from(index)
    if taken >= wanted then
      return
    end
    local stack = inventory[index]
    if stack.valid_for_read and stack.name == stake.name and stack.quality.name == stake.quality
      and not has_equipment(stack) then
      local count = math.min(stack.count, wanted - taken)
      takes[#takes + 1] = { index = index, count = count }
      taken = taken + count
      fresh = fresh + count * (1 - stack.spoil_percent)
    end
  end
  local preferred = {}
  for _, index in ipairs(stake.slots) do
    if index <= #inventory and not preferred[index] then
      preferred[index] = true
      take_from(index)
    end
  end
  for index = 1, #inventory do
    if not preferred[index] then
      take_from(index)
    end
  end
  local spoil = taken > 0 and (1 - fresh / taken) or 0
  return takes, taken, spoil
end

-- Wie viele Items dieser Sorte ohne Ausrüstung im Inventar liegen
local function available(inventory, stake)
  local _, count = plan_stake(inventory, stake, math.huge)
  return count
end

-- Spieler bekommt Items, was nicht passt, fällt vor der Spielfigur auf den Boden
local function give(player, stack)
  local inserted = player.insert(stack)
  local rest = stack.count - inserted
  if rest > 0 then
    local where = player.character or player
    where.surface.spill_item_stack({
      position = where.position,
      stack = { name = stack.name, quality = stack.quality, count = rest },
      allow_belts = false,
    })
  end
  return rest
end

-- Wie viele Items jeder Slot gerade für den Einsatz abgibt: {[index] = Anzahl}
function gamble.reserved(player, data)
  local inventory = player.get_main_inventory()
  local reserved = {}
  if inventory and data.stake then
    for _, take in ipairs(plan_stake(inventory, data.stake, data.stake_count or 0)) do
      reserved[take.index] = take.count
    end
  end
  return reserved
end

-- Klick auf einen Inventar-Slot: whole = Linksklick (ganzer Stack), sonst ein Item.
-- Eine andere Sorte ersetzt den bisherigen Einsatz. Gibt einen Problemschlüssel zurück,
-- wenn der Stack nicht taugt.
function gamble.add_stake(player, data, index, whole)
  local inventory = player.get_main_inventory()
  local stack = inventory and inventory[index]
  if not (stack and stack.valid_for_read) then
    return
  end
  local problem = gamble.stake_problem(stack)
  if problem then
    return problem
  end

  local stake = data.stake
  if not (stake and stake.name == stack.name and stake.quality == stack.quality.name) then
    stake = { name = stack.name, quality = stack.quality.name, slots = {} }
    data.stake = stake
    data.stake_count = 0
  end
  local known = false
  for _, slot in ipairs(stake.slots) do
    known = known or slot == index
  end
  if not known then
    stake.slots[#stake.slots + 1] = index
  end

  local free = stack.count - (gamble.reserved(player, data)[index] or 0)
  local add = whole and free or math.min(1, free)
  local limit = math.min(available(inventory, stake), stack.prototype.stack_size)
  data.stake_count = math.min(data.stake_count + add, limit)
  data.last = nil
end

-- Klick auf den Einsatz-Slot: whole = Linksklick (alles zurück), sonst ein Item zurück
function gamble.remove_stake(data, whole)
  if not data.stake then
    return
  end
  data.stake_count = whole and 0 or (data.stake_count or 1) - 1
  if data.stake_count <= 0 then
    data.stake = nil
    data.stake_count = 0
  end
end

-- Alles, was das Fenster anzeigt und der Dreh braucht.
-- problem: nil oder "no-inventory", "no-stake", "no-target", "target-no-value",
-- "lower" (Ziel billiger als Einsatz) oder "below-min" (Chance unter Minimum).
-- Ist der gewählte Einsatz nicht mehr im Inventar, wird die Auswahl gelöscht.
function gamble.evaluate(player, data)
  local state = {}
  local inventory = player.get_main_inventory()

  if inventory and data.stake then
    local stake = data.stake
    local have = available(inventory, stake)
    if have > 0 then
      -- Inventar kann seit dem Einlegen geschrumpft sein
      data.stake_count = math.max(1, math.min(data.stake_count or 1, have, prototypes.item[stake.name].stack_size))
      local _, taken, spoil = plan_stake(inventory, stake, data.stake_count)
      state.stake = { name = stake.name, quality = stake.quality, count = taken, spoil = spoil }
      state.stake_value = values.stack(stake.name, stake.quality, taken, spoil)
    else
      data.stake = nil
      data.stake_count = 0
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

  if not inventory then
    state.problem = "no-inventory"
  elseif not state.stake then
    state.problem = "no-stake"
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
-- steht - sonst verriete das Inventar im Fenster den Gewinn vorher.
function gamble.spin(player, data)
  local state = gamble.evaluate(player, data)
  if not state.ok or data.spin then
    return state
  end

  local inventory = player.get_main_inventory()
  local takes = plan_stake(inventory, data.stake, state.stake.count)
  data.stake = nil
  data.stake_count = 0
  for _, take in ipairs(takes) do
    local stack = inventory[take.index]
    if take.count >= stack.count then
      stack.clear()
    else
      stack.count = stack.count - take.count
    end
  end

  local won = storage.rng() < state.chance
  data.last = nil
  data.spin = {
    won = won,
    chance = state.chance,
    name = data.target.name,
    quality = data.target.quality,
    count = state.count,
    stake = state.stake,
    start = game.tick,
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
  result.reel_end = result.reel
  result.reel = nil
  data.last = result
  return result
end

function gamble.remove_player(player_index)
  storage.players[player_index] = nil
  storage.spins[player_index] = nil
end

return gamble
