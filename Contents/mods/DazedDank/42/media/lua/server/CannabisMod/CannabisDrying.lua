-- Server side of drying, trimming and curing: racks dry wet plants, trimming makes buds, jars cure them.
-- Records are kept by item ID in ModData because item data changes don't reliably sync in multiplayer.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"

local Config   = CannabisMod.Config
local Genetics = CannabisMod.Genetics
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

-- db.plants[itemId] = { harvest, hours, moldy, sunLoss, at, seen }   wet plants
-- db.buds[itemId]   = { type, quality, cureHours, moldy, moldBaked, moist, at, seen }
-- db.jars[itemId]   = { lastBurp }      db.stations["x_y_z"] = { lastTick }
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

--- Is a powered fan standing within FAN_RADIUS of this square?
local function hasFan(square)
    local found = false
    pcall(function()
        local cell, r = getCell(), D.FAN_RADIUS
        for dx = -r, r do
            for dy = -r, r do
                local sq = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                if sq and #objectsWhere(sq, function(n) return n == D.FAN_SPRITE end) > 0 and isPowered(sq) then
                    found = true
                end
            end
        end
    end)
    return found
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
    return env
end

--- How fast plants dry here (1 = normal).
function Drying.dryRate(env)
    local rate = 1
    if env.tempC then
        rate = 1 + (env.tempC - D.TEMP_REF_C) * D.TEMP_RATE_PER_C
    end
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

local function wetPlantsIn(container)
    return Seeds.findAll(container, function(item) return Config.isHangingPlant(item:getFullType()) end)
end

--- Swap a plant that has finished drying for its dried item, carrying its record across.
local function convertToDried(container, item, rec)
    local harvest = item:getModData().CannabisHarvest
    local driedType = Config.DRIED_PLANT_ITEMS[harvest and harvest.type] or Config.DRIED_PLANT_ITEMS.Hybrid
    local added = container:AddItems(driedType, 1)
    local dried = added and added:size() > 0 and added:get(0)
    if not dried then return end
    if harvest then dried:getModData().CannabisHarvest = harvest end
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    sendAddItemsToContainer(container, added)
    db.plants[item:getID()] = nil
    db.plants[dried:getID()] = rec
end

local function budsIn(container)
    return Seeds.findAll(container, function(item) return item:getFullType() == D.BUD_ITEM end)
end

--- Settle a rack: progress every plant that was in it at the last settle.
local function settleRack(container, key, square, now)
    local station = db.stations[key]
    local prev = station.lastTick or now
    local elapsed = Config.clamp(now - prev, 0, D.MAX_CATCHUP_HOURS)
    local env = Drying.environment(square)
    for _, item in ipairs(wetPlantsIn(container)) do
        local id = item:getID()
        local rec = db.plants[id]
        if not rec then
            rec = { harvest = item:getModData().CannabisHarvest, hours = 0, moldy = false, sunLoss = 0 }
            db.plants[id] = rec
        end
        if rec.at == key and rec.seen == prev and elapsed > 0 then
            Drying.advancePlant(rec, env, elapsed)
        end
        rec.at, rec.seen = key, now
        if Config.isWetPlant(item:getFullType()) and rec.hours >= Config.dryHours() then
            convertToDried(container, item, rec)
        end
    end
end

-- --------------------------------------------------------------------------
-- Curing jars
-- --------------------------------------------------------------------------

--- Jar progress over `elapsed` hours: buds cure, and a jar left unburped
--- (or holding moist buds) can grow mold, which spreads to every bud in it.
function Drying.advanceJar(jar, buds, elapsed, now)
    local curing, moist = false, false
    for _, rec in ipairs(buds) do
        rec.cureHours = (rec.cureHours or 0) + elapsed
        if rec.cureHours < Config.cureDays() * 24 then curing = true end
        if rec.moist then moist = true end
    end
    if not curing then return end
    local overdueFrom = jar.lastBurp + Cure.BURP_EVERY_HOURS
    local overdue = math.max(0, now - math.max(now - elapsed, overdueFrom))
    if overdue <= 0 then return end
    local p = Cure.MOLD_PER_HOUR * (moist and Cure.MOIST_MULT or 1) * (Config.sandbox("MoldChance") or 1)
    if Config.rollPercent(chanceOver(p, overdue) * 100) then
        for _, rec in ipairs(buds) do rec.moldy = true end
    end
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
    local present = {}
    for _, item in ipairs(budsIn(container)) do
        local rec = db.buds[item:getID()]
        if rec then
            if rec.at == key and rec.seen == prev then present[#present + 1] = rec end
            rec.at, rec.seen = key, now
        end
    end
    if elapsed > 0 then Drying.advanceJar(jar, present, elapsed, now) end
end

local function settleJar(jarItem, key, now)
    settleCure(jarItem:getInventory(), jarItem:getID(), key, now)
end

local function settleBarrels(square, key, now)
    for _, barrel in ipairs(barrelsAt(square)) do settleCure(barrel, barrelKey(square), key, now) end
end

-- --------------------------------------------------------------------------
-- Stations: discovery and the 10-minute tick
-- --------------------------------------------------------------------------

local function stationKey(x, y, z) return Config.tileKey(x, y, z) end

local function register(square)
    local key = stationKey(square:getX(), square:getY(), square:getZ())
    if not db.stations[key] then db.stations[key] = {} end
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
    for _, player in ipairs(players) do
        pcall(function()
            local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
            local cell = getCell()
            for dx = -r, r do
                for dy = -r, r do
                    local sq = cell:getGridSquare(px + dx, py + dy, pz)
                    if sq and (#racksAt(sq) > 0 or #worldItemsAt(sq, D.JAR_ITEM) > 0 or #barrelsAt(sq) > 0) then
                        register(sq)
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
            else
                for _, rack in ipairs(racks) do settleRack(rack, key, square, now) end
                for _, jar in ipairs(jars) do settleJar(jar, key, now) end
                settleBarrels(square, key, now)
                station.lastTick = now
            end
        end
    end
end

Events.EveryOneMinute.Add(Drying.discover)
Events.EveryTenMinutes.Add(Drying.tick)

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
        local rec = db.plants[item:getID()]
        local pct = rec and math.floor(Config.clamp(rec.hours / Config.dryHours(), 0, 1) * 100) or 0
        local note = pct >= 100 and "dry" or (pct .. "% dry")
        if rec and rec.moldy then note = note .. ", MOLD" end
        if rec and rec.hours > D.OVERDRY_AFTER then note = note .. ", over-dried" end
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
        local rec = db.buds[item:getID()]
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
    for _, item in ipairs(budsIn(container)) do
        local rec = db.buds[item:getID()]
        if rec and rec.moist and (rec.cureHours or 0) >= 24 then rec.moist = false end
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
    local rec = db.plants[id] or { hours = 0, moldy = false, sunLoss = 0 }
    local quality = Genetics.driedQuality(harvest.quality, rec)
    local count = math.max(1, harvest.budYield or 1)
    local moist = rec.hours < Config.dryHours() * Cure.MOIST_BELOW

    local container = plant:getContainer()
    if container then
        container:Remove(plant)
        sendRemoveItemFromContainer(container, plant)
    end
    db.plants[id] = nil

    local name = (rec.moldy and "Moldy " or (Config.qualityTier(quality) .. " ")) .. harvest.type .. " Bud"
    Farming.giveItems(player, D.BUD_ITEM, count, function(item)
        item:setName(name)
        db.buds[item:getID()] = {
            type = harvest.type, quality = quality, cureHours = 0,
            moldy = rec.moldy == true, moldBaked = rec.moldy == true, moist = moist,
            seeded = harvest.seeded == true, genetics = harvest.genetics,
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

--- What a bud is worth, by Agriculture level.
commands.inspectBud = function(player, args)
    local id = tonumber(args.id)
    local rec = id and db.buds[id]
    if not rec then
        Net.notify(player, "Just a bud")
        return
    end
    local level = SC.agricultureLevel(player)
    local q = Genetics.curedQuality(rec.quality, rec.cureHours, rec.moldy, rec.moldBaked)
    local parts = { rec.type }
    if rec.moldy then parts[#parts + 1] = "moldy" end
    if level >= 4 then parts[#parts + 1] = Config.qualityTier(q) .. " quality" end
    if level >= 8 then parts[#parts + 1] = "quality " .. q end
    if level >= 3 then parts[#parts + 1] = string.format("cured %.0f days", (rec.cureHours or 0) / 24) end
    Net.notify(player, table.concat(parts, ", "))
end
