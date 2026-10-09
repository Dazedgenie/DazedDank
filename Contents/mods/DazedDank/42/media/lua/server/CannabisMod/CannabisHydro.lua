-- Hydroponic reservoirs: plants drink from a reservoir instead of the plot, nutrients are mixed into it and run down,
-- old or tainted water and air pumps without power cause root rot, and bleach cures it if caught early.
-- Three systems: DWC (a bucket is its own reservoir), RDWC (sites share a control bucket) and Ebb and Flow (tables flooded from a reservoir).

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"
require "CannabisMod/CannabisPlumbing"
require "CannabisMod/CannabisWorld"

local Config   = CannabisMod.Config
local World    = CannabisMod.World
local Net      = CannabisMod.Net
local Seeds    = CannabisMod.Seeds
local Registry = CannabisMod.Registry
local Farming  = CannabisMod.Farming
local SC       = CannabisMod.ServerCommands
local commands = SC.handlers
local H        = Config.Hydro

local Hydro = {}
CannabisMod.Hydro = Hydro

-- res[tileKey] holds two kinds of record. A site record per hydro plot: { kind, medium, link } (a DWC bucket's site
-- record is also its reservoir). A reservoir record: { kind, x, y, z, level, strength, nutrient, changedAt, tainted, rot, lastTick }.
local res = nil

-- Kept beside res so nothing has to walk every record: drips[tileKey] = each drip tank record,
-- and sites[controlKey] = { [siteKey] = true } for each RDWC site linked to that control bucket.
local drips, sites = {}, {}
local EMPTY = {}

local function addSite(controlKey, siteKey)
    local set = sites[controlKey]
    if not set then set = {} sites[controlKey] = set end
    set[siteKey] = true
end

local function removeSite(controlKey, siteKey)
    local set = sites[controlKey]
    if set then set[siteKey] = nil end
end

--- Build both indexes from the saved records (after load or a reset).
local function indexAll()
    drips, sites = {}, {}
    for key, r in pairs(res or EMPTY) do
        if r.isDrip then drips[key] = r end
        if r.link then addSite(r.link, key) end
    end
end

--- Set or clear an RDWC site's link, keeping the site index in step.
local function setLink(site, siteKey, link)
    if site.link then removeSite(site.link, siteKey) end
    site.link = link
    if link then addSite(link, siteKey) end
end

--- Flag a record as a drip tank and list it.
local function markDrip(r)
    r.isDrip = true
    drips[Config.tileKey(r.x, r.y, r.z)] = r
end

--- Take a record out of the saved table and both indexes.
local function dropRecord(key)
    local r = res and res[key]
    if not r then return end
    drips[key] = nil
    if r.link then removeSite(r.link, key) end
    res[key] = nil
end

Events.OnInitGlobalModData.Add(function()
    res = ModData.getOrCreate(Config.MODDATA_KEY .. "_Hydro")
    indexAll()
end)

--- Replace the saved table (tests use this to start clean).
function Hydro._reset(tbl)
    res = tbl or {}
    indexAll()
end

--- The record for a tile, made on first use as an empty, fresh reservoir.
function Hydro.get(x, y, z, kind)
    if not res then return nil end
    local key = Config.tileKey(x, y, z)
    local r = res[key]
    if not r then
        r = { level = 0, strength = 0, changedAt = Registry.nowHours(), tainted = false, rot = 0 }
        res[key] = r
    end
    r.kind = kind or r.kind
    r.x, r.y, r.z = x, y, z
    return r
end

--- Forget a tile's record (its bucket was picked up or its plot is gone).
function Hydro.clear(x, y, z)
    dropRecord(Config.tileKey(x, y, z))
    Hydro.forgetSiteCounts()
    Hydro.forgetLinks()
end

-- Site counts per control bucket, worked out once per game minute (or after a link changes) instead of on every call.
local siteCounts, siteCountsAt = {}, nil

--- Note that an RDWC link changed, so the site counts are worked out again.
function Hydro.forgetSiteCounts() siteCountsAt = nil end

--- How many site buckets are linked to the control bucket with this tile key.
function Hydro.sitesOf(controlKey)
    local now = Registry.nowHours()
    if siteCountsAt ~= now then siteCounts, siteCountsAt = {}, now end
    local n = siteCounts[controlKey]
    if n == nil then
        n = 0
        for siteKey in pairs(sites[controlKey] or EMPTY) do
            local r = res and res[siteKey]
            -- A record whose bucket is gone (no RDWC bag on its tile) no longer holds a place.
            if r and r.link == controlKey and r.x and Registry.getBag(r.x, r.y, r.z) == "rdwc" then n = n + 1 end
        end
        siteCounts[controlKey] = n
    end
    return n
end

--- Litres a reservoir holds: fixed for DWC and Ebb and Flow, the control bucket plus every linked site for RDWC.
function Hydro.capacity(r)
    if r and r.kind == "rdwc" then
        return H.RDWC_CONTROL_L + H.RDWC_SITE_L * Hydro.sitesOf(Config.tileKey(r.x, r.y, r.z))
    end
    if r and r.kind == "ebb" then return H.EBB_RESERVOIR_L end
    if r and r.kind == "drip" then return Config.Drip.TANK_L end
    -- A DWC bucket holds its own size: the XL bucket more than the standard one.
    local def = r and r.x and Config.GrowBag[Registry.getBag(r.x, r.y, r.z)]
    return (def and def.reservoirL) or H.RESERVOIR_L.dwc
end

-- During the plant tick every site of a shared reservoir asks the same questions; their answers are kept until it ends.
local tickMemo = nil

--- Start keeping square answers for this plant tick (the Registry calls this at the top of its tick).
function Hydro.beginTick() tickMemo = {} end

--- Stop keeping them, so later questions see the world as it is.
function Hydro.endTick() tickMemo = nil end

-- True if an object with this sprite stands on the square (nil when the square isn't loaded).
local scanSprite = World.hasSprite

local function hasSprite(x, y, z, sprite)
    if not tickMemo then return scanSprite(x, y, z, sprite) end
    local key = sprite .. "@" .. x .. "_" .. y .. "_" .. z
    local hit = tickMemo[key]
    if hit == nil then
        hit = scanSprite(x, y, z, sprite)
        tickMemo[key] = (hit == nil) and "unknown" or hit
        return hit
    end
    if hit == "unknown" then return nil end
    return hit
end

--- True if an RDWC control bucket stands on this square (nil when the square isn't loaded).
function Hydro.hasControl(x, y, z) return hasSprite(x, y, z, H.CONTROL_SPRITE) end

--- True if an Ebb and Flow flood reservoir stands on this square (nil when the square isn't loaded).
function Hydro.hasFlood(x, y, z) return hasSprite(x, y, z, H.FLOOD_SPRITE) end

--- True if a drip irrigation tank stands on this square (nil when the square isn't loaded).
function Hydro.hasDrip(x, y, z) return hasSprite(x, y, z, Config.Drip.SPRITE) end

--- Every drip tank record: for key, r in Hydro.eachDrip() do ... end
function Hydro.eachDrip()
    local list = {}
    for key, r in pairs(drips) do
        if res and res[key] == r then list[#list + 1] = { key, r } end
    end
    local i = 0
    return function()
        i = i + 1
        local e = list[i]
        if e then return e[1], e[2] end
    end
end

-- RDWC sites that found no control in range, by tile key -> when they looked (not saved; cleared by forgetLinks).
local missedSearch = {}

--- The control bucket's reservoir record for an RDWC site, linking the site to the nearest control with room if needed.
function Hydro.linkSite(x, y, z)
    local site = Hydro.get(x, y, z, "rdwc")
    if site.link then
        local cx, cy, cz = Config.parseKey(site.link)
        if cx and Hydro.hasControl(cx, cy, cz) ~= false then
            local r = Hydro.get(cx, cy, cz, "rdwc")
            r.isControl = true
            return r
        end
        setLink(site, Config.tileKey(x, y, z), nil)
        Hydro.forgetSiteCounts()
    end
    -- A site with no control in range doesn't search again until a control is placed or the cache runs out.
    local now = Registry.nowHours()
    local lastMiss = missedSearch[Config.tileKey(x, y, z)]
    if lastMiss and now - lastMiss < H.LINK_CACHE_HOURS and now >= lastMiss then return nil end
    local best, bestD = nil, nil
    local R = H.RDWC_RANGE
    for dx = -R, R do
        for dy = -R, R do
            if Hydro.hasControl(x + dx, y + dy, z) then
                local key = Config.tileKey(x + dx, y + dy, z)
                local d = dx * dx + dy * dy
                if Hydro.sitesOf(key) < H.RDWC_MAX_SITES and (not bestD or d < bestD) then best, bestD = { x + dx, y + dy }, d end
            end
        end
    end
    if not best then
        missedSearch[Config.tileKey(x, y, z)] = now
        return nil
    end
    setLink(site, Config.tileKey(x, y, z), Config.tileKey(best[1], best[2], z))
    Hydro.forgetSiteCounts()
    local r = Hydro.get(best[1], best[2], z, "rdwc")
    r.isControl = true
    return r
end

-- --------------------------------------------------------------------------
-- Ebb and Flow networks: tables that touch (not diagonally) form a row; the flood reservoir beside any of them feeds the
-- nearest EBB_MAX_SITES. Working a row out walks the tables, so each answer is kept for LINK_CACHE_HOURS.
-- --------------------------------------------------------------------------
local ebbCache = {}       -- table tileKey -> { at, rkey (or false), linked }
local ebbSites = {}       -- reservoir tileKey -> { at, keys = { linked site keys } }
local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

--- Forget every worked-out table network (a table or reservoir was placed or removed).
function Hydro.forgetLinks()
    ebbCache, ebbSites, missedSearch = {}, {}, {}
end

--- Every table touching (not diagonally) the given starting tiles, walked outward, at most EBB_SCAN_MAX.
local function walkTables(starts, z)
    local out, seen, queue, head = {}, {}, {}, 1
    for _, t in ipairs(starts) do
        local k = t[1] .. "_" .. t[2]
        if not seen[k] then seen[k] = true queue[#queue + 1] = t end
    end
    while head <= #queue and #out < H.EBB_SCAN_MAX do
        local t = queue[head]
        head = head + 1
        out[#out + 1] = t
        for _, d in ipairs(NEIGHBOURS) do
            local nx, ny = t[1] + d[1], t[2] + d[2]
            local k = nx .. "_" .. ny
            if not seen[k] and Registry.getBag(nx, ny, z) == "ebb" then
                seen[k] = true
                queue[#queue + 1] = { nx, ny }
            end
        end
    end
    return out
end

--- Work out which reservoir feeds a table's row and which tables it feeds (every row beside it, nearest
--- EBB_MAX_SITES); fills both caches. A row whose reservoir might be on an unloaded square is left as it was.
local function solveEbb(x, y, z, now)
    local row = walkTables({ { x, y } }, z)
    -- Every reservoir beside the row; the one with the lowest tile key feeds it, so the answer never depends on
    -- which table asked.
    local rx, ry, unknown, best
    for _, t in ipairs(row) do
        for _, d in ipairs(NEIGHBOURS) do
            local cx, cy = t[1] + d[1], t[2] + d[2]
            local has = Hydro.hasFlood(cx, cy, z)
            if has == nil then unknown = true end
            local key = Config.tileKey(cx, cy, z)
            if has and (not best or key < best) then rx, ry, best = cx, cy, key end
        end
    end
    if not rx then
        -- A reservoir may stand on an unloaded square: say "unknown" (not "unconnected") for a little while.
        for _, t in ipairs(row) do ebbCache[Config.tileKey(t[1], t[2], z)] = { at = now, rkey = false, unknown = unknown or nil } end
        return
    end
    -- From the reservoir: every row touching it, nearest tables first.
    local starts = {}
    for _, d in ipairs(NEIGHBOURS) do
        if Registry.getBag(rx + d[1], ry + d[2], z) == "ebb" then starts[#starts + 1] = { rx + d[1], ry + d[2] } end
    end
    local fed = walkTables(starts, z)
    table.sort(fed, function(a, b)
        return math.abs(a[1] - rx) + math.abs(a[2] - ry) < math.abs(b[1] - rx) + math.abs(b[2] - ry)
    end)
    local rkey, keys = Config.tileKey(rx, ry, z), {}
    for i, t in ipairs(fed) do
        local k = Config.tileKey(t[1], t[2], z)
        local linked = i <= H.EBB_MAX_SITES
        if linked then keys[#keys + 1] = k end
        ebbCache[k] = { at = now, rkey = linked and rkey or false }
    end
    ebbSites[rkey] = { at = now, keys = keys }
end

--- The flood reservoir record feeding an Ebb and Flow table, or nil when it isn't connected; the second result is true
--- when that can't be known yet because a square beside the row isn't loaded.
function Hydro.linkEbb(x, y, z)
    local now = Registry.nowHours()
    local key = Config.tileKey(x, y, z)
    local c = ebbCache[key]
    -- A settled answer holds for EBB_LINK_HOURS (placing or picking up clears it at once); "unknown" is retried sooner.
    local life = (c and c.unknown) and H.LINK_CACHE_HOURS or H.EBB_LINK_HOURS
    if not c or now - c.at > life or now < c.at then
        solveEbb(x, y, z, now)
        c = ebbCache[key]
    end
    if not (c and c.rkey) then return nil, (c and c.unknown) or false end
    local rx, ry, rz = Config.parseKey(c.rkey)
    local r = Hydro.get(rx, ry, rz, "ebb")
    r.isFlood = true
    return r
end

--- The table tiles a flood reservoir feeds (from the last worked-out network), as tile keys.
function Hydro.ebbSitesOf(rkey)
    local e = ebbSites[rkey]
    return e and e.keys or {}
end

--- The reservoir a hydro plot drinks from: its own for DWC, the linked control bucket's for RDWC, the flood reservoir
--- for an Ebb and Flow table (nil when not connected).
function Hydro.reservoirOf(x, y, z)
    local kind = Registry.getBag(x, y, z)
    local def = kind and Config.GrowBag[kind]
    if not (def and def.hydro) then return nil end
    if def.hydro == "rdwc" then return Hydro.linkSite(x, y, z) end
    if def.hydro == "ebb" then return Hydro.linkEbb(x, y, z) end
    return Hydro.get(x, y, z, def.hydro)
end

--- The reservoir a water line feeds: a DWC bucket's own, an RDWC control bucket's or a flood reservoir. Nil if that kind isn't on the tile.
function Hydro.reservoirAt(x, y, z, kind)
    if kind == "rdwc" then
        if not Hydro.hasControl(x, y, z) then return nil end
        local r = Hydro.get(x, y, z, "rdwc")
        r.isControl = true
        return r
    end
    if kind == "ebb" then
        if not Hydro.hasFlood(x, y, z) then return nil end
        local r = Hydro.get(x, y, z, "ebb")
        r.isFlood = true
        return r
    end
    if kind == "dwc" and Config.hydroOf(Registry.getBag(x, y, z)) == "dwc" then return Hydro.get(x, y, z, "dwc") end
    if kind == "drip" then
        if not Hydro.hasDrip(x, y, z) then return nil end
        local r = Hydro.get(x, y, z, "drip")
        markDrip(r)
        return r
    end
    return nil
end

--- The reservoir record behind an object already known to be one (Dazed Plumbing hands it over), without re-scanning its square.
function Hydro.reservoirOfObject(x, y, z, kind)
    if kind == "dwc" then
        return Config.hydroOf(Registry.getBag(x, y, z)) == "dwc" and Hydro.get(x, y, z, "dwc") or nil
    end
    local r = Hydro.get(x, y, z, kind)
    if r then
        if kind == "rdwc" then r.isControl = true end
        if kind == "ebb" then r.isFlood = true end
        if kind == "drip" then markDrip(r) end
    end
    return r
end

--- True when a flood timer keeps this reservoir's tables wet: one fitted to it, or the grow room panel's.
function Hydro.hasFloodTimer(r)
    if r.floodTimer then return true end
    local Rooms = CannabisMod.Rooms
    return Rooms ~= nil and Rooms.floodTimerAt(r.x, r.y, r.z)
end

--- Flood every table a reservoir feeds: the rockwool soaks up enough to stay wet for EBB_WET_HOURS.
--- Returns "flooded", or why not: "noPower", "noWater" or "noTables".
--- Why a flood reservoir can't flood right now ("noTables", "noPower", "noWater"), or nil when it can.
function Hydro.floodBlocker(r)
    local n = #Hydro.ebbSitesOf(Config.tileKey(r.x, r.y, r.z))
    if n == 0 then return "noTables" end
    if not Hydro.pumpState(r) then return "noPower" end
    if r.level < H.EBB_FLOOD_L * n then return "noWater" end
    return nil
end

--- Copy when an object's rockwool dries onto it, so a right-click on the client can show it. Sent only when it moves half an hour or more,
--- and while a flood timer keeps it wet only when the timer flag changes (the client then shows it full).
local function markWet(obj, wetUntil, timer)
    if not obj then return end
    local md = obj:getModData()
    if timer and md.DDWetTimer == true then
        md.DDWetUntil = wetUntil
        return
    end
    local was = tonumber(md.DDWetUntil)
    if was and math.abs(was - wetUntil) < 0.5 and (md.DDWetTimer == true) == (timer == true) then return end
    md.DDWetUntil = wetUntil
    md.DDWetTimer = timer or nil
    pcall(obj.transmitModData, obj)
end

--- Show a flood table's wetness on its plot object.
function Hydro.markTableWet(x, y, z, wetUntil, timer)
    local luaObject = Farming.getVanilla(x, y, z)
    local obj = luaObject and luaObject.getIsoObject and luaObject:getIsoObject()
    markWet(obj, wetUntil, timer)
end

--- Show the wetness of the tables a flood reservoir feeds on the reservoir itself.
function Hydro.markReservoirWet(r, wetUntil, timer)
    local square = getCell():getGridSquare(r.x, r.y, r.z)
    if not square then return end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        if sprite and sprite:getName() == H.FLOOD_SPRITE then return markWet(obj, wetUntil, timer) end
    end
end

function Hydro.flood(r, now)
    local keys = Hydro.ebbSitesOf(Config.tileKey(r.x, r.y, r.z))
    local blocked = Hydro.floodBlocker(r)
    if blocked then return blocked end
    local timer = Hydro.hasFloodTimer(r)
    for _, k in ipairs(keys) do
        local x, y, z = Config.parseKey(k)
        Hydro.get(x, y, z, "ebb").wetUntil = now + H.EBB_WET_HOURS
        Hydro.markTableWet(x, y, z, now + H.EBB_WET_HOURS, timer)
    end
    Hydro.markReservoirWet(r, now + H.EBB_WET_HOURS, timer)
    return "flooded"
end

--- True if the pumps at this square have power, false if not, nil when the square isn't loaded (unknown).
function Hydro.pumpsOn(x, y, z)
    if not Config.sandbox("PumpsNeedPower") then return true end
    local square = getCell():getGridSquare(x, y, z)
    if not square then return nil end
    -- A grow room panel without power takes every pump in its room down with it.
    if CannabisMod.Rooms and CannabisMod.Rooms.poweredAt(x, y, z) == false then return false end
    return World.isPoweredSafe(square)
end

--- A reservoir's pump power, falling back to the last known state while its square isn't loaded.
function Hydro.pumpState(r)
    local key = tickMemo and ("power@" .. r.x .. "_" .. r.y .. "_" .. r.z)
    if key and tickMemo[key] ~= nil then return tickMemo[key] end
    local on = Hydro.pumpsOn(r.x, r.y, r.z)
    if on ~= nil then r.pumpOn = on end
    local state = on
    if on == nil then state = r.pumpOn ~= false end
    if key then tickMemo[key] = state end
    return state
end


--- True once a reservoir has gone this long without a change.
function Hydro.isStale(r, now)
    local rate = math.max(0.1, Config.sandbox("ReservoirUseRate") or 1)
    return (now - (r.changedAt or now)) > H.STALE_DAYS * 24 / rate
end

--- Keep the vanilla plot's water where the reservoir says, so vanilla never sees a thirsty or drowned plant.
local function setPlotWater(plant, water)
    plant.water = water
    local luaObject = Farming.getVanilla(plant.x, plant.y, plant.z)
    if luaObject and luaObject.waterLvl ~= water then
        luaObject.waterLvl = water
        pcall(function() luaObject:saveData() end)
    end
end

--- Reservoir-wide changes since its last update: nutrients run down and root rot builds; once per reservoir per tick.
local function advanceReservoir(r, now)
    local hours = Config.clamp(now - (r.lastTick or now), 0, 24)
    r.lastTick = now
    if hours <= 0 then return end
    local rate = Config.sandbox("ReservoirUseRate") or 1
    if r.strength > 0 then r.strength = math.max(0, r.strength - hours * rate / H.NUTRIENT_HOURS) end
    local risk = 0
    -- Ebb and Flow roots air out between floods, so they need no air pump and rot slowly.
    local ebb = r.kind == "ebb"
    if not ebb and not Hydro.pumpState(r) then risk = risk + H.ROT_NO_AIR end
    if Hydro.isStale(r, now) then risk = risk + H.ROT_STALE end
    if r.tainted then risk = risk + H.ROT_TAINTED end
    -- Rot feeds on itself, unless bleach-treated roots are recovering.
    if r.rot > 0 and not r.recovering then risk = risk + H.ROT_SPREAD end
    if ebb then risk = risk * H.EBB_ROT_MULT end
    local before = r.rot
    local change = risk * hours * (Config.sandbox("RootRotRisk") or 1)
    if r.recovering then change = change - H.ROT_RECOVER_PER_HOUR * hours end
    r.rot = Config.clamp(r.rot + change, 0, H.ROT_DEAD)
    if before < H.ROT_EARLY and r.rot >= H.ROT_EARLY and CannabisMod.Rooms then
        CannabisMod.Rooms.logTile(Config.tileKey(r.x, r.y, r.z), "Root rot set in at the reservoir at " .. r.x .. ", " .. r.y, now)
    end
    if r.rot <= 0 then r.recovering = nil end
    -- Which way the rot moved this tick: 1 rising, -1 falling, 0 steady.
    r.rotTrend = (r.rot > before + 0.001 and 1) or (r.rot < before - 0.001 and -1) or 0
end
Hydro.advanceReservoir = advanceReservoir

--- Every 10 minutes for each living hydro plant: drink from its reservoir, and suffer hunger or root rot from it.
function Hydro.update(plant, now)
    -- Nobody near the grow: the hydro side pauses (vanilla still runs the plot), so being away can't rot or dry the roots.
    local r, unknown = Hydro.reservoirOf(plant.x, plant.y, plant.z)
    if unknown or not getCell():getGridSquare(plant.x, plant.y, plant.z) then
        -- The reservoir's own clock stops only if it is out of range too; loaded sites keep it running.
        if r and not getCell():getGridSquare(r.x, r.y, r.z) then r.lastTick = now end
        plant.hydroTick = now
        setPlotWater(plant, plant.water or H.PLOT_WATER)
        return
    end
    local fresh = plant.hydroTick == nil
    local hours = Config.clamp(now - (plant.hydroTick or now), 0, 24)
    plant.hydroTick = now
    local ebb = plant.bag == "ebb" or Registry.getBag(plant.x, plant.y, plant.z) == "ebb"
    if not r then
        -- An RDWC site or flood table with nothing feeding it has no water at all.
        setPlotWater(plant, H.DRY_PLOT_WATER)
        plant.warnings.noControl = (not ebb) or nil
        plant.warnings.noFlood = ebb or nil
        plant.hydro = { level = 0, cap = 0, strength = 0, unlinked = true, ebb = ebb or nil }
        return
    end
    plant.warnings.noControl, plant.warnings.noFlood = nil, nil
    -- Fresh roots in a reservoir nothing has drunk from lately: the idle time grew no rot, so its clock starts now.
    if fresh then
        if r.lastTick and now - r.lastTick > H.IDLE_HOURS then r.lastTick = now end
    end
    advanceReservoir(r, now)
    local rate = Config.sandbox("ReservoirUseRate") or 1

    -- Ebb and Flow: the rockwool is wet for a while after each flood; a flood timer keeps it wet while the pump has power and water.
    local wet, wetHours = true, nil
    if ebb then
        local site = Hydro.get(plant.x, plant.y, plant.z, "ebb")
        local timed = Hydro.hasFloodTimer(r) and not Hydro.floodBlocker(r)
        if timed then site.wetUntil = now + H.EBB_WET_HOURS end
        Hydro.markTableWet(plant.x, plant.y, plant.z, site.wetUntil or 0, timed)
        -- Every table of a reservoir asks; the reservoir object is marked once per tick.
        if timed then
            local memoKey = tickMemo and ("wet@" .. r.x .. "_" .. r.y .. "_" .. r.z)
            if not (memoKey and tickMemo[memoKey]) then
                Hydro.markReservoirWet(r, site.wetUntil, true)
                if memoKey then tickMemo[memoKey] = true end
            end
        end
        wetHours = math.max(0, (site.wetUntil or 0) - now)
        wet = wetHours > 0
        plant.warnings.mediumDry = (not wet) or nil
    end

    -- The plant drinks, more when big from extra veg; a dry flood table has nothing to drink.
    if wet then
        local drink = (H.DRINK_PER_HOUR[plant.stage] or 0.3) * hours * rate * (1 + Config.Timer.vegBonus(plant.extraVegHours))
        r.level = math.max(0, math.min(r.level, Hydro.capacity(r)) - drink)
    end
    local watered = (ebb and wet) or (not ebb and r.level > 0)
    local cap = Hydro.capacity(r)
    setPlotWater(plant, watered and H.PLOT_WATER or H.DRY_PLOT_WATER)
    plant.warnings.reservoirDry = (r.level <= 0) or nil

    -- A growing plant in a weak reservoir starves.
    local feeding = plant.stage >= Config.STAGE.Vegetative and plant.stage < Config.STAGE.Ripe
    if feeding and r.strength < H.HUNGRY_BELOW then
        Registry.applyPenalty(plant, H.HUNGRY_PER_HOUR * hours, "hungry")
    else
        plant.warnings.hungry = nil
    end

    local stale = Hydro.isStale(r, now)
    plant.warnings.staleReservoir = stale or nil
    plant.warnings.pumpOff = (not ebb and not Hydro.pumpState(r)) or nil
    plant.rootRot = r.rot
    plant.rootRotTrend = r.rotTrend or 0
    local sites = nil
    if r.kind == "rdwc" then sites = Hydro.sitesOf(Config.tileKey(r.x, r.y, r.z)) end
    if ebb then sites = #Hydro.ebbSitesOf(Config.tileKey(r.x, r.y, r.z)) end
    plant.hydro = { level = r.level, cap = cap, strength = r.strength, nutrient = r.nutrient, stale = stale,
                    sites = sites, ebb = ebb or nil, wetHours = wetHours, floodTimer = (ebb and Hydro.hasFloodTimer(r)) or nil }
    -- Rot in a shared reservoir reaches every site's roots.
    if r.rot >= H.ROT_EARLY then
        Registry.applyPenalty(plant, H.ROT_CARE_PER_HOUR * hours, "rootRot")
        if plant.nextStageAt then plant.nextStageAt = plant.nextStageAt + hours * 0.5 end
    else
        plant.warnings.rootRot = nil
    end
    if r.rot >= H.ROT_DEAD then Farming.killPlant(plant) end
end

--- Whether a hydro plot's roots would find water now: a connected reservoir with water (and, on a flood table, wet rockwool).
function Hydro.isMoist(x, y, z)
    local r = Hydro.reservoirOf(x, y, z)
    if not r or r.level <= 0 then return false end
    if Registry.getBag(x, y, z) == "ebb" then
        local site = res and res[Config.tileKey(x, y, z)]
        return site ~= nil and (site.wetUntil or 0) > Registry.nowHours()
    end
    return true
end

--- Mix a nutrient into one plant's share of a reservoir: burn if the water was still strong, a penalty for the wrong food, a bonus for the right one.
local function applyNutrient(plant, nutrient, burn)
    plant.lastNutrient = nutrient
    plant.warnings.hungry = nil
    if burn then
        Registry.applyPenalty(plant, Config.Care.NUTRIENT_BURN, "nutrientBurn")
        return "burn"
    end
    local wanted = { Vegetative = { Veg = true }, PreFlower = { Veg = true, Bloom = true }, Flowering = { Bloom = true } }
    local stageName = Config.STAGES[plant.stage]
    if not (wanted[stageName] and wanted[stageName][nutrient]) then
        Registry.applyPenalty(plant, Config.Care.WRONG_NUTRIENT, "wrongNutrient")
        return "wrong"
    end
    plant.fedThisStage = (plant.fedThisStage or 0) + 1
    if plant.fedThisStage == 1 then plant.care = math.min(100, plant.care + Config.Care.RIGHT_NUTRIENT_BONUS) end
    return "mixed"
end

--- Mix a nutrient into the plant's reservoir; dosing a reservoir that is still strong burns the plant.
function Hydro.feed(plant, nutrient)
    local r = Hydro.reservoirOf(plant.x, plant.y, plant.z)
    if not r or r.level <= 0 then return "noWater" end
    local burn = r.strength > H.BURN_ABOVE
    r.strength, r.nutrient = 1, nutrient
    return applyNutrient(plant, nutrient, burn)
end

--- Mix a nutrient into a reservoir with no one plant in mind (the grow room panel): every living plant it feeds takes the result.
--- Returns "noWater", "burn" or "mixed" for the water, and how many plants were fed.
function Hydro.dose(r, nutrient)
    if r.level <= 0 then return "noWater", 0 end
    -- A drip tank just holds the food; the drip feeds each pot as it waters it.
    if r.kind == "drip" then
        r.strength, r.nutrient = 1, nutrient
        return "mixed", 0
    end
    local burn = r.strength > H.BURN_ABOVE
    r.strength, r.nutrient = 1, nutrient
    local fed = 0
    for _, plant in ipairs(Hydro.servedPlants(r)) do
        applyNutrient(plant, nutrient, burn)
        fed = fed + 1
    end
    return burn and "burn" or "mixed", fed
end

-- --------------------------------------------------------------------------
-- Water from the player's containers
-- --------------------------------------------------------------------------

--- Water and tainted-water containers in the player's inventory, fullest first.
local function waterContainers(player)
    local out = {}
    for _, item in ipairs(Seeds.findAll(player:getInventory(), function(item)
        local ok, kind = pcall(function()
            local fc = item:getFluidContainer()
            if not fc or fc:getAmount() <= 0 or not fc:getPrimaryFluid() then return nil end
            return fc:getPrimaryFluid():getFluidTypeString()
        end)
        return ok and (kind == "Water" or kind == "TaintedWater")
    end)) do
        out[#out + 1] = item
    end
    table.sort(out, function(a, b) return a:getFluidContainer():getAmount() > b:getFluidContainer():getAmount() end)
    return out
end

--- Pour up to `want` litres from the player's water containers. Returns litres poured and whether any was tainted.
local function pourWater(player, want)
    local poured, tainted = 0, false
    for _, item in ipairs(waterContainers(player)) do
        if poured >= want then break end
        local fc = item:getFluidContainer()
        local take = math.min(fc:getAmount(), want - poured)
        if fc:getPrimaryFluid():getFluidTypeString() == "TaintedWater" then tainted = true end
        fc:removeFluid(take)
        pcall(function() sendItemStats(item) end)
        poured = poured + take
    end
    return poured, tainted
end
Hydro.pourWater = pourWater

-- --------------------------------------------------------------------------
-- Commands
-- --------------------------------------------------------------------------

--- What a player is acting on: a hydro plot (its site record and reservoir) or an RDWC control bucket (its reservoir).
--- Returns luaObject (nil for a control bucket), site record, reservoir (nil for an unlinked site), or nothing if neither.
local function hydroTarget(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return nil end
    local kind = Registry.getBag(x, y, z)
    if Config.isHydro(kind) then
        local luaObject = Farming.getVanilla(x, y, z)
        if not luaObject then return nil end
        return luaObject, Hydro.get(x, y, z, Config.GrowBag[kind].hydro), Hydro.reservoirOf(x, y, z), true
    end
    if Hydro.hasControl(x, y, z) then return nil, nil, Hydro.reservoirAt(x, y, z, "rdwc"), true end
    if Hydro.hasFlood(x, y, z) then return nil, nil, Hydro.reservoirAt(x, y, z, "ebb"), true end
    if Hydro.hasDrip(x, y, z) then return nil, nil, Hydro.reservoirAt(x, y, z, "drip"), true end
    return nil
end

--- The reservoir to act on, or nil after telling the player why there isn't one.
local function reservoirFor(player, args)
    local luaObject, site, r, found = hydroTarget(player, args)
    if not found then return nil end
    if not r then
        if Registry.getBag(tonumber(args.x), tonumber(args.y), tonumber(args.z)) == "ebb" then
            Net.notify(player, "This table isn't connected: stand a flood reservoir beside a row of touching tables")
        else
            Net.notify(player, "This site isn't connected: put an RDWC control bucket within " .. H.RDWC_RANGE .. " tiles")
        end
        return nil
    end
    return r
end
Hydro.reservoirFor = reservoirFor

commands.hydroAddMedium = function(player, args)
    local luaObject, r = hydroTarget(player, args)
    local itemType = H.MEDIUM_ITEMS[args.medium]
    if not (luaObject and r and itemType) then return end
    local def = Config.GrowBag[Registry.getBag(luaObject.x, luaObject.y, luaObject.z)]
    if def and def.rockwoolOnly and args.medium ~= "rockwool" then
        Net.notify(player, "Flood tables take rockwool cubes only")
        return
    end
    if luaObject.state ~= "plow" or r.medium then
        Net.notify(player, "The net pot already has a medium")
        return
    end
    local item = player:getInventory():getFirstTypeRecurse(itemType)
    if not item then
        Net.notify(player, args.medium == "rockwool" and "You need a rockwool cube" or "You need a bag of clay pebbles")
        return
    end
    local container = item:getContainer()
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    r.medium = args.medium
    Registry.setBagSoiled(luaObject.x, luaObject.y, luaObject.z, true)
    luaObject:setSpriteName(farming_vegetableconf.getSpriteName(luaObject))
    luaObject:setObjectName(farming_vegetableconf.getObjectName(luaObject))
    luaObject:saveData()
    Net.notify(player, args.medium == "rockwool" and "Set a rockwool cube in the net pot" or "Filled the net pot with clay pebbles")
end

--- Top up `r` for the player. `say` receives each message (the menu shows it as a floating note; the panel gathers them).
function Hydro.topUp(player, r, say)
    say = say or function(text) Net.notify(player, text) end
    local room = Hydro.capacity(r) - r.level
    if room <= 0.05 then
        say("The reservoir is full")
        return
    end
    -- On a water line (its own or the room's), Top Up asks the line to fill it instead of pouring by hand.
    local Rooms = CannabisMod.Rooms
    local own = CannabisMod.Plumbing.isPlumbedAt(r.x, r.y, r.z)
    local roomLine = not own and Rooms ~= nil and Rooms.lineFeeder(r) ~= nil
    if own or roomLine then
        if not r.everFilled then r.changedAt = Registry.nowHours() end
        r.everFilled = true
        r.fillPending = true
        if roomLine then Rooms.waitOnLine(r) end
        say("The water line is topping up the reservoir")
        return
    end
    local poured, tainted = pourWater(player, room)
    if poured <= 0 then
        say("You have no water to pour")
        return
    end
    -- A brand-new reservoir's first fill is fresh water, so its age starts then (topping up a dried-out one isn't a change).
    if not r.everFilled then r.changedAt = Registry.nowHours() end
    r.everFilled = true
    -- Plain water thins the food already in a drip tank.
    if r.kind == "drip" and (r.strength or 0) > 0 then r.strength = r.strength * r.level / (r.level + poured) end
    r.level = r.level + poured
    if tainted then r.tainted = true end
    if r.level >= Hydro.capacity(r) - 0.05 then r.fillPending = nil end
    say(string.format("Topped up the reservoir: %.1f of %d L", r.level, Hydro.capacity(r))
        .. (tainted and " (tainted water)" or ""))
end

--- Mix a bottle of nutrients into the reservoir on this tile (the drip tank's menu uses this).
commands.hydroDose = function(player, args)
    local r = reservoirFor(player, args)
    local itemType = Config.NUTRIENT_ITEMS[args.nutrient]
    if not (r and itemType) then return end
    if r.level <= 0 then Net.notify(player, "The tank is empty: top it up first") return end
    local bottle = Seeds.findItem(player:getInventory(), function(item) return item:getFullType() == itemType end)
    if not bottle then Net.notify(player, "You have no " .. args.nutrient .. " nutrients") return end
    local container = bottle:getContainer()
    if container then
        container:Remove(bottle)
        sendRemoveItemFromContainer(container, bottle)
    end
    Hydro.dose(r, args.nutrient)
    Net.notify(player, "Mixed " .. args.nutrient .. " nutrients into the tank")
end

commands.hydroTopUp = function(player, args)
    local r = reservoirFor(player, args)
    if r then Hydro.topUp(player, r) end
end

--- Drain and refill `r` for the player. `say` receives each message (the menu shows it as a floating note; the panel gathers them).
function Hydro.change(player, r, say)
    say = say or function(text) Net.notify(player, text) end
    local cap = Hydro.capacity(r)
    -- A reservoir on a Dazed Plumbing line is dumped here and refilled by the line over the next minutes.
    local own = CannabisMod.Plumbing.isPlumbedAt(r.x, r.y, r.z)
    -- Without its own line, another reservoir's line in the same grow room refills it.
    local Rooms = CannabisMod.Rooms
    local roomLine = not own and Rooms ~= nil and Rooms.lineFeeder(r) ~= nil
    local plumbed = own or roomLine
    local poured, tainted = 0, false
    if not plumbed then
        poured, tainted = pourWater(player, cap)
        if poured <= 0 then
            say("You need water to refill it")
            return
        end
    end
    r.level, r.strength, r.nutrient = poured, 0, nil
    r.tainted = tainted
    r.changedAt = Registry.nowHours()
    r.everFilled = true
    r.fillPending = plumbed or nil
    if roomLine then Rooms.waitOnLine(r) end
    -- With every rotted plant pulled, fresh water leaves the system clean.
    local cleaned = r.rot > 0 and not Hydro.hasLivingPlants(r)
    if cleaned then r.rot, r.recovering, r.rotTrend = 0, nil, -1 end
    local text = (roomLine and "Drained the reservoir: the room's water line is refilling it. Add nutrients once it's full.")
        or plumbed and "Drained the reservoir: the water line is refilling it. Add nutrients once it's full."
        or string.format("Drained and refilled the reservoir: %.1f of %d L. Add nutrients.", poured, cap)
    say(text .. (cleaned and " The system is clean of rot." or ""))
end

commands.hydroChange = function(player, args)
    local r = reservoirFor(player, args)
    if r then Hydro.change(player, r) end
end

--- Treat with bleach `r` for the player. `say` receives each message (the menu shows it as a floating note; the panel gathers them).
function Hydro.bleach(player, r, say)
    say = say or function(text) Net.notify(player, text) end
    if r.rot <= 0 then
        say("The roots are healthy")
        return
    end
    if r.rot >= H.ROT_EARLY then
        say("The rot has gone too far for bleach to save it")
        return
    end
    if Registry.nowHours() - (r.changedAt or 0) > H.TREAT_WITHIN_HOURS then
        say("Change the reservoir first, then treat it")
        return
    end
    local bottle = nil
    for _, item in ipairs(Seeds.findAll(player:getInventory(), function(item)
        local ok, yes = pcall(function()
            local fc = item:getFluidContainer()
            return fc and fc:getPrimaryFluid() and fc:getPrimaryFluid():getFluidTypeString() == "Bleach"
                and fc:getAmount() >= H.BLEACH_L
        end)
        return ok and yes
    end)) do bottle = item break end
    if not bottle then
        say("You need bleach")
        return
    end
    bottle:getFluidContainer():removeFluid(H.BLEACH_L)
    pcall(function() sendItemStats(bottle) end)
    r.recovering = true
    r.tainted = false
    say("Treated the reservoir with bleach: the roots will recover over the next few hours")
end

commands.hydroBleach = function(player, args)
    local r = reservoirFor(player, args)
    if r then Hydro.bleach(player, r) end
end

--- The living plants that drink from this reservoir.
function Hydro.servedPlants(r)
    if r and r.kind == "drip" then return CannabisMod.Drip and CannabisMod.Drip.plantsOf(r) or {} end
    -- Only plants close enough to share this reservoir are looked up (a DWC bucket is its own tile).
    local reach = (r.kind == "rdwc" and H.RDWC_RANGE) or (r.kind == "ebb" and H.EBB_SCAN_MAX) or 0
    local out = {}
    local function consider(plant)
        if plant and not plant.dead and plant.z == r.z and math.abs(plant.x - r.x) <= reach and math.abs(plant.y - r.y) <= reach
                and Config.isHydro(Registry.getBag(plant.x, plant.y, plant.z))
                and Hydro.reservoirOf(plant.x, plant.y, plant.z) == r then
            out[#out + 1] = plant
        end
    end
    if r.kind == "ebb" then
        -- A flood network can reach far, so every plant is checked against its distance.
        for _, plant in Registry.each() do consider(plant) end
        return out
    end
    -- DWC and RDWC reach only a few tiles: look those tiles up instead of walking every plant.
    for dx = -reach, reach do
        for dy = -reach, reach do consider(Registry.getPlant(r.x + dx, r.y + dy, r.z)) end
    end
    return out
end

--- True if any living plant drinks from this reservoir.
local function hasLivingPlants(r)
    return #Hydro.servedPlants(r) > 0
end
Hydro.hasLivingPlants = hasLivingPlants

--- Pull a hydro plant whose roots have rotted past saving, leaving the bucket ready for a clean start.
commands.pullHydroPlant = function(player, args)
    local luaObject, site, r, found = hydroTarget(player, args)
    if not (found and luaObject) then return end
    local plant = Registry.getPlant(luaObject.x, luaObject.y, luaObject.z)
    if not plant or luaObject.state == "plow" then
        Net.notify(player, "There's no plant to pull")
        return
    end
    if not plant.dead and (plant.rootRot or 0) < H.ROT_EARLY then
        Net.notify(player, "Its roots can still be saved: change the reservoir and treat it with bleach")
        return
    end
    CannabisMod.GrowBags.reset(luaObject)
    Net.notify(player, "Pulled the rotted plant. Change the reservoir before planting again.")
end

commands.hydroCheck = function(player, args)
    local r = reservoirFor(player, args)
    if not r then return end
    -- Reading the reservoir changes nothing: its plants move it on every 10 minutes.
    local roomFed = CannabisMod.Rooms and CannabisMod.Rooms.isWaitingOnLine(r)
    if r.fillPending and not roomFed and not CannabisMod.Plumbing.isPlumbedAt(r.x, r.y, r.z) then r.fillPending = nil end
    local parts = { string.format("%.1f of %d L", math.min(r.level, Hydro.capacity(r)), Hydro.capacity(r)) }
    if r.kind == "rdwc" then
        local n = Hydro.sitesOf(Config.tileKey(r.x, r.y, r.z))
        parts[#parts + 1] = n .. " of " .. H.RDWC_MAX_SITES .. " sites connected"
    elseif r.kind == "ebb" then
        parts[#parts + 1] = #Hydro.ebbSitesOf(Config.tileKey(r.x, r.y, r.z)) .. " of " .. H.EBB_MAX_SITES .. " table sites connected"
        parts[#parts + 1] = r.floodTimer and "flood timer fitted" or "no flood timer (flood by hand)"
    elseif r.kind == "drip" and CannabisMod.Drip then
        local pots = #CannabisMod.Drip.tilesOf(r)
        local inRoom = CannabisMod.Rooms and CannabisMod.Rooms.keyAt(r.x, r.y, r.z)
        parts[#parts + 1] = string.format("drips to %d pot%s %s", pots, pots == 1 and "" or "s",
            inRoom and "in its grow room" or ("within " .. tostring(Config.sandbox("DripRadius") or 5) .. " tiles"))
        if r.dripOn == false then parts[#parts + 1] = "drip off" end
    end
    if r.nutrient and r.strength > 0 then
        parts[#parts + 1] = string.format("%s nutrients at %d%%", r.nutrient, math.floor(r.strength * 100 + 0.5))
    else
        parts[#parts + 1] = "no nutrients"
    end
    local age = (Registry.nowHours() - (r.changedAt or 0)) / 24
    parts[#parts + 1] = string.format("%.0f days old", age) .. (Hydro.isStale(r, Registry.nowHours()) and " (stale)" or "")
    if r.tainted then parts[#parts + 1] = "tainted" end
    if r.fillPending then
        parts[#parts + 1] = roomFed and "refilling from the room's water line" or "refilling from the water line"
    elseif CannabisMod.Plumbing.isPlumbedAt(r.x, r.y, r.z) then
        parts[#parts + 1] = "on a water line"
    end
    if not Hydro.pumpState(r) then parts[#parts + 1] = r.kind == "ebb" and "flood pump off" or "pumps off" end
    if r.rot >= H.ROT_EARLY then
        parts[#parts + 1] = "the roots are brown and rotting"
    elseif r.rot > 0 then
        parts[#parts + 1] = "the roots look a little brown"
    end
    Net.notify(player, (r.kind == "drip" and "Drip tank: " or "Reservoir: ") .. table.concat(parts, ", "))
end

-- --------------------------------------------------------------------------
-- Hooks used by the grow bag and sowing code
-- --------------------------------------------------------------------------

--- After a harvest or a cleared plant: a rockwool cube is spent, clay pebbles stay for the next plant.
function Hydro.onReset(x, y, z)
    local kind = Registry.getBag(x, y, z)
    if not Config.isHydro(kind) or not res then return end
    local r = res[Config.tileKey(x, y, z)]
    if r and r.medium == "rockwool" then
        r.medium = nil
        Registry.setBagSoiled(x, y, z, false)
    end
    -- A DWC bucket's own reservoir starts clean for the next plant; an RDWC site shares its control's water.
    if r and Config.hydroOf(kind) == "dwc" then r.rot = 0 end
    -- With no roots left in the water, its clock stops until the next plant goes in.
    local shared = Hydro.reservoirOf(x, y, z)
    if shared and not Hydro.hasLivingPlants(shared) then shared.lastTick = nil end
end

--- Picking up an empty bucket hands back its clay pebbles (or an unused rockwool cube) and forgets the reservoir.
function Hydro.onPickUp(player, x, y, z)
    local r = res and res[Config.tileKey(x, y, z)]
    if r and r.medium and H.MEDIUM_ITEMS[r.medium] then
        Farming.giveItems(player, H.MEDIUM_ITEMS[r.medium], 1)
    end
    Hydro.clear(x, y, z)
end

--- Whether a seed sown into this plot fails: clay pebbles let some seeds slip down and dry out.
function Hydro.seedFails(x, y, z)
    local r = res and res[Config.tileKey(x, y, z)]
    return r ~= nil and r.medium == "pebbles" and Config.rollPercent(H.PEBBLE_SEED_FAIL)
end

--- Flood the tables by hand (from the reservoir or any table it feeds).
commands.floodTables = function(player, args)
    local r = reservoirFor(player, args)
    if not r then return end
    if r.kind ~= "ebb" then return end
    local now = Registry.nowHours()
    -- Work the rows out fresh, so a table placed a moment ago is flooded too.
    Hydro.forgetLinks()
    for _, d in ipairs(NEIGHBOURS) do
        if Registry.getBag(r.x + d[1], r.y + d[2], r.z) == "ebb" then Hydro.linkEbb(r.x + d[1], r.y + d[2], r.z) break end
    end
    local result = Hydro.flood(r, now)
    local n = #Hydro.ebbSitesOf(Config.tileKey(r.x, r.y, r.z))
    if result == "flooded" and CannabisMod.Rooms then
        CannabisMod.Rooms.logTile(Config.tileKey(r.x, r.y, r.z), "Flooded " .. n .. " table site" .. (n == 1 and "" or "s") .. " by hand", now)
    end
    local text = {
        flooded = "Flooded " .. n .. " table site" .. (n == 1 and "" or "s") .. ": the rockwool will stay wet for about " .. H.EBB_WET_HOURS .. " hours",
        noPower = "The flood pump has no power",
        noWater = "Not enough water in the reservoir to flood the tables",
        noTables = "No flood tables touch this reservoir",
    }
    Net.notify(player, text[result])
end

--- Copy whether a flood timer is fitted onto the reservoir object, for the client's menu.
local function markFloodObject(x, y, z, fitted)
    pcall(function()
        local objects = getCell():getGridSquare(x, y, z):getObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj:getSprite():getName() == H.FLOOD_SPRITE then
                obj:getModData().DDFloodTimer = fitted or nil
                obj:transmitModData()
            end
        end
    end)
end

--- A flood reservoir placed back on a tile that still has its record: show its fitted timer again.
function Hydro.syncFloodObject(x, y, z)
    local r = res and res[Config.tileKey(x, y, z)]
    markFloodObject(x, y, z, r ~= nil and r.floodTimer == true)
end

--- A client placed a flood reservoir (multiplayer fallback for the object event): relink the tables and show its timer.
commands.floodPlaced = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return end
    Hydro.forgetLinks()
    Hydro.syncFloodObject(x, y, z)
end

--- Fit a flood timer to a flood reservoir: it then keeps the tables flooded while powered.
commands.installFloodTimer = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return end
    local r = Hydro.reservoirAt(x, y, z, "ebb")
    if not r then return end
    if r.floodTimer then
        Net.notify(player, "This reservoir already has a flood timer")
        return
    end
    local item = player:getInventory():getFirstTypeRecurse(H.FLOOD_TIMER_ITEM)
    if not item then
        Net.notify(player, "You need a flood timer")
        return
    end
    local container = item:getContainer()
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    r.floodTimer = true
    markFloodObject(x, y, z, true)
    Net.notify(player, "Flood timer fitted: the tables flood a few times a day while the pump has power and water")
end

commands.removeFloodTimer = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return end
    local r = Hydro.reservoirAt(x, y, z, "ebb")
    if not (r and r.floodTimer) then return end
    r.floodTimer = nil
    markFloodObject(x, y, z, false)
    Farming.giveItems(player, H.FLOOD_TIMER_ITEM, 1)
    Net.notify(player, "Flood timer removed: flood the tables by hand")
end

--- Drop records of RDWC control buckets and flood reservoirs that were picked up, handing a fitted flood timer to the floor.
function Hydro.cleanup()
    if not res then return end
    local gone = {}
    for key, r in pairs(res) do
        if r.isFlood or r.isControl or r.isDrip then
            local present
            if r.isFlood then present = Hydro.hasFlood(r.x, r.y, r.z)
            elseif r.isDrip then present = Hydro.hasDrip(r.x, r.y, r.z)
            else present = Hydro.hasControl(r.x, r.y, r.z) end
            if present == false then
                gone[#gone + 1] = key
                if r.floodTimer then
                    pcall(function()
                        getCell():getGridSquare(r.x, r.y, r.z):AddWorldInventoryItem(H.FLOOD_TIMER_ITEM, 0.5, 0.5, 0)
                    end)
                end
            end
        end
    end
    for _, key in ipairs(gone) do dropRecord(key) end
    if #gone > 0 then Hydro.forgetLinks() end
end
Events.EveryTenMinutes.Add(Hydro.cleanup)

--- A kit for testing hydro: DWC buckets, an RDWC control with two sites, rockwool, clay pebbles, nutrients and bleach.
commands.debugHydroKit = function(player, args)
    if not (isDebugEnabled() or (player.getAccessLevel and player:getAccessLevel() ~= "None")) then return end
    Farming.giveItems(player, "CannabisMod.DWCBucket", 2)
    Farming.giveItems(player, Config.GrowBag.xldwc.furnItem, 1)
    Farming.giveItems(player, H.CONTROL_ITEM, 1)
    Farming.giveItems(player, "CannabisMod.RDWCSite", 2)
    Farming.giveItems(player, H.MEDIUM_ITEMS.rockwool, 5)
    Farming.giveItems(player, H.MEDIUM_ITEMS.pebbles, 1)
    Farming.giveItems(player, Config.NUTRIENT_ITEMS.Veg, 2)
    Farming.giveItems(player, Config.NUTRIENT_ITEMS.Bloom, 2)
    Farming.giveItems(player, "Base.Bleach", 1)
    Farming.giveItems(player, "CannabisMod.FloodTable", 2)
    Farming.giveItems(player, H.FLOOD_ITEM, 1)
    Farming.giveItems(player, H.FLOOD_TIMER_ITEM, 1)
    Net.notify(player, "Gave 2 DWC buckets, an XL DWC bucket, an RDWC control and 2 sites, 2 flood tables, a flood reservoir and timer, "
        .. "5 rockwool cubes, clay pebbles, nutrients and bleach. Bring your own water.")
end

Hydro.DEBUG_FILL_RANGE = 20   -- tiles around the player the debug fill reaches, on any floor
Hydro.DEBUG_POT_WATER = 80    -- a soil pot's water after the debug fill: well watered, under the overwatering line

--- Fill `r` to capacity; one that was empty gets fresh, clean water and its age restarts.
local function debugFill(r, now)
    if not r.everFilled or (r.level or 0) <= 0.05 then
        r.changedAt = now
        r.tainted = false
    end
    r.everFilled = true
    r.level = Hydro.capacity(r)
    r.fillPending = nil
end

--- Debug: fill every hydro reservoir and drip tank and water every soil pot or cannabis plot near (x, y). Returns reservoirs, pots.
function Hydro.debugFillNear(x, y, range)
    local now = Registry.nowHours()
    local done, reservoirs, pots = {}, 0, 0
    local function near(tx, ty) return math.abs(tx - x) <= range and math.abs(ty - y) <= range end
    local function fill(r)
        if r and not done[r] then done[r] = true; debugFill(r, now); reservoirs = reservoirs + 1 end
    end
    local function water(tx, ty, tz)
        local key = Config.tileKey(tx, ty, tz)
        if done[key] then return end
        done[key] = true
        local luaObject = Farming.getVanilla(tx, ty, tz)
        if not luaObject then return end
        luaObject.waterLvl = Hydro.DEBUG_POT_WATER
        pcall(function() luaObject:saveData() end)
        local plant = Registry.getPlant(tx, ty, tz)
        if plant then plant.water = Hydro.DEBUG_POT_WATER end
        pots = pots + 1
    end
    for key, kind in Registry.eachBag() do
        local tx, ty, tz = Config.parseKey(key)
        if tx and near(tx, ty) then
            if Config.isHydro(kind) then fill(Hydro.reservoirOf(tx, ty, tz)) else water(tx, ty, tz) end
        end
    end
    -- RDWC control buckets and flood reservoirs with no site linked yet, and drip tanks, have no bag of their own.
    for _, r in pairs(res or {}) do
        if (r.isControl or r.isFlood or r.isDrip) and r.x and near(r.x, r.y) then fill(r) end
    end
    -- Cannabis planted straight in the ground has no bag.
    for _, plant in Registry.each() do
        if plant.x and near(plant.x, plant.y) and not Config.isHydro(Registry.getBag(plant.x, plant.y, plant.z)) then
            water(plant.x, plant.y, plant.z)
        end
    end
    return reservoirs, pots
end

commands.debugFillWater = function(player, args)
    if not (isDebugEnabled() or (player.getAccessLevel and player:getAccessLevel() ~= "None")) then return end
    local x, y = math.floor(player:getX()), math.floor(player:getY())
    local reservoirs, pots = Hydro.debugFillNear(x, y, Hydro.DEBUG_FILL_RANGE)
    Net.notify(player, string.format("Filled %d reservoir(s) and watered %d pot(s) within %d tiles", reservoirs, pots,
        Hydro.DEBUG_FILL_RANGE))
end
