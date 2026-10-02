-- Server side of cloning: taking cuttings, rooting gel, and cuttings rooting
-- in the dome or in soil.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"

local Config   = CannabisMod.Config
local Genetics = CannabisMod.Genetics
local Seeds    = CannabisMod.Seeds
local Net      = CannabisMod.Net
local Registry = CannabisMod.Registry
local Farming  = CannabisMod.Farming
local SC       = CannabisMod.ServerCommands
local commands = SC.handlers

local Cloning = {}
CannabisMod.Cloning = Cloning

-- --------------------------------------------------------------------------
-- Item helpers
-- --------------------------------------------------------------------------

--- Remove an item from wherever it is in a player's inventory (bags too), and
--- tell the player's game.
local function removeItem(item)
    local container = item:getContainer()
    if not container then return end
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
end

--- Find an item in a player's inventory by its ID.
local function findById(player, id)
    id = tonumber(id)
    if not id then return nil end
    return Seeds.findItem(player:getInventory(), function(item)
        return item:getID() == id
    end)
end

--- Give a player one cutting item carrying `data`, optionally aged.
local function giveCutting(player, fullType, data, ageDays)
    Farming.giveItems(player, fullType, 1, function(item)
        Seeds.setCuttingData(item, data)
        -- Dipped cuttings are labelled so they can be told apart.
        if data.gel and fullType == Config.CUTTING_ITEM then
            pcall(function() item:setName("Cannabis Cutting (Rooting Gel)") end)
        end
        if ageDays then
            pcall(function() item:setAge(ageDays) end)
        end
    end)
end

-- --------------------------------------------------------------------------
-- Take a cutting
-- --------------------------------------------------------------------------

commands.takeCutting = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return end

    local plant = Registry.getPlant(x, y, z)
    if not plant or plant.dead or plant.rooting then
        Net.notify(player, "There's nothing here to take a cutting from")
        return
    end
    if not Genetics.canClone(plant) then
        Net.notify(player, "Cuttings can only be taken during veg or pre-flower")
        return
    end
    if not Seeds.findCuttingTool(player) then
        Net.notify(player, "You need scissors or a sharp knife")
        return
    end

    -- The clone: mother's genetics minus random drift, half her stress.
    local data = Genetics.cloneFrom(plant)
    data.gel = false
    giveCutting(player, Config.CUTTING_ITEM, data, 0)

    -- Cutting stresses the mother a little.
    plant.stress = Config.clamp(plant.stress + Config.Stress.CUTTING_COST, 0, Config.Stress.MAX)
    Net.notify(player, "Took a cutting")
end

-- --------------------------------------------------------------------------
-- Rooting gel
-- --------------------------------------------------------------------------

commands.dipInGel = function(player, args)
    local cutting = findById(player, args.id)
    if not cutting or not Seeds.isUsableCutting(cutting) then return end

    local data = Seeds.getCuttingData(cutting)
    if data.gel then
        Net.notify(player, "That cutting is already dipped")
        return
    end
    local gel = Seeds.findItem(player:getInventory(), function(item)
        return item:getFullType() == Config.GEL_ITEM
    end)
    if not gel then
        Net.notify(player, "You need rooting gel")
        return
    end

    -- Swap the cutting for a dipped one of the same age (see header).
    local age = 0
    pcall(function() age = cutting:getAge() end)
    local dipped = {}
    for k, v in pairs(data) do dipped[k] = v end
    dipped.gel = true
    removeItem(cutting)
    giveCutting(player, Config.CUTTING_ITEM, dipped, age)
    gel:UseAndSync()
    Net.notify(player, "Dipped the cutting in rooting gel")
end

-- --------------------------------------------------------------------------
-- Cloning dome (a container item: cuttings are real items inside it)
-- --------------------------------------------------------------------------
-- The registry keeps one record per cutting in a dome, keyed by the cutting
-- item's ID: { id, data, startedAt, readyAt, success } The cutting items
-- themselves are never edited (item data changes don't reliably sync in
-- multiplayer).

--- Find a dome by item ID: in the player's inventory (bags too), or placed on
--- a nearby square (a table, the floor).
local function findDome(player, args)
    local id = tonumber(args.domeId)
    if not id then return nil end
    local function isDome(item)
        return item:getID() == id and item:getFullType() == Config.DOME_ITEM
    end
    local found = Seeds.findItem(player:getInventory(), isDome)
    if found then return found end

    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return nil end
    pcall(function()
        local square = getCell():getGridSquare(x, y, z)
        if not square then return end
        local objects = square:getWorldObjects()
        for i = 0, objects:size() - 1 do
            local item = objects:get(i):getItem()
            if item and isDome(item) then found = item end
        end
    end)
    return found
end

--- The cutting items currently inside a dome.
local function cuttingsIn(dome)
    return Seeds.findAll(dome:getInventory(), function(item)
        return Seeds.kind(item) == "cutting"
    end)
end

--- Where the dome is, for temperature and light.
local function domeSquare(dome, player)
    local square = nil
    pcall(function()
        local wo = dome:getWorldItem()
        if wo then square = wo:getSquare() end
    end)
    return square or player:getCurrentSquare()
end

--- Match the registry to what is physically in the dome. New cuttings get
--- their rooting roll now (conditions where the dome sits); records for
--- cuttings that are gone are dropped.
local function domeSync(dome, player)
    local list = Registry.getDome(dome:getID())
    local items = cuttingsIn(dome)

    local present = {}
    for _, item in ipairs(items) do present[item:getID()] = item end

    local keep, known = {}, {}
    for _, entry in ipairs(list) do
        if entry.id and present[entry.id] then
            keep[#keep + 1] = entry
            known[entry.id] = true
        end
    end

    local now = Registry.nowHours()
    local tempC, hasLight = Farming.conditionsAt(domeSquare(dome, player))
    local level = SC.agricultureLevel(player)
    for _, item in ipairs(items) do
        if not known[item:getID()] then
            local data = Seeds.getCuttingData(item)
            local chance, hours = Genetics.rootingOdds(level, {
                gel = data.gel, dome = true, tempC = tempC, hasLight = hasLight,
                wiltHours = Seeds.ageHours(item),
            })
            -- A cutting that already rotted can't root.
            local ok, rotten = pcall(function() return item:isRotten() end)
            keep[#keep + 1] = {
                id        = item:getID(),
                data      = data,
                startedAt = now,
                readyAt   = now + hours,
                success   = Config.rollPercent(chance) and not (ok and rotten),
            }
        end
    end
    Registry.setDome(dome:getID(), keep)
    return keep, present
end

--- Count cuttings by state. Returns pending, rooted, failed, hours until the
--- next one finishes.
local function domeStatus(list, now)
    local pending, rooted, failed, soonest = 0, 0, 0, nil
    for _, entry in ipairs(list) do
        if now < entry.readyAt then
            pending = pending + 1
            local left = entry.readyAt - now
            if not soonest or left < soonest then soonest = left end
        elseif entry.success then
            rooted = rooted + 1
        else
            failed = failed + 1
        end
    end
    return pending, rooted, failed, soonest
end
Cloning.domeStatus = domeStatus

--- Sent by the client after cuttings are moved into a dome, so the rooting
--- clock starts then. (Checking or taking also syncs, as a fallback.)
commands.domeSync = function(player, args)
    local dome = findDome(player, args)
    if not dome then return end
    domeSync(dome, player)
end

commands.domeCheck = function(player, args)
    local dome = findDome(player, args)
    if not dome then return end
    local list = domeSync(dome, player)
    if #list == 0 then
        Net.notify(player, "The dome is empty")
        return
    end
    local pending, rooted, failed, soonest = domeStatus(list, Registry.nowHours())
    local parts = {}
    if rooted > 0 then parts[#parts + 1] = rooted .. " rooted" end
    if failed > 0 then parts[#parts + 1] = failed .. " didn't root" end
    if pending > 0 then
        parts[#parts + 1] = pending .. " still rooting (next in ~" .. math.ceil(soonest) .. "h)"
    end
    Net.notify(player, "Cloning dome: " .. table.concat(parts, ", "))
end

commands.domeTake = function(player, args)
    local dome = findDome(player, args)
    if not dome then return end
    local list, present = domeSync(dome, player)
    local now = Registry.nowHours()

    local keep, rooted, failed = {}, 0, 0
    for _, entry in ipairs(list) do
        if now < entry.readyAt then
            keep[#keep + 1] = entry
        else
            local item = present[entry.id]
            if item then removeItem(item) end
            if entry.success then
                local data = entry.data
                data.gel = nil
                giveCutting(player, Config.ROOTED_ITEM, data)
                rooted = rooted + 1
            else
                failed = failed + 1
            end
        end
    end
    Registry.setDome(dome:getID(), keep)

    if rooted == 0 and failed == 0 then
        Net.notify(player, "Nothing has finished rooting yet")
        return
    end
    local msg = "Took " .. rooted .. " rooted cutting" .. (rooted == 1 and "" or "s")
    if failed > 0 then msg = msg .. "; " .. failed .. " didn't root and were thrown out" end
    Net.notify(player, msg)
end

-- --------------------------------------------------------------------------
-- Debug helpers (debug mode or admins only, re-checked here)
-- --------------------------------------------------------------------------

local function isDebugAllowed(player)
    return isDebugEnabled()
        or (player.getAccessLevel and player:getAccessLevel() ~= "None")
end

--- A kit for testing: a dome, rooting gel and three fresh cuttings (one of
--- each type).
commands.debugCloningKit = function(player, args)
    if not isDebugAllowed(player) then return end
    Farming.giveItems(player, Config.DOME_ITEM, 1)
    Farming.giveItems(player, Config.GEL_ITEM, 1)
    for _, t in ipairs({ Config.TYPES.INDICA, Config.TYPES.SATIVA, Config.TYPES.HYBRID }) do
        local data = Genetics.newSeed(t)
        data.sex, data.generation, data.stress, data.gel = Config.SEX.FEMALE, 1, 0, false
        giveCutting(player, Config.CUTTING_ITEM, data, 0)
    end
    Net.notify(player, "Gave a cloning kit: dome, gel, 3 cuttings")
end

--- Finish rooting right now, in a dome or in soil cuttings nearby.
commands.debugFinishRooting = function(player, args)
    if not isDebugAllowed(player) then return end
    local now = Registry.nowHours()
    if args.domeId then
        local dome = findDome(player, args)
        if dome then
            for _, entry in ipairs(domeSync(dome, player)) do entry.readyAt = now end
        end
    end
    for _, plant in Registry.each() do
        if plant.rooting then plant.rooting.readyAt = now end
    end
    Net.notify(player, "Rooting finished; results show on the next check")
end
