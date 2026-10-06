-- Bridges the plant registry and vanilla farm plots by hooking sowing, the
-- growth sync and harvest.

if isClient() then return end

require "Farming/SFarmingSystem"
require "Farming/SPlantGlobalObject"
require "Farming/TimedActions/ISSeedActionNew"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisCrop"
require "CannabisMod/CannabisStrains"

local Config   = CannabisMod.Config
local Genetics = CannabisMod.Genetics
local Strains  = CannabisMod.Strains
local Seeds    = CannabisMod.Seeds
local Net      = CannabisMod.Net
local Registry = CannabisMod.Registry

local CROP = Config.CROP_TYPE

local Farming = {}
CannabisMod.Farming = Farming

-- How far ahead we push vanilla's "next grow" time, in hours. Big enough that
-- vanilla never gets there before our next 10-minute check.
local FROZEN_HOURS = 100000

-- --------------------------------------------------------------------------
-- Helpers
-- --------------------------------------------------------------------------

--- The vanilla farming system, or nil if it isn't ready yet.
local function farmingSystem()
    return SFarmingSystem and SFarmingSystem.instance
end

--- The vanilla plot object ("luaObject") on a tile, or nil.
function Farming.getVanilla(x, y, z)
    local sys = farmingSystem()
    if not sys then return nil end
    return sys:getLuaObjectAt(x, y, z)
end

--- True if this vanilla plot is a living cannabis plant.
local function isOurLivePlant(luaObject)
    return luaObject
        and luaObject.typeOfSeed == CROP
        and luaObject.state == "seeded"
        and luaObject:isAlive()
end

--- Stop vanilla from growing the plant on its own timer.
local function holdVanillaClock(luaObject)
    local sys = farmingSystem()
    if sys then
        luaObject.nextGrowing = sys.hoursElapsed + FROZEN_HOURS
    end
end

--- Colour the plot's object by its strain (no plant: back to plain). Every game call is guarded, so a build without custom colours just shows plain sprites.
local function applyTint(plant, luaObject)
    if not luaObject.getIsoObject then return end
    if plant and not Config.sandbox("StrainTint") then plant = nil end
    local ok, obj = pcall(luaObject.getIsoObject, luaObject)
    if not ok or not obj or not obj.setCustomColor then return end
    local r, g, b = 1, 1, 1
    if plant then r, g, b = Strains.tint(Strains.of(plant)) end
    -- In a container the colour goes on the raised plant, and the container itself stays plain.
    local overlay = Config.overlayOn(obj:getSquare())
    local function paint(target, cr, cg, cb)
        pcall(function()
            target:setCustomColor(cr, cg, cb, 1)
            if isServer() and target.sendObjectChange then target:sendObjectChange("customColor") end
        end)
    end
    if overlay then
        paint(obj, 1, 1, 1)
        paint(overlay, r, g, b)
    else
        paint(obj, r, g, b)
    end
end
Farming.applyTint = applyTint

--- Make the vanilla plot show the right sprite and name for our stage.
local function applyStage(plant, luaObject)
    local stageName = Config.STAGES[plant.stage]
    luaObject.nbOfGrow = Config.STAGE_TO_NBOFGROW[stageName] or luaObject.nbOfGrow

    -- At Ripe, vanilla's own "Harvest" option appears (it checks
    -- hasVegetable). Males get it too, so players can clear them.
    luaObject.hasVegetable = plant.stage >= Config.STAGE.Ripe

    holdVanillaClock(luaObject)
    luaObject:setObjectName(farming_vegetableconf.getObjectName(luaObject))
    local sprite = farming_vegetableconf.getSpriteName(luaObject)
    if sprite then luaObject:setSpriteName(sprite) end
    applyTint(plant, luaObject)
    luaObject:saveData()
end

-- --------------------------------------------------------------------------
-- Called by the registry
-- --------------------------------------------------------------------------

--- Our stage changed: update the plot on the map.
function Farming.onStageChanged(plant)
    local luaObject = Farming.getVanilla(plant.x, plant.y, plant.z)
    if isOurLivePlant(luaObject) then
        applyStage(plant, luaObject)
    end
end

--- Mark a bag's plot as plowed today, so vanilla doesn't let an empty one fade away.
local function freshenPlot(luaObject, today)
    local square = luaObject:getSquare()
    if square then square:getModData().plowDay = today end
end

--- Runs every 10 minutes before the registry's own checks.
function Farming.syncWithVanilla()
    local sys = farmingSystem()
    if not sys then return end

    local count = sys:getLuaObjectCount()
    local seen = {}

    for i = 1, count do
        local luaObject = sys:getLuaObjectByIndex(i)
        local ours = luaObject and luaObject.typeOfSeed == CROP
        local live = ours and isOurLivePlant(luaObject)
        if ours and not live and luaObject.state ~= "plow" then
            -- dead, rotten, harvested or destroyed: keep the record, frozen
            local plant = Registry.getPlant(luaObject.x, luaObject.y, luaObject.z)
            if plant then
                plant.dead = true
                seen[Config.tileKey(luaObject.x, luaObject.y, luaObject.z)] = true
            end
        elseif live then
            local x, y, z = luaObject.x, luaObject.y, luaObject.z
            local plant = Registry.getPlant(x, y, z)
            if not plant then
                local types = { Config.TYPES.INDICA, Config.TYPES.SATIVA, Config.TYPES.HYBRID }
                plant = Registry.addPlant(x, y, z, Genetics.newSeed(types[Config.randInt(1, 3)]))
                applyStage(plant, luaObject)
            end
            -- A plant grown bigger by extra veg drinks more.
            local bonus = Config.isHydro(plant.bag) and 0 or Config.Timer.vegBonus(plant.extraVegHours)
            if bonus > 0 and plant.stage < Config.STAGE.Ripe and (luaObject.waterLvl or 0) > 0 then
                local extra = Config.Timer.EXTRA_WATER_PER_HOUR / 6 * bonus / Config.Timer.VEG_BONUS_MAX
                luaObject.waterLvl = math.max(0, luaObject.waterLvl - extra)
                pcall(luaObject.saveData, luaObject)
            end
            plant.water = luaObject.waterLvl
            holdVanillaClock(luaObject)
            seen[Config.tileKey(x, y, z)] = true
        end
    end

    -- Grow bag upkeep: forget bags whose plot is gone, and keep empty bag
    -- plots from fading away (vanilla slowly removes old unplanted plots).
    if count > 0 then
        local lostBags = {}
        local today = getGameTime():getWorldAgeHours() / 24
        for key, size in Registry.eachBag() do
            local x, y, z = key:match("^(-?%d+)_(-?%d+)_(-?%d+)$")
            local luaObject = x and Farming.getVanilla(tonumber(x), tonumber(y), tonumber(z))
            if not luaObject then
                lostBags[#lostBags + 1] = { tonumber(x), tonumber(y), tonumber(z) }
            else
                pcall(freshenPlot, luaObject, today)
            end
        end
        for _, c in ipairs(lostBags) do Registry.clearBag(c[1], c[2], c[3]) end
    end

    -- If vanilla reports no plots at all, it may simply not have loaded yet.
    -- Don't wipe our records on that; real removals happen on later ticks.
    if count == 0 then return end

    -- Collect first, then remove, so we don't change the table while looping
    -- over it.
    local gone = {}
    for key, plant in Registry.each() do
        if not seen[key] then gone[#gone + 1] = plant end
    end
    for _, plant in ipairs(gone) do
        Registry.removePlant(plant.x, plant.y, plant.z)
    end
end

-- --------------------------------------------------------------------------
-- Hook 1: sowing
-- --------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Growing conditions at a square (used for rooting)
-- --------------------------------------------------------------------------

--- Temperature (C) and whether there's light at a square. Each lookup is
--- wrapped in pcall: if the game API differs, we fall back to "fine" rather
--- than breaking the action.
function Farming.conditionsAt(square)
    local tempC, hasLight = nil, true
    if square then
        pcall(function()
            local climate = getClimateManager()
            tempC = climate:getAirTemperatureForSquare(square)
        end)
        pcall(function()
            if square:isOutside() then
                -- outdoors: daylight between 6am and 8pm
                local hour = getGameTime():getHour()
                hasLight = hour >= 6 and hour < 20
            else
                -- indoors: needs the building's power on (lights can run)
                hasLight = square:haveElectricity() or getWorld():isHydroPowerOn()
            end
        end)
    end
    return tempC, hasLight
end

-- --------------------------------------------------------------------------
-- Hook 1: sowing (seeds, rooted cuttings, and fresh cuttings stuck in soil)
-- --------------------------------------------------------------------------

local originalSeedComplete = ISSeedActionNew.complete

function ISSeedActionNew:complete()
    -- A grow bag has to be filled with soil before its first planting.
    local pl = self.plant
    local bagKind = pl and Registry.getBag(pl.x, pl.y, pl.z)
    if bagKind and self.typeOfSeed ~= CROP then
        if Net and self.character then Net.notify(self.character, "Grow bags, buckets and flood tables only take cannabis") end
        return false
    end
    if bagKind and not Registry.isBagSoiled(pl.x, pl.y, pl.z) then
        local msg = Config.isHydro(bagKind) and "Add a rockwool cube or clay pebbles first" or "Fill the grow bag with soil first"
        if Net and self.character then Net.notify(self.character, msg) end
        return false
    end
    -- A hydro plant drinks only from its reservoir, so it must be connected and hold water before anything goes in.
    local Hydro = CannabisMod.Hydro
    if bagKind and Config.isHydro(bagKind) and Hydro then
        local r = Hydro.reservoirOf(pl.x, pl.y, pl.z)
        local unlinked = bagKind == "ebb" and "Stand a flood reservoir beside this row of tables first"
            or "Connect this site to an RDWC control bucket first"
        local why = (not r and unlinked)
            or (r.level <= 0 and "Fill the reservoir first") or nil
        if why then
            if Net and self.character then Net.notify(self.character, why) end
            return false
        end
    end
    -- A seed sown straight into clay pebbles can slip down between them and never take.
    if bagKind and Config.isHydro(bagKind) and self.seed and Seeds.kind(self.seed) == "seed" and Hydro and Hydro.seedFails(pl.x, pl.y, pl.z) then
        local container = self.seed:getContainer()
        if container then
            container:Remove(self.seed)
            sendRemoveItemFromContainer(container, self.seed)
        end
        if Net and self.character then Net.notify(self.character, "The seed slipped down between the pebbles and didn't take") end
        return true
    end
    -- Read everything we need NOW, before vanilla removes the item.
    local kind, data, ageHours = nil, nil, 0
    if self.typeOfSeed == CROP and self.seed then
        kind = Seeds.kind(self.seed)
        data = Seeds.getPlantData(self.seed)
        if kind == "cutting" then ageHours = Seeds.ageHours(self.seed) end
    end

    local result = originalSeedComplete(self)

    if data then
        local p = self.plant
        local luaObject = Farming.getVanilla(p.x, p.y, p.z)
        if isOurLivePlant(luaObject) then
            -- Cuttings (rooted or not) skip the seedling stage.
            local plant = Registry.addPlant(p.x, p.y, p.z, data, { fromCutting = kind ~= "seed" })
            if kind == "cutting" then
                -- A fresh cutting stuck straight into soil still has to root.
                -- Roll it now; the registry settles it when the time is up
                -- (dies if it failed).
                local tempC, hasLight = Farming.conditionsAt(luaObject:getSquare())
                local chance, hours = Genetics.rootingOdds(self.character:getPerkLevel(Perks.Farming), {
                    gel = data.gel, soil = true, tempC = tempC, hasLight = hasLight,
                    moist = (Config.isHydro(Registry.getBag(p.x, p.y, p.z)) and CannabisMod.Hydro
                        and CannabisMod.Hydro.isMoist(p.x, p.y, p.z)) or (luaObject.waterLvl or 0) >= Config.Water.LOW,
                    wiltHours = ageHours,
                })
                Registry.startRooting(plant, hours, Config.rollPercent(chance))
            end
            applyStage(plant, luaObject)
        end
    end
    return result
end

--- A cutting that failed to root in soil dies on its plot.
function Farming.killPlant(plant)
    local luaObject = Farming.getVanilla(plant.x, plant.y, plant.z)
    plant.dead = true
    if isOurLivePlant(luaObject) then
        luaObject:killThis()
    end
end

-- --------------------------------------------------------------------------
-- Hook 2: harvest
-- --------------------------------------------------------------------------

--- Hours the harvest is outside the ripe window (0 = perfect timing).
local function hoursOutsideWindow(plant)
    if plant.stage < Config.STAGE.Ripe then return 0 end
    return math.max(0, Registry.nowHours() - plant.nextStageAt)
end

--- Give items to a player in a way that works in multiplayer. AddItems makes
--- the items; `prepare` lets us write modData on each one BEFORE they're
--- sent, so the data travels with them.
function Farming.giveItems(player, fullType, count, prepare)
    local inv = player:getInventory()
    local items = inv:AddItems(fullType, count)
    if prepare then
        for i = 0, items:size() - 1 do
            prepare(items:get(i), i + 1)
        end
    end
    sendAddItemsToContainer(inv, items)
end

--- Our harvest for one cannabis plant.
local function harvestCannabis(luaObject, player)
    local x, y, z = luaObject.x, luaObject.y, luaObject.z
    local plant = Registry.getPlant(x, y, z)

    if plant and player then
        if plant.sex == Config.SEX.MALE then
            -- Males make pollen, not buds.
            Net.notify(player, "Male plants don't produce buds.")
        else
            local quality = Genetics.calcQuality(plant, hoursOutsideWindow(plant), Config.dryHours())
            local range = Config.BUD_YIELD
            local buds = Config.randInt(range.min, range.max)
            local strain = Strains.of(plant)
            buds = buds * Config.sandbox("HarvestQuantity") * (plant.genetics / 100) * Strains.yieldMult(strain)
            -- Roots spread in a big bag.
            if plant.bag and Config.GrowBag[plant.bag] then
                buds = buds * Config.GrowBag[plant.bag].yield
            end
            -- Extra veg time grew a bigger plant.
            buds = buds * (1 + (plant.vegBonus or Config.Timer.vegBonus(plant.extraVegHours)))
            -- Topping in veg split the main cola into several.
            if plant.topped then buds = buds * (1 + Config.Topping.YIELD_BONUS) end
            buds = math.max(1, math.floor(buds + 0.5))

            -- Everything later steps need, stored on the harvested plant.
            -- `quality` here assumes a full dry; drying (step 6) applies the
            -- real dry multiplier and the mold roll.
            local wetItem = Config.WET_PLANT_ITEMS[plant.type] or Config.WET_PLANT_ITEMS.Hybrid
            Farming.giveItems(player, wetItem, 1, function(item)
                item:getModData().CannabisHarvest = {
                    type          = plant.type,
                    strain        = Strains.copy(strain),
                    quality       = quality,
                    budYield      = buds,
                    seeded        = plant.seeded == true,
                    genetics      = plant.genetics,
                    generation    = plant.generation,
                    hermieLineage = plant.hermieLineage == true,
                    harvestedAt   = Registry.nowHours(),
                }
            end)

            -- Pollinated (by a male or a hermie): seeds too.
            if plant.seeded then
                local father = {
                    type          = plant.fatherType or plant.type,
                    strain        = plant.fatherStrain or Strains.fromType(plant.fatherType or plant.type, plant.x),
                    hermieLineage = plant.fatherHermieLineage == true,
                }
                local seedList = Genetics.seedsFromPollination(plant, father)
                Farming.giveItems(player, Config.SEED_ITEM, #seedList, function(item, n)
                    Seeds.setData(item, seedList[n])
                end)
            end
        end
    end

    if plant and CannabisMod.Rooms then
        local text = plant.sex == Config.SEX.MALE and "Cleared a male plant" or ("Harvested a " .. plant.type .. " plant")
        CannabisMod.Rooms.logTile(Config.tileKey(x, y, z), text)
    end

    -- The whole plant is cut down and carried off. In a grow bag the bag
    -- stays (emptied, ready to sow again).
    luaObject.hasVegetable = false
    luaObject.hasSeed = false
    local GrowBags = CannabisMod.GrowBags
    if GrowBags and Registry.getBag(x, y, z) then
        GrowBags.reset(luaObject)
    else
        Registry.removePlant(x, y, z)
        SFarmingSystem.instance:removePlant(luaObject)
    end
end

local originalHarvest = SFarmingSystem.harvest

function SFarmingSystem:harvest(luaObject, player)
    if luaObject and luaObject.typeOfSeed == CROP then
        harvestCannabis(luaObject, player)
        return
    end
    return originalHarvest(self, luaObject, player)
end
