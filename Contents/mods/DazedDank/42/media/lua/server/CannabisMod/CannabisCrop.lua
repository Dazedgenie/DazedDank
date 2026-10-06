-- Registers cannabis as a vanilla farming crop and overrides sprite and object
-- names for bags. Loads on clients too.

require "Farming/farming_vegetableconf"
require "Farming/farming_vegetableconf_vegetables"
require "Farming/farming_vegetableconf_vegetables_sprites"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config
local CROP = Config.CROP_TYPE

-- All twelve months. Vanilla curses a plant sown outside its sowMonth list,
-- even INDOORS, which would punish indoor grows.
local ALL_MONTHS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }

farming_vegetableconf.props[CROP] = {
    icon        = "Item_CannabisSeed",
    texture     = Config.spriteName("Hybrid", 5, "sprite"),  -- tooltip picture
    waterLvl    = Config.Water.LOW,  -- vanilla's minimum water
    waterNeeded = 70,

    -- Display only (see header). 36 hours x 5 stages = about a week.
    timeToGrow   = 36,
    harvestLevel = 5,
    mature       = 5,
    fullGrown    = 7,

    -- Vanilla never runs its own harvest for this crop (CannabisFarming.lua
    -- takes over), but these must exist because vanilla code reads them.
    minVeg = 1, maxVeg = 1, minVegAutorized = 1, maxVegAutorized = 1,

    -- Everything the Sow Seed menu offers for cannabis: seeds, rooted
    -- cuttings, and fresh cuttings stuck straight into soil.
    seedName  = Config.SEED_ITEM,
    seedTypes = { Config.SEED_ITEM, Config.ROOTED_ITEM, Config.CUTTING_ITEM },
    sowMonth  = ALL_MONTHS,

    -- Knowing vanilla's hemp-growing recipe (from the "Legalize It!"
    -- magazine) also shows the full crop tooltip for cannabis. Vanilla's
    -- KillInsideCrops option slowly kills any crop indoors unless it is a
    -- houseplant.
    isHouseplant = true,

    seasonRecipe    = "base:hemp growing season",
    harvestPosition = "High",
}

-- Vanilla expects a sprite list per crop for each condition. Ours are picked
-- by the wrapper below instead, but the lists must exist because some vanilla
-- code checks them.
for _, setName in ipairs({ "sprite", "unhealthySprite", "dyingSprite", "deadSprite", "trampledSprite" }) do
    local set = farming_vegetableconf[setName]
    if set and set.Hemp then
        set[CROP] = set.Hemp
    end
end

-- --------------------------------------------------------------------------
-- Per-type sprites
-- --------------------------------------------------------------------------
-- Vanilla picks a plant's sprite with farming_vegetableconf.getSpriteName,
-- which only knows the crop name ("Cannabis") and a growth number.

-- Reverse of Config.STAGE_TO_NBOFGROW, for plots with no registry record.
local NBOFGROW_TO_STAGE = {}
for stageName, nb in pairs(Config.STAGE_TO_NBOFGROW) do
    NBOFGROW_TO_STAGE[nb] = Config.STAGE[stageName]
end

--- Which of vanilla's five condition sets applies. Copied from vanilla's own
--- getSpriteName so cannabis looks sick/dying at the same thresholds as every
--- other crop.
local function vanillaCondition(plot)
    if plot.state == "destroyed" or plot.state == "harvested" then
        return "trampledSprite"
    end
    if plot.state == "dead" or plot.state == "rotten" then
        return "deadSprite"
    end
    local health = math.min(plot.health or 100, plot.waterLvl or 100)
    local disease = math.max(plot.mildewLvl or 0, plot.aphidLvl or 0, plot.slugsLvl or 0)
    if health < 25 or disease >= 30 then return "dyingSprite" end
    if health < 50 or disease >= 10 or (plot.fertilizer or 0) > 1 then return "unhealthySprite" end
    return "sprite"
end

local originalGetSpriteName = farming_vegetableconf.getSpriteName
CannabisMod.vanillaSpriteName = originalGetSpriteName

--- What a cannabis plot looks like: type, stage index, vanilla condition and whether it shows as male.
function CannabisMod.plantLook(plot)
    local Registry = CannabisMod.Registry
    -- Type and stage come from the server registry; clients receive the resulting sprites.
    local record = Registry and Registry.getPlant(plot.x, plot.y, plot.z)
    local plantType = record and record.type or Config.TYPES.HYBRID
    local stage = record and record.stage or NBOFGROW_TO_STAGE[plot.nbOfGrow] or Config.STAGE.Seedling
    return plantType, stage, vanillaCondition(plot), record and record.sex == Config.SEX.MALE
end

farming_vegetableconf.getSpriteName = function(plot)
    -- Other crops go straight to vanilla, without a bag lookup.
    local plowed = plot and plot.state == "plow"
    if not plot or (not plowed and plot.typeOfSeed ~= CROP) then return originalGetSpriteName(plot) end
    -- Grow bags are registered on the server by tile.
    local Registry = CannabisMod.Registry
    local bag = Registry and Registry.getBag and Registry.getBag(plot.x, plot.y, plot.z) or nil

    -- An empty grow bag shows the bag, not plowed soil.
    if plowed and bag then
        return Config.bagEmptySprite(bag, Registry.isBagSoiled(plot.x, plot.y, plot.z))
    end
    if plowed then return originalGetSpriteName(plot) end
    -- A plant in a container keeps the container's sprite; the plant is a raised layer on top (CannabisPotPlants).
    if bag and Config.GrowBag[bag] then return Config.bagEmptySprite(bag, true) end
    local plantType, stage, condition, male = CannabisMod.plantLook(plot)
    return Config.spriteName(plantType, stage, condition, nil, male)
end

-- Name shown over a plot: an empty bag is a "Small Grow Bag", not "Plowed
-- Land".
local originalGetObjectName = farming_vegetableconf.getObjectName

farming_vegetableconf.getObjectName = function(plot)
    if plot and plot.state == "plow" then
        local Registry = CannabisMod.Registry
        local bag = Registry and Registry.getBag and Registry.getBag(plot.x, plot.y, plot.z)
        if bag and Config.GrowBag[bag] then
            local name = Config.GrowBag[bag].name
            if not Registry.isBagSoiled(plot.x, plot.y, plot.z) then
                name = name .. (Config.isHydro(bag) and ", needs a medium" or ", needs soil")
            end
            return name
        end
    end
    return originalGetObjectName(plot)
end
