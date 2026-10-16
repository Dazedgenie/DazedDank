-- Headless test of the Dank tab in Dazed Control (server/CannabisMod/CannabisControl.lua).
-- Run from the repo root:  lua5.1 tools/tests/control_tab_test.lua
-- Needs a Dazed Core checkout (1.8.1+): DAZEDCORE=/path/to/DazedCore, default /home/claude/DazedCore.
-- Optional: DANK_VIEW_OUT=<file> writes the tab's view for a sample world there (default /home/claude/work/views/dank.lua
-- when that folder exists).

local CORE = os.getenv("DAZEDCORE") or "/home/claude/DazedCore"
local LUA = "Contents/mods/DazedDank/42/media/lua"
local CORE_LUA = CORE .. "/Contents/mods/DazedCore/common/media/lua/shared"
package.path = LUA .. "/shared/?.lua;" .. LUA .. "/server/?.lua;" .. CORE_LUA .. "/?.lua;" .. package.path

---------------------------------------------------------------- a small engine stub

local fails, passes = 0, 0
local function check(cond, what)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. what) end
end

Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(fn) e.list[#e.list + 1] = fn end
    e.Remove = function() end
    rawset(t, k, e)
    return e
end })
function isClient() return false end
function isServer() return false end
function getDebug() return false end
function isDebugEnabled() return false end
function getTimestampMs() return os.time() * 1000 end

local store = {}
ModData = {
    exists = function(k) return store[k] ~= nil end,
    get = function(k) return store[k] end,
    getOrCreate = function(k) store[k] = store[k] or {}; return store[k] end,
}

local WORLD_HOURS = 18 * 24 + 10.7
function getGameTime()
    return {
        getWorldAgeHours = function() return WORLD_HOURS end,
        getNightsSurvived = function() return 18 end,
        getHour = function() return 10 end,
        getMinutes = function() return 42 end,
    }
end

local loadedTiles = {}
function getCell()
    return { getGridSquare = function(_, x, y, z)
        return loadedTiles[x .. "_" .. y .. "_" .. z] and {} or nil
    end }
end

local function newPlayer(name, access)
    return {
        getUsername = function() return name end,
        getAccessLevel = function() return access end,
        getX = function() return 100 end, getY = function() return 100 end, getZ = function() return 0 end,
        getOnlineID = function() return 1 end,
    }
end
local admin, moderator, plain = newPlayer("Kyle", "admin"), newPlayer("Ash", "moderator"), newPlayer("Pete", "none")
function getOnlinePlayers() return nil end
function getSpecificPlayer(i) if i == 0 then return admin end return nil end

---------------------------------------------------------------- load Core and the mod's config

require "DazedCore/DC_Util"
require "DazedCore/DC_Net"
require "DazedCore/DC_Control"
require "CannabisMod/CannabisConfig"
local C, Net, Config = DazedCore.Control, DazedCore.Net, CannabisMod.Config
check(C and C.register and Net and Net.on, "Dazed Core loaded")

---------------------------------------------------------------- fake mod state

local NOW = WORLD_HOURS
local function plant(x, y, z, o)
    local p = { x = x, y = y, z = z, strain = { name = o.name }, stage = o.stage, nextStageAt = NOW + (o.left or 30),
        plantedAt = NOW - (o.age or 20) * 24, care = o.care or 100, stress = o.stress or 0, water = 50,
        warnings = o.warnings or {}, dead = o.dead, bag = o.bag, sex = o.sex or "Female" }
    store[Config.MODDATA_KEY][Config.tileKey(x, y, z)] = p
    loadedTiles[Config.tileKey(x, y, z)] = not o.unloaded or nil
    return p
end

local function buildWorld()
    store = {}
    loadedTiles = {}
    ModData.getOrCreate(Config.MODDATA_KEY)
    local rooms = ModData.getOrCreate(Config.MODDATA_KEY .. "_Rooms")
    rooms["10600_9300_-1"] = { x = 10600, y = 9300, z = -1, name = "Riverside farm cellar", temp = 24.3, hum = 55,
        mode = "Veg", schedule = "18/6", powered = true }
    rooms["11020_6810_0"] = { x = 11020, y = 6810, z = 0, name = "School gym", temp = 33.1, hum = 48,
        mode = "Flower", schedule = "12/12", powered = true }
    rooms["8100_11500_0"] = { x = 8100, y = 11500, z = 0, name = "Pete's shed", mode = "Veg", schedule = "18/6",
        powered = false }
    local inRoom = {}
    local function room(p, pk) inRoom[Config.tileKey(p.x, p.y, p.z)] = pk end
    room(plant(10603, 9302, -1, { name = "Purple Haze", stage = 4, left = 54, age = 40, bag = "ebb" }), "10600_9300_-1")
    room(plant(10604, 9302, -1, { name = "Knox Kush", stage = 2, left = 20, age = 9, bag = "ebb" }), "10600_9300_-1")
    room(plant(10605, 9303, -1, { name = "Knox Kush", stage = 5, left = 11, age = 52, bag = "ebb" }), "10600_9300_-1")
    room(plant(11022, 6812, 0, { name = "Northern Lights", stage = 4, care = 41, stress = 35, bag = "rdwc",
        warnings = { rootRot = true } }), "11020_6810_0")
    room(plant(11023, 6812, 0, { name = "Muldraugh Purple", stage = 4, sex = "Male", bag = "rdwc" }), "11020_6810_0")
    room(plant(11024, 6813, 0, { name = "Rosewood Stone", stage = 3, care = 72, stress = 12, bag = "rdwc",
        warnings = { reservoirDry = true } }), "11020_6810_0")
    plant(8104, 11507, 0, { name = "Hybrid", stage = 2, care = 80, warnings = { underwatered = true } })
    plant(8105, 11507, 0, { name = "Riverside Dream", stage = 3, dead = true })
    plant(8106, 11508, 0, { name = "Knox Kush", stage = 1, left = 3, unloaded = true })
    local hydro = ModData.getOrCreate(Config.MODDATA_KEY .. "_Hydro")
    hydro["10601_9301_-1"] = { kind = "ebb", x = 10601, y = 9301, z = -1, level = 34, strength = 0.8, nutrient = "Veg",
        tainted = false, rot = 0, isFlood = true, everFilled = true }
    hydro["11021_6811_0"] = { kind = "rdwc", x = 11021, y = 6811, z = 0, level = 3, strength = 0.3, nutrient = "Bloom",
        tainted = true, rot = 34, isControl = true, everFilled = true }
    hydro["11022_6812_0"] = { kind = "rdwc", x = 11022, y = 6812, z = 0, link = "11021_6811_0" }  -- a site, not a reservoir
    hydro["11023_6812_0"] = { kind = "rdwc", x = 11023, y = 6812, z = 0, link = "11021_6811_0" }
    hydro["11024_6813_0"] = { kind = "rdwc", x = 11024, y = 6813, z = 0, link = "11021_6811_0" }
    local names = ModData.getOrCreate(Config.MODDATA_KEY .. "_StrainNames")
    for _, n in ipairs({ "Knox Kush", "Muldraugh Purple", "Rosewood Stone", "Louisville Haze", "West Point Diesel",
        "March Ridge Skunk", "Hybrid", "Purple Haze", "Northern Lights", "Riverside Dream", "Gym Rat" }) do names[n] = true end
    loadedTiles["10601_9301_-1"], loadedTiles["11021_6811_0"] = true, true
    loadedTiles["10600_9300_-1"], loadedTiles["11020_6810_0"], loadedTiles["8100_11500_0"] = true, true, true

    local vanilla = {}
    local CAP = { ebb = 60, rdwc = 40, dwc = 15, drip = 50 }
    CannabisMod.Strains = { STARTERS = { {}, {}, {}, {}, {}, {} } }
    CannabisMod.Registry = {
        nowHours = function() return NOW end,
        advanceStage = function(p) p.stage = p.stage + 1; p.nextStageAt = NOW + 30 end,
    }
    CannabisMod.Hydro = {
        DEBUG_POT_WATER = 80,
        capacity = function(r) return CAP[r.kind] end,
        reservoirOf = function(x, y, z)
            local site = hydro[Config.tileKey(x, y, z)]
            if site and site.link then return hydro[site.link] end
            if x >= 10600 and x < 10610 then return hydro["10601_9301_-1"] end
            return site
        end,
    }
    CannabisMod.Farming = {
        getVanilla = function(x, y, z)
            local k = Config.tileKey(x, y, z)
            vanilla[k] = vanilla[k] or { waterLvl = 20, saveData = function() end }
            return vanilla[k]
        end,
        killPlant = function(p) p.dead = true end,
    }
    CannabisMod.Rooms = { keyAt = function(x, y, z) return inRoom[Config.tileKey(x, y, z)] end }
    return vanilla
end

---------------------------------------------------------------- load the tab

local vanilla = buildWorld()
require "CannabisMod/CannabisControl"
local tab = C.tabs.dank
check(tab ~= nil, "dank tab registered")
local M = "DazedDankControl"
for _, cmd in ipairs({ "advance", "water", "cure", "kill", "refill" }) do
    check(tab.commands[M .. "." .. cmd] == "admin", cmd .. " needs admin")
    check(Net.server[M] and Net.server[M][cmd], cmd .. " handler registered")
end
check(C.level(admin) == "admin" and C.level(moderator) == "mod" and C.level(plain) == nil, "levels from access")

-- The real view, after Core marks its buttons, caught from the reply sendView makes.
local shown
Net.onClient("DazedCore", "ctlView", function(args) shown = args end)
C.sendView(admin, "dank")
check(shown and shown.tab == "dank", "sendView answered for the dank tab")
local view = shown and shown.view or {}

---------------------------------------------------------------- picture data

local function ser(v, ind)
    ind = ind or ""
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local inner = ind .. "  "
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = inner .. ser(v[i], inner) end
    local keys = {}
    for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. ser(k) .. "]")
        parts[#parts + 1] = inner .. ks .. " = " .. ser(v[k], inner)
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
end

local out = os.getenv("DANK_VIEW_OUT")
if not out then
    local probe = io.open("/home/claude/work/views/.probe", "w")
    if probe then probe:close(); os.remove("/home/claude/work/views/.probe"); out = "/home/claude/work/views/dank.lua" end
end
if out then
    local f = io.open(out, "w")
    if f then
        f:write("return " .. ser({ tab = "dank", target = nil, view = { clock = view.clock, lamps = view.lamps, cards = view.cards } }) .. "\n")
        f:close()
        print("wrote " .. out)
    end
end

---------------------------------------------------------------- the view

check(view.clock == "D19 10:42", "clock stamped")
local lampText = {}
for _, l in ipairs(view.lamps or {}) do lampText[l[1]] = l[2] end
check(lampText["Plants: 9"] == "green", "plants lamp")
check(lampText["Sick: 3"] == "amber", "sick lamp")
check(lampText["Dead: 1"] == "red", "dead lamp")
local cards = view.cards or {}
check(#cards == 4, "four cards")
local plantsCard, resCard, roomsCard, strainsCard = cards[1], cards[2], cards[3], cards[4]
check(plantsCard.items[1].tone == "red" and plantsCard.items[1].text:find("dead", 1, true) == nil
    and plantsCard.items[1].sub:find("dead", 1, true), "dead plant first")
check(plantsCard.items[1].buttons == nil or #plantsCard.items[1].buttons == 0, "a dead plant has no buttons")
local byName = {}
for _, it in ipairs(plantsCard.items) do byName[it.text] = it end
local nl = byName["Northern Lights, flowering"]
check(nl and nl.tone == "red" and nl.sub:find("root rot", 1, true), "root rot plant red")
local labels = {}
for _, b in ipairs(nl and nl.buttons or {}) do labels[b.label] = b; check(b.need == "admin" and b.module == M, "button marked by Core") end
check(labels.Cure and labels.Kill and not labels.Advance and not labels.Refill, "sick plant: cure and kill")
local rs = byName["Rosewood Stone, preflower"]
check(rs and rs.buttons[1].label == "Refill", "dry hydro plant: refill first")
local hy = byName["Hybrid, vegetative"]
check(hy and hy.buttons[1].label == "Water", "dry soil plant: water")
local ph = byName["Purple Haze, flowering"]
check(ph and #ph.buttons == 1 and ph.buttons[1].label == "Advance", "healthy plant: advance only")
local unl = byName["Knox Kush, seedling"]
check(unl and unl.sub:find("unloaded", 1, true), "unloaded plant said so")
local unlB = {}
for _, b in ipairs(unl and unl.buttons or {}) do unlB[b.label] = true end
check(not unlB.Kill and not unlB.Water and unlB.Advance, "unloaded plant: no kill or water")
check(byName["Muldraugh Purple, flowering (male)"] and byName["Muldraugh Purple, flowering (male)"].sub:find("pollinating", 1, true),
    "male in flower flagged")
check(#resCard.items == 2, "two reservoirs (the site is left out)")
check(resCard.items[1].text:find("RDWC", 1, true) and resCard.items[1].tone == "red", "lowest reservoir first, red")
check(resCard.items[1].sub:find("3 of 40 L", 1, true), "reservoir litres")
check(#roomsCard.items == 3, "three rooms")
local roomByName = {}
for _, it in ipairs(roomsCard.items) do roomByName[it.text:match("^(.-) at ")] = it end
check(roomByName["School gym"].tone == "red" and roomByName["School gym"].sub:find("too hot", 1, true), "hot room red")
check(roomByName["Riverside farm cellar"].sub:find("^3 plants"), "room plant count")
check(roomByName["Pete's shed"].sub:find("no power", 1, true), "unpowered room")
check(strainsCard.rows[1][2] == "11" and strainsCard.rows[2][2] == "4", "strain counts")
local marks = shown and shown.marks or {}
check(#marks >= 6, "marks for plants, reservoirs and rooms")

---------------------------------------------------------------- the handlers

local function copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, x in pairs(a) do if not same(x, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function run(player, cmd, args) Net.server[M][cmd].fn(player, args) end

local P, H = store[Config.MODDATA_KEY], store[Config.MODDATA_KEY .. "_Hydro"]
local calls = {
    { "advance", { key = "10604_9302_-1" } }, { "water", { key = "8104_11507_0" } }, { "water", { key = "11024_6813_0" } },
    { "cure", { key = "11022_6812_0" } }, { "kill", { key = "11023_6812_0" } }, { "refill", { key = "10601_9301_-1" } },
}
-- Moderators and players change nothing.
local before, beforeV = copy(store), copy(vanilla)
for _, who in ipairs({ moderator, plain }) do
    for _, c in ipairs(calls) do run(who, c[1], c[2]) end
end
check(same(before, store) and same(beforeV, vanilla), "moderator and plain player changed nothing")

-- Bad arguments change nothing either.
for _, bad in ipairs({ {}, { key = 5 }, { key = "x_y_z" }, { key = "1_2_3" }, { key = string.rep("9", 60) }, { key = "1.5_2_0" } }) do
    for _, cmd in ipairs({ "advance", "water", "cure", "kill", "refill" }) do run(admin, cmd, bad) end
end
run(admin, "refill", { key = "11022_6812_0" })  -- an RDWC site is not a reservoir
check(same(before, store), "bad arguments changed nothing")

-- Admin.
run(admin, "advance", { key = "10604_9302_-1" })
check(P["10604_9302_-1"].stage == 3, "advance moved the plant on")
run(admin, "advance", { key = "10605_9303_-1" })
check(P["10605_9303_-1"].stage == 5, "a ripe plant stays ripe")
run(admin, "advance", { key = "8105_11507_0" })
check(P["8105_11507_0"].stage == 3, "a dead plant does not advance")
run(admin, "water", { key = "8104_11507_0" })
check(vanilla["8104_11507_0"].waterLvl == 80 and P["8104_11507_0"].water == 80, "water filled the soil plot")
run(admin, "water", { key = "8106_11508_0" })
check(vanilla["8106_11508_0"] == nil and P["8106_11508_0"].water == 50, "water waits for an unloaded plot")
run(admin, "water", { key = "11024_6813_0" })
check(H["11021_6811_0"].level == 40, "water on a hydro plant refilled its reservoir")
run(admin, "cure", { key = "11022_6812_0" })
local nlp = P["11022_6812_0"]
check(nlp.care == 100 and nlp.stress == 0 and not nlp.warnings.rootRot, "cure reset the plant")
check(H["11021_6811_0"].rot == 0 and H["11021_6811_0"].tainted == false, "cure cleaned its reservoir")
run(admin, "kill", { key = "11023_6812_0" })
check(P["11023_6812_0"].dead == true, "kill killed the male")
run(admin, "kill", { key = "8106_11508_0" })
check(not P["8106_11508_0"].dead, "kill waits for an unloaded plot")
H["10601_9301_-1"].level = 0
run(admin, "refill", { key = "10601_9301_-1" })
check(H["10601_9301_-1"].level == 60 and H["10601_9301_-1"].changedAt == NOW, "refill filled with fresh water")

-- Through the panel's own action path: a moderator is refused, an admin runs it.
local result
Net.onClient("DazedCore", "ctlResult", function(args) result = args end)
H["10601_9301_-1"].level = 5
Net.server.DazedCore.ctlAct.fn(moderator, { tab = "dank", module = M, command = "refill", args = { key = "10601_9301_-1" } })
check(result and result.ok == false and H["10601_9301_-1"].level == 5, "ctlAct refuses a moderator")
Net.server.DazedCore.ctlAct.fn(admin, { tab = "dank", module = M, command = "refill", args = { key = "10601_9301_-1" } })
check(result and result.ok == true and H["10601_9301_-1"].level == 60, "ctlAct runs for an admin")

print(string.format("control_tab_test: %d passed, %d failed", passes, fails))
if fails > 0 then os.exit(1) end
