-- Every cannabis plant is a separate object drawn over its plot (a furrow, bag, bucket or flood table), raised onto
-- the soil, so one set of plant sprites serves the ground and every container.

if isClient() then return end

require "Farming/SPlantGlobalObject"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisCrop"
require "CannabisMod/CannabisWorld"

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
    -- Other crops only matter when a plant layer is still on their square (a replanted cannabis plot).
    if self.typeOfSeed ~= CROP then
        local square = self.getSquare and self:getSquare()
        if not (square and Config.overlayOn(square)) then return end
    end
    local ok, err = pcall(PotPlants.sync, self)
    if not ok then print("[DazedDank] plant-in-pot layer failed: " .. tostring(err)) end
end

-- A plant layer left on a square whose plot is gone (removed some way we don't hook) is cleared a little after the
-- square loads, once the farming system has its plots. A queue of { x, y, z, at } read from `head`, oldest first.
local orphanCheck, head, tail = {}, 1, 0

CannabisMod.World.onSquareLoad("plant layer check", function(square, hits)
    for i = 1, hits.n do
        if hits.info[i].overlay then
            tail = tail + 1
            orphanCheck[tail] = { x = square:getX(), y = square:getY(), z = square:getZ(), at = getTimestampMs() + 5000 }
            return
        end
    end
end)

--- Clear the layer on one queued tile if its plot is gone.
local function checkOrphan(e, system)
    local square = getCell():getGridSquare(e.x, e.y, e.z)
    if not square then return end
    local current = Config.overlayOn(square)
    local plot = system and system.getLuaObjectOnSquare and system:getLuaObjectOnSquare(square)
    if current and system and not (plot and plot.typeOfSeed == CROP and plot.state ~= "plow") then
        print("[DazedDank] removed a plant layer with no plant under it at " .. e.x .. "," .. e.y)
        lift(square, current)
    end
end

--- Work through the queued tiles whose wait is over.
function PotPlants.checkOrphans()
    if head > tail then return end
    local now = getTimestampMs()
    if now < orphanCheck[head].at then return end
    local system = SFarmingSystem and SFarmingSystem.instance
    while head <= tail and orphanCheck[head].at <= now do
        local e = orphanCheck[head]
        orphanCheck[head] = nil
        head = head + 1
        pcall(checkOrphan, e, system)
    end
    if head > tail then head, tail = 1, 0 end
end
Events.OnTick.Add(PotPlants.checkOrphans)

return PotPlants
