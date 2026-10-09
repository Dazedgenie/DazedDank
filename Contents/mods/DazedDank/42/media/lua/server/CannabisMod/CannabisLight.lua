-- Works out each plant's light every 10 game minutes from the sun or a powered
-- grow lamp, and stalls plants that get none. Lamps are placed furniture
-- matched by sprite, each reaching its own radius.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisWorld"

local Config   = CannabisMod.Config
local Registry = CannabisMod.Registry

local Light = {}
CannabisMod.Light = Light

local isPowered = CannabisMod.World.isPowered

--- True if this square has power for a lamp (the grow room panel reads this too).
Light.isPowered = isPowered

--- False when the tile sits in a grow room whose panel has no power, so its lamps are dead.
local function roomPowered(x, y, z)
    local Rooms = CannabisMod.Rooms
    return not Rooms or Rooms.poweredAt(x, y, z) ~= false
end

--- Schedule of the timer on a lamp tile, or nil for a lamp without one (24/0).
local function scheduleAt(x, y, z)
    local Timers = CannabisMod.Timers
    return Timers and Timers.scheduleAt(x, y, z) or nil
end

-- Placed lamps by tile: lampIndex[z][x][y] = true, fed by square loads, placements and an hourly full read, and checked
-- against the square when read so a lamp taken away drops out. Ground lamp items raise no event, so squares are still read for them.
local lampIndex = {}

--- Note a placed lamp on a tile so the light scan reads that square.
function Light.noteLamp(x, y, z)
    local floor = lampIndex[z]
    if not floor then floor = {} lampIndex[z] = floor end
    local column = floor[x]
    if not column then column = {} floor[x] = column end
    column[y] = true
end

--- True if a placed lamp was last seen on this tile.
local function indexed(x, y, z)
    local floor = lampIndex[z]
    local column = floor and floor[x]
    return column ~= nil and column[y] == true
end

local function forget(x, y, z)
    local column = lampIndex[z] and lampIndex[z][x]
    if column then column[y] = nil end
end

CannabisMod.World.onSquareLoad("lamp index", function(square, hits)
    for i = 1, hits.n do
        if hits.info[i].lamp then
            Light.noteLamp(square:getX(), square:getY(), square:getZ())
            return
        end
    end
end)
CannabisMod.World.onObjectAdded("lamp index", function(obj, name, info)
    if not info.lamp then return end
    local square = obj:getSquare()
    if square then Light.noteLamp(square:getX(), square:getY(), square:getZ()) end
end)

-- During the plant tick every plant asks about the same squares, so each square's lamps are read once per tick.
-- tickCache[z][x][y] = list of { def, schedule, powered }, or false for a square with none (nil = not read yet).
local tickCache = nil
-- Every FULL_SCAN_TICKS plant ticks the scan also reads unindexed squares, in case a placement raised no event.
Light.FULL_SCAN_TICKS = 6
local tickCount, fullScan = 0, false

--- Start sharing square reads between plants (the Registry calls this at the top of its tick).
function Light.beginTick()
    tickCache = {}
    fullScan = tickCount % Light.FULL_SCAN_TICKS == 0
    tickCount = tickCount + 1
end

--- Stop sharing, so later reads see the world as it is.
function Light.endTick() tickCache, fullScan = nil, false end

--- The lamps on one square, as a list of { def, schedule, powered }, or false when there are none.
local function readSquare(square, x, y, z)
    local found = false
    local sprites, items = Config.Light.SPRITES, Config.Light.ITEMS
    -- Only a tile the index knows can hold a placed lamp; one whose lamp has gone leaves the index.
    local known = indexed(x, y, z)
    if known or fullScan then
        local any = false
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local sprite = objects:get(i):getSprite()
            local def = sprite and sprites[sprite:getName()]
            if def then
                any = true
                found = found or {}
                found[#found + 1] = { def = def, schedule = scheduleAt(x, y, z), powered = isPowered(square) and roomPowered(x, y, z) }
            end
        end
        if not any and known then forget(x, y, z) end
        if any and not known then Light.noteLamp(x, y, z) end
    end
    -- Loose lamp items lying on the ground have no timer.
    local worldItems = square:getWorldObjects()
    for i = 0, worldItems:size() - 1 do
        local item = worldItems:get(i):getItem()
        local def = item and items[item:getFullType()]
        if def then
            found = found or {}
            found[#found + 1] = { def = def, powered = isPowered(square) }
        end
    end
    return found
end

--- The lamps on the square at x, y, z: from this tick's shared reads when there are any.
local function lampsOn(cell, x, y, z)
    if not tickCache then
        local square = cell:getGridSquare(x, y, z)
        return square and readSquare(square, x, y, z) or false
    end
    local floor = tickCache[z]
    if not floor then floor = {} tickCache[z] = floor end
    local column = floor[x]
    if not column then column = {} floor[x] = column end
    local lamps = column[y]
    if lamps == nil then
        local square = cell:getGridSquare(x, y, z)
        lamps = square and readSquare(square, x, y, z) or false
        column[y] = lamps
    end
    return lamps
end

--- Add every lamp within R of a plant at x, y, z to `out` (run under pcall by lampsAt).
local function scanLamps(out, x, y, z, R, hour, range, needPower, roomKey)
    local reaches, isOn, isLongDay = Config.Light.reaches, Config.Timer.isOn, Config.Timer.isLongDay
    local Rooms = CannabisMod.Rooms
    local cell = getCell()
    for dx = -R, R do
        for dy = -R, R do
            local lamps = lampsOn(cell, x + dx, y + dy, z)
            if lamps then
                for _, lamp in ipairs(lamps) do
                    local def = lamp.def
                    local outsideLeak = roomKey and Rooms.keyAt(x + dx, y + dy, z) ~= roomKey
                        and Rooms.lampLeak(roomKey, x, y, x + dx, y + dy, def, range) or nil
                    local blocked = outsideLeak ~= nil and outsideLeak < 1
                    -- A lit veg lamp seeping in round a closed door is a small leak, not the plant's light.
                    if blocked and outsideLeak > 0 and isLongDay(lamp.schedule) and isOn(lamp.schedule, hour)
                        and reaches(dx, dy, def.radius, range) and (lamp.powered or not needPower) then
                        out.seepLong = math.max(out.seepLong, outsideLeak)
                    end
                    if not blocked and reaches(dx, dy, def.radius, range) and (lamp.powered or not needPower) then
                        local on = isOn(lamp.schedule, hour)
                        if isLongDay(lamp.schedule) then
                            out.anyLong = true
                            if on then out.longOn = true end
                        else
                            out.anyShort = true
                        end
                        if on and (not out.cap or def.cap > out.cap) then out.cap, out.name = def.cap, def.name end
                    end
                end
            end
        end
    end
end

--- The powered lamps reaching a plant, summed up for this moment.
--- Returns { cap, name } for the brightest lamp lit right now (nil when none is lit), plus
--- anyLong / anyShort for whether any reaching lamp runs a veg (24/0, 18/6) or a 12/12 schedule.
function Light.lampsAt(x, y, z)
    local out = { cap = nil, name = nil, anyLong = false, anyShort = false, longOn = false, seepLong = 0 }
    local hour = getGameTime():getHour()
    local range = Config.sandbox("LampRange")
    local needPower = Config.sandbox("LampsNeedPower")
    local R = math.ceil(Config.Light.MAX_RADIUS * range)
    -- A plant in a grow room is only reached by outside lamps through an uncovered door or window.
    local Rooms = CannabisMod.Rooms
    local roomKey = Rooms and Rooms.keyAt(x, y, z)
    pcall(scanLamps, out, x, y, z, R, hour, range, needPower, roomKey)
    return out
end

--- The best lamp lit near a plant right now: returns its ceiling and name, or nil.
function Light.findLamp(x, y, z)
    local lamps = Light.lampsAt(x, y, z)
    return lamps.cap, lamps.name
end

--- Current light ceiling and its source name for a plant's tile, plus the lamp summary.
function Light.measure(plant)
    local lamps = Light.lampsAt(plant.x, plant.y, plant.z)
    local cell = getCell and getCell()
    local square = cell and cell:getGridSquare(plant.x, plant.y, plant.z)
    local sun = square == nil or square:isOutside()  -- unknown square: assume sun

    local sunCap = sun and Config.LightCap.SUN or 0
    -- Outdoors a lit lamp supplements the sun rather than replacing it, for a small boost.
    if sun and lamps.cap and lamps.cap > 0 then
        local cap = math.min(Config.LightCap.GOOD_LAMP, math.max(sunCap, lamps.cap) + Config.LightCap.SUN_BOOST)
        return cap, "Sun + " .. tostring(lamps.name), lamps
    end
    if lamps.cap and lamps.cap >= sunCap then return lamps.cap, lamps.name, lamps end
    if sun then return sunCap, "Sun", lamps end
    return Config.LightCap.NONE, "None", lamps
end

--- The light cycle a plant is on: "sun" (no lamp reaches it), "long" (veg light), "short" (12/12 only) or "leak" (both).
function Light.cycleOf(lamps)
    if lamps.anyShort and lamps.anyLong then return "leak" end
    if lamps.anyShort then return "short" end
    if lamps.anyLong then return "long" end
    return "sun"
end

--- Runs for each living, rooted plant every 10 minutes. Returns true if the
--- plant is stalled (the caller skips stage growth).
function Light.update(plant)
    -- Nobody near: keep the last light reading (an indoor plant mustn't read as sunlit and drop out of veg),
    -- and let it grow on as it was.
    local cell = getCell and getCell()
    if cell and not cell:getGridSquare(plant.x, plant.y, plant.z) then return plant.lightStalled == true end
    local cap, source, lamps = Light.measure(plant)
    local cycle = Light.cycleOf(lamps)
    plant.lightCycle = cycle
    -- Powered lamps reach the plant but none is lit: a timer's dark hours, not a fault.
    local scheduledDark = cap == 0 and (lamps.anyShort or lamps.anyLong)
    plant.lightSource = scheduledDark and "Lights off (timer)" or source

    -- Sunlight through an uncovered window into a 12/12 room's dark hours.
    local Rooms = CannabisMod.Rooms
    local roomKey = Rooms and Rooms.keyAt(plant.x, plant.y, plant.z)
    local hourNow = getGameTime():getHour()
    local sunLeak = roomKey ~= nil and Config.sandbox("LightLeaks") and Rooms.sunLeakAt(roomKey, plant.x, plant.y, hourNow)
    if sunLeak then
        plant.stress = Config.clamp((plant.stress or 0) + Config.Timer.LEAK_STRESS_PER_HOUR / 6 * sunLeak, 0, Config.Stress.MAX)
        plant.warnings.lightLeak = true
        Rooms.noteLeak(roomKey, sunLeak < 1 and "Light leak: sunlight round a closed door" or "Light leak: sunlight through an uncovered window or open door")
    end

    if scheduledDark then
        plant.warnings.noLight = nil
        plant.lightOn = false
        plant.lightStalled = false
        return false
    end

    -- Running light score for the quality formula.
    plant.lightCap = (plant.lightCap or Config.LightCap.SUN)
        + (cap - (plant.lightCap or Config.LightCap.SUN)) * Config.Light.EMA_PER_CHECK

    local lightOn = cap > 0
    local stalled = not lightOn

    if stalled then
        -- No light: the growth timer stops and the plant slowly suffers.
        if plant.nextStageAt then plant.nextStageAt = plant.nextStageAt + 1 / 6 end
        Registry.applyPenalty(plant, Config.Light.NO_LIGHT_PENALTY_PER_HOUR / 6, "noLight")
    else
        plant.warnings.noLight = nil
    end

    -- Light reaching a 12/12 plant while its own lamp is dark: stress, which feeds the hermie chance.
    local hour = getGameTime():getHour()
    local shortDark = not Config.Timer.isOn("12/12", hour)
    if cycle == "leak" and shortDark and lamps.longOn then
        plant.stress = Config.clamp((plant.stress or 0) + Config.Timer.LEAK_STRESS_PER_HOUR / 6, 0, Config.Stress.MAX)
        plant.warnings.lightLeak = true
        if roomKey then Rooms.noteLeak(roomKey, "Light leak: a lamp outside the room") end
    elseif (lamps.seepLong or 0) > 0 and shortDark and cycle ~= "long" and Config.sandbox("LightLeaks") then
        plant.stress = Config.clamp((plant.stress or 0) + Config.Timer.LEAK_STRESS_PER_HOUR / 6 * lamps.seepLong, 0, Config.Stress.MAX)
        plant.warnings.lightLeak = true
        if roomKey then Rooms.noteLeak(roomKey, "Light leak: a lamp outside, round a closed door") end
    elseif cycle ~= "leak" and not sunLeak then
        plant.warnings.lightLeak = nil
    end

    -- Broken light cycle while flowering (a power cut, not a timer).
    if plant.stage == Config.STAGE.Flowering and plant.lightOn and not lightOn then
        Registry.applyPenalty(plant, Config.Care.LIGHT_INTERRUPTION, "lightInterrupted")
    end
    if lightOn then plant.warnings.lightInterrupted = nil end
    plant.lightOn = lightOn
    plant.lightStalled = stalled

    return stalled
end
