-- Spiellogik ohne GUI: Einsatz, Chance, Dreh, Auszahlung.
--
-- Einsatz und Gewinn liegen in eigenen Script-Inventaren (game.create_inventory) und
-- werden im Glücksrad-Fenster als Slots angezeigt, die sich wie Vanilla-Slots bedienen
-- lassen. Der Einsatz ist ein Slot, also höchstens ein Stack.
-- Der Einsatz-Slot ist ein Vorrat: pro Dreh wird die eingestellte Menge mal
-- Multiplikator eingesetzt, so kann man nach einer Niete sofort weiterdrehen. Gewinne
-- landen im Gewinn-Bereich, der mit dem möglichen Gewinn wächst (fit_output).

local values = require("scripts.values")
local reel = require("scripts.reel")

local gamble = {}

gamble.OUTPUT_COLUMNS = 10      -- Gewinn-Bereich: Slots pro Reihe, mindestens eine Reihe
gamble.MAX_OUTPUT_SLOTS = 200   -- wächst mit dem möglichen Gewinn bis hierhin
gamble.MAX_MULTI = 100     -- höchster Multiplikator für Einsatz und Gewinn

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
    data.output_inventory = game.create_inventory(gamble.OUTPUT_COLUMNS)
  elseif #output < gamble.OUTPUT_COLUMNS then
    -- Gewinn-Slot aus 0.12.0 und früher hatte nur einen Platz
    output.resize(gamble.OUTPUT_COLUMNS)
  end
  return data
end

-- Vor dem Auszahlen: so viele Reihen anhängen, wie der Gewinn über den freien Platz
-- hinaus braucht (höchstens bis MAX_OUTPUT_SLOTS, der Rest geht ins Inventar).
local function grow_output(output, stack)
  local missing = stack.count - output.get_insertable_count({ name = stack.name, quality = stack.quality })
  if missing <= 0 then
    return
  end
  local columns = gamble.OUTPUT_COLUMNS
  local slots = math.ceil(missing / prototypes.item[stack.name].stack_size)
  local size = math.ceil((#output + slots) / columns) * columns
  output.resize(math.min(gamble.MAX_OUTPUT_SLOTS, size))
end

-- Gewinn-Bereich so groß wie sein Inhalt: Lücken rücken nach vorne (Reihenfolge
-- bleibt), dann genau so viele Reihen wie belegt, mindestens eine. Wachsen tut er beim
-- Auszahlen (grow_output). resize löscht Items hinter der neuen Größe - nach dem
-- Aufrücken liegt dort nichts mehr.
-- Gibt true zurück, wenn sich die Größe geändert hat.
function gamble.fit_output(data)
  local output = data.output_inventory
  local used = 0
  for i = 1, #output do
    if output[i].valid_for_read then
      used = used + 1
      if used < i then
        output[used].swap_stack(output[i])
      end
    end
  end
  local columns = gamble.OUTPUT_COLUMNS
  local size = math.max(columns, math.ceil(used / columns) * columns)
  if size == #output then
    return false
  end
  output.resize(size)
  return true
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

-- Gewinn-Bereich ins Inventar räumen: alles, oder mit like nur die Sorte (Item und
-- Qualität) dieses Stacks, wie Strg-Klick im Spiel. Was nicht passt, bleibt liegen.
function gamble.take_output(player, data, like)
  local inventory = player.get_main_inventory()
  if not inventory then
    return
  end
  local name = like and like.valid_for_read and like.name
  local quality = name and like.quality.name
  local output = data.output_inventory
  for i = 1, #output do
    local slot = output[i]
    if slot.valid_for_read and (not name or (slot.name == name and slot.quality.name == quality)) then
      local inserted = inventory.insert(slot)
      if inserted >= slot.count then
        slot.clear()
      elseif inserted > 0 then
        slot.count = slot.count - inserted
      end
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
  local output = data.output_inventory
  return #output < gamble.MAX_OUTPUT_SLOTS
    or output.can_insert({ name = target.name, quality = target.quality, count = 1 })
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
    -- Der Multiplikator vervielfacht Einsatz und Gewinn eines Drehs, soweit der Vorrat reicht.
    -- Die Chance bleibt gleich, beide Seiten wachsen im selben Verhältnis.
    state.max_multi = math.max(1, math.min(gamble.MAX_MULTI, math.floor(slot.count / count)))
    state.multi = math.max(1, math.min(math.floor(data.multi or 1), state.max_multi))
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

-- ── Freispins ───────────────────────────────────────────────────────────────
--
-- Eine Niete kann einen Freispin bringen. Ein Freispin spielt genau die Wette, mit der
-- er gewonnen wurde (Einsatz, Ziel, Menge, Chance, Multiplikator), nur ohne Kosten -
-- sonst könnte man Freispins mit billigen Wetten sammeln und auf teure umschalten.
-- Wie am Spielautomaten bringt ein ×N-Dreh ×N-Freispins; gewürfelt wird dafür nur
-- einmal, so ist ein Freispin pro eingesetztem Item bei jedem Multiplikator gleich viel
-- wert.
--
-- Balance: Eine Wette bringt im Schnitt Maximum × Wertfaktor (Standard 50 %) des
-- Einsatzwerts zurück, ein Freispin ist so viel wert. Bei Freispin-Chance p und
-- Nachtriggern kommt man auf etwa 50 % ÷ (1 - p): bei 5 % rund 52,6 %. Die
-- Einstellung ist auf 25 % begrenzt, damit das nie Pari erreicht.

gamble.MAX_FREESPINS = 100   -- mehr sammeln sich nicht an

local function same_bet(a, b)
  return a.stake.name == b.stake.name and a.stake.quality == b.stake.quality
    and a.stake.count == b.stake.count and a.name == b.name and a.quality == b.quality
    and a.count == b.count and (a.multi or 1) == (b.multi or 1) and math.abs(a.chance - b.chance) < 1e-9
end

function gamble.freespins_left(data)
  local left = 0
  for _, bet in ipairs(data.freespins or {}) do
    left = left + bet.left
  end
  return left
end

local function add_freespins(data, bet, count)
  data.freespins = data.freespins or {}
  count = math.min(count, gamble.MAX_FREESPINS - gamble.freespins_left(data))
  if count <= 0 then
    return
  end
  for _, queued in ipairs(data.freespins) do
    if same_bet(queued, bet) then
      queued.left = queued.left + count
      return
    end
  end
  data.freespins[#data.freespins + 1] = {
    stake = { name = bet.stake.name, quality = bet.stake.quality, count = bet.stake.count },
    stake_value = bet.stake_value,
    name = bet.name,
    quality = bet.quality,
    count = bet.count,
    chance = bet.chance,
    multi = bet.multi or 1,
    left = count,
  }
end

-- Die nächste Freispin-Wette, oder nil. Wetten mit Items, die es nicht mehr gibt
-- (Mod entfernt), fallen weg.
function gamble.next_freespin(data)
  local queue = data.freespins
  while queue and queue[1] do
    local bet = queue[1]
    if bet.left > 0 and prototypes.item[bet.name] and prototypes.item[bet.stake.name] then
      return bet
    end
    table.remove(queue, 1)
  end
  return nil
end

-- Startet einen Dreh. Liegen Freispins an, wird zuerst einer davon gespielt, sonst
-- ist der Einsatz sofort weg. Das Ergebnis steht sofort fest und liegt in data.spin.
-- Ausgezahlt wird erst in gamble.finish, wenn die Walze steht - sonst verriete das
-- Inventar daneben den Gewinn vorher.
function gamble.spin(player, data)
  if data.spin then
    return
  end
  local bet
  local free = gamble.next_freespin(data)
  if free then
    if not output_accepts(data, free) then
      return
    end
    free.left = free.left - 1
    if free.left <= 0 then
      table.remove(data.freespins, 1)
    end
    bet = {
      stake = free.stake,
      stake_value = free.stake_value,
      name = free.name,
      quality = free.quality,
      count = free.count,
      chance = free.chance,
      multi = free.multi or 1,
      free = true,
    }
  else
    local state = gamble.evaluate(data)
    if not state.ok then
      return
    end
    local slot = data.stake_inventory[1]
    local spent = state.stake.count * state.multi
    if spent >= slot.count then
      slot.clear()
    else
      slot.count = slot.count - spent
    end
    bet = {
      stake = state.stake,
      stake_value = state.stake_value,
      name = data.target.name,
      quality = data.target.quality,
      count = state.count,
      chance = state.chance,
      multi = state.multi,
    }
  end
  local multi = bet.multi

  -- Ein Wurf: Gewinn, sonst eventuell ein Freispin (mit diesem Multiplikator) und ein
  -- Trostpreis (mal Multiplikator).
  local rng = storage.rng
  local density = settings.global["item-gamble-consolation-chance"].value
  local freespin_chance = settings.global["item-gamble-freespin-chance"].value
  local pick = values.prize_picker(rng, bet.stake_value)
  local won = rng() < bet.chance
  local prize, freespins = nil, 0
  if not won then
    if rng() < freespin_chance then
      freespins = 1
    end
    if density > 0 and rng() < density then
      prize = pick()
    end
  end

  -- Die Walze zeigt das Ergebnis: ein Gewinn, sonst Freispins, ein Trostpreis oder ein
  -- leeres Feld. Ihre Felder tragen die einfachen Mengen, die GUI zeigt sie mal
  -- Multiplikator.
  local plan = reel.plan(rng, won, bet.chance, { density = density, pick = pick, freespin = freespin_chance })
  if not won and (prize or freespins > 0 or plan.fill) then
    plan.fill = plan.fill or {}
    plan.fill[plan.stop] = freespins > 0 and { freespin = freespins } or prize
  end
  local prizes = {}
  if prize then
    prizes[1] = { name = prize.name, quality = prize.quality, count = prize.count * multi }
  end
  data.last = nil
  data.spin = {
    won = won,
    wins = won and 1 or 0,
    multi = multi,
    free = bet.free,
    freespins = freespins,
    bet = bet,
    chance = bet.chance,
    name = bet.name,
    quality = bet.quality,
    count = bet.count * multi,
    stake = bet.stake,
    frame = 0,
    reel = plan,
    prizes = prizes,
  }
  storage.spins[player.index] = true
end

-- ── Statistik ───────────────────────────────────────────────────────────────
--
-- Pro Spieler: eingesetzter und zurückgewonnener Wert, Drehs, Gewinne, Freispins und
-- der wertvollste Treffer. Eingesetzt zählt nur, was bezahlt wurde (Freispins kosten
-- nichts), zurück zählen Gewinne und Trostpreise. Das Verhältnis zeigt den Hausvorteil.

function gamble.stats(data)
  data.stats = data.stats or { staked = 0, returned = 0, spins = 0, wins = 0, freespins = 0 }
  return data.stats
end

function gamble.reset_stats(data)
  data.stats = nil
end

local function item_value(stack)
  return values.is_selectable(stack.name) and values.stack(stack.name, stack.quality, stack.count) or 0
end

local function record_stats(data, result, wins, prizes)
  local stats = gamble.stats(data)
  stats.spins = stats.spins + 1
  if result.free then
    stats.freespins = stats.freespins + 1
  elseif result.bet then
    stats.staked = stats.staked + result.bet.stake_value * (result.multi or 1)
  end
  if wins > 0 then
    stats.wins = stats.wins + 1
    local hit = { name = result.name, quality = result.quality, count = result.count * wins }
    hit.value = item_value(hit)
    stats.returned = stats.returned + hit.value
    if not stats.best or hit.value > stats.best.value then
      stats.best = hit
    end
  end
  for _, prize in ipairs(prizes) do
    stats.returned = stats.returned + item_value(prize)
  end
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
  -- Freispins gelten ab jetzt, vorher würde der Knopf sie verraten
  if (result.freespins or 0) > 0 and result.bet then
    add_freespins(data, result.bet, result.freespins)
  end
  -- Gewinne und Trostpreise in den Gewinn-Bereich; was nicht passt (z.B. Abbruch beim
  -- Schließen, viele Drehs), ins Inventar, der Rest auf den Boden
  local function pay(paid)
    local stack = { name = paid.name, quality = paid.quality, count = paid.count }
    grow_output(data.output_inventory, stack)
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
  record_stats(data, result, wins, prizes)
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
  if storage.autospins then
    storage.autospins[player_index] = nil
  end
end

return gamble
