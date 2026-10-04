-- Strains: a named bundle of four traits that rides on every seed, plant, bud and
-- joint. Breeding blends the parents' traits, so every cross is a new strain.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config
local T = Config.TYPES

local Strains = {}
CannabisMod.Strains = Strains

-- Traits are 0-100. ind: indica share (100 = pure indica, 0 = pure sativa).
-- pot: potency. yld: bud count. flw: flowering speed (100 = fastest).
Strains.TRAITS = { "ind", "pot", "yld", "flw" }

-- The six starters: three indica-leaning, three sativa-leaning. Every seed in the world is one of these until players breed.
Strains.STARTERS = {
    { name = "Knox Kush",           ind = 85, pot = 60, yld = 65, flw = 70 },
    { name = "Muldraugh Purple",    ind = 90, pot = 70, yld = 45, flw = 60 },
    { name = "Rosewood Stone",      ind = 75, pot = 50, yld = 80, flw = 65 },
    { name = "Riverside Haze",      ind = 15, pot = 70, yld = 50, flw = 30 },
    { name = "West Point Lightning", ind = 10, pot = 80, yld = 35, flw = 25 },
    { name = "March Ridge Gold",    ind = 25, pot = 55, yld = 70, flw = 40 },
}

-- Above this indica share a strain counts as Indica, below SATIVA_MAX as Sativa, between as Hybrid.
Strains.INDICA_MIN = 65
Strains.SATIVA_MAX = 35

-- Breeding: each trait is the parents' average plus noise, with a rare bigger throw.
Strains.Breed = {
    NOISE = 8,         -- +/- this much on every trait
    THROW_CHANCE = 10, -- % chance a trait throws further
    THROW = 15,
}

-- How much each trait moves the game, as a span around 1.0.
Strains.Effect = {
    FLOWER_SLOWEST = 1.25, FLOWER_FASTEST = 0.80,   -- pre-flower and flowering stage length
    YIELD_LOW = 0.75, YIELD_HIGH = 1.25,            -- bud count
    POTENCY_LOW = 0.80, POTENCY_HIGH = 1.20,        -- high strength
}

-- Name parts for new crosses: a place, then a word that fits the indica share.
local PLACES = { "Knox", "Muldraugh", "Rosewood", "West Point", "Riverside", "March Ridge", "Louisville",
                 "Valley Station", "Ekron", "Brandenburg", "Dixie", "Kentucky", "Fallas Lake", "Irvington" }
local WORDS = {
    indica = { "Kush", "Purple", "Stone", "Couch", "Dream", "Nightfall", "Blanket", "Lullaby" },
    sativa = { "Haze", "Lightning", "Gold", "Sunrise", "Rush", "Spark", "Jolt", "Daybreak" },
    hybrid = { "Mist", "Fog", "Cross", "Blend", "Twist", "Drift", "Smoke", "Shuffle" },
}

local function clamp100(v) return Config.clamp(math.floor(v + 0.5), 0, 100) end

--- Indica / Sativa / Hybrid from a strain's indica share. Nil keeps the old records' own type.
function Strains.typeOf(strain)
    if not strain or not strain.ind then return nil end
    if strain.ind >= Strains.INDICA_MIN then return T.INDICA end
    if strain.ind <= Strains.SATIVA_MAX then return T.SATIVA end
    return T.HYBRID
end

--- A fresh copy of a strain record (strains are shared by value, never by reference).
function Strains.copy(strain)
    if not strain then return nil end
    return { name = strain.name, ind = strain.ind, pot = strain.pot, yld = strain.yld, flw = strain.flw }
end

--- A starter strain picked by a stable number (an item ID, a tile key hash). Same number, same strain.
function Strains.starterFor(n, wantType)
    local list = Strains.STARTERS
    if wantType then
        local filtered = {}
        for _, s in ipairs(list) do
            if Strains.typeOf(s) == wantType then filtered[#filtered + 1] = s end
        end
        if #filtered > 0 then list = filtered end
    end
    return Strains.copy(list[(math.abs(math.floor(n or 0)) % #list) + 1])
end

--- A random starter, optionally of one type; a Hybrid request blends two starters so it isn't a starter name.
function Strains.randomStarter(wantType)
    if wantType == T.HYBRID then
        local a = Strains.starterFor(Config.randInt(0, 2), T.INDICA)
        local b = Strains.starterFor(Config.randInt(0, 2), T.SATIVA)
        return Strains.cross(a, b)
    end
    return Strains.starterFor(Config.randInt(0, 99), wantType)
end

--- The strain for a record that only has a type (old saves, pre-strain items). Deterministic when `n` is given.
function Strains.fromType(plantType, n)
    if plantType == T.HYBRID then
        local a = Strains.starterFor(n or 0, T.INDICA)
        local b = Strains.starterFor(n or 0, T.SATIVA)
        local s = Strains.blend(a, b, false)
        s.name = "Hybrid"
        return s
    end
    return Strains.starterFor(n or 0, plantType)
end

--- The strain a record carries, falling back to one that matches its type so old data keeps working.
function Strains.of(record, n)
    if not record then return nil end
    if record.strain and record.strain.ind then return record.strain end
    return Strains.fromType(record.type or T.HYBRID, n or 0)
end

--- Average two parents' traits, with noise when `noisy`.
function Strains.blend(a, b, noisy)
    local out = {}
    local br = Strains.Breed
    for _, k in ipairs(Strains.TRAITS) do
        local v = ((a[k] or 50) + (b[k] or 50)) / 2
        if noisy then
            v = v + Config.randInt(-br.NOISE, br.NOISE)
            if Config.rollPercent(br.THROW_CHANCE) then
                v = v + (Config.rollPercent(50) and br.THROW or -br.THROW)
            end
        end
        out[k] = clamp100(v)
    end
    return out
end

--- Deterministic index into a list from a strain's traits, so one cross always gets the same name.
local function pick(list, strain, salt)
    local n = (strain.ind * 7 + strain.pot * 13 + strain.yld * 17 + strain.flw * 19 + salt * 23) % #list
    return list[n + 1]
end

--- A name for a new cross: a place and a word for its lean. Parents' names steer the place when they share one.
function Strains.nameFor(strain, parentA, parentB)
    local kind = Strains.typeOf(strain)
    local words = kind == T.INDICA and WORDS.indica or kind == T.SATIVA and WORDS.sativa or WORDS.hybrid
    local place = pick(PLACES, strain, 1)
    -- Two parents from the same place keep it: "Knox Kush" x "Knox Haze" gives "Knox <word>".
    if parentA and parentB and parentA.name and parentB.name then
        for _, p in ipairs(PLACES) do
            if parentA.name:sub(1, #p) == p and parentB.name:sub(1, #p) == p then place = p; break end
        end
    end
    return place .. " " .. pick(words, strain, 2)
end

--- Breed two strains. The same strain crossed with itself breeds true; anything else is a new named cross.
function Strains.cross(a, b)
    a, b = a or Strains.STARTERS[1], b or Strains.STARTERS[1]
    if a.name == b.name and a.name ~= "Hybrid" then
        local s = Strains.blend(a, b, true)
        s.name = a.name
        return s
    end
    local s = Strains.blend(a, b, true)
    s.name = Strains.nameFor(s, a, b)
    return s
end

-- --------------------------------------------------------------------------
-- What the traits do
-- --------------------------------------------------------------------------

local function span(v, lo, hi) return lo + (hi - lo) * Config.clamp((v or 50) / 100, 0, 1) end

--- Multiplier on the pre-flower and flowering stage lengths.
function Strains.flowerMult(strain)
    local e = Strains.Effect
    return span(strain and strain.flw, e.FLOWER_SLOWEST, e.FLOWER_FASTEST)
end

--- Multiplier on buds per plant.
function Strains.yieldMult(strain)
    local e = Strains.Effect
    return span(strain and strain.yld, e.YIELD_LOW, e.YIELD_HIGH)
end

--- Multiplier on how hard a bud hits.
function Strains.potencyMult(strain)
    local e = Strains.Effect
    return span(strain and strain.pot, e.POTENCY_LOW, e.POTENCY_HIGH)
end

--- Per-hour stat changes at full strength: the indica and sativa tables mixed by the indica share.
function Strains.effects(strain)
    local U = Config.Use.EFFECTS
    local w = Config.clamp((strain and strain.ind or 50) / 100, 0, 1)
    local out = {}
    for stat, v in pairs(U.Indica) do out[stat] = v * w end
    for stat, v in pairs(U.Sativa) do out[stat] = (out[stat] or 0) + v * (1 - w) end
    return out
end

--- Sprite tint (r, g, b, 0-1): indica leans violet, sativa leans gold, and each name shifts it a touch.
function Strains.tint(strain)
    if not strain then return 1, 1, 1 end
    local w = Config.clamp((strain.ind or 50) / 100, 0, 1)
    local r = 0.92 + 0.08 * w
    local g = 0.98 - 0.12 * w
    local b = 0.82 + 0.18 * w
    local shift = ((strain.pot or 50) % 20) / 20 * 0.06
    return Config.clamp(r - shift, 0.7, 1), Config.clamp(g + shift / 2, 0.7, 1), Config.clamp(b, 0.7, 1)
end

--- Trait words for the status window and inspect text, by level.
local BANDS = { "Low", "Mid", "High" }
local function band(v) return BANDS[Config.clamp(math.floor((v or 50) / 34) + 1, 1, 3)] end

--- Short readable summary: "85% indica, potency High, yield Mid, flowering fast".
function Strains.describe(strain)
    if not strain then return "" end
    local flw = (strain.flw or 50) >= 67 and "fast" or (strain.flw or 50) <= 33 and "slow" or "normal"
    return string.format("%d%% indica, potency %s, yield %s, flowers %s", strain.ind or 50, band(strain.pot), band(strain.yld), flw)
end

--- A strain record as it came off an item or over the network, checked field by field, or nil.
function Strains.sanitize(data)
    if type(data) ~= "table" or type(data.name) ~= "string" or #data.name > 40 then return nil end
    local out = { name = data.name }
    for _, k in ipairs(Strains.TRAITS) do
        if type(data[k]) ~= "number" then return nil end
        out[k] = clamp100(data[k])
    end
    return out
end
