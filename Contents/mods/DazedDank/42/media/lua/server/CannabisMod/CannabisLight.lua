-- Works out each plant's light every 10 game minutes from the sun or a powered
-- grow lamp, and stalls plants that get none. Lamps are placed furniture
-- matched by sprite, each reaching its own radius.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRegistry"

local Config   = CannabisMod.Config
local Registry = CannabisMod.Registry

local Light = {}
CannabisMod.Light = Light

--- True if this square has power for a lamp.
local function isPowered(square)
    local ok, powered = pcall(function()
        if square:haveElectricity() then return true end
        return (not square:isOutside()) and getWorld():isHydroPowerOn() or false
    end)
    return ok and powered == true
end

--- Schedule of the timer on a lamp tile, or nil for a lamp without one (24/0).
local function scheduleAt(x, y, z)
    local Timers = CannabisMod.Timers
    return Timers and Timers.scheduleAt(x, y, z) or nil
end

--- The powered lamps reaching a plant, summed up for this moment.
--- Returns { cap, name } for the brightest lamp lit right now (nil when none is lit), plus
--- anyLong / anyShort for whether any reaching lamp runs a veg (24/0, 18/6) or a 12/12 schedule.
function Light.lampsAt(x, y, z)
    local out = { cap = nil, name = nil, anyLong = false, anyShort = false, longOn = false }
    local hour = getGameTime():getHour()
    local R = math.ceil(Config.Light.MAX_RADIUS * Config.sandbox("LampRange"))
    local function consider(def, dx, dy, square, schedule)
        if not def then return end
        if not Config.Light.reaches(dx, dy, def.radius) then return end
        if Config.sandbox("LampsNeedPower") and not isPowered(square) then return end
        local on = Config.Timer.isOn(schedule, hour)
        if Config.Timer.isLongDay(schedule) then
            out.anyLong = true
            if on then out.longOn = true end
        else
            out.anyShort = true
        end
        if on and (not out.cap or def.cap > out.cap) then out.cap, out.name = def.cap, def.name end
    end
    pcall(function()
        local cell = getCell()
        for dx = -R, R do
            for dy = -R, R do
                local square = cell:getGridSquare(x + dx, y + dy, z)
                if square then
                    -- placed furniture lamps: match the object's sprite name
                    local objects = square:getObjects()
                    for i = 0, objects:size() - 1 do
                        local ok, name = pcall(function() return objects:get(i):getSprite():getName() end)
                        if ok and name and Config.Light.SPRITES[name] then
                            consider(Config.Light.SPRITES[name], dx, dy, square, scheduleAt(x + dx, y + dy, z))
                        end
                    end
                    -- loose lamp items lying on the ground have no timer
                    local worldItems = square:getWorldObjects()
                    for i = 0, worldItems:size() - 1 do
                        local item = worldItems:get(i):getItem()
                        if item then consider(Config.Light.ITEMS[item:getFullType()], dx, dy, square, nil) end
                    end
                end
            end
        end
    end)
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
    local sun = false
    local ok, outside = pcall(function()
        local square = getCell():getGridSquare(plant.x, plant.y, plant.z)
        return square == nil or square:isOutside()  -- unknown square: assume sun
    end)
    if not ok or outside then sun = true end

    local sunCap = sun and Config.LightCap.SUN or 0
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
    local cap, source, lamps = Light.measure(plant)
    local cycle = Light.cycleOf(lamps)
    plant.lightCycle = cycle
    -- Powered lamps reach the plant but none is lit: a timer's dark hours, not a fault.
    local scheduledDark = cap == 0 and (lamps.anyShort or lamps.anyLong)
    plant.lightSource = scheduledDark and "Lights off (timer)" or source

    if scheduledDark then
        plant.warnings.noLight = nil
        plant.lightOn = false
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
    elseif cycle ~= "leak" then
        plant.warnings.lightLeak = nil
    end

    -- Broken light cycle while flowering (a power cut, not a timer).
    if plant.stage == Config.STAGE.Flowering and plant.lightOn and not lightOn then
        Registry.applyPenalty(plant, Config.Care.LIGHT_INTERRUPTION, "lightInterrupted")
    end
    if lightOn then plant.warnings.lightInterrupted = nil end
    plant.lightOn = lightOn

    return stalled
end
