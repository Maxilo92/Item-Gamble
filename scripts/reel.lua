-- Walze: eine Reihe Felder rauscht seitlich durch, bremst ab, bleibt irgendwo im
-- Feld stehen und rastet dann in die Mitte des nächsten Feldes ein. Unter dem Pfeil
-- steht am Ende genau das Ergebnisfeld. Gewinnfelder zeigen das Zielitem und kommen
-- in festem Takt (z.B. jedes dritte Feld), dazwischen leere Nieten.
--
-- Spannung kommt aus Tempo und Timing, nicht aus Effekten:
--   kurz    schneller, klarer Dreh - fast immer eine Niete
--   normal  alles möglich
--   lang    die Walze kriecht am Ende, meist ein Gewinn, manchmal ein bitterer
--           Beinahe-Treffer
-- Beinahe-Treffer bleiben an der Kante zum Gewinnfeld hängen und kippen dann zurück
-- (oder rutschen gerade noch davon). Knappe Gewinne schieben sich über die Kante,
-- hängen kurz und rasten dann ein.
--
-- Das Ergebnis steht vorher fest, hier wird nur geplant, wie die Walze dorthin läuft.
-- Der Plan liegt in storage, die Bewegung zählt eigene Frames: Speichern mitten im
-- Dreh und Multiplayer sind sicher.

local reel = {}

reel.SLOT = 40          -- Pixel pro Feld (Slot-Größe)
reel.VISIBLE = 9        -- sichtbare Felder, das mittlere steht unter dem Pfeil
reel.CENTER = 4         -- Index des mittleren Feldes (0-basiert)
local SETTLE = 24       -- Frames für das Einrasten in die Feldmitte

-- frames: Laufzeit bis zum Stehenbleiben, travel: Felder, power: wie lang das Auslaufen
-- sich zieht (höher = längeres Kriechen am Ende), hold: Hängen an der Kante
local TIERS = {
  short = { frames = { 150, 195 }, travel = { 34, 44 }, power = 3, hold = 0 },
  normal = { frames = { 220, 270 }, travel = { 48, 60 }, power = 3, hold = 12 },
  long = { frames = { 300, 370 }, travel = { 58, 70 }, power = 4, hold = 40 },
}

-- Wie weit (in Feldern) die Walze vor dem Einrasten danebensteht. Unter 0,5 bleibt
-- immer das Ergebnisfeld das nächstgelegene.
local EDGE = { 0.42, 0.47 }
local LOOSE = 0.3

-- Jedes wievielte Feld ein Gewinnfeld ist. Nur Optik: Auch bei 1:100.000 soll das
-- Zielitem regelmäßig vorbeiziehen, bei 75 % nicht jedes Feld eins sein.
local function period_for(chance)
  if chance >= 0.4 then
    return 2
  elseif chance >= 0.2 then
    return 3
  elseif chance >= 0.05 then
    return 4
  end
  return 5
end

function reel.is_win(plan, index)
  return index % plan.period == plan.phase
end

local function between(rng, range)
  return range[1] + rng() * (range[2] - range[1])
end

-- Art des Drehs: was passiert, und wie lang er dauert
local function choose_kind(rng, won)
  if won then
    return "win", rng() < 0.65 and "long" or "normal"
  end
  local roll = rng()
  if roll < 0.35 then
    return "near-ahead", rng() < 0.45 and "long" or "normal"
  elseif roll < 0.55 then
    return "near-behind", rng() < 0.3 and "long" or "normal"
  end
  return "miss", rng() < 0.75 and "short" or "normal"
end

-- Plant einen Dreh. rng ist storage.rng, damit auch die Optik deterministisch ist.
function reel.plan(rng, won, chance)
  local period = period_for(chance)
  local plan = { period = period, phase = rng(0, period - 1) }
  local kind, tier_name = choose_kind(rng, won)
  local tier = TIERS[tier_name]

  local stop = rng(tier.travel[1], tier.travel[2]) + reel.CENTER
  local function fits(index)
    if kind == "win" then
      return reel.is_win(plan, index)
    elseif kind == "near-ahead" then
      return not reel.is_win(plan, index) and reel.is_win(plan, index + 1)
    elseif kind == "near-behind" then
      return not reel.is_win(plan, index) and reel.is_win(plan, index - 1)
    end
    return not reel.is_win(plan, index)
  end
  while not fits(stop) do
    stop = stop + 1
  end

  -- Wo die Walze vor dem Einrasten steht: + heißt schon Richtung nächstes Feld
  local drift
  if kind == "near-ahead" then
    drift = between(rng, EDGE)                    -- fast auf dem Gewinn, kippt zurück
  elseif kind == "near-behind" then
    drift = -between(rng, EDGE)                   -- gerade vom Gewinn gerutscht
  elseif kind == "win" and tier_name == "long" then
    drift = -between(rng, EDGE)                   -- gerade noch über die Kante
  else
    drift = (rng() * 2 - 1) * LOOSE
  end

  plan.kind = kind
  plan.tier = tier_name
  plan.stop = stop
  -- Ziel: Mitte des Stoppfeldes genau unter dem Pfeil
  plan.travel = (stop - reel.CENTER) * reel.SLOT
  plan.drift = drift * reel.SLOT
  plan.power = tier.power
  plan.run = rng(tier.frames[1], tier.frames[2])
  -- An der Kante hängen bleibt die Walze nur, wenn es wirklich knapp ist
  plan.hold = math.abs(drift) >= EDGE[1] and tier.hold or 0
  plan.duration = plan.run + plan.hold + SETTLE
  return plan
end

local function ease_in_out(u)
  return u * u * (3 - 2 * u)
end

-- Zurückgelegte Pixel nach frame Frames: schnell los, auslaufen bis knapp neben
-- die Feldmitte, eventuell kurz hängen, dann einrasten.
function reel.position(plan, frame)
  if frame <= plan.run then
    local u = frame / plan.run
    return (plan.travel + plan.drift) * (1 - (1 - u) ^ plan.power)
  end
  frame = frame - plan.run
  if frame <= plan.hold then
    return plan.travel + plan.drift
  end
  local u = math.min((frame - plan.hold) / SETTLE, 1)
  return plan.travel + plan.drift * (1 - ease_in_out(u))
end

-- Erstes sichtbares Feld und wie viele Pixel davon links abgeschnitten sind
function reel.window(position)
  local first = math.floor(position / reel.SLOT)
  return first, math.floor(position - first * reel.SLOT)
end

-- Welches Feld gerade unter dem Pfeil steht
function reel.center_index(position)
  return math.floor((position + (reel.CENTER + 0.5) * reel.SLOT) / reel.SLOT)
end

return reel
