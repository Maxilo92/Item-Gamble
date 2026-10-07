-- Walze: eine Reihe Felder rauscht seitlich durch und bremst ab, bis unter dem
-- Pfeil in der Mitte das Ergebnisfeld steht. Gewinnfelder zeigen das Zielitem,
-- Nieten sind leer.
--
-- Das Ergebnis steht vorher fest. Hier wird nur geplant, wie die Walze dorthin
-- läuft: welche Felder Gewinne zeigen, wo sie stoppt, wie lange sie läuft. Alles
-- liegt in storage und hängt nur am Tick, also überlebt es Speichern und läuft im
-- Multiplayer auf allen Rechnern gleich.

local reel = {}

reel.SLOT = 40          -- Pixel pro Feld (Slot-Größe)
reel.VISIBLE = 9        -- sichtbare Felder, das mittlere steht unter dem Pfeil
reel.CENTER = 4         -- Index des mittleren Feldes (0-basiert)
reel.DURATION = 270     -- Ticks, 4,5 Sekunden
local MIN_TRAVEL = 50   -- so viele Felder rauschen mindestens durch
local MAX_TRAVEL = 64
local EDGE = 6          -- so nah an die Feldkante darf der Pfeil am Ende kommen

-- Wie oft Gewinnfelder auf der Walze auftauchen. Nur Optik: Bei 1:100.000 soll
-- die Walze trotzdem ab und zu das Zielitem zeigen, bei 75 % nicht nur Gewinne.
local function visual_density(chance)
  return math.max(0.08, math.min(0.45, chance))
end

-- Plant einen Dreh. rng ist storage.rng, damit auch die Optik deterministisch ist.
function reel.plan(rng, won, chance)
  local stop = rng(MIN_TRAVEL, MAX_TRAVEL) + reel.CENTER
  local density = visual_density(chance)
  local symbols = {}
  for i = 0, stop + reel.VISIBLE do
    symbols[i] = rng() < density
  end
  symbols[stop] = won
  -- Knapp daneben: Bei einer Niete liegt oft ein Gewinnfeld direkt neben dem Stopp
  if not won and rng() < 0.5 then
    symbols[stop + (rng() < 0.5 and -1 or 1)] = true
  end
  -- Der Pfeil zeigt auf die Mitte des sichtbaren Bereichs. Damit Feld "stop" darunter
  -- liegt, steht die Walze am Ende so, dass seine Mitte (plus etwas Zufall) dort ist.
  local jitter = (rng() - 0.5) * (reel.SLOT - 2 * EDGE)
  local travel = (stop - reel.CENTER) * reel.SLOT + jitter
  return { symbols = symbols, travel = travel, stop = stop }
end

-- Zurückgelegte Pixel nach elapsed Ticks: schnell los, sanft auslaufen (kubisch)
function reel.position(plan, elapsed)
  local u = math.min(elapsed / reel.DURATION, 1)
  return plan.travel * (1 - (1 - u) ^ 3)
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
