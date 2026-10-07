-- Walze: eine Reihe Felder rauscht seitlich durch, bremst ab, bleibt irgendwo im
-- Feld stehen und rastet dann in die Mitte des nächsten Feldes ein. Unter dem Pfeil
-- steht am Ende genau das Ergebnisfeld. Gewinnfelder zeigen das Zielitem und kommen
-- in festem Takt (z.B. jedes dritte Feld), dazwischen leere Nieten.
--
-- Das Ergebnis steht vorher fest, hier wird nur geplant, wie die Walze dorthin läuft.
-- Der Plan liegt in storage, die Bewegung zählt eigene Frames: Speichern mitten im
-- Dreh und Multiplayer sind sicher.

local reel = {}

reel.SLOT = 40          -- Pixel pro Feld (Slot-Größe)
reel.VISIBLE = 9        -- sichtbare Felder, das mittlere steht unter dem Pfeil
reel.CENTER = 4         -- Index des mittleren Feldes (0-basiert)
reel.DURATION = 270     -- Frames insgesamt, 4,5 Sekunden
local SETTLE = 24       -- davon die letzten Frames: Einrasten in die Feldmitte
local MIN_TRAVEL = 50   -- so viele Felder rauschen mindestens durch
local MAX_TRAVEL = 64
local MAX_DRIFT = 0.4   -- so weit (in Feldern) darf die Walze vor dem Einrasten danebenstehen

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

-- Plant einen Dreh. rng ist storage.rng, damit auch die Optik deterministisch ist.
function reel.plan(rng, won, chance)
  local period = period_for(chance)
  local plan = { period = period, phase = rng(0, period - 1) }
  local stop = rng(MIN_TRAVEL, MAX_TRAVEL) + reel.CENTER
  if won then
    while not reel.is_win(plan, stop) do
      stop = stop + 1
    end
  else
    -- Niete: meistens knapp neben einem Gewinnfeld, sonst irgendein leeres Feld
    while reel.is_win(plan, stop) do
      stop = stop + 1
    end
    -- auf das Feld direkt vor dem nächsten Gewinnfeld schieben
    if rng() < 0.6 then
      while not reel.is_win(plan, stop + 1) do
        stop = stop + 1
      end
    end
  end
  plan.stop = stop
  -- Ziel: Mitte des Stoppfeldes genau unter dem Pfeil
  plan.travel = (stop - reel.CENTER) * reel.SLOT
  plan.drift = (rng() * 2 - 1) * MAX_DRIFT * reel.SLOT
  return plan
end

local function ease_out_cubic(u)
  return 1 - (1 - u) ^ 3
end

local function ease_in_out(u)
  return u * u * (3 - 2 * u)
end

-- Zurückgelegte Pixel nach frame Frames: schnell los, auslaufen bis knapp neben
-- die Feldmitte, dann einrasten.
function reel.position(plan, frame)
  local run = reel.DURATION - SETTLE
  if frame <= run then
    return (plan.travel + plan.drift) * ease_out_cubic(frame / run)
  end
  local u = math.min((frame - run) / SETTLE, 1)
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
