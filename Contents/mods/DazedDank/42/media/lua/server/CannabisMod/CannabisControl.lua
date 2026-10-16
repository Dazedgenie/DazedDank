--[[ Dazed Dank -- its tab in Dazed Control (Dazed Core 1.8.1 and later), the staff panel.

     Shows the plants that need a look first (dead, sick, a dry reservoir, a male in flower, ripe), the hydro
     reservoirs lowest first, the grow rooms and the strain counts, and marks plants, reservoirs and rooms on the
     panel's map. Admin buttons advance, water, cure or kill a plant and refill a reservoir. The handlers find the
     plant or reservoir by tile key in the server's own records and skip the 3-tile reach the player commands use.

     Plants and reservoirs live in global ModData, so they are listed and changed even when their cell is not
     loaded; watering and killing touch the vanilla plot, so those wait until its square is loaded.
     With an older Dazed Core there is no Dazed Control and this file does nothing. ]]

if isClient() then return end

require "CannabisMod/CannabisConfig"
pcall(require, "DazedCore/DC_Control")

local C = DazedCore and DazedCore.Control
local Net = DazedCore and DazedCore.Net
if not (C and C.register and C.level and C.atLeast and Net and Net.on) then return end

local Config = CannabisMod.Config
local M = "DazedDankControl"
local LIST_MAX = 14
local MARKS_MAX = 40
local SICK_CARE = 60      -- care under this counts as sick
local SICK_STRESS = 60    -- stress at or over this counts as sick (hermie risk starts here)

-- Words for each warning flag a plant record can carry.
local WARN = {
    overwatered = "overwatered", underwatered = "underwatered", hungry = "hungry", nutrientBurn = "nutrient burn",
    wrongNutrient = "wrong nutrient", rootRot = "root rot", overcut = "over-cut", reservoirDry = "reservoir dry",
    overStripped = "over-stripped", mediumDry = "rockwool dry", noControl = "no RDWC control", noFlood = "no flood reservoir",
    staleReservoir = "stale reservoir", pumpOff = "air pump off", noLight = "no light", lightLeak = "light leak",
    lightInterrupted = "light interrupted", roomTemp = "room temperature", roomHumid = "room humidity",
    outdoorTemp = "outdoor temperature",
}
local WARN_ORDER = { "rootRot", "reservoirDry", "underwatered", "overwatered", "hungry", "nutrientBurn", "wrongNutrient",
    "overcut", "overStripped", "mediumDry", "noControl", "noFlood", "staleReservoir", "pumpOff", "noLight", "lightLeak",
    "lightInterrupted", "roomTemp", "roomHumid", "outdoorTemp" }

local RES_NAME = { dwc = "DWC bucket", rdwc = "RDWC control bucket", ebb = "Flood reservoir", drip = "Drip tank" }

---------------------------------------------------------------- reading the mod's records (no side effects)

local function md(key)
    if not ModData then return nil end
    if ModData.exists and not ModData.exists(key) then return nil end
    if ModData.get then return ModData.get(key) end
    return nil
end

local function plantsTable() return md(Config.MODDATA_KEY) end
local function hydroTable() return md(Config.MODDATA_KEY .. "_Hydro") end
local function roomsTable() return md(Config.MODDATA_KEY .. "_Rooms") end
local function strainNames() return md(Config.MODDATA_KEY .. "_StrainNames") end

local function nowHours()
    local R = CannabisMod.Registry
    if R and R.nowHours then
        local ok, h = pcall(R.nowHours)
        if ok and type(h) == "number" then return h end
    end
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or 0
end

local function loaded(x, y, z)
    local cell = getCell and getCell()
    return cell ~= nil and cell:getGridSquare(x, y, z) ~= nil
end

local function int(n) return math.floor((tonumber(n) or 0) + 0.5) end

-- "2d 6h", "5h", "40m".
local function span(hours)
    hours = math.max(0, tonumber(hours) or 0)
    if hours >= 24 then return string.format("%dd %dh", math.floor(hours / 24), math.floor(hours % 24)) end
    if hours >= 1 then return string.format("%dh", math.floor(hours)) end
    return string.format("%dm", math.floor(hours * 60))
end

local function strainName(plant)
    local s = type(plant.strain) == "table" and plant.strain.name
    if type(s) == "string" and s ~= "" then return s end
    return tostring(plant.type or "Cannabis")
end

local function stageName(plant)
    return Config.STAGES[tonumber(plant.stage) or 0] or "?"
end

local function warningsOf(plant)
    local out = {}
    local w = type(plant.warnings) == "table" and plant.warnings or {}
    for _, k in ipairs(WARN_ORDER) do
        if w[k] then out[#out + 1] = WARN[k] end
    end
    return out
end

local function isSick(plant)
    if plant.dead then return false end
    if #warningsOf(plant) > 0 then return true end
    return (tonumber(plant.care) or 100) < SICK_CARE or (tonumber(plant.stress) or 0) >= SICK_STRESS
end

local function roomKeyOf(x, y, z)
    local R = CannabisMod.Rooms
    if not (R and R.keyAt) then return nil end
    local ok, k = pcall(R.keyAt, x, y, z)
    return ok and k or nil
end

local function roomName(panelKey)
    local rooms = roomsTable()
    local room = panelKey and rooms and rooms[panelKey]
    return room and tostring(room.name or "Grow Room") or nil
end

-- A reservoir record (not an RDWC site or a flood table): a DWC bucket, an RDWC control, a flood reservoir or a drip tank.
local function isReservoir(r)
    if type(r) ~= "table" or not r.x or not r.kind then return false end
    if r.isControl or r.isFlood or r.isDrip then return true end
    return r.kind == "dwc" and not r.link
end

local function capacityOf(r)
    local H = CannabisMod.Hydro
    if H and H.capacity then
        local ok, cap = pcall(H.capacity, r)
        if ok and tonumber(cap) then return cap end
    end
    return nil
end

local function key(x, y, z) return Config.tileKey(x, y, z) end

---------------------------------------------------------------- what needs a look

-- Score and words for one plant: higher scores list first; 0 means it is fine.
local function assess(plant, now)
    if plant.dead then return 5, "red", "dead" end
    local warns = warningsOf(plant)
    local care = tonumber(plant.care) or 100
    local stress = tonumber(plant.stress) or 0
    local w = type(plant.warnings) == "table" and plant.warnings or {}
    if #warns > 0 or care < SICK_CARE or stress >= SICK_STRESS then
        local words = #warns > 0 and table.concat(warns, ", ", 1, math.min(3, #warns)) or "low care"
        local bad = w.rootRot or w.reservoirDry or care < 30
        return bad and 4 or 3, bad and "red" or "amber",
            string.format("sick: %s - care %d, stress %d", words, int(care), int(stress))
    end
    if plant.sex == Config.SEX.MALE and plant.stage == Config.STAGE.Flowering then
        return 2, "amber", "male, pollinating"
    end
    if plant.stage == Config.STAGE.Ripe then
        local left = (tonumber(plant.nextStageAt) or now) - now
        if left < 0 then return 2, "amber", "ripe, overripe by " .. span(-left) end
        return 1, "green", "ripe, harvest within " .. span(left)
    end
    return 0, "green", nil
end

-- Only the buttons that fit what the plant needs, so a row stays short: a sick plant gets Cure and Kill, a healthy
-- one Advance, a dry one Water (or Refill for hydro), a male in flower Kill. Water and Kill need the square loaded.
local function plantButtons(plant, k, isLoaded)
    if plant.dead then return nil end
    local b = {}
    local w = type(plant.warnings) == "table" and plant.warnings or {}
    local hydro = Config.isHydro(plant.bag)
    local sick = isSick(plant)
    local male = plant.sex == Config.SEX.MALE and plant.stage == Config.STAGE.Flowering
    if not sick and not male and (tonumber(plant.stage) or 99) < Config.STAGE.Ripe and not plant.rooting then
        b[#b + 1] = { label = "Advance", module = M, command = "advance", args = { key = k } }
    end
    if hydro and (w.reservoirDry or w.mediumDry) then
        b[#b + 1] = { label = "Refill", module = M, command = "water", args = { key = k } }
    elseif not hydro and isLoaded and (w.underwatered or (tonumber(plant.water) or 100) < 30) then
        b[#b + 1] = { label = "Water", module = M, command = "water", args = { key = k } }
    end
    if sick then b[#b + 1] = { label = "Cure", module = M, command = "cure", args = { key = k } } end
    if isLoaded and (sick or male or plant.isHermie) then
        b[#b + 1] = { label = "Kill", module = M, command = "kill", args = { key = k }, danger = true }
    end
    return b
end

-- One pass over the plants: counts, the per-room tallies and the list, sorted most urgent first.
local function survey(now)
    local s = { total = 0, sick = 0, dead = 0, ripe = 0, list = {}, byRoom = {} }
    for k, plant in pairs(plantsTable() or {}) do
        if type(plant) == "table" and plant.x and plant.y then
            local z = plant.z or 0
            s.total = s.total + 1
            if plant.dead then s.dead = s.dead + 1 elseif isSick(plant) then s.sick = s.sick + 1 end
            if not plant.dead and plant.stage == Config.STAGE.Ripe then s.ripe = s.ripe + 1 end
            local pk = roomKeyOf(plant.x, plant.y, z)
            if pk then s.byRoom[pk] = (s.byRoom[pk] or 0) + 1 end
            local score, tone, why = assess(plant, now)
            s.list[#s.list + 1] = { k = k, plant = plant, score = score, tone = tone, why = why, room = pk }
        end
    end
    table.sort(s.list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.k < b.k
    end)
    return s
end

local function plantItem(e, now)
    local p = e.plant
    local z = p.z or 0
    local isLoaded = loaded(p.x, p.y, z)
    local parts = {}
    parts[#parts + 1] = (roomName(e.room) or "outdoors") .. " " .. p.x .. ", " .. p.y
    if e.why then parts[#parts + 1] = e.why end
    if not p.dead then
        if p.plantedAt then parts[#parts + 1] = "day " .. (math.floor((now - p.plantedAt) / 24) + 1) end
        if p.rooting then
            parts[#parts + 1] = "rooting"
        elseif (tonumber(p.stage) or 99) < Config.STAGE.Ripe and p.nextStageAt then
            parts[#parts + 1] = "next stage in " .. span(p.nextStageAt - now)
        end
    end
    if not isLoaded then parts[#parts + 1] = "unloaded" end
    local title = strainName(p) .. ", " .. string.lower(stageName(p))
    if p.sex == Config.SEX.MALE then title = title .. " (male)" elseif p.isHermie then title = title .. " (hermie)" end
    return { text = title, sub = table.concat(parts, " - "), tone = e.tone, buttons = plantButtons(p, e.k, isLoaded) }
end

local function plantsCard(s, now)
    local items, attention = {}, 0
    for _, e in ipairs(s.list) do
        if e.score > 0 then attention = attention + 1 end
    end
    for i = 1, math.min(LIST_MAX, #s.list) do items[i] = plantItem(s.list[i], now) end
    if #s.list > LIST_MAX then
        items[#items + 1] = { text = "and " .. (#s.list - LIST_MAX) .. " more", tone = "muted" }
    end
    if #items == 0 then items[1] = { text = "No plants in the world", tone = "muted" } end
    return { title = string.format("Plants (%d need attention)", attention), items = items }
end

local function reservoirList()
    local out = {}
    for k, r in pairs(hydroTable() or {}) do
        if isReservoir(r) then
            local cap = capacityOf(r)
            local level = tonumber(r.level) or 0
            out[#out + 1] = { k = k, r = r, cap = cap, level = level, frac = (cap and cap > 0) and level / cap or 1 }
        end
    end
    table.sort(out, function(a, b)
        if a.frac ~= b.frac then return a.frac < b.frac end
        return a.k < b.k
    end)
    return out
end

local function reservoirTone(e)
    local r = e.r
    local H = Config.Hydro or {}
    if e.level <= 0 or (tonumber(r.rot) or 0) >= (H.ROT_EARLY or 30) then return "red" end
    if e.frac < 0.25 or r.tainted or (tonumber(r.rot) or 0) > 0 then return "amber" end
    return "green"
end

local function reservoirCard()
    local list = reservoirList()
    local items = {}
    for i = 1, math.min(LIST_MAX, #list) do
        local e = list[i]
        local r = e.r
        local where = roomName(roomKeyOf(r.x, r.y, r.z or 0))
        local parts = {}
        parts[#parts + 1] = e.cap and string.format("%d of %d L", int(e.level), int(e.cap)) or string.format("%d L", int(e.level))
        if (tonumber(r.strength) or 0) > 0 then
            parts[#parts + 1] = string.format("%s nutrients %d%%", tostring(r.nutrient or ""), int((r.strength or 0) * 100))
        else
            parts[#parts + 1] = "no nutrients"
        end
        if r.tainted then parts[#parts + 1] = "tainted" end
        if (tonumber(r.rot) or 0) > 0 then parts[#parts + 1] = "rot " .. int(r.rot) end
        if e.level <= 0 then parts[#parts + 1] = "dry" elseif e.frac < 0.25 then parts[#parts + 1] = "nearly dry" end
        if not loaded(r.x, r.y, r.z or 0) then parts[#parts + 1] = "unloaded" end
        items[#items + 1] = {
            text = string.format("%s at %d, %d%s", RES_NAME[r.kind] or tostring(r.kind), int(r.x), int(r.y), where and (" (" .. where .. ")") or ""),
            sub = table.concat(parts, " - "), tone = reservoirTone(e),
            buttons = e.cap and { { label = "Refill", module = M, command = "refill", args = { key = e.k } } } or nil,
        }
    end
    if #list > LIST_MAX then items[#items + 1] = { text = "and " .. (#list - LIST_MAX) .. " more", tone = "muted" } end
    if #items == 0 then items[1] = { text = "No hydro reservoirs", tone = "muted" } end
    return { title = "Hydro reservoirs", items = items }
end

local function roomsCard(s)
    local rooms = roomsTable() or {}
    local list = {}
    for k, room in pairs(rooms) do
        if type(room) == "table" and room.x then list[#list + 1] = { k = k, room = room } end
    end
    table.sort(list, function(a, b) return a.k < b.k end)
    local K = Config.Climate or {}
    local items = {}
    for i = 1, math.min(LIST_MAX, #list) do
        local room = list[i].room
        local parts = { (s.byRoom[list[i].k] or 0) .. " plants" }
        local tone = "green"
        if room.temp then
            local t = tonumber(room.temp) or 0
            local text = string.format("%d C", int(t))
            if room.hum then text = text .. string.format(", %d%% RH", int(room.hum)) end
            local tg = K.TARGETS and (K.TARGETS[room.mode] or K.TARGETS.Veg)
            if K.TEMP_STRESS_ABOVE and t > K.TEMP_STRESS_ABOVE then text = text .. ", too hot"; tone = "red"
            elseif K.TEMP_STRESS_BELOW and t < K.TEMP_STRESS_BELOW then text = text .. ", too cold"; tone = "red"
            elseif tg and (t > tg.tHi or t < tg.tLo) then tone = "amber" end
            parts[#parts + 1] = text
        end
        parts[#parts + 1] = tostring(room.mode or "Veg") .. " " .. tostring(room.schedule or "")
        if room.powered == false or room.debugCut then parts[#parts + 1] = "no power"; tone = "red" end
        if not loaded(room.x, room.y, room.z or 0) then parts[#parts + 1] = "unloaded" end
        items[#items + 1] = { text = tostring(room.name or "Grow Room") .. string.format(" at %d, %d", int(room.x), int(room.y)),
            sub = table.concat(parts, " - "), tone = tone }
    end
    if #list > LIST_MAX then items[#items + 1] = { text = "and " .. (#list - LIST_MAX) .. " more", tone = "muted" } end
    if #items == 0 then items[1] = { text = "No grow room panels", tone = "muted" } end
    return { title = "Grow rooms", items = items }
end

local function strainsCard()
    local names = strainNames() or {}
    local known = 0
    for _ in pairs(names) do known = known + 1 end
    local S = CannabisMod.Strains
    local starters = (S and S.STARTERS and #S.STARTERS) or 6
    local hybrid = names.Hybrid and 1 or 0
    return { title = "Strains", rows = {
        { "Known strains", tostring(known) },
        { "Bred on this server", tostring(math.max(0, known - starters - hybrid)) },
    } }
end

C.register("dank", {
    title = "Dank",
    order = 30,
    commands = { [M .. ".advance"] = "admin", [M .. ".water"] = "admin", [M .. ".cure"] = "admin", [M .. ".kill"] = "admin",
        [M .. ".refill"] = "admin" },
    view = function()
        local now = nowHours()
        local s = survey(now)
        local lamps = {
            { "Plants: " .. s.total, s.total > 0 and "green" or "off" },
            { "Sick: " .. s.sick, s.sick > 0 and "amber" or "off" },
            { "Dead: " .. s.dead, s.dead > 0 and "red" or "off" },
            { "Ripe: " .. s.ripe, s.ripe > 0 and "green" or "off" },
        }
        return { lamps = lamps, cards = { plantsCard(s, now), reservoirCard(), roomsCard(s), strainsCard() } }
    end,
    -- Plants that need a look, low or rotting reservoirs, and every grow room panel.
    marks = function()
        local now = nowHours()
        local out = {}
        local s = survey(now)
        for _, e in ipairs(s.list) do
            if e.score <= 0 or #out >= MARKS_MAX then break end
            out[#out + 1] = { x = e.plant.x, y = e.plant.y, tone = e.tone,
                label = strainName(e.plant) .. ": " .. tostring(e.why) }
        end
        local n = 0
        for _, e in ipairs(reservoirList()) do
            local tone = reservoirTone(e)
            if tone == "green" or n >= MARKS_MAX then break end
            n = n + 1
            out[#out + 1] = { x = e.r.x, y = e.r.y, tone = tone,
                label = string.format("%s: %d L", RES_NAME[e.r.kind] or "Reservoir", int(e.level)) }
        end
        for _, room in pairs(roomsTable() or {}) do
            if type(room) == "table" and room.x and room.y then
                out[#out + 1] = { x = room.x, y = room.y, tone = "blue", label = "Grow room: " .. tostring(room.name or "") }
            end
        end
        return out
    end,
})

---------------------------------------------------------------- the handlers (authority only)

local function isAdmin(player) return C.atLeast(C.level(player), "admin") end

-- The plant a client named by tile key, from the server's own records; nil for anything odd.
local function plantFrom(args)
    local k = type(args) == "table" and args.key
    if type(k) ~= "string" or #k > 40 then return nil end
    local x, y, z = Config.parseKey(k)
    if not (x and y and z) or z < -32 or z > 32 then return nil end
    local plants = plantsTable()
    local plant = plants and plants[key(x, y, z)]
    if type(plant) ~= "table" or plant.x ~= x or plant.y ~= y then return nil end
    return plant, x, y, z
end

local function reservoirFrom(args)
    local k = type(args) == "table" and args.key
    if type(k) ~= "string" or #k > 40 then return nil end
    local x, y, z = Config.parseKey(k)
    if not (x and y and z) then return nil end
    local res = hydroTable()
    local r = res and res[key(x, y, z)]
    if not isReservoir(r) or r.x ~= x or r.y ~= y then return nil end
    return r
end

-- Fill a reservoir to the brim the way the mod's debug fill does: one that was empty gets fresh, clean water.
local function refill(r, now)
    local cap = capacityOf(r)
    if not cap then return false end
    if not r.everFilled or (tonumber(r.level) or 0) <= 0.05 then
        r.changedAt = now
        r.tainted = false
    end
    r.everFilled = true
    r.level = cap
    r.fillPending = nil
    return true
end

-- The reservoir a hydro plant drinks from, or nil (the mod's own lookup; it may link an unlinked site).
local function reservoirOfPlant(plant)
    local H = CannabisMod.Hydro
    if not (H and H.reservoirOf and Config.isHydro(plant.bag)) then return nil end
    local ok, r = pcall(H.reservoirOf, plant.x, plant.y, plant.z or 0)
    return ok and type(r) == "table" and r or nil
end

Net.on(M, "advance", function(player, args)
    if not isAdmin(player) then return end
    local plant = plantFrom(args)
    local R = CannabisMod.Registry
    if not (plant and R and R.advanceStage) or plant.dead or plant.rooting then return end
    if (tonumber(plant.stage) or 99) >= Config.STAGE.Ripe then return end
    R.advanceStage(plant)
end, 250)

Net.on(M, "water", function(player, args)
    if not isAdmin(player) then return end
    local plant, x, y, z = plantFrom(args)
    if not plant or plant.dead then return end
    if Config.isHydro(plant.bag) then
        local r = reservoirOfPlant(plant)
        if r then refill(r, nowHours()) end
        return
    end
    -- A soil plot: only while its square is loaded, so the vanilla plot and its object agree.
    local F, H = CannabisMod.Farming, CannabisMod.Hydro
    if not (F and F.getVanilla and loaded(x, y, z)) then return end
    local ok, luaObject = pcall(F.getVanilla, x, y, z)
    if not (ok and luaObject) then return end
    local want = (H and H.DEBUG_POT_WATER) or 80
    luaObject.waterLvl = want
    pcall(function() luaObject:saveData() end)
    plant.water = want
end, 250)

Net.on(M, "cure", function(player, args)
    if not isAdmin(player) then return end
    local plant = plantFrom(args)
    if not plant or plant.dead then return end
    plant.warnings = {}
    plant.care = (Config.Care and Config.Care.START) or 100
    plant.stress = 0
    plant.rootRot = 0
    plant.rootRotTrend = 0
    local r = reservoirOfPlant(plant)
    if r then
        r.rot = 0
        r.tainted = false
        r.recovering = nil
        r.rotTrend = 0
    end
end, 250)

Net.on(M, "kill", function(player, args)
    if not isAdmin(player) then return end
    local plant, x, y, z = plantFrom(args)
    local F = CannabisMod.Farming
    -- Only while loaded: killing the record alone would leave the vanilla plot growing on the map.
    if not (plant and F and F.killPlant) or plant.dead or not loaded(x, y, z) then return end
    F.killPlant(plant)
end, 250)

Net.on(M, "refill", function(player, args)
    if not isAdmin(player) then return end
    local r = reservoirFrom(args)
    if r then refill(r, nowHours()) end
end, 250)
