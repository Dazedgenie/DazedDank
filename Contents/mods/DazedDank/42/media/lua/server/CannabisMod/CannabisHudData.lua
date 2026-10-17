-- Read-only data for other Dazed mods (the Dazed HUD overlay), written onto synced IsoObject ModData.
-- A client can only read synced object ModData, not the server's global ModData where plants and rooms live.
--   md.DDHud     on a plant's plot object:  { stage, stageStartAt, nextStageAt }  (stage = Config.STAGE index, times in world hours)
--   md.DDRoomHud on a room's panel object:  { temp, hum, tLo, tHi, hLo, hHi, plants, stressed }
-- Values are rounded, and an object is only transmitted when a rounded value differs from what it already holds.
-- Standalone: nothing here needs Dazed HUD or Core. The helpers below are pure so tests can call them directly.

if isClient() then return end

local Hud = {}
CannabisMod = CannabisMod or {}
CannabisMod.HudData = Hud

Hud.PLANT_KEY = "DDHud"
Hud.ROOM_KEY = "DDRoomHud"

local floor = math.floor

--- Round to a step (0.1, 0.01, 1...).
local function round(v, step)
    local inv = floor(1 / step + 0.5)  -- dividing by a whole number keeps 24.2 exactly 24.2
    return floor(v * inv + 0.5) / inv
end
Hud.round = round

--- Keys of each table, so changed() and the builders agree on the fields.
Hud.PLANT_FIELDS = { "stage", "stageStartAt", "nextStageAt" }
Hud.ROOM_FIELDS = { "temp", "hum", "tLo", "tHi", "hLo", "hHi", "plants", "stressed" }

--- The plant's HUD table, or nil when the record has no stage. Times are world hours rounded to 0.01.
function Hud.buildPlant(plant)
    if type(plant) ~= "table" or type(plant.stage) ~= "number" then return nil end
    return {
        stage = plant.stage,
        stageStartAt = plant.stageStartAt and round(plant.stageStartAt, 0.01) or nil,
        nextStageAt = plant.nextStageAt and round(plant.nextStageAt, 0.01) or nil,
    }
end

--- How many of these plant records carry a warning (a cold night is a deliberate cost, not a warning).
function Hud.countStressed(plants)
    local n = 0
    for _, p in ipairs(plants or {}) do
        local hit = false
        for name, on in pairs(p.warnings or {}) do
            if on and name ~= "coldNight" then hit = true end
        end
        if hit then n = n + 1 end
    end
    return n
end

--- The room's HUD table from its record, its current target bands ({tLo,tHi,hLo,hHi}) and its living plants,
--- or nil without a reading. Temperature is rounded to 0.1 C and humidity to 1 percent.
function Hud.buildRoom(room, targets, plants)
    if type(room) ~= "table" or type(room.temp) ~= "number" or type(room.hum) ~= "number" or type(targets) ~= "table" then return nil end
    return {
        temp = round(room.temp, 0.1), hum = round(room.hum, 1),
        tLo = round(targets.tLo, 0.1), tHi = round(targets.tHi, 0.1),
        hLo = round(targets.hLo, 1), hHi = round(targets.hHi, 1),
        plants = #(plants or {}), stressed = Hud.countStressed(plants),
    }
end

--- True when two HUD tables differ (a missing table counts as different from a present one).
--- Numbers compare within 1e-6 so a rounded value never flips on float noise.
function Hud.changed(old, new)
    if old == nil and new == nil then return false end
    if old == nil or new == nil then return true end
    local seen = {}
    for k, v in pairs(new) do
        seen[k] = true
        local o = old[k]
        if type(v) == "number" and type(o) == "number" then
            if math.abs(v - o) > 1e-6 then return true end
        elseif o ~= v then
            return true
        end
    end
    for k in pairs(old) do
        if not seen[k] then return true end
    end
    return false
end

--- Write `tbl` (or nil to clear) under `key` on an IsoObject's ModData and transmit, only when it differs. Returns true if sent.
--- Every object access is guarded.
local function write(obj, key, tbl)
    if not obj then return false end
    local ok, sent = pcall(function()
        local md = obj:getModData()
        if not Hud.changed(md[key], tbl) then return false end
        md[key] = tbl
        obj:transmitModData()
        return true
    end)
    return ok and sent == true
end

--- Write a plant's table onto its plot object. Returns true when it was transmitted.
function Hud.writePlant(obj, plant)
    return write(obj, Hud.PLANT_KEY, Hud.buildPlant(plant))
end

--- Clear a plant's table (removed or no longer cannabis). Returns true when it was transmitted.
function Hud.clearPlant(obj)
    return write(obj, Hud.PLANT_KEY, nil)
end

--- Write a room's table onto its panel object. Returns true when it was transmitted.
function Hud.writeRoom(obj, room, targets, plants)
    return write(obj, Hud.ROOM_KEY, Hud.buildRoom(room, targets, plants))
end

return Hud
