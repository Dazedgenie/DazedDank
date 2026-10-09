-- Makes placed grow lamps actually light the room: a purple glow from the basic lamps and a warm yellow one from the pro lamps.
-- Lights are client-side visuals, rebuilt from the lamps near the player and switched by power and the lamp's timer.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisWorld"

local Config = CannabisMod.Config

local LampLights = {}
CannabisMod.LampLights = LampLights

-- Light colours by lamp tier: basic lamps run blurple LEDs, pro lamps a strong HPS-style yellow-orange.
LampLights.COLORS = {
    basic = { 0.85, 0.25, 1.00 },
    pro   = { 1.00, 0.62, 0.12 },
}
-- How many light sources each tier stacks on its tile: the purple stacks four so it reads strongly in a lit room.
LampLights.LAYERS = { basic = 4, pro = 3 }
LampLights.SCAN_RADIUS = 30   -- tiles around the player that get lamp lights
LampLights.ROWS_PER_TICK = 1  -- rows of the scan area read each tick, so a full pass takes about a second

local active = {}             -- tileKey -> { lights = { IsoLightSource... } }
local warned = false

-- The pass in progress: it reads one row of squares per tick around a centre fixed when the pass began.
local sweep = nil             -- { cx, cy, z, row, seen = { tileKey = true } }

--- Print the first failure to console.txt so a changed game API shows up instead of silently giving no light.
local function warnOnce(err)
    if warned then return end
    warned = true
    print("[DazedDank] lamp lights failed: " .. tostring(err))
end

--- Colour tier for a lamp definition: pro-ceiling lamps are yellow, the rest purple.
function LampLights.tier(def)
    return def.cap >= Config.LightCap.GOOD_LAMP and "pro" or "basic"
end

--- Light radius in tiles for a lamp: a little past the area it grows plants in.
function LampLights.radius(def)
    return math.ceil(def.radius) + 2
end

local powered = CannabisMod.World.isPowered

--- Switch one light source off and take it out of the cell.
local function dropSource(cell, light)
    light:setActive(false)
    cell:removeLamppost(light)
end

--- Switch a lamp off: deactivate and remove each of its light sources. Only these two calls are safe with Build 42's lighting engine.
local function removeLight(key)
    local entry = active[key]
    if not entry then return end
    local cell = getCell()
    for _, light in ipairs(entry.lights) do pcall(dropSource, cell, light) end
    active[key] = nil
end

--- Make one light source and add it to the cell.
local function makeSource(cell, x, y, z, c, radius)
    local light = IsoLightSource.new(x, y, z, c[1], c[2], c[3], radius)
    cell:addLamppost(light)
    return light
end

local function addLight(key, x, y, z, def)
    local tier = LampLights.tier(def)
    local c = LampLights.COLORS[tier]
    local radius = LampLights.radius(def)
    local cell = getCell()
    local entry = { lights = {} }
    for _ = 1, LampLights.LAYERS[tier] do
        local ok, light = pcall(makeSource, cell, x, y, z, c, radius)
        if ok and light then entry.lights[#entry.lights + 1] = light else warnOnce(light) end
    end
    if #entry.lights > 0 then active[key] = entry end
end

--- Read one row of the pass: switch each lamp's glow to match its power and timer, and note which lamps are still there.
local function scanRow(cell, s, needPower, hour)
    local sprites, isOn = Config.Light.SPRITES, Config.Timer.isOn
    local R, z = LampLights.SCAN_RADIUS, s.z
    local y = s.cy - R + s.row
    for x = s.cx - R, s.cx + R do
        local square = cell:getGridSquare(x, y, z)
        if square then
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                local sprite = obj:getSprite()
                local def = sprite and sprites[sprite:getName()]
                if def then
                    local key = Config.tileKey(x, y, z)
                    s.seen[key] = true
                    local md = obj:getModData()
                    local schedule = md.DDTimer
                    -- DDRoomOff is set by the server while the lamp's grow room panel has no power.
                    local on = (not needPower or powered(square)) and not md.DDRoomOff and isOn(schedule, hour)
                    if on and not active[key] then addLight(key, x, y, z, def) end
                    if not on and active[key] then
                        removeLight(key)
                        -- One line per switch-off in debug mode, so a glow that won't go out can be traced in console.txt.
                        Config.debugLog("lamp glow off at " .. key .. " (timer " .. tostring(schedule) .. ", hour " .. tostring(hour) .. ")")
                    end
                    break
                end
            end
        end
    end
end

--- Close a finished pass: lamps it didn't see were picked up, or left behind when the player moved or changed floor.
local function finishSweep(s)
    local gone = {}
    for key in pairs(active) do
        if not s.seen[key] then gone[#gone + 1] = key end
    end
    for _, key in ipairs(gone) do removeLight(key) end
end

--- Advance the scan by a few rows, starting a new pass around the player when the last one is done.
function LampLights.step()
    local player = getPlayer()
    if not player then return end
    local R = LampLights.SCAN_RADIUS
    if not sweep then
        sweep = { cx = math.floor(player:getX()), cy = math.floor(player:getY()), z = math.floor(player:getZ()),
                  row = 0, seen = {} }
    end
    local cell = getCell()
    local needPower = Config.sandbox("LampsNeedPower")
    local hour = getGameTime():getHour()
    for _ = 1, LampLights.ROWS_PER_TICK do
        scanRow(cell, sweep, needPower, hour)
        sweep.row = sweep.row + 1
        if sweep.row > 2 * R then
            finishSweep(sweep)
            sweep = nil
            return
        end
    end
end

--- Run one whole pass at once (used by tests and when a pass must finish now).
function LampLights.update()
    sweep = nil
    repeat LampLights.step() until sweep == nil or not getPlayer()
end

Events.OnTick.Add(function()
    local ok, err = pcall(LampLights.step)
    if not ok then
        sweep = nil
        warnOnce(err)
    end
end)
