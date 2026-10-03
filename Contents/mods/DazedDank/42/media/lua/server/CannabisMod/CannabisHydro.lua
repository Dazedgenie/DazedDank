-- Hydroponic reservoirs: plants drink from a reservoir instead of the plot, nutrients are mixed into it and run down,
-- old or tainted water and air pumps without power cause root rot, and bleach cures it if caught early.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"
require "CannabisMod/CannabisPlumbing"

local Config   = CannabisMod.Config
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

Events.OnInitGlobalModData.Add(function()
    res = ModData.getOrCreate(Config.MODDATA_KEY .. "_Hydro")
end)

--- Replace the saved table (tests use this to start clean).
function Hydro._reset(tbl) res = tbl or {} end

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

--- Forget a tile's record (its bucket was picked up).
function Hydro.clear(x, y, z)
    if res then res[Config.tileKey(x, y, z)] = nil end
end

--- How many site buckets are linked to the control bucket with this tile key.
function Hydro.sitesOf(controlKey)
    local n = 0
    for _, r in pairs(res or {}) do
        if r.link == controlKey then n = n + 1 end
    end
    return n
end

--- Litres a reservoir holds: fixed for DWC, the control bucket plus every linked site for RDWC.
function Hydro.capacity(r)
    if r and r.kind == "rdwc" then
        return H.RDWC_CONTROL_L + H.RDWC_SITE_L * Hydro.sitesOf(Config.tileKey(r.x, r.y, r.z))
    end
    return H.RESERVOIR_L.dwc
end

--- True if an RDWC control bucket stands on this square (nil when the square isn't loaded).
function Hydro.hasControl(x, y, z)
    local square = getCell():getGridSquare(x, y, z)
    if not square then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local ok, name = pcall(function() return objects:get(i):getSprite():getName() end)
        if ok and name == H.CONTROL_SPRITE then return true end
    end
    return false
end

--- The control bucket's reservoir record for an RDWC site, linking the site to the nearest control with room if needed.
function Hydro.linkSite(x, y, z)
    local site = Hydro.get(x, y, z, "rdwc")
    if site.link then
        local cx, cy, cz = site.link:match("^(-?%d+)_(-?%d+)_(-?%d+)$")
        if cx and Hydro.hasControl(tonumber(cx), tonumber(cy), tonumber(cz)) ~= false then
            return Hydro.get(tonumber(cx), tonumber(cy), tonumber(cz), "rdwc")
        end
        site.link = nil
    end
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
    if not best then return nil end
    site.link = Config.tileKey(best[1], best[2], z)
    return Hydro.get(best[1], best[2], z, "rdwc")
end

--- The reservoir a hydro plot drinks from: its own for DWC, the linked control bucket's for RDWC (nil if none in range).
function Hydro.reservoirOf(x, y, z)
    local kind = Registry.getBag(x, y, z)
    local def = kind and Config.GrowBag[kind]
    if not (def and def.hydro) then return nil end
    if def.hydro == "rdwc" then return Hydro.linkSite(x, y, z) end
    return Hydro.get(x, y, z, def.hydro)
end

--- The reservoir a water line feeds: a DWC bucket's own, or an RDWC control bucket's. Nil if that kind isn't on the tile.
function Hydro.reservoirAt(x, y, z, kind)
    if kind == "rdwc" then
        return Hydro.hasControl(x, y, z) and Hydro.get(x, y, z, "rdwc") or nil
    end
    if kind == "dwc" and Registry.getBag(x, y, z) == "dwc" then return Hydro.get(x, y, z, "dwc") end
    return nil
end

--- True if the air and water pumps at this square are running.
function Hydro.pumpsOn(x, y, z)
    if not Config.sandbox("PumpsNeedPower") then return true end
    local ok, on = pcall(function()
        local square = getCell():getGridSquare(x, y, z)
        if not square then return false end
        if square:haveElectricity() then return true end
        return (not square:isOutside()) and getWorld():isHydroPowerOn() or false
    end)
    return ok and on == true
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
    if not Hydro.pumpsOn(r.x, r.y, r.z) then risk = risk + H.ROT_NO_AIR end
    if Hydro.isStale(r, now) then risk = risk + H.ROT_STALE end
    if r.tainted then risk = risk + H.ROT_TAINTED end
    -- Rot feeds on itself, unless bleach-treated roots are recovering.
    if r.rot > 0 and not r.recovering then risk = risk + H.ROT_SPREAD end
    local before = r.rot
    local change = risk * hours * (Config.sandbox("RootRotRisk") or 1)
    if r.recovering then change = change - H.ROT_RECOVER_PER_HOUR * hours end
    r.rot = Config.clamp(r.rot + change, 0, H.ROT_DEAD)
    if r.rot <= 0 then r.recovering = nil end
    -- Which way the rot moved this tick: 1 rising, -1 falling, 0 steady.
    r.rotTrend = (r.rot > before + 0.001 and 1) or (r.rot < before - 0.001 and -1) or 0
end
Hydro.advanceReservoir = advanceReservoir

--- Every 10 minutes for each living hydro plant: drink from its reservoir, and suffer hunger or root rot from it.
function Hydro.update(plant, now)
    local r = Hydro.reservoirOf(plant.x, plant.y, plant.z)
    local fresh = plant.hydroTick == nil
    local hours = Config.clamp(now - (plant.hydroTick or now), 0, 24)
    plant.hydroTick = now
    if not r then
        -- An RDWC site with no control bucket in range has no water at all.
        setPlotWater(plant, H.DRY_PLOT_WATER)
        plant.warnings.noControl = true
        plant.hydro = { level = 0, cap = 0, strength = 0, unlinked = true }
        return
    end
    plant.warnings.noControl = nil
    -- Fresh roots in a reservoir nothing has drunk from lately: the idle time grew no rot, so its clock starts now.
    if fresh then
        if r.lastTick and now - r.lastTick > H.IDLE_HOURS then r.lastTick = now end
    end
    advanceReservoir(r, now)
    local rate = Config.sandbox("ReservoirUseRate") or 1

    -- The plant drinks, more when big from extra veg.
    local drink = (H.DRINK_PER_HOUR[plant.stage] or 0.3) * hours * rate * (1 + Config.Timer.vegBonus(plant.extraVegHours))
    r.level = math.max(0, math.min(r.level, Hydro.capacity(r)) - drink)
    setPlotWater(plant, r.level > 0 and H.PLOT_WATER or H.DRY_PLOT_WATER)
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
    plant.warnings.pumpOff = (not Hydro.pumpsOn(r.x, r.y, r.z)) or nil
    plant.rootRot = r.rot
    plant.rootRotTrend = r.rotTrend or 0
    plant.hydro = { level = r.level, cap = Hydro.capacity(r), strength = r.strength, nutrient = r.nutrient, stale = stale,
                    sites = r.kind == "rdwc" and Hydro.sitesOf(Config.tileKey(r.x, r.y, r.z)) or nil }
    -- Rot in a shared reservoir reaches every site's roots.
    if r.rot >= H.ROT_EARLY then
        Registry.applyPenalty(plant, H.ROT_CARE_PER_HOUR * hours, "rootRot")
        if plant.nextStageAt then plant.nextStageAt = plant.nextStageAt + hours * 0.5 end
    else
        plant.warnings.rootRot = nil
    end
    if r.rot >= H.ROT_DEAD then Farming.killPlant(plant) end
end

--- Mix a nutrient into the plant's reservoir; dosing a reservoir that is still strong burns the plant.
function Hydro.feed(plant, nutrient)
    local r = Hydro.reservoirOf(plant.x, plant.y, plant.z)
    if not r or r.level <= 0 then return "noWater" end
    local burn = r.strength > H.BURN_ABOVE
    r.strength, r.nutrient = 1, nutrient
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
    if Hydro.hasControl(x, y, z) then return nil, nil, Hydro.get(x, y, z, "rdwc"), true end
    return nil
end

--- The reservoir to act on, or nil after telling the player why there isn't one.
local function reservoirFor(player, args)
    local luaObject, site, r, found = hydroTarget(player, args)
    if not found then return nil end
    if not r then
        Net.notify(player, "This site isn't connected: put an RDWC control bucket within " .. H.RDWC_RANGE .. " tiles")
        return nil
    end
    return r
end

commands.hydroAddMedium = function(player, args)
    local luaObject, r = hydroTarget(player, args)
    local itemType = H.MEDIUM_ITEMS[args.medium]
    if not (luaObject and r and itemType) then return end
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

commands.hydroTopUp = function(player, args)
    local r = reservoirFor(player, args)
    if not r then return end
    local room = Hydro.capacity(r) - r.level
    if room <= 0.05 then
        Net.notify(player, "The reservoir is full")
        return
    end
    local poured, tainted = pourWater(player, room)
    if poured <= 0 then
        Net.notify(player, "You have no water to pour")
        return
    end
    r.level = r.level + poured
    if tainted then r.tainted = true end
    Net.notify(player, string.format("Topped up the reservoir: %.1f of %d L", r.level, Hydro.capacity(r))
        .. (tainted and " (tainted water)" or ""))
end

commands.hydroChange = function(player, args)
    local r = reservoirFor(player, args)
    if not r then return end
    local cap = Hydro.capacity(r)
    -- A reservoir on a Dazed Plumbing line is dumped here and refilled by the line over the next minutes.
    local plumbed = CannabisMod.Plumbing.isPlumbedAt(r.x, r.y, r.z)
    local poured, tainted = 0, false
    if not plumbed then
        poured, tainted = pourWater(player, cap)
        if poured <= 0 then
            Net.notify(player, "You need water to refill it")
            return
        end
    end
    r.level, r.strength, r.nutrient = poured, 0, nil
    r.tainted = tainted
    r.changedAt = Registry.nowHours()
    r.fillPending = plumbed or nil
    -- With every rotted plant pulled, fresh water leaves the system clean.
    local cleaned = r.rot > 0 and not Hydro.hasLivingPlants(r)
    if cleaned then r.rot, r.recovering, r.rotTrend = 0, nil, -1 end
    local text = plumbed and "Drained the reservoir: the water line is refilling it. Add nutrients once it's full."
        or string.format("Drained and refilled the reservoir: %.1f of %d L. Add nutrients.", poured, cap)
    Net.notify(player, text .. (cleaned and " The system is clean of rot." or ""))
end

commands.hydroBleach = function(player, args)
    local r = reservoirFor(player, args)
    if not r then return end
    if r.rot <= 0 then
        Net.notify(player, "The roots are healthy")
        return
    end
    if r.rot >= H.ROT_EARLY then
        Net.notify(player, "The rot has gone too far for bleach to save it")
        return
    end
    if Registry.nowHours() - (r.changedAt or 0) > H.TREAT_WITHIN_HOURS then
        Net.notify(player, "Change the reservoir first, then treat it")
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
        Net.notify(player, "You need bleach")
        return
    end
    bottle:getFluidContainer():removeFluid(H.BLEACH_L)
    pcall(function() sendItemStats(bottle) end)
    r.recovering = true
    r.tainted = false
    Net.notify(player, "Treated the reservoir with bleach: the roots will recover over the next few hours")
end

--- True if any living plant drinks from this reservoir.
local function hasLivingPlants(r)
    for _, plant in Registry.each() do
        if not plant.dead and Hydro.reservoirOf(plant.x, plant.y, plant.z) == r then return true end
    end
    return false
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
    -- Only a reservoir with roots in it moves on; an idle one is read as it stands.
    if Hydro.hasLivingPlants(r) then advanceReservoir(r, Registry.nowHours()) end
    local parts = { string.format("%.1f of %d L", math.min(r.level, Hydro.capacity(r)), Hydro.capacity(r)) }
    if r.kind == "rdwc" then
        local n = Hydro.sitesOf(Config.tileKey(r.x, r.y, r.z))
        parts[#parts + 1] = n .. " of " .. H.RDWC_MAX_SITES .. " sites connected"
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
        parts[#parts + 1] = "refilling from the water line"
    elseif CannabisMod.Plumbing.isPlumbedAt(r.x, r.y, r.z) then
        parts[#parts + 1] = "on a water line"
    end
    if not Hydro.pumpsOn(r.x, r.y, r.z) then parts[#parts + 1] = "pumps off" end
    if r.rot >= H.ROT_EARLY then
        parts[#parts + 1] = "the roots are brown and rotting"
    elseif r.rot > 0 then
        parts[#parts + 1] = "the roots look a little brown"
    end
    Net.notify(player, "Reservoir: " .. table.concat(parts, ", "))
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
    if r and kind == "dwc" then r.rot = 0 end
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

--- A kit for testing hydro: DWC buckets, an RDWC control with two sites, rockwool, clay pebbles, nutrients and bleach.
commands.debugHydroKit = function(player, args)
    if not (isDebugEnabled() or (player.getAccessLevel and player:getAccessLevel() ~= "None")) then return end
    Farming.giveItems(player, "CannabisMod.DWCBucket", 2)
    Farming.giveItems(player, H.CONTROL_ITEM, 1)
    Farming.giveItems(player, "CannabisMod.RDWCSite", 2)
    Farming.giveItems(player, H.MEDIUM_ITEMS.rockwool, 4)
    Farming.giveItems(player, H.MEDIUM_ITEMS.pebbles, 1)
    Farming.giveItems(player, Config.NUTRIENT_ITEMS.Veg, 2)
    Farming.giveItems(player, Config.NUTRIENT_ITEMS.Bloom, 2)
    Farming.giveItems(player, "Base.Bleach", 1)
    Net.notify(player, "Gave 2 DWC buckets, an RDWC control and 2 sites, 4 rockwool cubes, clay pebbles, nutrients and bleach. Bring your own water.")
end
