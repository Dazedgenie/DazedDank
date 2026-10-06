-- Every cannabis plant is a separate object drawn over its plot (a furrow, bag, bucket or flood table), raised onto
-- the soil, so one set of plant sprites serves the ground and every container.

if isClient() then return end

require "Farming/SPlantGlobalObject"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisCrop"

local Config = CannabisMod.Config
local Registry = CannabisMod.Registry
local CROP = Config.CROP_TYPE

local PotPlants = {}
CannabisMod.PotPlants = PotPlants

local function lift(square, obj)
    pcall(function() square:transmitRemoveItemFromSquare(obj) end)
    pcall(function() square:RemoveTileObject(obj) end)
end

--- The plant sprite a plot should show and its container kind (nil on the ground), or nil when there is no plant to draw.
function PotPlants.wanted(luaObject)
    if not luaObject or luaObject.state == "plow" or luaObject.typeOfSeed ~= CROP then return nil end
    local bag = Registry.getBag(luaObject.x, luaObject.y, luaObject.z)
    local shape, colour, stage, condition, male = CannabisMod.plantLook(luaObject)
    return Config.overlaySprite(shape, colour, stage, condition, bag, male), bag
end

--- Make the raised plant object on a plot's square match the plot: add, swap or remove it.
function PotPlants.sync(luaObject)
    local square = luaObject and luaObject.getSquare and luaObject:getSquare()
    if not square then return end
    local want, bag = PotPlants.wanted(luaObject)
    local current, currentName = Config.overlayOn(square)
    if current and currentName == want then return end
    local color = current and current.getCustomColor and current:getCustomColor()
    if current then lift(square, current) end
    if not want then return end
    -- A fresh object per change (rather than a re-sprite) so the client always draws the new stage.
    local obj = IsoObject.new(getCell(), square, want)
    obj:setRenderYOffset(bag and Config.PLANT_LIFT[bag] or 0)
    if color then pcall(function() obj:setCustomColor(color) end) end
    square:AddTileObject(obj)
    pcall(function() obj:transmitCompleteItemToClients() end)
end

--- Take the plant object off a square (the container is being picked up).
function PotPlants.clear(square)
    local current = square and Config.overlayOn(square)
    if current then lift(square, current) end
end

-- Every sprite change made to a plot (sowing, growing, sickness, death, harvest) re-checks the raised plant.
local originalSetSpriteName = SPlantGlobalObject.setSpriteName
function SPlantGlobalObject:setSpriteName(spriteName)
    originalSetSpriteName(self, spriteName)
    local ok, err = pcall(PotPlants.sync, self)
    if not ok then print("[DazedDank] plant-in-pot layer failed: " .. tostring(err)) end
end

-- A plant layer left on a square whose plot is gone (removed some way we don't hook) is cleared a little after the
-- square loads, once the farming system has its plots.
local orphanCheck = {}
Events.LoadGridsquare.Add(function(square)
    if Config.overlayOn(square) then orphanCheck[#orphanCheck + 1] = { square = square, at = getTimestampMs() + 5000 } end
end)
Events.OnTick.Add(function()
    if #orphanCheck == 0 or getTimestampMs() < orphanCheck[1].at then return end
    local now, due = getTimestampMs(), {}
    while orphanCheck[1] and orphanCheck[1].at <= now do due[#due + 1] = table.remove(orphanCheck, 1) end
    local system = SFarmingSystem and SFarmingSystem.instance
    for _, e in ipairs(due) do
        local current = Config.overlayOn(e.square)
        local plot = system and system.getLuaObjectOnSquare and system:getLuaObjectOnSquare(e.square)
        if current and system and not (plot and plot.typeOfSeed == CROP and plot.state ~= "plow") then
            print("[DazedDank] removed a plant layer with no plant under it at " .. e.square:getX() .. "," .. e.square:getY())
            lift(e.square, current)
        end
    end
end)

return PotPlants
