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
    if name:sub(1, 8) == "Farming/" then return end
    for _, dir in ipairs({ "shared/", "server/", "client/" }) do
        local f = io.open(MOD .. dir .. name .. ".lua")
        if f then f:close(); dofile(MOD .. dir .. name .. ".lua"); return end
    end
    error("module not found: " .. name)
end
function isClient() return false end
function isServer() return true end   -- route replies through sendServerCommand so tests can see them
function isDebugEnabled() return true end
local handlers = {}
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function(fn) handlers[k] = handlers[k] or {}; table.insert(handlers[k], fn) end }
    rawset(t, k, e); return e end })
local store = {}
ModData = { getOrCreate = function(k) store[k] = store[k] or {}; return store[k] end }
local worldHours = 0
function getGameTime() return { getWorldAgeHours = function() return worldHours end } end
Perks = { Farming = "Farming" }
local sent = {}
function sendServerCommand(player, module, cmd, data) sent[#sent + 1] = { module = module, cmd = cmd, data = data } end
local function fire(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end

-- ---- Vanilla farming stubs (shaped like the real B42 files) ------------
farming_vegetableconf = { props = {} }
for _, set in ipairs({ "sprite", "unhealthySprite", "dyingSprite", "deadSprite", "trampledSprite" }) do
    farming_vegetableconf[set] = { Hemp = { "h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8" } }
end
farming_vegetableconf.getObjectName = function(p) return "Cannabis plot" end
farming_vegetableconf.getSpriteName = function(p)
    return farming_vegetableconf.sprite[p.typeOfSeed][p.nbOfGrow]
end
local plots = {}
local Plot = {}; Plot.__index = Plot
function Plot:isAlive() return self.state ~= "dead" and self.state ~= "destroyed" and self.state ~= "harvested" end
function Plot:setObjectName(n) self.objectName = n end
function Plot:setSpriteName(n) self.spriteName = n end
function Plot:saveData() end
function Plot:harvestThis() self.state = "harvested" end
function Plot:getSquare() return nil end
local function newPlot(x, y, z)
    local p = setmetatable({ x = x, y = y, z = z, state = "plow", nbOfGrow = -1, typeOfSeed = "none", waterLvl = 60 }, Plot)
    plots[#plots + 1] = p; return p
end
SFarmingSystem = { instance = { hoursElapsed = 500 } }
function SFarmingSystem.instance:getLuaObjectAt(x, y, z)
    for _, p in ipairs(plots) do if p.x == x and p.y == y and p.z == z then return p end end
end
function SFarmingSystem.instance:getLuaObjectCount() return #plots end
function SFarmingSystem.instance:getLuaObjectByIndex(i) return plots[i] end
local vanillaHarvested = nil
function SFarmingSystem:harvest(lo, player) vanillaHarvested = lo end
ISSeedActionNew = {}
function ISSeedActionNew:complete()   -- vanilla: removes the seed, seeds the plot
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
        UseAndSync = function(self) self.uses = self.uses - 1 end }
end
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
    function inv:count(fullType)
        local n = 0
        for _, it in ipairs(self.items) do if it.fullType == fullType then n = n + 1 end end
        return n
    end
    return inv
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
require "CannabisMod/CannabisInfo"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisServerCommands"
require "CannabisMod/CannabisCloning"
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
check("pollination seeds hybrid + hermie line", seeds[1].type == T.HYBRID and seeds[1].hermieLineage)

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
check("lvl3 type, sex hidden before preflower", l3.type == T.SATIVA and l3.sex == "Not yet visible" and l3.hoursLeft == 20)
check("lvl3 no stress", l3.stressBand == nil)
plant.stage = 3
check("sex shows at preflower", I.buildVisible(plant, 3, 10).sex == C.SEX.MALE)
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

-- Stress-driven hermie over a long flower
local hits = 0
for trial = 1, 200 do
    local sp = { stage = 4, sex = C.SEX.FEMALE, stress = 100, genetics = 100, type = T.INDICA,
        x = 500 + trial * 20, y = 500, z = 0, nextStageAt = 1e9, warnings = {} }
    store[C.MODDATA_KEY]["t" .. trial] = sp
end
for tick = 1, 6 * 36 do fire("EveryTenMinutes") end   -- 36 hours of flower
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
check("ID seeds spread over 3 types", tcount.Indica > 9000 and tcount.Sativa > 9000 and tcount.Hybrid > 9000)
check("ID seeds ~10% male (" .. mcount .. ")", mcount > 2400 and mcount < 3600)
local written = newItem(C.SEED_ITEM)
S.setData(written, { type = T.SATIVA, sex = C.SEX.MALE, genetics = 80, generation = 0 })
check("written seed data wins over ID", S.getData(written).type == T.SATIVA and S.getData(written).genetics == 80)

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
check("seedling sprite is our shared seedling", plotA.spriteName == "dazeddank_plants_01_0")

-- Other crops are left alone.
local plotT = newPlot(401, 400, 0)
ISSeedActionNew.complete({ typeOfSeed = "Tomato", seed = newItem("Base.TomatoSeed"), plant = { x = 401, y = 400, z = 0 } })
check("tomato gets no cannabis record", R.getPlant(401, 400, 0) == nil)

-- Growth: our stage drives the sprite, ripe enables harvest.
R.advanceStage(recA)
check("sativa veg sprite (slot 5)", plotA.nbOfGrow == 3 and plotA.spriteName == "dazeddank_plants_01_5" and not plotA.hasVegetable)
R.advanceStage(recA); R.advanceStage(recA); R.advanceStage(recA)
check("ripe sprite + harvest option", plotA.nbOfGrow == 7 and plotA.hasVegetable == true
    and plotA.spriteName == "dazeddank_plants_01_8")

-- Sync: water copies over; a vanilla plot without a record gets one.
plotA.waterLvl = 42
local plotB = newPlot(402, 400, 0); plotB.state, plotB.typeOfSeed, plotB.nbOfGrow = "seeded", "Cannabis", 1
F.syncWithVanilla()
check("water copied from plot", recA.water == 42)
check("orphan plot gets a record", R.getPlant(402, 400, 0) ~= nil)
plotB.state = "dead"
F.syncWithVanilla()
check("dead plot keeps record, marked dead", R.getPlant(402, 400, 0) and R.getPlant(402, 400, 0).dead)
local deadType = R.getPlant(402, 400, 0).type
check("dead sprite keeps type", farming_vegetableconf.getSpriteName(plotB)
    == C.spriteName(deadType, R.getPlant(402, 400, 0).stage, "deadSprite"))
plotB.state, plotB.typeOfSeed = "plow", "none"            -- replowed for a new crop
F.syncWithVanilla()
check("replowed plot's record removed", R.getPlant(402, 400, 0) == nil)

-- Harvest: female ripe -> wet plant with quality, no vanilla produce.
local farmer = newPlayer(400, 400, 5)
worldHours = recA.nextStageAt - 1   -- inside the ripe window
recA.lightCap = 100
SFarmingSystem.harvest(SFarmingSystem.instance, plotA, farmer)
local wet = farmer.inv.items[1]
local hd = wet and wet:getModData().CannabisHarvest
check("harvest gives wet plant", wet and wet.fullType == "CannabisMod.WetCannabisPlant")
check("wet plant carries quality (" .. tostring(hd and hd.quality) .. ")", hd and hd.quality == 90 and hd.type == T.SATIVA)
check("bud yield 4-8 scaled by genetics", hd and hd.budYield >= 4 and hd.budYield <= 7)
check("plot harvested, record kept as dead", plotA.state == "harvested" and R.getPlant(400, 400, 0).dead)
check("harvested plot shows trampled sativa", farming_vegetableconf.getSpriteName(plotA) == "dazeddank_plants_01_60")
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
        check("Indica x Sativa seed is Hybrid", S.getData(it).type == T.HYBRID)
    end
end
check("pollinated harvest drops 3-8 seeds (" .. seedsOut .. ")", seedsOut >= 3 and seedsOut <= 8)
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
check("sprite: healthy ripe hybrid = 12", C.spriteName("Hybrid", 5, "sprite") == "dazeddank_plants_01_12")
check("sprite: indica veg = 1", C.spriteName("Indica", 2, "sprite") == "dazeddank_plants_01_1")
check("sprite: seedling shared", C.spriteName("Indica", 1, "sprite") == C.spriteName("Sativa", 1, "sprite"))
check("sprite: dead seedling = 39", C.spriteName("Sativa", 1, "deadSprite") == "dazeddank_plants_01_39")
check("sprite: last one = 64", C.spriteName("Hybrid", 5, "trampledSprite") == "dazeddank_plants_01_64")
local seen = {}
for _, cond in ipairs({ "sprite", "unhealthySprite", "dyingSprite", "deadSprite", "trampledSprite" }) do
    for _, ty in ipairs({ "Indica", "Sativa", "Hybrid" }) do
        for st = 1, 5 do seen[C.spriteName(ty, st, cond)] = true end
    end
end
local nSeen = 0; for _ in pairs(seen) do nSeen = nSeen + 1 end
check("all 65 sprites reachable, no extras (" .. nSeen .. ")", nSeen == 65)
local sick = newPlot(500, 500, 0); sick.state, sick.typeOfSeed, sick.nbOfGrow = "seeded", "Cannabis", 6
sick.health, sick.mildewLvl = 40, 0
-- no registry record -> Hybrid art; nbOfGrow 6 = Flowering = slot 11
check("unhealthy at health 40", tonumber(farming_vegetableconf.getSpriteName(sick):match("_(%d+)$")) == 1 * 13 + 11)
sick.mildewLvl = 35
check("dying at mildew 35", tonumber(farming_vegetableconf.getSpriteName(sick):match("_(%d+)$")) == 2 * 13 + 11)
local tomatoPlot = newPlot(501, 500, 0); tomatoPlot.state, tomatoPlot.typeOfSeed, tomatoPlot.nbOfGrow = "seeded", "Hemp", 3
check("other crops use vanilla sprites", farming_vegetableconf.getSpriteName(tomatoPlot) == "h3")

-- ---- Cloning ---------------------------------------------------------------
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
R.advanceStage(mom)                                    -- now Vegetative
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
R.advanceStage(mom); R.advanceStage(mom)               -- Flowering
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

-- cloning dome
local dome = gardener.inv:addExisting(newItem(C.DOME_ITEM))
for i = 1, 14 do gardener.inv:addExisting(newItem(C.CUTTING_ITEM)) end      -- 15 fresh now
local rotten = gardener.inv:addExisting(newItem(C.CUTTING_ITEM)); rotten.rotten = true
fire("OnClientCommand", "CannabisMod", "domeAdd", gardener, { domeId = dome:getID() })
local list = R.getDome(dome:getID())
check("dome holds 12", #list == 12)
check("3 fresh + 1 rotten left over", gardener.inv:count(C.CUTTING_ITEM) == 4)
check("rotten cutting not added", rotten.container == gardener.inv)
local gelEntry = 0
for _, e in ipairs(list) do if e.data.gel then gelEntry = gelEntry + 1 end end
check("dipped cutting went in first, keeps gel", gelEntry == 1)
fire("OnClientCommand", "CannabisMod", "domeAdd", gardener, { domeId = dome:getID() })
check("full dome refuses more", #R.getDome(dome:getID()) == 12 and sent[#sent].data.text:find("full"))

fire("OnClientCommand", "CannabisMod", "domeTake", gardener, { domeId = dome:getID() })
check("nothing ready yet", gardener.inv:count(C.ROOTED_ITEM) == 0 and #R.getDome(dome:getID()) == 12)
local p0, r0, f0 = CL.domeStatus(list, worldHours)
check("all 12 pending", p0 == 12 and r0 == 0 and f0 == 0)
for i, e in ipairs(list) do e.success = i <= 9 end     -- 9 root, 3 fail
worldHours = worldHours + 48
fire("OnClientCommand", "CannabisMod", "domeCheck", gardener, { domeId = dome:getID() })
check("check reports rooted/failed", sent[#sent].data.text:find("9 rooted") and sent[#sent].data.text:find("3 didn't root"))
fire("OnClientCommand", "CannabisMod", "domeTake", gardener, { domeId = dome:getID() })
check("took 9 rooted, dome emptied", gardener.inv:count(C.ROOTED_ITEM) == 9 and #R.getDome(dome:getID()) == 0)
local rootedItem = S.findItem(gardener.inv, function(i) return S.kind(i) == "rooted" end)
check("rooted cutting keeps lineage", S.getCuttingData(rootedItem).type ~= nil)

-- planting a rooted cutting: starts in veg, no rooting wait
local rcPlot = newPlot(610, 600, 0)
local rcItem = newItem(C.ROOTED_ITEM)
S.setCuttingData(rcItem, { type = T.SATIVA, sex = C.SEX.FEMALE, genetics = 80, generation = 4, stress = 6 })
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = rcItem, plant = { x = 610, y = 600, z = 0 }, character = gardener })
local rc = R.getPlant(610, 600, 0)
check("rooted cutting planted in veg", rc.stage == C.STAGE.Vegetative and rc.generation == 4
    and rc.stress == 6 and not rc.rooting and rcPlot.spriteName == C.spriteName(T.SATIVA, 2, "sprite"))

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
check("debug kit: dome, gel, 3 cuttings", dbg.inv:count(C.DOME_ITEM) == 1 and dbg.inv:count(C.GEL_ITEM) == 1
    and dbg.inv:count(C.CUTTING_ITEM) == 3)

-- ---- Debug commands ------------------------------------------------------
local tester = newPlayer(430, 430, 3)
fire("OnClientCommand", "CannabisMod", "debugGiveSeeds", tester, {})
local males = 0
for _, it in ipairs(tester.inv.items) do if S.getData(it).sex == C.SEX.MALE then males = males + 1 end end
check("debug seeds: 6 given, 3 male", #tester.inv.items == 6 and males == 3)
local plotD = newPlot(430, 430, 0)
ISSeedActionNew.complete({ typeOfSeed = "Cannabis", seed = tester.inv.items[1], plant = { x = 430, y = 430, z = 0 } })
fire("OnClientCommand", "CannabisMod", "debugNextStage", tester, { x = 430, y = 430, z = 0 })
check("debug next stage", R.getPlant(430, 430, 0).stage == 2 and plotD.nbOfGrow == 3)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
