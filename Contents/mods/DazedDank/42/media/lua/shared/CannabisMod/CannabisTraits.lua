-- Dazed Dank's occupations and traits: who has which, and the numbers their effects use.
-- The ids are registered in media/registries.lua; everything here reads as "no" when the sandbox switch is off.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local Traits = {}
CannabisMod.Traits = Traits

Traits.TECH_INFO_BOOST = 2        -- levels the Cultivation Tech reads plants above their Agriculture (genetics excluded)
Traits.TECH_ROOTING = 10          -- percent added to a Cultivation Tech's rooting chance
Traits.GREEN_THUMB_ROOTING = 5    -- percent added to a Green Thumb's rooting chance
Traits.GREEN_THUMB_CARE = 0.85    -- care penalties on plants a Green Thumb planted
Traits.BUDTENDER_CURE = 0.15      -- curing bonus on buds a Budtender jars or burps (normally Config.Curing.BONUS)
Traits.BREEDER_EXTRA_SEEDS = 1    -- seeds added to each pollination a Breeder harvests
Traits.BREEDER_NOISE = 5          -- trait variation in a Breeder's cross (normally Strains.Breed.NOISE)
Traits.BREEDER_LUCK = 75          -- percent of big jumps in a Breeder's cross that go the way they want
Traits.TRIM_SPEED = 0.5           -- a Trim Hand's trim time as a share of normal
Traits.LIGHTWEIGHT_STRENGTH = 1.5 -- a Lightweight's high strength and tolerance gain
Traits.CHRONIC_DEP, Traits.CHRONIC_TOL = 45, 30 -- a Chronic's starting dependency and tolerance

--- True when the grower occupations and traits are switched on in sandbox.
function Traits.enabled()
    return Config.sandbox("TraitsAndOccupations") ~= false
end

--- True when the player has one of Dank's traits ("greenthumb", "trimhand", "chronic", "lightweight") or occupations
--- ("cultivationtech", "budtender", "breeder", through the trait each grants).
function Traits.has(player, key)
    if not player or not Traits.enabled() then return false end
    local trait = DazedDankTraits and DazedDankTraits[key]
    if not trait then return false end
    local ok, yes = pcall(player.hasTrait, player, trait)
    return ok and yes == true
end

--- What a player reads beyond their Agriculture level: { boost = levels, genetics = true/false, buds = true/false }.
function Traits.reading(player)
    return {
        boost = Traits.has(player, "cultivationtech") and Traits.TECH_INFO_BOOST or 0,
        genetics = Traits.has(player, "breeder"),
        buds = Traits.has(player, "budtender"),
    }
end

--- Percent added to this player's cutting rooting chance.
function Traits.rootingBonus(player)
    local bonus = 0
    if Traits.has(player, "cultivationtech") then bonus = bonus + Traits.TECH_ROOTING end
    if Traits.has(player, "greenthumb") then bonus = bonus + Traits.GREEN_THUMB_ROOTING end
    return bonus
end

return Traits
