-- Placeable grow bags that act as vanilla farm plots, work indoors, and need a
-- one-time soil fill before the first sowing.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisSchedule"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"
require "CannabisMod/CannabisWorld"

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
    Farming.applyTint(nil, luaObject)  -- the empty bag loses the old plant's strain colour
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

--- The other half of a flood table as its plot, or nil (no partner, not loaded, or already gone).
local function partnerPlot(x, y, z)
    local Hydro = CannabisMod.Hydro
    local site = Hydro and Hydro.get(x, y, z, "ebb")
    if not (site and site.partner) then return nil end
    local px, py, pz = Config.parseKey(site.partner)
    if not px then return nil end
    if Registry.getBag(px, py, pz) ~= "ebb" then return nil end
    -- Only a partner that points back is the same table.
    if Hydro.get(px, py, pz, "ebb").partner ~= Config.tileKey(x, y, z) then return nil end
    return Farming.getVanilla(px, py, pz)
end

--- Take one plot off the map, handing back an unused medium.
local function removePlot(player, luaObject, size)
    if Config.isHydro(size) and CannabisMod.Hydro then
        CannabisMod.Hydro.onPickUp(player, luaObject.x, luaObject.y, luaObject.z)
    end
    if CannabisMod.PotPlants then CannabisMod.PotPlants.clear(luaObject:getSquare()) end
    Registry.clearBag(luaObject.x, luaObject.y, luaObject.z)
    SFarmingSystem.instance:removePlant(luaObject)
end

commands.pickUpGrowBag = function(player, args)
    local luaObject, size = bagPlot(player, args)
    if not luaObject then return end
    local other = size == "ebb" and partnerPlot(luaObject.x, luaObject.y, luaObject.z) or nil
    if luaObject.state ~= "plow" or (other and other.state ~= "plow") then
        Net.notify(player, size == "ebb" and "Clear both halves of the table first" or "Empty the bag first")
        return
    end
    -- A lone flood table half (its pair never matched) gives the table back only from its first half, so no table is doubled.
    local site = size == "ebb" and CannabisMod.Hydro and CannabisMod.Hydro.get(luaObject.x, luaObject.y, luaObject.z, "ebb") or nil
    local give = not site or other ~= nil or site.part ~= 1
    removePlot(player, luaObject, size)
    if other then removePlot(player, other, size) end
    if CannabisMod.Hydro then CannabisMod.Hydro.forgetLinks() end
    if give then giveBag(player, size) end
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

--- Pull an unwanted male plant (any container or the ground) before it can pollinate; the plot is left ready to replant.
commands.pullMalePlant = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return end
    local luaObject = Farming.getVanilla(x, y, z)
    local plant = Registry.getPlant(x, y, z)
    if not (luaObject and plant) or plant.sex ~= Config.SEX.MALE or plant.stage < Config.STAGE.PreFlower then
        Net.notify(player, "That isn't a male plant you can tell apart yet")
        return
    end
    GrowBags.reset(luaObject)
    Net.notify(player, "Pulled the male plant")
end

-- Vanilla's shovel "Remove" on a dead plant in a bag empties the bag instead of deleting it.
local originalRemovePlant = SFarmingSystem.removePlant
function SFarmingSystem:removePlant(luaObject)
    if luaObject and luaObject.state ~= "plow" and Registry.getBag(luaObject.x, luaObject.y, luaObject.z) then
        GrowBags.reset(luaObject)
        return
    end
    local square = luaObject and luaObject.getSquare and luaObject:getSquare()
    if square and CannabisMod.PotPlants then CannabisMod.PotPlants.clear(square) end
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

local FACINGS = { "E", "S", "W", "N" }

--- A placed flood table tile's facing (1-4, E S W N) and part (0 or 1), from its sprite; nil if it isn't one.
function GrowBags.tablePart(spriteName)
    local sheet, n = Config.splitSprite(spriteName)
    local def = Config.GrowBag.ebb
    if sheet ~= Config.sheetOf("ebb") or not n or n < def.furnSprites[1] or n > def.furnSprites[#def.furnSprites] then return nil end
    local i = n - def.furnSprites[1]
    return math.floor(i / 2) + 1, i % 2
end

--- Where the other tile of a flood table is expected, from one tile's sprite (south and north run along x, east and west along y).
function GrowBags.tablePartner(spriteName, x, y, z)
    local facing, part = GrowBags.tablePart(spriteName)
    if not facing then return nil end
    local step = part == 0 and 1 or -1
    if FACINGS[facing] == "S" or FACINGS[facing] == "N" then return x + step, y, z end
    return x, y + step, z
end

--- Pair a newly converted table tile with its other half: the neighbour holding the complementary part of the same table,
--- checked on the map rather than assumed, so a wrong guess about tile order can never pair two different tables.
local function pairTable(x, y, z, facing, part)
    local Hydro = CannabisMod.Hydro
    local me = Hydro.get(x, y, z, "ebb")
    me.facing, me.part, me.partner = facing, part, nil
    local def = Config.GrowBag.ebb
    local wantSprite = Config.sheetOf("ebb") .. "_" .. (def.furnSprites[1] + (facing - 1) * 2 + (1 - part))
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        local other = Registry.getBag(nx, ny, z) == "ebb" and Hydro.get(nx, ny, z, "ebb") or nil
        local mine = Config.tileKey(x, y, z)
        local match = other and other.facing == facing and other.part == 1 - part
            and (other.partner == nil or other.partner == mine)
        if not match then
            -- The other half may still be furniture, waiting to be converted.
            local square = getCell():getGridSquare(nx, ny, z)
            local furn = square and furnitureBagAt(square)
            match = furn ~= nil and furn:getSprite():getName() == wantSprite
        end
        if match then
            me.partner = Config.tileKey(nx, ny, z)
            if other then other.partner = Config.tileKey(x, y, z) end
            return
        end
    end
end

--- The other half of a flood table that is still furniture: the neighbour holding the complementary sprite, or nil.
local function tableHalfFurniture(x, y, z, facing, part)
    local def = Config.GrowBag.ebb
    local wantSprite = Config.sheetOf("ebb") .. "_" .. (def.furnSprites[1] + (facing - 1) * 2 + (1 - part))
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local square = getCell():getGridSquare(x + d[1], y + d[2], z)
        local furn = square and furnitureBagAt(square)
        if furn and furn:getSprite():getName() == wantSprite and not Farming.getVanilla(x + d[1], y + d[2], z) then
            return square, furn
        end
    end
    return nil
end

--- Turn one furniture tile into a plot, leaving the furniture in place. Returns true when done.
local function plotFromFurniture(square, obj, size)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local spriteName = obj:getSprite():getName()
    -- A fresh bucket or table starts with a clean record, whatever stood here before.
    if CannabisMod.Hydro then CannabisMod.Hydro.clear(x, y, z) end
    if not GrowBags.makePlot(square, size) then return false end
    -- Each half of a flood table remembers the other, so picking either up takes the whole table.
    if size == "ebb" and CannabisMod.Hydro then
        local facing, part = GrowBags.tablePart(spriteName)
        if facing then pairTable(x, y, z, facing, part) end
    end
    return true
end

local function removeFurniture(square, obj)
    pcall(function() square:transmitRemoveItemFromSquare(obj) end)
    pcall(function() square:RemoveTileObject(obj) end)
end

--- Swap a placed furniture bag for a bag plot. Returns true when done.
--- A flood table is one two-tile object, and removing either half's furniture takes both, so both halves become plots first.
local function convertBagAt(x, y, z)
    local square = getCell():getGridSquare(x, y, z)
    if not square then return false end
    local obj, size = furnitureBagAt(square)
    if not obj then return false end
    if Farming.getVanilla(x, y, z) then return false end
    local otherSquare, otherObj = nil, nil
    if size == "ebb" then
        local facing, part = GrowBags.tablePart(obj:getSprite():getName())
        if facing then otherSquare, otherObj = tableHalfFurniture(x, y, z, facing, part) end
    end
    if not plotFromFurniture(square, obj, size) then return false end
    if otherObj then plotFromFurniture(otherSquare, otherObj, size) end
    if CannabisMod.Hydro then CannabisMod.Hydro.forgetLinks() end
    removeFurniture(square, obj)
    if otherObj then removeFurniture(otherSquare, otherObj) end
    return true
end
GrowBags.convertBagAt = convertBagAt

--- Bring back a bag, bucket or table tile the save kept without its farming record (a crash between saves). True when done.
--- A plot object that still carries its farming state goes back to the farming system as it is; otherwise an empty plot is made.
function GrowBags.adoptOrphan(square, obj, kind)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    if Farming.getVanilla(x, y, z) then return false end
    local sys = SFarmingSystem and SFarmingSystem.instance
    local okValid, valid = pcall(function() return sys and sys.isValidIsoObject and sys:isValidIsoObject(obj) end)
    if okValid and valid then
        Registry.setBag(x, y, z, kind)
        pcall(sys.loadIsoObject, sys, obj)
        local luaObject = Farming.getVanilla(x, y, z)
        if not luaObject then Registry.clearBag(x, y, z) return false end
        -- A pot with something growing in it already has its soil or medium.
        Registry.setBagSoiled(x, y, z, luaObject.state ~= "plow" or (not Config.isHydro(kind) and not Config.bagIsUnfilled(obj:getSprite():getName())))
        return true
    end
    local soiled = not Config.isHydro(kind) and not Config.bagIsUnfilled(obj:getSprite():getName())
    if CannabisMod.Hydro then CannabisMod.Hydro.clear(x, y, z) end
    Registry.setBag(x, y, z, kind)
    Registry.setBagSoiled(x, y, z, soiled)
    local luaObject = GrowBags.makePlot(square, kind)
    if not luaObject then return false end
    -- The plow takes an object already on the square as the plot's own; only a separate leftover is removed.
    local mine = false
    pcall(function() mine = luaObject:getIsoObject() == obj end)
    if not mine then removeFurniture(square, obj) end
    return true
end

--- Draw the object back for a registered bag whose plot is in the farming system but has nothing on its square. True when drawn.
function GrowBags.redraw(x, y, z)
    local luaObject = Farming.getVanilla(x, y, z)
    if not (luaObject and luaObject.getIsoObject and luaObject.addObject) or luaObject:getIsoObject() then return false end
    luaObject.spriteName = farming_vegetableconf.getSpriteName(luaObject)
    luaObject.objectName = farming_vegetableconf.getObjectName(luaObject)
    if not pcall(luaObject.addObject, luaObject) then return false end
    return luaObject:getIsoObject() ~= nil
end

--- Pair a rebuilt flood table tile with a rebuilt neighbour that has no partner, so picking up either takes the table.
function GrowBags.pairOrphanTable(x, y, z)
    local Hydro = CannabisMod.Hydro
    if not Hydro or Registry.getBag(x, y, z) ~= "ebb" then return end
    local me = Hydro.get(x, y, z, "ebb")
    if me.partner then return end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if Registry.getBag(nx, ny, z) == "ebb" then
            local other = Hydro.get(nx, ny, z, "ebb")
            if not other.partner then
                me.partner, other.partner = Config.tileKey(nx, ny, z), Config.tileKey(x, y, z)
                me.part, other.part = 0, 1
                return
            end
        end
    end
end

-- Squares waiting for a furniture bag to show up, retried for a few seconds.
local pendingConvert = {}

local function queueConvert(x, y, z, ticks)
    ticks = ticks or 120
    -- One job per tile: a second request just restarts the wait.
    for _, job in ipairs(pendingConvert) do
        if job.x == x and job.y == y and job.z == z then
            job.ticks = math.max(job.ticks, ticks)
            return
        end
    end
    pendingConvert[#pendingConvert + 1] = { x = x, y = y, z = z, ticks = ticks }
end

CannabisMod.Ticker.every(1, function()
    if #pendingConvert == 0 then return end
    for i = #pendingConvert, 1, -1 do
        local job = pendingConvert[i]
        job.ticks = job.ticks - 1
        if convertBagAt(job.x, job.y, job.z) or job.ticks <= 0 then
            table.remove(pendingConvert, i)
        end
    end
end, "bag converting")

-- Where the furniture is placed on the server (and in single player).
CannabisMod.World.onObjectAdded("bag placing", function(obj, name, info)
    if not (info.furn or info.flood) then return end
    local sq = obj:getSquare()
    if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    if info.furn then queueConvert(x, y, z) end
    -- A new flood reservoir changes which tables are fed.
    if info.flood and CannabisMod.Hydro then
        CannabisMod.Hydro.forgetLinks()
        CannabisMod.Hydro.syncFloodObject(x, y, z)
    end
end)

-- Where the placing client asks for it (when placement runs client-side).
commands.convertBag = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return end
    queueConvert(x, y, z)
end
