-- Optional hooks for the standalone DazedOccupations mod: who has which trait, and the numbers their effects use.
-- Dank registers no occupations or traits of its own. Without DazedOccupations every check below is false and every
-- player plays as a no-trait player. DazedOccupations announces nothing here: Dank announces which effects it has.

require "CannabisMod/CannabisConfig"

local Traits = {}
CannabisMod.Traits = Traits

Traits.TECH_INFO_BOOST = 2        -- levels the Cultivation Tech reads plants above their Agriculture (genetics excluded)
Traits.TECH_ROOTING = 10          -- percent added to a Cultivation Tech's rooting chance
Traits.GREEN_THUMB_ROOTING = 5    -- percent added to a Green Thumb's rooting chance
Traits.GREEN_THUMB_CARE = 0.85    -- care penalties on plants a Green Thumb planted
Traits.BUDTENDER_CURE = 0.15      -- curing bonus on buds a Budtender jars or burps (normally Config.Curing.BONUS)
Traits.READ_BUDS = true           -- Inspect Bud shows everything at any Agriculture level
Traits.BREEDER_EXTRA_SEEDS = 1    -- seeds added to each pollination a Breeder harvests
Traits.BREEDER_NOISE = 5          -- trait variation in a Breeder's cross (normally Strains.Breed.NOISE)
Traits.BREEDER_LUCK = 75          -- percent of big jumps in a Breeder's cross that go the way they want
Traits.READ_GENETICS = true       -- strain traits and hermie lines read at any Agriculture level
Traits.TRIM_SPEED = 0.5           -- a Trim Hand's trim time as a share of normal
Traits.TRIM_CONFIRM = true        -- a Trim Hand is asked before trimming a plant that is still too wet
Traits.LIGHTWEIGHT_STRENGTH = 1.5 -- a Lightweight's high strength and tolerance gain
Traits.CHRONIC_DEP, Traits.CHRONIC_TOL = 45, 30 -- a Chronic's starting dependency and tolerance

--- True when the player has one of Dank's traits ("greenthumb", "trimhand", "chronic", "lightweight") or occupations
--- ("cultivationtech", "budtender", "breeder", through the trait each grants). Always false without DazedOccupations.
function Traits.has(player, key)
    if not player then return false end
    return DazedOccupations ~= nil and type(DazedOccupations.has) == "function" and DazedOccupations.has(player, key) == true
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

-- Every call site for these seven effects is wired through Traits.has above, so each one is announced.
DazedOccupationsHooks = DazedOccupationsHooks or {}
DazedOccupationsHooks["dank.cultivationtech"] = true
DazedOccupationsHooks["dank.budtender"] = true
DazedOccupationsHooks["dank.breeder"] = true
DazedOccupationsHooks["dank.greenthumb"] = true
DazedOccupationsHooks["dank.trimhand"] = true
DazedOccupationsHooks["dank.chronic"] = true
DazedOccupationsHooks["dank.lightweight"] = true

return Traits
