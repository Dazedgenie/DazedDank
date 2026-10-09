-- Offline test harness: stubs the Zomboid API, loads the mod's shared and
-- server files, and checks the genetics, breeding, rooting, quality,
-- info-tier and registry logic.
local MOD = arg[1] .. "/Contents/mods/DazedDank/42/media/lua/"
math.randomseed(42)

-- ---- Zomboid API stubs -------------------------------------------------
local loaded = {}
function require(name)
    if loaded[name] then return end
    loaded[name] = true
    -- Vanilla farming files are provided by the stubs below.
    if name:sub(1, 8) == "Farming/" or name:sub(1, 6) == "Items/" or name:sub(1, 10) == "Moveables/" then return end
    for _, dir in ipairs({ "shared/", "server/", "client/" }) do
        local f = io.open(MOD .. dir .. name .. ".lua")
        if f then f:close(); dofile(MOD .. dir .. name .. ".lua"); return end
    end
    error("module not found: " .. name)
end
next = nil  -- the game's Lua (Kahlua) has no next()
function isClient() return false end
function isServer() return true end  -- route replies through sendServerCommand so tests can see them
function isDebugEnabled() return true end
local handlers = {}
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function(fn) handlers[k] = handlers[k] or {}; table.insert(handlers[k], fn) end }
    rawset(t, k, e); return e end })
local store = {}
ModData = { getOrCreate = function(k) store[k] = store[k] or {}; return store[k] end }
local worldHours = 0
hourOfDay = 12
function getGameTime() return { getWorldAgeHours = function() return worldHours end, getHour = function() return hourOfDay end } end
Perks = { Farming = "Farming" }
local sent = {}
function sendServerCommand(player, module, cmd, data) sent[#sent + 1] = { module = module, cmd = cmd, data = data } end
local function fire(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end

-- ---- Vanilla farming stubs (shaped like the real B42 files) ------------
farming_vegetableconf = { props = {} }
for _, set in ipairs({ "sprite", "unhealthySprite", "dyingSprite", "deadSprite", "trampledSprite" }) do
    farming_vegetableconf[set] = { Hemp = { "h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8" } }
end
farming_vegetableconf.getObjectName = function(p)
    if p.state == "plow" then return "Plowed Land" end
    return "Cannabis plot"
end
farming_vegetableconf.getSpriteName = function(p)
    if p.state == "plow" then return "vegetation_farming_01_1" end
    return farming_vegetableconf.sprite[p.typeOfSeed][p.nbOfGrow]
end
local plots = {}
local Plot = {}; Plot.__index = Plot
function Plot:isAlive() return self.state ~= "dead" and self.state ~= "destroyed" and self.state ~= "harvested" end
function Plot:setObjectName(n) self.objectName = n end
function Plot:setSpriteName(n) self.spriteName = n end
function Plot:saveData() end
function Plot:harvestThis() self.state = "harvested" end
function Plot:initNew() self.state, self.nbOfGrow, self.typeOfSeed, self.waterLvl = "plow", -1, "none", 0 end
function Plot:getSquare() return nil end
function Plot:getIsoObject()
    self.iso = self.iso or { md = {}, getModData = function(o) return o.md end, transmitModData = function(o) o.sent = (o.sent or 0) + 1 end }
    return self.iso
end
local function newPlot(x, y, z)
    local p = setmetatable({ x = x, y = y, z = z, state = "plow", nbOfGrow = -1, typeOfSeed = "none", waterLvl = 60 }, Plot)
    plots[#plots + 1] = p; return p
end
SFarmingSystem = { instance = { hoursElapsed = 500 } }
function SFarmingSystem.instance:getLuaObjectAt(x, y, z)
    for _, p in ipairs(plots) do if p.x == x and p.y == y and p.z == z then return p end end
end
function SFarmingSystem.instance:getLuaObjectCount() return #plots end
function SFarmingSystem.instance:plow(sq)
    local p = newPlot(sq.x, sq.y, sq.z); p.state = "plow"; p.nbOfGrow = -1; p.typeOfSeed = "none"
    return p
end
function SFarmingSystem:removePlant(lo)
    for i, p in ipairs(plots) do if p == lo then table.remove(plots, i) break end end
    lo.removed = true
end
setmetatable(SFarmingSystem.instance, { __index = SFarmingSystem })
function SFarmingSystem.instance:getLuaObjectByIndex(i) return plots[i] end
local vanillaHarvested = nil
function SFarmingSystem:harvest(lo, player) vanillaHarvested = lo end
ISSeedActionNew = {}
function ISSeedActionNew:complete()  -- vanilla: removes the seed, seeds the plot
    self.seed.removed = true
    local p = SFarmingSystem.instance:getLuaObjectAt(self.plant.x, self.plant.y, self.plant.z)
    p.state, p.typeOfSeed, p.nbOfGrow = "seeded", self.typeOfSeed, 1
    return true
end
local nextId = 1000
-- Items: tags, food age/rot, drainable uses, and which container holds them.
ItemTag = { CUT_PLANT = "base:cutplant", SCISSORS = "base:scissors", SHARP_KNIFE = "base:sharpknife",
            IS_SEED = "base:isseed" }
local function newItem(fullType, id)
    nextId = nextId + 1
    local md = {}
    return { fullType = fullType, id = id or nextId, tags = {}, age = 0, rotten = false, uses = 10,
        getModData = function() return md end,
        getID = function(self) return self.id end,
        getFullType = function(self) return self.fullType end,
        hasTag = function(self, t) return self.tags[t] == true end,
        getAge = function(self) return self.age end,
        setAge = function(self, a) self.age = a end,
        isRotten = function(self) return self.rotten end,
        getContainer = function(self) return self.container end,
        setName = function(self, n) self.name = n end,
        getName = function(self) return self.name or self.fullType end,
        UseAndSync = function(self) self.uses = self.uses - 1 end }
end
function instanceof(o, name) return name == "InventoryContainer" and o.getInventory ~= nil end
local function newContainer()
    local inv = { items = {} }
    function inv:getItems()
        local items = self.items
        return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
    end
    function inv:AddItems(fullType, n)
        local list = {}
        for i = 1, n do
            list[i] = newItem(fullType); list[i].container = self
            self.items[#self.items + 1] = list[i]
        end
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    function inv:addExisting(item) item.container = self; self.items[#self.items + 1] = item; return item end
    function inv:Remove(item)
        for i, it in ipairs(self.items) do if it == item then table.remove(self.items, i); break end end
        item.container = nil
    end
    function inv:getFirstTypeRecurse(fullType)
        for _, it in ipairs(self.items) do if it.fullType == fullType then return it end end
        return nil
    end
    function inv:count(fullType)
        local n = 0
        for _, it in ipairs(self.items) do if it.fullType == fullType then n = n + 1 end end
        return n
    end
    return inv
end
-- A dome is a container item: its inventory knows which item owns it.
local function newDome()
    local dome = newItem("CannabisMod.CloningDomeTray")
    local inv = newContainer()
    inv.getContainingItem = function() return dome end
    dome.getInventory = function() return inv end
    dome.getWorldItem = function() return nil end
    return dome
end
local function newPlayer(x, y, level)
    local inv = newContainer()
    return { inv = inv, getInventory = function() return inv end,
        getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
        getCurrentSquare = function() return nil end,
        getPerkLevel = function() return level end, getAccessLevel = function() return "None" end }
end
function sendRemoveItemFromContainer() end
function sendAddItemsToContainer() end

-- ---- Load the mod ------------------------------------------------------
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisUse"
require "CannabisMod/CannabisInfo"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisServerCommands"
require "CannabisMod/CannabisCloning"
require "CannabisMod/CannabisLight"
require "CannabisMod/CannabisGrowing"
require "CannabisMod/CannabisGrowBags"
require "CannabisMod/CannabisDrying"
require "CannabisMod/CannabisUse"
require "CannabisMod/CannabisSmoking"
require "CannabisMod/CannabisTimers"
require "CannabisMod/CannabisHydro"
require "CannabisMod/CannabisDrip"
SPlantGlobalObject = SPlantGlobalObject or { setSpriteName = function(self, n) self.spriteName = n end }
require "CannabisMod/CannabisPotPlants"
require "CannabisMod/CannabisPlantTemp"
require "CannabisMod/CannabisLampHeat"
--- The plant layer a plot shows (plots themselves show the furrow or container).
local function plantSprite(plot) return (CannabisMod.PotPlants.wanted(plot)) end
--- The shape index of the plant on a plot's tile, from its strain.
local function shapeAt(x, y, z)
    local St = CannabisMod.Strains
    return St.shapeIndex(St.shapeOf(St.of(CannabisMod.Registry.getPlant(x, y, z))))
end
fire("OnInitGlobalModData", true)

local C, G, I, R = CannabisMod.Config, CannabisMod.Genetics, CannabisMod.Info, CannabisMod.Registry
local T = C.TYPES
local passed, failed = 0, 0
local function check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name) end
end

-- ---- Config ------------------------------------------------------------
check("stage lookup", C.STAGE.Flowering == 4 and C.STAGE.Ripe == 5)
check("sandbox default", C.sandbox("MaleSeedChance") == 10)
local okRange = true
for i = 1, 2000 do local v = C.randInt(1, 3); if v < 1 or v > 3 then okRange = false end end
check("randInt inclusive range", okRange)

-- ---- Sex ratio ---------------------------------------------------------
local males = 0
for i = 1, 10000 do if G.rollSex() == C.SEX.MALE then males = males + 1 end end
check("~10% males (" .. males .. ")", males > 800 and males < 1200)

-- ---- Breeding ----------------------------------------------------------
check("I x I = I", G.breedType(T.INDICA, T.INDICA) == T.INDICA)
check("S x S = S", G.breedType(T.SATIVA, T.SATIVA) == T.SATIVA)
check("I x S = H", G.breedType(T.INDICA, T.SATIVA) == T.HYBRID)
check("S x I = H", G.breedType(T.SATIVA, T.INDICA) == T.HYBRID)
local hi, hh = 0, 0
for i = 1, 10000 do
    local r = G.breedType(T.HYBRID, T.INDICA)
    if r == T.INDICA then hi = hi + 1 elseif r == T.HYBRID then hh = hh + 1 end
end
check("H x I ~70% indica (" .. hi .. ")", hi > 6600 and hi < 7400 and hi + hh == 10000)
local counts = { Indica = 0, Sativa = 0, Hybrid = 0 }
for i = 1, 9000 do local r = G.breedType(T.HYBRID, T.HYBRID); counts[r] = counts[r] + 1 end
check("H x H spread", counts.Indica > 2600 and counts.Sativa > 2600 and counts.Hybrid > 2600)

-- ---- Seeds & hermie lineage -------------------------------------------
local s = G.newSeed(T.SATIVA)
check("fresh seed genetics 100", s.genetics == 100 and s.generation == 0 and not s.hermieLineage)
local hs = G.newSeed(T.SATIVA, { hermieLineage = true })
check("hermie seed penalty", hs.genetics == 75 and hs.hermieLineage)
local seeds = G.seedsFromPollination({ type = T.INDICA }, { type = T.SATIVA, hermieLineage = true })
check("pollination seed count 3-8", #seeds >= 3 and #seeds <= 8)
local st1 = seeds[1].strain
check("pollination seeds carry a mid cross + hermie line", st1 and st1.ind >= 27 and st1.ind <= 73 and seeds[1].hermieLineage)
check("one pollination, one strain name", seeds[#seeds].strain.name == st1.name and st1.name ~= "Hybrid")
check("seed type follows its strain", seeds[1].type == CannabisMod.Strains.typeOf(st1))

-- ---- Strains ------------------------------------------------------------
local ST = CannabisMod.Strains
local kush, haze = ST.STARTERS[1], ST.STARTERS[4]
check("6 starters, 3 indica 3 sativa", #ST.STARTERS == 6 and ST.typeOf(kush) == T.INDICA and ST.typeOf(haze) == T.SATIVA)
local same = ST.cross(kush, kush)
check("same strain breeds true", same.name == kush.name and math.abs(same.ind - kush.ind) <= 23)
local x1, x2 = ST.cross(kush, haze), ST.cross(haze, kush)
check("cross gets a new name", x1.name ~= kush.name and x1.name ~= haze.name and #x1.name > 3)
check("cross name is a place and a word", x1.name:find(" ") ~= nil)
check("traits stay 0-100", x1.ind >= 0 and x1.ind <= 100 and x1.pot >= 0 and x1.pot <= 100)
check("fast strain flowers sooner", ST.flowerMult({ flw = 100 }) < ST.flowerMult({ flw = 0 }) and ST.flowerMult({ flw = 50 }) > 0.99 and ST.flowerMult({ flw = 50 }) < 1.04)
check("yield span", ST.yieldMult({ yld = 0 }) == 0.75 and ST.yieldMult({ yld = 100 }) == 1.25)
check("potency span", ST.potencyMult({ pot = 0 }) == 0.8 and ST.potencyMult({ pot = 100 }) == 1.2)
local eff = ST.effects({ ind = 100 })
check("pure indica effects = indica table", eff.STRESS == C.Use.EFFECTS.Indica.STRESS and eff.BOREDOM == C.Use.EFFECTS.Indica.BOREDOM)
local mix = ST.effects({ ind = 50 })
check("50/50 effects are the average", math.abs(mix.BOREDOM - (C.Use.EFFECTS.Indica.BOREDOM + C.Use.EFFECTS.Sativa.BOREDOM) / 2) < 0.001)
check("old record gets a starter of its type", ST.typeOf(ST.of({ type = T.SATIVA })) == T.SATIVA and ST.of({ type = T.HYBRID }).name == "Hybrid")
check("sanitize rejects junk", ST.sanitize({ name = "x" }) == nil and ST.sanitize("no") == nil and ST.sanitize({ name = "ok", ind = 50, pot = 500, yld = 1, flw = 1 }).pot == 100)
local tr, tg, tb = ST.tint(kush)
check("tint stays light", tr >= 0.7 and tg >= 0.7 and tb >= 0.7 and tr <= 1 and tg <= 1 and tb <= 1)
check("strain potency scales a dose", CannabisMod.Use.potency(100, false, { pot = 100 }) > CannabisMod.Use.potency(100, false, { pot = 0 }))
check("describe reads", ST.describe(kush):find("85%% indica") ~= nil)

-- ---- Cloning drift -----------------------------------------------------
local mom = { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100, generation = 0, stress = 40 }
local line = mom
for gen = 1, 10 do line = G.cloneFrom(line) end
check("10 gens drift 10-50 (" .. line.genetics .. ")", line.genetics <= 90 and line.genetics >= 50)
check("clone generation counted", line.generation == 10)
check("clone stays female", line.sex == C.SEX.FEMALE)
local c1 = G.cloneFrom(mom)
check("clone inherits half stress", c1.stress == 20)
local floor = { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 11, generation = 50 }
check("genetics floor", G.cloneFrom(floor).genetics == 10)
check("can clone in veg", G.canClone({ stage = 2 }) and G.canClone({ stage = 3 }))
check("no clone in flower", not G.canClone({ stage = 4 }) and not G.canClone({ stage = 1 }))

-- ---- Rooting -----------------------------------------------------------
local base = G.rootingOdds(0, { moist = true })
local best = G.rootingOdds(10, { gel = true, dome = true, tempC = 22, hasLight = true })
local bare, slow = G.rootingOdds(0, { tempC = 5, hasLight = false })
check("rooting base 35 (" .. base .. ")", base == 35)
check("rooting best capped 95 (" .. best .. ")", best == 95)
check("rooting worst floored 5 (" .. bare .. ")", bare == 5)
check("bad conditions slow rooting (" .. slow .. "h)", slow > 24)
local _, domeHours = G.rootingOdds(3, { dome = true })
check("dome counts as moist", domeHours == 24)
check("level raises rooting", G.rootingOdds(5, { moist = true }) == 55)

-- ---- Hermie chance -----------------------------------------------------
check("no hermie below threshold", G.hermieChance(59) == 0)
check("max hermie at 100 stress", G.hermieChance(100) == 25)
local hp = { genetics = 90, hermieLineage = false }
G.makeHermie(hp); G.makeHermie(hp)
check("hermie penalty applied once", hp.genetics == 65 and hp.isHermie)

-- ---- Quality -----------------------------------------------------------
local perfectLamp = { lightCap = 100, genetics = 100, care = 100 }
check("perfect lamp grow = 100", G.calcQuality(perfectLamp, 0, 48) == 100)
check("sun cap 70", G.calcQuality({ lightCap = 70, genetics = 100, care = 100 }, 0, 48) == 70)
check("genetics lower than cap wins", G.calcQuality({ lightCap = 100, genetics = 60, care = 100 }, 0, 48) == 60)
check("seeded x0.75", G.calcQuality({ lightCap = 100, genetics = 100, care = 100, seeded = true }, 0, 48) == 75)
check("rushed dry 0h x0.6", G.calcQuality(perfectLamp, 0, 0) == 60)
check("late harvest falls off", G.calcQuality(perfectLamp, 10, 48) == 80)
check("harvest floor 0.5", G.calcQuality(perfectLamp, 1000, 48) == 50)

-- ---- Info tiers --------------------------------------------------------
local plant = { stage = 2, water = 50, type = T.SATIVA, sex = C.SEX.MALE, care = 90, stress = 10,
    genetics = 95, generation = 2, lightCap = 70, nextStageAt = 30, warnings = { overwatered = true } }
local l0 = I.buildVisible(plant, 0, 10)
check("lvl0 rough only", l0.stageRough == "Growing" and l0.waterRough == "OK" and l0.type == nil and l0.stage == nil)
local l3 = I.buildVisible(plant, 3, 10)
check("lvl3 type and sex (sex reads like a seed at 3)", l3.type == T.SATIVA and l3.sex == C.SEX.MALE and l3.hoursLeft == 20)
check("lvl3 strain name shows", l3.strain ~= nil and l3.traits == nil)
check("lvl3 no stress", l3.stressBand == nil)
plant.stage = 3
check("lvl2 sees no type or sex", I.buildVisible(plant, 2, 10).type == nil and I.buildVisible(plant, 2, 10).sex == nil)
plant.isHermie = true
check("hermie shows as hermaphrodite", I.buildVisible(plant, 3, 10).sex == "Hermaphrodite")
plant.isHermie = nil
local l10 = I.buildVisible(plant, 10, 10)
check("lvl10 everything", l10.qualityEstimate ~= nil and l10.geneticsBand == "Strong" and l10.warnings[1] == "overwatered")
check("lvl9 no quality", I.buildVisible(plant, 9, 10).qualityEstimate == nil)
check("seed hidden below 3", I.seedLabel(s, 2) == "Unknown cannabis seed")
check("seed shown at 3", I.seedLabel(s, 3):find(T.SATIVA) ~= nil)

-- ---- Registry & growth clock ------------------------------------------
worldHours = 100
local p = R.addPlant(10, 10, 0, G.newSeed(T.INDICA))
check("registry stores plant", R.getPlant(10, 10, 0) == p and p.stage == 1)
check("stage timer 24-48h", p.nextStageAt >= 124 and p.nextStageAt <= 148)
local clone = R.addPlant(11, 10, 0, c1, { fromCutting = true })
check("cutting starts in veg", clone.stage == 2 and clone.stress == 20)
worldHours = 1000; fire("EveryTenMinutes")
check("plant advanced one stage per tick", p.stage == 2)
for i = 1, 5 do worldHours = worldHours + 100; fire("EveryTenMinutes") end
check("plant stops at ripe", p.stage == 5)

-- Feeding
local f = R.addPlant(20, 20, 0, G.newSeed(T.HYBRID)); f.stage = 2
check("veg in veg = good", R.feed(f, "Veg") == "good" and f.care == 100)
check("double feed = burn", R.feed(f, "Veg") == "burn" and f.care == 90 and f.warnings.nutrientBurn)
f.stage = 4; f.fedThisStage = 0
check("veg in flower = wrong", R.feed(f, "Veg") == "wrong" and f.care == 87)

-- Pollination: a male in flower seeds nearby flowering females only
local male = R.addPlant(30, 30, 0, { type = T.SATIVA, sex = C.SEX.MALE, genetics = 100 })
local near = R.addPlant(33, 30, 0, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
local far = R.addPlant(60, 30, 0, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
local upstairs = R.addPlant(31, 30, 1, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
local inVeg = R.addPlant(31, 31, 0, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
for _, pl in ipairs({ male, near, far, upstairs }) do pl.stage = 4; pl.nextStageAt = 1e9 end
inVeg.nextStageAt = 1e9
fire("EveryTenMinutes")
check("near female pollinated", near.seeded and near.fatherType == T.SATIVA)
check("far female untouched", not far.seeded)
check("other floor untouched", not upstairs.seeded)
check("veg female untouched", not inVeg.seeded)

-- Hermie pollinates neighbours and carries lineage
local herm = R.addPlant(80, 80, 0, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
local nb = R.addPlant(82, 80, 0, { type = T.SATIVA, sex = C.SEX.FEMALE, genetics = 100 })
herm.stage, nb.stage = 4, 4; herm.nextStageAt, nb.nextStageAt = 1e9, 1e9
G.makeHermie(herm)
fire("EveryTenMinutes")
check("hermie seeds itself", herm.seeded)
check("hermie seeds neighbour w/ lineage", nb.seeded and nb.fatherHermieLineage)
local nbSeeds = G.seedsFromPollination(nb, { type = nb.fatherType, hermieLineage = nb.fatherHermieLineage })
check("neighbour seeds inherit hermie line", nbSeeds[1].hermieLineage and nbSeeds[1].genetics == 75)

-- Two males share one female list per tick: the female is seeded once, and a female that starts flowering later is still caught.
do
    local m1 = R.addPlant(120, 120, 0, { type = T.SATIVA, sex = C.SEX.MALE, genetics = 100 })
    local m2 = R.addPlant(121, 120, 0, { type = T.INDICA, sex = C.SEX.MALE, genetics = 100 })
    local fem = R.addPlant(122, 121, 0, { type = T.HYBRID, sex = C.SEX.FEMALE, genetics = 100 })
    local late = R.addPlant(123, 121, 0, { type = T.HYBRID, sex = C.SEX.FEMALE, genetics = 100 })
    for _, pl in ipairs({ m1, m2, fem }) do pl.stage = 4; pl.nextStageAt = 1e9 end
    late.stage = 3; late.nextStageAt = 1e9
    fire("EveryTenMinutes")
    check("shared list: female seeded once by one of the males",
        fem.seeded and (fem.fatherType == T.SATIVA or fem.fatherType == T.INDICA))
    check("pre-flower female not seeded", not late.seeded)
    late.stage = 4
    fire("EveryTenMinutes")
    check("female that starts flowering is seeded next tick", late.seeded)
    -- Outside the tick the list is rebuilt each call.
    local loose = R.addPlant(124, 120, 0, { type = T.HYBRID, sex = C.SEX.FEMALE, genetics = 100 })
    loose.stage = 4; loose.nextStageAt = 1e9
    R.pollinateAround(m1)
    check("direct pollinate call outside a tick", loose.seeded and loose.fatherType == T.SATIVA)
end

-- Reading a dome never adds a save record, and an emptied dome drops its record.
do
    local domeStore = store[C.MODDATA_KEY .. "_Domes"]
    check("unknown dome reads empty", #R.getDome(987654) == 0 and domeStore["987654"] == nil)
    R.setDome(987654, { { id = 1, readyAt = 0 } })
    check("dome record stored", #R.getDome(987654) == 1)
    R.setDome(987654, {})
    check("empty dome record dropped", domeStore["987654"] == nil and #R.getDome(987654) == 0)
end

-- Stress-driven hermie over a long flower
local hits = 0
for trial = 1, 200 do
    local sp = { stage = 4, sex = C.SEX.FEMALE, stress = 100, genetics = 100, type = T.INDICA,
        x = 500 + trial * 20, y = 500, z = 0, nextStageAt = 1e9, warnings = {} }
    store[C.MODDATA_KEY]["t" .. trial] = sp
end
for tick = 1, 6 * 36 do fire("EveryTenMinutes") end  -- 36 hours of flower
for trial = 1, 200 do if store[C.MODDATA_KEY]["t" .. trial].isHermie then hits = hits + 1 end end
check("max-stress plants hermie ~25% over a 36h flower (" .. hits .. "/200)", hits >= 25 and hits <= 80)

-- ---- Server commands ---------------------------------------------------
local player = { getX = function() return 10 end, getY = function() return 11 end, getZ = function() return 0 end,
    getPerkLevel = function() return 3 end, getAccessLevel = function() return "None" end }
fire("OnClientCommand", "CannabisMod", "requestPlantInfo", player, { x = 10, y = 10, z = 0 })
local reply = sent[#sent]
check("info reply sent", reply and reply.cmd == "plantInfo" and reply.data.type == T.INDICA)
check("info reply hides lvl5+", reply.data.stressBand == nil and reply.data.qualityEstimate == nil)
local n = #sent
fire("OnClientCommand", "CannabisMod", "requestPlantInfo", player, { x = 99, y = 99, z = 0 })
check("far request ignored", #sent == n)
fire("OnClientCommand", "OtherMod", "requestPlantInfo", player, { x = 10, y = 10, z = 0 })
check("other module ignored", #sent == n)
fire("OnClientCommand", "CannabisMod", "requestPlantInfo", player, { x = "bad", y = 10, z = 0 })
check("bad args ignored", #sent == n)
fire("OnClientCommand", "CannabisMod", "requestPlantInfo", player, { x = 12, y = 12, z = 0 })
check("missing plant reply", sent[#sent].data.missing == true)

-- ---- Water ---------------------------------------------------------------
local wp = R.addPlant(300, 300, 0, G.newSeed(T.INDICA)); wp.stage = 2
wp.water = 95; R.waterCheck(wp)
check("overwatered costs care + warns", wp.care < 100 and wp.warnings.overwatered)
wp.water = 60; R.waterCheck(wp)
check("warning clears when water OK", wp.warnings.overwatered == nil)
local sp = R.addPlant(301, 300, 0, G.newSeed(T.INDICA)); sp.water = 5; R.waterCheck(sp)
check("seedlings get water grace period", sp.care == 100)

-- ---- Seeds from item IDs -------------------------------------------------
local S = CannabisMod.Seeds
local a, b = S._deriveFromId(123456), S._deriveFromId(123456)
check("same ID -> same seed", a.type == b.type and a.sex == b.sex)
local tcount, mcount = { Indica = 0, Sativa = 0, Hybrid = 0 }, 0
for id = 1, 30000 do
    local d = S._deriveFromId(id * 37 + 11)
    tcount[d.type] = tcount[d.type] + 1
    if d.sex == C.SEX.MALE then mcount = mcount + 1 end
end
check("ID seeds are starters, half indica half sativa", tcount.Indica > 13500 and tcount.Sativa > 13500 and tcount.Hybrid == 0)
check("ID seeds carry a strain", S.getData(newItem(C.SEED_ITEM, 77)).strain ~= nil)
check("ID seeds ~10% male (" .. mcount .. ")", mcount > 2400 and mcount < 3600)
local written = newItem(C.SEED_ITEM)
S.setData(written, { type = T.SATIVA, sex = C.SEX.MALE, genetics = 80, generation = 0 })
check("written seed data wins over ID", S.getData(written).type == T.SATIVA and S.getData(written).genetics == 80)
check("pre-strain seed data gets a matching starter", CannabisMod.Strains.typeOf(S.getData(written).strain) == T.SATIVA)

-- ---- Vanilla farming link ------------------------------------------------
-- Fresh start: drop all earlier test plants, which have no vanilla plots.
for k in pairs(store[C.MODDATA_KEY]) do store[C.MODDATA_KEY][k] = nil end
local F = CannabisMod.Farming
check("crop registered with vanilla", farming_vegetableconf.props.Cannabis ~= nil
    and farming_vegetableconf.props.Cannabis.seedName == C.SEED_ITEM)
check("hemp sprites borrowed", farming_vegetableconf.sprite.Cannabis[7] == "h7"
    and farming_vegetableconf.deadSprite.Cannabis ~= nil)

-- Sowing: the seed's data becomes the plant record.
local plotA = newPlot(400, 400, 0)
local seedItem = newItem(C.SEED_ITEM)
S.setData(seedItem, { type = T.SATIVA, sex = C.SEX.FEMALE, genetics = 90, generation = 2 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seedItem, plant = { x = 400, y = 400, z = 0 } })
local recA = R.getPlant(400, 400, 0)
check("sowing creates record from seed data", recA and recA.type == T.SATIVA and recA.genetics == 90 and recA.generation == 2)
check("vanilla clock frozen", plotA.nextGrowing > SFarmingSystem.instance.hoursElapsed + 1000)
check("a ground plant's plot shows the furrow", plotA.spriteName == C.FURROW_SPRITE)
check("seedling layer is the shared seedling", plantSprite(plotA) == "dazeddank_overlay_01_0")

-- Other crops are left alone.
local plotT = newPlot(401, 400, 0)
ISSeedActionNew.complete({ typeOfSeed = "Tomato", seed = newItem("Base.TomatoSeed"), plant = { x = 401, y = 400, z = 0 } })
check("tomato gets no cannabis record", R.getPlant(401, 400, 0) == nil)

-- Growth: our stage drives the sprite, ripe enables harvest.
R.advanceStage(recA)
check("veg layer follows the strain's shape", plotA.nbOfGrow == 3 and not plotA.hasVegetable
    and plantSprite(plotA) == C.overlaySprite(shapeAt(400, 400, 0), 1, 2, "sprite"))
R.advanceStage(recA); R.advanceStage(recA); R.advanceStage(recA)
check("ripe layer + harvest option", plotA.nbOfGrow == 7 and plotA.hasVegetable == true
    and plantSprite(plotA) == C.overlaySprite(shapeAt(400, 400, 0), CannabisMod.Strains.colourIndex(CannabisMod.Strains.colourOf(CannabisMod.Strains.of(recA))), 5, "sprite"))

-- Sync: water copies over; a vanilla plot without a record gets one.
plotA.waterLvl = 42
local plotB = newPlot(402, 400, 0); plotB.state, plotB.typeOfSeed, plotB.nbOfGrow = "seeded", "Cannabis", 1
F.syncWithVanilla()
check("water copied from plot", recA.water == 42)
check("orphan plot gets a record", R.getPlant(402, 400, 0) ~= nil)
plotB.state = "dead"
F.syncWithVanilla()
check("dead plot keeps record, marked dead", R.getPlant(402, 400, 0) and R.getPlant(402, 400, 0).dead)
check("dead layer keeps the shape", plantSprite(plotB) == C.overlaySprite(shapeAt(402, 400, 0), 1, R.getPlant(402, 400, 0).stage, "deadSprite"))
plotB.state, plotB.typeOfSeed = "plow", "none"  -- replowed for a new crop
F.syncWithVanilla()
check("replowed plot's record removed", R.getPlant(402, 400, 0) == nil)

-- Harvest: female ripe -> wet plant with quality, no vanilla produce.
local farmer = newPlayer(400, 400, 5)
worldHours = recA.nextStageAt - 1  -- inside the ripe window
recA.lightCap = 100
SFarmingSystem.harvest(SFarmingSystem.instance, plotA, farmer)
local wet = farmer.inv.items[1]
local hd = wet and wet:getModData().CannabisHarvest
check("harvest gives wet plant of its type", wet and wet.fullType == C.WET_PLANT_ITEMS[T.SATIVA])
check("wet plant carries quality (" .. tostring(hd and hd.quality) .. ")", hd and hd.quality == 90 and hd.type == T.SATIVA)
check("bud yield 4-8 scaled by genetics and strain (" .. tostring(hd and hd.budYield) .. ")", hd and hd.budYield >= 3 and hd.budYield <= 10)
check("wet plant carries its strain", hd and hd.strain and hd.strain.name ~= nil)
check("wet plant is named for its strain (" .. tostring(wet and wet.name) .. ")", wet and wet.name == "Wet " .. hd.strain.name .. " (" .. hd.type .. ")")
check("harvest removes the plant from the world", plotA.removed == true and SFarmingSystem.instance:getLuaObjectAt(400, 400, 0) == nil and R.getPlant(400, 400, 0) == nil)
check("unpollinated: no seeds", #farmer.inv.items == 1)

-- Harvest a pollinated plant: seeds carry bred types.
local plotC = newPlot(410, 410, 0); local seedC = newItem(C.SEED_ITEM)
S.setData(seedC, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seedC, plant = { x = 410, y = 410, z = 0 } })
local recC = R.getPlant(410, 410, 0)
for i = 1, 4 do R.advanceStage(recC) end
recC.seeded, recC.fatherType = true, T.SATIVA
local breeder = newPlayer(410, 410, 5)
SFarmingSystem.harvest(SFarmingSystem.instance, plotC, breeder)
local seedsOut = 0
for _, it in ipairs(breeder.inv.items) do
    if it.fullType == C.SEED_ITEM then
        seedsOut = seedsOut + 1
        local sd = S.getData(it)
        check("Indica x Sativa seed is a mid cross", sd.strain and sd.strain.ind >= 27 and sd.strain.ind <= 73 and sd.type == CannabisMod.Strains.typeOf(sd.strain))
    end
end
check("pollinated harvest drops 3-8 seeds (" .. seedsOut .. ")", seedsOut >= 3 and seedsOut <= 8)
check("indica harvest gives the Indica item", breeder.inv.items[1].fullType == "CannabisMod.WetIndicaPlant")
check("seeded buds lower quality", breeder.inv.items[1]:getModData().CannabisHarvest.quality < 70)

-- Harvest a male: no buds.
local plotM = newPlot(420, 420, 0); local seedM = newItem(C.SEED_ITEM)
S.setData(seedM, { type = T.INDICA, sex = C.SEX.MALE, genetics = 100 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seedM, plant = { x = 420, y = 420, z = 0 } })
local maleGuy = newPlayer(420, 420, 5)
SFarmingSystem.harvest(SFarmingSystem.instance, plotM, maleGuy)
check("male gives no buds", #maleGuy.inv.items == 0 and sent[#sent].cmd == "notify")

-- Vanilla harvest still runs for other crops.
SFarmingSystem.harvest(SFarmingSystem.instance, plotT, farmer)
check("tomato uses vanilla harvest", vanillaHarvested == plotT)

-- ---- Sprite selection ----------------------------------------------------
check("sprite: seedling shared by every shape", C.overlaySprite(1, 1, 1, "sprite") == C.overlaySprite(7, 4, 1, "sprite")
    and C.overlaySprite(2, 1, 1, "sprite") == "dazeddank_overlay_01_0")
check("sprite: first shape veg = 1", C.overlaySprite(1, 1, 2, "sprite") == "dazeddank_overlay_01_1")
check("sprite: dead seedling = 3 x 29", C.overlaySprite(4, 1, 1, "deadSprite") == "dazeddank_overlay_01_87")
check("sprite: green only before flowering", C.overlaySprite(4, 2, 3, "sprite") == C.overlaySprite(4, 1, 3, "sprite")
    and C.overlaySprite(4, 2, 4, "sprite") ~= C.overlaySprite(4, 1, 4, "sprite")
    and C.overlaySprite(4, 2, 4, "dyingSprite") == C.overlaySprite(4, 1, 4, "dyingSprite"))
check("sprite: XL pots use the second sheet", C.overlaySprite(3, 1, 4, "sprite", "xldwc") == "dazeddank_overlay_02_" .. (1 + 2 * 4 + 2))
local seen = {}
for _, cond in ipairs({ "sprite", "unhealthySprite", "dyingSprite", "deadSprite", "trampledSprite" }) do
    for shape = 1, 7 do
        for colour = 1, 5 do
            for st = 1, 5 do
                for _, male in ipairs({ false, true }) do seen[C.overlaySprite(shape, colour, st, cond, nil, male)] = true end
            end
        end
    end
end
local nSeen, maxN = 0, -1
for name in pairs(seen) do nSeen = nSeen + 1; maxN = math.max(maxN, tonumber(name:match("_(%d+)$"))) end
check("all " .. C.OVERLAY_COUNT .. " layer sprites reachable, no extras (" .. nSeen .. ")", nSeen == C.OVERLAY_COUNT and maxN == C.OVERLAY_COUNT - 1)
local sick = newPlot(500, 500, 0); sick.state, sick.typeOfSeed, sick.nbOfGrow = "seeded", "Cannabis", 6
sick.health, sick.mildewLvl = 40, 0
-- no registry record -> a Hybrid-shaped green plant; nbOfGrow 6 = Flowering
check("unhealthy at health 40", plantSprite(sick) == C.overlaySprite(3, 1, 4, "unhealthySprite"))
sick.mildewLvl = 35
check("dying at mildew 35", plantSprite(sick) == C.overlaySprite(3, 1, 4, "dyingSprite"))
local tomatoPlot = newPlot(501, 500, 0); tomatoPlot.state, tomatoPlot.typeOfSeed, tomatoPlot.nbOfGrow = "seeded", "Hemp", 3
check("other crops use vanilla sprites", farming_vegetableconf.getSpriteName(tomatoPlot) == "h3")

-- ---- Cloning
-- ---------------------------------------------------------------
local CL = CannabisMod.Cloning
check("wilt: none in grace period", G.rootingOdds(0, { moist = true, wiltHours = 5 }) == 35)
check("wilt: -2/h after 6h", G.rootingOdds(0, { moist = true, wiltHours = 10 }) == 27)
check("soil penalty -10", G.rootingOdds(0, { moist = true, soil = true }) == 25)

check("kind: seed/cutting/rooted", S.kind(newItem(C.SEED_ITEM)) == "seed"
    and S.kind(newItem(C.CUTTING_ITEM)) == "cutting" and S.kind(newItem(C.ROOTED_ITEM)) == "rooted"
    and S.kind(newItem("Base.Apple")) == nil)
local spawned = S.getCuttingData(newItem(C.CUTTING_ITEM, 777))
check("spawned cutting: female gen-1 clone", spawned.sex == C.SEX.FEMALE and spawned.generation == 1
    and spawned.genetics >= 95 and spawned.genetics <= 99)

-- a mother in veg, a gardener with scissors
for k in pairs(store[C.MODDATA_KEY]) do store[C.MODDATA_KEY][k] = nil end
local momPlot = newPlot(600, 600, 0); local momSeed = newItem(C.SEED_ITEM)
S.setData(momSeed, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 92, generation = 2 })
local gardener = newPlayer(600, 601, 4)
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = momSeed, plant = { x = 600, y = 600, z = 0 }, character = gardener })
local mom = R.getPlant(600, 600, 0)
mom.stress = 10

fire("OnClientCommand", "CannabisMod", "takeCutting", gardener, { x = 600, y = 600, z = 0 })
check("no cutting from a seedling", gardener.inv:count(C.CUTTING_ITEM) == 0)
R.advanceStage(mom)  -- now Vegetative
fire("OnClientCommand", "CannabisMod", "takeCutting", gardener, { x = 600, y = 600, z = 0 })
check("no cutting without a tool", gardener.inv:count(C.CUTTING_ITEM) == 0)
local scissors = gardener.inv:addExisting(newItem("Base.Scissors")); scissors.tags["base:scissors"] = true
check("scissors count as a tool", S.findCuttingTool(gardener) == scissors)
fire("OnClientCommand", "CannabisMod", "takeCutting", gardener, { x = 600, y = 600, z = 0 })
check("cutting taken in veg", gardener.inv:count(C.CUTTING_ITEM) == 1)
local cut = S.findItem(gardener.inv, function(i) return S.kind(i) == "cutting" end)
local cd = S.getCuttingData(cut)
check("cutting: gen +1, drift 1-5, half stress, same type", cd.generation == 3 and cd.genetics >= 87
    and cd.genetics <= 91 and cd.stress == 5 and cd.type == T.INDICA and not cd.gel)
check("mother stressed by cutting", mom.stress == 13)
local far = newPlayer(650, 650, 4); far.inv:addExisting(scissors)
fire("OnClientCommand", "CannabisMod", "takeCutting", far, { x = 600, y = 600, z = 0 })
check("too far away: no cutting", far.inv:count(C.CUTTING_ITEM) == 0)
gardener.inv:addExisting(scissors)
R.advanceStage(mom); R.advanceStage(mom)  -- Flowering
fire("OnClientCommand", "CannabisMod", "takeCutting", gardener, { x = 600, y = 600, z = 0 })
check("no cutting in flower", gardener.inv:count(C.CUTTING_ITEM) == 1)

-- rooting gel: the cutting is swapped for a dipped one of the same age
cut.age = 0.25
fire("OnClientCommand", "CannabisMod", "dipInGel", gardener, { id = cut:getID() })
check("no gel: not dipped", not S.getCuttingData(S.findItem(gardener.inv, S.isUsableCutting)).gel)
local gel = gardener.inv:addExisting(newItem(C.GEL_ITEM))
fire("OnClientCommand", "CannabisMod", "dipInGel", gardener, { id = cut:getID() })
local dipped = S.findItem(gardener.inv, S.isUsableCutting)
check("dipped: gel flag, same age, old item gone", S.getCuttingData(dipped).gel and dipped.age == 0.25
    and dipped ~= cut and gardener.inv:count(C.CUTTING_ITEM) == 1)
check("gel used once", gel.uses == 9)
check("dipped keeps genetics", S.getCuttingData(dipped).genetics == cd.genetics)

-- cloning dome: a container item. Cuttings are moved in like a bag, then the client sends domeSync.
local dome = gardener.inv:addExisting(newItem(C.DOME_ITEM))
local domeInv = newContainer()
dome.getInventory = function() return domeInv end
dome.getWorldItem = function() return nil end
for i = 1, 12 do domeInv:addExisting(newItem(C.CUTTING_ITEM)) end
domeInv:addExisting(dipped)
local rotten = domeInv:addExisting(newItem(C.CUTTING_ITEM)); rotten.rotten = true
fire("OnClientCommand", "CannabisMod", "domeSync", gardener, { domeId = dome:getID() })
local list = R.getDome(dome:getID())
check("dome records every cutting inside (14)", #list == 14)
check("rotten cutting can never root", (function()
    for _, e in ipairs(list) do if e.id == rotten:getID() then return e.success == false end end
end)())
local gelEntry = 0
for _, e in ipairs(list) do if e.data.gel then gelEntry = gelEntry + 1 end end
check("dipped cutting keeps gel in its record", gelEntry == 1)
domeInv:Remove(rotten)
fire("OnClientCommand", "CannabisMod", "domeSync", gardener, { domeId = dome:getID() })
list = R.getDome(dome:getID())
check("removed cutting drops from the dome record", #list == 13)

fire("OnClientCommand", "CannabisMod", "domeTake", gardener, { domeId = dome:getID() })
check("nothing ready yet", gardener.inv:count(C.ROOTED_ITEM) == 0 and #R.getDome(dome:getID()) == 13)
local p0, r0, f0 = CL.domeStatus(list, worldHours)
check("all 13 pending", p0 == 13 and r0 == 0 and f0 == 0)
for i, e in ipairs(list) do e.success = i <= 9 end     -- 9 root, 4 fail
worldHours = worldHours + 48
fire("OnClientCommand", "CannabisMod", "domeCheck", gardener, { domeId = dome:getID() })
check("check reports rooted/failed", sent[#sent].data.text:find("9 rooted") and sent[#sent].data.text:find("4 didn't root"))
fire("OnClientCommand", "CannabisMod", "domeTake", gardener, { domeId = dome:getID() })
check("took 9 rooted, dome emptied", gardener.inv:count(C.ROOTED_ITEM) == 9 and #R.getDome(dome:getID()) == 0 and #domeInv.items == 0)
local rootedItem = S.findItem(gardener.inv, function(i) return S.kind(i) == "rooted" end)
check("rooted cutting keeps lineage", S.getCuttingData(rootedItem).type ~= nil and S.getCuttingData(rootedItem).strain ~= nil)

-- a cutting taken out of the dome by hand drops its record
local d2 = gardener.inv:addExisting(newDome())
local c2 = newItem(C.CUTTING_ITEM); d2:getInventory():addExisting(c2)
fire("OnClientCommand", "CannabisMod", "domeSync", gardener, { domeId = d2:getID() })
check("record created", #R.getDome(d2:getID()) == 1)
d2:getInventory():Remove(c2)
fire("OnClientCommand", "CannabisMod", "domeSync", gardener, { domeId = d2:getID() })
check("record dropped when cutting removed", #R.getDome(d2:getID()) == 0)

-- a dome keeps rooting cuttings fresh; ones that won't root still wilt
do
    local d3 = gardener.inv:addExisting(newDome())
    local good, bad = newItem(C.CUTTING_ITEM), newItem(C.CUTTING_ITEM)
    good.age, bad.age = 0.2, 0.2
    d3:getInventory():addExisting(good); d3:getInventory():addExisting(bad)
    fire("OnClientCommand", "CannabisMod", "domeSync", gardener, { domeId = d3:getID() })
    for _, e in ipairs(R.getDome(d3:getID())) do e.success = (e.id == good:getID()) end
    good.age, bad.age = 2.5, 2.5
    CL.holdDomes()
    check("rooting cutting in a dome doesn't age", good.age == 0.2)
    check("cutting that won't root still ages", bad.age == 2.5)
end

-- a dipped cutting is labelled
local dippedCut = S.findItem(gardener.inv, function(i) return i.name == "Cannabis Cutting (Rooting Gel)" end)
check("dipped cutting renamed", dipped.name == "Cannabis Cutting (Rooting Gel)")

-- planting a rooted cutting: starts in veg, no rooting wait
local rcPlot = newPlot(610, 600, 0)
local rcItem = newItem(C.ROOTED_ITEM)
S.setCuttingData(rcItem, { type = T.SATIVA, sex = C.SEX.FEMALE, genetics = 80, generation = 4, stress = 6 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = rcItem, plant = { x = 610, y = 600, z = 0 }, character = gardener })
local rc = R.getPlant(610, 600, 0)
check("rooted cutting planted in veg", rc.stage == C.STAGE.Vegetative and rc.generation == 4
    and rc.stress == 6 and not rc.rooting and plantSprite(rcPlot) == C.overlaySprite(shapeAt(610, 600, 0), 1, 2, "sprite"))

-- sticking a fresh cutting in soil: growth waits for rooting
local scPlot = newPlot(620, 600, 0)
local scItem = newItem(C.CUTTING_ITEM); scItem.age = 0.1
S.setCuttingData(scItem, { type = T.HYBRID, sex = C.SEX.FEMALE, genetics = 90, generation = 2 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = scItem, plant = { x = 620, y = 600, z = 0 }, character = gardener })
local sc = R.getPlant(620, 600, 0)
check("soil cutting is rooting", sc.rooting ~= nil and sc.stage == C.STAGE.Vegetative)
check("veg timer starts after rooting", sc.nextStageAt > sc.rooting.readyAt)
check("info shows rooting to anyone", I.buildVisible(sc, 0, worldHours).rooting == "Still rooting")
sc.rooting.success = true
local readyAt = sc.rooting.readyAt
worldHours = readyAt - 1; fire("EveryTenMinutes")
check("still rooting before time", sc.rooting ~= nil and sc.stage == C.STAGE.Vegetative)
worldHours = readyAt + 0.1; fire("EveryTenMinutes")
check("rooted: growth resumes", sc.rooting == nil and not sc.dead)

local fcPlot = newPlot(630, 600, 0)
local fcItem = newItem(C.CUTTING_ITEM)
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = fcItem, plant = { x = 630, y = 600, z = 0 }, character = gardener })
local fc = R.getPlant(630, 600, 0)
local killed = false
function fcPlot:killThis() killed = true; self.state = "dead" end
fc.rooting.success = false
worldHours = fc.rooting.readyAt + 0.1; fire("EveryTenMinutes")
check("failed soil cutting dies on its plot", killed and fc.dead)

-- debug kit
local dbg = newPlayer(700, 700, 1)
fire("OnClientCommand", "CannabisMod", "debugCloningKit", dbg, {})
check("debug kit: dome tray, gel, 3 cuttings", dbg.inv:count(C.DOME_ITEM) == 1 and dbg.inv:count(C.GEL_ITEM) == 1
    and dbg.inv:count(C.CUTTING_ITEM) == 3)

-- ---- Debug commands ------------------------------------------------------
local tester = newPlayer(430, 430, 3)
fire("OnClientCommand", "CannabisMod", "debugGiveSeeds", tester, {})
local males, perStrain = 0, {}
for _, it in ipairs(tester.inv.items) do
    local d = S.getData(it)
    if d.sex == C.SEX.MALE then males = males + 1 end
    perStrain[d.strain.name] = (perStrain[d.strain.name] or 0) + (d.sex == C.SEX.MALE and 10 or 1)
end
local allThree = true
for _, st in ipairs(CannabisMod.Strains.STARTERS) do if perStrain[st.name] ~= 12 then allThree = false end end
check("debug seeds: 2 female and 1 male of each starter", #tester.inv.items == 3 * #CannabisMod.Strains.STARTERS
    and males == #CannabisMod.Strains.STARTERS and allThree)
local plotD = newPlot(430, 430, 0)
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = tester.inv.items[1], plant = { x = 430, y = 430, z = 0 } })
fire("OnClientCommand", "CannabisMod", "debugNextStage", tester, { x = 430, y = 430, z = 0 })
check("debug next stage", R.getPlant(430, 430, 0).stage == 2 and plotD.nbOfGrow == 3)


;(function() -- second half of the suite in its own scope (Lua allows 200 locals per function)
-- ---- Feeding -----------------------------------------------------------
local feeder = newPlayer(800, 800, 5)
local fPlot = newPlot(800, 800, 0); local fSeed = newItem(C.SEED_ITEM)
S.setData(fSeed, { type = T.HYBRID, sex = C.SEX.FEMALE, genetics = 100 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = fSeed, plant = { x = 800, y = 800, z = 0 } })
local fRec = R.getPlant(800, 800, 0)
local fargs = { x = 800, y = 800, z = 0, nutrient = "Veg" }
fire("OnClientCommand", "CannabisMod", "feedPlant", feeder, fargs)
check("seedlings aren't fed", sent[#sent].data.text:find("doesn't need") and fRec.fedThisStage == 0)
R.advanceStage(fRec)  -- Vegetative
fire("OnClientCommand", "CannabisMod", "feedPlant", feeder, fargs)
check("no bottle: refused", sent[#sent].data.text:find("no Veg") and fRec.fedThisStage == 0)
feeder.inv:addExisting(newItem(C.NUTRIENT_ITEMS.Veg)); feeder.inv:addExisting(newItem(C.NUTRIENT_ITEMS.Veg))
feeder.inv:addExisting(newItem(C.NUTRIENT_ITEMS.Bloom))
fRec.care = 90
fire("OnClientCommand", "CannabisMod", "feedPlant", feeder, fargs)
check("right food: bonus, bottle used", fRec.care == 90 + C.Care.RIGHT_NUTRIENT_BONUS and feeder.inv:count(C.NUTRIENT_ITEMS.Veg) == 1)
fire("OnClientCommand", "CannabisMod", "feedPlant", feeder, fargs)
check("second feed in a stage burns", fRec.warnings.nutrientBurn == true and feeder.inv:count(C.NUTRIENT_ITEMS.Veg) == 0)
local careBefore = fRec.care
fRec.fedThisStage = 0
fire("OnClientCommand", "CannabisMod", "feedPlant", feeder, { x = 800, y = 800, z = 0, nutrient = "Bloom" })
check("wrong food in veg: penalty", fRec.care == careBefore - C.Care.WRONG_NUTRIENT and fRec.warnings.wrongNutrient)
local far = newPlayer(900, 900, 5)
far.inv:addExisting(newItem(C.NUTRIENT_ITEMS.Veg))
fire("OnClientCommand", "CannabisMod", "feedPlant", far, fargs)
check("too far away: ignored", far.inv:count(C.NUTRIENT_ITEMS.Veg) == 1)

-- ---- Grow lights ---------------------------------------------------------
-- A tiny fake world: squares know if they're outside, powered, and what items
-- lie on them.
local fakeSquares = {}
local function fakeSquare(x, y, z, outside, power)
    local sq = { x = x, y = y, z = z, outside = outside, power = power, items = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getFloor() return {} end
    function sq:isSolid() return false end
    function sq:isSolidTrans() return false end
    function sq:HasStairs() return false end
    function sq:isOutside() return self.outside end
    function sq:haveElectricity() return self.power end
    sq.objs = {}  -- placed furniture, by sprite name
    function sq:RemoveTileObject(obj)
        for i, e in ipairs(self.objs) do if e == obj.entry then table.remove(self.objs, i) break end end
    end
    function sq:transmitRemoveItemFromSquare() end
    function sq:AddWorldInventoryItem(fullType) self.items[#self.items + 1] = newItem(fullType) end
    function sq:getObjects()
        local list = self.objs
        return { size = function() return #list end,
                 get = function(_, i) local e = list[i + 1]
                     local n = type(e) == "table" and e.sprite or e
                     return { getSprite = function() return { getName = function() return n end } end,
                              getContainer = function() return type(e) == "table" and e.container or nil end,
                              getSquare = function() return sq end, entry = e,
                              getModData = function() if type(e) == "table" then e.md = e.md or {} return e.md end return {} end,
                              transmitModData = function() end } end }
    end
    function sq:getWorldObjects()
        local list = self.items
        return { size = function() return #list end,
                 get = function(_, i) local it = list[i + 1]; return { getItem = function() return it end } end }
    end
    fakeSquares[x .. "_" .. y .. "_" .. z] = sq
    return sq
end
function getCell() return { getGridSquare = function(_, x, y, z) return fakeSquares[x .. "_" .. y .. "_" .. z] end } end
function getWorld() return { isHydroPowerOn = function() return false end } end

local L = CannabisMod.Light
local outdoor = { x = 1, y = 1, z = 0, warnings = {}, stage = 2, care = 100, stress = 0, lightCap = 70 }
fakeSquare(1, 1, 0, true, false)
local cap, src = L.measure(outdoor)
check("outdoors: sunlight 70", cap == 70 and src == "Sun")

local indoor = { x = 10, y = 10, z = 0, warnings = {}, stage = 2, care = 100, stress = 0, lightCap = 70, nextStageAt = 100 }
local room = fakeSquare(10, 10, 0, false, false)
cap, src = L.measure(indoor)
check("indoors, no lamp: dark", cap == 0 and src == "None")
local lamp = newItem("CannabisMod.GrowLampPro")
room.items[1] = lamp
cap, src = L.measure(indoor)
check("lamp without power does nothing", cap == 0)
room.power = true
cap, src = L.measure(indoor)
check("powered pro lamp: 100", cap == 100 and src == "Pro grow lamp")
room.items[2] = newItem("CannabisMod.GrowLampBasic")
check("best lamp wins", select(1, L.measure(indoor)) == 100)
local nextRoom = fakeSquare(32, 10, 0, false, true)
nextRoom.items[1] = newItem("CannabisMod.GrowLampBasic")
local nearPlant = { x = 33, y = 10, z = 0, warnings = {}, stage = 2 }
fakeSquare(33, 10, 0, false, true)
check("lamp within 2 tiles reaches the plant", select(1, L.measure(nearPlant)) == 85)
local farPlant = { x = 36, y = 10, z = 0, warnings = {}, stage = 2 }
fakeSquare(36, 10, 0, false, true)
check("lamp 4 tiles away doesn't", select(1, L.measure(farPlant)) == 0)

-- Placed (furniture) lamps: each reaches its own radius
local lampSq = fakeSquare(200, 200, 0, false, true)
local function plantAt(dx) fakeSquare(200 + dx, 200, 0, false, true); return { x = 200 + dx, y = 200, z = 0, warnings = {}, stage = 2 } end
lampSq.objs[1] = "dazeddank_plants_01_197"  -- Basic, radius 2
fire("LoadGridsquare", lampSq)  -- announce the placed lamp to the light index
check("placed basic lamp: 2 tiles", select(1, L.measure(plantAt(2))) == 85)
check("placed basic lamp: not 3 tiles", select(1, L.measure(plantAt(3))) == 0)
lampSq.objs[1] = "dazeddank_plants_01_198"  -- Pro, radius 2.5
check("pro lamp reaches 2 tiles at 100", select(1, L.measure(plantAt(2))) == 100)
check("pro lamp not 3 tiles", select(1, L.measure(plantAt(3))) == 0)
lampSq.objs[1] = "dazeddank_plants_01_199"  -- Large basic, radius 3
check("large basic: 3 tiles at 85", select(1, L.measure(plantAt(3))) == 85)
lampSq.objs[1] = "dazeddank_plants_01_200"  -- Large pro, radius 4
check("large pro: 4 tiles at 100", select(1, L.measure(plantAt(4))) == 100)
check("large pro: not 5 tiles", select(1, L.measure(plantAt(5))) == 0)
lampSq.objs[1] = "dazeddank_plants_01_234"  -- Flood light, radius 3.5
check("flood light: 3 tiles at 85", select(1, L.measure(plantAt(3))) == 85)
check("flood light: not 4 tiles", select(1, L.measure(plantAt(4))) == 0)
lampSq.objs[1] = "dazeddank_plants_01_235"  -- Pro flood light, radius 4.5
check("pro flood light: 4 tiles at 100", select(1, L.measure(plantAt(4))) == 100)
check("pro flood light: not 5 tiles", select(1, L.measure(plantAt(5))) == 0)
-- A plant out of loaded range keeps its last light reading instead of reading as sunlit.
do
    local inRoom = { x = 210, y = 200, z = 0, warnings = {}, stage = 2, care = 100, stress = 0, lightCap = 85 }
    fakeSquare(210, 200, 0, false, true)
    local lamp = fakeSquare(209, 200, 0, false, true)
    lamp.objs[1] = "dazeddank_plants_01_197"
    fire("LoadGridsquare", lamp)  -- announce the placed lamp to the light index
    L.update(inRoom)
    local cycle, cap = inRoom.lightCycle, inRoom.lightCap
    fakeSquares["210_200_0"] = nil
    local stalled = L.update(inRoom)
    fakeSquares["210_200_0"] = fakeSquare(210, 200, 0, false, true)
    check("an unloaded indoor plant keeps its lamp reading and isn't stalled", not stalled and inRoom.lightCycle == cycle
        and inRoom.lightCap == cap and inRoom.lightSource ~= "Sun")
    lamp.objs[1] = nil
end

-- Lamp squares are read once per plant tick and shared: a change mid-tick isn't seen until the next one.
do
    local sq = fakeSquare(220, 200, 0, false, true)
    fakeSquare(221, 200, 0, false, true)
    L.beginTick()
    local before = select(1, L.measure({ x = 221, y = 200, z = 0, warnings = {} }))
    sq.objs[1] = "dazeddank_plants_01_198"
    fire("LoadGridsquare", sq)  -- announce the placed lamp to the light index
    local during = select(1, L.measure({ x = 221, y = 200, z = 0, warnings = {} }))
    L.endTick()
    local after = select(1, L.measure({ x = 221, y = 200, z = 0, warnings = {} }))
    check("lamp squares are shared within a tick and fresh after it", before == 0 and during == 0 and after == 100)
    sq.objs[1] = nil
end

-- Placed lamps reach the light scan through the lamp index: placing adds a tile, and a lamp taken away drops out.
do
    local sq = fakeSquare(230, 200, 0, false, true)
    fakeSquare(231, 200, 0, false, true)
    local plant = { x = 231, y = 200, z = 0, warnings = {} }
    sq.objs[1] = "dazeddank_plants_01_198"
    check("lamp index: a lamp no event announced is not read", select(1, L.measure(plant)) == 0)
    fire("OnObjectAdded", sq:getObjects():get(0))
    check("lamp index: a placed lamp lights the plant", select(1, L.measure(plant)) == 100)
    sq.objs[1] = nil
    check("lamp index: a lamp taken away stops lighting", select(1, L.measure(plant)) == 0)
    sq.objs[1] = "dazeddank_plants_01_198"
    check("lamp index: the emptied tile left the index", select(1, L.measure(plant)) == 0)
    sq.objs[1] = nil
end

-- Outdoors a lit flood light supplements the sun.
local yard = fakeSquare(400, 400, 0, true, true)
local function yardPlant(dx) fakeSquare(400 + dx, 400, 0, true, false); return { x = 400 + dx, y = 400, z = 0, warnings = {}, stage = 2 } end
yard.objs[1] = "dazeddank_plants_01_234"
fire("LoadGridsquare", yard)  -- announce the placed lamp to the light index
local yc, ysrc = L.measure(yardPlant(2))
check("outdoors, sun + basic flood: stronger light plus a boost", yc == 85 + C.LightCap.SUN_BOOST and ysrc:find("^Sun %+"))
yard.objs[1] = "dazeddank_plants_01_235"
check("outdoors, sun + pro flood stops at 100", select(1, L.measure(yardPlant(2))) == 100)
check("outdoors, out of the flood's reach: sun only", select(1, L.measure(yardPlant(6))) == C.LightCap.SUN)
yard.power = false
check("outdoors, an unpowered flood adds nothing", select(1, L.measure(yardPlant(2))) == C.LightCap.SUN)
check("flood lights are floor lamps, ceiling lamps are not", C.Light.SPRITES["dazeddank_plants_01_234"].floor and C.Light.SPRITES["dazeddank_plants_01_235"].floor and not C.Light.SPRITES["dazeddank_plants_01_197"].floor)
check("lamp zone is round", not C.Light.reaches(2, 2, 2) and C.Light.reaches(2, 1, 2.5) and C.Light.reaches(0, 2, 2))
lampSq.power = false
check("placed lamp needs power", select(1, L.measure(plantAt(1))) == 0)
lampSq.objs[1] = "dazeddank_plants_01_3"  -- some other sprite
lampSq.power = true
check("non-lamp sprite is ignored", select(1, L.measure(plantAt(1))) == 0)

-- Running light score drifts toward the current ceiling
indoor.lightCap = 70
for i = 1, 120 do L.update(indoor) end
check("score climbs toward lamp ceiling (" .. string.format("%.1f", indoor.lightCap) .. ")", indoor.lightCap > 88 and indoor.lightCap < 100)

-- Power cut: stalls, loses care, timer frozen
room.power = false
local nextBefore, careBefore2 = indoor.nextStageAt, indoor.care
local stalled = L.update(indoor)
check("dark indoor plant stalls", stalled and indoor.nextStageAt > nextBefore and indoor.care < careBefore2 and indoor.warnings.noLight)
-- Flowering interruption
local flower = { x = 10, y = 10, z = 0, warnings = {}, stage = C.STAGE.Flowering, care = 100, stress = 0, lightCap = 100, lightOn = true }
L.update(flower)
check("flowering light interruption penalised", flower.warnings.lightInterrupted and flower.care < 100 - C.Care.LIGHT_INTERRUPTION + 1)
room.power = true
L.update(flower)
check("light back: warnings clear", flower.warnings.noLight == nil and flower.warnings.lightInterrupted == nil and flower.lightOn)

-- The 10-minute tick holds a stalled plant's stage
local gPlot = newPlot(10, 10, 0); local gSeed = newItem(C.SEED_ITEM)
S.setData(gSeed, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = gSeed, plant = { x = 10, y = 10, z = 0 } })
local gRec = R.getPlant(10, 10, 0)
room.power = false
local stageBefore = gRec.stage
worldHours = gRec.nextStageAt + 5
fire("EveryTenMinutes")
check("stalled plant doesn't advance when its timer is up", gRec.stage == stageBefore)
room.power = true
fire("EveryTenMinutes")
check("with light again it can advance", gRec.stage == stageBefore + 1 or gRec.nextStageAt > worldHours)


-- ---- Grow bags -----------------------------------------------------------
do
local G = CannabisMod.GrowBags
local bagger = newPlayer(50, 50, 6)
fakeSquare(50, 50, 0, false, true)
local function placeBag(x, y, size) return G.makePlot(getCell():getGridSquare(x, y, 0), size) end
placeBag(50, 50, "small")
local bagPlot = SFarmingSystem.instance:getLuaObjectAt(50, 50, 0)
check("bag placed indoors makes a plot", bagPlot and bagPlot.state == "plow" and R.getBag(50, 50, 0) == "small")
check("new bag is unfilled: dry sprite, needs-soil name", bagPlot.spriteName == "dazeddank_plants_01_201"
    and bagPlot.objectName == "Small Grow Bag, needs soil" and C.bagIsUnfilled(bagPlot.spriteName))
check("unfilled sprites still read as bags", C.bagFromSprite("dazeddank_plants_01_201") == "small" and C.bagFromSprite("dazeddank_plants_01_202") == "large")
-- sowing needs soil first
local dSeed = newItem(C.SEED_ITEM); S.setData(dSeed, { type = T.SATIVA, sex = C.SEX.FEMALE, genetics = 100 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = dSeed, plant = { x = 50, y = 50, z = 0 }, character = bagger })
check("can't sow into a bag with no soil", R.getPlant(50, 50, 0) == nil and sent[#sent].data.text:find("soil first"))
fire("OnClientCommand", "CannabisMod", "fillGrowBag", bagger, { x = 50, y = 50, z = 0 })
check("fill without a sack is refused", not R.isBagSoiled(50, 50, 0) and sent[#sent].data.text:find("sack of soil"))
bagger.inv:addExisting(newItem("CannabisMod.SoilSack"))
fire("OnClientCommand", "CannabisMod", "fillGrowBag", bagger, { x = 50, y = 50, z = 0 })
check("small bag takes 1 sack and is filled", R.isBagSoiled(50, 50, 0) and bagger.inv:count("CannabisMod.SoilSack") == 0)
check("filled bag shows soil sprite and normal name", bagPlot.spriteName == "dazeddank_plants_01_195" and bagPlot.objectName == "Small Grow Bag")
bagger.inv:addExisting(newItem("CannabisMod.SoilSack"))
fire("OnClientCommand", "CannabisMod", "fillGrowBag", bagger, { x = 50, y = 50, z = 0 })
check("can't fill twice", bagger.inv:count("CannabisMod.SoilSack") == 1 and sent[#sent].data.text:find("already"))
check("vanilla dirt bag counts as soil", C.isSoilItem("Base.Dirtbag") and not C.isSoilItem("Base.Dirt"))
check("client can tell it's a bag from its sprite", C.bagFromSprite(bagPlot.spriteName) == "small"
    and C.bagFromSprite("dazeddank_plants_01_196") == "large" and C.bagFromSprite(C.FURROW_SPRITE) == nil
    and C.bagFromSprite("dazeddank_overlay_01_12") == nil
    and C.bagFromSprite("vegetation_farming_01_1") == nil)

-- sow into the bag: sprite is the bag version, plant remembers its bag
local bSeed = newItem(C.SEED_ITEM)
S.setData(bSeed, { type = T.SATIVA, sex = C.SEX.FEMALE, genetics = 100 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = bSeed, plant = { x = 50, y = 50, z = 0 } })
local bRec = R.getPlant(50, 50, 0)
check("plant records its bag", bRec.bag == "small")
check("seedling in a small bag keeps the bag sprite", bagPlot.spriteName == C.bagEmptySprite("small", true)
    and C.bagFromSprite(bagPlot.spriteName) == "small")
check("info shows the container", I.buildVisible(bRec, 0, 0).container == "Small Grow Bag"
    and I.buildVisible(R.getPlant(800, 800, 0), 0, 0).container == "Ground")
-- large bag needs 2 sacks
fakeSquare(55, 55, 0, false, true)
local lg = newPlayer(55, 55, 5)
placeBag(55, 55, "large")
lg.inv:addExisting(newItem("CannabisMod.SoilSack"))
fire("OnClientCommand", "CannabisMod", "fillGrowBag", lg, { x = 55, y = 55, z = 0 })
check("large bag with 1 sack refused", not R.isBagSoiled(55, 55, 0) and lg.inv:count("CannabisMod.SoilSack") == 1)
lg.inv:addExisting(newItem("CannabisMod.SoilSack"))
fire("OnClientCommand", "CannabisMod", "fillGrowBag", lg, { x = 55, y = 55, z = 0 })
check("large bag takes 2 sacks", R.isBagSoiled(55, 55, 0) and lg.inv:count("CannabisMod.SoilSack") == 0)
check("large bag plants use the standard layers", C.overlaySprite(4, 1, 4, "sprite", "large") == C.overlaySprite(4, 1, 4, "sprite"))
-- breathing: overwater hurts less in a bag
local wetG = { stage = 3, water = 100, care = 100, stress = 0, warnings = {}, bag = nil }
local wetB = { stage = 3, water = 100, care = 100, stress = 0, warnings = {}, bag = "large" }
R.waterCheck(wetG); R.waterCheck(wetB)
check("bag takes less overwater damage", wetB.care > wetG.care)

-- picking up needs an empty bag
fire("OnClientCommand", "CannabisMod", "pickUpGrowBag", bagger, { x = 50, y = 50, z = 0 })
check("can't pick up a planted bag", R.getBag(50, 50, 0) == "small")

-- harvest leaves the bag, emptied
for i = 1, 4 do R.advanceStage(bRec) end
SFarmingSystem.harvest(SFarmingSystem.instance, bagPlot, bagger)
check("harvest keeps the bag plot", SFarmingSystem.instance:getLuaObjectAt(50, 50, 0) == bagPlot and not bagPlot.removed)
check("bag is empty again", bagPlot.state == "plow" and R.getPlant(50, 50, 0) == nil and R.getBag(50, 50, 0) == "small")
check("bag shows the empty sprite again", bagPlot.spriteName == "dazeddank_plants_01_195")

-- the large bag gives more buds
local function harvestBuds(size)
    local sq = size == "large" and 60 or 70
    fakeSquare(sq, sq, 0, false, true)
    local pl = newPlayer(sq, sq, 5)
    placeBag(sq, sq, size)
    for _ = 1, C.GrowBag[size].soil do pl.inv:addExisting(newItem("CannabisMod.SoilSack")) end
    fire("OnClientCommand", "CannabisMod", "fillGrowBag", pl, { x = sq, y = sq, z = 0 })
    local sd = newItem(C.SEED_ITEM); S.setData(sd, { type = T.HYBRID, sex = C.SEX.FEMALE, genetics = 100 })
    ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = sd, plant = { x = sq, y = sq, z = 0 } })
    local rec = R.getPlant(sq, sq, 0)
    for i = 1, 4 do R.advanceStage(rec) end
    rec.lightCap = 100
    SFarmingSystem.harvest(SFarmingSystem.instance, SFarmingSystem.instance:getLuaObjectAt(sq, sq, 0), pl)
    return pl.inv.items[#pl.inv.items]:getModData().CannabisHarvest.budYield
end
local smallTotal, largeTotal = 0, 0
for i = 1, 30 do
    -- each run uses fresh squares so plots don't collide
    smallTotal = smallTotal + harvestBuds("small")
    largeTotal = largeTotal + harvestBuds("large")
end
check("large bags out-yield small (" .. largeTotal .. " vs " .. smallTotal .. ")", largeTotal > smallTotal)

-- empty an expired plant, then pick the empty bag up
local dSeed = newItem(C.SEED_ITEM); S.setData(dSeed, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = dSeed, plant = { x = 50, y = 50, z = 0 } })
fire("OnClientCommand", "CannabisMod", "emptyGrowBag", bagger, { x = 50, y = 50, z = 0 })
check("live plant can't be emptied out", bagPlot.state ~= "plow")
bagPlot.state = "dead"
fire("OnClientCommand", "CannabisMod", "emptyGrowBag", bagger, { x = 50, y = 50, z = 0 })
check("dead plant cleared from the bag", bagPlot.state == "plow" and R.getPlant(50, 50, 0) == nil)
-- vanilla shovel removal of a dead plant in a bag empties the bag instead of deleting it
local sSeed = newItem(C.SEED_ITEM); S.setData(sSeed, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = sSeed, plant = { x = 50, y = 50, z = 0 } })
bagPlot.state = "dead"
SFarmingSystem.instance:removePlant(bagPlot)
check("shovel-removing a dead plant keeps the bag", not bagPlot.removed and bagPlot.state == "plow"
    and R.getPlant(50, 50, 0) == nil and R.getBag(50, 50, 0) == "small" and R.isBagSoiled(50, 50, 0))
fire("OnClientCommand", "CannabisMod", "emptyGrowBag", bagger, { x = 50, y = 50, z = 0 })
check("emptying an empty bag says so", sent[#sent].data.text:find("already empty"))
fire("OnClientCommand", "CannabisMod", "pickUpGrowBag", bagger, { x = 50, y = 50, z = 0 })
check("empty bag picked up and returned", R.getBag(50, 50, 0) == nil and bagger.inv:count(C.GrowBag.small.furnItem) == 1
    and SFarmingSystem.instance:getLuaObjectAt(50, 50, 0) == nil)

-- upkeep: a bag whose plot vanished is forgotten
R.setBag(99, 99, 0, "large")
fire("EveryTenMinutes")
check("orphan bag record cleaned up", R.getBag(99, 99, 0) == nil)

end

-- ---- Drying, trimming and curing -----------------------------------------
do
local Dr = CannabisMod.Drying
local base = { hours = 0 }
check("rushed dry hurts, full dry doesn't", G.driedQuality(80, { hours = 0 }) == 48 and G.driedQuality(80, { hours = 48 }) == 80)
check("over-drying costs quality, floor 70%", G.driedQuality(80, { hours = 200 }) < 80 and G.driedQuality(100, { hours = 5000 }) == 70)
check("mold ruins it, sun bleaches it", G.driedQuality(80, { hours = 48, moldy = true }) == 16 and G.driedQuality(80, { hours = 48, sunLoss = 0.25 }) == 60)
check("curing adds up to 10%", G.curedQuality(80, 6 * 24) == 88 and G.curedQuality(80, 0) == 80 and G.curedQuality(80, 5000) == 88)
check("cured mold applied once", G.curedQuality(80, 0, true, false) == 16 and G.curedQuality(16, 0, true, true) == 16)
check("quality tiers", C.qualityTier(90) == "Premium" and C.qualityTier(70) == "Good" and C.qualityTier(45) == "Average" and C.qualityTier(10) == "Poor")
check("warm air dries faster, a fan helps", Dr.dryRate({ tempC = 28 }) > Dr.dryRate({ tempC = 18 }) and Dr.dryRate({ tempC = 18, fan = true }) > 1)
local calm = Dr.moldPerHour({ tempC = 18 }, 1)
check("fan cuts mold, rain and warmth raise it", Dr.moldPerHour({ tempC = 18, fan = true }, 1) < calm
    and Dr.moldPerHour({ tempC = 18, outdoors = true, rain = true }, 1) > calm and Dr.moldPerHour({ tempC = 30 }, 1) > calm)
check("dry plants rarely mold", Dr.moldPerHour({ tempC = 18 }, 0) < calm)

local function newStation(fullType)
    local it = newItem(fullType)
    local inv = newContainer()
    inv.getContainingItem = function() return it end
    it.getInventory = function() return inv end
    return it
end
local function placeRack(sq, sprite)
    local c = newContainer()
    sq.objs[#sq.objs + 1] = { sprite = sprite or "dazeddank_plants_01_206", container = c }
    return c
end
local roomSq = fakeSquare(300, 300, 0, false, true)
local cook = newPlayer(300, 300, 5)
function getSpecificPlayer(i) if i == 0 then return cook end end
local rack = placeRack(roomSq)
local wets = {}
for i = 1, 2 do
    local w = rack:addExisting(newItem(C.WET_PLANT_ITEMS.Indica))
    w:getModData().CannabisHarvest = { type = "Indica", quality = 80, budYield = 3, genetics = 80 }
    wets[i] = w
end
SandboxVars = { CannabisMod = { MoldChance = 0 } }   -- no random mold in the basic flow
worldHours = 1000
fire("EveryOneMinute")
fire("EveryTenMinutes")
local dd = Dr.data()
check("rack found near the player and plants noticed", dd.stations["300_300_0"] and dd.plants[wets[1]:getID()] and dd.plants[wets[1]:getID()].hours == 0)
worldHours = 1024; fire("EveryTenMinutes")
check("24 hours passes: plants are 24h dry", math.abs(dd.plants[wets[1]:getID()].hours - 24) < 0.01)
worldHours = 1060; fire("EveryTenMinutes")
local driedNow = {}
for _, it in ipairs(rack.items) do driedNow[#driedNow + 1] = it end
check("finished plants become dried items", #driedNow == 2 and C.isDriedPlant(driedNow[1]:getFullType())
    and C.isDriedPlant(driedNow[2]:getFullType()) and driedNow[1]:getModData().CannabisHarvest.type == "Indica"
    and dd.plants[wets[1]:getID()] == nil)
wets = driedNow
check("keeps drying: 60h", math.abs(dd.plants[wets[1]:getID()].hours - 60) < 0.01)
fire("OnClientCommand", "CannabisMod", "checkRack", cook, { x = 300, y = 300, z = 0 })
check("check rack reports dry", sent[#sent].data.text:find("Rack:") and sent[#sent].data.text:find("dry"))

-- a plant taken out stops drying, and one put back resumes from where it was
local takenOut = wets[2]
rack:Remove(takenOut)
worldHours = 1100; fire("EveryTenMinutes")
check("removed plant stopped drying", math.abs(dd.plants[takenOut:getID()].hours - 60) < 0.01)
rack:addExisting(takenOut)
worldHours = 1110; fire("EveryTenMinutes")
check("put back: no catch-up for time away", math.abs(dd.plants[takenOut:getID()].hours - 60) < 0.01)

-- mold, forced by the sandbox multiplier (the trimming test below uses the clean first rack)
dd.stations["300_300_0"] = nil   -- stop tracking the first rack for this part
SandboxVars = { CannabisMod = { MoldChance = 100000 } }
local moldSq = fakeSquare(310, 300, 0, false, true)
local moldRack = placeRack(moldSq)
local mw = moldRack:addExisting(newItem(C.WET_PLANT_ITEMS.Hybrid))
mw:getModData().CannabisHarvest = { type = "Hybrid", quality = 80, budYield = 2 }
cook = newPlayer(310, 300, 5)
worldHours = 1200; fire("EveryOneMinute"); fire("EveryTenMinutes")
worldHours = 1260; fire("EveryTenMinutes")
check("a damp rack grows mold", dd.plants[moldRack.items[1]:getID()].moldy == true)
SandboxVars = { CannabisMod = { MoldChance = 0 } }

-- trimming
local trimmer = newPlayer(300, 300, 8)
rack:Remove(wets[1]); trimmer.inv:addExisting(wets[1])
fire("OnClientCommand", "CannabisMod", "trimPlant", trimmer, { id = wets[1]:getID() })
check("trimming needs a tool", sent[#sent].data.text:find("scissors") and trimmer.inv:count(C.DRIED_PLANT_ITEMS.Indica) == 1)
local scissors = newItem("Base.Scissors"); scissors.tags[ItemTag.SCISSORS] = true
trimmer.inv:addExisting(scissors)
fire("OnClientCommand", "CannabisMod", "trimPlant", trimmer, { id = wets[1]:getID() })
check("plant trimmed into buds", trimmer.inv:count(C.DRIED_PLANT_ITEMS.Indica) == 0 and trimmer.inv:count(C.Drying.BUD_ITEM) == 3)
local bud = nil
for _, it in ipairs(trimmer.inv.items) do if it.fullType == C.Drying.BUD_ITEM then bud = it end end
check("buds named by quality, carrying their own data", bud.name == "Good Indica Bud" and bud:getModData().DDBud.quality == 80
    and not bud:getModData().DDBud.moist and dd.buds[bud:getID()] == nil)
check("dried plant record is gone", dd.plants[wets[1]:getID()] == nil)
fire("OnClientCommand", "CannabisMod", "inspectBud", trimmer, { id = bud:getID() })
check("inspect bud shows quality at high level", sent[#sent].data.text:find("quality 80"))
fire("OnClientCommand", "CannabisMod", "inspectBud", newPlayer(0, 0, 0), { id = bud:getID(), data = bud:getModData().DDBud })
check("inspect bud hides quality at level 0", not sent[#sent].data.text:find("80") and sent[#sent].data.text:find("Indica"))
check("inspect bud shows moisture and mold", sent[#sent].data.text:find("moisture %d+%%") and sent[#sent].data.text:find("no mold, low mold risk"))
check("moisture runs from about 75%% wet to 12%% dry and 6%% over-dried", CannabisMod.Drying.moistureFromHours(0) == 75
    and CannabisMod.Drying.moistureFromHours(C.dryHours()) == 12 and CannabisMod.Drying.moistureFromHours(C.dryHours() + 24 * 30) == 6)
fire("OnClientCommand", "CannabisMod", "inspectBud", trimmer, { id = 424299, data = { type = "Sativa", quality = 70, moist = true, moisture = 28 } })
check("a moist bud warns of mold risk", sent[#sent].data.text:find("moisture 28%%") and sent[#sent].data.text:find("high mold risk"))
fire("OnClientCommand", "CannabisMod", "inspectBud", trimmer, { id = 424298, data = { type = "Sativa", quality = 70, moldy = true } })
check("a moldy bud says moldy, and an old bud gets an estimated moisture", sent[#sent].data.text:find("moldy") and sent[#sent].data.text:find("moisture 12%%"))

-- curing in a jar, burped on schedule
local jar = newStation(C.Drying.JAR_ITEM)
local jarSq = fakeSquare(320, 300, 0, false, true); jarSq.items[1] = jar
local burper = newPlayer(320, 300, 5); cook = burper
local jarBuds = {}
for i = 1, 3 do
    local b = jar:getInventory():addExisting(newItem(C.Drying.BUD_ITEM))
    dd.buds[b:getID()] = { type = "Indica", quality = 80, cureHours = 0, moldy = false, moldBaked = false, moist = false }
    jarBuds[i] = b
end
worldHours = 2000; fire("EveryOneMinute"); fire("EveryTenMinutes")
for day = 1, 6 do
    worldHours = worldHours + 24; fire("EveryTenMinutes")
    fire("OnClientCommand", "CannabisMod", "burpJar", burper, { id = jar:getID(), x = 320, y = 300, z = 0 })
end
local jr = jar:getInventory().items[1]:getModData().DDBud
check("six days of burped curing: no mold, full bonus", jr and not jr.moldy and jr.cureHours >= 6 * 24 - 0.01
    and G.curedQuality(jr.quality, jr.cureHours, jr.moldy, jr.moldBaked) == 88)
check("cured buds carry the cure and their records are gone", #jar:getInventory().items == 3 and dd.buds[jarBuds[1]:getID()] == nil
    and jar:getInventory().items[1]:getID() ~= jarBuds[1]:getID() and jar:getInventory().items[1]:getName() == "Premium Indica Bud")
fire("OnClientCommand", "CannabisMod", "checkJar", burper, { id = jar:getID(), x = 320, y = 300, z = 0 })
check("check jar reports the cure", sent[#sent].data.text:find("Jar: 3 buds"))

-- neglected jar with moist buds goes bad
SandboxVars = { CannabisMod = { MoldChance = 100000 } }
local badJar = newStation(C.Drying.JAR_ITEM)
local badSq = fakeSquare(330, 300, 0, false, true); badSq.items[1] = badJar
cook = newPlayer(330, 300, 5)
local bb = badJar:getInventory():addExisting(newItem(C.Drying.BUD_ITEM))
dd.buds[bb:getID()] = { type = "Indica", quality = 80, cureHours = 0, moldy = false, moist = true }
worldHours = 3000; fire("EveryOneMinute"); fire("EveryTenMinutes")
worldHours = 3000 + 100; fire("EveryTenMinutes")
check("unburped jar of moist buds goes moldy", dd.buds[bb:getID()].moldy == true)
SandboxVars = nil

-- curing barrel: furniture that cures like a big jar
local barrelSq = fakeSquare(340, 300, 0, false, true)
local barrel = placeRack(barrelSq, C.Drying.BARREL_SPRITE)
local cooper = newPlayer(340, 300, 5); cook = cooper
local barrelBud = barrel:addExisting(newItem(C.Drying.BUD_ITEM))
dd.buds[barrelBud:getID()] = { type = "Hybrid", quality = 70, cureHours = 0, moldy = false, moldBaked = false, moist = false }
worldHours = 4000; fire("EveryOneMinute"); fire("EveryTenMinutes")
for day = 1, 6 do
    worldHours = worldHours + 24; fire("EveryTenMinutes")
    fire("OnClientCommand", "CannabisMod", "burpBarrel", cooper, { x = 340, y = 300, z = 0 })
end
local brec = barrel.items[1]:getModData().DDBud
check("barrel cures buds like a jar", brec and not brec.moldy and brec.cureHours >= 6 * 24 - 0.01 and dd.buds[barrelBud:getID()] == nil)
fire("OnClientCommand", "CannabisMod", "checkBarrel", cooper, { x = 340, y = 300, z = 0 })
check("check barrel reports the cure", sent[#sent].data.text:find("Barrel: 1 buds"))
local sentBefore = #sent
fire("OnClientCommand", "CannabisMod", "burpBarrel", newPlayer(900, 900, 5), { x = 340, y = 300, z = 0 })
check("burping a barrel needs you nearby", #sent == sentBefore)
check("barrel holds ten jars' worth", C.Drying.BARREL_CAPACITY == 10 * C.Drying.JAR_CAPACITY)

-- Buds carry their own data: a jar keeps a curing record only while they cure, and the save forgets it afterwards.
-- A function rather than a do-block, so its locals don't count against the main chunk's limit.
;(function()
    SandboxVars = { CannabisMod = { MoldChance = 0 } }
    local j = newStation(C.Drying.JAR_ITEM)
    local jsq = fakeSquare(350, 300, 0, false, true); jsq.items[1] = j
    cook = newPlayer(350, 300, 5)
    local b = j:getInventory():addExisting(newItem(C.Drying.BUD_ITEM)); b:setName("Good Sativa Bud")
    b:getModData().DDBud = { type = "Sativa", quality = 70, cureHours = 0, moldy = false, moldBaked = false, moist = false }
    worldHours = 6000; fire("EveryOneMinute"); fire("EveryTenMinutes")
    local r = dd.buds[b:getID()]
    check("a bud going into a jar gets a curing record from its own data", r and r.fromItem and r.quality == 70 and r.cureHours == 0)
    worldHours = 6024; fire("EveryTenMinutes")
    check("it cures in the record, and the item is left alone", math.abs(dd.buds[b:getID()].cureHours - 24) < 0.01 and b:getModData().DDBud.cureHours == 0)
    for _ = 2, 6 do worldHours = worldHours + 24; fire("EveryTenMinutes") end
    local done = j:getInventory().items[1]
    check("a finished bud is swapped for one carrying its cure", done ~= b and done:getModData().DDBud.cureHours >= 144 - 0.01
        and dd.buds[b:getID()] == nil and dd.buds[done:getID()] == nil and done.name == "Good Sativa Bud")
    worldHours = worldHours + 24; fire("EveryTenMinutes")
    check("a finished bud doesn't get a new record", dd.buds[done:getID()] == nil and j:getInventory().items[1] == done)
    -- Mold in a neglected jar spoils the finished buds in it too.
    SandboxVars = { CannabisMod = { MoldChance = 100000 } }
    local wetBud = j:getInventory():addExisting(newItem(C.Drying.BUD_ITEM))
    wetBud:getModData().DDBud = { type = "Hybrid", quality = 60, cureHours = 0, moldy = false, moldBaked = false, moist = true }
    worldHours = worldHours + 1; fire("EveryTenMinutes")
    worldHours = worldHours + 100; fire("EveryTenMinutes")
    local spoiled = nil
    for _, it in ipairs(j:getInventory().items) do if it:getModData().DDBud.type == "Sativa" then spoiled = it end end
    check("mold in the jar spoils the finished bud too", dd.buds[wetBud:getID()].moldy and spoiled and spoiled ~= done
        and spoiled:getModData().DDBud.moldy == true and spoiled:getName() == "Moldy Sativa Bud")
    -- A bud inside a bag in the jar isn't cured or swapped, so it can't be duplicated.
    SandboxVars = { CannabisMod = { MoldChance = 0 } }
    local bag = newItem("Base.Bag_Schoolbag"); local bagInv = newContainer()
    bag.getInventory = function() return bagInv end
    j:getInventory():addExisting(bag)
    local tucked = bagInv:addExisting(newItem(C.Drying.BUD_ITEM))
    tucked:getModData().DDBud = { type = "Indica", quality = 60, cureHours = 140, moldy = false, moldBaked = false, moist = false }
    for _ = 1, 3 do worldHours = worldHours + 24; fire("EveryTenMinutes") end
    check("a bud in a bag inside a jar is left alone", #bagInv.items == 1 and bagInv.items[1] == tucked and dd.buds[tucked:getID()] == nil)
    SandboxVars = nil
    SandboxVars = nil

    -- Pruning: only records the item can do without, whose station is gone, after RECORD_KEEP_DAYS untouched.
    local now = 100000
    local old = now - (C.Drying.RECORD_KEEP_DAYS + 1) * 24
    dd.buds.p1 = { type = "Indica", quality = 50, cureHours = 10, fromItem = true, touched = old }
    dd.buds.p2 = { type = "Indica", quality = 50, cureHours = 10, touched = old }
    dd.buds.p3 = { type = "Indica", quality = 50, cureHours = 10, fromItem = true, touched = old, at = "350_300_0" }
    dd.buds.p4 = { type = "Indica", quality = 50, cureHours = 10, fromItem = true }
    dd.plants.p5 = { hours = 30, touched = old }
    dd.jars.p6 = { lastBurp = 0, touched = old }
    dd.buds.p7 = { type = "Indica", quality = 50, cureHours = 40, fromItem = true, changed = true, touched = old }
    dd.jars["barrel_340_300_0"].touched = old
    Dr.prune(now)
    check("prune drops an old record the item can do without", dd.buds.p1 == nil and dd.jars.p6 == nil)
    check("prune keeps old-style records, ones at a known station, and a known barrel's burp clock",
        dd.buds.p2 and dd.buds.p3 and dd.jars["barrel_340_300_0"])
    check("prune keeps cure and drying progress the item doesn't have", dd.buds.p7 and dd.plants.p5)
    check("records from before pruning start their clock", dd.buds.p4 and dd.buds.p4.touched == now)

    -- Inspecting a bud in a nearby container uses the data the client read off it, checked first.
    local far = newPlayer(0, 0, 9)
    fire("OnClientCommand", "CannabisMod", "inspectBud", far, { id = 424242, data = { type = "Sativa", quality = 77, cureHours = 0 } })
    check("inspect a bud from the data the client sent", sent[#sent].data.text:find("quality 77") and sent[#sent].data.text:find("Sativa"))
    fire("OnClientCommand", "CannabisMod", "inspectBud", far, { id = 424243, data = { type = "Purple", quality = 77 } })
    check("made-up bud data is ignored", sent[#sent].data.text == "Just a bud")

    -- A dried plant with no drying record (pruned, or never on a rack) trims as dry.
    local tp = newPlayer(0, 0, 8)
    local shears = newItem("Base.Scissors"); shears.tags[ItemTag.SCISSORS] = true
    local dryOne = newItem(C.DRIED_PLANT_ITEMS.Hybrid)
    dryOne:getModData().CannabisHarvest = { type = "Hybrid", quality = 80, budYield = 2 }
    tp.inv:addExisting(shears); tp.inv:addExisting(dryOne)
    fire("OnClientCommand", "CannabisMod", "trimPlant", tp, { id = dryOne:getID() })
    local tb = nil
    for _, it in ipairs(tp.inv.items) do if it.fullType == C.Drying.BUD_ITEM then tb = it end end
    check("an untracked dried plant trims as dry, not moist", tb and tb:getModData().DDBud.moist == false and tb:getModData().DDBud.quality == 80)
end)()

-- debug kit and time skip
local dk = newPlayer(0, 0, 1)
fire("OnClientCommand", "CannabisMod", "debugDryingKit", dk, {})
local wetGiven, named = 0, 0
for _, it in ipairs(dk.inv.items) do
    if C.isHangingPlant(it.fullType) then
        wetGiven = wetGiven + 1
        local h = it:getModData().CannabisHarvest
        if h and h.strain and it.name == "Wet " .. h.strain.name .. " (" .. h.type .. ")" then named = named + 1 end
    end
end
check("debug drying kit: rack, jar and 3 named starter-strain wet plants", dk.inv:count(C.Drying.RACK_ITEM) == 1
    and dk.inv:count(C.Drying.JAR_ITEM) == 1 and wetGiven == 3 and named == 3)

end

-- furniture: bags placed like furniture become plots, racks and fans are found by sprite
do
local Dr = CannabisMod.Drying
local fsq = fakeSquare(400, 400, 0, false, true)
fsq.objs[1] = C.SPRITE_SHEET .. "_" .. C.GrowBag.large.furnSprite
fire("OnObjectAdded", fsq:getObjects():get(0))
for _ = 1, 3 do fire("OnTick") end
check("placed furniture bag becomes a large bag plot", R.getBag(400, 400, 0) == "large"
    and SFarmingSystem.instance:getLuaObjectAt(400, 400, 0) and #fsq.objs == 0)
check("the new plot shows the unfilled bag", SFarmingSystem.instance:getLuaObjectAt(400, 400, 0).spriteName == "dazeddank_plants_01_202")
local fp = newPlayer(441, 400, 5)
local fsq2 = fakeSquare(442, 400, 0, false, true)
fsq2.objs[1] = C.SPRITE_SHEET .. "_" .. C.GrowBag.small.furnSprite
fire("OnClientCommand", "CannabisMod", "convertBag", fp, { x = 442, y = 400, z = 0 })
for _ = 1, 3 do fire("OnTick") end
check("convertBag from the client also works", R.getBag(442, 400, 0) == "small")
check("pickup returns the placeable item", (function()
    fire("OnClientCommand", "CannabisMod", "pickUpGrowBag", fp, { x = 442, y = 400, z = 0 })
    return fp.inv:count("CannabisMod.GrowBagSmallPlaceable") == 1
end)())
-- a rack's tiles know their other half
local rsq1, rsq2 = fakeSquare(410, 400, 0, false, true), fakeSquare(411, 400, 0, false, true)
rsq1.objs[1] = { sprite = "dazeddank_plants_01_208", container = newContainer() }
rsq2.objs[1] = { sprite = "dazeddank_plants_01_209", container = newContainer() }
check("south rack halves find each other", Dr.rackSquares(rsq1)[2] == rsq2 and Dr.rackSquares(rsq2)[2] == rsq1)
local esq1, esq2 = fakeSquare(420, 400, 0, false, true), fakeSquare(420, 401, 0, false, true)
esq1.objs[1] = { sprite = "dazeddank_plants_01_206", container = newContainer() }
esq2.objs[1] = { sprite = "dazeddank_plants_01_207", container = newContainer() }
check("east rack runs north to south", Dr.rackSquares(esq1)[2] == esq2 and Dr.rackSquares(esq2)[2] == esq1)
check("no rack, no squares", #Dr.rackSquares(fakeSquare(430, 400, 0, false, true)) == 0)
-- checking either half reports plants on both
local rackPlayer = newPlayer(410, 400, 5)
local half = rsq2.objs[1].container:addExisting(newItem(C.WET_PLANT_ITEMS.Indica))
half:getModData().CannabisHarvest = { type = "Indica", quality = 80, budYield = 3 }
fire("OnClientCommand", "CannabisMod", "checkRack", rackPlayer, { x = 410, y = 400, z = 0 })
check("check from one half sees the other half's plants", sent[#sent].data.text:find("Rack:"))
-- a placed fan beside a rack speeds drying
local fanSq = fakeSquare(412, 400, 0, false, true)
check("no fan yet", not Dr.environment(rsq1).fan)
fanSq.objs[1] = C.Drying.FAN_SPRITE
check("fan furniture near the rack is felt", Dr.environment(rsq1).fan)
end

-- ---- Smoking, tolerance and dependency ------------------------------------
do
local U = CannabisMod.Use
local user = U.new()
check("potency: premium beats poor, mold ruins", U.potency(95) > U.potency(20) and U.potency(95, true) < 0.2)
local s1 = U.dose(user, 100, 1.0, "joint")
local s2 = U.dose(user, 101, 1.0, "joint")
check("tolerance: the second dose is weaker", s2 < s1 and user.tol > 0)
check("a pipe hits harder than a joint", U.dose(U.new(), 0, 1.0, "pipe") > U.dose(U.new(), 0, 1.0, "joint"))
local _, h = U.dose(U.new(), 0, 1.0, "joint")
check("a full-strength joint lasts about 2.5 hours", math.abs(h - 2.5) < 0.01)
local heavy = U.new()
for i = 0, 29 do U.dose(heavy, i * 12, 1.0, "joint") end
check("regular use builds dependency and tolerance", heavy.dep > 60 and heavy.tol > 40)
local lastUse = heavy.lastUse
check("no withdrawal right after use", U.withdrawal(heavy, lastUse + 1) == 0)
check("withdrawal grows after a day off", U.withdrawal(heavy, lastUse + 20 + 24) > 0.5 and U.withdrawal(heavy, lastUse + 20 + 12) < U.withdrawal(heavy, lastUse + 20 + 24))
check("occasional use isn't dependent", U.withdrawal(user, 1000) == 0)
U.decay(heavy, lastUse + 24 * 20)
check("tolerance fades over weeks off", heavy.tol < 1 and heavy.dep < 60)
local e = U.highEffects("Indica", 1)
check("indica relaxes and tires", e.STRESS < 0 and e.FATIGUE > 0 and e.HUNGER > 0)
check("sativa lifts and wakes", U.highEffects("Sativa", 1).FATIGUE < 0 and U.highEffects("Sativa", 1).BOREDOM < e.BOREDOM)
check("strong sativa gets anxious, indica doesn't", U.highEffects("Sativa", 1.4).STRESS > U.highEffects("Sativa", 1).STRESS
    and U.highEffects("Indica", 1.4).STRESS == U.highEffects("Indica", 1).STRESS * 1.4)
check("moldy smoke does harm", U.highEffects("Hybrid", 1, true).UNHAPPINESS > 0)

-- server commands
local sm = CannabisMod.Smoking
local smoker = newPlayer(960, 960, 3)
local rec = CannabisMod.Drying.data()
local bud = newItem(C.Drying.BUD_ITEM); smoker.inv:addExisting(bud)
rec.buds[bud:getID()] = { type = "Sativa", quality = 90, cureHours = 0, moldy = false }
fire("OnClientCommand", "CannabisMod", "rollJoint", smoker, { id = bud:getID() })
check("rolling needs papers", sent[#sent].data.text:find("papers") and smoker.inv:count(C.Drying.BUD_ITEM) == 1)
smoker.inv:addExisting(newItem(C.Smoking.PAPER_ITEM))
fire("OnClientCommand", "CannabisMod", "rollJoint", smoker, { id = bud:getID() })
check("bud and paper become a joint", smoker.inv:count(C.Smoking.JOINT_ITEM) == 1 and smoker.inv:count(C.Drying.BUD_ITEM) == 0
    and smoker.inv:count(C.Smoking.PAPER_ITEM) == 0)
local joint
for _, it in ipairs(smoker.inv.items) do if it.fullType == C.Smoking.JOINT_ITEM then joint = it end end
check("the joint remembers the bud", joint:getModData().DDJoint.type == "Sativa" and joint.name == "Premium Sativa Joint"
    and sm.data().joints[joint:getID()] == nil and rec.buds[bud:getID()] == nil)
worldHours = 5000
fire("OnClientCommand", "CannabisMod", "smoke", smoker, { id = joint:getID(), method = "joint" })
local reply = sent[#sent]
check("smoking sends the high to the player", reply.cmd == "smoked" and reply.data.type == "Sativa" and reply.data.strength > 1
    and smoker.inv:count(C.Smoking.JOINT_ITEM) == 0)
check("the server tracked tolerance", sm.data().users["player"].tol > 0 and sm.data().joints[joint:getID()] == nil)
-- A joint rolled before joints carried their data still smokes from its old record, which then goes.
local oldJoint = newItem(C.Smoking.JOINT_ITEM); smoker.inv:addExisting(oldJoint)
sm.data().joints[oldJoint:getID()] = { type = "Indica", quality = 60, moldy = false }
fire("OnClientCommand", "CannabisMod", "smoke", smoker, { id = oldJoint:getID(), method = "joint" })
check("an old joint smokes from its record", sent[#sent].cmd == "smoked" and sent[#sent].data.type == "Indica"
    and sm.data().joints[oldJoint:getID()] == nil)
-- pipe needs the pipe
local b2 = newItem(C.Drying.BUD_ITEM); smoker.inv:addExisting(b2)
fire("OnClientCommand", "CannabisMod", "smoke", smoker, { id = b2:getID(), method = "pipe" })
check("a pipe hit needs a pipe", sent[#sent].data.text:find("pipe") and smoker.inv:count(C.Drying.BUD_ITEM) == 1)
smoker.inv:addExisting(newItem(C.Smoking.PIPE_ITEM))
fire("OnClientCommand", "CannabisMod", "smoke", smoker, { id = b2:getID(), method = "pipe" })
check("pipe smokes a plain bud", sent[#sent].cmd == "smoked" and smoker.inv:count(C.Drying.BUD_ITEM) == 0
    and smoker.inv:count(C.Smoking.PIPE_ITEM) == 1)
-- state request
sm.data().users["player"].dep = 80; sm.data().users["player"].lastUse = worldHours - 60
fire("OnClientCommand", "CannabisMod", "requestUseState", smoker, {})
check("withdrawal reported", sent[#sent].cmd == "useState" and sent[#sent].data.withdrawal > 0.3)
end

-- debug kit
local gk = newPlayer(950, 950, 1)
fire("OnClientCommand", "CannabisMod", "debugGrowKit", gk, {})
check("debug grow kit", gk.inv:count(C.NUTRIENT_ITEMS.Veg) == 2 and gk.inv:count("CannabisMod.GrowLampLargePro") == 1)


-- Loot tables and recipes
do
    ProceduralDistributions = { list = { GardenStoreMisc = { items = { "Base.Existing", 1 } }, DrugShackMisc = { items = {} } } }
    require "CannabisMod/CannabisLoot"
    fire("OnPreDistributionMerge")
    local gs = ProceduralDistributions.list.GardenStoreMisc.items
    check("loot appended after vanilla entries", gs[1] == "Base.Existing" and #gs > 2 and #gs % 2 == 0)
    check("loot skips lists that don't exist", ProceduralDistributions.list.NoSuchList == nil)
    local function readAll(path) local f = assert(io.open(MOD .. "../" .. path)); local t = f:read("*a"); f:close(); return t end
    local items = readAll("scripts/CannabisItems.txt")
    local recipes = readAll("scripts/CannabisRecipes.txt")
    local names = readAll("lua/shared/Translate/EN/Recipes.json")
    local missing = {}
    local function need(fullType)
        local id = fullType:match("^CannabisMod%.(.+)$")
        if id and not items:find("item%s+" .. id .. "%s*\n") then missing[#missing + 1] = fullType end
    end
    for _, entries in pairs(CannabisMod.Loot.TABLE) do for fullType in pairs(entries) do need(fullType) end end
    for fullType in recipes:gmatch("(CannabisMod%.[%w_]+)") do need(fullType) end
    check("every looted or crafted item is defined: " .. table.concat(missing, ","), #missing == 0)
    local unnamed = {}
    for recipe in recipes:gmatch("craftRecipe%s+([%w_]+)") do
        if not names:find('"' .. recipe .. '"') then unnamed[#unnamed + 1] = recipe end
    end
    check("every recipe has a translated name: " .. table.concat(unnamed, ","), #unnamed == 0)
end


-- Light timers
do
    local TM, Lt = C.Timer, CannabisMod.Light
    check("18/6 is on from 6:00 to midnight", TM.isOn("18/6", 6) and TM.isOn("18/6", 23) and not TM.isOn("18/6", 0) and not TM.isOn("18/6", 5))
    check("12/12 is on from 6:00 to 18:00", TM.isOn("12/12", 6) and TM.isOn("12/12", 17) and not TM.isOn("12/12", 18) and not TM.isOn("12/12", 3))
    check("no timer is always on", TM.isOn(nil, 2) and TM.isOn(nil, 20))
    local function litHours(sch) local n = 0 for h = 0, 23 do if TM.isOn(sch, h) then n = n + 1 end end return n end
    check("18/6 lights 18 hours a day and 12/12 lights 12", litHours("18/6") == 18 and litHours("12/12") == 12 and litHours(nil) == 24)
    -- The game's Lua truncates % toward zero (-1 % 24 is -1), so the timer must not lean on % for hours before 6:00.
    local src = io.open(MOD .. "shared/CannabisMod/CannabisConfig.lua"):read("*a")
    local body = src:match("function Config%.Timer%.isOn.-\nend")
    check("the timer's hour maths doesn't use %", body ~= nil and not body:gsub("%-%-[^\n]*", ""):find("%%"))
    check("only 12/12 is a short day", TM.isLongDay(nil) and TM.isLongDay("18/6") and not TM.isLongDay("12/12"))
    local b1, b3, b7 = TM.vegBonus(24), TM.vegBonus(72), TM.vegBonus(168)
    check("veg bonus: none without extra veg", TM.vegBonus(0) == 0 and TM.vegBonus(nil) == 0)
    check("veg bonus grows with diminishing returns (" .. string.format("%.2f %.2f %.2f", b1, b3, b7) .. ")",
        b1 < b3 and b3 < b7 and b7 < TM.VEG_BONUS_MAX and b7 > 0.45 and (b3 - b1) > (b7 - b3) / 2)

    local TS = CannabisMod.Timers
    TS._reset({})
    local lamp = fakeSquare(300, 300, 0, false, true)
    lamp.objs[1] = "dazeddank_plants_01_197"
    fire("LoadGridsquare", lamp)  -- announce the placed lamp to the light index
    fakeSquare(301, 300, 0, false, true)
    local function plant() return { x = 301, y = 300, z = 0, warnings = {}, stage = 2, care = 100, stress = 0, lightCap = 85 } end
    local old = hourOfDay
    hourOfDay = 20
    local p = plant(); Lt.update(p)
    check("lamp without a timer: veg light, lit at night", p.lightCycle == "long" and p.lightOn)

    local player = newPlayer(300, 300, 5)
    fire("OnClientCommand", "CannabisMod", "installTimer", player, { x = 300, y = 300, z = 0 })
    check("install needs a timer item", TS.scheduleAt(300, 300, 0) == nil)
    player.inv:AddItems(TM.ITEM, 1)
    fire("OnClientCommand", "CannabisMod", "installTimer", player, { x = 300, y = 300, z = 0 })
    check("install uses the item and starts on 18/6", TS.scheduleAt(300, 300, 0) == "18/6" and player.inv:count(TM.ITEM) == 0)
    fire("OnClientCommand", "CannabisMod", "setTimer", player, { x = 300, y = 300, z = 0, schedule = "12/12" })
    check("set the timer to 12/12", TS.scheduleAt(300, 300, 0) == "12/12")
    fire("OnClientCommand", "CannabisMod", "setTimer", player, { x = 300, y = 300, z = 0, schedule = "6/18" })
    check("unknown schedule ignored", TS.scheduleAt(300, 300, 0) == "12/12")

    p = plant()
    local stalled = Lt.update(p)
    check("12/12 dark hours: not stalled, no penalty", not stalled and p.care == 100 and not p.warnings.noLight
        and p.lightCycle == "short" and p.lightSource == "Lights off (timer)")
    hourOfDay = 12
    p = plant(); Lt.update(p)
    check("12/12 daytime: lit by the lamp", p.lightOn and p.lightCycle == "short")

    -- A second lamp with no timer leaks light into the 12/12 plant's night.
    local leakSq = fakeSquare(302, 300, 0, false, true)
    leakSq.objs[1] = "dazeddank_plants_01_198"
    fire("LoadGridsquare", leakSq)  -- announce the placed lamp to the light index
    hourOfDay = 20
    p = plant(); Lt.update(p)
    check("light leak at night: stress and a warning", p.lightCycle == "leak" and p.stress > 0 and p.warnings.lightLeak)
    hourOfDay = 12
    p = plant(); Lt.update(p)
    check("no leak stress while the 12/12 lamp is on", p.stress == 0)
    leakSq.objs[1] = nil

    -- Held veg and the yield bonus.
    local veg = { x = 301, y = 300, z = 0, warnings = {}, stage = C.STAGE.Vegetative, care = 100, stress = 0, fedThisStage = 1, lightCycle = "long" }
    check("veg light holds a plant in veg", R.heldInVeg(veg))
    for _ = 1, 6 * 72 do R.extendVeg(veg, 1000) end
    check("extra veg hours add up", math.abs(veg.extraVegHours - 72) < 0.01 and veg.vegHeld)
    R.extendVeg(veg, 1000 + TM.FEED_EVERY_HOURS + 1)
    check("fed plant isn't hungry", not veg.warnings.hungry and veg.fedThisStage == 0)
    R.extendVeg(veg, 1000 + 2 * TM.FEED_EVERY_HOURS + 2)
    check("unfed plant in held veg gets hungry", veg.warnings.hungry and veg.care == 100 - TM.HUNGRY_PENALTY)
    veg.lightCycle = "short"
    check("12/12 releases it", not R.heldInVeg(veg))
    R.advanceStage(veg)
    check("flip locks in the veg bonus", veg.stage == C.STAGE.PreFlower and math.abs(veg.vegBonus - TM.vegBonus(veg.extraVegHours)) < 1e-9
        and not veg.vegHeld and not veg.warnings.hungry)
    local sunPlant = { stage = C.STAGE.Vegetative, lightCycle = "sun" }
    check("sun-grown plants flip on their own", not R.heldInVeg(sunPlant))

    -- Info and the status window.
    local info = I.buildVisible({ stage = 2, lightCycle = "short", extraVegHours = 30, vegHeld = true, warnings = {}, water = 50, care = 100, stress = 0 }, 10, 0)
    check("info shows the light cycle, held veg and extra veg", info.lightCycle == "Flower light (12/12)" and info.vegHeld
        and info.extraVeg and info.extraVeg.hours == 30 and info.extraVeg.bonus > 0)

    -- Removing returns the item; a lamp picked up drops its timer on the floor.
    fire("OnClientCommand", "CannabisMod", "removeTimer", player, { x = 300, y = 300, z = 0 })
    check("remove gives the timer back", TS.scheduleAt(300, 300, 0) == nil and player.inv:count(TM.ITEM) == 1)
    fire("OnClientCommand", "CannabisMod", "installTimer", player, { x = 300, y = 300, z = 0 })
    local dropped = {}
    function lamp:AddWorldInventoryItem(t) dropped[#dropped + 1] = t end
    lamp.objs[1] = nil
    TS.cleanup()
    check("picked-up lamp drops its timer", TS.scheduleAt(300, 300, 0) == nil and dropped[1] == TM.ITEM)
    hourOfDay = old
end

-- Lamp light colours
do
    require "CannabisMod/CannabisLampLights"
    local LL = CannabisMod.LampLights
    local basic, pro = C.Light.SPRITES["dazeddank_plants_01_197"], C.Light.SPRITES["dazeddank_plants_01_198"]
    check("basic lamps glow purple, pro lamps yellow", LL.tier(basic) == "basic" and LL.tier(pro) == "pro"
        and LL.tier(C.Light.SPRITES["dazeddank_plants_01_234"]) == "basic" and LL.tier(C.Light.SPRITES["dazeddank_plants_01_235"]) == "pro"
        and LL.COLORS.basic[3] > LL.COLORS.basic[2] and LL.COLORS.pro[1] > LL.COLORS.pro[3])
    check("lamp light reaches past its growing area", LL.radius(basic) > basic.radius and LL.radius(C.Light.SPRITES["dazeddank_plants_01_235"]) >= 6)
end

-- Lamp glow: known lamps are re-read about once a second, follow power and the timer, and clear when gone or left behind.
do
    local LL = CannabisMod.LampLights
    local lit, litCount = {}, 0
    local cellObj = {
        getGridSquare = function(_, x, y, z) return fakeSquares[x .. "_" .. y .. "_" .. z] end,
        addLamppost = function(_, l) lit[l] = true; litCount = litCount + 1 end,
        removeLamppost = function(_, l) if lit[l] then lit[l] = nil; litCount = litCount - 1 end end,
    }
    local oldCell, oldPlayer, oldLight, oldHour, oldTs = getCell, getPlayer, IsoLightSource, hourOfDay, getTimestampMs
    local px, py = 1000.5, 1000.5
    local clock = 0
    getTimestampMs = function() return clock end
    getCell = function() return cellObj end
    getPlayer = function() return { getX = function() return px end, getY = function() return py end, getZ = function() return 0 end } end
    IsoLightSource = { new = function() return { setActive = function() end } end }
    local lampSq = fakeSquare(1005, 998, 0, false, true)
    lampSq.objs = { { sprite = "dazeddank_plants_01_197", md = { DDTimer = "12/12" } } }
    hourOfDay = 12
    LL.update()
    check("lamp glow: a lamp no event announced isn't lit yet", litCount == 0)
    fire("LoadGridsquare", lampSq)
    LL.update()
    check("lamp glow: a loaded lamp lights (one source per layer)", litCount == LL.LAYERS.basic)
    LL.update()
    check("lamp glow: a recheck keeps a lamp it saw", litCount == LL.LAYERS.basic)
    hourOfDay = 20
    LL.step()
    check("lamp glow: an hour change rechecks at once and goes dark in the timer's off hours", litCount == 0)
    hourOfDay = 12
    LL.update()
    lampSq.power = false
    LL.update()
    check("lamp glow: off without power", litCount == 0)
    lampSq.power = true
    LL.update()
    clock = 500
    lampSq.power = false
    LL.step()
    check("lamp glow: rechecks wait about a second", litCount == LL.LAYERS.basic)
    clock = 1600
    LL.step()
    check("lamp glow: and then catch up", litCount == 0)
    lampSq.power = true
    LL.update()
    px = 1100.5
    LL.update()
    check("lamp glow: off once the player walks out of range", litCount == 0)
    px = 1000.5
    LL.update()
    check("lamp glow: back on walking back", litCount == LL.LAYERS.basic)
    lampSq.objs = {}
    LL.update()
    check("lamp glow: off when the lamp is picked up", litCount == 0)
    -- A lamp that arrived without any event is found by the slow safety sweep.
    local quiet = fakeSquare(1001, 1002, 0, false, true)
    quiet.objs = { { sprite = "dazeddank_plants_01_198", md = {} } }
    for _ = 1, (2 * LL.SCAN_RADIUS + 2) * LL.DISCOVER_EVERY do LL.step() end
    check("lamp glow: the safety sweep finds an unannounced lamp", litCount == LL.LAYERS.pro)
    quiet.objs = {}
    LL.update()
    fakeSquares["1005_998_0"], fakeSquares["1001_1002_0"] = nil, nil
    getCell, getPlayer, IsoLightSource, hourOfDay, getTimestampMs = oldCell, oldPlayer, oldLight, oldHour, oldTs
end

-- Male plant sprites
do
    check("males look female until pre-flower", C.overlaySprite(4, 1, 2, "sprite", nil, true) == C.overlaySprite(4, 1, 2, "sprite"))
    check("first male sprite: healthy first shape pre-flower", C.overlaySprite(1, 1, 3, "sprite", nil, true) == "dazeddank_overlay_01_145")
    check("last male sprite: trampled last shape ripe", C.overlaySprite(7, 1, 5, "trampledSprite", "large", true) == "dazeddank_overlay_01_249")
    check("males ignore colour", C.overlaySprite(2, 3, 5, "sprite", nil, true) == C.overlaySprite(2, 1, 5, "sprite", nil, true))
    check("male layers read as male, female and coloured ones don't", C.isMaleSprite(C.overlaySprite(5, 1, 4, "dyingSprite", "xlbag", true))
        and not C.isMaleSprite(C.overlaySprite(5, 1, 4, "sprite")) and not C.isMaleSprite(C.overlaySprite(5, 2, 4, "sprite")))
end

-- Hydroponics: DWC buckets
do
    local HY, HC, GB = CannabisMod.Hydro, C.Hydro, CannabisMod.GrowBags
    HY._reset({})
    local function fluidItem(fluid, litres)
        local it = newItem("Base.WaterBottle")
        local fc = { amount = litres }
        function fc:getAmount() return self.amount end
        function fc:getPrimaryFluid() return { getFluidTypeString = function() return fluid end } end
        function fc:removeFluid(n) self.amount = math.max(0, self.amount - n) end
        it.getFluidContainer = function() return fc end
        return it, fc
    end
    -- sprites and container rules
    check("DWC sprites read as a DWC bucket", C.bagFromSprite("dazeddank_plants_01_374") == "dwc" and C.bagFromSprite("dazeddank_plants_01_373") == "dwc"
        and C.bagFromSprite("dazeddank_plants_01_372") == nil and C.bagFromFurnSprite("dazeddank_plants_01_372") == "dwc")
    check("a DWC bucket with no medium needs one", C.bagIsUnfilled("dazeddank_plants_01_373") and C.isHydro("dwc") and not C.isHydro("small"))

    local sq = fakeSquare(700, 700, 0, false, true)
    local plot = GB.makePlot(sq, "dwc")
    local grower = newPlayer(700, 700, 6)
    check("placing a DWC bucket makes a hydro plot", plot and R.getBag(700, 700, 0) == "dwc" and plot.spriteName == "dazeddank_plants_01_373")
    -- sowing needs a medium
    local seedA = newItem(C.SEED_ITEM); S.setData(seedA, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
    ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seedA, plant = { x = 700, y = 700, z = 0 }, character = grower })
    check("can't sow into a DWC bucket without a medium", R.getPlant(700, 700, 0) == nil and sent[#sent].data.text:find("rockwool"))
    fire("OnClientCommand", "CannabisMod", "hydroAddMedium", grower, { x = 700, y = 700, z = 0, medium = "rockwool" })
    check("adding rockwool needs a cube", sent[#sent].data.text:find("rockwool cube") and not R.isBagSoiled(700, 700, 0))
    grower.inv:addExisting(newItem(HC.MEDIUM_ITEMS.rockwool))
    fire("OnClientCommand", "CannabisMod", "hydroAddMedium", grower, { x = 700, y = 700, z = 0, medium = "rockwool" })
    check("rockwool cube set in the net pot", R.isBagSoiled(700, 700, 0) and grower.inv:count(HC.MEDIUM_ITEMS.rockwool) == 0
        and plot.spriteName == "dazeddank_plants_01_374")
    ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seedA, plant = { x = 700, y = 700, z = 0 }, character = grower })
    check("can't sow into a dry reservoir", R.getPlant(700, 700, 0) == nil and sent[#sent].data.text:find("Fill the reservoir"))
    local dwcRes = HY.get(700, 700, 0, "dwc")
    dwcRes.level, dwcRes.lastTick, dwcRes.rot = 5, 1, 0
    ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seedA, plant = { x = 700, y = 700, z = 0 }, character = grower })
    local hp = R.getPlant(700, 700, 0)
    check("seed sown into rockwool", hp and hp.bag == "dwc")
    sq.power = false
    HY.update(hp, 50)
    sq.power = true
    check("an idle reservoir grew no rot before the plant went in", dwcRes.rot < 1 and dwcRes.lastTick == 50)
    dwcRes.level = 0

    -- water: top up from bottles, tainted water marks the reservoir
    fire("OnClientCommand", "CannabisMod", "hydroTopUp", grower, { x = 700, y = 700, z = 0 })
    check("topping up needs water", sent[#sent].data.text:find("no water"))
    local bottle, bfc = fluidItem("Water", 10)
    grower.inv:addExisting(bottle)
    fire("OnClientCommand", "CannabisMod", "hydroTopUp", grower, { x = 700, y = 700, z = 0 })
    local r = HY.get(700, 700, 0)
    check("top up pours the bottle in", math.abs(r.level - 10) < 0.01 and bfc.amount == 0 and not r.tainted)
    local dirty, dfc = fluidItem("TaintedWater", 8)
    grower.inv:addExisting(dirty)
    fire("OnClientCommand", "CannabisMod", "hydroTopUp", grower, { x = 700, y = 700, z = 0 })
    check("top up stops at capacity and tainted water marks it", math.abs(r.level - 15) < 0.01 and math.abs(dfc.amount - 3) < 0.01 and r.tainted)

    -- the plant drinks and the plot stays watered while there is water
    hp.stage = C.STAGE.Vegetative
    r.lastTick, hp.hydroTick = 0, 0
    HY.update(hp, 10)
    check("plant drinks from the reservoir", math.abs(r.level - (15 - 0.3 * 10)) < 0.01 and hp.water == HC.PLOT_WATER)
    -- nutrients: mixing, running down, starving, burn
    check("no nutrients: the plant is hungry", hp.warnings.hungry)
    local care0 = hp.care
    check("feeding a hydro plant mixes into the reservoir", R.feed(hp, "Veg") == "mixed" and r.strength == 1 and r.nutrient == "Veg" and not hp.warnings.hungry)
    check("dosing a strong reservoir burns", R.feed(hp, "Veg") == "burn" and hp.care < care0 + C.Care.RIGHT_NUTRIENT_BONUS)
    r.strength = 0.5
    HY.update(hp, 10 + 24)
    check("nutrients run down over time", r.strength < 0.5 - 0.3)
    -- the reservoir runs dry
    r.level = 0.1
    HY.update(hp, 10 + 25)
    check("a dry reservoir leaves the plant dry", r.level == 0 and hp.water == HC.DRY_PLOT_WATER and hp.warnings.reservoirDry)
    do
    -- Feeding an empty reservoir keeps the bottle.
    local keepBottle = grower.inv:count(C.NUTRIENT_ITEMS.Veg)
    grower.inv:addExisting(newItem(C.NUTRIENT_ITEMS.Veg))
    fire("OnClientCommand", "CannabisMod", "feedPlant", grower, { x = 700, y = 700, z = 0, nutrient = "Veg" })
    check("feeding an empty reservoir keeps the nutrient bottle", grower.inv:count(C.NUTRIENT_ITEMS.Veg) == keepBottle + 1
        and sent[#sent].data.text:find("empty"))
    check("an empty reservoir isn't moist for a cutting", not HY.isMoist(700, 700, 0))
    -- Away from the grow, the hydro side pauses: no rot, no drinking.
    r.level, r.rot = 10, 5
    fakeSquares["700_700_0"] = nil
    sq.power = false
    HY.update(hp, 300)
    fakeSquares["700_700_0"] = sq
    check("while the grow isn't loaded nothing rots or drains", r.rot == 5 and r.level == 10 and r.lastTick == 300)
    sq.power = true
    check("a reservoir with water is moist for a cutting", HY.isMoist(700, 700, 0))
    -- Checking a reservoir doesn't move it on.
    r.lastTick = 250
    fire("OnClientCommand", "CannabisMod", "hydroCheck", grower, { x = 700, y = 700, z = 0 })
    check("checking a reservoir adds no rot", r.rot == 5 and r.lastTick == 250)
    r.rot, r.level = 0, 0.1
    end
    do
    -- Debug: fill nearby reservoirs and water nearby soil pots in one go.
    local soilSq = fakeSquare(704, 700, 0, false, true)
    local soilPlot = GB.makePlot(soilSq, "small")
    soilPlot.waterLvl = 5
    local farSq = fakeSquare(760, 700, 0, false, true)
    local farPlot = GB.makePlot(farSq, "small")
    farPlot.waterLvl = 5
    r.level, r.tainted = 0, true
    local drip = HY.get(708, 700, 0, "drip"); drip.isDrip, drip.level = true, 0
    fire("OnClientCommand", "CannabisMod", "debugFillWater", grower, {})
    check("debug fill fills a nearby drip tank", math.abs(drip.level - HY.capacity(drip)) < 0.01)
    HY.clear(708, 700, 0)
    check("debug fill tops the DWC reservoir up with clean water", math.abs(r.level - HY.capacity(r)) < 0.01 and not r.tainted)
    check("debug fill waters a nearby pot to a healthy level", soilPlot.waterLvl == HY.DEBUG_POT_WATER
        and soilPlot.waterLvl > C.Water.LOW and soilPlot.waterLvl < C.Water.HIGH)
    check("debug fill leaves pots out of range alone", farPlot.waterLvl == 5 and sent[#sent].data.text:find("Filled 2 reservoir"))
    R.clearBag(704, 700, 0); R.clearBag(760, 700, 0)
    r.rot, r.level, r.tainted = 0, 0.1, false
    end

    -- root rot: no power, and the cure
    r.level, r.rot, r.tainted, r.changedAt = 15, 0, false, 30
    sq.power = false
    r.lastTick, hp.hydroTick = 40, 40
    HY.update(hp, 45)
    check("pumps without power start root rot", r.rot > 0 and hp.warnings.pumpOff)
    sq.power = true
    local before = r.rot
    HY.update(hp, 46)
    check("once started, rot keeps spreading", r.rot > before)
    grower.inv:addExisting(fluidItem("Water", 20))
    local bleach, bleachFc = fluidItem("Bleach", 1)
    grower.inv:addExisting(bleach)
    worldHours = 46
    fire("OnClientCommand", "CannabisMod", "hydroBleach", grower, { x = 700, y = 700, z = 0 })
    check("bleach needs a fresh reservoir", r.rot > 0 and sent[#sent].data.text:find("Change the reservoir"))
    fire("OnClientCommand", "CannabisMod", "hydroChange", grower, { x = 700, y = 700, z = 0 })
    check("changing the reservoir refills it and clears the nutrients", math.abs(r.level - 15) < 0.01 and r.strength == 0 and r.changedAt == 46)
    fire("OnClientCommand", "CannabisMod", "hydroBleach", grower, { x = 700, y = 700, z = 0 })
    local treated = r.rot
    check("bleach starts early rot healing", r.recovering and treated > 0 and math.abs(bleachFc.amount - (1 - HC.BLEACH_L)) < 0.001)
    r.lastTick, hp.hydroTick = 46, 46
    HY.update(hp, 46.5)
    check("treated rot falls, and the trend shows it", r.rot < treated and hp.rootRotTrend == -1)
    HY.update(hp, 70)
    check("treated roots heal fully", r.rot == 0 and not r.recovering)
    r.rot = HC.ROT_EARLY + 5; r.changedAt = 46; r.lastTick, hp.hydroTick = 70, 70
    fire("OnClientCommand", "CannabisMod", "hydroBleach", grower, { x = 700, y = 700, z = 0 })
    check("advanced rot can't be bleached", r.rot > HC.ROT_EARLY and sent[#sent].data.text:find("too far"))
    local careRot = hp.care
    r.lastTick, hp.hydroTick = 46, 46
    HY.update(hp, 47)
    check("advanced rot costs care, and the trend shows it rising", hp.care < careRot and hp.warnings.rootRot and hp.rootRotTrend == 1)
    -- Pulling a plant: only once it's past saving, then a reservoir change clears the rot.
    local saveable = HC.ROT_EARLY - 5
    hp.rootRot = saveable
    fire("OnClientCommand", "CannabisMod", "pullHydroPlant", grower, { x = 700, y = 700, z = 0 })
    check("a saveable plant can't be pulled", R.getPlant(700, 700, 0) ~= nil and sent[#sent].data.text:find("can still be saved"))
    hp.rootRot = HC.ROT_EARLY + 5
    fire("OnClientCommand", "CannabisMod", "pullHydroPlant", grower, { x = 700, y = 700, z = 0 })
    check("a rotted plant can be pulled, leaving its DWC bucket clean", R.getPlant(700, 700, 0) == nil and sent[#sent].data.text:find("Pulled")
        and r.rot == 0)
    r.rot, r.recovering = 0, nil
    -- stale reservoir
    r.changedAt, r.lastTick, hp.hydroTick = 0, HC.STALE_DAYS * 24, HC.STALE_DAYS * 24
    HY.update(hp, HC.STALE_DAYS * 24 + 1)
    check("an old reservoir goes stale and risks rot", hp.warnings.staleReservoir and r.rot > 0)
    r.rot, hp.rootRot = 0, 0
    -- hydro is more forgiving
    local soilPlant = { care = 100, stress = 0, warnings = {} }
    local hydroPlant = { care = 100, stress = 0, warnings = {}, bag = "dwc" }
    R.applyPenalty(soilPlant, 10); R.applyPenalty(hydroPlant, 10)
    check("care penalties are smaller in DWC", hydroPlant.care > soilPlant.care)
    -- info
    local info = I.buildVisible(hp, 10, 0)
    check("status window shows the reservoir and roots", info.reservoir and info.reservoir.cap == 15 and info.roots == "Healthy")
    hp.rootRot = 12
    local rotInfo = I.buildVisible(hp, 10, 0)
    require "CannabisMod/CannabisStatusLayout"
    local lay = CannabisMod.StatusLayout.build(rotInfo, function() return 12 end, function(_, t) return #t * 6 end)
    local shown = false
    for _, op in ipairs(lay.ops) do if op.kind == "text" and op.text == "Browning  12%" then shown = true end end
    check("status window shows the root rot level", rotInfo.rootRot == 12 and rotInfo.roots == "Browning" and shown)
    hp.rootRotTrend = 1
    local function arrowRows(level)
        local l = CannabisMod.StatusLayout.build(I.buildVisible(hp, level, 0), function() return 12 end, function(_, t) return #t * 6 end)
        local n = 0
        for _, op in ipairs(l.ops) do if op.kind == "rect" and op.h == 1 and op.color == CannabisMod.StatusLayout.COLORS.bad then n = n + 1 end end
        return n
    end
    check("rising rot shows a red arrow from Agriculture 5, hidden below it", arrowRows(5) == 4 and arrowRows(4) == 0)
    hp.rootRot, hp.rootRotTrend = 0, nil

    -- harvest: rockwool is spent, pebbles would stay
    for _ = 1, 3 do R.advanceStage(hp) end
    SFarmingSystem.harvest(SFarmingSystem.instance, plot, grower)
    check("harvest empties the bucket and spends the rockwool", plot.state == "plow" and not R.isBagSoiled(700, 700, 0))
    grower.inv:addExisting(newItem(HC.MEDIUM_ITEMS.pebbles))
    fire("OnClientCommand", "CannabisMod", "hydroAddMedium", grower, { x = 700, y = 700, z = 0, medium = "pebbles" })
    GB.reset(plot)
    check("clay pebbles stay in the bucket after a reset", R.isBagSoiled(700, 700, 0) and HY.get(700, 700, 0).medium == "pebbles")
    -- seeds in pebbles sometimes fail
    local old = HC.PEBBLE_SEED_FAIL
    HC.PEBBLE_SEED_FAIL = 100
    local seedB = grower.inv:addExisting(newItem(C.SEED_ITEM)); S.setData(seedB, { type = T.SATIVA, sex = C.SEX.FEMALE, genetics = 100 })
    ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seedB, plant = { x = 700, y = 700, z = 0 }, character = grower })
    check("a seed can slip through clay pebbles", R.getPlant(700, 700, 0) == nil and grower.inv:count(C.SEED_ITEM) == 0)
    HC.PEBBLE_SEED_FAIL = old
    -- picking up gives the pebbles back
    fire("OnClientCommand", "CannabisMod", "pickUpGrowBag", grower, { x = 700, y = 700, z = 0 })
    local kit = newPlayer(0, 0, 1)
    fire("OnClientCommand", "CannabisMod", "debugHydroKit", kit, {})
    check("debug hydro kit", kit.inv:count("CannabisMod.DWCBucket") == 2 and kit.inv:count(HC.CONTROL_ITEM) == 1 and kit.inv:count(HC.MEDIUM_ITEMS.rockwool) == 5
        and kit.inv:count(C.GrowBag.xldwc.furnItem) == 1)
    check("picking up a bucket returns it and its pebbles", grower.inv:count("CannabisMod.DWCBucket") == 1
        and grower.inv:count(HC.MEDIUM_ITEMS.pebbles) == 1 and R.getBag(700, 700, 0) == nil)
end

-- Hydroponics: RDWC
do
    local HY, HC, GB = CannabisMod.Hydro, C.Hydro, CannabisMod.GrowBags
    HY._reset({})
    check("RDWC sites have their sprites on the hydro sheet", C.bagFromSprite("dazeddank_hydro_01_2") == "rdwc" and C.bagFromFurnSprite("dazeddank_hydro_01_0") == "rdwc"
        and C.bagEmptySprite("rdwc", true) == "dazeddank_hydro_01_2" and C.bagIsUnfilled("dazeddank_hydro_01_1"))
    check("hydro sheet numbers don't leak onto the main sheet", C.bagFromSprite("dazeddank_hydro_01_1") == "rdwc"
        and C.bagFromSprite("dazeddank_plants_01_2") == nil and C.bagFromFurnSprite("dazeddank_plants_01_0") == nil
        and not C.bagIsUnfilled("dazeddank_plants_01_1") and C.bagFromSprite("othermod_01_201") == nil)
    -- The game refuses a whole tile sheet over 512 tiles, which hides every placed object from the mod.
    local highest = { [C.SPRITE_SHEET] = 0, [C.HYDRO_SHEET] = 0 }
    for kind, def in pairs(C.GrowBag) do
        local sheet = C.sheetOf(kind)
        for _, n in ipairs({ def.furnSprite, def.emptySprite, def.drySprite }) do
            highest[sheet] = math.max(highest[sheet], n)
        end
    end
    local ctrlSheet, ctrlN = C.splitSprite(HC.CONTROL_SPRITE)
    highest[ctrlSheet] = math.max(highest[ctrlSheet], ctrlN)
    check("every tile sheet stays within the 512-tile limit", highest[C.SPRITE_SHEET] < C.MAX_SHEET_TILES
        and highest[C.HYDRO_SHEET] < C.MAX_SHEET_TILES and ctrlSheet == C.HYDRO_SHEET)
    local ctrl = fakeSquare(800, 800, 0, false, true)
    ctrl.objs[1] = HC.CONTROL_SPRITE
    local function site(x, y)
        local sq = fakeSquare(x, y, 0, false, true)
        local plot = GB.makePlot(sq, "rdwc")
        local seed = newItem(C.SEED_ITEM); S.setData(seed, { type = T.HYBRID, sex = C.SEX.FEMALE, genetics = 100 })
        R.setBagSoiled(x, y, 0, true); HY.get(x, y, 0, "rdwc").medium = "rockwool"
        -- Sowing needs water in the reservoir; an unlinked site is planted past the check so its dry state can be tested.
        local res = HY.reservoirOf(x, y, 0)
        local orig = HY.reservoirOf
        if res and res.level <= 0 then res.level = 1 end
        if not res then HY.reservoirOf = function() return { level = 1 } end end
        ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seed, plant = { x = x, y = y, z = 0 } })
        HY.reservoirOf = orig
        local p = R.getPlant(x, y, 0); p.stage = C.STAGE.Vegetative
        return p, plot
    end
    local far = site(810, 800)
    HY.update(far, 100)
    check("a site with no control bucket in range is dry", far.warnings.noControl and far.water == HC.DRY_PLOT_WATER and HY.reservoirOf(810, 800, 0) == nil)
    local a = site(801, 800)
    local b = site(800, 802)
    local r = HY.reservoirOf(801, 800, 0)
    HY.reservoirOf(800, 802, 0)
    check("sites link to the control bucket and grow its reservoir", r and r.kind == "rdwc" and r.x == 800
        and HY.sitesOf("800_800_0") == 2 and HY.capacity(r) == HC.RDWC_CONTROL_L + 2 * HC.RDWC_SITE_L)
    -- top up and dose from the control bucket itself
    local pl = newPlayer(800, 800, 6)
    local it = newItem("Base.WaterBottle"); local fc = { amount = 100 }
    function fc:getAmount() return self.amount end
    function fc:getPrimaryFluid() return { getFluidTypeString = function() return "Water" end } end
    function fc:removeFluid(n) self.amount = math.max(0, self.amount - n) end
    it.getFluidContainer = function() return fc end
    pl.inv:addExisting(it)
    fire("OnClientCommand", "CannabisMod", "hydroTopUp", pl, { x = 800, y = 800, z = 0 })
    check("topping up the control fills the shared reservoir", math.abs(r.level - 80) < 0.01)
    check("feeding one site doses the whole system", R.feed(a, "Veg") == "mixed" and r.strength == 1)
    -- both plants drink from it; reservoir-wide changes happen once per tick
    a.hydroTick, b.hydroTick, r.lastTick = 100, 100, 100
    HY.update(a, 110); HY.update(b, 110)
    check("every site drinks from the shared reservoir", math.abs(r.level - (80 - 2 * 0.3 * 10)) < 0.01 and a.hydro.sites == 2)
    check("nutrients run down once per tick, not once per site", math.abs(r.strength - (1 - 10 / HC.NUTRIENT_HOURS)) < 1e-6)
    -- rot is shared
    r.rot = HC.ROT_EARLY + 1
    HY.update(a, 111); HY.update(b, 111)
    check("root rot spreads to every site", a.warnings.rootRot and b.warnings.rootRot and a.rootRot == b.rootRot)
    -- Shared rot only clears once every rotted site is pulled and the reservoir is changed.
    local b2, bl2 = newPlayer(800, 801, 6), newItem("Base.WaterBottle")
    local fc2 = { amount = 200 }
    function fc2:getAmount() return self.amount end
    function fc2:getPrimaryFluid() return { getFluidTypeString = function() return "Water" end } end
    function fc2:removeFluid(n) self.amount = math.max(0, self.amount - n) end
    bl2.getFluidContainer = function() return fc2 end
    b2.inv:addExisting(bl2)
    fire("OnClientCommand", "CannabisMod", "pullHydroPlant", b2, { x = 801, y = 800, z = 0 })
    fire("OnClientCommand", "CannabisMod", "hydroChange", b2, { x = 800, y = 800, z = 0 })
    check("a change with rotted sites still planted doesn't clear the rot", r.rot > 0 and R.getPlant(801, 800, 0) == nil)
    fire("OnClientCommand", "CannabisMod", "pullHydroPlant", b2, { x = 800, y = 802, z = 0 })
    fire("OnClientCommand", "CannabisMod", "hydroChange", b2, { x = 800, y = 800, z = 0 })
    check("with every rotted site pulled, a change cleans the system", r.rot == 0 and sent[#sent].data.text:find("clean of rot"))
    a = site(801, 800); b = site(800, 802)
    r.rot = 0
    -- max sites
    for i = 1, 4 do site(802, 800 + i - 2) ; HY.reservoirOf(802, 800 + i - 2, 0) end
    check("a control bucket runs six sites", HY.sitesOf("800_800_0") == HC.RDWC_MAX_SITES)
    site(798, 800)
    check("a seventh site isn't connected", HY.reservoirOf(798, 800, 0) == nil)
    -- losing the control bucket unlinks its sites
    ctrl.objs[1] = nil
    check("sites lose their water when the control bucket is gone", HY.reservoirOf(801, 800, 0) == nil)
    ctrl.objs[1] = HC.CONTROL_SPRITE

    -- Pulling males: recognised by sprite on the client, checked against the real record on the server.
    check("male layers are recognised in every container", C.isMaleSprite(C.overlaySprite(3, 1, 4, "sprite", "rdwc", true))
        and C.isMaleSprite(C.overlaySprite(1, 1, 3, "sprite", nil, true)) and C.isMaleSprite(C.overlaySprite(2, 1, 5, "dyingSprite", "xldwc", true))
        and not C.isMaleSprite(C.overlaySprite(3, 1, 4, "sprite", "rdwc")) and not C.isMaleSprite("dazeddank_plants_01_205"))
    a.sex, a.stage = C.SEX.FEMALE, C.STAGE.PreFlower
    fire("OnClientCommand", "CannabisMod", "pullMalePlant", pl, { x = 801, y = 800, z = 0 })
    check("a female can't be pulled as a male", R.getPlant(801, 800, 0) ~= nil and sent[#sent].data.text:find("isn't a male"))
    a.sex = C.SEX.MALE
    fire("OnClientCommand", "CannabisMod", "pullMalePlant", pl, { x = 801, y = 800, z = 0 })
    check("a male plant can be pulled", R.getPlant(801, 800, 0) == nil and sent[#sent].data.text:find("Pulled the male"))

    -- A site out of range doesn't freeze the shared reservoir its loaded neighbours still use.
    local bsq = fakeSquares["800_802_0"]
    r.lastTick = 500
    fakeSquares["800_802_0"] = nil
    HY.update(b, 600)
    fakeSquares["800_802_0"] = bsq
    check("an unloaded site leaves a loaded shared reservoir's clock alone", r.lastTick == 500 and b.hydroTick == 600)

    -- Top Shelf quality
    local best = { lightCap = 100, genetics = 100, care = 100, bag = "rdwc" }
    local dwcBest = { lightCap = 100, genetics = 100, care = 100, bag = "dwc" }
    check("RDWC can reach Top Shelf quality", G.calcQuality(best, 0, nil) == 115 and G.calcQuality(dwcBest, 0, nil) == 100)
    check("Top Shelf buds cure up to 115, ordinary buds stop at 100", G.curedQuality(105, 999, false) == 115 and G.curedQuality(98, 999, false) == 100)
    check("Top Shelf name and stronger smoke", C.qualityTier(110) == "Top Shelf" and C.qualityTier(100) == "Premium"
        and CannabisMod.Use.potency(115) > CannabisMod.Use.potency(100))
    local oldVars = SandboxVars
    SandboxVars = { CannabisMod = { HydroQualityBonus = 0 } }
    check("Hydro Quality Bonus 0 removes Top Shelf", G.calcQuality(best, 0, nil) == 100)
    SandboxVars = oldVars
    check("RDWC is the most forgiving", C.GrowBag.rdwc.careMult < C.GrowBag.dwc.careMult and C.GrowBag.rdwc.yield == 1.4)
end

-- Hydroponics: Ebb and Flow
do
    local HY, HC, GB = CannabisMod.Hydro, C.Hydro, CannabisMod.GrowBags
    HY._reset({})
    HY.forgetLinks()
    local res = fakeSquare(999, 1000, 0, false, true)
    res.objs[1] = { sprite = HC.FLOOD_SPRITE, md = {} }
    local function tableAt(x, y)
        local sq = fakeSquare(x, y, 0, false, true)
        GB.makePlot(sq, "ebb")
        return sq
    end
    for x = 1000, 1003 do tableAt(x, 1000) end
    local r = HY.reservoirOf(1003, 1000, 0)
    check("touching tables link to the flood reservoir beside the row", r and r.x == 999 and r.kind == "ebb" and r.isFlood
        and #HY.ebbSitesOf("999_1000_0") == 4 and HY.capacity(r) == HC.EBB_RESERVOIR_L)
    tableAt(1010, 1000)
    check("a table not touching the row isn't fed", HY.reservoirOf(1010, 1000, 0) == nil)
    check("flood table sprites read as Ebb and Flow", C.bagFromSprite(C.bagEmptySprite("ebb", true)) == "ebb"
        and C.bagFromFurnSprite("dazeddank_hydro_01_119") == "ebb")

    -- rockwool only, and water before sowing
    local grower = newPlayer(1001, 1000, 6)
    grower.inv:addExisting(newItem(HC.MEDIUM_ITEMS.pebbles))
    fire("OnClientCommand", "CannabisMod", "hydroAddMedium", grower, { x = 1001, y = 1000, z = 0, medium = "pebbles" })
    check("flood tables refuse clay pebbles", sent[#sent].data.text:find("rockwool cubes only") and not R.isBagSoiled(1001, 1000, 0))
    grower.inv:addExisting(newItem(HC.MEDIUM_ITEMS.rockwool))
    fire("OnClientCommand", "CannabisMod", "hydroAddMedium", grower, { x = 1001, y = 1000, z = 0, medium = "rockwool" })
    check("rockwool goes on a flood table", R.isBagSoiled(1001, 1000, 0))
    r.level = 30
    local seed = newItem(C.SEED_ITEM); S.setData(seed, { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100 })
    ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = seed, plant = { x = 1001, y = 1000, z = 0 }, character = grower })
    local ep = R.getPlant(1001, 1000, 0)
    check("seed sown on a flood table", ep and ep.bag == "ebb")
    ep.stage = C.STAGE.Vegetative

    -- dry until flooded; a flood keeps it wet for EBB_WET_HOURS
    HY.update(ep, 200)
    check("an unflooded table is dry", ep.warnings.mediumDry and ep.water == HC.DRY_PLOT_WATER and r.level == 30)
    local tsq = fakeSquare(1001, 1000, 0, false, true)
    res.power = false
    fire("OnClientCommand", "CannabisMod", "floodTables", grower, { x = 1001, y = 1000, z = 0 })
    check("flooding needs power", sent[#sent].data.text:find("no power"))
    res.power = true
    worldHours = 200
    fire("OnClientCommand", "CannabisMod", "floodTables", grower, { x = 1001, y = 1000, z = 0 })
    check("flooding wets every table the reservoir feeds", sent[#sent].data.text:find("Flooded 4 table sites")
        and HY.get(1003, 1000, 0, "ebb").wetUntil == 200 + HC.EBB_WET_HOURS)
    local tableMd = SFarmingSystem.instance:getLuaObjectAt(ep.x, ep.y, ep.z):getIsoObject().md
    check("a flood shows on each table for a right-click", tableMd.DDWetUntil == 200 + HC.EBB_WET_HOURS and not tableMd.DDWetTimer)
    local resMd
    for _, o in ipairs(res.objs) do if type(o) == "table" and o.sprite == HC.FLOOD_SPRITE then resMd = o.md end end
    check("and on the flood reservoir", resMd and resMd.DDWetUntil == 200 + HC.EBB_WET_HOURS)
    check("wetness reads as a percent and the hours left", C.Hydro.wetnessLabel(212, false, 203) == "Rockwool: 75% wet, dry in 9 h"
        and C.Hydro.wetnessLabel(212, false, 212) == "Rockwool: dry, flood the tables"
        and C.Hydro.wetnessLabel(220, true, 210):find("flood timer"))
    HY.update(ep, 205)
    check("a flooded table waters the plant and it drinks", not ep.warnings.mediumDry and ep.water == HC.PLOT_WATER and r.level < 30
        and ep.hydro.ebb and ep.hydro.wetHours == 7)
    HY.update(ep, 213)
    check("the rockwool dries out after about 12 hours", ep.warnings.mediumDry and ep.water == HC.DRY_PLOT_WATER)

    -- the flood timer keeps it wet while powered, and power loss dries it over 12 hours
    grower.inv:addExisting(newItem(HC.FLOOD_TIMER_ITEM))
    fire("OnClientCommand", "CannabisMod", "installFloodTimer", grower, { x = 999, y = 1000, z = 0 })
    check("a flood timer fits on the reservoir", r.floodTimer and grower.inv:count(HC.FLOOD_TIMER_ITEM) == 0)
    HY.update(ep, 214)
    check("with a timer and power the tables stay wet", not ep.warnings.mediumDry and ep.hydro.floodTimer)
    check("the table shows the timer keeping it wet", tableMd.DDWetTimer == true and tableMd.DDWetUntil == 214 + HC.EBB_WET_HOURS)
    local sentBefore = SFarmingSystem.instance:getLuaObjectAt(ep.x, ep.y, ep.z):getIsoObject().sent
    HY.update(ep, 214 + 1 / 6)
    check("the table's wetness isn't re-sent every ten minutes", SFarmingSystem.instance:getLuaObjectAt(ep.x, ep.y, ep.z):getIsoObject().sent == sentBefore)
    res.power = false
    HY.update(ep, 220)
    check("after a power cut the rockwool is still wet for a while", not ep.warnings.mediumDry)
    HY.update(ep, 227)
    check("12 hours without power and the table is dry", ep.warnings.mediumDry)
    res.power = true
    fire("OnClientCommand", "CannabisMod", "removeFloodTimer", grower, { x = 999, y = 1000, z = 0 })
    check("the flood timer comes back off", not r.floodTimer and grower.inv:count(HC.FLOOD_TIMER_ITEM) == 1)

    -- root rot builds slowly and needs no air pump
    r.rot, r.tainted, r.changedAt, r.lastTick, ep.hydroTick = 0, true, 227, 227, 227
    res.power = false
    HY.update(ep, 237)
    check("Ebb and Flow rot is slow and ignores the air pump", r.rot > 0 and r.rot <= HC.ROT_TAINTED * 10 * HC.EBB_ROT_MULT + 0.01)
    res.power = true
    r.rot, r.tainted = 0, false

    -- at most 12 sites per reservoir
    for x = 1004, 1012 do tableAt(x, 1000) end
    HY.forgetLinks()
    HY.reservoirOf(1000, 1000, 0)
    check("a flood reservoir feeds at most 12 table sites", #HY.ebbSitesOf("999_1000_0") == HC.EBB_MAX_SITES
        and HY.reservoirOf(1012, 1000, 0) == nil and HY.reservoirOf(1010, 1000, 0) ~= nil)

    -- two-tile tables: the halves pair up and pick up together
    check("table halves find each other", select(2, GB.tablePartner("dazeddank_hydro_01_114", 5, 5, 0)) == 6
        and GB.tablePartner("dazeddank_hydro_01_117", 5, 5, 0) == 4)
    local a = fakeSquare(1100, 1000, 0, false, true); a.objs[1] = { sprite = "dazeddank_hydro_01_116" }
    local b = fakeSquare(1101, 1000, 0, false, true); b.objs[1] = { sprite = "dazeddank_hydro_01_117" }
    check("placing a flood table turns both tiles into sites in one go", GB.convertBagAt(1100, 1000, 0) and not GB.convertBagAt(1101, 1000, 0)
        and #a.objs == 0 and #b.objs == 0
        and R.getBag(1100, 1000, 0) == "ebb" and R.getBag(1101, 1000, 0) == "ebb" and HY.get(1100, 1000, 0, "ebb").partner == "1101_1000_0")
    local picker = newPlayer(1100, 1000, 6)
    fire("OnClientCommand", "CannabisMod", "pickUpGrowBag", picker, { x = 1100, y = 1000, z = 0 })
    check("picking up either half takes the whole table", R.getBag(1100, 1000, 0) == nil and R.getBag(1101, 1000, 0) == nil
        and picker.inv:count("CannabisMod.FloodTable") == 1)

    -- the reservoir can take a Dazed Plumbing line, and a picked-up reservoir drops its timer
    check("flood reservoirs are plumbable", CannabisMod.Plumbing.kindOf(res:getObjects():get(0)) == "ebb"
        and HY.reservoirAt(999, 1000, 0, "ebb") == r)
    r.floodTimer = true
    res.objs[1] = nil
    HY.cleanup()
    local dropped = 0
    for _, it in ipairs(res.items) do if it:getFullType() == HC.FLOOD_TIMER_ITEM then dropped = dropped + 1 end end
    check("a picked-up reservoir is forgotten and drops its flood timer", HY.reservoirAt(999, 1000, 0, "ebb") == nil and dropped == 1)
    res.objs[1] = HC.FLOOD_SPRITE

    -- review fixes --------------------------------------------------------------
    -- One reservoir between two rows feeds 12 sites across both, and a flood reaches all of them.
    HY.forgetLinks()
    local mid = fakeSquare(2000, 2000, 0, false, true)
    mid.objs[1] = HC.FLOOD_SPRITE
    for i = 1, 7 do tableAt(2000 + i, 2000); tableAt(2000 - i, 2000) end
    local mr = HY.reservoirOf(2001, 2000, 0)
    HY.reservoirOf(1999, 2000, 0)
    local fedKeys = HY.ebbSitesOf("2000_2000_0")
    local left, right = 0, 0
    for _, k in ipairs(fedKeys) do if tonumber(k:match("^(-?%d+)")) < 2000 then left = left + 1 else right = right + 1 end end
    check("a reservoir between two rows feeds the nearest 12 across both", mr and #fedKeys == HC.EBB_MAX_SITES and left == 6 and right == 6
        and HY.reservoirOf(2007, 2000, 0) == nil and HY.reservoirOf(1993, 2000, 0) == nil and HY.reservoirOf(1994, 2000, 0) == mr)
    mr.level = 30
    local mp = newPlayer(2001, 2000, 6)
    worldHours = 300
    fire("OnClientCommand", "CannabisMod", "floodTables", mp, { x = 2000, y = 2000, z = 0 })
    check("a hand flood waters both rows", HY.get(1995, 2000, 0, "ebb").wetUntil == 300 + HC.EBB_WET_HOURS
        and HY.get(2005, 2000, 0, "ebb").wetUntil == 300 + HC.EBB_WET_HOURS)

    -- Tables beside a reservoir on an unloaded square aren't written off as unconnected.
    HY.forgetLinks()
    fakeSquares["2000_2000_0"] = nil
    local gone, unknown = HY.reservoirOf(2001, 2000, 0)
    check("an unloaded reservoir reads as unknown, not unconnected", gone == nil and unknown == true)
    fakeSquares["2000_2000_0"] = mid
    worldHours = worldHours + 1
    check("...and the row links again once it loads", HY.reservoirOf(2001, 2000, 0) == mr)

    -- Pairing: a lone back half never hands out a table; a lone front half gives one.
    local lone1 = fakeSquare(3000, 3000, 0, false, true); lone1.objs[1] = { sprite = "dazeddank_hydro_01_117" }
    local lone0 = fakeSquare(3010, 3000, 0, false, true); lone0.objs[1] = { sprite = "dazeddank_hydro_01_116" }
    GB.convertBagAt(3000, 3000, 0); GB.convertBagAt(3010, 3000, 0)
    local lp, lq = newPlayer(3000, 3000, 0), newPlayer(3010, 3000, 0)
    fire("OnClientCommand", "CannabisMod", "pickUpGrowBag", lp, { x = 3000, y = 3000, z = 0 })
    fire("OnClientCommand", "CannabisMod", "pickUpGrowBag", lq, { x = 3010, y = 3000, z = 0 })
    check("unpaired table halves give back one table, not two", lp.inv:count("CannabisMod.FloodTable") + lq.inv:count("CannabisMod.FloodTable") == 1
        and R.getBag(3000, 3000, 0) == nil and R.getBag(3010, 3000, 0) == nil)
    -- Halves converted in either order pair both ways.
    local h1 = fakeSquare(3101, 3000, 0, false, true); h1.objs[1] = { sprite = "dazeddank_hydro_01_117" }
    local h0 = fakeSquare(3100, 3000, 0, false, true); h0.objs[1] = { sprite = "dazeddank_hydro_01_116" }
    GB.convertBagAt(3101, 3000, 0); GB.convertBagAt(3100, 3000, 0)
    check("halves pair both ways whichever converts first", HY.get(3100, 3000, 0, "ebb").partner == "3101_3000_0"
        and HY.get(3101, 3000, 0, "ebb").partner == "3100_3000_0")

    -- A flood reservoir placed back keeps showing its fitted timer.
    local back = fakeSquare(3200, 3000, 0, false, true)
    local backEntry = { sprite = HC.FLOOD_SPRITE }
    back.objs[1] = backEntry
    HY.reservoirAt(3200, 3000, 0, "ebb").floodTimer = true
    HY.syncFloodObject(3200, 3000, 0)
    check("a re-placed reservoir shows its fitted timer again", backEntry.md and backEntry.md.DDFloodTimer == true)
end


-- Dazed Plumbing hookup
do
    local PL, HY, HC = CannabisMod.Plumbing, CannabisMod.Hydro, C.Hydro
    local registered
    DazedPlumb = { Links = {
        register = function(a) registered = a return true end,
        linkOf = function(obj, id) local md = obj:getModData(); return md.dazedplumbLinks and md.dazedplumbLinks[id] end } }
    PL.registered = nil
    PL.register()
    check("reservoirs register with Dazed Plumbing as a water sink", registered and registered.id == PL.ID and registered.supplies == "water")
    local sq = fakeSquare(900, 900, 0, false, true)
    local entry = { sprite = HC.CONTROL_SPRITE, md = {} }
    sq.objs[1] = entry
    local obj = PL.objectAt(sq)
    check("the control bucket matches the adapter", obj and registered.match(obj) and PL.kindOf(obj) == "rdwc"
        and PL.kindOf({ getSprite = function() return { getName = function() return "dazeddank_plants_01_374" end } end }) == "dwc")
    local r = HY.reservoirAt(900, 900, 0, "rdwc")
    r.level, r.strength = 30, 0.5
    local pl = newPlayer(900, 900, 6)
    fire("OnClientCommand", "CannabisMod", "hydroChange", pl, { x = 900, y = 900, z = 0 })
    check("without a line, a change still needs carried water", r.level == 30 and sent[#sent].data.text:find("need water"))
    entry.md.dazedplumbLinks = { [PL.ID] = { source = "tank" } }
    check("no top-up from the line until a change", registered.room(obj) == 0 and PL.isPlumbedAt(900, 900, 0))
    fire("OnClientCommand", "CannabisMod", "hydroChange", pl, { x = 900, y = 900, z = 0 })
    check("a plumbed change dumps the water and waits for the line", r.level == 0 and r.strength == 0 and r.fillPending
        and sent[#sent].data.text:find("water line"))
    local cap = HY.capacity(r)
    check("the line may fill it to capacity", math.abs(registered.room(obj) - cap) < 0.01)
    registered.put(obj, 10, false)
    check("line water fills the reservoir", math.abs(r.level - 10) < 0.01 and not r.tainted)
    registered.put(obj, cap, true)
    check("tainted tank water taints it, and filling stops once full", math.abs(r.level - cap) < 0.01 and r.tainted
        and not r.fillPending and registered.room(obj) == 0)
    -- A line taken off mid-refill doesn't leave the reservoir "refilling" forever.
    r.fillPending = true
    entry.md.dazedplumbLinks = nil
    fire("OnClientCommand", "CannabisMod", "hydroCheck", pl, { x = 900, y = 900, z = 0 })
    check("a reservoir without a line stops waiting for one", not r.fillPending and not sent[#sent].data.text:find("refilling"))
    -- Filling an empty reservoir by hand counts as fresh water.
    r.level, r.changedAt, r.everFilled = 0, 0, nil
    worldHours = 400
    local jug = newItem("Base.WaterBottle"); local jfc = { amount = 10 }
    function jfc:getAmount() return self.amount end
    function jfc:getPrimaryFluid() return { getFluidTypeString = function() return "Water" end } end
    function jfc:removeFluid(n) self.amount = math.max(0, self.amount - n) end
    jug.getFluidContainer = function() return jfc end
    pl.inv:addExisting(jug)
    fire("OnClientCommand", "CannabisMod", "hydroTopUp", pl, { x = 900, y = 900, z = 0 })
    check("a brand-new reservoir's first fill starts its age", r.changedAt == 400 and r.level > 0)
    r.level, r.changedAt = 0, 0
    jfc.amount = 10
    fire("OnClientCommand", "CannabisMod", "hydroTopUp", pl, { x = 900, y = 900, z = 0 })
    check("topping up a dried-out reservoir isn't a change", r.changedAt == 0)
    DazedPlumb = nil
end

-- Watering cursor: a tall plant's leaves over the tile behind it still water the plant
do
    local plots = {}
    local oldCF = CFarmingSystem
    dofile(MOD .. "client/CannabisMod/CannabisWaterCursor.lua")
    CFarmingSystem = { instance = { getLuaObjectOnSquare = function(_, sq) return plots[sq:getX() .. "_" .. sq:getY()] end } }
    local behind = fakeSquare(4000, 4000, 0, false, true)
    local front = fakeSquare(4001, 4001, 0, false, true)
    plots["4000_4000"] = { state = "plow" }
    plots["4001_4001"] = { state = "seeded", typeOfSeed = C.CROP_TYPE }
    check("hovering the furrow behind a tall plant waters the plant", CannabisMod.WaterCursor.target(behind) == front)
    plots["4001_4001"] = { state = "seeded", typeOfSeed = "Tomato" }
    check("only cannabis gets the retarget; a planted tile under the mouse stays put",
        CannabisMod.WaterCursor.target(behind) == behind and CannabisMod.WaterCursor.target(front) == front)
    CFarmingSystem = oldCF
end

-- Debug: boost a plant's quality
do
    local pl = newPlayer(0, 0, 0)
    local oldDebug = isDebugEnabled
    isDebugEnabled = function() return true end
    local p = R.addPlant(950, 950, 0, { type = T.HYBRID, sex = C.SEX.FEMALE, genetics = 50 })
    p.care, p.lightCap, p.stress = 60, 70, 40
    fire("OnClientCommand", "CannabisMod", "debugBoostQuality", pl, { x = 950, y = 950, z = 0, amount = 20 })
    check("debug +20 raises genetics, light and care and clears stress", p.genetics == 70 and p.lightCap == 90 and p.care == 80 and p.stress == 0
        and sent[#sent].data.text:find("quality"))
    fire("OnClientCommand", "CannabisMod", "debugBoostQuality", pl, { x = 950, y = 950, z = 0, amount = "max" })
    check("debug max quality tops every factor", p.genetics == 100 and p.lightCap == 100 and p.care == 100
        and sent[#sent].data.text:find("quality 100"))
    isDebugEnabled = oldDebug
end

-- Recipe magazine
do
    local function readAll(path) local f = assert(io.open(MOD .. "../" .. path)); local t = f:read("*a"); f:close(); return t end
    local recipes = readAll("scripts/CannabisRecipes.txt")
    local items = readAll("scripts/CannabisItems.txt")
    -- Every recipe that must be learned is taught by exactly one of the two magazines; kiln firing needs no learning.
    local inMag, inScript, learnable = {}, {}, true
    local taughtCount = 0
    for _, mag in ipairs({ "GrowersHandbook", "HydroMagazine", "ControlledEnvMagazine" }) do
        local taught = items:match("item " .. mag .. ".-LearnedRecipes%s*=%s*([^,]+),")
        if not taught then learnable = false end
        for n in (taught or ""):gmatch("[^;]+") do
            if inMag[n] then learnable = false end
            inMag[n] = true; taughtCount = taughtCount + 1
        end
    end
    for name, body in recipes:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
        if body:find("NeedToBeLearn = true", 1, true) then inScript[name] = true end
    end
    for n in pairs(inScript) do if not inMag[n] then learnable = false end end
    for n in pairs(inMag) do if not inScript[n] then learnable = false end end
    check("the magazines teach exactly the learnable recipes", learnable)
    local total = 0
    for _ in pairs(inScript) do total = total + 1 end
    local kilnOnly = true
    for name, body in recipes:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
        if not inScript[name] and not body:find("Kiln", 1, true) then kilnOnly = false end
    end
    check("every recipe needs learning except kiln firing", kilnOnly and total > 0)
    require "CannabisMod/CannabisRecipes"
    local listed = {}
    for _, n in ipairs(CannabisMod.Recipes.NAMES) do listed[n] = true end
    local same = true
    for n in pairs(inScript) do if not listed[n] then same = false end end
    check("auto-learn list matches the recipes", same and #CannabisMod.Recipes.NAMES == total)
    local known, learned = {}, 0
    local player = { isRecipeKnown = function(_, n) return known[n] end, learnRecipe = function(_, n) known[n] = true; learned = learned + 1 end }
    local old = SandboxVars
    SandboxVars = { CannabisMod = { RecipeMagazine = true } }
    check("magazine required: nothing auto-learned", CannabisMod.Recipes.learnAll(player) == 0 and learned == 0)
    SandboxVars = { CannabisMod = { RecipeMagazine = false } }
    check("magazine off: all recipes learned", CannabisMod.Recipes.learnAll(player) == total and learned == total)
    check("magazine off: nothing learned twice", CannabisMod.Recipes.learnAll(player) == 0)
    SandboxVars = old
    check("magazine option has defaults, text and tooltip", readAll("sandbox-options.txt"):find("CannabisMod.RecipeMagazine", 1, true)
        and readAll("lua/shared/Translate/EN/Sandbox.json"):find("RecipeMagazine_tooltip", 1, true)
        and CannabisMod.Config.SandboxDefaults.RecipeMagazine == true)
end


-- Sandbox options that change the rules
do
    local U, Cf = CannabisMod.Use, C
    local function withVars(vars, fn) local old = SandboxVars; SandboxVars = { CannabisMod = vars }; local ok, err = pcall(fn); SandboxVars = old; assert(ok, err) end
    withVars({ DependencyEnabled = false }, function()
        local u = U.new(); U.dose(u, 100, 1, "joint")
        check("dependency off: none builds and no withdrawal", u.dep == 0 and U.withdrawal({ dep = 90, lastUse = 0 }, 500) == 0)
    end)
    withVars({ DependencyRate = 2 }, function()
        local u = U.new(); U.dose(u, 100, 1, "joint")
        check("dependency rate doubles the gain", u.dep == C.Use.DEP_GAIN * 2 * C.Use.DEP_OCCASIONAL)
    end)
    withVars({ ToleranceRate = 0 }, function()
        local u = U.new(); U.dose(u, 100, 1, "joint")
        check("tolerance rate 0: no tolerance", u.tol == 0)
    end)
    withVars({ EffectStrength = 2 }, function()
        check("effect strength scales the high", U.highEffects("Indica", 1, false).UNHAPPINESS == C.Use.EFFECTS.Indica.UNHAPPINESS * 2)
        check("effect strength scales withdrawal", U.withdrawalEffects(1).STRESS == C.Use.WITHDRAWAL.STRESS * 2)
    end)
    withVars({ CuringDays = 12, DryingHours = 96 }, function()
        check("curing days option", G.curedQuality(80, 6 * 24) == 84 and G.curedQuality(80, 12 * 24) == 88)
        check("drying hours option", math.abs(G.dryMultiplier(48) - (C.Quality.RUSHED_DRY_MIN_MULT + (1 - C.Quality.RUSHED_DRY_MIN_MULT) * 0.5)) < 1e-9)
    end)
    withVars({ LampRange = 2 }, function()
        check("lamp range multiplier widens the zone", C.Light.reaches(4, 0, 2) and not C.Light.reaches(5, 0, 2))
    end)
    check("sandbox defaults restored", C.Light.reaches(2, 0, 2) and not C.Light.reaches(3, 0, 2))
end


-- Status window layout
do
    require "CannabisMod/CannabisStatusLayout"
    local Lay = CannabisMod.StatusLayout
    local function fontH(f) return f == "Medium" and 20 or 14 end
    local function measure(f, str) return #str * 7 end
    local function inside(model)
        for _, op in ipairs(model.ops) do
            if op.kind == "rect" and (op.x < -0.01 or op.x + op.w > model.width + 0.01 or op.y < 0 or op.y + op.h > model.height) then return false, op end
            if op.kind == "text" then
                local w = measure(op.font, op.text)
                local left = (op.align == "right") and op.x - w or ((op.align == "center") and op.x - w / 2 or op.x)
                if left < 0 or left + w > model.width or op.y < 0 or op.y + fontH(op.font) > model.height then return false, op end
            end
        end
        return true
    end
    local novice = Lay.build({ level = 0, name = "Cannabis Plant", stageRough = "Growing", waterRough = "OK", container = "Ground" }, fontH, measure)
    check("novice status fits", inside(novice) and novice.height > 60)
    local full = Lay.build({ level = 10, name = "Cannabis Plant", container = "Large Grow Bag", stage = "Flowering", hoursLeft = 30,
        water = 62, lastNutrient = "Bloom", type = "Indica", sex = "Female", light = "Large pro grow lamp", healthBand = "Good",
        stressBand = "Moderate", warnings = { "nutrientBurn", "overwatered", "wrongNutrient", "lightInterrupted" }, harvestWindow = "Not ripe",
        pollinated = false, hermieSigns = false, generation = 2, geneticsBand = "Strong", qualityEstimate = "Excellent" }, fontH, measure)
    check("full status fits", inside(full))
    check("more info makes a taller window", full.height > novice.height)
    check("hours text", Lay.formatHours(30) == "1 d 6 h" and Lay.formatHours(5) == "5 h")
    check("next unlock", Lay.nextUnlock(0) == 2 and Lay.nextUnlock(4) == 5 and Lay.nextUnlock(10) == nil)
    local hot = Lay.build({ level = 5, type = "Weird", stage = "Ripe", water = 120, healthBand = "Unknown", warnings = { "mystery" } }, fontH, measure)
    check("unknown values still lay out", inside(hot))
end


-- Grow rooms: panel registration, flood fill, shared schedule
;(function()
    require "CannabisMod/CannabisRooms"
    local R, TS, TM = CannabisMod.Rooms, CannabisMod.Timers, C.Timer
    R._reset({}); TS._reset({})
    for x = 500, 505 do for y = 500, 504 do fakeSquare(x, y, 0, false, true) end end
    -- A solid wall between x=502 and x=503 splits the block into two rooms of 15 tiles.
    local function wall(a, b) return (a:getX() <= 502) ~= (b:getX() <= 502) end
    local set, count, capped = R.fill(fakeSquares["500_500_0"], wall)
    check("fill stops at the wall", count == 15 and not capped and set["502_504_0"] and not set["503_500_0"])

    local lampA = fakeSquares["501_501_0"]
    lampA.objs[1] = { sprite = "dazeddank_plants_01_197", md = {} }
    fire("LoadGridsquare", lampA)  -- announce the placed lamp to the light index
    local lampB = fakeSquares["504_501_0"]
    lampB.objs[1] = { sprite = "dazeddank_plants_01_197", md = {} }
    fire("LoadGridsquare", lampB)  -- announce the placed lamp to the light index
    local owner = newPlayer(501, 501, 5)
    owner.inv:AddItems(TM.ITEM, 1)
    fire("OnClientCommand", "CannabisMod", "installTimer", owner, { x = 501, y = 501, z = 0 })
    fire("OnClientCommand", "CannabisMod", "installTimer", owner, { x = 504, y = 501, z = 0 })
    check("own timer on the lamp before the panel", TS.scheduleAt(501, 501, 0) == "18/6" and TS.scheduleAt(504, 501, 0) == nil)

    local function mount(key, sprite) table.insert(fakeSquares[key].objs, { sprite = sprite or "dazeddank_rooms_01_0", md = {} }) end
    mount("500_500_0"); mount("505_504_0")
    local ok, freed = R.register(fakeSquares["500_500_0"], owner, wall)
    check("panel registers and hands the lamp's timer back", ok and freed == 1 and owner.inv:count(TM.ITEM) == 1)
    check("room lamp runs the room's 18/6", TS.scheduleAt(501, 501, 0) == "18/6" and lampA.objs[1].md.DDTimer == "18/6")
    check("lamp in the other room is untouched", TS.scheduleAt(504, 501, 0) == nil)

    local again, why = R.register(fakeSquares["502_503_0"], owner, wall)
    check("a second panel in the same room is refused with the first position", again == false and why:find("500, 500"))
    check("a panel in the next room is fine", R.register(fakeSquares["505_504_0"], owner, wall))

    fire("OnClientCommand", "CannabisMod", "roomSetSchedule", owner, { x = 500, y = 500, z = 0, schedule = "12/12" })
    check("panel sets the room schedule on every lamp", TS.scheduleAt(501, 501, 0) == "12/12" and lampA.objs[1].md.DDTimer == "12/12")
    fire("OnClientCommand", "CannabisMod", "roomSetSchedule", owner, { x = 500, y = 500, z = 0, schedule = "24/0" })
    check("24/0 means no timer", TS.scheduleAt(501, 501, 0) == nil and lampA.objs[1].md.DDTimer == nil)
    fire("OnClientCommand", "CannabisMod", "roomSetSchedule", owner, { x = 500, y = 500, z = 0, schedule = "6/18" })
    check("unknown room schedule ignored", TS.scheduleAt(501, 501, 0) == nil and R.roomAt(501, 501, 0).schedule == "24/0")
    fire("OnClientCommand", "CannabisMod", "roomSetSchedule", owner, { x = 500, y = 500, z = 0, schedule = "18/6" })

    fire("OnClientCommand", "CannabisMod", "roomSetMode", owner, { x = 500, y = 500, z = 0, mode = "Flower" })
    fire("OnClientCommand", "CannabisMod", "roomSetMode", owner, { x = 500, y = 500, z = 0, mode = "Bogus" })
    check("room mode sets, bad mode ignored", R.roomAt(500, 500, 0).mode == "Flower")
    fire("OnClientCommand", "CannabisMod", "roomRename", owner, { x = 500, y = 500, z = 0, name = "   Mother Room with an extremely long name   " })
    check("rename trims and caps the name", R.roomAt(500, 500, 0).name == "Mother Room with an extr" and R.cleanName("  ") == "Grow Room")

    local far = newPlayer(900, 900, 5)
    fire("OnClientCommand", "CannabisMod", "roomSetMode", far, { x = 500, y = 500, z = 0, mode = "Veg" })
    check("too far from the panel: ignored", R.roomAt(500, 500, 0).mode == "Flower")

    owner.inv:AddItems(TM.ITEM, 1)
    local before = owner.inv:count(TM.ITEM)
    fire("OnClientCommand", "CannabisMod", "installTimer", owner, { x = 501, y = 501, z = 0 })
    check("a room lamp can't take its own timer", owner.inv:count(TM.ITEM) == before and TS.scheduleAt(501, 501, 0) == "18/6")

    -- A new lamp placed in the room picks up the room schedule at the next resync.
    local lampC = fakeSquares["500_503_0"]
    lampC.objs[1] = { sprite = "dazeddank_plants_01_197", md = {} }
    fire("LoadGridsquare", lampC)  -- announce the placed lamp to the light index
    check("new lamp runs the room schedule at once", TS.scheduleAt(500, 503, 0) == "18/6")
    R.rebuild(wall)
    check("rebuild marks the new lamp for clients", lampC.objs[1].md.DDTimer == "18/6")

    -- Taking the panel off its wall drops the room at the next rebuild.
    table.remove(fakeSquares["505_504_0"].objs)
    R.rebuild(wall)
    check("a panel object that is gone drops its room", R.roomAt(504, 503, 0) == nil and R.roomAt(501, 501, 0) ~= nil)

    local key = "500_500_0"
    check("removing a panel frees the room", R.remove(key) and R.roomAt(501, 501, 0) == nil and TS.scheduleAt(501, 501, 0) == nil)

    -- Placing a second panel in a room that has one takes it down again and drops the item.
    R.register(fakeSquares["500_500_0"], owner, wall)
    local extra = { sprite = "dazeddank_rooms_01_2", md = {} }
    table.insert(fakeSquares["502_503_0"].objs, extra)
    extra.getSquare = nil
    local placed = { getSprite = function() return { getName = function() return extra.sprite end } end,
                     getSquare = function() return fakeSquares["502_503_0"] end, entry = extra }
    local oldEdge = R.edgeBlocked
    R.edgeBlocked = wall
    fire("OnObjectAdded", placed)
    R.edgeBlocked = oldEdge
    check("a second panel is taken back down", #fakeSquares["502_503_0"].items == 1
        and fakeSquares["502_503_0"].items[1]:getFullType() == "CannabisMod.GrowRoomPanel" and R.keyAt(502, 503, 0) == "500_500_0")

    -- The panel window's data lists the lamps, their state and the room's size.
    hourOfDay = 12
    fire("OnClientCommand", "CannabisMod", "roomSetSchedule", owner, { x = 500, y = 500, z = 0, schedule = "12/12" })
    sent = {}
    fire("OnClientCommand", "CannabisMod", "requestRoom", owner, { x = 500, y = 500, z = 0 })
    local info = sent[#sent] and sent[#sent].data
    check("requestRoom answers with the room", info and info.tiles == 15 and info.name == "Grow Room" and info.schedule == "12/12")
    check("info lists room lamps and their state", info and #info.lamps == 2 and info.lamps[1].lit == true and info.powered == true)
    hourOfDay = 22
    fire("OnClientCommand", "CannabisMod", "requestRoom", owner, { x = 500, y = 500, z = 0 })
    check("a 12/12 lamp is dark at 22:00", sent[#sent].data.lamps[1].lit == false)
    -- The panel window works from anywhere in the room, not just beside the panel.
    sent = {}
    fire("OnClientCommand", "CannabisMod", "requestRoom", newPlayer(502, 504, 5), { x = 500, y = 500, z = 0 })
    check("Refresh works from the far end of the room", sent[#sent] and sent[#sent].data and sent[#sent].data.tiles == 15)
    sent = {}
    fire("OnClientCommand", "CannabisMod", "requestRoom", newPlayer(520, 520, 5), { x = 500, y = 500, z = 0 })
    check("outside the room it says why instead of doing nothing", sent[#sent] and sent[#sent].data and sent[#sent].data.tiles == nil
        and tostring(sent[#sent].data.text):find("Walk back into the grow room"))
    hourOfDay = 12
    R.remove("500_500_0")

    do -- Power loss: lamps go dark, the schedule clock keeps running, and flowering plants pay for the lit hours lost.
    local oldOutdoor = R.outdoor
    R.outdoor = function() return { t = 15, h = 40 } end   -- mild, dry air so only the outage adds stress here
    R.register(fakeSquares["500_500_0"], owner, wall)
    R.rebuild(wall)
    fire("OnClientCommand", "CannabisMod", "roomSetSchedule", owner, { x = 500, y = 500, z = 0, schedule = "12/12" })
    local flower = CannabisMod.Registry.addPlant(501, 502, 0, CannabisMod.Genetics.newSeed(T.INDICA))
    flower.stage = C.STAGE.Flowering; flower.stress = 0
    local seedling = CannabisMod.Registry.addPlant(500, 504, 0, CannabisMod.Genetics.newSeed(T.INDICA))
    seedling.stage = C.STAGE.Seedling; seedling.stress = 0
    local outsider = CannabisMod.Registry.addPlant(504, 502, 0, CannabisMod.Genetics.newSeed(T.INDICA))
    outsider.stage = C.STAGE.Flowering; outsider.stress = 0
    hourOfDay = 10
    R.tick(1000)
    check("powered room: no outage", R.roomAt(500, 500, 0).powered == nil and R.poweredAt(501, 501, 0) == true)
    for x = 500, 502 do for y = 500, 504 do fakeSquares[x .. "_" .. y .. "_0"].power = false end end
    R.tick(1001)
    check("panel without power: room is dead and the lamp glow is switched off",
        R.poweredAt(501, 501, 0) == false and lampA.objs[1].md.DDRoomOff == true and R.poweredAt(504, 501, 0) == nil)
    local lampList = CannabisMod.Light.lampsAt(501, 502, 0)
    check("dead room lamps don't light plants", lampList.cap == nil)
    check("schedule clock keeps running through the outage", TS.scheduleAt(501, 501, 0) == "12/12")
    for _ = 1, 12 do R.tick(1002) end   -- two lit hours more (12 ticks of ten minutes) while dark hours are not counted below
    hourOfDay = 22
    for _ = 1, 6 do R.tick(1003) end     -- an hour in the dark hours adds no lit time
    for x = 500, 502 do for y = 500, 504 do fakeSquares[x .. "_" .. y .. "_0"].power = true end end
    R.tick(1004)
    local lost = (1 + 12) / 6
    check("outage penalty: flowering plant in the room gets stress for the lit hours lost",
        math.abs(flower.stress - lost * C.Rooms.OUTAGE_STRESS_PER_LIT_HOUR) < 0.01)
    check("seedling and plants outside the room are untouched", seedling.stress == 0 and outsider.stress == 0)
    check("power back: lamps glow again", lampA.objs[1].md.DDRoomOff == nil and R.roomAt(500, 500, 0).powered == nil)
    local log = R.roomAt(500, 500, 0).log
    local lostAt, backAt = nil, nil
    for i, e in ipairs(log or {}) do
        if e.text == "Power lost" then lostAt = i end
        if e.text:find("Power restored") and e.text:find("1 flowering") then backAt = i end
    end
    check("the outage is logged", lostAt ~= nil and backAt ~= nil and backAt > lostAt)

    -- The Room Power Penalty option turns the extra stress off.
    flower.stress = 0
    SandboxVars = { CannabisMod = { RoomPowerPenalty = false } }
    for x = 500, 502 do for y = 500, 504 do fakeSquares[x .. "_" .. y .. "_0"].power = false end end
    hourOfDay = 10
    R.tick(1100); R.tick(1101)
    for x = 500, 502 do for y = 500, 504 do fakeSquares[x .. "_" .. y .. "_0"].power = true end end
    R.tick(1102)
    check("penalty option off: no extra stress", flower.stress == 0)
    SandboxVars = nil

    -- Debug: cutting power at the panel works like a real outage, with the grid still on.
    hourOfDay = 10
    R.tick(1200)
    local panelObj = fakeSquares["500_500_0"].objs[#fakeSquares["500_500_0"].objs]
    fire("OnClientCommand", "CannabisMod", "debugRoomPower", owner, { x = 500, y = 500, z = 0, cut = true })
    check("debug cut: the room loses power at once and the lamps go dark",
        R.poweredAt(501, 501, 0) == false and R.roomAt(500, 500, 0).powered == false and lampA.objs[1].md.DDRoomOff == true
        and CannabisMod.Light.lampsAt(501, 502, 0).cap == nil)
    check("debug cut: the panel object knows, so the menu offers to restore", panelObj.md.DDPowerCut == true)
    R.tick(1201)
    check("debug cut holds through the ten-minute check while the grid is on", R.roomAt(500, 500, 0).powered == false)
    fire("OnClientCommand", "CannabisMod", "debugRoomPower", owner, { x = 500, y = 500, z = 0, cut = false })
    check("debug restore: power and lamp glow come back", R.poweredAt(501, 501, 0) == true and lampA.objs[1].md.DDRoomOff == nil
        and R.roomAt(500, 500, 0).powered == nil and panelObj.md.DDPowerCut == nil)
    local cutLogged = false
    for _, e in ipairs(R.roomAt(500, 500, 0).log or {}) do if e.text == "Power cut (debug)" then cutLogged = true end end
    check("the debug cut is logged as such", cutLogged)
    CannabisMod.Registry.removePlant(501, 502, 0); CannabisMod.Registry.removePlant(500, 504, 0); CannabisMod.Registry.removePlant(504, 502, 0)
    R.remove("500_500_0")
    R.outdoor = oldOutdoor
    end

    do -- Light leaks and blackout curtains
        IsoObject = { new = function(_, _, sprite) return { sprite = sprite, md = {} } end }
        for x = 800, 804 do for y = 800, 803 do fakeSquare(x, y, 0, false, true) end end
        for _, k in ipairs({ { 805, 801 }, { 805, 802 }, { 802, 799 } }) do fakeSquare(k[1], k[2], 0, true, true) end
        for _, sq in pairs(fakeSquares) do
            if not sq.AddTileObject then sq.AddTileObject = function(self, obj) table.insert(self.objs, obj) end end
        end
        local function gate(a, b) return a:isOutside() ~= b:isOutside() end
        local oldKind, oldBlocked = R.edgeKind, R.edgeBlocked
        R.edgeBlocked = gate
        R.edgeKind = function(a, b)
            local ax, ay, bx, by = a:getX(), a:getY(), b:getX(), b:getY()
            local function pair(x1, y1, x2, y2) return (ax == x1 and ay == y1 and bx == x2 and by == y2) or (ax == x2 and ay == y2 and bx == x1 and by == y1) end
            if pair(804, 801, 805, 801) then return "door" end
            if pair(802, 800, 802, 799) then return "window" end
            return nil
        end
        table.insert(fakeSquares["800_800_0"].objs, { sprite = "dazeddank_rooms_01_0", md = {} })
        R.register(fakeSquares["800_800_0"], owner)
        fire("OnClientCommand", "CannabisMod", "roomSetSchedule", newPlayer(801, 801, 5), { x = 800, y = 800, z = 0, schedule = "12/12" })
        local ops = R.openingsOf("800_800_0")
        check("the room finds its door and window, both uncovered", #ops == 2 and not ops[1].covered and not ops[2].covered
            and ((ops[1].kind == "window") ~= (ops[2].kind == "window")))

        local outLamp = fakeSquares["805_801_0"]
        outLamp.objs[1] = { sprite = "dazeddank_plants_01_198", md = {} }
        fire("LoadGridsquare", outLamp)  -- announce the placed lamp to the light index
        hourOfDay = 22
        local reach = CannabisMod.Light.lampsAt(804, 802, 0)
        check("an outside lamp leaks in through an uncovered door", reach.cap ~= nil and reach.anyLong)

        local near = newPlayer(805, 801, 5)
        near.inv:AddItems(C.Rooms.CURTAIN_ITEM, 1)
        fire("OnClientCommand", "CannabisMod", "hangCurtain", near, { x = 805, y = 801, z = 0, dir = "W" })
        check("hanging a curtain uses the item and covers the door", near.inv:count(C.Rooms.CURTAIN_ITEM) == 0 and R.openingsOf("800_800_0")[1].covered ~= R.openingsOf("800_800_0")[2].covered)
        local overlay = false
        for _, e in ipairs(fakeSquares["805_801_0"].objs) do if e.sprite == C.Rooms.CURTAIN_SPRITES.door.W then overlay = true end end
        check("the curtain overlay is drawn on the frame", overlay)
        check("a covered door blocks the outside lamp", CannabisMod.Light.lampsAt(804, 802, 0).cap == nil)
        fire("OnClientCommand", "CannabisMod", "hangCurtain", near, { x = 805, y = 801, z = 0, dir = "W" })
        check("a frame takes only one curtain", near.inv:count(C.Rooms.CURTAIN_ITEM) == 0)
        fire("OnClientCommand", "CannabisMod", "hangCurtain", near, { x = 803, y = 801, z = 0, dir = "N" })
        check("a plain wall takes no curtain", near.inv:count(C.Rooms.CURTAIN_ITEM) == 0)

        SandboxVars = { CannabisMod = { LightLeaks = false } }
        fire("OnClientCommand", "CannabisMod", "removeCurtain", near, { x = 805, y = 801, z = 0, dir = "W" })
        check("taking the curtain down returns it and opens the frame", near.inv:count(C.Rooms.CURTAIN_ITEM) == 1 and not R.openingsOf("800_800_0")[1].covered)
        check("Light Leaks off: outside lamps never get in", CannabisMod.Light.lampsAt(804, 802, 0).cap == nil)
        SandboxVars = nil

        -- Retired curtains: a loaded square loses its overlay, the records go at game start, and inventories are emptied.
        near.inv:AddItems(C.Rooms.CURTAIN_ITEM, 1)
        fire("OnClientCommand", "CannabisMod", "hangCurtain", near, { x = 805, y = 801, z = 0, dir = "W" })
        local function overlayCount() local n = 0 for _, e in ipairs(fakeSquares["805_801_0"].objs) do if (type(e) == "table" and e.sprite or e) == C.Rooms.CURTAIN_SPRITES.door.W then n = n + 1 end end return n end
        check("retire: a hung curtain to clear", overlayCount() == 1 and R.openingsOf("800_800_0")[1].covered ~= R.openingsOf("800_800_0")[2].covered)
        fire("LoadGridsquare", fakeSquares["805_801_0"])
        fire("OnGameStart")
        R.rebuild(gate)
        check("retire: loading the square removes the overlay", overlayCount() == 0)
        check("retire: game start forgets the curtain, so the door is open again", not R.openingsOf("800_800_0")[1].covered and not R.openingsOf("800_800_0")[2].covered)
        near.inv:AddItems(C.Rooms.CURTAIN_ITEM, 3)
        local had = near.inv:count(C.Rooms.CURTAIN_ITEM)
        fire("OnClientCommand", "CannabisMod", "retireCurtains", near, {})
        check("retire: curtains in the inventory are removed", had >= 3 and near.inv:count(C.Rooms.CURTAIN_ITEM) == 0
            and sent[#sent].data.text:find("removed " .. had, 1, true))

        hourOfDay = 19
        local p = { x = 803, y = 801, z = 0, warnings = {}, stage = 2, care = 100, stress = 0, lightCap = 85, nextStageAt = 100 }
        check("sun through an open window leaks in the dusk dark hours", R.sunLeakAt("800_800_0", 803, 801, 19))
        CannabisMod.Light.update(p)
        check("the sun leak stresses the plant and warns", p.stress > 0 and p.warnings.lightLeak == true)
        check("the leak is logged", R.roomAt(800, 800, 0).log[#R.roomAt(800, 800, 0).log].text:find("sunlight"))
        check("no sun leak at night or in the lit hours", not R.sunLeakAt("800_800_0", 803, 801, 3) and not R.sunLeakAt("800_800_0", 803, 801, 12))
        -- An empty door frame to the outside lets the sun in too, so the window alone no longer seals the room.
        near.inv:AddItems(C.Rooms.CURTAIN_ITEM, 1)
        fire("OnClientCommand", "CannabisMod", "hangCurtain", near, { x = 802, y = 800, z = 0, dir = "N" })
        check("an empty door frame to the outside lets the sun in", R.sunLeakAt("800_800_0", 803, 801, 19) == 1)

        -- A real door: closed it seeps the DoorLeak share, and a sheet hung and drawn seals it.
        local door = { open = false, sheet = nil }
        function door:IsOpen() return self.open end
        function door:HasCurtains() return self.sheet end
        fakeSquares["804_801_0"].getDoorTo = function() return door end
        local sheet = { shut = false }
        function sheet:IsOpen() return not self.shut end
        local function leakNow() R.rebuild(gate) return R.openingsOf("800_800_0") end
        local function doorOf(ops) for _, o in ipairs(ops) do if o.kind == "door" then return o end end end
        door.open = true
        check("an open door leaks fully", doorOf(leakNow()).leak == 1)
        door.open = false
        local d = doorOf(leakNow())
        check("a closed door with no sheet seeps a quarter by default", math.abs(d.leak - 0.25) < 1e-9 and d.seeps and not d.covered)
        check("the sun seeps in round the closed door at that share", math.abs(R.sunLeakAt("800_800_0", 803, 801, 19) - 0.25) < 1e-9)
        local before = (function() local q = { x = 803, y = 801, z = 0, warnings = {}, stage = 2, care = 100, stress = 0, lightCap = 85, nextStageAt = 100 }
            CannabisMod.Light.update(q) return q end)()
        -- Sun and the lamp outside both seep in, each at a quarter: half a full leak, not a whole one.
        SandboxVars = { CannabisMod = { DoorLeak = 0 } }; leakNow()
        local base = (function() local q = { x = 803, y = 801, z = 0, warnings = {}, stage = 2, care = 100, stress = 0, lightCap = 85, nextStageAt = 100 }
            CannabisMod.Light.update(q) return q end)()
        SandboxVars = nil; leakNow()
        check("a seeping door stresses a plant a quarter as much per source", math.abs(before.stress - base.stress - C.Timer.LEAK_STRESS_PER_HOUR / 6 * 0.5) < 1e-6
            and before.warnings.lightLeak == true)
        check("a lamp seeping in round a closed door isn't the plant's light", CannabisMod.Light.lampsAt(803, 801, 0).cap == nil)
        door.sheet = sheet
        check("an open sheet on the door still seeps", doorOf(leakNow()).seeps)
        sheet.shut = true
        d = doorOf(leakNow())
        check("a drawn sheet on a closed door seals it", d.leak == 0 and d.covered and not R.sunLeakAt("800_800_0", 803, 801, 19))
        door.sheet = nil
        SandboxVars = { CannabisMod = { DoorLeak = 0 } }
        check("Closed Door Light Leak 0: a closed door seals", doorOf(leakNow()).covered)
        SandboxVars = { CannabisMod = { DoorLeak = 100 } }
        check("Closed Door Light Leak 100: a closed door leaks like an open one", doorOf(leakNow()).leak == 1)
        SandboxVars = nil
        fakeSquares["804_801_0"].getDoorTo = nil
        R.edgeKind, R.edgeBlocked = oldKind, oldBlocked
        R.remove("800_800_0")
        hourOfDay = 12
    end

    do -- Hydro and Plants tabs, and the panel's flood timer
        local HY, HC = CannabisMod.Hydro, C.Hydro
        for x = 1100, 1103 do for y = 1100, 1102 do fakeSquare(x, y, 0, false, true) end end
        table.insert(fakeSquares["1100_1100_0"].objs, { sprite = "dazeddank_rooms_01_0", md = {} })
        fakeSquares["1101_1101_0"].objs[1] = { sprite = HC.CONTROL_SPRITE, md = {} }
        fakeSquares["1102_1101_0"].objs[1] = { sprite = HC.FLOOD_SPRITE, md = {} }
        CannabisMod.Registry.setBag(1103, 1100, 0, "dwc")
        local oldBlocked = R.edgeBlocked
        R.edgeBlocked = function() return false end
        local pl = newPlayer(1101, 1100, 8)
        R.register(fakeSquares["1100_1100_0"], pl)
        local pkey = "1100_1100_0"
        local function lastNote() for k = #sent, 1, -1 do if sent[k].data.text then return sent[k].data.text end end return "" end
        local function jug(amount)
            local item = newItem("Base.WaterBottle")
            local fc = { amount = amount }
            function fc:getAmount() return self.amount end
            function fc:getPrimaryFluid() return { getFluidTypeString = function() return "Water" end } end
            function fc:removeFluid(n) self.amount = math.max(0, self.amount - n) end
            item.getFluidContainer = function() return fc end
            return item, fc
        end
        sent = {}
        fire("OnClientCommand", "CannabisMod", "requestRoom", pl, { x = 1100, y = 1100, z = 0 })
        local info = sent[#sent].data
        check("the Hydro tab lists the room's three reservoirs, nearest first", #info.reservoirs == 3 and info.reservoirs[1].name == "RDWC control"
            and info.reservoirs[2].dist == nil and info.reservoirs[3].x ~= nil)

        local bottle, bfc = jug(200)
        pl.inv:addExisting(bottle)
        fire("OnClientCommand", "CannabisMod", "roomHydro", pl, { x = 1100, y = 1100, z = 0, action = "topUp", target = "all" })
        local filled = 0
        for _, row in ipairs(R.reservoirRows(pkey)) do if row.level > 0 then filled = filled + 1 end end
        check("Top Up all fills every reservoir from what the player carries", filled == 3 and bfc.amount < 200)
        check("a bulk action tells the player how many it reached", lastNote():find("3 of 3"))

        pl.inv:addExisting(newItem(C.NUTRIENT_ITEMS.Veg)); pl.inv:addExisting(newItem(C.NUTRIENT_ITEMS.Veg))
        local control = HY.reservoirAt(1101, 1101, 0, "rdwc")
        fire("OnClientCommand", "CannabisMod", "roomHydro", pl, { x = 1100, y = 1100, z = 0, action = "dose", target = "1101_1101_0", nutrient = "Veg" })
        check("Dose one reservoir uses one bottle and mixes the food", control.strength == 1 and control.nutrient == "Veg" and pl.inv:count(C.NUTRIENT_ITEMS.Veg) == 1)
        fire("OnClientCommand", "CannabisMod", "roomHydro", pl, { x = 1100, y = 1100, z = 0, action = "dose", target = "all", nutrient = "Veg" })
        check("Dose all stops when the bottles run out", pl.inv:count(C.NUTRIENT_ITEMS.Veg) == 0)

        fire("OnClientCommand", "CannabisMod", "roomHydro", pl, { x = 1100, y = 1100, z = 0, action = "bleach", target = "1101_1101_0" })
        check("Bleach without rot says the roots are healthy", lastNote():find("healthy"))

        local flood = HY.reservoirAt(1102, 1101, 0, "ebb")
        check("no timer on the panel yet", not HY.hasFloodTimer(flood))
        pl.inv:addExisting(newItem(HC.FLOOD_TIMER_ITEM))
        fire("OnClientCommand", "CannabisMod", "roomFloodTimer", pl, { x = 1100, y = 1100, z = 0, mode = "install" })
        check("the panel's flood timer covers every flood reservoir in the room", HY.hasFloodTimer(flood) and pl.inv:count(HC.FLOOD_TIMER_ITEM) == 0)
        fire("OnClientCommand", "CannabisMod", "roomFloodTimer", pl, { x = 1100, y = 1100, z = 0, mode = "remove" })
        check("taking it off hands the timer back", not HY.hasFloodTimer(flood) and pl.inv:count(HC.FLOOD_TIMER_ITEM) == 1)

        local plant = CannabisMod.Registry.addPlant(1101, 1102, 0, CannabisMod.Genetics.newSeed(T.INDICA))
        plant.stage = C.STAGE.Vegetative
        local rows = R.plantRows(pkey, 10)
        check("the Plants tab lists plants in the room", #rows == 1 and rows[1].x == 1101 and rows[1].stage ~= "?")
        check("a novice reads less than an expert", R.plantRows(pkey, 0)[1].stage ~= nil)
        sent = {}
        fire("OnClientCommand", "CannabisMod", "roomInspectPlant", pl, { x = 1100, y = 1100, z = 0, px = 1101, py = 1102, pz = 0 })
        check("clicking a plant opens Inspect even from across the room", sent[#sent] and sent[#sent].cmd == "plantInfo" and sent[#sent].data.x == 1101)
        sent = {}
        fire("OnClientCommand", "CannabisMod", "roomInspectPlant", pl, { x = 1100, y = 1100, z = 0, px = 50, py = 50, pz = 0 })
        check("only plants in the room can be inspected from the panel", #sent == 0)
        local log = R.roomAt(1100, 1100, 0).log
        check("hydro actions and the flood timer are logged", log and #log >= 4)

        -- The room's water line: a plumbed control bucket's line also refills the room's other reservoirs after a change.
        local PL = CannabisMod.Plumbing
        local registered
        DazedPlumb = { Links = {
            register = function(a) registered = a return true end,
            linkOf = function(obj, id) local md = obj:getModData(); return md.dazedplumbLinks and md.dazedplumbLinks[id] end } }
        PL.registered = nil
        PL.register()
        local controlEntry = fakeSquares["1101_1101_0"].objs[1]
        controlEntry.md.dazedplumbLinks = { [PL.ID] = { source = "tank" } }
        local dwc = HY.reservoirAt(1103, 1100, 0, "dwc")
        dwc.level = 5
        fire("OnClientCommand", "CannabisMod", "roomHydro", pl, { x = 1100, y = 1100, z = 0, action = "change", target = "1103_1100_0" })
        check("an unplumbed reservoir in a room with a line waits on the room's line", dwc.level == 0 and dwc.fillPending
            and R.isWaitingOnLine(dwc) and lastNote():find("room's water line"))
        local controlObj = PL.objectAt(fakeSquares["1101_1101_0"])
        local wants = registered.room(controlObj)
        check("the line's demand includes the room's waiting reservoir", math.abs(wants - HY.capacity(dwc)) < 0.01)
        registered.put(controlObj, wants, false)
        check("the room's line refills it, then stops", math.abs(dwc.level - HY.capacity(dwc)) < 0.01 and not dwc.fillPending
            and registered.room(controlObj) == 0)
        controlEntry.md.dazedplumbLinks = nil
        dwc.level = 5
        fire("OnClientCommand", "CannabisMod", "roomHydro", pl, { x = 1100, y = 1100, z = 0, action = "change", target = "1103_1100_0" })
        check("with no line in the room, a change needs carried water", dwc.level ~= 0 or not dwc.fillPending)
        DazedPlumb = nil

        -- Log entries for schedule, mode, rename, hand floods and root rot.
        local room = R.roomAt(1100, 1100, 0)
        local function logged(pattern)
            for _, e in ipairs(room.log or {}) do if e.text:find(pattern) then return true end end
            return false
        end
        fire("OnClientCommand", "CannabisMod", "roomSetSchedule", pl, { x = 1100, y = 1100, z = 0, schedule = "12/12" })
        fire("OnClientCommand", "CannabisMod", "roomSetMode", pl, { x = 1100, y = 1100, z = 0, mode = "Flower" })
        fire("OnClientCommand", "CannabisMod", "roomRename", pl, { x = 1100, y = 1100, z = 0, name = "Tent A" })
        check("schedule, mode and rename are logged", logged("Lights set to 12/12") and logged("Mode set to Flower") and logged("Renamed to Tent A"))
        control.rot, control.lastTick = HC.ROT_EARLY - 0.01, 0
        HY.advanceReservoir(control, 24)
        check("root rot setting in is logged", control.rot >= HC.ROT_EARLY and logged("Root rot set in"))
        R.logTile("9999_9999_0", "nowhere")
        check("a tile outside any room logs nothing", not logged("nowhere"))
        CannabisMod.Registry.removePlant(1101, 1102, 0)
        R.edgeBlocked = oldBlocked
        R.remove(pkey)
    end

    do -- Climate: the model, equipment control, plant stress and the Drying hooks
        local CL, K = CannabisMod.Climate, C.Climate
        local tg = CL.targets("Flower", false)
        check("targets follow the mode and seedlings want humid air", tg.tHi == 26 and tg.hHi == 50 and CL.targets("Veg", true).hLo == 65)
        local sealedT = CL.balance({ outT = 10, outH = 60, lampHeat = 0, moisture = 0, exhaust = 0, intake = 0 })
        check("no gains: the room settles at the outdoor air", sealedT == 10)
        local hotT = CL.balance({ outT = 10, outH = 60, lampHeat = 8, moisture = 0, exhaust = 0, intake = 0 })
        local ventT = CL.balance({ outT = 10, outH = 60, lampHeat = 8, moisture = 0, exhaust = 1.2, intake = 0.6 })
        check("lamps heat a sealed room and fans cool it", hotT > ventT and ventT > 10)
        local _, wetH = CL.balance({ outT = 10, outH = 60, lampHeat = 0, moisture = 4, exhaust = 0, intake = 0 })
        local _, dryH = CL.balance({ outT = 10, outH = 60, lampHeat = 0, moisture = 4, exhaust = 0, intake = 0, dehumidifier = 1 })
        check("plants raise humidity and a dehumidifier takes it back", wetH > 60 and dryH < wetH)
        local _, two = CL.balance({ outT = 10, outH = 60, lampHeat = 0, moisture = 0, exhaust = 0, intake = 0, humidifier = 2 })
        check("two humidifiers move twice as much", math.abs(two - 60 - 2 * K.HUMIDIFIER) < 0.01)
        local base = { outT = 30, outH = 60, lampHeat = 0, moisture = 0, exhaust = 0, intake = 0 }
        local function with(extra) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(extra) do t[k] = v end return t end
        local acT, acH = CL.balance(with({ cooler = 1 }))
        check("a wall AC cools a room whatever the weather and dries it a little", acT == 30 - K.COOLER_C and acH == 60 - K.COOLER_DRY)
        check("ACs stop at their floor", CL.balance(with({ cooler = 5 })) == K.COOLER_FLOOR_C
            and CL.balance(with({ outT = 8, cooler = 1 })) == 8)
        local sealedLamps = { outT = 29, outH = 40, lampHeat = 8, moisture = 0, exhaust = 0, intake = 0 }
        local hot2 = CL.balance(sealedLamps)
        sealedLamps.cooler = 1
        local held = CL.balance(sealedLamps)
        check("one AC holds a sealed room with two large pro lamps", hot2 > 50 and held <= 29 - K.COOLER_C + 0.01)
        sealedLamps.lampHeat, sealedLamps.cooler = 16, 1
        local over = CL.balance(sealedLamps)
        sealedLamps.cooler = 2
        check("more lamps than the AC can carry warm the room; a second AC catches up", over > 40 and CL.balance(sealedLamps) <= 23.01)
        check("circulation fans take a little off, capped", CL.balance(with({ circfan = 1 })) == 30 - K.CIRC_FAN_C
            and CL.balance(with({ circfan = 5 })) == 30 - K.CIRC_FAN_MAX_C)

        local cr = { temp = 20, hum = 45 }
        local on = CL.control(cr, tg, { heater = true, exhaust = true, intake = true }, nil)
        check("a room inside its range runs nothing", not on.heater and not on.exhaust and not on.intake)
        cr.temp = 18
        on = CL.control(cr, tg, { heater = true }, nil)
        check("cold: the heater runs", on.heater == true)
        cr.temp = 21
        on = CL.control(cr, tg, { heater = true }, nil)
        check("the heater holds on until it is clear of the limit", on.heater == true)
        cr.temp = 22
        on = CL.control(cr, tg, { heater = true }, nil)
        check("then switches off", on.heater == false)
        cr.temp = 30
        on = CL.control(cr, tg, { exhaust = true, intake = true }, nil)
        check("hot: exhaust and intake run together", on.exhaust and on.intake)
        on = CL.control(cr, tg, { exhaust = true, intake = true }, { exhaust = "off" })
        check("a manual off beats auto, and only for that kind", on.exhaust == false and on.intake == true)
        on = CL.control({ temp = 20, hum = 45 }, tg, { heater = true }, { heater = "on" })
        check("a manual on runs even in range", on.heater == true)
        check("kinds the room lacks are not listed", on.exhaust == nil)
        local ac = { temp = 27, hum = 45 }
        on = CL.control(ac, tg, { cooler = true, circfan = true }, nil)
        check("too hot: the AC and circulation fans run", on.cooler == true and on.circfan == true)
        ac.temp = 24.5
        on = CL.control(ac, tg, { cooler = true, circfan = true }, nil)
        check("the AC holds on until 2 C under the top, the fans to 2.5 under", on.cooler == true and on.circfan == true)
        ac.temp = 23.4
        on = CL.control(ac, tg, { cooler = true, circfan = true }, nil)
        check("then both rest", on.cooler == false and on.circfan == false)
        ac.temp = 27
        on = CL.control(ac, tg, { heater = true, cooler = true, circfan = true }, { heater = "on" })
        check("the AC and fans never fight a running heater", on.heater == true and not on.cooler and not on.circfan)
        local s1, hot1 = CL.plantStress(20, 45, true)
        local s2, hot2 = CL.plantStress(35, 45, false)
        local s3, _, wet3 = CL.plantStress(20, 70, true)
        local s4, _, wet4 = CL.plantStress(20, 70, false)
        check("plant stress: comfy none, hot some, wet only matters in flower", s1 == 0 and not hot1 and s2 > 0 and hot2 and s3 > 0 and wet3 and s4 == 0 and not wet4)
        check("wet air dries slower and molds more", CL.dryFactor(80) < CL.dryFactor(40) and CL.moldFactor(80) > CL.moldFactor(40) and CL.moldFactor(60) == 1)

        -- A room with a lamp, a fan and a plant, against a cool, dry outdoors.
        for x = 1300, 1304 do for y = 1300, 1302 do fakeSquare(x, y, 0, false, true) end end
        table.insert(fakeSquares["1300_1300_0"].objs, { sprite = "dazeddank_rooms_01_0", md = {} })
        for x = 1301, 1304 do
            for y = 1301, 1302 do fakeSquares[x .. "_" .. y .. "_0"].objs[1] = { sprite = "dazeddank_plants_01_197", md = {} }; fire("LoadGridsquare", fakeSquares[x .. "_" .. y .. "_0"]) end
        end
        local oldBlocked, oldOutdoor = R.edgeBlocked, R.outdoor
        R.edgeBlocked = function() return false end
        R.outdoor = function() return { t = 10, h = 50 } end
        local cp = newPlayer(1301, 1300, 8)
        R.register(fakeSquares["1300_1300_0"], cp)
        local ckey = "1300_1300_0"
        fire("OnClientCommand", "CannabisMod", "roomSetSchedule", cp, { x = 1300, y = 1300, z = 0, schedule = "24/0" })
        fire("OnClientCommand", "CannabisMod", "roomSetMode", cp, { x = 1300, y = 1300, z = 0, mode = "Flower" })
        local croom = R.roomAt(1300, 1300, 0)
        for _ = 1, 20 do R.tick(2000) end
        check("eight lamps heat the sealed room well above the outdoors", croom.temp > 30 and croom.temp < 10 + 8 * 2 * K.LAMP_HEAT_PER_RADIUS / K.BASE_VENT + 0.01)
        check("the room's air is what Drying and the panel read", select(1, R.climateAt(1301, 1301, 0)) == croom.temp and R.climateAt(50, 50, 0) == nil)

        table.insert(fakeSquares["1304_1300_0"].objs, { sprite = "dazeddank_rooms_01_8", md = {} })
        table.insert(fakeSquares["1304_1301_0"].objs, { sprite = "dazeddank_rooms_01_12", md = {} })
        local settled = croom.temp
        for _ = 1, 30 do R.tick(2001) end
        check("exhaust and intake fans on an outside wall run when it is too hot and cool the room",
            croom.running.exhaust == true and croom.running.intake == true and croom.temp < settled)
        check("equipment present is counted by kind", croom.present.exhaust == 1 and croom.present.intake == 1)

        -- A fan on a wall to the next room moves a quarter as much air.
        check("a fan's wall to outdoors is full strength", R.wallFactor(fakeSquares["1304_1300_0"], "S") == 1)
        fakeSquare(1304, 1299, 0, false, true)
        check("a fan's wall to another indoor space is a quarter", R.wallFactor(fakeSquares["1304_1300_0"], "S") == K.INSIDE_WALL_FACTOR)
        fakeSquares["1304_1299_0"] = nil

        fire("OnClientCommand", "CannabisMod", "roomOverride", cp, { x = 1300, y = 1300, z = 0, kind = "exhaust", state = "off" })
        check("manual off switches the exhaust at once", croom.running.exhaust == false and croom.override.exhaust == "off")
        fire("OnClientCommand", "CannabisMod", "roomOverride", cp, { x = 1300, y = 1300, z = 0, kind = "intake", state = "on" })
        check("manual on runs a fan the auto control would leave off", croom.running.intake == true)
        fire("OnClientCommand", "CannabisMod", "roomOverride", cp, { x = 1300, y = 1300, z = 0, kind = "intake", state = "auto" })
        fire("OnClientCommand", "CannabisMod", "roomOverride", cp, { x = 1300, y = 1300, z = 0, kind = "exhaust", state = "auto" })
        fire("OnClientCommand", "CannabisMod", "roomOverride", cp, { x = 1300, y = 1300, z = 0, kind = "kettle", state = "on" })
        check("auto clears the override, an unknown kind is ignored", croom.override.exhaust == nil and croom.override.kettle == nil)

        -- A heat wave: the fans can't beat the outdoors, a wall AC and a circulation fan can.
        R.outdoor = function() return { t = 35, h = 50 } end
        for _ = 1, 40 do R.tick(2001) end
        local wave = croom.temp
        table.insert(fakeSquares["1302_1300_0"].objs, { sprite = "dazeddank_rooms_01_32", md = {} })
        table.insert(fakeSquares["1303_1300_0"].objs, { sprite = "dazeddank_rooms_01_36", md = {} })
        for _ = 1, 40 do R.tick(2001) end
        check("in a heat wave the exhaust can't cool past the outdoors but a wall AC can", wave >= 35
            and croom.running.cooler == true and croom.running.circfan == true and croom.temp < wave - K.COOLER_C
            and croom.present.cooler == 1 and croom.present.circfan == 1)
        local LHc = CannabisMod.LampHeat
        local acObj = { getSprite = function() return { getName = function() return "dazeddank_rooms_01_33" end } end,
            getSquare = function() return fakeSquares["1302_1300_0"] end }
        check("a running AC cools its Dazed Climate room too", LHc.isCooler(acObj) and LHc.coolerHeat(acObj) == K.COOLER_HEAT)
        croom.running.cooler = false
        check("an idle AC gives Dazed Climate nothing", LHc.coolerHeat(acObj) == 0)
        table.remove(fakeSquares["1303_1300_0"].objs); table.remove(fakeSquares["1302_1300_0"].objs)
        R.outdoor = function() return { t = 10, h = 50 } end

        for x = 1300, 1304 do for y = 1300, 1302 do fakeSquares[x .. "_" .. y .. "_0"].power = false end end
        R.tick(2002)
        check("no power: no equipment runs", not croom.running.exhaust and not croom.running.intake and croom.powered == false)
        for x = 1300, 1304 do for y = 1300, 1302 do fakeSquares[x .. "_" .. y .. "_0"].power = true end end
        R.tick(2003)

        -- Plants feel it: too hot stresses them and warns, a wet flower room warns of mold.
        local cplant = CannabisMod.Registry.addPlant(1301, 1302, 0, CannabisMod.Genetics.newSeed(T.INDICA))
        cplant.stage = C.STAGE.Flowering; cplant.stress = 0
        croom.temp, croom.hum = 40, 70
        R.outdoor = function() return { t = 40, h = 70 } end
        R.tick(2004)
        check("heat and wet air stress a flowering plant and warn", cplant.stress > 0 and cplant.warnings.roomTemp and cplant.warnings.roomHumid)
        local logged = false
        for _, e in ipairs(croom.log) do if e.text:find("Mold risk") then logged = true end end
        check("the mold risk is logged", logged)
        R.outdoor = function() return { t = 22, h = 45 } end
        croom.temp, croom.hum = 22, 45
        for x = 1301, 1304 do for y = 1301, 1302 do
            local objs = fakeSquares[x .. "_" .. y .. "_0"].objs
            for k = #objs, 1, -1 do if objs[k].sprite == "dazeddank_plants_01_197" then table.remove(objs, k) end end
        end end
        R.tick(2005)
        check("comfortable air clears the warnings", cplant.warnings.roomTemp == nil and cplant.warnings.roomHumid == nil)
        cplant.stage = C.STAGE.Seedling
        R.tick(2006)
        check("seedlings in a Flower room are flagged", croom.notes[1] and croom.notes[1]:find("Seedlings"))

        -- The panel tells the client what it needs for the Climate tab.
        sent = {}
        fire("OnClientCommand", "CannabisMod", "requestRoom", cp, { x = 1300, y = 1300, z = 0 })
        local cinfo = sent[#sent].data.climate
        check("info carries the climate", cinfo and cinfo.enabled and cinfo.temp and cinfo.targets.tHi and cinfo.present.exhaust == 1 and cinfo.notes[1])

        -- Drying inside the room follows the room's air.
        local DR = CannabisMod.Drying
        croom.temp, croom.hum = 20, 80
        local wetEnv = DR.environment(fakeSquares["1301_1301_0"])
        croom.hum = 40
        local dryEnv = DR.environment(fakeSquares["1301_1301_0"])
        check("drying reads the room's temperature and humidity", wetEnv.tempC == 20 and wetEnv.hum == 80 and dryEnv.hum == 40)
        check("humid room: slower drying, more mold", DR.dryRate(wetEnv) < DR.dryRate(dryEnv) and DR.moldPerHour(wetEnv, 1) > DR.moldPerHour(dryEnv, 1))

        -- With room climate switched off the air sits at the targets and nothing stresses.
        local oldVars = SandboxVars
        SandboxVars = { CannabisMod = { RoomClimate = false } }
        cplant.stage = C.STAGE.Flowering; cplant.stress = 0
        R.tick(2007)
        check("climate off: no stress, no room air for Drying", cplant.stress == 0 and R.climateAt(1301, 1301, 0) == nil and croom.temp == 23 and croom.hum == 45)
        SandboxVars = oldVars
        CannabisMod.Registry.removePlant(1301, 1302, 0)
        R.edgeBlocked, R.outdoor = oldBlocked, oldOutdoor
        R.remove(ckey)
    end

    do -- Climate equipment items exist everywhere they must
        local function readAll(path) local f = assert(io.open(MOD .. "../" .. path)); local t = f:read("*a"); f:close(); return t end
        local items, recipes = readAll("scripts/CannabisItems.txt"), readAll("scripts/CannabisRecipes.txt")
        local names, tips, recipeNames = readAll("lua/shared/Translate/EN/ItemName.json"), readAll("lua/shared/Translate/EN/Tooltip.json"), readAll("lua/shared/Translate/EN/Recipes.json")
        local gear = { ExhaustFan = "DDMakeExhaustFan", IntakeFan = "DDMakeIntakeFan", Heater = "DDMakeHeater", Dehumidifier = "DDMakeDehumidifier", Humidifier = "DDMakeHumidifier",
            WallAC = "DDMakeWallAC", CirculationFan = "DDMakeCirculationFan" }
        local all = true
        for item, recipe in pairs(gear) do
            local f = io.open(MOD .. "../textures/Item_" .. item .. ".png", "rb")
            if f then f:close() end
            if not (items:find("item " .. item, 1, true) and recipes:find("craftRecipe " .. recipe, 1, true) and names:find("CannabisMod." .. item, 1, true)
                and tips:find("Tooltip_DD_" .. item, 1, true) and recipeNames:find(recipe, 1, true) and f
                and items:find(recipe, 1, true)) then
                all = false
                print("  missing piece for " .. item)
            end
        end
        check("every climate item has its script, recipe, names, tooltip, icon and magazine entry", all)
        local sprites = 0
        for _ in pairs(C.Rooms.EQUIPMENT) do sprites = sprites + 1 end
        check("equipment sprites cover 8 fan facings, 3 old floor units, 20 wall-unit facings and the drip tank", sprites == 32)
        local wallOk = true
        for n = 20, 31 do
            local g = C.Rooms.EQUIPMENT["dazeddank_rooms_01_" .. n]
            if not (g and g.wall and not g.facing) then wallOk = false end
        end
        check("wall units hang in four facings and never count as fan air", wallOk)
    end

    -- A huge indoor space hits the cap and falls back to a radius around the panel.
    for x = 600, 640 do for y = 600, 640 do fakeSquare(x, y, 0, false, true) end end
    local bigSet, bigCount, bigCapped = R.fill(fakeSquares["620_620_0"], function() return false end)
    local inRadius = (2 * C.Rooms.FALLBACK_RADIUS + 1) ^ 2
    check("past the cap the room is a radius", bigCapped and bigCount > C.Rooms.MAX_TILES and bigSet["620_620_0"] and bigSet["630_630_0"] and not bigSet["631_620_0"])
    local n = 0
    for _ in pairs(bigSet) do n = n + 1 end
    check("radius room size", n == inRadius)

    check("outdoor panel refused", R.register(fakeSquare(700, 700, 0, true, true), owner, wall) == false)
end)()

-- Grow room panel: the Lights tab draws without errors
do
    local oldRequire = require
    require = function(n) if n:sub(1, 5) == "ISUI/" then return end return oldRequire(n) end
    ISPanel = {}
    function ISPanel:derive() local c = {}; c.__index = c; setmetatable(c, { __index = self }); return c end
    function ISPanel:new(x, y, w, h) return { x = x, y = y, width = w, height = h } end
    function ISPanel:createChildren() end
    UIFont = { Small = "S", Medium = "M" }
    local buttons, texts = {}, {}
    CannabisMod.RoomPanel = { choiceButton = function(_, x, y, w, label, active) buttons[#buttons + 1] = { label = label, active = active } end }
    dofile(MOD .. "client/CannabisMod/CannabisLightsTab.lua")
    require = oldRequire
    local info = { name = "Mother Room", x = 1, y = 2, z = 0, schedule = "18/6", mode = "Veg", tiles = 40, hour = 9, powered = true, lamps = {} }
    for i = 1, 14 do info.lamps[i] = { name = "Pro grow lamp", x = i, y = 1, z = 0, powered = i ~= 2, lit = i ~= 3 } end
    local tab = CannabisMod.LightsTab:new(0, 0, 560, 392, info, { schedule = function() end, mode = function() end, rename = function() end })
    tab.drawText = function(_, text) texts[#texts + 1] = text end
    tab.drawRect = function() end
    tab:createChildren(); tab:createChildren()
    check("lights tab builds its seven buttons once", #buttons == 7 and buttons[2].active == true and buttons[1].active == false)
    tab:render()
    local joined = table.concat(texts, "|")
    check("lights tab shows the room, the lamp states and the overflow", joined:find("Mother Room", 1, true) and joined:find("No power", 1, true)
        and joined:find("Dark hours", 1, true) and joined:find("+3 more", 1, true))
    texts = {}
    info.lamps, info.powered = {}, false
    tab:render()
    joined = table.concat(texts, "|")
    check("an empty room says so, and a dead panel warns", joined:find("No lamps yet", 1, true) and joined:find("NO POWER", 1, true))
end


-- Grow room panel: the Hydro and Plants tabs build their rows and scroll
;(function()
    local oldRequire = require
    require = function(n) if n:sub(1, 5) == "ISUI/" then return end return oldRequire(n) end
    UIFont = { Small = "S", Medium = "M" }
    local made, removed = {}, 0
    CannabisMod.RoomPanel = { choiceButton = function(_, x, y, w, label, active, onClick)
        local b = { x = x, y = y, w = w, label = label, active = active, click = onClick }
        made[#made + 1] = b
        return b
    end }
    dofile(MOD .. "client/CannabisMod/CannabisRowsTab.lua")
    dofile(MOD .. "client/CannabisMod/CannabisHydroTab.lua")
    dofile(MOD .. "client/CannabisMod/CannabisPlantsTab.lua")
    dofile(MOD .. "client/CannabisMod/CannabisClimateTab.lua")
    dofile(MOD .. "client/CannabisMod/CannabisLogTab.lua")
    require = oldRequire
    local calls = {}
    local actions = {
        override = function(kind, state) calls[#calls + 1] = { "override", kind, state } end,
        hydro = function(action, target, nutrient) calls[#calls + 1] = { "hydro", action, target, nutrient } end,
        floodTimer = function(mode) calls[#calls + 1] = { "flood", mode } end,
        highlight = function(x, y, z) calls[#calls + 1] = { "show", x, y, z } end,
        inspect = function(x, y, z) calls[#calls + 1] = { "inspect", x, y, z } end,
    }
    local function stub(tab)
        tab.removeChild = function() removed = removed + 1 end
        tab.drawText = function() end
        tab.drawRect = function() end
        return tab
    end
    local info = { mode = "Flower", floodTimer = false, reservoirs = {}, plants = {} }
    for i = 1, 14 do info.reservoirs[i] = { key = "k" .. i, name = "DWC bucket", x = i, y = 1, z = 0, level = 5, cap = 15, strength = 0.5, rot = 0, pump = true } end
    local tab = stub(CannabisMod.HydroTab:new(0, 0, 560, 392, info, actions))
    tab:createChildren(); tab:createChildren()
    check("Hydro tab: 4 'all' buttons, the flood timer button and 5 buttons for each visible row",
        #made == 4 + 1 + 10 * 5 and #tab:visibleRows() == 10)
    made[1].click()
    check("Top Up all uses the room's food: bloom in a flower room", calls[1][1] == "hydro" and calls[1][2] == "topUp" and calls[1][3] == "all" and calls[1][4] == "Bloom")
    for _, b in ipairs(made) do if b.label == "Show" then b.click() break end end
    check("Show tints the row's equipment", calls[#calls][1] == "show" and calls[#calls][2] == 1)
    made[5].click()
    check("the flood timer button fits one when none is on the panel", calls[#calls][1] == "flood" and calls[#calls][2] == "install")
    made = {}
    tab:onMouseWheel(3)
    check("scrolling rebuilds the row buttons from the new position", tab.scroll == 3 and #made == 10 * 5 and removed == 50 and tab:visibleRows()[1].row.key == "k4")
    tab:onMouseWheel(99)
    check("scrolling stops at the last row", tab.scroll == 4)
    tab:render()

    made = {}
    local pinfo = { plants = {} }
    for i = 1, 3 do pinfo.plants[i] = { x = i, y = 2, z = 0, name = "Cannabis Plant", stage = "Vegetative", water = "60%", health = "Good", warnings = i - 1 } end
    local ptab = stub(CannabisMod.PlantsTab:new(0, 0, 560, 392, pinfo, actions))
    ptab:createChildren()
    check("Plants tab: one Inspect button per plant", #made == 3 and made[2].label == "Inspect")
    made[2].click()
    check("Inspect sends the plant's tile", calls[#calls][1] == "inspect" and calls[#calls][2] == 2 and calls[#calls][3] == 2)
    ptab:render()
    pinfo.plants = {}
    ptab:rebuild(); ptab:render()
    check("an empty room draws without errors", true)

    -- Climate tab: readouts, a row of Auto/On/Off per fitted kind, and notes.
    made = {}
    local texts = {}
    local cinfo = { powered = true, climate = {
        enabled = true, temp = 31.2, hum = 45, outT = 12, outH = 55,
        targets = { tLo = 20, tHi = 26, hLo = 40, hHi = 50 }, present = { exhaust = 2, heater = 1 },
        running = { exhaust = true, heater = false }, override = { heater = "off" }, notes = { "Seedlings are in a Flower room: set Veg mode" },
    } }
    local ctab = stub(CannabisMod.ClimateTab:new(0, 0, 560, 392, cinfo, actions))
    ctab.drawText = function(_, text) texts[#texts + 1] = text end
    ctab:createChildren(); ctab:createChildren()
    check("Climate tab: Auto, On and Off for each fitted kind, the manual one marked", #made == 6 and made[1].label == "Auto" and made[1].active == true
        and made[4].active == false and made[6].label == "Off" and made[6].active == true)
    made[2].click()
    check("On sends that kind's override", calls[#calls][1] == "override" and calls[#calls][2] == "exhaust" and calls[#calls][3] == "on")
    ctab:render()
    local joined = table.concat(texts, "|")
    check("Climate tab shows the readings, the equipment state and the note", joined:find("31.2", 1, true) and joined:find("Exhaust fan x2", 1, true)
        and joined:find("Running", 1, true) and joined:find("(manual)", 1, true) and joined:find("Seedlings", 1, true))
    texts = {}
    cinfo.climate.enabled = false
    ctab:render()
    check("Climate tab says so when room climate is off", table.concat(texts, "|"):find("switched off", 1, true))
    texts = {}
    cinfo.climate.enabled, cinfo.powered, cinfo.climate.present = true, false, {}
    ctab:render()
    check("no power and no equipment are both said", table.concat(texts, "|"):find("NO POWER", 1, true) and table.concat(texts, "|"):find("None yet", 1, true))

    -- Log tab: newest first, with ages.
    made = {}
    texts = {}
    local linfo = { now = 100, log = { { t = 10, text = "Power lost" }, { t = 99.5, text = "Power restored" }, { t = 90, text = "Light leak" } } }
    local ltab = stub(CannabisMod.LogTab:new(0, 0, 560, 392, linfo, actions))
    ltab.drawText = function(_, text) texts[#texts + 1] = text end
    ltab:createChildren()
    check("Log tab lists the newest entry first", ltab:rows()[1].text == "Light leak" and ltab:rows()[3].text == "Power lost")
    ltab:render()
    joined = table.concat(texts, "|")
    check("Log tab shows ages", joined:find("just now", 1, true) and joined:find("10 h ago", 1, true) and joined:find("3 d ago", 1, true))
    check("ages read well", CannabisMod.LogTab.ago(0.2) == "just now" and CannabisMod.LogTab.ago(5) == "5 h ago" and CannabisMod.LogTab.ago(72) == "3 d ago")
    linfo.log = {}
    ltab:rebuild(); texts = {}; ltab:render()
    check("an empty log says so", table.concat(texts, "|"):find("Nothing has happened", 1, true))
end)()

-- ---- XL pots, cutting budget, topping, mothers ----------------------------
local GB = C.GrowBag
check("XL kinds exist", GB.xlbag and GB.xldwc and GB.xlbag.mother and GB.xldwc.mother and not GB.large.mother)
check("hydroOf", C.hydroOf("xldwc") == "dwc" and C.hydroOf("dwc") == "dwc" and C.hydroOf("xlbag") == nil and C.hydroOf(nil) == nil)
-- No two container kinds on one sheet claim the same sprite number.
local claimed, clash = {}, nil
for kind, def in pairs(GB) do
    local sheet = C.sheetOf(kind)
    local nums = { def.emptySprite, def.drySprite, def.furnSprite }
    for _, n in ipairs(def.furnSprites or {}) do nums[#nums + 1] = n end
    for _, n in ipairs(nums) do
        local key = sheet .. "_" .. n
        if claimed[key] and claimed[key] ~= kind then clash = key .. " " .. claimed[key] .. "/" .. kind end
        claimed[key] = kind
    end
end
check("no sprite clashes between containers (" .. tostring(clash) .. ")", clash == nil)
check("plant layer sheets stay inside the 512-tile limit", C.OVERLAY_COUNT <= C.MAX_SHEET_TILES)
check("XL bag sprites recognised", C.bagFromSprite("dazeddank_hydro_01_237") == "xlbag" and C.bagFromSprite("dazeddank_hydro_01_236") == "xlbag"
    and C.bagFromFurnSprite("dazeddank_hydro_01_235") == "xlbag")
check("XL DWC sprites recognised", C.bagFromSprite("dazeddank_hydro_01_350") == "xldwc" and C.bagFromFurnSprite("dazeddank_hydro_01_348") == "xldwc")
check("XL plant layer name", C.overlaySprite(4, 1, 3, "sprite", "xlbag") == "dazeddank_overlay_02_" .. (1 + 3 * 4 + 1))

-- cutting budget
local bp = { stage = 2, bag = nil }
check("ground budget 3, XL 8", G.cutBudgetMax(bp) == 3 and G.cutBudgetMax({ bag = "xlbag" }) == 8 and G.cutBudgetMax({ bag = "xldwc" }) == 8)
local spent = { G.spendCut(bp, 100), G.spendCut(bp, 100), G.spendCut(bp, 100), G.spendCut(bp, 100) }
check("3 cuts within budget, the 4th overcuts", spent[1] and spent[2] and spent[3] and not spent[4])
check("budget refills: 3 over 4 days", math.abs(G.cutsAvailable(bp, 100 + 32) - 1) < 0.01 and G.cutsAvailable(bp, 100 + 500) == 3)

-- clone drift: an XL mother loses 0-2 per generation
local xlMom = { type = T.INDICA, sex = C.SEX.FEMALE, genetics = 100, generation = 0, bag = "xlbag" }
local lo, hi = 100, 0
for i = 1, 300 do local g2 = G.cloneFrom(xlMom).genetics; lo = math.min(lo, g2); hi = math.max(hi, g2) end
check("XL mother drift 0-2 (" .. lo .. "-" .. hi .. ")", lo == 98 and hi == 100)

-- topping
worldHours = 5000
local tp = R.addPlant(900, 900, 0, G.newSeed(T.SATIVA))
check("can't top a seedling", R.top(tp, worldHours) ~= nil and not tp.topped)
tp.stage = C.STAGE.Vegetative; tp.nextStageAt = worldHours + 10; tp.stress = 0
check("top in veg", R.top(tp, worldHours) == nil and tp.topped and tp.stress == C.Topping.STRESS
    and math.abs(tp.nextStageAt - (worldHours + 10 + C.Topping.PAUSE_HOURS)) < 0.001)
check("only once", R.top(tp, worldHours) ~= nil and tp.stress == C.Topping.STRESS)
check("info shows topped to anyone", I.buildVisible(tp, 0, worldHours).topped == true)

-- taking cuttings past the budget sets the plant back (via the real command)
local cutter = newPlayer(910, 910, 5)
local snips = cutter.inv:addExisting(newItem("Base.Scissors")); snips.tags["base:scissors"] = true
local cp = R.addPlant(910, 910, 0, G.newSeed(T.INDICA))
cp.stage = C.STAGE.PreFlower; cp.stress = 0; cp.nextStageAt = worldHours + 5
for i = 1, 3 do fire("OnClientCommand", "CannabisMod", "takeCutting", cutter, { x = 910, y = 910, z = 0 }) end
check("3 cuts in budget, still pre-flower", cp.stage == C.STAGE.PreFlower and not cp.warnings.overcut
    and cp.stress == 3 * C.Stress.CUTTING_COST and cutter.inv:count(C.CUTTING_ITEM) == 3)
fire("OnClientCommand", "CannabisMod", "takeCutting", cutter, { x = 910, y = 910, z = 0 })
check("4th cut sets her back to veg", cp.stage == C.STAGE.Vegetative and cp.warnings.overcut
    and cp.nextStageAt > worldHours + 20 and cp.stress == 4 * C.Stress.CUTTING_COST + C.Cuttings.OVERCUT_STRESS)
check("status shows cuttings ready", I.buildVisible(cp, 2, worldHours).cuttings.left == 0 and I.buildVisible(cp, 2, worldHours).cuttings.max == 3)

-- mother perks while held in veg
local mp = R.addPlant(920, 920, 0, G.newSeed(T.INDICA))
mp.bag = "xlbag"; mp.stage = C.STAGE.Vegetative; mp.stress = 30; mp.cutStress = 12
for i = 1, 60 do R.extendVeg(mp, worldHours + i / 6) end        -- 10 hours held
check("XL mother sheds cut stress only (" .. mp.stress .. ")", math.abs(mp.stress - 20) < 0.01 and math.abs(mp.cutStress - 2) < 0.01)
for i = 61, 120 do R.extendVeg(mp, worldHours + i / 6) end      -- 20 hours
check("cut stress fully gone, other stress stays", mp.cutStress < 0.001 and math.abs(mp.stress - 18) < 0.01)
check("XL mother feeds every 96h", math.abs(mp.vegFeedDueAt - (worldHours + 1 / 6 + 96)) < 0.01)
local np = R.addPlant(921, 920, 0, G.newSeed(T.INDICA))
np.stage = C.STAGE.Vegetative; np.stress = 30; np.cutStress = 12
for i = 1, 60 do R.extendVeg(np, worldHours + i / 6) end
check("normal pot keeps its cut stress", np.stress == 30 and math.abs(np.vegFeedDueAt - (worldHours + 1 / 6 + 48)) < 0.01)


-- ---- Strain names are unique; breeding can push flowering speed -----------
local STN = CannabisMod.Strains
check("name registry is live", STN.registry ~= nil and STN.registry["Knox Kush"] == true)
check("first claim keeps the name", STN.claimName("Test Mist") == "Test Mist")
check("second different strain is numbered", STN.claimName("Test Mist") == "Test Mist #2" and STN.claimName("Test Mist") == "Test Mist #3")
check("starter names are reserved", STN.claimName("Knox Kush") == "Knox Kush #2")
check("same strain still breeds true, unnumbered", STN.cross(STN.STARTERS[2], STN.STARTERS[2]).name == "Muldraugh Purple")
local before = 0
for _ in pairs(STN.registry) do before = before + 1 end
local batch = G.seedsFromPollination({ type = T.INDICA, strain = STN.STARTERS[1] }, { type = T.SATIVA, strain = STN.STARTERS[5] })
local after = 0
for _ in pairs(STN.registry) do after = after + 1 end
check("a seed batch claims one name (" .. (after - before) .. ")", after - before == 1 and batch[#batch].strain.name == batch[1].strain.name)
local names = {}
for i = 1, 40 do names[STN.cross(STN.STARTERS[1], STN.STARTERS[4]).name] = true end
local n = 0
for _ in pairs(names) do n = n + 1 end
check("40 crosses, 40 different names (" .. n .. ")", n == 40)
check("flowering speed 50 = normal time", STN.flowerMult({ flw = 50 }) == 1)
check("indica starters flower faster, sativas slower", STN.flowerMult(STN.STARTERS[2]) < 1 and STN.flowerMult(STN.STARTERS[5]) > 1)
check("readout is exact", STN.describe({ ind = 85, pot = 50, yld = 100, flw = 100 }) == "85% indica, potency 0%, yield +25%, flowers 20% faster")
-- A grower keeping the fastest seed of each batch, crossed with itself, for 10 generations.
local line = STN.cross(STN.STARTERS[1], STN.STARTERS[2])
for gen = 1, 10 do
    local best = line
    for k = 1, 6 do
        local kid = STN.crossTraits(line, line)
        if kid.flw > best.flw then best = kid end
    end
    best.name = line.name
    line = best
end
check("selecting for speed reaches the top (" .. line.flw .. ")", line.flw >= 95 and STN.flowerMult(line) <= 0.81)

-- ---- Climate: DazedCore temperatures, lamp heat, outdoor plants, purple buds, curing -----------
do
    local Wx, PT, LH = CannabisMod.Weather, CannabisMod.PlantTemp, CannabisMod.LampHeat
    local W = C.Weather
    local near = function(a, b) return a and b and math.abs(a - b) < 1e-6 end
    local oldVars, oldHour = SandboxVars, hourOfDay
    SandboxVars = nil
    -- Without DazedCore the game's climate manager answers.
    getClimateManager = function() return { getTemperature = function() return 11 end,
        getAirTemperatureForSquare = function() return 13 end, getHumidity = function() return 0.5 end } end
    local wsq = fakeSquare(7000, 7000, 0, true, false)
    check("weather: vanilla outdoor and square reads", Wx.outdoor() == 11 and Wx.tempAt(wsq) == 13 and Wx.tempAt(nil, 4) == 4)
    -- With DazedCore the shared lookup wins.
    local coreT = 8
    DazedCore = { Climate = { outdoor = function() return 2 end, temperatureAt = function() return coreT end } }
    check("weather: DazedCore outdoor and square reads", Wx.outdoor() == 2 and Wx.tempAt(wsq) == 8)
    check("room climate reads DazedCore's outdoor", CannabisMod.Rooms.outdoor().t == 2)
    check("farming conditions read DazedCore's square", (CannabisMod.Farming.conditionsAt(wsq)) == 8)
    check("slowdown 0 at 15, half at 10, stalled at 5", Wx.slowdown(15) == 0 and near(Wx.slowdown(10), 0.5) and Wx.slowdown(5) == 1 and Wx.slowdown(-3) == 1)
    check("purple chance: sativa rarely, indica often", near(Wx.purpleChance({ ind = 0 }), 0.15) and near(Wx.purpleChance({ ind = 100 }), 0.75))
    check("purple prefix falls back to English", Wx.purplePrefix() == "Purple ")

    -- Lamp heat for Dazed Climate rooms.
    local lsq = fakeSquare(7100, 7100, 0, false, true)
    local function lampObj(sq, sprite) return { getSprite = function() return { getName = function() return sprite end } end, getSquare = function() return sq end } end
    local big, bar, chair = lampObj(lsq, "dazeddank_plants_01_200"), lampObj(lsq, "dazeddank_plants_01_222"), lampObj(lsq, "furniture_01_1")
    check("lamp heat: only grow lamps match", LH.match(big) and LH.match(bar) and not LH.match(chair))
    check("lamp heat: a lit 4-radius lamp gives 12, a 1x3 bar 4 per tile", near(LH.heat(big), 12) and near(LH.heat(bar), 4))
    local dark = lampObj(fakeSquare(7101, 7100, 0, false, false), "dazeddank_plants_01_200")
    check("lamp heat: unpowered lamp gives none", LH.heat(dark) == 0)
    SandboxVars = { CannabisMod = { LampsNeedPower = false } }
    check("lamp heat: lamps that need no power stay lit", near(LH.heat(dark), 12))
    SandboxVars = { CannabisMod = { LampHeat = false } }
    check("lamp heat: option off gives none", LH.heat(big) == 0)
    SandboxVars = nil
    local sources = {}
    DazedClimate = { Rooms = { addObjectSource = function(src) sources[#sources + 1] = src end } }
    LH.register(); LH.register()
    check("lamp heat and AC cooling register with Dazed Climate once", #sources == 2 and sources[1].heat == LH.heat
        and sources[2].heat == LH.coolerHeat and sources[2].match == LH.isCooler)

    -- A bar lamp heats Dank's room once, shared across its tiles, the same as for Dazed Climate.
    for x = 7600, 7602 do fakeSquare(x, 7600, 0, false, true) end
    table.insert(fakeSquares["7600_7600_0"].objs, { sprite = "dazeddank_rooms_01_0", md = {} })
    table.insert(fakeSquares["7601_7600_0"].objs, { sprite = "dazeddank_plants_01_222", md = {} })
    table.insert(fakeSquares["7602_7600_0"].objs, { sprite = "dazeddank_plants_01_223", md = {} })
    local Rooms = CannabisMod.Rooms
    hourOfDay = 12
    check("scan room registers", Rooms.register(fakeSquares["7600_7600_0"], newPlayer(7600, 7600, 5), function() return false end))
    check("bar lamp tiles share their lamp's heat", near(Rooms.scan("7600_7600_0").lampHeat, 2 * 4 / 3 * C.Climate.LAMP_HEAT_PER_RADIUS))
    Rooms.remove("7600_7600_0")

    -- Outdoor plants feel the air.
    fakeSquare(7200, 7200, 0, true, false)
    local function outPlant(extra)
        local p = { x = 7200, y = 7200, z = 0, stage = 3, nextStageAt = 100, stress = 0, care = 100, warnings = {}, sex = C.SEX.FEMALE,
                    strain = CannabisMod.Strains.copy(CannabisMod.Strains.STARTERS[2]) }
        for k, v in pairs(extra or {}) do p[k] = v end
        return p
    end
    hourOfDay = 12
    coreT = 10
    local p = outPlant()
    PT.update(p, 50, false)
    check("10 C: stressed, warned, growth half speed", near(p.nextStageAt, 100 + 0.5 / 6) and near(p.stress, C.Climate.TEMP_STRESS_PER_HOUR / 6) and p.warnings.outdoorTemp == true)
    p = outPlant(); PT.update(p, 50, true)
    check("light-stalled plants aren't slowed twice", p.nextStageAt == 100 and p.stress > 0)
    coreT = 3; p = outPlant(); PT.update(p, 50, false)
    check("5 C and below stalls growth", near(p.nextStageAt, 100 + 1 / 6))
    coreT = 22; p = outPlant({ warnings = { outdoorTemp = true } }); PT.update(p, 50, false)
    check("22 C: no stress, warning clears", p.nextStageAt == 100 and p.stress == 0 and p.warnings.outdoorTemp == nil)
    coreT = 35; p = outPlant(); PT.update(p, 50, false)
    check("35 C: heat stress without slowing", p.nextStageAt == 100 and p.stress > 0 and p.warnings.outdoorTemp)
    SandboxVars = { CannabisMod = { PlantTemperature = false } }
    coreT = 3; p = outPlant(); PT.update(p, 50, false)
    check("plant temperature option off: no effect", p.nextStageAt == 100 and p.stress == 0)
    SandboxVars = nil
    p = outPlant({ x = 7299 }); PT.update(p, 50, false)
    check("unloaded square is left alone, even with DazedCore", p.nextStageAt == 100 and p.stress == 0)
    -- Dazed Climate's crop frost owns 0 C and below for outdoor plants.
    coreT = -2; p = outPlant(); PT.update(p, 50, false)
    check("frost without Dazed Climate's crop frost: Dank stresses", p.stress > 0)
    DazedClimate.Crops = { enabled = function() return true end }
    p = outPlant(); PT.update(p, 50, false)
    check("frost with Dazed Climate's crop frost: no double stress, growth still stalled", p.stress == 0 and near(p.nextStageAt, 100 + 1 / 6))
    coreT = 3; p = outPlant(); PT.update(p, 50, false)
    check("cool air above 0 C still stresses with crop frost on", p.stress > 0)
    -- A frost cover keeps the plant warmer.
    DazedClimate.Covers = { at = function() return "Base.Sheet" end }
    coreT = 12; p = outPlant(); PT.update(p, 50, false)
    check("a covered plant at 12 C feels 16 C", p.stress == 0 and p.nextStageAt == 100)
    DazedClimate.Frost = { COVER_BONUS = 2 }
    p = outPlant(); PT.update(p, 50, false)
    check("cover bonus comes from Dazed Climate's Frost", p.stress > 0 and near(p.nextStageAt, 100 + (15 - 14) / 10 / 6))
    DazedClimate.Covers, DazedClimate.Frost = nil, nil
    local Rm = CannabisMod.Rooms
    local oldKeyAt, oldClimateAt = Rm.keyAt, Rm.climateAt
    Rm.keyAt = function() return "room" end
    Rm.climateAt = function() return 10 end
    p = outPlant({ warnings = { outdoorTemp = true } }); PT.update(p, 50, false)
    check("grow room plants are left to the room", p.nextStageAt == 100 and p.stress == 0 and p.warnings.outdoorTemp == nil)
    Rm.keyAt, Rm.climateAt = oldKeyAt, oldClimateAt

    -- Cold nights in late flower.
    local plotObj = setmetatable({}, { __index = function() return nil end })
    check("advanceStage marks the start of flower", (function()
        local fp = R.addPlant(7300, 7300, 0, G.newSeed(T.INDICA))
        fp.stage = C.STAGE.PreFlower; worldHours = 9000
        R.advanceStage(fp)
        local ok = fp.flowerStartAt == 9000
        R.removePlant(7300, 7300, 0)
        return ok
    end)())
    local function flowering(extra)
        return outPlant(extra or { stage = C.STAGE.Flowering, flowerStartAt = 0, nextStageAt = 100 })
    end
    hourOfDay = 23; coreT = 10
    p = flowering()
    for _ = 1, 71 do PT.update(p, 60, false) end
    check("cold night hours add up in late flower", near(p.coldNightHours, 71 / 6) and not p.purpleRolled)
    PT.update(p, 60, false)
    check("12 cold night hours roll purple once", p.purpleRolled == true)
    p = flowering(); PT.update(p, 30, false)
    check("first half of flower doesn't count", p.coldNightHours == nil)
    hourOfDay = 14; p = flowering(); PT.update(p, 60, false)
    check("daytime cold doesn't count", p.coldNightHours == nil)
    hourOfDay = 2; p = flowering({ stage = C.STAGE.Ripe, nextStageAt = 200 }); PT.update(p, 150, false)
    check("ripe plants count cold nights", near(p.coldNightHours, 1 / 6))
    p = flowering({ stage = C.STAGE.Flowering, nextStageAt = 100 })
    PT.update(p, 99, false)
    check("old flowering plants get an estimated flower start", p.flowerStartAt ~= nil and p.flowerStartAt < 99)
    p = flowering({ stage = C.STAGE.Flowering, flowerStartAt = 0, nextStageAt = 100, sex = C.SEX.MALE }); PT.update(p, 60, false)
    check("males don't count cold nights", p.coldNightHours == nil)
    SandboxVars = { CannabisMod = { PurpleBuds = false } }
    p = flowering(); PT.update(p, 60, false)
    check("purple buds option off: no cold night count", p.coldNightHours == nil)
    SandboxVars = nil
    coreT = 3; p = flowering()
    PT.update(p, 60, false)
    check("near freezing costs 2% yield an hour", near(p.coldYieldLoss, W.FREEZE_YIELD_PER_HOUR / 6) and p.coldNightHours == nil)
    for _ = 1, 200 do PT.update(p, 60, false) end
    check("freeze yield loss caps at 25%", near(p.coldYieldLoss, W.FREEZE_YIELD_MAX))
    coreT = -1; p = flowering(); PT.update(p, 60, false)
    check("frost nights cost no Dank yield while Dazed Climate's crop frost is on", p.coldYieldLoss == nil)
    DazedClimate.Crops = nil
    p = flowering(); PT.update(p, 60, false)
    check("frost nights cost yield without it", near(p.coldYieldLoss, W.FREEZE_YIELD_PER_HOUR / 6))
    -- In a timed grow room, night is the lights-off hours.
    local oldSched = Rm.scheduleAt
    Rm.scheduleAt = function() return true, "12/12" end
    check("12/12 room: 7 PM is night", PT.isNight({ x = 0, y = 0, z = 0 }, 19))
    Rm.scheduleAt = function() return true, "18/6" end
    check("18/6 room: 10 PM is lights-on, not night", not PT.isNight({ x = 0, y = 0, z = 0 }, 22))
    Rm.scheduleAt = function() return false, nil end
    check("outside a room the clock decides", PT.isNight({ x = 0, y = 0, z = 0 }, 22) and not PT.isNight({ x = 0, y = 0, z = 0 }, 19))
    Rm.scheduleAt = oldSched
    local function purpleRate(ind)
        local n = 0
        for _ = 1, 2000 do
            local q = { strain = { name = "x", ind = ind, pot = 50, yld = 50, flw = 50 }, x = 0, y = 0, z = 0 }
            PT.rollPurple(q)
            if q.purple then n = n + 1 end
        end
        return n / 2000
    end
    local sat, ind = purpleRate(0), purpleRate(100)
    check("sativa purples rarely (" .. sat .. "), indica often (" .. ind .. ")", sat > 0.1 and sat < 0.2 and ind > 0.7 and ind < 0.8)

    -- Purple plants: tint, quality, name.
    local r, g, b = Wx.purpleTint(1, 1, 1)
    check("purple tint blends toward violet", near(r, 0.76) and near(g, 0.61) and near(b, 0.88))
    local painted
    local isoObj = { setCustomColor = function(_, cr, cg, cb) painted = { cr, cg, cb } end, getSquare = function() return nil end }
    local lo = { getIsoObject = function() return isoObj end }
    local purplePlant = { strain = CannabisMod.Strains.copy(CannabisMod.Strains.STARTERS[1]), purple = true }
    CannabisMod.Farming.applyTint(purplePlant, lo)
    local sr, sg = CannabisMod.Strains.tint(purplePlant.strain)
    check("purple plants are painted purple", painted and painted[2] < sg - 0.1 and painted[1] < sr)
    SandboxVars = { CannabisMod = { StrainTint = false } }
    CannabisMod.Farming.applyTint(purplePlant, lo)
    check("strain tint off: no purple either", painted[1] == 1 and painted[2] == 1 and painted[3] == 1)
    SandboxVars = nil
    local qp = { lightCap = 80, genetics = 80, care = 100 }
    local plain = G.calcQuality(qp, 0, nil); qp.purple = true
    check("purple adds 5% quality", G.calcQuality(qp, 0, nil) == math.floor(plain * 1.05 + 0.5))
    check("purple quality is capped", G.calcQuality({ lightCap = 100, genetics = 100, care = 100, purple = true }, 0, nil) == 100)
    check("no Purple Purple: names that already say purple keep their name",
        Wx.purpleName({ purple = true }, "Muldraugh Purple") == "Muldraugh Purple" and Wx.purpleName({ purple = true }, "PURPLE Haze") == "PURPLE Haze"
        and Wx.purpleName({ purple = true }, "Knox Kush") == "Purple Knox Kush" and Wx.purpleName({}, "Knox Kush") == "Knox Kush")
    check("status shows a purple plant's strain as Purple",
        CannabisMod.Info.buildVisible({ strain = CannabisMod.Strains.copy(CannabisMod.Strains.STARTERS[1]), stage = 5, purple = true }, 3, 0).strain == "Purple Knox Kush")

    -- Harvest carries purple, and freezing nights cut the yield.
    local function harvestOne(x, extra)
        local plot = newPlot(x, 7500, 0); plot.state, plot.typeOfSeed, plot.nbOfGrow = "seeded", "Cannabis", 7
        local rec = R.addPlant(x, 7500, 0, G.newSeed(T.INDICA))
        rec.sex, rec.stage, rec.nextStageAt, rec.lightCap = C.SEX.FEMALE, C.STAGE.Ripe, worldHours + 10, 80
        for k, v in pairs(extra) do rec[k] = v end
        local who = newPlayer(x, 7500, 5)
        math.randomseed(7)
        SFarmingSystem.harvest(SFarmingSystem.instance, plot, who)
        return who.inv.items[1]:getModData().CannabisHarvest
    end
    local hPlain = harvestOne(7500, {})
    local hCold = harvestOne(7501, { purple = true, coldYieldLoss = 0.25 })
    check("harvest carries purple (" .. hPlain.budYield .. " vs " .. hCold.budYield .. " buds)", hCold.purple == true and hPlain.purple == nil
        and hCold.budYield < hPlain.budYield and hCold.quality > hPlain.quality)
    local St = CannabisMod.Strains
    check("plant names: dried, purple, and none without a strain",
        St.plantName({ type = "Indica", strain = St.copy(St.STARTERS[1]) }, "Dried") == "Dried Knox Kush (Indica)"
        and St.plantName({ type = "Indica", purple = true, strain = St.copy(St.STARTERS[1]) }, "Wet") == "Wet Purple Knox Kush (Indica)"
        and St.plantName({ type = "Indica", purple = true, strain = St.copy(St.STARTERS[2]) }, "Wet") == "Wet Muldraugh Purple (Indica)"
        and St.plantName({ type = "Hybrid" }, "Wet") == nil)

    -- Purple carries from the dried plant into buds and joints.
    local pp = newPlayer(0, 0, 8)
    local sc = newItem("Base.Scissors"); sc.tags[ItemTag.SCISSORS] = true
    local dried = newItem(C.DRIED_PLANT_ITEMS.Indica)
    dried:getModData().CannabisHarvest = { type = "Indica", quality = 80, budYield = 1, purple = true,
        strain = CannabisMod.Strains.copy(CannabisMod.Strains.STARTERS[1]) }
    pp.inv:addExisting(sc); pp.inv:addExisting(dried)
    fire("OnClientCommand", "CannabisMod", "trimPlant", pp, { id = dried:getID() })
    local pb
    for _, it in ipairs(pp.inv.items) do if it.fullType == C.Drying.BUD_ITEM then pb = it end end
    check("trimmed purple buds keep purple and say so", pb and pb:getModData().DDBud.purple == true and pb.name:find("Purple Knox Kush Bud") ~= nil)
    pp.inv:addExisting(newItem(C.Smoking.PAPER_ITEM))
    fire("OnClientCommand", "CannabisMod", "rollJoint", pp, { id = pb:getID() })
    local pj
    for _, it in ipairs(pp.inv.items) do if it.fullType == C.Smoking.JOINT_ITEM then pj = it end end
    check("a purple bud rolls a purple joint", pj and pj.name:find("Purple Knox Kush Joint") ~= nil)

    -- Curing temperature.
    check("cure speed: full 15-21, easing to half at 10 and 25", Wx.cureSpeed(18) == 1 and near(Wx.cureSpeed(12.5), 0.75)
        and near(Wx.cureSpeed(5), 0.5) and near(Wx.cureSpeed(23), 0.75) and near(Wx.cureSpeed(30), 0.5) and Wx.cureSpeed(nil) == 1)
    check("hot jars mold 1.5x on missed burps", Wx.cureMoldFactor(26) == 1.5 and Wx.cureMoldFactor(20) == 1)
    local jar = { lastBurp = 0 }
    local warm, cold, unknown = { { cureHours = 0 } }, { { cureHours = 0 } }, { { cureHours = 0 } }
    CannabisMod.Drying.advanceJar(jar, warm, 10, 10, 18)
    CannabisMod.Drying.advanceJar(jar, cold, 10, 10, 5)
    CannabisMod.Drying.advanceJar(jar, unknown, 10, 10, nil)
    check("jars cure slower in the cold", warm[1].cureHours == 10 and near(cold[1].cureHours, 5) and unknown[1].cureHours == 10)
    SandboxVars = { CannabisMod = { CuringTemperature = false } }
    check("curing temperature option off: full speed", Wx.cureSpeed(5) == 1 and Wx.cureMoldFactor(30) == 1)
    SandboxVars = nil
    coreT = 9; fakeSquare(7400, 7400, 0, false, false)
    check("a jar's station reads the square's temperature", CannabisMod.Drying.cureTemp("7400_7400_0") == 9)

    DazedCore, DazedClimate, getClimateManager = nil, nil, nil
    SandboxVars, hourOfDay = oldVars, oldHour
end

do
    -- Drip irrigation: a tank that holds soil pots at a set moisture, in its room or within a radius, and feeds them.
    local HY, DR, GBm, K = CannabisMod.Hydro, CannabisMod.Drip, CannabisMod.GrowBags, C.Drip
    local tsq = fakeSquare(9000, 9000, 0, false, true)
    tsq.objs[1] = { sprite = K.SPRITE, md = {} }
    local function pot(x, y, water)
        local sq = fakeSquare(x, y, 0, false, true)
        local plot = GBm.makePlot(sq, "small")
        R.setBagSoiled(x, y, 0, true)
        plot.waterLvl = water
        return plot
    end
    local near, far = pot(9002, 9000, 10), pot(9010, 9000, 10)
    local bare = fakeSquare(9001, 9001, 0, false, true)
    GBm.makePlot(bare, "small")
    CannabisMod.Farming.getVanilla(9001, 9001, 0).waterLvl = 10
    local r = HY.reservoirAt(9000, 9000, 0, "drip")
    check("a drip tank is a 50 L reservoir", r and r.isDrip and HY.capacity(r) == K.TANK_L)
    r.level, r.dripTick = 50, 0
    DR.run(r, 2)
    check("the drip waters a pot slowly", math.abs(near.waterLvl - (10 + 2 * K.RATE_PER_HOUR)) < 0.01
        and math.abs(r.level - (50 - 2 * K.RATE_PER_HOUR * K.L_PER_POINT)) < 0.001)
    check("pots out of reach and bags with no soil are left alone", far.waterLvl == 10
        and CannabisMod.Farming.getVanilla(9001, 9001, 0).waterLvl == 10)
    DR.run(r, 12)
    check("it holds the pot at the target and no wetter", near.waterLvl == K.TARGET)
    local before = r.level
    DR.run(r, 14)
    check("a pot at the target takes no water", r.level == before)
    near.waterLvl = 20
    tsq.power = false
    DR.run(r, 16)
    check("no power, no drip", near.waterLvl == 20 and r.dripOn == false)
    tsq.power = true
    -- Fertigation: a fed tank feeds each pot once a stage as it waters it.
    local plant = R.addPlant(9002, 9000, 0, CannabisMod.Genetics.newSeed(T.INDICA))
    plant.stage, plant.fedThisStage, plant.care = C.STAGE.Vegetative, 0, 50
    r.nutrient, r.strength = "Veg", 1
    DR.run(r, 18)
    check("a fed tank feeds the pots it waters", plant.fedThisStage == 1 and plant.care > 50 and plant.water == near.waterLvl)
    near.waterLvl = 20
    DR.run(r, 20)
    check("and never twice in a stage", plant.fedThisStage == 1)
    check("the panel and Check see the plants it waters", #HY.servedPlants(r) == 1)
    check("dosing a drip tank feeds nobody at once, it waits for the drip", select(2, HY.dose(r, "Bloom")) == 0 and r.nutrient == "Bloom")
    near.waterLvl = 20
    r.level = 0.1
    DR.run(r, 22)
    check("an empty tank stops", r.level == 0 and near.waterLvl > 20 and near.waterLvl < 30)
    -- On a water line it refills itself once under half, and plain water thins the food.
    local PL = CannabisMod.Plumbing
    local tankObj = { getSprite = function() return { getName = function() return K.SPRITE end } end, getSquare = function() return tsq end }
    r.level, r.strength, r.fillPending = 30, 1, nil
    check("a drip tank above half asks the line for nothing", PL.room(tankObj) == 0)
    r.level = 20
    check("under half it asks to be filled", math.abs(PL.room(tankObj) - 30) < 0.01)
    PL.put(tankObj, 30)
    check("the line fills it and thins the nutrients", math.abs(r.level - 50) < 0.01 and math.abs(r.strength - 0.4) < 0.01 and not r.fillPending)
    R.removePlant(9002, 9000, 0)
    tsq.objs = {}
    HY.cleanup()
    check("a picked-up tank's record is dropped", HY.reservoirAt(9000, 9000, 0, "drip") == nil)
    -- In a grow room it reaches every soil pot in the room, however far, and the panel can switch it off.
    local RM = CannabisMod.Rooms
    for x = 9100, 9108 do for y = 9100, 9102 do fakeSquare(x, y, 0, false, true) end end
    table.insert(fakeSquares["9100_9100_0"].objs, { sprite = "dazeddank_rooms_01_0", md = {} })
    local oldBlocked = RM.edgeBlocked
    RM.edgeBlocked = function() return false end
    RM.register(fakeSquares["9100_9100_0"], newPlayer(9101, 9100, 8))
    local room = RM.roomAt(9100, 9100, 0)
    table.insert(fakeSquares["9101_9102_0"].objs, { sprite = K.SPRITE, md = {} })
    local rp = GBm.makePlot(fakeSquares["9108_9102_0"], "small")
    R.setBagSoiled(9108, 9102, 0, true)
    local rr = HY.reservoirAt(9101, 9102, 0, "drip")
    local reached = false
    for _, t in ipairs(DR.tilesOf(rr)) do if t[1] == 9108 and t[2] == 9102 then reached = true end end
    check("in a grow room the drip reaches the room's pots past its radius", room and reached and rp ~= nil)
    room.override = room.override or {}
    room.override.drip = "off"
    check("the panel can switch the drip off", DR.running(rr) == false)
    room.override.drip = nil
    check("and back to auto", DR.running(rr) == true)
    RM.edgeBlocked = oldBlocked
end

-- Crash recovery: bags, buckets and panels the map kept without their records are rebuilt as their square loads.
do
    require "CannabisMod/CannabisAdopt"
    local Ad, Rooms = CannabisMod.Adopt, CannabisMod.Rooms
    local dsq = fakeSquare(7700, 7700, 0, false, true)
    dsq.objs[1] = C.bagEmptySprite("dwc", true)
    local lsq = fakeSquare(7702, 7700, 0, false, true)
    lsq.objs[1] = C.bagEmptySprite("large", true)
    local fsq = fakeSquare(7704, 7700, 0, false, true)
    fsq.objs[1] = C.SPRITE_SHEET .. "_" .. C.GrowBag.small.furnSprite
    local t1, t2 = fakeSquare(7706, 7700, 0, false, true), fakeSquare(7707, 7700, 0, false, true)
    t1.objs[1], t2.objs[1] = C.bagEmptySprite("ebb", true), C.bagEmptySprite("ebb", true)
    local psq = fakeSquare(7720, 7720, 0, false, true)
    psq.objs[1] = { sprite = "dazeddank_rooms_01_0", md = {} }
    local kept = fakeSquare(7730, 7700, 0, false, true)
    kept.objs[1] = C.bagEmptySprite("small", true)
    R.setBag(7730, 7700, 0, "small"); local keptPlot = SFarmingSystem.instance:plow(kept)
    for _, sq in ipairs({ dsq, lsq, fsq, t1, t2, psq, kept }) do fire("LoadGridsquare", sq) end
    for _ = 1, Ad.START_TICKS + Ad.WAIT_TICKS + 5 do fire("OnTick") end
    local fp = SFarmingSystem.instance
    check("a DWC bucket that lost its record is a working bucket again", R.getBag(7700, 7700, 0) == "dwc"
        and fp:getLuaObjectAt(7700, 7700, 0) ~= nil and #dsq.objs == 0)
    check("a rebuilt bucket asks for its medium again", not R.isBagSoiled(7700, 7700, 0))
    check("a rebuilt soil bag keeps its soil", R.getBag(7702, 7700, 0) == "large" and R.isBagSoiled(7702, 7700, 0))
    check("a bag left as furniture is converted", R.getBag(7704, 7700, 0) == "small" and fp:getLuaObjectAt(7704, 7700, 0) ~= nil)
    local h1 = CannabisMod.Hydro.get(7706, 7700, 0, "ebb")
    check("both halves of a rebuilt flood table pair up", R.getBag(7707, 7700, 0) == "ebb" and h1.partner == "7707_7700_0"
        and CannabisMod.Hydro.get(7707, 7700, 0, "ebb").partner == "7706_7700_0")
    check("a grow room panel that lost its room is registered again", Rooms.scan("7720_7720_0") ~= nil)
    check("a bag that still has its plot is left alone", fp:getLuaObjectAt(7730, 7700, 0) == keptPlot and #kept.objs == 1)

    -- The real plow takes a plot object already on the square as its own: that object must stay.
    local oldPlow, oldGetIso = SFarmingSystem.instance.plow, Plot.getIsoObject
    local tsq = fakeSquare(7740, 7700, 0, false, true)
    tsq.objs[1] = C.bagEmptySprite("dwc", true)
    local orphanObj = tsq:getObjects():get(0)
    SFarmingSystem.instance.plow = function(self, sq)
        local p = oldPlow(self, sq)
        if sq == tsq then p.iso = orphanObj end
        return p
    end
    check("an orphan the plow takes as its plot is kept, not deleted", CannabisMod.GrowBags.adoptOrphan(tsq, orphanObj, "dwc") and #tsq.objs == 1)
    SFarmingSystem.instance.plow = oldPlow

    -- A plot object that still carries its farming state goes back to the farming system as it is, plant and all.
    local vsq = fakeSquare(7742, 7700, 0, false, true)
    local vobj = { md = { state = "seeded", nbOfGrow = 3, health = 80 }, sprite = C.bagEmptySprite("large", true) }
    function vobj:hasModData() return true end
    function vobj:getModData() return self.md end
    function vobj:getSprite() local n = self.sprite return { getName = function() return n end } end
    local loaded = nil
    SFarmingSystem.isValidIsoObject = function(_, o) return o.hasModData ~= nil and o:hasModData() and o:getModData().state ~= nil end
    SFarmingSystem.loadIsoObject = function(self, o) loaded = o; local p = SFarmingSystem.instance:plow(vsq); p.state = o:getModData().state end
    check("a plot object with its farming state is restored as it is", CannabisMod.GrowBags.adoptOrphan(vsq, vobj, "large")
        and loaded == vobj and fp:getLuaObjectAt(7742, 7700, 0).state == "seeded" and R.getBag(7742, 7700, 0) == "large" and R.isBagSoiled(7742, 7700, 0))
    SFarmingSystem.isValidIsoObject, SFarmingSystem.loadIsoObject = nil, nil

    -- A registered bag whose plot lost its object gets it drawn back.
    local rsq = fakeSquare(7744, 7700, 0, false, true)
    R.setBag(7744, 7700, 0, "small")
    local lost = SFarmingSystem.instance:plow(rsq)
    lost.noIso = true
    Plot.getIsoObject = function(self) if self.noIso then return nil end return oldGetIso(self) end
    Plot.addObject = function(self) self.noIso = nil; self.drawnSprite = self.spriteName end
    check("a bag whose plot lost its object is drawn back", Ad.redrawAll() >= 1 and not lost.noIso and lost.drawnSprite == C.bagEmptySprite("small", false))
    check("a bag that has its object isn't drawn twice", Ad.redrawAll() == 0)
    Plot.getIsoObject, Plot.addObject = oldGetIso, nil
end

-- ---- Orphaned plant layers are cleared from a queue a few seconds after load --------
do
    local clock = 0
    local oldTs, oldGet = getTimestampMs, SFarmingSystem.instance.getLuaObjectOnSquare
    getTimestampMs = function() return clock end
    SFarmingSystem.instance.getLuaObjectOnSquare = function() return nil end
    local orphan = fakeSquare(9100, 9100, 0, false, true)
    orphan.objs[1] = C.overlaySprite(3, 1, 2, "sprite")
    local kept = fakeSquare(9102, 9100, 0, false, true)
    kept.objs[1] = C.overlaySprite(3, 1, 2, "sprite")
    fire("LoadGridsquare", orphan)
    clock = 1000
    fire("LoadGridsquare", kept)
    clock = 5500
    CannabisMod.PotPlants.checkOrphans()
    check("orphan queue: a layer with no plot goes once its wait is over", #orphan.objs == 0 and #kept.objs == 1)
    clock = 6500
    CannabisMod.PotPlants.checkOrphans()
    check("orphan queue: later entries follow in order", #kept.objs == 0)
    getTimestampMs, SFarmingSystem.instance.getLuaObjectOnSquare = oldTs, oldGet
end

end)()

-- ---- Cannabis in pots: the pot stays, the plant is a raised layer ------------
do
    loaded["CannabisMod/CannabisCrop"] = nil
    require "CannabisMod/CannabisCrop"
    require "CannabisMod/CannabisPotPlants"
    local sq = { objs = {} }
    local placed = {}
    function sq:AddTileObject(obj) placed[#placed + 1] = obj; table.insert(self.objs, obj) end
    function sq:RemoveTileObject(obj) for i, e in ipairs(self.objs) do if e == obj then table.remove(self.objs, i) break end end end
    function sq:transmitRemoveItemFromSquare() end
    function sq:getObjects()
        local list = self.objs
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    IsoObject = { new = function(_, _, sprite)
        local o = { isOverlay = true, md = {}, sprite = sprite }
        function o:getModData() return self.md end
        function o:getSprite() local n = self.sprite return { getName = function() return n end } end
        function o:setRenderYOffset(v) self.yOff = v end
        function o:transmitCompleteItemToClients() end
        return o end }
    local function overlays()
        local n = 0
        for _, e in ipairs(sq.objs) do if type(e) == "table" and e.isOverlay then n = n + 1 end end
        return n
    end
    CannabisMod.Registry.setBag(1200, 1200, 0, "large")
    local plot = { x = 1200, y = 1200, z = 0, state = "seed", typeOfSeed = "Cannabis", nbOfGrow = 0, health = 100, waterLvl = 100 }
    function plot:getSquare() return sq end
    check("cannabis in a large bag keeps the bag sprite", farming_vegetableconf.getSpriteName(plot) == C.bagEmptySprite("large", true))
    SPlantGlobalObject.setSpriteName(plot, farming_vegetableconf.getSpriteName(plot))
    local ov = placed[#placed]
    check("the plant is its own object, raised onto the soil",
        ov and ov.sprite == C.overlaySprite(3, 1, 1, "sprite", "large") and ov.yOff == C.PLANT_LIFT.large)
    plot.nbOfGrow = 3
    SPlantGlobalObject.setSpriteName(plot, farming_vegetableconf.getSpriteName(plot))
    check("growing swaps the layer instead of stacking another", overlays() == 1 and placed[#placed].sprite ~= ov.sprite)
    plot.state = "plow"
    SPlantGlobalObject.setSpriteName(plot, farming_vegetableconf.getSpriteName(plot))
    check("an emptied bag drops the plant layer", overlays() == 0)
    plot.state, plot.typeOfSeed = "seed", "Tomato"
    SPlantGlobalObject.setSpriteName(plot, "vegetation_farming_01_2")
    check("other crops get no layer", overlays() == 0)
    CannabisMod.Registry.clearBag(1200, 1200, 0)
end

-- ---- Looks genes: shape and colour --------------------------------------------
do
    local St = CannabisMod.Strains
    local kush, haze = St.copy(St.STARTERS[1]), St.copy(St.STARTERS[4])
    check("starters carry a shape and colour", kush.shp == "kush" and kush.col == "green" and St.STARTERS[2].col == "purple")
    local shapes, colours, surprise = {}, {}, 0
    for _ = 1, 2000 do
        local c = St.crossTraits(kush, haze)
        shapes[c.shp] = (shapes[c.shp] or 0) + 1
        colours[c.col] = (colours[c.col] or 0) + 1
        if c.shp ~= "kush" and c.shp ~= "haze" then surprise = surprise + 1 end
    end
    check("crosses take one parent's shape about half the time each", (shapes.kush or 0) > 800 and (shapes.haze or 0) > 800)
    check("a few crosses show a surprise shape (" .. surprise .. ")", surprise > 10 and surprise < 120)
    check("green x green is nearly always green", (colours.green or 0) > 1900)
    local self = St.crossTraits(St.copy(St.STARTERS[2]), St.copy(St.STARTERS[2]))
    check("a strain bred with itself keeps its looks", self.shp == "afghan" and self.col == "purple")
    check("looks survive the network check", St.sanitize(St.copy(St.STARTERS[5])).col == "frosty"
        and St.sanitize({ name = "x", ind = 1, pot = 1, yld = 1, flw = 1, shp = "bogus" }).shp == nil)
    check("older strains get looks from their traits and name", St.shapeOf({ ind = 10 }) == "landrace"
        and St.colourOf({ name = "Cave City Purple" }) == "purple" and St.colourOf({ name = "Plain" }) == "green")
    check("inspect shows the looks", CannabisMod.Info.buildVisible({ strain = St.copy(St.STARTERS[2]), stage = 3 }, 3, 0).looks == "Afghan, Purple")
end

-- ---- UI redesign: plant card and grow room dashboard ---------------------------
do
    require "CannabisMod/CannabisStatusLayout"
    require "CannabisMod/CannabisDashboardLayout"
    local Dash, Lay = CannabisMod.DashboardLayout, CannabisMod.StatusLayout
    local fh, ms = function() return 12 end, function(_, t) return #tostring(t) * 6 end
    local function find(m, kind, pred)
        for _, op in ipairs(m.ops) do if op.kind == kind and (not pred or pred(op)) then return op end end
    end
    local function hitIds(m) local out = {} for _, h in ipairs(m.hits) do out[h.id] = h end return out end
    local plants = {}
    for i = 1, 5 do plants[i] = { x = i, y = 1, z = 0, strain = "Strain " .. i, type = "Indica", stage = "Flowering", stageKey = "Flowering",
        water = "50%", health = "Good", warnings = i == 2 and 2 or 0, sprite = "dazeddank_overlay_01_1", pot = "dazeddank_plants_01_196", lift = 20 } end
    local info = { name = "Shed", mode = "Veg", schedule = "18/6", hour = 3, tiles = 9, lamps = {}, plants = plants,
        reservoirs = { { key = "k", name = "DWC bucket", level = 5, cap = 20, strength = 0.2, nutrient = "Veg", rot = 0, pump = true } },
        equipment = { { kind = "heater", running = true, powered = true } }, openings = {}, log = {}, climate = { enabled = false } }
    local m = Dash.build(info, 0, fh, ms)
    local ids = hitIds(m)
    check("dashboard has its fixed size", m.width == Dash.WIDTH and m.height == Dash.HEIGHT)
    local function hasText(model, str) for _, op in ipairs(model.ops) do if op.kind == "text" and op.text == str then return true end end return false end
    check("the Refresh button reads Refresh by default", hasText(m, "Refresh") and ids.refresh)
    info.refreshLabel = "Updated"
    check("the Refresh button can show the last refresh's outcome", hasText(Dash.build(info, 0, fh, ms), "Updated"))
    info.refreshLabel = nil
    do
        -- A room with all seven kinds of unit: every tile shows, inside the equipment card, with labels that fit.
        local all = {}
        for _, k in ipairs(C.Rooms.EQUIPMENT_ORDER) do all[#all + 1] = { kind = k, running = k == "cooler", powered = true } end
        local full = {}
        for k, v in pairs(info) do full[k] = v end
        full.equipment = all
        local fm = Dash.build(full, 0, fh, ms)
        local tiles, fits, right = 0, true, Dash.WIDTH - 12
        for _, op in ipairs(fm.ops) do
            if op.kind == "equip" then
                tiles = tiles + 1
                if op.x + op.w > right then fits = false end
            end
        end
        local labelsFit = true
        for _, op in ipairs(fm.ops) do
            if op.kind == "text" and op.align == "center" and op.y > 400 and #op.text * 6 > 60 then labelsFit = false end
        end
        local fids = hitIds(fm)
        check("every kind of equipment tile fits in the card", tiles == #C.Rooms.EQUIPMENT_ORDER and fits and fids["equip:cooler"] and fids["equip:drip"])
        check("narrow equipment tiles use short labels", labelsFit and find(fm, "text", function(op) return op.text == "AC" end) ~= nil)
    end
    check("dashboard offers the room actions", ids.rename and ids.mode and ids.schedule and ids.topUpAll and ids.doseAll and ids["res:1"]
        and ids["equip:heater"] and ids.log and ids["plant:1"])
    check("five plants scroll sideways", Dash.maxScroll(info) > 0 and ids.scrollRight ~= nil and ids.scrollLeft == nil)
    check("plant cards draw the plant fitted to its box", find(m, "plant", function(op) return op.fit end) ~= nil)
    check("plant row is clipped", find(m, "clip") ~= nil and find(m, "unclip") ~= nil)
    local far = Dash.build(info, Dash.maxScroll(info), fh, ms)
    local fids = hitIds(far)
    check("scrolled to the end shows the last plant", fids["plant:5"] ~= nil and fids["plant:1"] == nil and fids.scrollLeft ~= nil and fids.scrollRight == nil)
    for _, h in ipairs(far.hits) do
        if h.id:sub(1, 6) == "plant:" then
            check("plant click regions stay inside the row (" .. h.id .. ")", h.x >= Dash.PLANT_AREA.x and h.x + h.w <= Dash.PLANT_AREA.x + Dash.PLANT_AREA.w + 0.01)
        end
    end
    check("room climate off says so", find(m, "text", function(op) return op.text == "Room climate is off" end) ~= nil)
    check("heater tile shows its mode", find(m, "equip", function(op) return op.equipKind == "heater" end) ~= nil
        and find(m, "text", function(op) return op.text == "Auto" end) ~= nil)
    check("long names are shortened to fit the card", find(Dash.build({ plants = { { strain = string.rep("Long", 20) } } }, 0, fh, ms), "text",
        function(op) return op.text:sub(-2) == ".." end) ~= nil)
    check("an empty room still builds", #Dash.build({}, 0, fh, ms).ops > 0)
    local lay = Lay.build({ level = 10, name = "Cannabis Plant", stage = "Flowering", sprite = "s", potSprite = "p", lift = 13,
        traitBars = { ind = 80, pot = 60, yld = 40, flw = 50, potText = "+5%", yldText = "-2%", flwText = "+1%" } }, fh, ms)
    check("plant card draws the plant in its pot", find(lay, "plant", function(op) return op.sprite == "s" and op.pot == "p" and op.lift == 13 end) ~= nil)
    check("plant card fits its width", lay.width == Lay.WIDTH)
    -- Every rendered image the two windows ask for ships with the mod.
    local missing = {}
    for _, model in ipairs({ m, far, lay }) do
        for _, op in ipairs(model.ops) do
            if op.kind == "tex" then
                local fh = io.open(MOD .. "../ui/DazedDank/" .. op.name .. ".png", "rb")
                if fh then fh:close() else missing[#missing + 1] = op.name end
            end
        end
    end
    check("every UI image exists (" .. table.concat(missing, ", ") .. ")", #missing == 0)
    check("reservoir tanks draw glass over water", find(m, "tex", function(op) return op.name == "tank_front" end) ~= nil)
end

do
    -- Racks take whole plants and jars and barrels take buds, through the game's own container check.
    require "CannabisMod/CannabisAccept"
    local A = DazedDankAccept
    local function item(t) return { getFullType = function() return t end } end
    local wet, dried, bud, apple = item(C.WET_PLANT_ITEMS.Indica), item(C.DRIED_PLANT_ITEMS.Hybrid), item(C.Drying.BUD_ITEM), item("Base.Apple")
    check("racks take only whole plants", A.Rack(nil, wet) and A.Rack(nil, dried) and not A.Rack(nil, bud) and not A.Rack(nil, apple))
    check("jars and barrels take only buds", A.Buds(nil, bud) and not A.Buds(nil, wet) and not A.Buds(nil, apple))
    local function obj(sprite, n)
        local cs = {}
        for i = 1, n do cs[i] = { fn = nil, getAcceptItemFunction = function(c) return c.fn end, setAcceptItemFunction = function(c, f) c.fn = f end } end
        return { getSprite = function() return { getName = function() return sprite end } end,
            getContainerCount = function() return n end, getContainerByIndex = function(_, i) return cs[i + 1] end }, cs
    end
    local rackSprite
    for name in pairs(C.Drying.RACK_SPRITES) do rackSprite = name break end
    local rack, rc = obj(rackSprite, 2)
    local barrel, bc = obj(C.Drying.BARREL_SPRITE, 1)
    local shelf, sc = obj("furniture_shelving_01_0", 1)
    local sq = { getObjects = function() local list = { rack, barrel, shelf }
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end } end }
    fire("LoadGridsquare", sq)
    check("loading a square tags every rack container", rc[1].fn == A.RACK and rc[2].fn == A.RACK)
    check("loading a square tags barrels for buds and leaves other furniture alone", bc[1].fn == A.BUDS and sc[1].fn == nil)
    local placed, pc = obj(C.Drying.BARREL_SPRITE, 1)
    fire("OnObjectAdded", placed)
    check("a newly placed barrel is tagged too", pc[1].fn == A.BUDS)
    local script = io.open(MOD .. "../scripts/CannabisItems.txt", "r")
    local text = script and script:read("*a") or ""
    if script then script:close() end
    check("the curing jar item takes buds only", text:find("item CuringJar%s*{[^}]*AcceptItemFunction%s*=%s*DazedDankAccept%.Buds") ~= nil)
end

-- ---- Occupations and traits ---------------------------------------------
;(function()
    local reg = {}
    CharacterTrait = { register = function(id) reg[id] = "trait"; return id end }
    CharacterProfession = { register = function(id) reg[id] = reg[id] or "profession"; return id end }
    dofile(MOD .. "../registries.lua")
    local Tr = CannabisMod.Traits
    local function traitPlayer(x, y, level, list)
        local p = newPlayer(x, y, level)
        local has = {}
        for _, k in ipairs(list) do has[DazedDankTraits[k]] = true end
        p.hasTrait = function(_, t) return has[t] == true end
        p.getUsername = function() return "trait" .. x end
        return p
    end
    SandboxVars = { CannabisMod = { MoldChance = 0 } }
    local plain, tech = traitPlayer(1, 1, 3, {}), traitPlayer(2, 2, 3, { "cultivationtech", "greenthumb" })
    check("traits: has reads the player's traits", Tr.has(tech, "cultivationtech") and not Tr.has(plain, "cultivationtech"))
    check("traits: rooting bonus stacks Tech and Green Thumb", Tr.rootingBonus(tech) == 15 and Tr.rootingBonus(plain) == 0)
    SandboxVars = { CannabisMod = { MoldChance = 0, TraitsAndOccupations = false } }
    check("traits: the sandbox switch turns every effect off", not Tr.has(tech, "cultivationtech") and Tr.rootingBonus(tech) == 0)
    SandboxVars = { CannabisMod = { MoldChance = 0 } }

    -- Reading: the Tech reads 2 levels up short of genetics; the Breeder reads genetics and hermie lines.
    local techRead, breedRead = Tr.reading(tech), { boost = 0, genetics = true, buds = false }
    check("traits: Tech opens a tier 2 levels up", I.tierOpen(5, 3, techRead) and not I.tierOpen(6, 3, techRead))
    check("traits: Tech never opens genetics early", not I.tierOpen(I.GENETICS_LEVEL, 8, techRead) and I.tierOpen(I.GENETICS_LEVEL, 9, techRead))
    check("traits: Breeder reads genetics at any level", I.tierOpen(I.GENETICS_LEVEL, 0, breedRead) and not I.tierOpen(5, 0, breedRead))
    local seed = { type = T.SATIVA, sex = "female", strain = CannabisMod.Strains.copy(CannabisMod.Strains.STARTERS[1]), hermieLineage = true }
    local seedText = I.seedLabel(seed, 3, breedRead)
    check("traits: Breeder sees a seed's traits and hermie line", seedText:find("hermie line") and seedText:find(":"))
    check("traits: others don't see a hermie line", not I.seedLabel(seed, 10):find("hermie line"))
    check("traits: a Breeder reads a seed's strain and sex at Agriculture 0", I.seedLabel(seed, 0, breedRead):find("Knox Kush") ~= nil
        and I.seedLabel(seed, 0) == "Unknown cannabis seed")

    -- Rooting, curing and seeds
    check("traits: rooting bonus adds to the odds", G.rootingOdds(5, { moist = true, bonus = 10 }) == G.rootingOdds(5, { moist = true }) + 10)
    check("traits: a Budtender's cure goes to +15%", G.curedQuality(80, 5000, false, false, 0.15) == 92 and G.curedQuality(80, 5000) == 88)
    local mom, dad = { type = T.INDICA, strain = CannabisMod.Strains.STARTERS[1] }, { type = T.SATIVA, strain = CannabisMod.Strains.STARTERS[5] }
    local range = C.SEEDS_PER_POLLINATED_PLANT
    local fewest, most = 99, 0
    for _ = 1, 40 do
        local n = #G.seedsFromPollination(mom, dad, { extra = 1, noise = 5, luck = 75 })
        fewest, most = math.min(fewest, n), math.max(most, n)
    end
    check("traits: a Breeder gets one extra seed", fewest >= range.min + 1 and most <= range.max + 1)
    local St = CannabisMod.Strains
    local a, b = St.copy(St.STARTERS[1]), St.copy(St.STARTERS[5])
    local plainSum, breedSum, plainSpread, breedSpread = 0, 0, 0, 0
    local mid = ((a.pot or 50) + (b.pot or 50)) / 2
    for _ = 1, 400 do
        local p1, p2 = St.blend(a, b, true), St.blend(a, b, true, { noise = 5, luck = 75 })
        plainSum, breedSum = plainSum + p1.pot, breedSum + p2.pot
        plainSpread, breedSpread = plainSpread + math.abs(p1.ind - (a.ind + b.ind) / 2), breedSpread + math.abs(p2.ind - (a.ind + b.ind) / 2)
    end
    check("traits: Breeder crosses lean toward more potency", breedSum > plainSum)
    check("traits: Breeder crosses vary less", breedSpread < plainSpread)

    -- Trim Hand stops at a wet plant unless told to trim anyway.
    local trimmer2 = traitPlayer(300, 300, 8, { "trimhand" })
    local sc = newItem("Base.Scissors"); sc.tags[ItemTag.SCISSORS] = true; trimmer2.inv:addExisting(sc)
    local wet = trimmer2.inv:addExisting(newItem(C.WET_PLANT_ITEMS.Indica))
    wet:getModData().CannabisHarvest = { type = "Indica", quality = 80, budYield = 2, genetics = 80 }
    fire("OnClientCommand", "CannabisMod", "trimPlant", trimmer2, { id = wet:getID() })
    check("traits: Trim Hand won't trim a wet plant without asking", sent[#sent].data.text:find("too wet")
        and trimmer2.inv:count(C.Drying.BUD_ITEM) == 0)
    fire("OnClientCommand", "CannabisMod", "trimPlant", trimmer2, { id = wet:getID(), force = true })
    check("traits: Trim Plant Anyway trims it", trimmer2.inv:count(C.Drying.BUD_ITEM) == 2)
    local wet2 = plain.inv:addExisting(newItem(C.WET_PLANT_ITEMS.Indica))
    wet2:getModData().CannabisHarvest = { type = "Indica", quality = 80, budYield = 1 }
    local sc2 = newItem("Base.Scissors"); sc2.tags[ItemTag.SCISSORS] = true; plain.inv:addExisting(sc2)
    fire("OnClientCommand", "CannabisMod", "trimPlant", plain, { id = wet2:getID() })
    check("traits: anyone else trims wet plants as before", plain.inv:count(C.Drying.BUD_ITEM) == 1)

    -- Lightweight and Chronic
    local U = CannabisMod.Use
    local u1, u2 = U.new(), U.new()
    local s1 = U.dose(u1, 100, 1, "joint")
    local s2 = U.dose(u2, 100, 1, "joint", { mult = Tr.LIGHTWEIGHT_STRENGTH })
    check("traits: Lightweight highs hit 50% harder", math.abs(s2 - s1 * 1.5) < 1e-6 and math.abs(u2.tol - u1.tol * 1.5) < 1e-6)
    local light = traitPlayer(1500, 1500, 1, { "lightweight" })
    local lj = newItem(C.Smoking.JOINT_ITEM); light.inv:addExisting(lj)
    lj:getModData().DDJoint = { type = "Indica", quality = 50, moldy = false }
    local heavy = traitPlayer(1501, 1501, 1, {})
    local hj = newItem(C.Smoking.JOINT_ITEM); heavy.inv:addExisting(hj)
    hj:getModData().DDJoint = { type = "Indica", quality = 50, moldy = false }
    fire("OnClientCommand", "CannabisMod", "smoke", light, { id = lj:getID(), method = "joint" })
    local ls = sent[#sent].data.strength
    fire("OnClientCommand", "CannabisMod", "smoke", heavy, { id = hj:getID(), method = "joint" })
    check("traits: a Lightweight smoker gets the stronger dose", sent[#sent].cmd == "smoked" and ls > sent[#sent].data.strength * 1.4)
    local chronic = traitPlayer(1502, 1502, 1, { "chronic" })
    fire("OnClientCommand", "CannabisMod", "chronicStart", chronic, {})
    local cu = CannabisMod.Smoking.data().users["trait1502"]
    check("traits: a Chronic starts hooked", cu and cu.dep == Tr.CHRONIC_DEP and cu.tol == Tr.CHRONIC_TOL and sent[#sent].cmd == "useState")
    fire("OnClientCommand", "CannabisMod", "chronicStart", plain, {})
    check("traits: chronicStart does nothing without the trait", CannabisMod.Smoking.data().users["trait1"] == nil)

    -- Green Thumb softens care penalties on plants they planted.
    check("traits: Green Thumb care constant is a reduction", Tr.GREEN_THUMB_CARE < 1)

    -- Scripts: every id is registered, every recipe exists, every UI key is translated.
    local function readAll(path) local f = io.open(path, "r"); local t = f and f:read("*a") or ""; if f then f:close() end; return t end
    local chars = readAll(MOD .. "../scripts/CannabisCharacters.txt")
    local recipes = readAll(MOD .. "../scripts/CannabisRecipes.txt") .. readAll(MOD .. "../scripts/CannabisItems.txt")
    local ui = readAll(MOD .. "shared/Translate/EN/UI.json")
    local missingId, missingRecipe, missingKey, defs = {}, {}, {}, 0
    for id in chars:gmatch("character_%a+_definition%s+([%w:]+)") do
        defs = defs + 1
        if not reg[id] then missingId[#missingId + 1] = id end
    end
    for list in chars:gmatch("GrantedRecipes%s*=%s*([^,\n]+)") do
        for name in list:gmatch("[^;%s]+") do
            if not recipes:find("craftRecipe%s+" .. name .. "%f[%W]") then missingRecipe[#missingRecipe + 1] = name end
        end
    end
    for key in chars:gmatch("UI%w*Name%s*=%s*([%w_]+)") do if not ui:find('"' .. key .. '"', 1, true) then missingKey[#missingKey + 1] = key end end
    for key in chars:gmatch("UIDescription%s*=%s*([%w_]+)") do if not ui:find('"' .. key .. '"', 1, true) then missingKey[#missingKey + 1] = key end end
    check("traits: 3 occupations and 7 traits defined", defs == 10)
    check("traits: every definition id is registered (" .. table.concat(missingId, ",") .. ")", #missingId == 0)
    check("traits: every granted recipe exists (" .. table.concat(missingRecipe, ",") .. ")", #missingRecipe == 0)
    check("traits: every UI key is translated (" .. table.concat(missingKey, ",") .. ")", #missingKey == 0)
    for _, icon in ipairs({ "textures/profession_dd_cultivationtech.png", "textures/profession_dd_budtender.png", "textures/profession_dd_breeder.png",
        "ui/traits/trait_greenthumb.png", "ui/traits/trait_trimhand.png", "ui/traits/trait_chronic.png", "ui/traits/trait_lightweight.png" }) do
        local f = io.open(MOD .. "../" .. icon, "rb")
        check("traits: icon " .. icon .. " exists", f ~= nil)
        if f then f:close() end
    end

    -- Character creation hides our entries when the switch is off and leaves the rest alone.
    local vanillaCalls = 0
    CharacterCreationProfession = {
        isTraitEnabled = function(self, t) vanillaCalls = vanillaCalls + 1; return true end,
        populateProfessionList = function(self, list)
            list.items = { { item = { getType = function() return "base:farmer" end } },
                           { item = { getType = function() return DazedDankProfessions.breeder end } } }
        end,
    }
    dofile(MOD .. "client/CannabisMod/CannabisCreation.lua")
    local Cr, scr = CannabisMod.Creation, CharacterCreationProfession
    local ours, theirs = { getType = function() return DazedDankTraits.chronic end }, { getType = function() return "base:smoker" end }
    check("creation: our traits show with the switch on", scr:isTraitEnabled(ours) and scr:isTraitEnabled(theirs))
    SandboxVars = { CannabisMod = { MoldChance = 0, TraitsAndOccupations = false } }
    local list = {}; scr:populateProfessionList(list)
    check("creation: switch off hides our traits only", not scr:isTraitEnabled(ours) and scr:isTraitEnabled(theirs))
    check("creation: switch off hides our occupations only", #list.items == 1 and list.items[1].item:getType() == "base:farmer")
    SandboxVars = { CannabisMod = { MoldChance = 0 } }
    list = {}; scr:populateProfessionList(list)
    check("creation: switch on keeps our occupations", #list.items == 2)
    DazedDankTraits, DazedDankProfessions, CharacterCreationProfession = nil, nil, nil
    SandboxVars = nil
end)()

-- ---- High Tracker report --------------------------------------------------
;(function()
    require "CannabisMod/CannabisHighReport"
    local Rp = CannabisMod.HighReport
    local function find(rows, label) for _, r in ipairs(rows) do if r[1] == label then return r[2] end end end
    local heading, rows = Rp.build({ tolerance = 12, dependency = 30 }, 100)
    check("tracker: sober with tolerance and dependency", heading == "Sober" and find(rows, "Tolerance") == "12 / 100"
        and find(rows, "Dependency") == "30 / 100" and find(rows, "Stress") == nil)
    local high = { type = "Indica", strength = 1.0, startedAt = 100, endsAt = 102.5,
        strain = CannabisMod.Strains.copy(CannabisMod.Strains.STARTERS[1]) }
    heading, rows = Rp.build({ high = high }, 100.1, { STRESS = 0.4 })
    check("tracker: coming up partway to full strength", heading == "High" and find(rows, "Phase") == "Coming up"
        and find(rows, "Strength"):find("^0%.40 now, 1%.00 peak") ~= nil)
    check("tracker: shows the strain and time left", find(rows, "Smoked") == "Knox Kush (Indica)" and find(rows, "Time left") == "2h 24m")
    check("tracker: stress rate with the current value", find(rows, "Stress"):find("^%-") ~= nil and find(rows, "Stress"):find("now 40%%") ~= nil)
    heading, rows = Rp.build({ high = high }, 101)
    check("tracker: peak", find(rows, "Phase") == "Peak" and find(rows, "Strength"):find("^1%.00 now") ~= nil)
    heading, rows = Rp.build({ high = high }, 102.3)
    check("tracker: coming down", find(rows, "Phase") == "Coming down")
    local racy = { type = "Sativa", strength = 1.3, startedAt = 0, endsAt = 3, strain = CannabisMod.Strains.copy(CannabisMod.Strains.STARTERS[5]) }
    heading, rows = Rp.build({ high = racy }, 1)
    check("tracker: flags an anxious hit", find(rows, "Anxious") ~= nil)
    heading, rows = Rp.build({ withdrawal = 0.5, tolerance = 0, dependency = 80 }, 50)
    check("tracker: withdrawal shows its level and effects", heading == "Withdrawal" and find(rows, "Withdrawal") == "50%"
        and find(rows, "Stress"):find("^%+") ~= nil)
    heading = Rp.build({ high = high, withdrawal = 0.3 }, 200)
    check("tracker: an ended high falls back to withdrawal", heading == "Withdrawal")
    check("tracker: durations", Rp.duration(0.5) == "30m" and Rp.duration(1.25) == "1h 15m")
end)()

-- ---- Sow menu seed groups --------------------------------------------------
;(function()
    local St = CannabisMod.Strains
    local function seed(i, sex, extra)
        local d = { type = St.typeOf(St.STARTERS[i]), strain = St.copy(St.STARTERS[i]), sex = sex }
        for k, v in pairs(extra or {}) do d[k] = v end
        return { d = d }
    end
    local items = { seed(1, "Female"), seed(1, "Female"), seed(1, "Male"), seed(4, "Female"), seed(4, "Female", { hermieLineage = true }) }
    local dataOf = function(it) return it.d end
    local groups = I.seedGroups(items, 5, nil, dataOf)
    local function count(label) for _, g in ipairs(groups) do if g.label == label then return #g.items end end return 0 end
    check("sow: seeds group by strain and sex", #groups == 3 and count("Knox Kush (Indica), Female") == 2
        and count("Knox Kush (Indica), Male") == 1 and count("Riverside Haze (Sativa), Female") == 2)
    groups = I.seedGroups(items, 1, nil, dataOf)
    check("sow: below the inspect level every seed is one unknown group", #groups == 1 and groups[1].label == "Unknown cannabis seed" and #groups[1].items == 5)
    groups = I.seedGroups(items, 0, { boost = 0, genetics = true }, dataOf)
    check("sow: a Breeder tells hermie lines apart at any level", count("Riverside Haze (Sativa), Female, hermie line") == 1
        and count("Riverside Haze (Sativa), Female") == 1)
end)()

-- ---- Shared sprite dispatcher ----------------------------------------------
;(function()
    local W = CannabisMod.World
    local lampName = "dazeddank_plants_01_197"
    check("dispatcher: lamp sprite reads as a lamp", W.info(lampName) and W.info(lampName).lamp == C.Light.SPRITES[lampName])
    check("dispatcher: vanilla sprites are rejected", W.info("furniture_shelving_01_0") == nil and W.info(nil) == nil)
    check("dispatcher: overlay, bag, panel and curtain flags", W.info(C.overlaySprite(2, 1, 3, "sprite")).overlay
        and W.info(C.bagEmptySprite("dwc", true)).bag == "dwc" and W.info("dazeddank_rooms_01_0").panel == "S"
        and W.info("dazeddank_rooms_01_4").curtain and W.info(C.Hydro.FLOOD_SPRITE).flood)
    check("splitSprite memo returns both parts every time", select(2, C.splitSprite("dazeddank_hydro_01_113")) == 113
        and select(2, C.splitSprite("dazeddank_hydro_01_113")) == 113 and C.splitSprite("vegetation_01_1") == nil)
    -- Each object's sprite is read once per load, however many handlers look at the square.
    local reads, seen = 0, {}
    local function obj(name) return { getSprite = function() reads = reads + 1 return { getName = function() return name end } end } end
    local list = { obj(lampName), obj("floors_01_1"), obj(C.Drying.BARREL_SPRITE) }
    local sq = { getObjects = function() return { size = function() return #list end, get = function(_, i) return list[i + 1] end } end }
    W.onSquareLoad("test a", function(_, hits) seen[#seen + 1] = hits.n end)
    W.onSquareLoad("test b", function(_, hits) seen[#seen + 1] = hits.name[1] end)
    reads = 0
    W.dispatchLoad(sq)
    check("dispatcher: one sprite read per object", reads == 3)
    check("dispatcher: handlers see only our objects", seen[1] == 2 and seen[2] == lampName)
    local px, py, pz = C.parseKey("-12_340_1")
    local qx = C.parseKey("-12_340_1")
    check("parseKey: numbers from a key, the same again from its memo", px == -12 and py == 340 and pz == 1 and qx == -12)
    check("parseKey: not a key", C.parseKey("barrel_1_2_3") == nil and C.parseKey(nil) == nil and C.parseKey("1_2") == nil)
    check("tileKey: numbers and odd values keep the old form", C.tileKey(5, -6, 0) == "5_-6_0" and C.tileKey(nil, 1, 2) == "nil_1_2")
    check("item sets: wet, dried and hanging plants", C.isWetPlant(C.WET_PLANT_ITEMS.Sativa) and not C.isWetPlant(C.DRIED_PLANT_ITEMS.Sativa)
        and C.isDriedPlant(C.DRIED_PLANT_ITEMS.Indica) and C.isHangingPlant(C.WET_PLANT_ITEMS.Hybrid) and not C.isHangingPlant("Base.Apple"))
end)()

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
