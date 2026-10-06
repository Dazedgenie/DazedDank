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

--- The air temperature (C) at a plant outside a grow room, or nil when nothing can tell.
function PlantTemp.outdoorTempOf(plant)
    local ok, square = pcall(function() return getCell():getGridSquare(plant.x, plant.y, plant.z) end)
    if ok and square then return Weather.tempAt(square, nil) end
    -- Nobody near: with DazedCore loaded the outdoor reading stands in, else the plant is left alone.
    if Weather.core() then return Weather.outdoor() end
    return nil
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
function PlantTemp.feel(plant, temp, stalled)
    plant.warnings = plant.warnings or {}
    if temp == nil or not Config.sandbox("PlantTemperature") then
        plant.warnings.outdoorTemp = nil
        return
    end
    local stress, bad = CannabisMod.Climate.plantStress(temp, 0, false)
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
    end
end

--- One ten-minute step of night air in late flower: 5-15 C counts toward purple, under 5 C costs yield.
function PlantTemp.coldNight(plant, temp, now, hour)
    if temp == nil or plant.sex == Config.SEX.MALE or not Weather.isNight(hour) then return end
    if not PlantTemp.lateFlower(plant, now) then return end
    if temp < W.PURPLE_LO then
        if Config.sandbox("PlantTemperature") then
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
    local temp
    if inRoom then
        temp = Rooms.climateAt(plant.x, plant.y, plant.z)
        if plant.warnings then plant.warnings.outdoorTemp = nil end
    else
        temp = PlantTemp.outdoorTempOf(plant)
        PlantTemp.feel(plant, temp, stalled)
    end
    PlantTemp.coldNight(plant, temp, now, getGameTime():getHour())
end
