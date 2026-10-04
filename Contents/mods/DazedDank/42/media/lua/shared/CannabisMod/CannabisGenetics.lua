-- Pure functions for the mod's biology rules: genetics drift, sex, quality and
-- rooting odds.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisStrains"

local Config = CannabisMod.Config
local Strains = CannabisMod.Strains
local T = Config.TYPES
local SEX = Config.SEX

local Genetics = {}
CannabisMod.Genetics = Genetics

-- ==========================================================================
-- Seeds
-- ==========================================================================

--- Roll the sex of a brand new seed. Male chance comes from the sandbox
--- option MaleSeedChance (default 10%).
function Genetics.rollSex()
    if Config.rollPercent(Config.sandbox("MaleSeedChance")) then
        return SEX.MALE
    end
    return SEX.FEMALE
end

--- Create the data for a new seed. This table is what gets stored in the seed
--- item's modData, and later copied into the plant record when the seed is
--- planted.
--- @param plantType one of Config.TYPES, or a strain record (its type is worked out from it)
--- @param opts optional { hermieLineage = true } for seeds from a hermie, { strain = record } to set the strain
function Genetics.newSeed(plantType, opts)
    opts = opts or {}
    local genetics = Config.Genetics.START
    -- A hermie anywhere in the line is permanent damage, so its seeds are
    -- born with the penalty already applied.
    if opts.hermieLineage then
        genetics = genetics - Config.Genetics.HERMIE_PENALTY
    end
    -- A strain passed in place of a type, or asked for by type, so every seed has one.
    local strain = opts.strain
    if type(plantType) == "table" then strain, plantType = plantType, nil end
    strain = Strains.copy(strain) or Strains.randomStarter(plantType)
    return {
        type          = Strains.typeOf(strain) or plantType,
        strain        = strain,
        sex           = Genetics.rollSex(),
        genetics      = genetics,
        generation    = 0,  -- 0 = grown from seed, 1+ = clone generations
        hermieLineage = opts.hermieLineage == true,
    }
end

-- ==========================================================================
-- Breeding
-- ==========================================================================

--- Decide the type of one seed from two parent types (order doesn't matter).
function Genetics.breedType(typeA, typeB)
    -- Same type always breeds true... except Hybrid x Hybrid, handled below.
    if typeA == typeB and typeA ~= T.HYBRID then
        return typeA
    end

    -- One Indica + one Sativa (in either order).
    if (typeA == T.INDICA and typeB == T.SATIVA)
    or (typeA == T.SATIVA and typeB == T.INDICA) then
        return T.HYBRID
    end

    -- Hybrid x Hybrid: spread across all three.
    if typeA == T.HYBRID and typeB == T.HYBRID then
        local odds = Config.Breeding.HYBRID_X_HYBRID
        local roll = Config.randInt(1, 100)
        if roll <= odds.indica then return T.INDICA end
        if roll <= odds.indica + odds.sativa then return T.SATIVA end
        return T.HYBRID
    end

    -- Only case left: one Hybrid and one pure type.
    local pure = (typeA == T.HYBRID) and typeB or typeA
    if Config.rollPercent(Config.Breeding.HYBRID_X_PURE.pure) then
        return pure
    end
    return T.HYBRID
end

--- Make the full set of seeds a pollinated female drops at harvest.
--- @param mother the female plant record
--- @param father the male (or hermie) plant record that pollinated her
--- @return list of seed tables
function Genetics.seedsFromPollination(mother, father)
    local range = Config.SEEDS_PER_POLLINATED_PLANT
    local count = Config.randInt(range.min, range.max)
    count = math.max(1, math.floor(count * Config.sandbox("HarvestQuantity") + 0.5))

    -- If EITHER parent carries a hermie line, the seeds do too.
    local hermie = (mother.hermieLineage == true) or (father.hermieLineage == true)

    -- One cross per pollination: every seed in the batch is the same new strain, with its own trait roll.
    local ma, fa = Strains.of(mother), Strains.of(father)
    local seeds = {}
    for i = 1, count do
        seeds[i] = Genetics.newSeed(Strains.cross(ma, fa), { hermieLineage = hermie })
        if i > 1 then seeds[i].strain.name = seeds[1].strain.name end
    end
    return seeds
end

-- ==========================================================================
-- Cloning
-- ==========================================================================

--- Can this plant have a cutting taken right now?
function Genetics.canClone(plant)
    local stageName = Config.STAGES[plant.stage]
    return Config.CLONEABLE_STAGES[stageName] == true
end

--- The most cuttings a plant's pot holds at once.
function Genetics.cutBudgetMax(plant)
    local b = Config.Cuttings.BUDGET
    return b[plant.bag or "ground"] or b.ground
end

--- Cuttings a plant can give right now: its stored budget, refilled for the time since it was last spent.
function Genetics.cutsAvailable(plant, now)
    local max = Genetics.cutBudgetMax(plant)
    if plant.cutBudget == nil then return max end
    local speed = math.max(0.1, math.min(10, Config.sandbox("GrowthSpeed") or 1))
    local perHour = max / (Config.Cuttings.REFILL_DAYS * 24) * speed
    return math.min(max, plant.cutBudget + math.max(0, now - (plant.cutBudgetAt or now)) * perHour)
end

--- Spend one cutting. True if it was within budget, false if it overcut the plant.
function Genetics.spendCut(plant, now)
    local avail = Genetics.cutsAvailable(plant, now)
    plant.cutBudgetAt = now
    if avail >= 1 then
        plant.cutBudget = avail - 1
        return true
    end
    plant.cutBudget = avail  -- an overcut doesn't drain it further; it keeps refilling from here
    return false
end

--- Build the genetics for a new cutting: it copies the mother, then drifts (less from a mother in an XL pot).
function Genetics.cloneFrom(mother)
    local g = Config.Genetics
    local m = Config.isMotherPot(mother.bag) and Config.Mother or g
    local drift = Config.randInt(m.DRIFT_MIN, m.DRIFT_MAX)
    return {
        type          = mother.type,
        strain        = Strains.copy(Strains.of(mother)),
        sex           = mother.sex,  -- a clone of a female is always female
        genetics      = math.max(g.FLOOR, mother.genetics - drift),
        generation    = (mother.generation or 0) + 1,
        hermieLineage = mother.hermieLineage == true,
        stress        = math.floor((mother.stress or 0) * Config.Stress.CLONE_INHERIT),
    }
end

--- Work out a cutting's rooting chance and rooting time.
--- @param level player's Agriculture level (0-10)
--- @param opts { gel, dome, tempC, hasLight, moist, wiltHours, soil }
--- @return chance (percent), hours (time until the roll)
function Genetics.rootingOdds(level, opts)
    local r = Config.Rooting
    opts = opts or {}

    local chance = r.BASE + (level or 0) * r.PER_LEVEL
    local hours = r.HOURS

    if opts.gel  then chance = chance + r.GEL_BONUS end
    if opts.dome then chance = chance + r.DOME_BONUS end
    if opts.soil then chance = chance + r.SOIL_PENALTY end

    -- Wilting: free for a few hours, then the chance drops per hour.
    local wilt = (opts.wiltHours or 0) - r.WILT_GRACE_HOURS
    if wilt > 0 then
        chance = chance - wilt * r.WILT_PER_HOUR
    end

    -- Temperature: only penalize if we actually know the temperature.
    if opts.tempC ~= nil
    and (opts.tempC < r.TEMP_IDEAL_MIN or opts.tempC > r.TEMP_IDEAL_MAX) then
        chance = chance + r.TEMP_PENALTY
        hours = hours * r.TEMP_SLOW
    end

    if opts.hasLight == false then
        chance = chance + r.NO_LIGHT_PENALTY
        hours = hours * r.NO_LIGHT_SLOW
    end

    -- A dome always keeps cuttings moist, so only bare cuttings can dry out.
    local moist = opts.dome or opts.moist
    if not moist then
        chance = chance + r.DRY_PENALTY
        hours = hours * r.DRY_SLOW
    end

    return Config.clamp(chance, r.MIN, r.MAX), hours
end

--- Roll whether a cutting roots. Server only.
function Genetics.rollRooting(level, opts)
    local chance = Genetics.rootingOdds(level, opts)
    return Config.rollPercent(chance)
end

-- ==========================================================================
-- Hermaphrodites
-- ==========================================================================

--- Percent chance a flowering female turns hermie on one check. 0 below the
--- stress threshold, then rises in a straight line to the max at 100 stress.
function Genetics.hermieChance(stress)
    local s = Config.Stress
    stress = stress or 0
    if stress < s.HERMIE_THRESHOLD then
        return 0
    end
    local over = (stress - s.HERMIE_THRESHOLD) / (s.MAX - s.HERMIE_THRESHOLD)
    return over * s.HERMIE_CHANCE_MAX
end

--- Turn a plant into a hermie: marks it and applies the lineage penalty.
--- Modifies the plant record in place.
function Genetics.makeHermie(plant)
    if plant.isHermie then return end  -- already done, don't stack penalties
    plant.isHermie = true
    if not plant.hermieLineage then
        plant.hermieLineage = true
        plant.genetics = math.max(Config.Genetics.FLOOR,
            plant.genetics - Config.Genetics.HERMIE_PENALTY)
    end
end

-- ==========================================================================
-- Quality
-- ==========================================================================

--- How harvest timing affects quality, from 0.5 to 1.0.
--- @param hoursOutside hours before or after the ripe window (0 = inside)
function Genetics.harvestMultiplier(hoursOutside)
    local q = Config.Quality
    local mult = 1.0 - (math.abs(hoursOutside or 0) * q.HARVEST_FALLOFF / 100)
    return Config.clamp(mult, q.HARVEST_MIN_MULT, 1.0)
end

--- How drying time affects quality, from 0.6 (0 hours) to 1.0 (full dry).
function Genetics.dryMultiplier(hoursDried)
    local q = Config.Quality
    local fraction = Config.clamp((hoursDried or 0) / Config.dryHours(), 0, 1)
    return q.RUSHED_DRY_MIN_MULT + (1 - q.RUSHED_DRY_MIN_MULT) * fraction
end

--- Drying past the ideal window slowly dries the buds out (0.7 to 1.0).
function Genetics.overDryMultiplier(hoursDried)
    local d = Config.Drying
    local over = math.max(0, (hoursDried or 0) - d.OVERDRY_AFTER)
    return Config.clamp(1 - over * d.OVERDRY_PER_HOUR, d.OVERDRY_MIN, 1.0)
end

--- Quality of the buds after trimming. `base` is the harvest quality (which
--- assumed a perfect dry); rec = { hours, moldy, sunLoss }.
function Genetics.driedQuality(base, rec)
    local q = (base or 0) * Genetics.dryMultiplier(rec.hours) * Genetics.overDryMultiplier(rec.hours)
    q = q * (1 - (rec.sunLoss or 0))
    if rec.moldy then q = q * Config.Drying.MOLDY_MULT end
    return math.floor(Config.clamp(q, 0, math.max(100, base or 0)) + 0.5)
end

--- Quality after curing: up to +10% over FULL_DAYS in a jar. Mold ruins it.
function Genetics.curedQuality(quality, cureHours, moldy, moldBaked)
    local c = Config.Curing
    local q = (quality or 0) * (1 + c.BONUS * Config.clamp((cureHours or 0) / (Config.cureDays() * 24), 0, 1))
    if moldy and not moldBaked then q = q * Config.Drying.MOLDY_MULT end
    -- Curing can't lift ordinary buds past 100; Top Shelf buds cure up to the RDWC ceiling.
    return math.floor(Config.clamp(q, 0, Config.maxQuality((quality or 0) > 100)) + 0.5)
end

--- The final quality formula from the design doc: Quality = min(LightCap,
--- Genetics) x Care/100 x M_harvest x M_seeded x M_dry
--- @param plant plant record with lightCap, genetics, care, seeded
--- @param hoursOutsideWindow harvest timing (0 = perfect)
--- @param hoursDried nil if not dried yet (treated as a full dry so the
--- status window can show an estimate)
--- @return quality 0-100, rounded
function Genetics.calcQuality(plant, hoursOutsideWindow, hoursDried)
    local cap = math.min(plant.lightCap or Config.LightCap.SUN, plant.genetics or 0)
    -- RDWC's steady root zone lifts the ceiling above 100 (Top Shelf).
    local def = plant.bag and Config.GrowBag[plant.bag]
    local topShelf = def ~= nil and def.topShelf == true
    if topShelf then cap = cap * (1 + math.max(0, Config.sandbox("HydroQualityBonus") or 0)) end
    local care = Config.clamp(plant.care or Config.Care.START, 0, 100) / 100
    local seeded = plant.seeded and Config.Quality.SEEDED_MULT or 1.0
    local dry = Genetics.dryMultiplier(hoursDried or Config.dryHours())
    local q = cap * care * Genetics.harvestMultiplier(hoursOutsideWindow) * seeded * dry
    return math.floor(Config.clamp(q, 0, Config.maxQuality(topShelf)) + 0.5)
end
