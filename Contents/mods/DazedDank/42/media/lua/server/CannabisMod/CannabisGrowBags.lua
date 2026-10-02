-- Placeable grow bags that act as vanilla farm plots, work indoors, and need a
-- one-time soil fill before the first sowing.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"

local Config   = CannabisMod.Config
local Net      = CannabisMod.Net
local Seeds    = CannabisMod.Seeds
local Registry = CannabisMod.Registry
local Farming  = CannabisMod.Farming
local SC       = CannabisMod.ServerCommands
local commands = SC.handlers

local GrowBags = {}
CannabisMod.GrowBags = GrowBags

--- Put a plot back to an empty bag: no plant, no record, bag sprite. Used
--- after harvest and when a dead plant is cleared out.
function GrowBags.reset(luaObject)
    local x, y, z = luaObject.x, luaObject.y, luaObject.z
    Registry.removePlant(x, y, z)
    if CannabisMod.Hydro then CannabisMod.Hydro.onReset(x, y, z) end
    luaObject:initNew()  -- vanilla's "freshly plowed" state
    pcall(function() luaObject.exterior = luaObject:getSquare():isOutside() end)
    luaObject:setSpriteName(farming_vegetableconf.getSpriteName(luaObject))
    luaObject:setObjectName(farming_vegetableconf.getObjectName(luaObject))
    luaObject:saveData()
end

--- Hand a placeable bag back to a player.
local function giveBag(player, size)
    Farming.giveItems(player, Config.GrowBag[size].furnItem, 1)
end

--- Create the bag's farm plot on a square. Returns the plot, or nil if it wouldn't take.
function GrowBags.makePlot(square, size)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    -- Register first so the sprite and name picked below are the bag's.
    Registry.setBag(x, y, z, size)
    SFarmingSystem.instance:plow(square)
    local luaObject = Farming.getVanilla(x, y, z)
    if not luaObject then
        Registry.clearBag(x, y, z)
        return nil
    end
    luaObject:setSpriteName(farming_vegetableconf.getSpriteName(luaObject))
    luaObject:setObjectName(farming_vegetableconf.getObjectName(luaObject))
    luaObject:saveData()
    return luaObject
end

--- The plot at a tile, if it is a registered grow bag. Returns plot, size.
local function bagPlot(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) then return nil end
    if not SC.isNear(player, x, y, z) then
        Net.notify(player, "You're too far from the bag")
        return nil
    end
    local size = Registry.getBag(x, y, z)
    local luaObject = Farming.getVanilla(x, y, z)
    if not (size and luaObject) then
        Net.notify(player, "That isn't a grow bag")
        return nil
    end
    return luaObject, size
end

--- Take `count` soil sacks out of a player's inventory. All or nothing.
local function takeSoil(player, count)
    local inv = player:getInventory()
    local found = {}
    for _ = 1, count do
        local sack = Seeds.findItem(inv, function(item)
            if not Config.isSoilItem(item:getFullType()) then return false end
            for _, f in ipairs(found) do if f == item then return false end end
            return true
        end)
        if not sack then return false end
        found[#found + 1] = sack
    end
    for _, sack in ipairs(found) do
        local container = sack:getContainer()
        if container then
            container:Remove(sack)
            sendRemoveItemFromContainer(container, sack)
        end
    end
    return true
end

commands.fillGrowBag = function(player, args)
    local luaObject, size = bagPlot(player, args)
    if not luaObject then return end
    local x, y, z = luaObject.x, luaObject.y, luaObject.z
    if Config.isHydro(size) then return end
    if Registry.isBagSoiled(x, y, z) then
        Net.notify(player, "That bag already has soil")
        return
    end
    local need = Config.GrowBag[size].soil
    if not takeSoil(player, need) then
        Net.notify(player, "You need " .. need .. " sack" .. (need > 1 and "s" or "") .. " of soil")
        return
    end
    Registry.setBagSoiled(x, y, z, true)
    luaObject:setSpriteName(farming_vegetableconf.getSpriteName(luaObject))
    luaObject:setObjectName(farming_vegetableconf.getObjectName(luaObject))
    luaObject:saveData()
    Net.notify(player, "Filled the bag with soil")
end

commands.pickUpGrowBag = function(player, args)
    local luaObject, size = bagPlot(player, args)
    if not luaObject then return end
    if luaObject.state ~= "plow" then
        Net.notify(player, "Empty the bag first")
        return
    end
    if Config.isHydro(size) and CannabisMod.Hydro then
        CannabisMod.Hydro.onPickUp(player, luaObject.x, luaObject.y, luaObject.z)
    end
    Registry.clearBag(luaObject.x, luaObject.y, luaObject.z)
    SFarmingSystem.instance:removePlant(luaObject)
    giveBag(player, size)
end

commands.emptyGrowBag = function(player, args)
    local luaObject = bagPlot(player, args)
    if not luaObject then return end
    -- Only a plant that is already dead or spent can be cleared out.
    if luaObject.state == "plow" then
        Net.notify(player, "The bag is already empty")
        return
    end
    if luaObject:isAlive() then
        Net.notify(player, "That plant is still alive")
        return
    end
    GrowBags.reset(luaObject)
    Net.notify(player, "Emptied the bag")
end

-- Vanilla's shovel "Remove" on a dead plant in a bag empties the bag instead of deleting it.
local originalRemovePlant = SFarmingSystem.removePlant
function SFarmingSystem:removePlant(luaObject)
    if luaObject and luaObject.state ~= "plow" and Registry.getBag(luaObject.x, luaObject.y, luaObject.z) then
        GrowBags.reset(luaObject)
        return
    end
    return originalRemovePlant(self, luaObject)
end

-- --------------------------------------------------------------------------
-- Furniture bags: placed like furniture, then swapped for a plot
-- --------------------------------------------------------------------------

--- The furniture bag object on a square, with its size.
local function furnitureBagAt(square)
    local found, size
    pcall(function()
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            local sprite = obj:getSprite()
            local sz = sprite and Config.bagFromFurnSprite(sprite:getName())
            if sz then found, size = obj, sz end
        end
    end)
    return found, size
end

--- Swap a placed furniture bag for a bag plot. Returns true when done.
local function convertBagAt(x, y, z)
    local square = getCell():getGridSquare(x, y, z)
    if not square then return false end
    local obj, size = furnitureBagAt(square)
    if not obj then return false end
    if Farming.getVanilla(x, y, z) then return false end
    if not GrowBags.makePlot(square, size) then return false end
    pcall(function() square:transmitRemoveItemFromSquare(obj) end)
    pcall(function() square:RemoveTileObject(obj) end)
    return true
end
GrowBags.convertBagAt = convertBagAt

-- Squares waiting for a furniture bag to show up, retried for a few seconds.
local pendingConvert = {}

local function queueConvert(x, y, z, ticks)
    pendingConvert[#pendingConvert + 1] = { x = x, y = y, z = z, ticks = ticks or 120 }
end

Events.OnTick.Add(function()
    if #pendingConvert == 0 then return end
    for i = #pendingConvert, 1, -1 do
        local job = pendingConvert[i]
        job.ticks = job.ticks - 1
        if convertBagAt(job.x, job.y, job.z) or job.ticks <= 0 then
            table.remove(pendingConvert, i)
        end
    end
end)

-- Where the furniture is placed on the server (and in single player).
Events.OnObjectAdded.Add(function(obj)
    local ok, x, y, z, isBag = pcall(function()
        local sprite = obj:getSprite()
        local sq = obj:getSquare()
        return sq:getX(), sq:getY(), sq:getZ(), sprite and Config.bagFromFurnSprite(sprite:getName()) ~= nil
    end)
    if ok and isBag then queueConvert(x, y, z) end
end)

-- Where the placing client asks for it (when placement runs client-side).
commands.convertBag = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return end
    queueConvert(x, y, z)
end
