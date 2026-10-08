-- Server side of drying, trimming and curing: racks dry wet plants, trimming makes buds, jars cure them.
-- What never changes rides on the item (set when it is made); what changes over time is kept by item ID in ModData,
-- because later item data changes don't reliably sync in multiplayer.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisStrains"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"
require "CannabisMod/CannabisTraits"
require "CannabisMod/CannabisClimate"
require "CannabisMod/CannabisWeather"

local Config   = CannabisMod.Config
local Genetics = CannabisMod.Genetics
local Strains  = CannabisMod.Strains
local Seeds    = CannabisMod.Seeds
local Net      = CannabisMod.Net
local Registry = CannabisMod.Registry
local Farming  = CannabisMod.Farming
local SC       = CannabisMod.ServerCommands
local commands = SC.handlers
local D        = Config.Drying
local Cure     = Config.Curing

local Drying = {}
CannabisMod.Drying = Drying

-- db.plants[itemId] = { harvest, hours, moldy, sunLoss, at, seen, touched }   plants that have been on a rack
-- db.buds[itemId]   = { type, quality, cureHours, moldy, moldBaked, moist, at, seen, touched, fromItem }   buds part-way through a cure
-- db.jars[jarId or "barrel_x_y_z"] = { lastBurp, touched }      db.stations["x_y_z"] = { lastTick }
-- A bud item carries { type, quality, cureHours, moldy, moldBaked, moist, seeded, genetics, purple } under Config.Drying.BUD_DATA.
local db = nil

local function onInitGlobalModData()
    db = ModData.getOrCreate(Config.MODDATA_KEY .. "_Drying")
    db.plants = db.plants or {}
    db.buds = db.buds or {}
    db.jars = db.jars or {}
    db.stations = db.stations or {}
end
Events.OnInitGlobalModData.Add(onInitGlobalModData)

--- Test hook: the registry tables.
function Drying.data() return db end

local BUD_FIELDS = { "type", "quality", "cureHours", "moldy", "moldBaked", "moist", "moisture", "seeded", "genetics", "purple", "cureBonus" }

--- A bud's moisture (%) from its plant's drying hours: about 75% wet off the plant, 12% fully dry, down to 6% when over-dried.
function Drying.moistureFromHours(hours)
    local full = Config.dryHours()
    if hours < full then return math.floor((75 - 63 * hours / full) * 10 + 0.5) / 10 end
    return math.max(6, math.floor((12 - (hours - full) / 24) * 10 + 0.5) / 10)
end

--- A bud's moisture (%), estimating it for buds trimmed before moisture was recorded.
function Drying.moistureOf(rec)
    if type(rec.moisture) == "number" then return rec.moisture end
    return rec.moist and 30 or 12
end

--- A copy of a bud's own fields, without the station bookkeeping.
local function copyBud(from)
    local out = {}
    for _, k in ipairs(BUD_FIELDS) do out[k] = from[k] end
    out.strain = Strains.copy(from.strain)
    return out
end

--- What a bud is called: its strain when it has one, else its type, with "Purple" in front for purple buds.
local function strainWord(data)
    return CannabisMod.Weather.purpleName(data, (data.strain and data.strain.name) or tostring(data.type))
end

--- The data a bud item was made with, or nil for a plain bud (or one from before buds carried their data).
function Drying.budData(item)
    local data = item:getModData()[D.BUD_DATA]
    return type(data) == "table" and data or nil
end

--- What a bud is now: its curing record if it has one, else the data on the item, else nil.
function Drying.budRecord(item)
    return db.buds[item:getID()] or Drying.budData(item)
end

--- True once a bud has cured for the full time; after that nothing about it changes.
local function cureDone(rec)
    return (rec.cureHours or 0) >= Config.cureDays() * 24
end

--- A plant's drying record, or what an untracked plant counts as: a wet one fresh, a dried one just dry.
local function plantRecord(item)
    local rec = db.plants[item:getID()]
    if rec then return rec end
    local dried = Config.isDriedPlant(item:getFullType())
    return { hours = dried and Config.dryHours() or 0, moldy = false, sunLoss = 0 }
end

-- --------------------------------------------------------------------------
-- Environment at a station
-- --------------------------------------------------------------------------

--- Items of a type lying on a square (the world items).
local function worldItemsAt(square, fullType)
    local out = {}
    pcall(function()
        local objects = square:getWorldObjects()
        for i = 0, objects:size() - 1 do
            local item = objects:get(i):getItem()
            if item and item:getFullType() == fullType then out[#out + 1] = item end
        end
    end)
    return out
end

--- Placed furniture objects on a square whose sprite satisfies `test(spriteName)`.
local function objectsWhere(square, test)
    local out = {}
    pcall(function()
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            local sprite = obj:getSprite()
            if sprite and test(sprite:getName()) then out[#out + 1] = obj end
        end
    end)
    return out
end

--- Containers of the drying racks standing on a square (one per rack: the rack's first tile).
local function racksAt(square)
    local out = {}
    for _, obj in ipairs(objectsWhere(square, function(n) return D.RACK_SPRITES[n] end)) do
        local container = obj:getContainer()
        if container then out[#out + 1] = container end
    end
    return out
end

--- Containers of the curing barrels standing on a square.
local function barrelsAt(square)
    local out = {}
    for _, obj in ipairs(objectsWhere(square, function(n) return n == D.BARREL_SPRITE end)) do
        local container = obj:getContainer()
        if container then out[#out + 1] = container end
    end
    return out
end

--- Jar records are keyed by item ID; a barrel, being furniture, by its tile.
local function barrelKey(square)
    return "barrel_" .. Config.tileKey(square:getX(), square:getY(), square:getZ())
end

--- The squares of the rack standing on a tile: the tile itself and its other half.
local function rackSquares(square)
    if not square then return {} end
    local out = {}
    for _, obj in ipairs(objectsWhere(square, function(n) return D.RACK_PARTNER[n] end)) do
        local off = D.RACK_PARTNER[obj:getSprite():getName()]
        out[1] = square
        out[2] = getCell():getGridSquare(square:getX() + off[1], square:getY() + off[2], square:getZ())
        break
    end
    return out
end

local function isPowered(square)
    local ok, powered = pcall(function()
        if square:haveElectricity() then return true end
        return (not square:isOutside()) and getWorld():isHydroPowerOn() or false
    end)
    return ok and powered == true
end

--- True if a fan stands on this square (one pass over its objects, no lists built).
local function fanOn(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        if sprite and sprite:getName() == D.FAN_SPRITE then return true end
    end
    return false
end

--- Is a powered fan standing within FAN_RADIUS of this square? Stops at the first one found.
local function hasFan(square)
    local ok, found = pcall(function()
        local cell, r = getCell(), D.FAN_RADIUS
        local x, y, z = square:getX(), square:getY(), square:getZ()
        for dx = -r, r do
            for dy = -r, r do
                local sq = cell:getGridSquare(x + dx, y + dy, z)
                if sq and fanOn(sq) and isPowered(sq) then return true end
            end
        end
        return false
    end)
    return ok and found == true
end

--- Temperature, outdoors, daylight, rain and fan at a square.
function Drying.rackSquares(square) return rackSquares(square) end

function Drying.environment(square)
    local env = { tempC = nil, outdoors = false, sun = false, rain = false, fan = false }
    if not square then return env end
    env.tempC = Farming.conditionsAt(square)
    pcall(function() env.outdoors = square:isOutside() end)
    if env.outdoors then
        local hour = getGameTime():getHour()
        env.sun = hour >= 6 and hour < 20
        pcall(function() env.rain = getClimateManager():getRainIntensity() > 0.05 end)
    end
    env.fan = hasFan(square)
    -- Inside a grow room the room's own air decides temperature and humidity.
    local Rooms = CannabisMod.Rooms
    if Rooms then
        local t, h = Rooms.climateAt(square:getX(), square:getY(), square:getZ())
        if t then env.tempC, env.hum = t, h end
    end
    return env
end

--- How fast plants dry here (1 = normal).
function Drying.dryRate(env)
    local rate = 1
    if env.tempC then
        rate = 1 + (env.tempC - D.TEMP_REF_C) * D.TEMP_RATE_PER_C
    end
    if env.hum then rate = rate * CannabisMod.Climate.dryFactor(env.hum) end
    rate = Config.clamp(rate, D.RATE_MIN, D.RATE_MAX)
    if env.fan then rate = rate * D.FAN_RATE end
    return rate
end

--- Chance per hour that a still-wet plant goes moldy. `wetness` is 0-1.
function Drying.moldPerHour(env, wetness)
    local p = D.MOLD_BASE * math.max(D.MOLD_DRY_FLOOR, wetness)
    if env.outdoors then p = p * D.MOLD_OUTDOORS end
    if env.rain then p = p * D.MOLD_RAIN end
    if env.tempC and env.tempC > D.MOLD_WARM_C then p = p * D.MOLD_WARM end
    if env.tempC and env.tempC < D.MOLD_COLD_C then p = p * D.MOLD_COLD end
    if env.fan then p = p * D.MOLD_FAN end
    if env.hum then p = p * CannabisMod.Climate.moldFactor(env.hum) end
    return p * (Config.sandbox("MoldChance") or 1)
end

local function chanceOver(perHour, hours)
    return 1 - (1 - math.min(perHour, 1)) ^ hours
end

-- --------------------------------------------------------------------------
-- Drying racks
-- --------------------------------------------------------------------------

--- One plant's drying progress over `elapsed` hours.
function Drying.advancePlant(rec, env, elapsed)
    local wetness = 1 - Config.clamp(rec.hours / Config.dryHours(), 0, 1)
    rec.hours = rec.hours + elapsed * Drying.dryRate(env)
    if not rec.moldy and Config.rollPercent(chanceOver(Drying.moldPerHour(env, wetness), elapsed) * 100) then
        rec.moldy = true
    end
    if env.sun then
        rec.sunLoss = math.min(D.SUN_LOSS_MAX, (rec.sunLoss or 0) + elapsed * D.SUN_LOSS_PER_HOUR)
    end
end

--- Items lying directly in a container (not inside bags in it) that pass `test(fullType)`.
--- Only direct contents dry or cure, so an item swapped for its next stage is always in this container.
local function directItems(container, test)
    local out = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if test(item:getFullType()) then out[#out + 1] = item end
    end
    return out
end

local function wetPlantsIn(container)
    return directItems(container, Config.isHangingPlant)
end

--- How many wet hanging plants a container holds (the grow room's humidity counts them).
function Drying.wetCountIn(container) return #wetPlantsIn(container) end

--- The rack containers standing on a square.
function Drying.racksAt(square) return racksAt(square) end

--- Swap a plant that has finished drying for its dried item, carrying its record across.
local function convertToDried(container, item, rec)
    local harvest = item:getModData().CannabisHarvest
    local driedType = Config.DRIED_PLANT_ITEMS[harvest and harvest.type] or Config.DRIED_PLANT_ITEMS.Hybrid
    local added = container:AddItems(driedType, 1)
    local dried = added and added:size() > 0 and added:get(0)
    if not dried then return end
    if harvest then
        dried:getModData().CannabisHarvest = harvest
        local name = Strains.plantName(harvest, "Dried")
        if name then dried:setName(name) end
    end
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    sendAddItemsToContainer(container, added)
    db.plants[item:getID()] = nil
    db.plants[dried:getID()] = rec
end

local function isBud(fullType) return fullType == D.BUD_ITEM end

local function budsIn(container)
    return directItems(container, isBud)
end

--- Settle a rack: progress every plant that was in it at the last settle.
local function settleRack(container, key, square, now)
    local station = db.stations[key]
    local prev = station.lastTick or now
    local elapsed = Config.clamp(now - prev, 0, D.MAX_CATCHUP_HOURS)
    -- The environment (a fan search among other things) is only worked out if a plant actually moves on.
    local env = nil
    for _, item in ipairs(wetPlantsIn(container)) do
        local id = item:getID()
        local rec = db.plants[id]
        if not rec then
            rec = { harvest = item:getModData().CannabisHarvest, hours = 0, moldy = false, sunLoss = 0 }
            db.plants[id] = rec
            -- Plants harvested before they were named by strain pick their name up the first time they hang.
            local name = Strains.plantName(rec.harvest, "Wet")
            if name and item:getName() ~= name then pcall(item.setName, item, name) end
        end
        if rec.at == key and rec.seen == prev and elapsed > 0 then
            env = env or Drying.environment(square)
            local wasMoldy = rec.moldy
            Drying.advancePlant(rec, env, elapsed)
            if rec.moldy and not wasMoldy and CannabisMod.Rooms then CannabisMod.Rooms.logTile(key, "Mold on a drying plant", now) end
        end
        rec.at, rec.seen, rec.touched = key, now, now
        if Config.isWetPlant(item:getFullType()) and rec.hours >= Config.dryHours() then
            convertToDried(container, item, rec)
        end
    end
end

-- --------------------------------------------------------------------------
-- Curing jars
-- --------------------------------------------------------------------------

--- The air temperature (C) at a station tile key: its grow room's air when it has one, else the square's. Nil when unknown.
function Drying.cureTemp(key)
    local x, y, z = tostring(key):match("^(-?%d+)_(-?%d+)_(-?%d+)$")
    if not x then return nil end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    local Rooms = CannabisMod.Rooms
    local t = Rooms and Rooms.climateAt(x, y, z)
    if t then return t end
    local ok, square = pcall(function() return getCell():getGridSquare(x, y, z) end)
    return CannabisMod.Weather.tempAt(ok and square or nil, nil)
end

--- Jar progress over `elapsed` hours in air of `tempC` (optional): buds cure, slower when cold or hot, and an unburped jar
--- (or one holding moist buds) can grow mold, faster when hot, which spreads to every bud in it. Returns true if mold struck.
function Drying.advanceJar(jar, buds, elapsed, now, tempC)
    local Weather = CannabisMod.Weather
    local speed = Weather.cureSpeed(tempC)
    local curing, moist = false, false
    for _, rec in ipairs(buds) do
        rec.cureHours = (rec.cureHours or 0) + elapsed * speed
        if rec.cureHours < Config.cureDays() * 24 then curing = true end
        if rec.moist then moist = true end
    end
    if not curing then return false end
    local overdueFrom = jar.lastBurp + Cure.BURP_EVERY_HOURS
    local overdue = math.max(0, now - math.max(now - elapsed, overdueFrom))
    if overdue <= 0 then return false end
    local p = Cure.MOLD_PER_HOUR * (moist and Cure.MOIST_MULT or 1) * (Config.sandbox("MoldChance") or 1)
    p = p * Weather.cureMoldFactor(tempC)
    if Config.rollPercent(chanceOver(p, overdue) * 100) then
        for _, rec in ipairs(buds) do rec.moldy = true end
        return true
    end
    return false
end

--- The curing record for a bud in a cure container, made from the item's data the first time it goes in.
--- Returns nil for a plain bud or one that has already finished curing.
local function cureRecord(item)
    local id = item:getID()
    local rec = db.buds[id]
    if rec then return rec end
    local data = Drying.budData(item)
    if not data or cureDone(data) then return nil end
    rec = copyBud(data)
    rec.cureHours = rec.cureHours or 0
    rec.fromItem = true
    db.buds[id] = rec
    return rec
end

--- The name a bud goes by for its quality now, like the names trimming gives.
local function budName(data)
    if data.moldy then return "Moldy " .. strainWord(data) .. " Bud" end
    local q = Genetics.curedQuality(data.quality, data.cureHours, data.moldy, data.moldBaked, data.cureBonus)
    return Config.qualityTier(q) .. " " .. strainWord(data) .. " Bud"
end
Drying.budName = budName

--- Swap a bud for a fresh one that carries `rec` on the item, and drop its record. Used once nothing more can change.
local function finishBud(container, item, rec)
    local added = container:AddItems(D.BUD_ITEM, 1)
    local fresh = added and added:size() > 0 and added:get(0)
    if not fresh then return end
    local data = copyBud(rec)
    data.moist = false
    fresh:getModData()[D.BUD_DATA] = data
    fresh:setName(budName(data))
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    sendAddItemsToContainer(container, added)
    db.buds[item:getID()] = nil
end

--- Settle any curing container (a jar's inventory or a barrel's) whose burp record lives under `cureKey`.
local function settleCure(container, cureKey, key, now)
    local station = db.stations[key]
    local prev = station.lastTick or now
    local elapsed = Config.clamp(now - prev, 0, D.MAX_CATCHUP_HOURS)
    local jar = db.jars[cureKey]
    if not jar then
        jar = { lastBurp = now }
        db.jars[cureKey] = jar
    end
    jar.touched = now
    local present, presentItems, finished = {}, {}, {}
    for _, item in ipairs(budsIn(container)) do
        local rec = cureRecord(item)
        if rec then
            if rec.at == key and rec.seen == prev then
                present[#present + 1] = rec
                presentItems[#present] = item
            end
            rec.at, rec.seen, rec.touched = key, now, now
        elseif Drying.budData(item) then
            finished[#finished + 1] = item
        end
    end
    if elapsed <= 0 then return end
    -- These records now hold cure progress the items don't have, so pruning must leave them.
    for _, rec in ipairs(present) do rec.changed = true end
    -- Mold in the jar also spoils buds that had already finished curing.
    if Drying.advanceJar(jar, present, elapsed, now, #present > 0 and Drying.cureTemp(key) or nil) then
        if CannabisMod.Rooms then CannabisMod.Rooms.logTile(key, "Mold in a curing jar or barrel: every bud in it is spoiled", now) end
        for _, item in ipairs(finished) do
            local data = Drying.budData(item)
            if not data.moldy then
                local spoiled = copyBud(data)
                spoiled.moldy = true
                finishBud(container, item, spoiled)
            end
        end
    end
    -- A bud whose cure is over now carries its final state itself, so the save can forget it.
    for i, rec in ipairs(present) do
        if cureDone(rec) then finishBud(container, presentItems[i], rec) end
    end
end

local function settleJar(jarItem, key, now)
    settleCure(jarItem:getInventory(), jarItem:getID(), key, now)
end

local function settleBarrels(square, key, now, barrels)
    for _, barrel in ipairs(barrels or barrelsAt(square)) do settleCure(barrel, barrelKey(square), key, now) end
end

-- --------------------------------------------------------------------------
-- Stations: discovery and the 10-minute tick
-- --------------------------------------------------------------------------

local function stationKey(x, y, z) return Config.tileKey(x, y, z) end

local function register(square)
    local key = stationKey(square:getX(), square:getY(), square:getZ())
    if not db.stations[key] then db.stations[key] = {} end
end

--- True if a rack, curing barrel or jar is on this square: one pass over its objects, then its loose items.
local function hasStation(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if name and (D.RACK_SPRITES[name] or name == D.BARREL_SPRITE) and obj:getContainer() then return true end
    end
    local items = square:getWorldObjects()
    for i = 0, items:size() - 1 do
        local item = items:get(i):getItem()
        if item and item:getFullType() == D.JAR_ITEM then return true end
    end
    return false
end

--- Find racks and jars placed near each player.
function Drying.discover()
    if not db then return end
    local players = {}
    pcall(function()
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do players[#players + 1] = list:get(i) end
    end)
    if #players == 0 then
        for i = 0, 3 do
            local p = getSpecificPlayer(i)
            if p then players[#players + 1] = p end
        end
    end
    local r = D.SCAN_RADIUS
    -- Players standing together share squares: each square is looked at once per pass.
    local seen = #players > 1 and {} or nil
    for _, player in ipairs(players) do
        pcall(function()
            local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
            local cell = getCell()
            local floor = seen and (seen[pz] or {})
            if seen then seen[pz] = floor end
            for dx = -r, r do
                local x = px + dx
                local column = floor and (floor[x] or {})
                if floor then floor[x] = column end
                for dy = -r, r do
                    local y = py + dy
                    if not (column and column[y]) then
                        if column then column[y] = true end
                        local sq = cell:getGridSquare(x, y, pz)
                        if sq and hasStation(sq) then register(sq) end
                    end
                end
            end
        end)
    end
end

--- Process every registered station whose square is loaded.
function Drying.tick()
    if not db then return end
    local now = Registry.nowHours()
    for key, station in pairs(db.stations) do
        local x, y, z = key:match("^(-?%d+)_(-?%d+)_(-?%d+)$")
        local square = x and getCell():getGridSquare(tonumber(x), tonumber(y), tonumber(z))
        if square then
            local racks, jars, barrels = racksAt(square), worldItemsAt(square, D.JAR_ITEM), barrelsAt(square)
            if #racks == 0 and #jars == 0 and #barrels == 0 then
                db.stations[key] = nil
                db.jars["barrel_" .. key] = nil
            else
                for _, rack in ipairs(racks) do settleRack(rack, key, square, now) end
                for _, jar in ipairs(jars) do settleJar(jar, key, now) end
                settleBarrels(square, key, now, barrels)
                station.lastTick = now
            end
        end
    end
end

Events.EveryOneMinute.Add(Drying.discover)
Events.EveryTenMinutes.Add(Drying.tick)

--- Records that hold nothing the item doesn't, untouched for RECORD_KEEP_DAYS, can go.
--- Kept: old-style bud records, cure progress, drying progress and anything at a station still in use. Returns how many went.
function Drying.prune(now)
    if not db then return 0 end
    now = now or Registry.nowHours()
    local keep = D.RECORD_KEEP_DAYS * 24
    local dropped = 0
    local function sweep(list, canDrop)
        local gone = {}
        for id, rec in pairs(list) do
            -- Records from before this sweep existed start their clock now.
            if not rec.touched then
                rec.touched = now
            elseif now - rec.touched > keep and canDrop(rec, id) then
                gone[#gone + 1] = id
            end
        end
        for _, id in ipairs(gone) do list[id] = nil end
        dropped = dropped + #gone
    end
    -- A record whose rack or jar is still known is kept, since that station may just be out of loaded range.
    local function away(rec) return not (rec.at and db.stations[rec.at]) end
    sweep(db.buds, function(rec) return rec.fromItem == true and not rec.changed and away(rec) end)
    sweep(db.jars, function(_, id)
        local isBarrel = type(id) == "string" and id:sub(1, 7) == "barrel_"
        return not (isBarrel and db.stations[id:sub(8)])
    end)
    return dropped
end
Events.EveryDays.Add(function() Drying.prune() end)

-- --------------------------------------------------------------------------
-- Commands
-- --------------------------------------------------------------------------

--- A curing jar by item ID, in the inventory or placed on a nearby square.
local function findStation(player, args, fullType)
    local id = tonumber(args.id)
    if not id then return nil end
    local function match(item) return item:getID() == id and item:getFullType() == fullType end
    local found = Seeds.findItem(player:getInventory(), match)
    if found then return found, nil end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return nil end
    local square = getCell():getGridSquare(x, y, z)
    if not square then return nil end
    for _, item in ipairs(worldItemsAt(square, fullType)) do
        if item:getID() == id then return item, square end
    end
    return nil
end

--- Settle one placed station right now (so a check shows current numbers).
local function settleNow(square)
    if not square then return end
    register(square)
    local key = stationKey(square:getX(), square:getY(), square:getZ())
    local now = Registry.nowHours()
    for _, rack in ipairs(racksAt(square)) do settleRack(rack, key, square, now) end
    for _, jar in ipairs(worldItemsAt(square, D.JAR_ITEM)) do settleJar(jar, key, now) end
    settleBarrels(square, key, now)
    db.stations[key].lastTick = now
end

commands.checkRack = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return end
    local items = {}
    for _, square in ipairs(rackSquares(getCell():getGridSquare(x, y, z))) do
        settleNow(square)
        for _, container in ipairs(racksAt(square)) do
            for _, item in ipairs(wetPlantsIn(container)) do items[#items + 1] = item end
        end
    end
    if #items == 0 then
        Net.notify(player, "The rack is empty")
        return
    end
    local lines = {}
    for _, item in ipairs(items) do
        local rec = plantRecord(item)
        local pct = math.floor(Config.clamp(rec.hours / Config.dryHours(), 0, 1) * 100)
        local note = pct >= 100 and "dry" or (pct .. "% dry")
        if rec.moldy then note = note .. ", MOLD" end
        if rec.hours > D.OVERDRY_AFTER then note = note .. ", over-dried" end
        lines[#lines + 1] = note
    end
    Net.notify(player, "Rack: " .. table.concat(lines, "; "))
end

--- Tell the player how a curing container is doing: bud count, curing days, time since the last burp and mold.
local function reportCure(player, container, cureKey, label)
    local items = budsIn(container)
    if #items == 0 then
        Net.notify(player, "The " .. label:lower() .. " is empty")
        return
    end
    local days, moldy = 0, false
    for _, item in ipairs(items) do
        local rec = Drying.budRecord(item)
        if rec then
            days = math.max(days, (rec.cureHours or 0) / 24)
            if rec.moldy then moldy = true end
        end
    end
    local info = db.jars[cureKey]
    local sinceBurp = info and (Registry.nowHours() - info.lastBurp) or 0
    local msg = string.format("%s: %d buds, curing %.0f of %d days, burped %.0fh ago", label, #items, days, Config.cureDays(), sinceBurp)
    if moldy then msg = msg .. ". It smells musty: MOLD" end
    Net.notify(player, msg)
end

--- Burp a curing container: resets its mold clock and lets moist buds finish drying.
local function burpCure(player, container, cureKey, label)
    local info = db.jars[cureKey]
    if not info then
        info = {}
        db.jars[cureKey] = info
    end
    info.lastBurp = Registry.nowHours()
    info.touched = info.lastBurp
    local budtender = CannabisMod.Traits.has(player, "budtender")
    for _, item in ipairs(budsIn(container)) do
        -- A Budtender's care lifts the whole cure, so their burp marks each bud for the bigger bonus.
        local rec = budtender and cureRecord(item) or db.buds[item:getID()]
        if rec and budtender then rec.cureBonus = CannabisMod.Traits.BUDTENDER_CURE end
        if rec and rec.moist and (rec.cureHours or 0) >= 24 then
            rec.moist = false
            rec.moisture = math.min(Drying.moistureOf(rec), 15)
            rec.changed = true
        end
    end
    Net.notify(player, "Burped the " .. label:lower())
end

commands.checkJar = function(player, args)
    local jar, square = findStation(player, args, D.JAR_ITEM)
    if not jar then return end
    if square then settleNow(square) end
    reportCure(player, jar:getInventory(), jar:getID(), "Jar")
end

commands.burpJar = function(player, args)
    local jar, square = findStation(player, args, D.JAR_ITEM)
    if not jar then return end
    if square then settleNow(square) end
    burpCure(player, jar:getInventory(), jar:getID(), "Jar")
end

--- The barrel standing on the tile a player is acting on, after checking they're close enough.
local function barrelFor(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return nil end
    local square = getCell():getGridSquare(x, y, z)
    local barrel = square and barrelsAt(square)[1]
    return barrel, square
end

commands.checkBarrel = function(player, args)
    local barrel, square = barrelFor(player, args)
    if not barrel then return end
    settleNow(square)
    reportCure(player, barrel, barrelKey(square), "Barrel")
end

commands.burpBarrel = function(player, args)
    local barrel, square = barrelFor(player, args)
    if not barrel then return end
    settleNow(square)
    burpCure(player, barrel, barrelKey(square), "Barrel")
end

--- Trim a whole plant into buds. Dry time, mold and sun exposure set the quality.
commands.trimPlant = function(player, args)
    local id = tonumber(args.id)
    local plant = id and Seeds.findItem(player:getInventory(), function(item)
        return item:getID() == id and Config.isHangingPlant(item:getFullType())
    end)
    if not plant then return end
    if not Seeds.findCuttingTool(player) then
        Net.notify(player, "You need scissors or a sharp knife to trim")
        return
    end
    local harvest = plant:getModData().CannabisHarvest
    if not harvest then
        Net.notify(player, "This plant can't be trimmed")
        return
    end
    local rec = plantRecord(plant)
    local quality = Genetics.driedQuality(harvest.quality, rec)
    local count = math.max(1, harvest.budYield or 1)
    local moist = rec.hours < Config.dryHours() * Cure.MOIST_BELOW
    -- A Trim Hand stops before trimming a wet plant unless they chose to trim it anyway.
    if moist and not args.force and CannabisMod.Traits.has(player, "trimhand") then
        Net.notify(player, "It's still too wet to cure safely. Hang it longer, or use Trim Plant Anyway")
        return
    end

    local container = plant:getContainer()
    if container then
        container:Remove(plant)
        sendRemoveItemFromContainer(container, plant)
    end
    db.plants[id] = nil

    local name = (rec.moldy and "Moldy " or (Config.qualityTier(quality) .. " ")) .. strainWord(harvest) .. " Bud"
    -- Each bud carries its own data; it is set before the item is sent, so clients get it too.
    Farming.giveItems(player, D.BUD_ITEM, count, function(item)
        item:setName(name)
        item:getModData()[D.BUD_DATA] = {
            type = harvest.type, strain = Strains.copy(harvest.strain), quality = quality, cureHours = 0,
            moldy = rec.moldy == true, moldBaked = rec.moldy == true, moist = moist,
            moisture = Drying.moistureFromHours(rec.hours),
            seeded = harvest.seeded == true, genetics = harvest.genetics, purple = harvest.purple == true or nil,
        }
    end)

    local msg = "Trimmed " .. count .. " " .. name .. (count == 1 and "" or "s")
    if rec.moldy then msg = msg .. ". They're covered in mold" end
    Net.notify(player, msg)
end

-- Debug helpers (debug mode or admins only)

local function debugAllowed(player)
    return isDebugEnabled() or (player.getAccessLevel and player:getAccessLevel() ~= "None")
end

commands.debugDryingKit = function(player, args)
    if not debugAllowed(player) then return end
    Farming.giveItems(player, D.RACK_ITEM, 1)
    Farming.giveItems(player, D.JAR_ITEM, 1)
    Farming.giveItems(player, D.BARREL_ITEM, 1)
    Farming.giveItems(player, D.FAN_ITEM, 1)
    Farming.giveItems(player, "Base.Scissors", 1)
    Farming.giveItems(player, Config.WET_PLANT_ITEMS.Indica, 2, function(item)
        item:getModData().CannabisHarvest = { type = "Indica", quality = 80, budYield = 6, genetics = 80, generation = 1 }
    end)
    Net.notify(player, "Gave a rack, jar, barrel, fan, scissors and 2 wet plants. Place the rack, barrel and fan like furniture; set the jar down")
end

--- Pretend `hours` hours have passed at every station (applied at the next settle).
commands.debugAdvanceStations = function(player, args)
    if not debugAllowed(player) or not db then return end
    local h = tonumber(args.hours) or 24
    for key, station in pairs(db.stations) do
        if station.lastTick then station.lastTick = station.lastTick - h end
        for _, rec in pairs(db.plants) do if rec.at == key and rec.seen then rec.seen = rec.seen - h end end
        for _, rec in pairs(db.buds) do if rec.at == key and rec.seen then rec.seen = rec.seen - h end end
    end
    for _, jar in pairs(db.jars) do jar.lastBurp = jar.lastBurp - h end
    Drying.tick()
    Net.notify(player, "Advanced racks and jars by " .. h .. " hours")
end

local KNOWN_TYPES = {}
for _, t in pairs(Config.TYPES) do KNOWN_TYPES[t] = true end

--- A bud's data as the client read it off the item (for a bud in a nearby container), checked field by field.
local function clientBud(data)
    if type(data) ~= "table" or not KNOWN_TYPES[data.type] or type(data.quality) ~= "number" then return nil end
    return { type = data.type, strain = Strains.sanitize(data.strain), quality = Config.clamp(data.quality, 0, 200),
             cureHours = tonumber(data.cureHours) or 0, moldy = data.moldy == true, moldBaked = data.moldBaked == true,
             moist = data.moist == true, moisture = tonumber(data.moisture), purple = data.purple == true or nil,
             cureBonus = tonumber(data.cureBonus) and Config.clamp(tonumber(data.cureBonus), 0, CannabisMod.Traits.BUDTENDER_CURE) or nil }
end

--- What a bud is worth, by Agriculture level.
commands.inspectBud = function(player, args)
    local id = tonumber(args.id)
    local rec = id and db.buds[id]
    if not rec and id then
        local item = Seeds.findItem(player:getInventory(), function(i) return i:getID() == id end)
        rec = item and Drying.budData(item)
    end
    rec = rec or clientBud(args.data)
    if not rec then
        Net.notify(player, "Just a bud")
        return
    end
    local reading = CannabisMod.Traits.reading(player)
    -- A Budtender reads a bud completely, whatever their Agriculture.
    local level = reading.buds and 10 or SC.agricultureLevel(player)
    local q = Genetics.curedQuality(rec.quality, rec.cureHours, rec.moldy, rec.moldBaked, rec.cureBonus)
    local parts = { rec.strain and (strainWord(rec) .. " (" .. rec.type .. ")") or rec.type }
    local moisture = Drying.moistureOf(rec)
    parts[#parts + 1] = string.format("moisture %d%%", math.floor(moisture + 0.5))
    -- Mold: moldy buds say so; clean ones show their risk, which moist buds raise in a jar.
    if rec.moldy then
        parts[#parts + 1] = "moldy"
    elseif rec.moist or moisture > 15 then
        parts[#parts + 1] = "no mold yet, high mold risk while curing (burp often)"
    else
        parts[#parts + 1] = "no mold, low mold risk"
    end
    if (level >= 6 or reading.genetics) and rec.strain then parts[#parts + 1] = Strains.describe(rec.strain) end
    if level >= 4 then parts[#parts + 1] = Config.qualityTier(q) .. " quality" end
    if level >= 8 then parts[#parts + 1] = "quality " .. q end
    if level >= 3 then parts[#parts + 1] = string.format("cured %.0f days", (rec.cureHours or 0) / 24) end
    Net.notify(player, table.concat(parts, ", "))
end
