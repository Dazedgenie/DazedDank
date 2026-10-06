-- Builds the plant info a player may see at their Agriculture level. The
-- server runs it and sends only the result.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisStrains"
require "CannabisMod/CannabisWeather"

local Config = CannabisMod.Config
local Genetics = CannabisMod.Genetics

local Info = {}
CannabisMod.Info = Info

-- --------------------------------------------------------------------------
-- Word bands: turn a 0-100 number into a word
-- --------------------------------------------------------------------------

--- Pick a word for a value. bands = list of { upTo = n, word = "..." },
--- sorted from lowest upTo to highest. The first band the value fits is used.
local function band(value, bands)
    for _, b in ipairs(bands) do
        if value <= b.upTo then return b.word end
    end
    return bands[#bands].word
end

local HEALTH_BANDS  = { { upTo = 40, word = "Poor" }, { upTo = 65, word = "Fair" },
                        { upTo = 85, word = "Good" }, { upTo = 100, word = "Excellent" } }
local STRESS_BANDS  = { { upTo = 20, word = "Low" }, { upTo = 50, word = "Moderate" },
                        { upTo = 75, word = "High" }, { upTo = 100, word = "Severe" } }
local GENETIC_BANDS = { { upTo = 60, word = "Degraded" }, { upTo = 85, word = "Drifting" },
                        { upTo = 100, word = "Strong" } }
local QUALITY_BANDS = { { upTo = 40, word = "Poor" }, { upTo = 65, word = "Fair" }, { upTo = 85, word = "Good" },
                        { upTo = 100, word = "Excellent" }, { upTo = 1000, word = "Top Shelf" } }

-- Rough stage names for low-skill players.
local ROUGH_STAGE = {
    Seedling   = "Young",
    Vegetative = "Growing",
    PreFlower  = "Growing",
    Flowering  = "Flowering",
    Ripe       = "Ready",
}

-- --------------------------------------------------------------------------
-- Field builders
-- --------------------------------------------------------------------------
-- Each one takes (plant, nowHours) and returns the value to display. Plant
-- fields used here are set by the server registry (see
-- server/CannabisMod/CannabisRegistry.lua for the full list).

local builders = {}

builders.name = function(plant)
    return "Cannabis Plant"
end

builders.stageRough = function(plant)
    return ROUGH_STAGE[Config.STAGES[plant.stage]] or "Unknown"
end

builders.waterRough = function(plant)
    local w = plant.water or 0
    if w < Config.Water.LOW then return "Dry" end
    if w > Config.Water.HIGH then return "Wet" end
    return "OK"
end

-- A cutting stuck in soil that hasn't rooted yet. Anyone can see that.
builders.rooting = function(plant)
    if plant.rooting then return "Still rooting" end
    return nil
end

builders.container = function(plant)
    local def = plant.bag and Config.GrowBag[plant.bag]
    return def and def.name or "Ground"
end

builders.stage = function(plant)
    return Config.STAGES[plant.stage]
end

builders.hoursLeft = function(plant, now)
    if not plant.nextStageAt then return nil end
    return math.max(0, math.floor(plant.nextStageAt - now))
end

builders.water = function(plant)
    return math.floor(plant.water or 0)
end

builders.lastNutrient = function(plant)
    return plant.lastNutrient or "None"
end

builders.type = function(plant)
    return plant.type
end

-- Topping is plain to see on the plant.
builders.topped = function(plant)
    return plant.topped == true or nil
end

-- Cuttings she can give before being set back, while cuttings can be taken at all.
builders.cuttings = function(plant, now)
    if not Genetics.canClone(plant) then return nil end
    return { left = math.floor(Genetics.cutsAvailable(plant, now)), max = Genetics.cutBudgetMax(plant) }
end

-- The strain's name, shown with the type.
builders.strain = function(plant)
    local s = CannabisMod.Strains.of(plant)
    if not s then return nil end
    local Weather = CannabisMod.Weather
    return (Weather and Weather.purplePrefix(plant) or "") .. s.name
end

-- How the strain looks: its body shape, and its bud colour when that isn't plain green.
builders.looks = function(plant)
    local Strains = CannabisMod.Strains
    local s = Strains.of(plant)
    if not s then return nil end
    local shape, colour = Strains.shapeOf(s), Strains.colourOf(s)
    local out = Strains.SHAPE_NAMES[shape] or shape
    if colour ~= "green" then out = out .. ", " .. (Strains.COLOUR_NAMES[colour] or colour) end
    return out
end

-- The strain's traits in words, for growers who can read genetics.
builders.traits = function(plant)
    local s = CannabisMod.Strains.of(plant)
    return s and CannabisMod.Strains.describe(s) or nil
end

-- Sex is shown whenever the player's level unlocks it (Agriculture 3, same as
-- reading a seed). Hermaphrodites show as such once they've turned.
builders.sex = function(plant)
    return plant.isHermie and "Hermaphrodite" or plant.sex
end

builders.light = function(plant)
    return plant.lightSource or "Sun"
end

local CYCLE_WORDS = { sun = "Sunlight", long = "Veg light (18/6 or 24/0)", short = "Flower light (12/12)", leak = "Light leak" }

builders.lightCycle = function(plant)
    return plant.lightCycle and CYCLE_WORDS[plant.lightCycle] or nil
end

-- True while a plant has finished its minimum veg but its lamps keep it in veg.
builders.vegHeld = function(plant)
    return plant.vegHeld == true and plant.stage == Config.STAGE.Vegetative or nil
end

-- Extra veg time so far and the yield bonus it gives.
builders.extraVeg = function(plant)
    local hours = plant.extraVegHours or 0
    if hours <= 0 then return nil end
    local bonus = plant.vegBonus or Config.Timer.vegBonus(hours)
    return { hours = math.floor(hours), bonus = math.floor(bonus * 100 + 0.5) }
end

-- A hydro plant's reservoir: litres, capacity, nutrient and its strength.
builders.reservoir = function(plant)
    local h = plant.hydro
    if not h then return nil end
    return { level = math.floor(h.level * 10 + 0.5) / 10, cap = h.cap, nutrient = h.nutrient,
             strength = math.floor((h.strength or 0) * 100 + 0.5), stale = h.stale == true,
             sites = h.sites, unlinked = h.unlinked == true, ebb = h.ebb == true,
             wetHours = h.wetHours and math.floor(h.wetHours * 10 + 0.5) / 10 or nil, floodTimer = h.floodTimer == true }
end

-- How the roots of a hydro plant look.
builders.roots = function(plant)
    if not plant.hydro then return nil end
    local rot = plant.rootRot or 0
    if rot >= Config.Hydro.ROT_EARLY then return "Rotting" end
    if rot > 0 then return "Browning" end
    return "Healthy"
end

-- Root rot level, 0-100 (early rot below ROT_EARLY can still be treated).
builders.rootRot = function(plant)
    if not plant.hydro then return nil end
    return math.floor((plant.rootRot or 0) + 0.5)
end

-- Which way root rot is heading: 1 rising, -1 falling, 0 steady.
builders.rootRotTrend = function(plant)
    if not plant.hydro then return nil end
    return plant.rootRotTrend or 0
end

builders.healthBand = function(plant)
    return band(plant.care or 100, HEALTH_BANDS)
end

builders.stressBand = function(plant)
    return band(plant.stress or 0, STRESS_BANDS)
end

builders.warnings = function(plant)
    -- plant.warnings is a set like { nutrientBurn = true, overwatered = true
    -- }
    local list = {}
    for name, active in pairs(plant.warnings or {}) do
        if active then list[#list + 1] = name end
    end
    table.sort(list)  -- stable order so the window doesn't shuffle
    return list
end

builders.harvestWindow = function(plant, now)
    if plant.stage < Config.STAGE.Ripe then return "Not ripe" end
    if plant.nextStageAt and now > plant.nextStageAt then return "Overripe" end
    return "Ready now"
end

builders.pollinated = function(plant)
    return plant.seeded == true
end

-- An expert spots a hermie early, before it's obvious to everyone.
builders.hermieSigns = function(plant)
    return plant.isHermie == true
end

builders.generation = function(plant)
    return plant.generation or 0
end

builders.geneticsBand = function(plant)
    return band(plant.genetics or 100, GENETIC_BANDS)
end

builders.qualityEstimate = function(plant)
    -- Estimate assumes a perfect harvest time and a full dry.
    return band(Genetics.calcQuality(plant, 0, nil), QUALITY_BANDS)
end

-- --------------------------------------------------------------------------
-- Public function
-- --------------------------------------------------------------------------

--- Build the table of info a player at `level` may see.
--- @param plant full plant record (server side)
--- @param level player's Agriculture level
--- @param nowHours current game time in hours
--- @return table of field -> value, plus `level` so the UI knows the tier
function Info.buildVisible(plant, level, nowHours)
    local out = { level = level }
    for _, tier in ipairs(Config.InfoTiers) do
        if level >= tier.level then
            for _, field in ipairs(tier.fields) do
                local build = builders[field]
                if build then
                    out[field] = build(plant, nowHours or 0)
                end
            end
        end
    end
    return out
end

--- What a player sees when inspecting a SEED item (not a planted plant).
--- Below Agriculture 3 the type and sex are hidden.
function Info.seedLabel(seedData, level)
    if level < Config.SEED_INSPECT_LEVEL or not seedData then
        return "Unknown cannabis seed"
    end
    local strain = seedData.strain and seedData.strain.name
    local label = (strain and (strain .. " (" .. seedData.type .. ")") or seedData.type) .. " seed (" .. seedData.sex .. ")"
    if level >= 9 and seedData.strain then label = label .. ": " .. CannabisMod.Strains.describe(seedData.strain) end
    return label
end
