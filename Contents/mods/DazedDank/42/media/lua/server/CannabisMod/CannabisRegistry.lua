-- The server's record of every cannabis plant, kept in global ModData by tile
-- key. The server is the only source of truth in multiplayer.

-- On a multiplayer CLIENT, server files are not used. Stop here.
if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisTraits"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisStrains"

local Config = CannabisMod.Config
local Genetics = CannabisMod.Genetics
local Strains = CannabisMod.Strains

-- Stages whose length a strain's flowering speed changes.
local FLOWER_STAGES = { PreFlower = true, Flowering = true }

local Registry = {}
CannabisMod.Registry = Registry

-- The actual table of plants. Filled in by onInitGlobalModData below.
local plants = nil
local bags = nil  -- grow bag tiles: key -> "small" | "large"
local soiled = nil  -- grow bag tiles that have been filled with soil: key -> true
local domes = nil  -- cloning dome contents, see "Cloning domes" below

-- --------------------------------------------------------------------------
-- Time helpers
-- --------------------------------------------------------------------------

--- Current game time in hours since the world started. Always increases,
--- survives save/load, and is the same for every player on the server.
local function nowHours()
    return getGameTime():getWorldAgeHours()
end
Registry.nowHours = nowHours

--- Random length for a stage, scaled by the GrowthSpeed sandbox option and, in flower, by the strain.
local function rollStageHours(stageIndex, plant)
    local stageName = Config.STAGES[stageIndex]
    local range = Config.STAGE_HOURS[stageName]
    local hours = Config.randInt(range.min, range.max)
    if plant and FLOWER_STAGES[stageName] then
        hours = hours * Strains.flowerMult(Strains.of(plant))
    end
    local speed = Config.sandbox("GrowthSpeed")
    if speed and speed > 0 then
        -- The option allows 0.1 to 10. Clamp so a bad value can never make a
        -- stage last months (or seconds).
        speed = math.max(0.1, math.min(10, speed))
        hours = hours / speed
    end
    return hours
end

-- --------------------------------------------------------------------------
-- Loading the saved data
-- --------------------------------------------------------------------------

--- Runs once when the world loads. getOrCreate returns the saved table if one
--- exists, or a fresh empty table for a new world.
local function onInitGlobalModData(isNewGame)
    plants = ModData.getOrCreate(Config.MODDATA_KEY)
    domes = ModData.getOrCreate(Config.MODDATA_KEY .. "_Domes")
    bags = ModData.getOrCreate(Config.MODDATA_KEY .. "_Bags")
    soiled = ModData.getOrCreate(Config.MODDATA_KEY .. "_BagSoil")
    -- Every strain name given out, so two different crosses never share one.
    Strains.useRegistry(ModData.getOrCreate(Config.MODDATA_KEY .. "_StrainNames"))
end
Events.OnInitGlobalModData.Add(onInitGlobalModData)

-- --------------------------------------------------------------------------
-- Creating, reading and removing plants
-- --------------------------------------------------------------------------

--- Register a new plant on a tile.
--- @param x,y,z tile position
--- @param seed seed or cutting data from Genetics.newSeed / cloneFrom
--- @param opts { fromCutting = bool } cuttings skip the Seedling stage
--- @return the new plant record
function Registry.addPlant(x, y, z, seed, opts)
    opts = opts or {}
    local key = Config.tileKey(x, y, z)
    local startStage = opts.fromCutting and Config.STAGE.Vegetative or Config.STAGE.Seedling
    local now = nowHours()

    local plant = {
        -- Position (stored so we can find the tile again from the record).
        x = x, y = y, z = z,

        -- Genetics, copied from the seed or cutting.
        type          = seed.type,
        strain        = Strains.copy(Strains.of(seed)),
        sex           = seed.sex,
        genetics      = seed.genetics,
        generation    = seed.generation or 0,
        hermieLineage = seed.hermieLineage == true,

        -- Growth.
        stage       = startStage,
        plantedAt   = now,
        nextStageAt = now + rollStageHours(startStage),

        -- Condition. Care starts at 100 and only goes down (except small
        -- bonuses for correct feeding).
        care   = Config.Care.START,
        stress = seed.stress or 0,
        water  = 50,

        -- Feeding history. fedThisStage stops double-feeding bonuses and
        -- detects nutrient burn.
        lastNutrient = nil,
        fedThisStage = 0,

        -- Light. Updated every 10 minutes by CannabisLight.lua.
        bag = bags and bags[key] or nil,

        lightSource = "Sun",
        lightCap    = Config.LightCap.SUN,

        -- Pollination / hermie.
        seeded     = false,  -- true once pollinated (by a male or hermie)
        fatherType = nil,  -- type of whatever pollinated it, for seeds
        fatherStrain = nil,  -- and its strain, which the seeds cross with the mother's
        fatherHermieLineage = false,
        isHermie   = false,

        -- Flags shown as warnings in the status window at Agriculture 5+.
        warnings = {},
    }

    plants[key] = plant
    return plant
end

--- Get the plant on a tile, or nil.
function Registry.getPlant(x, y, z)
    if not plants then return nil end
    return plants[Config.tileKey(x, y, z)]
end

-- --------------------------------------------------------------------------
-- Grow bags (tile -> size)
-- --------------------------------------------------------------------------

function Registry.getBag(x, y, z)
    if not bags then return nil end
    return bags[Config.tileKey(x, y, z)]
end

function Registry.setBag(x, y, z, size)
    if bags then bags[Config.tileKey(x, y, z)] = size end
end

function Registry.clearBag(x, y, z)
    if bags then bags[Config.tileKey(x, y, z)] = nil end
    if soiled then soiled[Config.tileKey(x, y, z)] = nil end
    -- Its hydro record (medium, link, reservoir) goes too, so a new bucket here starts clean.
    if CannabisMod.Hydro then CannabisMod.Hydro.clear(x, y, z) end
end

--- Has this bag been filled with soil yet? Old bags from before soil existed
--- read as unfilled; they just need one sack.
function Registry.isBagSoiled(x, y, z)
    return soiled ~= nil and soiled[Config.tileKey(x, y, z)] == true
end

function Registry.setBagSoiled(x, y, z, value)
    if soiled then soiled[Config.tileKey(x, y, z)] = value and true or nil end
end

--- for key, size in Registry.eachBag() do ... end (key is "x_y_z")
function Registry.eachBag()
    return pairs(bags or {})
end

--- Remove a plant (harvested, dug up, or died).
function Registry.removePlant(x, y, z)
    if not plants then return end
    plants[Config.tileKey(x, y, z)] = nil
end

--- Loop over every plant: for key, plant in Registry.each() do ... end
function Registry.each()
    return pairs(plants or {})
end

-- --------------------------------------------------------------------------
-- Rooting in soil
-- --------------------------------------------------------------------------

--- A fresh cutting stuck in soil: hold its growth until it has rooted. The
--- outcome is rolled when it's planted (so conditions at planting time count)
--- and settled when the time is up.
--- @param hours how long rooting takes
--- @param success the pre-rolled result
function Registry.startRooting(plant, hours, success)
    local now = nowHours()
    plant.rooting = { readyAt = now + hours, success = success == true }
    -- The vegetative timer only starts once the roots are in.
    plant.nextStageAt = plant.rooting.readyAt + rollStageHours(plant.stage, plant)
end

--- Settle a soil cutting whose rooting time is up.
local function settleRooting(plant, now)
    if not plant.rooting or now < plant.rooting.readyAt then return end
    local ok = plant.rooting.success
    plant.rooting = nil
    if not ok and CannabisMod.Farming then
        CannabisMod.Farming.killPlant(plant)
    elseif not ok then
        plant.dead = true
    end
end
Registry.settleRooting = settleRooting

-- --------------------------------------------------------------------------
-- Cloning domes
-- --------------------------------------------------------------------------
-- What's inside each Cloning Dome item, keyed by the item's ID (IDs are the
-- same on server and clients and survive save/load).

--- The cuttings in a dome, or an empty list; reading never adds a record.
function Registry.getDome(domeId)
    return domes and domes[tostring(domeId)] or {}
end

--- Replace a dome's cuttings; an empty dome drops its record from the save.
function Registry.setDome(domeId, list)
    if not domes then return end
    if list and #list == 0 then list = nil end
    domes[tostring(domeId)] = list
end

-- --------------------------------------------------------------------------
-- Care: stress and penalties
-- --------------------------------------------------------------------------

--- Take care points away and add matching stress. One function for every kind
--- of mistake, so care and stress always move together.
function Registry.applyPenalty(plant, amount, warningName)
    -- Hydro systems are more forgiving: their containers scale every care penalty.
    local def = plant.bag and Config.GrowBag[plant.bag]
    if def and def.careMult then amount = amount * def.careMult end
    if plant.greenThumb and CannabisMod.Traits and CannabisMod.Traits.enabled() then amount = amount * CannabisMod.Traits.GREEN_THUMB_CARE end
    plant.care = Config.clamp(plant.care - amount, 0, 100)
    plant.stress = Config.clamp(plant.stress + amount * Config.Care.STRESS_FROM_CARE,
        0, Config.Stress.MAX)
    if warningName then
        plant.warnings[warningName] = true
    end
end

--- Feed a plant. nutrient = "Veg" or "Bloom". Right nutrient for the stage,
--- first feed this stage: small bonus.
function Registry.feed(plant, nutrient)
    -- Hydro plants are fed through their reservoir.
    if Config.isHydro(plant.bag) and CannabisMod.Hydro then return CannabisMod.Hydro.feed(plant, nutrient) end
    local stageName = Config.STAGES[plant.stage]
    plant.fedThisStage = plant.fedThisStage + 1
    plant.lastNutrient = nutrient

    if plant.fedThisStage > 1 then
        Registry.applyPenalty(plant, Config.Care.NUTRIENT_BURN, "nutrientBurn")
        return "burn"
    end

    -- Which nutrient each stage wants. Pre-flower accepts either because
    -- growers switch from veg to bloom food during it.
    local wanted = {
        Vegetative = { Veg = true },
        PreFlower  = { Veg = true, Bloom = true },
        Flowering  = { Bloom = true },
    }
    local ok = wanted[stageName] and wanted[stageName][nutrient]
    if ok then
        plant.care = math.min(100, plant.care + Config.Care.RIGHT_NUTRIENT_BONUS)
        return "good"
    end
    Registry.applyPenalty(plant, Config.Care.WRONG_NUTRIENT, "wrongNutrient")
    return "wrong"
end

-- --------------------------------------------------------------------------
-- Water
-- --------------------------------------------------------------------------

--- Called every 10 minutes. plant.water is copied from the vanilla plot by
--- CannabisFarming.lua. Too wet or too dry costs care (and adds stress).
function Registry.waterCheck(plant)
    if plant.dead or plant.stage <= Config.STAGE.Seedling or plant.water == nil then return end
    local c = Config.Care
    if plant.water > Config.Water.HIGH then
        -- Fabric bags breathe: less overwater damage.
        local drain = plant.bag and Config.GrowBag[plant.bag] and Config.GrowBag[plant.bag].drain or 1
        Registry.applyPenalty(plant, c.OVERWATER_PER_HOUR / 6 * drain, "overwatered")
    else
        plant.warnings.overwatered = nil
    end
    if plant.water < Config.Water.LOW then
        Registry.applyPenalty(plant, c.UNDERWATER_PER_HOUR / 6, "underwatered")
    else
        plant.warnings.underwatered = nil
    end
end

-- --------------------------------------------------------------------------
-- Pollination
-- --------------------------------------------------------------------------

-- During the plant tick the flowering, unseeded females are listed once and shared by every pollen source.
-- nil outside a tick; false inside one until the first source asks.
local tickFemales = nil

--- Every living female that is flowering and not yet seeded.
local function openFemales()
    local list = {}
    local FEMALE, FLOWERING = Config.SEX.FEMALE, Config.STAGE.Flowering
    for _, other in Registry.each() do
        if not other.dead and not other.seeded and other.sex == FEMALE and other.stage == FLOWERING then
            list[#list + 1] = other
        end
    end
    return list
end

--- Pollinate every flowering female within range of a pollen source. Called
--- when a male or a hermie is flowering.
--- @param source the male or hermie plant record
function Registry.pollinateAround(source)
    local targets = tickFemales
    if targets == false then
        targets = openFemales()
        tickFemales = targets
    elseif targets == nil then
        targets = openFemales()
    end
    local r, abs = Config.POLLINATION_RADIUS, math.abs
    -- Re-check each one, since earlier sources this tick may have seeded it.
    for _, other in ipairs(targets) do
        if other ~= source and not other.seeded and not other.dead and other.stage == Config.STAGE.Flowering and other.z == source.z
            and abs(other.x - source.x) <= r and abs(other.y - source.y) <= r then
            other.seeded = true
            other.fatherType = source.type
            other.fatherStrain = Strains.copy(Strains.of(source))
            other.fatherHermieLineage = source.hermieLineage == true
        end
    end
end

-- --------------------------------------------------------------------------
-- Growth clock
-- --------------------------------------------------------------------------

--- True if a plant has finished its minimum veg but its lamps keep it vegging (no 12/12 timer, or a light leak).
function Registry.heldInVeg(plant)
    return plant.stage == Config.STAGE.Vegetative
        and (plant.lightCycle == "long" or plant.lightCycle == "leak")
end

--- One 10-minute tick of extra veg: the plant grows on, and wants feeding every couple of days.
function Registry.extendVeg(plant, now)
    plant.extraVegHours = (plant.extraVegHours or 0) + 1 / 6
    plant.vegHeld = true
    if plant.warnings.overcut and Genetics.cutsAvailable(plant, now) >= 1 then plant.warnings.overcut = nil end
    local mother = Config.isMotherPot(plant.bag)
    -- A mother in an XL pot shakes off the stress of being cut while she's held in veg.
    if mother and (plant.cutStress or 0) > 0 then
        local r = math.min(plant.cutStress, Config.Mother.CUT_STRESS_RECOVERY_PER_HOUR / 6)
        plant.cutStress = plant.cutStress - r
        plant.stress = math.max(0, (plant.stress or 0) - r)
    end
    -- Hydro plants eat from their reservoir instead of a feeding schedule.
    if Config.isHydro(plant.bag) then return end
    local every = mother and Config.Mother.FEED_EVERY_HOURS or Config.Timer.FEED_EVERY_HOURS
    plant.vegFeedDueAt = plant.vegFeedDueAt or (now + every)
    if now >= plant.vegFeedDueAt then
        if (plant.fedThisStage or 0) == 0 then
            Registry.applyPenalty(plant, Config.Timer.HUNGRY_PENALTY, "hungry")
        else
            plant.warnings.hungry = nil
        end
        plant.fedThisStage = 0
        plant.vegFeedDueAt = now + every
    end
end

--- Top a plant in veg: more colas at harvest, some stress and a short pause. Returns nil, or why it can't be done.
function Registry.top(plant, now)
    if plant.stage ~= Config.STAGE.Vegetative then return "Plants can only be topped in veg" end
    if plant.topped then return "This plant has already been topped" end
    local t = Config.Topping
    plant.topped = true
    plant.stress = Config.clamp((plant.stress or 0) + t.STRESS, 0, Config.Stress.MAX)
    local speed = math.max(0.1, math.min(10, Config.sandbox("GrowthSpeed") or 1))
    -- A plant already held in veg pauses from now; one still in its veg timer has that timer pushed back.
    plant.nextStageAt = math.max(plant.nextStageAt or now, now) + t.PAUSE_HOURS / speed
    return nil
end

--- Cutting past the pot's budget sets the plant back: pre-flower drops to veg, and the veg timer starts over.
function Registry.setBack(plant, now)
    if plant.stage == Config.STAGE.PreFlower then
        plant.stage = Config.STAGE.Vegetative
        plant.fedThisStage = 0
        if CannabisMod.Farming then CannabisMod.Farming.onStageChanged(plant) end
    end
    plant.nextStageAt = now + rollStageHours(Config.STAGE.Vegetative, plant)
    plant.warnings.overcut = true
end

--- Move a plant to its next stage and start the new stage timer.
function Registry.advanceStage(plant)
    if plant.stage >= Config.STAGE.Ripe then return end
    if plant.stage == Config.STAGE.Vegetative then
        -- Leaving veg: lock in the yield bonus earned by extra veg time.
        plant.vegBonus = Config.Timer.vegBonus(plant.extraVegHours)
        plant.vegHeld = nil
        plant.vegFeedDueAt = nil
        plant.warnings.hungry = nil
    end
    plant.stage = plant.stage + 1
    plant.nextStageAt = nowHours() + rollStageHours(plant.stage, plant)
    -- Late flower (cold nights, purple) is measured from here.
    if plant.stage == Config.STAGE.Flowering then plant.flowerStartAt = nowHours() end
    plant.fedThisStage = 0
    plant.warnings.nutrientBurn = nil
    plant.warnings.overcut = nil
    plant.warnings.wrongNutrient = nil

    -- Ripe: remember when the harvest window opened. The window closes at
    -- nextStageAt; harvesting after that is "late" and costs quality.
    if plant.stage == Config.STAGE.Ripe then
        plant.ripeAt = nowHours()
    end
    -- A female that starts flowering mid-tick joins this tick's pollination list.
    if tickFemales and plant.stage == Config.STAGE.Flowering and plant.sex == Config.SEX.FEMALE
            and not plant.seeded and not plant.dead then
        tickFemales[#tickFemales + 1] = plant
    end

    -- Tell the vanilla farming link so the sprite (and, at Ripe, the Harvest
    -- option) matches our stage. CannabisFarming.lua sets this up; it's
    -- missing only in the offline tests.
    if CannabisMod.Farming then
        CannabisMod.Farming.onStageChanged(plant)
    end
end

--- Checks done every 10 minutes while a plant is flowering.
local function flowerChecks(plant)
    -- Males release pollen while flowering.
    if plant.sex == Config.SEX.MALE then
        Registry.pollinateAround(plant)
        return
    end

    -- Stressed females may turn hermie. hermieChance() is the chance over the
    -- WHOLE flowering stage (25% at max stress).
    if not plant.isHermie then
        local total = Genetics.hermieChance(plant.stress) / 100
        if total > 0 then
            local range = Config.STAGE_HOURS.Flowering
            local avgHours = (range.min + range.max) / 2 / Config.sandbox("GrowthSpeed")
            local checks = math.max(1, avgHours * 6)
            local perCheck = 1 - (1 - total) ^ (1 / checks)
            if Config.randInt(1, 1000000) <= perCheck * 1000000 then
                Genetics.makeHermie(plant)
            end
        end
    end

    -- A hermie pollinates itself AND every flowering female nearby.
    if plant.isHermie then
        plant.seeded = true
        plant.fatherType = plant.fatherType or plant.type
        plant.fatherStrain = plant.fatherStrain or Strains.copy(Strains.of(plant))
        plant.fatherHermieLineage = true
        Registry.pollinateAround(plant)
    end
end

--- One 10-minute step for every plant: rooting, light, stage, flowering, hydro and water.
local function tickPlants(now)
    for _, plant in Registry.each() do
        -- Dead and harvested plants keep their record (for their sprite) but
        -- no longer grow, drink, flower or pollinate.
        if not plant.dead and plant.rooting then
            settleRooting(plant, now)
        end
        local stalled = false
        if not plant.dead and not plant.rooting and CannabisMod.Light then
            stalled = CannabisMod.Light.update(plant)
        end
        -- Outdoor heat and cold, and cold nights in late flower.
        if not plant.dead and not plant.rooting and CannabisMod.PlantTemp then
            CannabisMod.PlantTemp.update(plant, now, stalled)
        end
        if not plant.dead and not plant.rooting then
            -- Stage timer ran out: move on (Ripe stays Ripe; overripe is
            -- handled by the harvest multiplier).
            if not stalled and plant.stage < Config.STAGE.Ripe and now >= plant.nextStageAt then
                if Registry.heldInVeg(plant) then
                    Registry.extendVeg(plant, now)
                else
                    Registry.advanceStage(plant)
                end
            end
            if plant.stage == Config.STAGE.Flowering then
                flowerChecks(plant)
            end
            if Config.isHydro(plant.bag) and CannabisMod.Hydro and not plant.dead then
                CannabisMod.Hydro.update(plant, now)
            end
            Registry.waterCheck(plant)
        end
    end
end

--- Runs every 10 in-game minutes on the server.
local function onEveryTenMinutes()
    if not plants then return end
    local now = nowHours()

    -- First match our records against vanilla farm plots: add records for new
    -- cannabis plots, mark dead ones, drop replowed ones, copy water.
    if CannabisMod.Farming then
        CannabisMod.Farming.syncWithVanilla()
    end

    -- Plants share this tick's lamp square reads, reservoir checks and pollination list.
    if CannabisMod.Light then CannabisMod.Light.beginTick() end
    if CannabisMod.Hydro then CannabisMod.Hydro.beginTick() end
    tickFemales = false
    -- The shared reads are always cleared afterwards, even if one plant's update fails.
    local ok, err = pcall(tickPlants, now)
    if CannabisMod.Light then CannabisMod.Light.endTick() end
    if CannabisMod.Hydro then CannabisMod.Hydro.endTick() end
    tickFemales = nil
    if not ok then print("[DazedDank] plant tick failed: " .. tostring(err)) end
end
Events.EveryTenMinutes.Add(onEveryTenMinutes)
