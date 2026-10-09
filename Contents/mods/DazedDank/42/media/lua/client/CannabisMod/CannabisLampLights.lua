-- Makes placed grow lamps actually light the room: a purple glow from the basic lamps and a warm yellow one from the pro lamps.
-- Lights are client-side visuals, rebuilt from the lamps near the player and switched by power and the lamp's timer.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisSchedule"
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
LampLights.RECHECK_MS = 1000  -- how often the known lamps are re-read (and at once when the game hour changes)
LampLights.DISCOVER_EVERY = 30  -- ticks between rows of the slow safety sweep for lamps no event announced

local active = {}             -- tileKey -> { lights = { IsoLightSource... }, pass = n }
local known = {}              -- tileKey -> { x, y, z }: tiles that held a lamp when last seen
local warned = false
local pass = 0                -- counts rechecks, so lamps not reached this time can be told apart without a table
local gone = {}               -- reused list of keys to drop after a recheck
local nextAt, lastHour = 0, nil
local sweep = nil             -- the safety sweep in progress: { cx, cy, z, row }
local sweepWait = 0

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
    local entry = { lights = {}, pass = pass }
    for _ = 1, LampLights.LAYERS[tier] do
        local ok, light = pcall(makeSource, cell, x, y, z, c, radius)
        if ok and light then entry.lights[#entry.lights + 1] = light else warnOnce(light) end
    end
    if #entry.lights > 0 then active[key] = entry end
end

--- Remember a tile that holds a lamp, so the rechecks look at it.
function LampLights.note(x, y, z)
    local key = Config.tileKey(x, y, z)
    if not known[key] then known[key] = { x = x, y = y, z = z } end
    return key
end

--- Make sure the next step re-reads the lamps (a lamp was placed or is about to go).
function LampLights.soon() nextAt = 0 end

--- Switch one known lamp's glow to match its power and timer; false when no lamp is on its tile any more.
local function checkLamp(cell, key, k, needPower, hour)
    local square = cell:getGridSquare(k.x, k.y, k.z)
    if not square then return false end
    local obj, _, def = CannabisMod.World.findIn(square, Config.Light.SPRITES)
    if not obj then return false end
    local md = obj:getModData()
    local schedule = md.DDTimer
    -- DDRoomOff is set by the server while the lamp's grow room panel has no power.
    local on = (not needPower or powered(square)) and not md.DDRoomOff and Config.Timer.isOn(schedule, hour)
    local entry = active[key]
    if on and not entry then addLight(key, k.x, k.y, k.z, def) end
    if on and entry then entry.pass = pass end
    if not on and entry then
        removeLight(key)
        -- One line per switch-off in debug mode, so a glow that won't go out can be traced in console.txt.
        Config.debugLog("lamp glow off at " .. key .. " (timer " .. tostring(schedule) .. ", hour " .. tostring(hour) .. ")")
    end
    return true
end

--- Re-read every known lamp near the player; lamps out of range, on another floor or gone lose their glow.
function LampLights.update()
    local player = getPlayer()
    if not player then return end
    pass = pass + 1
    local cx, cy, cz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local R = LampLights.SCAN_RADIUS
    local cell = getCell()
    local needPower = Config.sandbox("LampsNeedPower")
    local hour = getGameTime():getHour()
    lastHour = hour
    local n = 0
    for key, k in pairs(known) do
        if k.z == cz and math.abs(k.x - cx) <= R and math.abs(k.y - cy) <= R then
            if not checkLamp(cell, key, k, needPower, hour) then n = n + 1 gone[n] = key end
        end
    end
    for i = 1, n do known[gone[i]] = nil gone[i] = nil end
    n = 0
    for key, entry in pairs(active) do
        if entry.pass ~= pass then n = n + 1 gone[n] = key end
    end
    for i = 1, n do removeLight(gone[i]) gone[i] = nil end
end

--- One row of the slow safety sweep: lamps that arrived without an event (or before this file loaded) join the known list.
local function discoverRow(player)
    local R = LampLights.SCAN_RADIUS
    if not sweep then
        sweep = { cx = math.floor(player:getX()), cy = math.floor(player:getY()), z = math.floor(player:getZ()), row = 0 }
    end
    local cell, sprites = getCell(), Config.Light.SPRITES
    local y, z = sweep.cy - R + sweep.row, sweep.z
    for x = sweep.cx - R, sweep.cx + R do
        local square = cell:getGridSquare(x, y, z)
        if square and CannabisMod.World.findIn(square, sprites) then
            if not known[Config.tileKey(x, y, z)] then
                LampLights.note(x, y, z)
                nextAt = 0
            end
        end
    end
    sweep.row = sweep.row + 1
    if sweep.row > 2 * R then sweep = nil end
end

--- Run every tick: re-read the known lamps about once a second or when the hour changes, and sweep a row now and then.
function LampLights.step()
    local player = getPlayer()
    if not player then return end
    sweepWait = sweepWait - 1
    if sweepWait <= 0 then
        sweepWait = LampLights.DISCOVER_EVERY
        discoverRow(player)
    end
    local now = getTimestampMs()
    if now >= nextAt or getGameTime():getHour() ~= lastHour then
        nextAt = now + LampLights.RECHECK_MS
        LampLights.update()
    end
end

-- Lamps reach the known list as their squares load and as they are placed; a removal rechecks soon after it lands.
CannabisMod.World.onSquareLoad("lamp glow", function(square, hits)
    for i = 1, hits.n do
        if hits.info[i].lamp then
            LampLights.note(square:getX(), square:getY(), square:getZ())
            return
        end
    end
end)
CannabisMod.World.onObjectAdded("lamp glow", function(obj, name, info)
    if not info.lamp then return end
    local square = obj:getSquare()
    if square then LampLights.note(square:getX(), square:getY(), square:getZ()) end
    nextAt = 0
end)
CannabisMod.World.onObjectRemoved("lamp glow", function(obj, name, info)
    if info.lamp then nextAt = 0 end
end)

CannabisMod.Ticker.every(1, function()
    local ok, err = pcall(LampLights.step)
    if not ok then
        sweep = nil
        warnOnce(err)
    end
end, "lamp glow")
