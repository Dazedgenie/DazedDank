-- How the air temperature reaches a plant every ten minutes: outdoor heat and cold, and cold nights in late flower.
-- Plants in a grow room feel the room through CannabisRooms; here they only count its cold nights.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisStrains"
require "CannabisMod/CannabisWeather"
require "CannabisMod/CannabisClimate"
require "CannabisMod/CannabisRegistry"

local Config = CannabisMod.Config
local Strains = CannabisMod.Strains
local Weather = CannabisMod.Weather
local W = Config.Weather

local PlantTemp = {}
CannabisMod.PlantTemp = PlantTemp

--- True when Dazed Climate's crop frost is on: it damages and kills outdoor plants at 0 C and below, so Dank leaves that to it.
function PlantTemp.frostHandled()
    local crops = DazedClimate and DazedClimate.Crops
    if not (crops and crops.enabled) then return false end
    local ok, on = pcall(crops.enabled)
    return ok and on == true
end

--- Degrees a Dazed Climate frost cover over this plant adds (0 with none).
function PlantTemp.coverBonus(plant)
    local covers = DazedClimate and DazedClimate.Covers
    if not (covers and covers.at) then return 0 end
    local ok, item = pcall(covers.at, plant.x, plant.y, plant.z)
    if not (ok and item) then return 0 end
    local frost = DazedClimate.Frost
    return (frost and tonumber(frost.COVER_BONUS)) or 4
end

--- The air temperature (C) at a plant outside a grow room, and whether it stands outdoors; nil when its square isn't loaded.
function PlantTemp.outdoorTempOf(plant)
    local ok, square = pcall(function() return getCell():getGridSquare(plant.x, plant.y, plant.z) end)
    -- Nobody near: the plant is left alone, as the light check does.
    if not (ok and square) then return nil, false end
    local temp = Weather.tempAt(square, nil)
    if temp == nil then return nil, false end
    local outside = false
    pcall(function() outside = square:isOutside() == true end)
    return temp + PlantTemp.coverBonus(plant), outside
end

--- True when this temperature is frost that Dazed Climate already deals with for this plant.
local function frostForDazedClimate(temp, outside)
    return outside and temp <= 0 and PlantTemp.frostHandled()
end

--- When a flowering plant started flowering; plants from before this was saved get an estimate from the usual flowering time.
function PlantTemp.flowerStart(plant, now)
    if plant.flowerStartAt then return plant.flowerStartAt end
    local range = Config.STAGE_HOURS.Flowering
    local speed = math.max(0.1, math.min(10, Config.sandbox("GrowthSpeed") or 1))
    local hours = (range.min + range.max) / 2 * Strains.flowerMult(Strains.of(plant)) / speed
    plant.flowerStartAt = math.min(now, (plant.nextStageAt or now) - hours)
    return plant.flowerStartAt
end

--- True in the second half of Flowering and all of Ripe, when cold nights bring out colour.
function PlantTemp.lateFlower(plant, now)
    if plant.stage == Config.STAGE.Ripe then return true end
    if plant.stage ~= Config.STAGE.Flowering then return false end
    local start = PlantTemp.flowerStart(plant, now)
    local span = (plant.nextStageAt or now) - start
    if span <= 0 then return true end
    return (now - start) / span >= 0.5
end

--- A plant outside a grow room feels the air: stress out of 15-32 C, and growth slows in the cold (not while light already stalls it).
--- Frost that Dazed Climate handles adds no stress here, but still stalls growth.
function PlantTemp.feel(plant, temp, stalled, outside)
    plant.warnings = plant.warnings or {}
    if temp == nil or not Config.sandbox("PlantTemperature") then
        plant.warnings.outdoorTemp = nil
        return
    end
    local stress, bad = CannabisMod.Climate.plantStress(temp, 0, false)
    if frostForDazedClimate(temp, outside) then stress = 0 end
    if stress > 0 then plant.stress = Config.clamp((plant.stress or 0) + stress, 0, Config.Stress.MAX) end
    plant.warnings.outdoorTemp = bad or nil
    local slow = Weather.slowdown(temp)
    if slow > 0 and not stalled and plant.stage < Config.STAGE.Ripe and plant.nextStageAt then
        plant.nextStageAt = plant.nextStageAt + slow / 6
    end
end

--- Purple or not, rolled once when a plant's cold nights first add up; indica-leaning strains purple far more often.
function PlantTemp.rollPurple(plant)
    plant.purpleRolled = true
    if Config.rollPercent(Weather.purpleChance(Strains.of(plant)) * 100) then
        plant.purple = true
        -- Repaint the plant so the colour shows.
        if CannabisMod.Farming then CannabisMod.Farming.onStageChanged(plant) end
        -- A grow room's log notes it; outside a room logTile does nothing.
        local Rooms = CannabisMod.Rooms
        if Rooms and Rooms.logTile and plant.x then
            local s = Strains.of(plant)
            Rooms.logTile(Config.tileKey(plant.x, plant.y, plant.z), ((s and s.name) or "A plant") .. " turned purple")
        end
    end
end

--- Night for a plant: its grow room's lights-off hours when the room runs a timer, else the clock's night.
function PlantTemp.isNight(plant, hour)
    local Rooms = CannabisMod.Rooms
    if Rooms and Rooms.scheduleAt then
        local ruled, schedule = Rooms.scheduleAt(plant.x, plant.y, plant.z)
        if ruled and schedule then return not Config.Timer.isOn(schedule, hour) end
    end
    return Weather.isNight(hour)
end

--- One ten-minute step of night air in late flower: 5-15 C counts toward purple, under 5 C costs yield.
function PlantTemp.coldNight(plant, temp, now, hour, outside)
    if temp == nil or plant.sex == Config.SEX.MALE or not PlantTemp.isNight(plant, hour) then return end
    if not PlantTemp.lateFlower(plant, now) then return end
    if temp < W.PURPLE_LO then
        if Config.sandbox("PlantTemperature") and not frostForDazedClimate(temp, outside) then
            plant.coldYieldLoss = math.min(W.FREEZE_YIELD_MAX, (plant.coldYieldLoss or 0) + W.FREEZE_YIELD_PER_HOUR / 6)
        end
    elseif temp < W.PURPLE_HI and Config.sandbox("PurpleBuds") and not plant.purpleRolled then
        plant.coldNightHours = (plant.coldNightHours or 0) + 1 / 6
        if plant.coldNightHours >= W.PURPLE_HOURS - 0.001 then PlantTemp.rollPurple(plant) end
    end
end

--- Every ten minutes for each living, rooted plant (the Registry calls this before the stage check).
function PlantTemp.update(plant, now, stalled)
    local Rooms = CannabisMod.Rooms
    local inRoom = Rooms ~= nil and Rooms.keyAt(plant.x, plant.y, plant.z) ~= nil
    local temp, outside = nil, false
    if inRoom then
        temp = Rooms.climateAt(plant.x, plant.y, plant.z)
        if plant.warnings then plant.warnings.outdoorTemp = nil end
    else
        temp, outside = PlantTemp.outdoorTempOf(plant)
        PlantTemp.feel(plant, temp, stalled, outside)
    end
    PlantTemp.coldNight(plant, temp, now, getGameTime():getHour(), outside)
end
