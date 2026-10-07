-- Itemwerte: Rohstoffe haben Grundwerte, alles andere ergibt sich aus dem
-- billigsten Rezept. Je mehr Forschung ein Rezept und sein Gebäude brauchen,
-- desto mehr ist das Ergebnis wert (Fortschrittsfaktor). Das Ergebnis liegt in storage.values und wird nur beim
-- Laden neu gerechnet (on_init, on_configuration_changed, /gamble-recalc).
--
-- Qualität und Frische stecken nicht in storage, sondern werden beim Abfragen
-- draufgerechnet. So wirkt eine geänderte Einstellung sofort.

local base = require("scripts.base-values")

local values = {}

local MAX_PASSES = 200   -- Durchläufe über alle Rezepte, bis sich nichts mehr ändert
local MAX_ROUNDS = 10    -- Neustarts (Gutschriften nachziehen, Schleifen ausschließen)
local EPSILON = 1e-6     -- kleinere Verbesserungen zählen nicht als Änderung
-- Nebenprodukte werden gutgeschrieben, senken die Kosten aber höchstens auf 10 %
local MIN_COST_SHARE = 0.1

-- Was in der Welt abgebaut oder abgepumpt wird. Taucht so ein Produkt weder in
-- base-values.lua noch als Rezeptergebnis auf, bekommt es den Auto-Grundwert.
-- simple-entity fehlt absichtlich: Wracks lassen Stahlplatten und Zahnräder fallen.
local NATURAL_ENTITY_TYPES = {
  ["resource"] = true,
  ["tree"] = true,
  ["plant"] = true,
  ["fish"] = true,
}

local function key(type, name)
  return type .. "/" .. name
end
values.key = key

local function prototype_exists(type, name)
  if type == "item" then
    return prototypes.item[name] ~= nil
  end
  return prototypes.fluid[name] ~= nil
end

local function ignore_reason(recipe)
  if recipe.hidden or recipe.is_parameter or recipe.parameter then
    return "hidden"
  end
  if base.ignored_recipes[recipe.name] then
    return "list"
  end
  if base.ignored_categories[recipe.category] then
    return "category"
  end
  if recipe.subgroup and base.ignored_subgroups[recipe.subgroup.name] then
    return "subgroup"
  end
end

-- Rezept in Nettomengen zerlegen. Was rein- und wieder rausgeht (Kovarex,
-- Pentapod-Ei, Kohleverflüssigung), hebt sich auf. Produkte, die nur als
-- Katalysator zurückkommen (heißes Fluoroketon beim Quantenprozessor), werden
-- gutgeschrieben statt mit dem eigentlichen Produkt die Kosten zu teilen.
local function parse_recipe(recipe)
  local consumed = {}
  for _, ingredient in pairs(recipe.ingredients) do
    local k = key(ingredient.type, ingredient.name)
    consumed[k] = (consumed[k] or 0) + ingredient.amount
  end

  local outputs = {}
  local order = {}
  for _, product in pairs(recipe.products) do
    local amount = product.amount or (product.amount_min + product.amount_max) / 2
    local expected = amount * (product.probability or 1) + (product.extra_count_fraction or 0)
    if expected > 0 then
      local k = key(product.type, product.name)
      local out = outputs[k]
      if not out then
        out = { amount = 0, ignored = 0, fresh = 0 }
        outputs[k] = out
        order[#order + 1] = k
      end
      out.amount = out.amount + expected
      out.ignored = out.ignored + math.min(product.ignored_by_productivity or 0, expected)
      out.fresh = out.fresh + expected * (1 - (product.percent_spoiled or 0))
    end
  end

  local parsed = { name = recipe.name, time = recipe.energy, inputs = {}, targets = {}, credits = {} }
  for _, k in ipairs(order) do
    local out = outputs[k]
    local used = consumed[k] or 0
    consumed[k] = nil
    local net = out.amount - used
    if net < 0 then
      parsed.inputs[#parsed.inputs + 1] = { key = k, amount = -net }
    elseif net > 0 then
      local fresh_ratio = out.fresh / out.amount
      local returned = math.min(math.max(out.ignored - used, 0), net)
      local made = net - returned
      if returned > 0 then
        parsed.credits[#parsed.credits + 1] = { key = k, amount = returned * fresh_ratio }
      end
      if made > 0 then
        parsed.targets[#parsed.targets + 1] = { key = k, amount = made * fresh_ratio }
      end
    end
  end
  for k, amount in pairs(consumed) do
    parsed.inputs[#parsed.inputs + 1] = { key = k, amount = amount }
  end

  -- Gibt es kein anderes Produkt, ist das "zurückgegebene" das eigentliche Ergebnis.
  -- Die Runtime markiert z.B. beim Abkühlen von Fluoroketon das kalte als ignored_by_productivity.
  if #parsed.targets == 0 then
    parsed.targets, parsed.credits = parsed.credits, {}
  end

  -- Ohne Zutaten lässt sich nichts ableiten (z.B. Biter-Eier aus dem Spawner)
  if #parsed.inputs == 0 or #parsed.targets == 0 then
    return nil
  end
  return parsed
end

local function natural_products()
  local found = {}
  local function add(mineable)
    if mineable and mineable.minable and mineable.products then
      for _, product in pairs(mineable.products) do
        found[key(product.type, product.name)] = true
      end
    end
  end
  for _, entity in pairs(prototypes.entity) do
    if NATURAL_ENTITY_TYPES[entity.type] then
      add(entity.mineable_properties)
    end
  end
  for _, chunk in pairs(prototypes.asteroid_chunk) do
    add(chunk.mineable_properties)
  end
  for _, tile in pairs(prototypes.tile) do
    if tile.fluid then
      found[key("fluid", tile.fluid.name)] = true
    end
  end
  return found
end

-- Forschungszeit in Sekunden für jede Technologie samt aller Vorgänger.
-- Gezählt werden Laborsekunden (Einheiten × Zeit pro Einheit), Packsorten zählen nicht extra.
local function research_times()
  local own = {}
  for name, tech in pairs(prototypes.technology) do
    own[name] = tech.research_unit_count * tech.research_unit_energy / 60
  end
  local total = {}
  for name, tech in pairs(prototypes.technology) do
    local seen, stack, sum = { [name] = true }, { tech }, 0
    while #stack > 0 do
      local current = table.remove(stack)
      sum = sum + own[current.name]
      for prerequisite_name, prerequisite in pairs(current.prerequisites) do
        if not seen[prerequisite_name] then
          seen[prerequisite_name] = true
          stack[#stack + 1] = prerequisite
        end
      end
    end
    total[name] = sum
  end
  return total
end

-- Kürzeste Forschungszeit, nach der ein Rezept freigeschaltet ist
local function recipe_unlock_times()
  local times = research_times()
  local unlock = {}
  for name, tech in pairs(prototypes.technology) do
    for _, effect in pairs(tech.effects) do
      if effect.type == "unlock-recipe" then
        local current = unlock[effect.recipe]
        if not current or times[name] < current then
          unlock[effect.recipe] = times[name]
        end
      end
    end
  end
  return unlock
end

-- Pro Rezeptkategorie: Welche Gebäude-Items stellen sie her, geht es von Hand?
local function crafting_machines()
  local by_category = {}
  for _, entity in pairs(prototypes.entity) do
    local categories = entity.crafting_categories
    if categories then
      local items = entity.items_to_place_this
      for category in pairs(categories) do
        local machines = by_category[category]
        if not machines then
          machines = { items = {} }
          by_category[category] = machines
        end
        if entity.type == "character" then
          machines.hand = true
        elseif items then
          for _, item in pairs(items) do
            machines.items[#machines.items + 1] = key("item", item.name)
          end
        end
      end
    end
  end
  return by_category
end

-- Fortschritt des frühesten Gebäudes, das die Kategorie herstellt. nil, solange
-- noch keins einen Wert hat (oder es gar keins gibt).
local function machine_progress(machines, progress)
  if not machines then
    return nil
  end
  if machines.hand then
    return 0
  end
  local best
  for _, item in ipairs(machines.items) do
    local p = progress[item]
    if p and (not best or p < best) then
      best = p
    end
  end
  return best
end

local function progress_factor(seconds, weight)
  return 1 + weight * math.log(1 + seconds / base.progress_scale, 10)
end
values.progress_factor = progress_factor

local function copy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = v
  end
  return c
end

-- Bellman-Ford über die Rezepte: Werte sinken nur, das billigste Rezept gewinnt.
-- Pro Item gibt es den Materialwert (Zutaten + Craftzeit) und den Fortschritt
-- (Forschungszeit, bis man es herstellen kann). Verglichen wird der Endwert
-- Material × Fortschrittsfaktor, weitergereicht wird nur das Material. So
-- multipliziert sich der Faktor über lange Ketten nicht auf.
-- Gutschriften für Nebenprodukte kommen aus credit_material (Ergebnis der Vorrunde),
-- damit ein später billiger werdendes Nebenprodukt nicht falsch hängen bleibt.
local function relax(recipes, excluded, state, credit_material, machines, weight)
  local value, material, progress, source = state.value, state.material, state.progress, state.source
  local changed
  for _ = 1, MAX_PASSES do
    changed = {}
    local any = false
    for _, recipe in ipairs(recipes) do
      if not excluded[recipe.name] then
        local cost = recipe.time * base.time_value
        local reached = machine_progress(machines[recipe.category], progress)
        local complete = reached ~= nil
        if complete then
          reached = math.max(reached, recipe.research)
          for _, input in ipairs(recipe.inputs) do
            local m = material[input.key]
            if not m then
              complete = false
              break
            end
            cost = cost + m * input.amount
            reached = math.max(reached, progress[input.key])
          end
        end
        if complete then
          local credit = 0
          for _, c in ipairs(recipe.credits) do
            credit = credit + (credit_material[c.key] or 0) * c.amount
          end
          cost = math.max(cost - credit, cost * MIN_COST_SHARE)
          local share = cost / #recipe.targets
          local factor = progress_factor(reached, weight)
          for _, target in ipairs(recipe.targets) do
            local m = share / target.amount
            local candidate = m * factor
            -- Mindestwert (base-values.lua): Material mit hochziehen, damit es konsistent weitergereicht wird
            local floor = base.min_value[target.key]
            if floor and candidate < floor then
              candidate = floor
              m = floor / factor
            end
            local current = value[target.key]
            if candidate > 0 and (not current or candidate < current * (1 - EPSILON)) then
              value[target.key] = candidate
              material[target.key] = m
              progress[target.key] = reached
              source[target.key] = recipe.name
              changed[recipe.name] = true
              any = true
            end
          end
        end
      end
    end
    if not any then
      return true
    end
  end
  return false, changed
end

local function same_values(a, b)
  for k, v in pairs(a) do
    local w = b[k]
    if not w or math.abs(v - w) > math.max(v, w) * 1e-4 then
      return false
    end
  end
  for k in pairs(b) do
    if not a[k] then
      return false
    end
  end
  return true
end

function values.rebuild()
  local weight = settings.global["item-gamble-progression-weight"].value

  local seed_value, seed_source = {}, {}
  for _, type in pairs({ "item", "fluid" }) do
    for name, v in pairs(base[type]) do
      if prototype_exists(type, name) then
        seed_value[key(type, name)] = v
        seed_source[key(type, name)] = "base"
      end
    end
  end

  local unlock = recipe_unlock_times()
  local recipes, ignored = {}, 0
  for _, recipe in pairs(prototypes.recipe) do
    if ignore_reason(recipe) then
      ignored = ignored + 1
    else
      local parsed = parse_recipe(recipe)
      if parsed then
        parsed.category = recipe.category
        -- Nie per Technologie freigeschaltet (z.B. per Skript anderer Mods): zählt wie von Anfang an da
        parsed.research = recipe.enabled and 0 or unlock[recipe.name] or 0
        recipes[#recipes + 1] = parsed
      end
    end
  end

  local produced = {}
  for _, recipe in ipairs(recipes) do
    for _, target in ipairs(recipe.targets) do
      produced[target.key] = true
    end
  end
  for k in pairs(natural_products()) do
    if not seed_value[k] and not produced[k] then
      seed_value[k] = k:sub(1, 5) == "item/" and base.auto_item or base.auto_fluid
      seed_source[k] = "auto"
    end
  end

  -- Grundwerte sind fest: Als Rezeptergebnis werden sie nur gutgeschrieben
  local usable = {}
  for _, recipe in ipairs(recipes) do
    local targets = {}
    for _, target in ipairs(recipe.targets) do
      if seed_value[target.key] then
        recipe.credits[#recipe.credits + 1] = target
      else
        targets[#targets + 1] = target
      end
    end
    recipe.targets = targets
    if #targets > 0 then
      usable[#usable + 1] = recipe
    end
  end

  local seed_progress = {}
  for k in pairs(seed_value) do
    seed_progress[k] = 0
  end

  local machines = crafting_machines()
  local excluded = {}
  local credit_material = seed_value
  local state, previous
  for _ = 1, MAX_ROUNDS do
    state = {
      value = copy(seed_value),
      material = copy(seed_value),
      progress = copy(seed_progress),
      source = copy(seed_source),
    }
    local stable, changed = relax(usable, excluded, state, credit_material, machines, weight)
    if stable then
      if previous and same_values(previous, state.value) then
        break
      end
      previous = state.value
      credit_material = state.material
    else
      -- Wert fällt immer weiter: Schleife. Beteiligte Rezepte raus und neu anfangen.
      for name in pairs(changed) do
        excluded[name] = true
      end
      credit_material = seed_value
      previous = nil
    end
  end

  local excluded_list = {}
  for name in pairs(excluded) do
    excluded_list[#excluded_list + 1] = name
  end
  table.sort(excluded_list)

  storage.values = {
    value = state.value,
    progress = state.progress,
    source = state.source,
    excluded = excluded_list,
    recipe_count = #usable,
    ignored_count = ignored,
    tick = game.tick,
  }
  log(string.format("[item-gamble] Werte berechnet: %d Rezepte genutzt, %d ignoriert, %d wegen Schleifen ausgeschlossen",
    #usable, ignored, #excluded_list))
end

-- Forschungszeit in Sekunden, bis man das Item herstellen kann
function values.progress(type, name)
  local data = storage.values
  return data and data.progress[key(type, name)]
end

-- Wert eines einzelnen, normalen, frischen Items (oder einer Flüssigkeitseinheit)
function values.unit(type, name)
  local data = storage.values
  return data and data.value[key(type, name)]
end

function values.source(type, name)
  local data = storage.values
  return data and data.source[key(type, name)]
end

function values.quality_factor(quality)
  local prototype = prototypes.quality[quality or "normal"]
  local level = prototype and prototype.level or 0
  return settings.global["item-gamble-quality-multiplier"].value ^ level
end

-- Gesamtwert eines Stacks. spoil_percent wie LuaItemStack.spoil_percent (0 = frisch).
function values.stack(name, quality, count, spoil_percent)
  local unit = values.unit("item", name)
  if not unit then
    return nil
  end
  return unit * values.quality_factor(quality) * count * (1 - (spoil_percent or 0))
end

function values.is_selectable(name)
  local prototype = prototypes.item[name]
  return prototype ~= nil
    and not prototype.hidden
    and not prototype.parameter
    and values.unit("item", name) ~= nil
end

-- Gewinnchance für einen Einsatz- und einen Zielwert.
-- Gibt chance, r, grund zurück. grund ist nil, "no-value", "lower" (Ziel billiger
-- als Einsatz, gesperrt) oder "below-min" (Chance unter der Minimalchance).
function values.chance(stake_value, target_value)
  if not stake_value or not target_value or stake_value <= 0 then
    return nil, nil, "no-value"
  end
  local r = target_value / stake_value
  if r < 1 then
    return nil, r, "lower"
  end
  local max = settings.global["item-gamble-max-chance"].value
  local min = math.min(settings.global["item-gamble-min-chance"].value, max)
  local chance = max / r
  if chance < min then
    return chance, r, "below-min"
  end
  return chance, r, nil
end

return values
