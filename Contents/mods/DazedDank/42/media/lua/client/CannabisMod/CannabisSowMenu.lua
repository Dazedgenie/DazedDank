-- The Sow Seed menu on a grow bag, bucket or flood table lists only cannabis seeds the player is carrying,
-- and the cannabis row opens a list of the seeds carried, grouped by what the player can read of them.

require "Farming/ISUI/ISFarmingMenu"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisInfo"
require "CannabisMod/CannabisTraits"

local Config = CannabisMod.Config
local Info = CannabisMod.Info
local Seeds = CannabisMod.Seeds

--- True when a square holds one of our pots or tables (any plot sprite on a Dank sheet that is a bag kind).
local function isPotSquare(square)
    if not square then return false end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        local name = sprite and sprite:getName()
        if name and Config.bagFromSprite(name) then return true end
    end
    return false
end

--- True when a Sow row plants a crop other than cannabis (its crop name is one of the option's arguments).
local function otherCrop(option)
    local props = farming_vegetableconf and farming_vegetableconf.props
    if not props then return false end
    for i = 1, 10 do
        local v = option["param" .. i]
        if type(v) == "string" and props[v] then return v ~= Config.CROP_TYPE end
    end
    return false
end

--- The cannabis seeds a player carries, bags included.
local function carriedSeeds(player)
    local out = {}
    local found = player:getInventory():getAllTypeRecurse(Config.SEED_ITEM)
    for i = 0, found:size() - 1 do out[#out + 1] = found:get(i) end
    return out
end

--- The player's seed groups, as the Sow list shows them.
local function seedGroups(player)
    return Info.seedGroups(carriedSeeds(player), player:getPerkLevel(Perks.Farming), CannabisMod.Traits.reading(player), Seeds.getData)
end

--- The first carried seed in the group with this label, or nil.
local function seedInGroup(player, label)
    for _, g in ipairs(seedGroups(player)) do
        if g.label == label then return g.items[1] end
    end
    return nil
end

--- Sow one seed from the chosen group here, then keep that group on the cursor for the next plots, like vanilla.
local function sowFromGroup(player, typeOfSeed, plant, sq, seedName, label)
    if ISFarmingMenu.walkToPlant(player, sq) and not isJoypadCharacter(player) then
        local seed = seedInGroup(player, label)
        if seed then
            ISInventoryPaneContextMenu.transferIfNeeded(player, seed)
            ISTimedActionQueue.add(ISSeedActionNew:new(player, seed, typeOfSeed, plant))
        end
    end
    ISFarmingMenu.cursor = ISFarmingCursorMouse:new(player, ISFarmingMenu.onSeedSquareSelected, ISFarmingMenu.isSeedValid)
    getCell():setDrag(ISFarmingMenu.cursor, player:getPlayerNum())
    ISFarmingMenu.cursor.typeOfSeed = typeOfSeed
    ISFarmingMenu.cursor.seedName = seedName
    ISFarmingMenu.cursor.ddSeedLabel = label
end

-- Clicking more plots with the cursor keeps sowing from the chosen group.
if ISFarmingMenu and ISFarmingMenu.onSeedSquareSelected and not ISFarmingMenu.ddSowGroups then
    ISFarmingMenu.ddSowGroups = true
    local original = ISFarmingMenu.onSeedSquareSelected
    function ISFarmingMenu:onSeedSquareSelected(...)
        local cursor = ISFarmingMenu.cursor
        if not (cursor and cursor.ddSeedLabel) then return original(self, ...) end
        if not ISFarmingMenu.walkToPlant(cursor.character, cursor.sq) then return end
        local plant = CFarmingSystem.instance:getLuaObjectOnSquare(cursor.sq)
        local seed = seedInGroup(cursor.character, cursor.ddSeedLabel)
        if seed and plant then
            ISInventoryPaneContextMenu.transferIfNeeded(cursor.character, seed)
            ISTimedActionQueue.add(ISSeedActionNew:new(cursor.character, seed, cursor.typeOfSeed, plant))
        end
    end
end

--- Turn the cannabis row of a Sow menu into a list of the seed groups carried.
local function addSeedChoices(context, subMenu, player, plant, sq)
    for _, option in ipairs(subMenu.options or {}) do
        if option.param1 == Config.CROP_TYPE and option.onSelect then
            local groups = seedGroups(player)
            if #groups == 0 then return end
            local seedName = option.param4
            local choices = context:getNew(context)
            for _, g in ipairs(groups) do
                choices:addOption(g.label .. " : " .. #g.items, player, sowFromGroup, Config.CROP_TYPE, plant, sq, seedName, g.label)
            end
            option.onSelect = nil
            context:addSubMenu(option, choices)
            return
        end
    end
end

if ISFarmingMenu and ISFarmingMenu.doSeedMenu and not ISFarmingMenu.ddSowFiltered then
    ISFarmingMenu.ddSowFiltered = true
    local original = ISFarmingMenu.doSeedMenu
    function ISFarmingMenu:doSeedMenu(context, plant, sq, playerObj, ...)
        -- Catch the Sow submenu as vanilla makes it, so its rows can be pruned afterwards.
        local subMenu
        local getNew = context.getNew
        context.getNew = function(c, ...)
            local m = getNew(c, ...)
            subMenu = subMenu or m
            return m
        end
        local ok, err = pcall(original, self, context, plant, sq, playerObj, ...)
        context.getNew = nil
        if not ok then error(err, 0) end
        if subMenu then pcall(addSeedChoices, context, subMenu, playerObj, plant, sq) end
        if not (subMenu and isPotSquare(sq)) then return end
        local empty = {}
        for _, option in ipairs(subMenu.options or {}) do
            if type(option.name) == "string" and (option.name:match(" : 0$") or otherCrop(option)) then empty[#empty + 1] = option.name end
        end
        for _, name in ipairs(empty) do subMenu:removeOptionByName(name) end
        if subMenu.numOptions <= 1 then
            subMenu:addOption(getText("IGUI_DD_NoSeedsCarried") ~= "IGUI_DD_NoSeedsCarried" and getText("IGUI_DD_NoSeedsCarried") or "No cannabis seeds carried", nil, nil).notAvailable = true
        end
    end
end
