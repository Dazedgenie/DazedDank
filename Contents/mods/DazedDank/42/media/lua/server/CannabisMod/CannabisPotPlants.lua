-- Cannabis in grow bags, buckets and flood tables: the plot keeps the container's sprite and the plant is a separate
-- object raised onto the soil, so one set of plant sprites serves every container.

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

--- The plant sprite a plot should show above its container and the container kind, or nil when there is no plant to draw.
function PotPlants.wanted(luaObject)
    if not luaObject or luaObject.state == "plow" or luaObject.typeOfSeed ~= CROP then return nil end
    local bag = Registry.getBag(luaObject.x, luaObject.y, luaObject.z)
    if not (bag and Config.PLANT_LIFT[bag]) then return nil end
    local plantType, stage, condition, male = CannabisMod.plantLook(luaObject)
    return Config.overlaySprite(plantType, stage, condition, bag, male), bag
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
    obj:setRenderYOffset(Config.PLANT_LIFT[bag])
    if color then pcall(function() obj:setCustomColor(color) end) end
    square:AddTileObject(obj)
    pcall(function() obj:transmitCompleteItemToClients() end)
end

--- Take the raised plant object off a square (the container is being picked up).
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

return PotPlants
