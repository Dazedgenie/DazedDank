-- Every tunable number in the mod lives here: growth times, caps, penalties,
-- sprite layout and info unlock levels.

-- Global namespace for the whole mod. Every file adds its own table onto this
-- one (CannabisMod.Genetics, CannabisMod.Registry, ...).
CannabisMod = CannabisMod or {}

local Config = {}
CannabisMod.Config = Config

-- --------------------------------------------------------------------------
-- Identity
-- --------------------------------------------------------------------------

-- The "module" name used when the client and server send each other commands
-- (sendClientCommand / sendServerCommand). Both sides check this string so
-- they ignore commands from other mods.
Config.COMMAND_MODULE = "CannabisMod"

-- Key for the server's global ModData table that stores every plant.
Config.MODDATA_KEY = "CannabisMod_Plants"

-- --------------------------------------------------------------------------
-- Strain types and sexes
-- --------------------------------------------------------------------------
-- Plain strings are used (not numbers) because they are readable in the save
-- file and in debug prints.

Config.TYPES = {
    INDICA = "Indica",
    SATIVA = "Sativa",
    HYBRID = "Hybrid",
}

Config.SEX = {
    MALE   = "Male",
    FEMALE = "Female",
}

-- --------------------------------------------------------------------------
-- Growth stages
-- --------------------------------------------------------------------------
-- Ordered list: index 1 is the first stage. Code moves a plant forward by
-- adding 1 to its stage index.

Config.STAGES = {
    "Seedling",  -- 1
    "Vegetative",  -- 2
    "PreFlower",  -- 3 sex becomes visible here
    "Flowering",  -- 4
    "Ripe",  -- 5 harvest window
}

-- Reverse lookup so we can write Config.STAGE.Flowering instead of 4.
Config.STAGE = {}
for index, name in ipairs(Config.STAGES) do
    Config.STAGE[name] = index
end

-- Each stage lasts a random number of in-game hours between min and max. 24
-- to 48 hours = the "1 to 2 days per stage" we agreed on.
Config.STAGE_HOURS = {
    Seedling   = { min = 24, max = 48 },
    Vegetative = { min = 24, max = 48 },
    PreFlower  = { min = 24, max = 48 },
    Flowering  = { min = 24, max = 48 },
    Ripe       = { min = 24, max = 36 },  -- the harvest window itself
}

-- Stages where a cutting can be taken.
Config.CLONEABLE_STAGES = {
    Vegetative = true,
    PreFlower  = true,
}

-- --------------------------------------------------------------------------
-- Vanilla farming link
-- --------------------------------------------------------------------------

-- The crop name vanilla farming knows us by (farming_vegetableconf.props
-- key). Vanilla also uses it for the translation key "Farming_Cannabis".
Config.CROP_TYPE = "Cannabis"

-- Items. All three plantable ones are listed as "seeds" for vanilla's Sow
-- Seed menu (see CannabisCrop.lua).
Config.SEED_ITEM   = "CannabisMod.CannabisSeed"
Config.CUTTING_ITEM = "CannabisMod.CannabisCutting"  -- fresh, unrooted
Config.ROOTED_ITEM  = "CannabisMod.RootedCannabisCutting"
-- The dome is a container item (placeable on a table).
Config.DOME_ITEM    = "CannabisMod.CloningDomeTray"

-- Harvested whole plants, one item per plant type.
Config.WET_PLANT_ITEMS = {
    Indica = "CannabisMod.WetIndicaPlant",
    Sativa = "CannabisMod.WetSativaPlant",
    Hybrid = "CannabisMod.WetHybridPlant",
}
function Config.isWetPlant(fullType)
    for _, t in pairs(Config.WET_PLANT_ITEMS) do
        if t == fullType then return true end
    end
    return false
end
-- What a wet plant turns into once it has dried on a rack.
Config.DRIED_PLANT_ITEMS = {
    Indica = "CannabisMod.DriedIndicaPlant",
    Sativa = "CannabisMod.DriedSativaPlant",
    Hybrid = "CannabisMod.DriedHybridPlant",
}
function Config.isDriedPlant(fullType)
    for _, t in pairs(Config.DRIED_PLANT_ITEMS) do
        if t == fullType then return true end
    end
    return false
end
--- Wet or dried whole plant: what racks hold and what can be trimmed.
function Config.isHangingPlant(fullType)
    return Config.isWetPlant(fullType) or Config.isDriedPlant(fullType)
end
Config.GEL_ITEM     = "CannabisMod.RootingGel"

-- Nutrient bottles, by the name Registry.feed expects.
Config.NUTRIENT_ITEMS = {
    Veg   = "CannabisMod.VegNutrients",
    Bloom = "CannabisMod.BloomNutrients",
}

-- Tools that can take a cutting: anything vanilla lets you cut plants with,
-- plus scissors and sharp knives. These are vanilla ItemTag names.
Config.CUTTING_TOOL_TAGS = { "CUT_PLANT", "SCISSORS", "SHARP_KNIFE" }

-- Vanilla tracks a plant's growth as a number, nbOfGrow. We set it from our
-- stage so vanilla's own checks (like "is it big enough to harvest") still
-- make sense.
Config.STAGE_TO_NBOFGROW = {
    Seedling   = 1,
    Vegetative = 3,
    PreFlower  = 5,
    Flowering  = 6,
    Ripe       = 7,
}

-- --------------------------------------------------------------------------
-- Plant sprites
-- --------------------------------------------------------------------------
-- Our tile sheet is drawn by tools/draw_placeholders.py: blocks of 13 sprites
-- per condition, then bag variants, empty bags, lamps and unfilled bags.

Config.SPRITE_SHEET = "dazeddank_plants_01"

-- Vanilla's names for plant conditions -> our block number.
Config.SPRITE_CONDITION = {
    sprite          = 0,
    unhealthySprite = 1,
    dyingSprite     = 2,
    deadSprite      = 3,
    trampledSprite  = 4,
}

local SPRITE_TYPE_OFFSET = { Indica = 1, Sativa = 5, Hybrid = 9 }

-- --------------------------------------------------------------------------
-- Grow bags
-- --------------------------------------------------------------------------
-- Optional fabric pots. A bag is a placeable plot that works indoors and out.
Config.GrowBag = {
    small = { name = "Small Grow Bag",
              drain = 0.6, yield = 1.0,  spriteBlock = 1, emptySprite = 195,
              drySprite = 201, soil = 1, plantBase = 65, maleBase = 282,
              furnItem = "CannabisMod.GrowBagSmallPlaceable", furnSprite = 203 },
    large = { name = "Large Grow Bag",
              drain = 0.5, yield = 1.25, spriteBlock = 2, emptySprite = 196,
              drySprite = 202, soil = 2, plantBase = 130, maleBase = 327,
              furnItem = "CannabisMod.GrowBagLargePlaceable", furnSprite = 204 },
    -- Deep water culture bucket: a hydro container. It needs a medium (rockwool or clay pebbles) instead of soil.
    dwc   = { name = "DWC Bucket", hydro = "dwc",
              drain = 1, yield = 1.3, careMult = 0.75, emptySprite = 374,
              drySprite = 373, soil = 0, plantBase = 375, maleBase = 440, lastSprite = 484,
              furnItem = "CannabisMod.DWCBucket", furnSprite = 372 },
}
-- Ground plants: the first 65 sprites, and males from MALE_SPRITE_BASE.
Config.GROUND_SPRITES = { plantBase = 0, maleBase = 237 }

-- Items that count as a sack of soil (our own, plus vanilla's bag of dirt if
-- this build has it; an unknown type simply never matches).
Config.SOIL_ITEMS = { "CannabisMod.SoilSack", "Base.Dirtbag" }
function Config.isSoilItem(fullType)
    for _, t in ipairs(Config.SOIL_ITEMS) do
        if t == fullType then return true end
    end
    return false
end

--- Which bag size a furniture sprite (the one placed from a bag item) is, or nil.
function Config.bagFromFurnSprite(spriteName)
    for size, def in pairs(Config.GrowBag) do
        if spriteName == Config.SPRITE_SHEET .. "_" .. def.furnSprite then return size end
    end
    return nil
end

-- Male plants from pre-flower on have their own sprites: per container, 5 conditions x 3 types x 3 stages.
Config.MALE_SPRITE_BASE = 237
local MALE_TYPE_INDEX = { Indica = 0, Sativa = 1, Hybrid = 2 }

--- The sprite ranges of a container kind (nil or unknown means the ground).
local function spriteBases(bag)
    return (bag and Config.GrowBag[bag]) or Config.GROUND_SPRITES
end

--- Sprite name for a plant type, stage index (1-5) and vanilla condition.
--- `bag` is nil for ground, or a Config.GrowBag key; `male` picks the male sprites once the sex shows.
function Config.spriteName(plantType, stage, condition, bag, male)
    local bases = spriteBases(bag)
    local cond = Config.SPRITE_CONDITION[condition] or 0
    if male and stage and stage >= 3 then
        local t = MALE_TYPE_INDEX[plantType] or MALE_TYPE_INDEX.Hybrid
        return Config.SPRITE_SHEET .. "_" .. tostring(bases.maleBase + cond * 9 + t * 3 + (math.min(stage, 5) - 3))
    end
    local slot = 0  -- seedling
    if stage and stage > 1 then
        local offset = SPRITE_TYPE_OFFSET[plantType] or SPRITE_TYPE_OFFSET.Hybrid
        slot = offset + math.min(stage, 5) - 2
    end
    return Config.SPRITE_SHEET .. "_" .. tostring(bases.plantBase + cond * 13 + slot)
end

--- Sprite of an empty bag. `soiled` false/nil = the new, unfilled bag.
function Config.bagEmptySprite(bag, soiled)
    local def = Config.GrowBag[bag]
    if not def then return nil end
    return Config.SPRITE_SHEET .. "_" .. (soiled and def.emptySprite or def.drySprite)
end

--- True if this sprite is an unfilled (no soil yet) bag.
function Config.bagIsUnfilled(spriteName)
    if type(spriteName) ~= "string" then return false end
    local n = tonumber(spriteName:match("^" .. Config.SPRITE_SHEET .. "_(%d+)$"))
    for _, def in pairs(Config.GrowBag) do
        if n == def.drySprite then return true end
    end
    return false
end

--- Which container kind a sprite name shows, or nil for ground / other sprites.
--- Clients use this to tell a bag or bucket plot from a plowed one (the registry lives on the server).
function Config.bagFromSprite(spriteName)
    if type(spriteName) ~= "string" then return nil end
    local n = tonumber(spriteName:match("^" .. Config.SPRITE_SHEET .. "_(%d+)$"))
    if not n then return nil end
    for kind, def in pairs(Config.GrowBag) do
        if n == def.emptySprite or n == def.drySprite then return kind end
        if n >= def.plantBase and n < def.plantBase + 65 then return kind end
        if n >= def.maleBase and n < def.maleBase + 45 then return kind end
    end
    return nil
end

--- True if a container kind is a hydro system rather than a soil pot.
function Config.isHydro(bag)
    return bag ~= nil and Config.GrowBag[bag] ~= nil and Config.GrowBag[bag].hydro ~= nil
end

-- Water level (0-100, vanilla's scale) outside this range hurts the plant.
Config.Water = {
    LOW  = 30,  -- below this: underwatered
    HIGH = 90,  -- above this: overwatered / root stress
}

-- Buds a healthy female gives at trimming, before quality and the
-- HarvestQuantity sandbox option. Stored on the harvested plant item.
Config.BUD_YIELD = { min = 4, max = 8 }

-- --------------------------------------------------------------------------
-- Genetics
-- --------------------------------------------------------------------------
-- Every plant has a hidden "genetics" score from 0 to 100. It sets the
-- ceiling for how good the plant can ever be.

Config.Genetics = {
    START          = 100,  -- fresh seeds (looted or from pollination)
    DRIFT_MIN      = 1,  -- smallest loss per clone generation
    DRIFT_MAX      = 5,  -- largest loss per clone generation
    HERMIE_PENALTY = 25,  -- permanent loss for a line that went hermie
    FLOOR          = 10,  -- genetics never drop below this
}

-- --------------------------------------------------------------------------
-- Breeding odds
-- --------------------------------------------------------------------------
-- When a hybrid is involved, the offspring type is rolled. Numbers are
-- percent chances and each row must add up to 100.
Config.Breeding = {
    HYBRID_X_PURE   = { pure = 70, hybrid = 30 },  -- Hybrid x Indica or Hybrid x Sativa
    HYBRID_X_HYBRID = { indica = 33, sativa = 33, hybrid = 34 },
}

-- Seeds dropped per pollinated plant at harvest (before HarvestQuantity).
Config.SEEDS_PER_POLLINATED_PLANT = { min = 3, max = 8 }

-- How many tiles away a flowering male (or hermie) can pollinate.
Config.POLLINATION_RADIUS = 6

-- --------------------------------------------------------------------------
-- Stress and hermaphrodites
-- --------------------------------------------------------------------------
Config.Stress = {
    MAX                = 100,
    CLONE_INHERIT      = 0.5,  -- a clone starts with half its mother's stress
    CUTTING_COST       = 3,  -- stress added to the mother per cutting taken
    HERMIE_THRESHOLD   = 60,  -- below this stress, no hermie chance at all
    HERMIE_CHANCE_MAX  = 25,  -- % chance over a whole flowering stage at 100 stress
}

-- --------------------------------------------------------------------------
-- Cloning / rooting
-- --------------------------------------------------------------------------
-- Rooting chance (%) = BASE + level * PER_LEVEL + gel + dome + conditions,
-- then clamped between MIN and MAX.
Config.Rooting = {
    BASE       = 35,
    PER_LEVEL  = 4,  -- Agriculture 10 adds +40
    GEL_BONUS  = 15,  -- Rooting Gel
    DOME_BONUS = 15,  -- Cloning Dome
    MIN        = 5,
    MAX        = 95,
    HOURS      = 24,  -- base time to root, before conditions slow it down

    -- Condition modifiers. Each one is checked when the root roll happens.
    TEMP_IDEAL_MIN = 18,  -- degrees C
    TEMP_IDEAL_MAX = 28,
    TEMP_PENALTY   = -15,  -- outside the ideal range
    TEMP_SLOW      = 1.5,
    NO_LIGHT_PENALTY = -10,
    NO_LIGHT_SLOW    = 1.25,
    DRY_PENALTY      = -20,  -- cutting not kept moist (a dome keeps it moist)
    DRY_SLOW         = 1.25,

    -- Wilting: a cut stem starts losing vigour after a few hours out of
    -- water. The cutting item also goes stale/rotten on vanilla's food timer
    -- (DaysFresh in CannabisItems.txt), and stale cuttings can't be sown at
    -- all.
    WILT_GRACE_HOURS = 6,  -- no penalty for this long after cutting
    WILT_PER_HOUR    = 2,  -- then -2% rooting chance per hour

    -- Sticking a cutting straight into soil instead of a dome.
    SOIL_PENALTY = -10,

    DOME_CAPACITY = 12,
}

-- --------------------------------------------------------------------------
-- Light caps (max final quality a light source allows)
-- --------------------------------------------------------------------------
Config.LightCap = {
    NONE       = 0,  -- plant stalls, handled separately
    SUN        = 70,
    BASIC_LAMP = 85,
    GOOD_LAMP  = 100,
}

-- --------------------------------------------------------------------------
-- Care penalties (subtracted from the plant's Care score, which starts at
-- 100)
-- --------------------------------------------------------------------------
-- Grow lights. PLACED LAMPS are furniture (moveable items): each has a tile
-- sprite, and the light scan looks for those sprites on nearby squares.
Config.Light = {
    EMA_PER_CHECK = 1/120,  -- how fast the plant's light score follows its light
    NO_LIGHT_PENALTY_PER_HOUR = 1.0,
    -- By tile sprite name (placed furniture). Sprites 197-200 of the sheet.
    SPRITES = {
        ["dazeddank_plants_01_197"] = { cap = 85,  radius = 2, name = "Basic grow lamp" },
        ["dazeddank_plants_01_198"] = { cap = 100, radius = 2.5, name = "Pro grow lamp" },
        ["dazeddank_plants_01_199"] = { cap = 85,  radius = 3, name = "Large basic grow lamp" },
        ["dazeddank_plants_01_200"] = { cap = 100, radius = 4, name = "Large pro grow lamp" },
        -- Floor flood lights (sprites 234-235) stand on the ground, so they may be placed outdoors.
        ["dazeddank_plants_01_234"] = { cap = 85,  radius = 3.5, name = "Flood grow light", floor = true },
        ["dazeddank_plants_01_235"] = { cap = 100, radius = 4.5, name = "Pro flood grow light", floor = true },
    },
    -- By item type: lamp items lying on the ground still light plants (always 24/0).
    ITEMS = {
        ["CannabisMod.GrowLampBasic"]      = { cap = 85,  radius = 2, name = "Basic grow lamp" },
        ["CannabisMod.GrowLampPro"]        = { cap = 100, radius = 2.5, name = "Pro grow lamp" },
        ["CannabisMod.GrowLampLargeBasic"] = { cap = 85,  radius = 3, name = "Large basic grow lamp" },
        ["CannabisMod.GrowLampLargePro"]   = { cap = 100, radius = 4, name = "Large pro grow lamp" },
        ["CannabisMod.GrowFloodBasic"]     = { cap = 85,  radius = 3.5, name = "Flood grow light" },
        ["CannabisMod.GrowFloodPro"]       = { cap = 100, radius = 4.5, name = "Pro flood grow light" },
    },
}
-- Bar lamps span several tiles and each tile lights on its own. Large basic is 1x2 (sprites 214-221), large pro 1x3 (222-233).
for n = 214, 221 do
    Config.Light.SPRITES["dazeddank_plants_01_" .. n] = { cap = 85, radius = 3, name = "Large basic grow lamp" }
end
for n = 222, 233 do
    Config.Light.SPRITES["dazeddank_plants_01_" .. n] = { cap = 100, radius = 4, name = "Large pro grow lamp" }
end
-- Widest radius of any lamp, rounded up: how far the scan has to look.
Config.Light.MAX_RADIUS = 0
for _, def in pairs(Config.Light.SPRITES) do
    if math.ceil(def.radius) > Config.Light.MAX_RADIUS then Config.Light.MAX_RADIUS = math.ceil(def.radius) end
end

--- True if a square (dx, dy) from a lamp tile is lit: a round zone, so a bar lamp's tiles together make a capsule.
function Config.Light.reaches(dx, dy, radius)
    radius = radius * Config.sandbox("LampRange")
    return dx * dx + dy * dy <= radius * radius + 0.01
end

-- Light timers: a timer installed on a lamp sets its schedule, and a lamp without one runs 24/0.
-- 18/6 and 24/0 hold plants in veg; only 12/12 lets a plant past Vegetative into flower.
Config.Timer = {
    ITEM = "CannabisMod.LightTimer",
    ON_HOUR = 6,                                -- every schedule switches on at 6:00
    SCHEDULES = { ["18/6"] = 18, ["12/12"] = 12 },
    ORDER = { "18/6", "12/12" },
    DEFAULT = "18/6",                           -- what a freshly installed timer runs
    VEG_BONUS_MAX = 0.5,                        -- most extra yield that extra veg time can give
    VEG_BONUS_DAYS = 2.5,                       -- the bonus reaches about 63% of max after this many extra days
    LEAK_STRESS_PER_HOUR = 6,                   -- stress from light reaching a 12/12 plant in its dark hours
    EXTRA_WATER_PER_HOUR = 1.0,                 -- extra water a plant at the full veg bonus drinks
    FEED_EVERY_HOURS = 48,                      -- in held veg the plant wants feeding this often
    HUNGRY_PENALTY = 3,                         -- care lost for each missed feeding while held in veg
}

--- True if a lamp on this schedule is lit at this hour of the day (0-23); nil means no timer (24/0).
function Config.Timer.isOn(schedule, hour)
    local onHours = schedule and Config.Timer.SCHEDULES[schedule]
    if not onHours then return true end
    return (hour - Config.Timer.ON_HOUR) % 24 < onHours
end

--- True if a schedule keeps plants in veg (no timer, or anything but 12/12).
function Config.Timer.isLongDay(schedule)
    return schedule ~= "12/12"
end

--- Extra yield fraction for this many hours of veg beyond the minimum; each day adds less than the last.
function Config.Timer.vegBonus(extraHours)
    if not extraHours or extraHours <= 0 then return 0 end
    local days = extraHours / 24 * math.max(0.1, Config.sandbox("GrowthSpeed") or 1)
    return Config.Timer.VEG_BONUS_MAX * (1 - math.exp(-days / Config.Timer.VEG_BONUS_DAYS))
end

-- Hydroponics: reservoirs that plants drink from, nutrient strength that runs down, and root rot.
Config.Hydro = {
    RESERVOIR_L = { dwc = 15 },                 -- litres each system holds
    -- litres a plant drinks per hour, by stage (seedling, veg, pre-flower, flowering, ripe)
    DRINK_PER_HOUR = { 0.1, 0.3, 0.4, 0.5, 0.3 },
    PLOT_WATER = 70,                            -- the plot's water level while the reservoir has water
    DRY_PLOT_WATER = 10,                        -- and when it has run dry
    NUTRIENT_HOURS = 72,                        -- a full dose runs out over about three days
    HUNGRY_BELOW = 0.2,                         -- nutrient strength under this starves the plant
    HUNGRY_PER_HOUR = 0.3,                      -- care lost per hour while starved
    BURN_ABOVE = 0.6,                           -- dosing a reservoir still this strong burns the plant
    STALE_DAYS = 7,                             -- days before a reservoir goes stale and needs changing
    TREAT_WITHIN_HOURS = 6,                     -- bleach only works on a reservoir changed this recently
    BLEACH_L = 0.1,                             -- bleach used per treatment
    -- Root rot: risk per hour from each cause, and the stages it passes through (0-100).
    ROT_NO_AIR = 3, ROT_STALE = 1, ROT_TAINTED = 0.5, ROT_SPREAD = 0.5,
    ROT_EARLY = 30, ROT_DEAD = 100,
    ROT_CARE_PER_HOUR = 1.0,                    -- care lost per hour once rot is past early
    MEDIUM_ITEMS = { rockwool = "CannabisMod.RockwoolCube", pebbles = "CannabisMod.ClayPebbles" },
    PEBBLE_SEED_FAIL = 25,                      -- % of seeds sown straight into clay pebbles that don't take
}

Config.Care = {
    START                 = 100,
    OVERWATER_PER_HOUR    = 0.5,
    UNDERWATER_PER_HOUR   = 0.5,
    WRONG_NUTRIENT        = 3,
    NUTRIENT_BURN         = 10,
    LIGHT_INTERRUPTION    = 5,  -- per interruption during Flowering
    -- Each care penalty also adds this fraction of itself as stress.
    STRESS_FROM_CARE      = 1.0,
    RIGHT_NUTRIENT_BONUS  = 2,  -- the right nutrient once per stage
}

-- --------------------------------------------------------------------------
-- Quality multipliers
-- --------------------------------------------------------------------------
Config.Quality = {
    SEEDED_MULT        = 0.75,  -- pollinated or hermie buds
    HARVEST_FALLOFF    = 2.0,  -- % quality lost per hour outside the ripe window
    HARVEST_MIN_MULT   = 0.5,  -- worst a bad harvest time can do
    RUSHED_DRY_MIN_MULT = 0.6,  -- buds pulled at 0% dry time
    DRY_HOURS          = 48,
}

-- --------------------------------------------------------------------------
-- After harvest: drying, trimming and curing
-- --------------------------------------------------------------------------
-- Racks and jars only work while placed in the world (on a table, shelf or
-- floor); stations within SCAN_RADIUS of a player are found automatically.
Config.Drying = {
    RACK_ITEM = "CannabisMod.DryingRack", RACK_CAPACITY = 8,
    JAR_ITEM  = "CannabisMod.CuringJar",  JAR_CAPACITY  = 30,
    -- The curing barrel: a one-tile furniture container (sprite 236) that cures like a big jar.
    BARREL_ITEM = "CannabisMod.CuringBarrel", BARREL_CAPACITY = 300,
    BARREL_SPRITE = "dazeddank_plants_01_236",
    FAN_ITEM  = "CannabisMod.DryingFan",  FAN_RADIUS = 3,
    -- Placed furniture, by sprite name: the rack tiles (206-213) and the fan.
    RACK_SPRITES = {},
    -- Where the other half of a rack is: east and west racks run south, south and north racks run east.
    RACK_PARTNER = {},
    FAN_SPRITE   = "dazeddank_plants_01_205",
    BUD_ITEM  = "CannabisMod.CannabisBud",
    SCAN_RADIUS = 8,
    TEMP_REF_C = 18, TEMP_RATE_PER_C = 0.03, RATE_MIN = 0.6, RATE_MAX = 1.6,
    FAN_RATE = 1.15,
    -- mold chance per hour for a plant that is still wet
    MOLD_BASE = 0.0008, MOLD_OUTDOORS = 1.5, MOLD_RAIN = 3, MOLD_WARM_C = 24, MOLD_WARM = 1.5,
    MOLD_COLD_C = 10, MOLD_COLD = 0.5, MOLD_FAN = 0.4, MOLD_DRY_FLOOR = 0.1,
    OVERDRY_AFTER = 120, OVERDRY_PER_HOUR = 0.001, OVERDRY_MIN = 0.7,
    SUN_LOSS_PER_HOUR = 0.004, SUN_LOSS_MAX = 0.25,   -- direct sun bleaches buds
    MOLDY_MULT = 0.2,
    MAX_CATCHUP_HOURS = 24 * 30,
}
-- Pairs of rack sprites: first tile of a facing, then its partner (E and W run along y, S and N along x).
for n = 206, 212, 2 do
    local along = (n < 208 or (n >= 210 and n < 212)) and { 0, 1 } or { 1, 0 }
    local a, b = "dazeddank_plants_01_" .. n, "dazeddank_plants_01_" .. (n + 1)
    Config.Drying.RACK_SPRITES[a], Config.Drying.RACK_SPRITES[b] = true, true
    Config.Drying.RACK_PARTNER[a] = { along[1], along[2] }
    Config.Drying.RACK_PARTNER[b] = { -along[1], -along[2] }
end
Config.Curing = {
    FULL_DAYS = 6, BONUS = 0.10,        -- up to +10% quality after FULL_DAYS in a jar
    BURP_EVERY_HOURS = 36,               -- an unburped jar starts to risk mold after this
    MOLD_PER_HOUR = 0.003, MOIST_MULT = 3,
    MOIST_BELOW = 0.8,                   -- buds trimmed under 80% dry go in "moist"
    BUD_WEIGHT = 0.03,
}
-- Item name prefix by final quality.
Config.QualityTiers = { { 85, "Premium" }, { 65, "Good" }, { 40, "Average" }, { 0, "Poor" } }
function Config.qualityTier(q)
    for _, t in ipairs(Config.QualityTiers) do
        if (q or 0) >= t[1] then return t[2] end
    end
    return "Poor"
end

-- --------------------------------------------------------------------------
-- Status window: which Agriculture level reveals which field
-- --------------------------------------------------------------------------
-- The server reads this table to decide what to send to a player. Fields
-- above the player's level are never sent, so they can't be read by
-- inspecting network traffic or client memory.
Config.InfoTiers = {
    { level = 0,  fields = { "name", "stageRough", "waterRough", "rooting", "container" } },
    { level = 2,  fields = { "stage", "hoursLeft", "water", "lastNutrient", "vegHeld", "reservoir" } },
    { level = 3,  fields = { "type", "sex", "light", "lightCycle", "roots" } },
    { level = 5,  fields = { "healthBand", "stressBand", "warnings", "extraVeg" } },
    { level = 7,  fields = { "harvestWindow", "pollinated", "hermieSigns" } },
    { level = 9,  fields = { "generation", "geneticsBand" } },
    { level = 10, fields = { "qualityEstimate" } },
}

-- Agriculture level needed to see a SEED's type and sex when inspecting it.
Config.SEED_INSPECT_LEVEL = 3

-- --------------------------------------------------------------------------
-- Sandbox defaults
-- --------------------------------------------------------------------------
-- Used when SandboxVars isn't available (for example, the offline test
-- script) or an option is missing from an old save.
Config.SandboxDefaults = {
    GrowthSpeed       = 1.0,  -- multiplier, 2.0 = twice as fast
    MaleSeedChance    = 10,  -- % of seeds that are male
    MoldChance        = 1.0,  -- multiplier on mold risk
    DependencyEnabled = true,
    DependencyRate    = 1.0,  -- multiplier on how fast dependency builds
    HarvestQuantity   = 1.0,  -- multiplier on buds and seeds from harvest
    LootRarity        = 1.0,  -- multiplier on world loot weights, 0 = no loot
    EffectStrength    = 1.0,  -- multiplier on the mood and need changes of a high and of withdrawal
    ToleranceRate     = 1.0,  -- multiplier on how fast tolerance builds with use
    DryingHours       = 48,   -- game hours for a wet plant to dry fully
    CuringDays        = 6,    -- days in a jar for the full curing bonus
    LampRange         = 1.0,  -- multiplier on how far grow lamps reach
    LampsNeedPower    = true, -- placed grow lamps only work with power
    RecipeMagazine    = true, -- crafting recipes must be learned from the Grower's Handbook
    RootRotRisk       = 1.0,  -- multiplier on how fast root rot builds and spreads, 0 = off
    ReservoirUseRate  = 1.0,  -- multiplier on how fast reservoirs drain and go stale
    HydroQualityBonus = 0.15, -- extra quality ceiling RDWC can reach (0.15 = up to 115)
    PumpsNeedPower    = true, -- hydro pumps only run with power
}

--- Hours a wet plant takes to dry fully (sandbox DryingHours).
function Config.dryHours() return Config.sandbox("DryingHours") end

--- Days in a jar for the full curing bonus (sandbox CuringDays).
function Config.cureDays() return Config.sandbox("CuringDays") end

--- Read a sandbox option, falling back to the default above.
--- @param name string option name, e.g. "GrowthSpeed"
--- @return the option value
function Config.sandbox(name)
    -- SandboxVars is a Zomboid global. Our options sit under
    -- SandboxVars.CannabisMod because sandbox-options.txt names them
    -- "CannabisMod.GrowthSpeed" and so on.
    local vars = SandboxVars and SandboxVars.CannabisMod
    if vars and vars[name] ~= nil then
        return vars[name]
    end
    return Config.SandboxDefaults[name]
end

-- --------------------------------------------------------------------------
-- Small helpers used everywhere
-- --------------------------------------------------------------------------

--- Random whole number from lo to hi, INCLUDING both ends. Zomboid's
--- ZombRand(a, b) returns a .. b-1, which is easy to get wrong, so everything
--- goes through this wrapper.
function Config.randInt(lo, hi)
    if hi < lo then lo, hi = hi, lo end
    if ZombRand then
        return ZombRand(lo, hi + 1)
    end
    return math.random(lo, hi)
end

--- Roll a percent chance. rollPercent(25) is true about 25% of the time.
function Config.rollPercent(chance)
    if chance <= 0 then return false end
    if chance >= 100 then return true end
    return Config.randInt(1, 100) <= chance
end

--- Keep a number between lo and hi.
function Config.clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

--- Build the registry key for a tile. One plant per tile, so x/y/z is a
--- unique id that both client and server can work out from a square.
function Config.tileKey(x, y, z)
    return tostring(x) .. "_" .. tostring(y) .. "_" .. tostring(z)
end


-- --------------------------------------------------------------------------
-- Smoking, effects, tolerance and dependency
-- --------------------------------------------------------------------------
Config.Smoking = {
    PAPER_ITEM = "CannabisMod.RollingPapers",
    JOINT_ITEM = "CannabisMod.Joint",
    PIPE_ITEM  = "CannabisMod.SmokingPipe",
    -- Anything in the bag that can light it (vanilla item types).
    LIGHTERS = { "Base.Lighter", "Base.LighterDisposable", "Base.Matches", "Base.MatchesBox" },
    -- A joint is a gentle smoke; a pipe hit is stronger and builds tolerance faster.
    METHODS = {
        joint = { potency = 1.0, tolerance = 1.0, ticks = 420, name = "Joint" },
        pipe  = { potency = 1.3, tolerance = 1.4, ticks = 240, name = "Pipe" },
    },
    BASE_HOURS = 2.5,   -- how long a full-strength high lasts
}

Config.Use = {
    TOL_GAIN = 8, TOL_DECAY_PER_DAY = 6, TOL_MAX_REDUCTION = 0.65,
    DEP_GAIN = 3, DEP_OCCASIONAL = 0.3, DEP_REGULAR_HOURS = 30,
    DEP_DECAY_AFTER_DAYS = 3, DEP_DECAY_PER_DAY = 5,
    WITHDRAW_AFTER_HOURS = 20, WITHDRAW_MIN_DEP = 15,
    MOLDY_POTENCY = 0.1,
    -- Stat change per hour at full strength, by strain. Stat names are CharacterStat entries.
    EFFECTS = {
        Indica = { STRESS = -0.15, UNHAPPINESS = -12, BOREDOM = -8, FATIGUE = 0.06, HUNGER = 0.05, THIRST = 0.04 },
        Sativa = { STRESS = -0.05, UNHAPPINESS = -10, BOREDOM = -15, FATIGUE = -0.04, HUNGER = 0.03, THIRST = 0.03 },
        Hybrid = { STRESS = -0.10, UNHAPPINESS = -11, BOREDOM = -11, FATIGUE = 0.01, HUNGER = 0.04, THIRST = 0.035 },
    },
    MOLDY_EFFECTS = { STRESS = 0.05, UNHAPPINESS = 5, THIRST = 0.03 },
    ANXIETY_ABOVE = 0.9, ANXIETY_STRESS = 0.1,   -- an overly strong sativa-leaning hit gets anxious
    WITHDRAWAL = { STRESS = 0.12, UNHAPPINESS = 8, BOREDOM = 8, HUNGER = -0.02 },
}
