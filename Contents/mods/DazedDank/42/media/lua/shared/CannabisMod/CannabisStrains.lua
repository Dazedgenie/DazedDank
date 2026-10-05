-- Strains: a named bundle of four traits that rides on every seed, plant, bud and
-- joint. Breeding blends the parents' traits, so every cross is a new strain.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config
local T = Config.TYPES

local Strains = {}
CannabisMod.Strains = Strains

-- Traits are 0-100. ind: indica share (100 = pure indica, 0 = pure sativa).
-- pot: potency. yld: bud count. flw: flowering speed (50 = normal time, 100 = fastest).
Strains.TRAITS = { "ind", "pot", "yld", "flw" }

-- The six starters: three indica-leaning, three sativa-leaning. Every seed in the world is one of these until players breed.
-- Indicas finish fast and sativas slow, so crossing and selecting can push flowering time either way.
Strains.STARTERS = {
    { name = "Knox Kush",           ind = 85, pot = 60, yld = 65, flw = 72 },
    { name = "Muldraugh Purple",    ind = 90, pot = 70, yld = 45, flw = 80 },
    { name = "Rosewood Stone",      ind = 75, pot = 50, yld = 80, flw = 64 },
    { name = "Riverside Haze",      ind = 15, pot = 70, yld = 50, flw = 30 },
    { name = "West Point Lightning", ind = 10, pot = 80, yld = 35, flw = 22 },
    { name = "March Ridge Gold",    ind = 25, pot = 55, yld = 70, flw = 42 },
}

-- The server's list of strain names already given out (global ModData). Nil offline, where names are never numbered.
Strains.registry = nil

--- Point naming at the saved list of strain names, and make sure the starters hold their own names.
function Strains.useRegistry(tbl)
    Strains.registry = tbl
    if not tbl then return end
    for _, s in ipairs(Strains.STARTERS) do tbl[s.name] = true end
    tbl.Hybrid = true
end

--- Claim a name for a brand new strain: the name itself if free, else the first free "Name #2", "Name #3"...
function Strains.claimName(name)
    local reg = Strains.registry
    if not reg then return name end
    local out, n = name, 1
    while reg[out] do
        n = n + 1
        out = name .. " #" .. n
    end
    reg[out] = true
    return out
end

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
-- The game's own towns come first, then real Kentucky towns and the state's odder little communities.
local PLACES = { "Knox", "Muldraugh", "Rosewood", "West Point", "Riverside", "March Ridge", "Louisville",
                 "Valley Station", "Ekron", "Brandenburg", "Dixie", "Kentucky", "Fallas Lake", "Irvington",
                 "Bardstown", "Shepherdsville", "Elizabethtown", "Radcliff", "Vine Grove", "Fort Knox", "Frankfort",
                 "Lexington", "Bowling Green", "Paducah", "Owensboro", "Hazard", "Harlan", "Pikeville", "Paintsville",
                 "Corbin", "Somerset", "Berea", "Winchester", "Georgetown", "Versailles", "Lawrenceburg", "Shelbyville",
                 "La Grange", "Taylorsville", "Hodgenville", "Leitchfield", "Hardinsburg", "Cloverport", "Hawesville",
                 "Morehead", "Ashland", "Maysville", "Murray", "Hopkinsville", "Glasgow", "Cave City", "Horse Cave",
                 "Russellville", "Henderson", "Middlesboro", "Prestonsburg", "Whitesburg", "Harrodsburg", "Midway",
                 "Beattyville", "Salyersville", "Vanceburg", "West Liberty", "Irvine", "Hyden", "Cumberland",
                 "Lynch", "Rineyville", "Sonora", "Cecilia", "Bloomfield", "Campbellsville", "Stanford",
                 "Rabbit Hash", "Monkeys Eyebrow", "Possum Trot", "Bugtussle", "Paint Lick", "Big Bone Lick",
                 "Black Gnat", "Kingdom Come", "Quicksand", "Viper", "Hippo", "Dwarf", "Ordinary", "Mousie", "Wild Cat" }
local WORDS = {
    indica = { "Kush", "Purple", "Stone", "Couch", "Dream", "Nightfall", "Blanket", "Lullaby" },
    sativa = { "Haze", "Lightning", "Gold", "Sunrise", "Rush", "Spark", "Jolt", "Daybreak" },
    hybrid = { "Mist", "Fog", "Cross", "Blend", "Twist", "Drift", "Smoke", "Shuffle" },
}
-- The alternate word lists: pieces of real, well-known strains of each lean ("Knox Northern Lights", "Ekron Sour Diesel").
local REAL_WORDS = {
    indica = { "Northern Lights", "Bubba Kush", "Granddaddy Purple", "Hindu Kush", "Afghan", "Purple Kush", "Blueberry",
               "Grape Ape", "Purple Urkle", "Ice Cream Cake", "Do-Si-Dos", "Mendo Breath", "Kosher Kush", "Master Kush" },
    sativa = { "Sour Diesel", "Durban Poison", "Jack Herer", "Green Crack", "Super Lemon Haze", "Strawberry Cough",
               "Maui Wowie", "Tangie", "Super Silver Haze", "Ghost Train Haze", "Acapulco Gold", "Trainwreck",
               "Amnesia Haze", "Panama Red" },
    hybrid = { "Blue Dream", "Girl Scout Cookies", "Gelato", "Wedding Cake", "Gorilla Glue", "White Widow",
               "Pineapple Express", "Zkittlez", "Runtz", "OG Kush", "Chemdawg", "Cherry Pie", "Sherbert", "Skywalker OG" },
}
Strains.WORDS, Strains.REAL_WORDS = WORDS, REAL_WORDS

--- The strain words a lean draws from, by the Strain Words sandbox option: 1 both lists, 2 the original words, 3 real strains.
local function wordsFor(key)
    local style = tonumber(Config.sandbox and Config.sandbox("StrainWords")) or 1
    if style == 2 then return WORDS[key] end
    if style == 3 then return REAL_WORDS[key] end
    local both = {}
    for _, w in ipairs(WORDS[key]) do both[#both + 1] = w end
    for _, w in ipairs(REAL_WORDS[key]) do both[#both + 1] = w end
    return both
end

-- Zombie-style names: some crosses lead with the apocalypse instead of a town, or end on a zombie word.
local ZOMBIE_LEADS = { "Undead", "Shambler", "Walker", "Rotter", "Bloodmoon", "Outbreak", "Quarantine", "Patient Zero",
                       "Day One", "Exclusion Zone", "Knox Event", "Infected", "Horde", "Sprinter", "Crawler",
                       "Deadhead", "Bitten", "Last Stand", "Helicopter", "Safehouse", "Barricade", "Ground Zero" }
local ZOMBIE_TAILS = {
    indica = { "Coma", "Graveyard", "Tombstone", "Dead Sleep", "Corpse Kush", "Rigor" },
    sativa = { "Sprinter", "Fever", "Adrenaline", "Panic", "Siren", "Outbreak Haze" },
    hybrid = { "Plague", "Groan", "Brains", "Bite", "Rot", "Horde Mix" },
}
-- Out of every 10 crosses by trait roll: 6 town + word, 2 zombie lead + word, 2 town + zombie tail.
local ZOMBIE_LEAD_ROLLS, ZOMBIE_TAIL_ROLLS = 2, 2

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
    local key = kind == T.INDICA and "indica" or kind == T.SATIVA and "sativa" or "hybrid"
    local roll = (strain.ind * 3 + strain.pot * 5 + strain.yld * 11 + strain.flw * 29) % 10
    local lead = pick(PLACES, strain, 1)
    if roll < ZOMBIE_LEAD_ROLLS then lead = pick(ZOMBIE_LEADS, strain, 3) end
    -- Two parents that open the same way keep it: "Knox Kush" x "Knox Haze" gives "Knox <word>".
    if parentA and parentB and parentA.name and parentB.name then
        for _, list in ipairs({ PLACES, ZOMBIE_LEADS }) do
            for _, p in ipairs(list) do
                if parentA.name:sub(1, #p + 1) == p .. " " and parentB.name:sub(1, #p + 1) == p .. " " then lead = p; break end
            end
        end
    end
    local tail = pick(wordsFor(key), strain, 2)
    if roll >= 10 - ZOMBIE_TAIL_ROLLS then tail = pick(ZOMBIE_TAILS[key], strain, 4) end
    return lead .. " " .. tail
end

--- True when two parents are the same strain, which breeds true and keeps its name.
local function sameStrain(a, b)
    return a.name == b.name and a.name ~= "Hybrid"
end

--- Breed two strains' traits without naming the result (the other seeds of a batch share the first one's name).
function Strains.crossTraits(a, b)
    a, b = a or Strains.STARTERS[1], b or Strains.STARTERS[1]
    local s = Strains.blend(a, b, true)
    if sameStrain(a, b) then s.name = a.name end
    return s
end

--- Breed two strains. The same strain crossed with itself breeds true; anything else is a new strain with a name of its own.
function Strains.cross(a, b)
    a, b = a or Strains.STARTERS[1], b or Strains.STARTERS[1]
    local s = Strains.crossTraits(a, b)
    if not s.name then s.name = Strains.claimName(Strains.nameFor(s, a, b)) end
    return s
end

-- --------------------------------------------------------------------------
-- What the traits do
-- --------------------------------------------------------------------------

local function span(v, lo, hi) return lo + (hi - lo) * Config.clamp((v or 50) / 100, 0, 1) end

--- Multiplier on the pre-flower and flowering stage lengths: 50 is normal time, 0 the slowest, 100 the fastest.
function Strains.flowerMult(strain)
    local e = Strains.Effect
    local v = Config.clamp((strain and strain.flw or 50), 0, 100)
    if v >= 50 then return 1 + (e.FLOWER_FASTEST - 1) * (v - 50) / 50 end
    return 1 + (e.FLOWER_SLOWEST - 1) * (50 - v) / 50
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

--- A percent change as players read it: "+12%", "-5%", "0%".
local function pct(mult)
    local v = math.floor((mult - 1) * 100 + (mult >= 1 and 0.5 or -0.5))
    return (v > 0 and "+" or "") .. v .. "%"
end

--- Exact summary so growers can select for a trait: "85% indica, potency +4%, yield +6%, flowers 9% faster".
function Strains.describe(strain)
    if not strain then return "" end
    local f = math.floor((1 - Strains.flowerMult(strain)) * 100 + 0.5)
    local flw = f > 0 and (f .. "% faster") or f < 0 and (-f .. "% slower") or "in normal time"
    return string.format("%d%% indica, potency %s, yield %s, flowers %s", strain.ind or 50,
        pct(Strains.potencyMult(strain)), pct(Strains.yieldMult(strain)), flw)
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
