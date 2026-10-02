-- Hydroponic reservoirs: plants drink from a reservoir instead of the plot, nutrients are mixed into it and run down,
-- old or tainted water and air pumps without power cause root rot, and bleach cures it if caught early.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"

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

-- res[tileKey] = { kind, level, strength, nutrient, changedAt, tainted, rot, medium, lastTick }
local res = nil

Events.OnInitGlobalModData.Add(function()
    res = ModData.getOrCreate(Config.MODDATA_KEY .. "_Hydro")
end)

--- Replace the saved table (tests use this to start clean).
function Hydro._reset(tbl) res = tbl or {} end

--- Litres a hydro system of this kind holds.
function Hydro.capacity(kind)
    return H.RESERVOIR_L[kind] or 15
end

--- The reservoir record for a hydro plot, made on first use (empty, fresh).
function Hydro.get(x, y, z, kind)
    if not res then return nil end
    local key = Config.tileKey(x, y, z)
    local r = res[key]
    if not r then
        r = { level = 0, strength = 0, changedAt = Registry.nowHours(), tainted = false, rot = 0 }
        res[key] = r
    end
    r.kind = kind or r.kind
    return r
end

--- Forget a reservoir (its bucket was picked up).
function Hydro.clear(x, y, z)
    if res then res[Config.tileKey(x, y, z)] = nil end
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

--- Every 10 minutes for each living hydro plant: drink, use up nutrients, and build root rot.
function Hydro.update(plant, now)
    local def = Config.GrowBag[plant.bag]
    local r = def and Hydro.get(plant.x, plant.y, plant.z, def.hydro)
    if not r then return end
    local hours = Config.clamp(now - (r.lastTick or now), 0, 24)
    r.lastTick = now
    local rate = Config.sandbox("ReservoirUseRate") or 1

    -- The plant drinks, more when big from extra veg.
    local drink = (H.DRINK_PER_HOUR[plant.stage] or 0.3) * hours * rate * (1 + Config.Timer.vegBonus(plant.extraVegHours))
    r.level = math.max(0, r.level - drink)
    if r.strength > 0 then r.strength = math.max(0, r.strength - hours * rate / H.NUTRIENT_HOURS) end
    setPlotWater(plant, r.level > 0 and H.PLOT_WATER or H.DRY_PLOT_WATER)
    plant.warnings.reservoirDry = (r.level <= 0) or nil

    -- A growing plant in a weak reservoir starves.
    local feeding = plant.stage >= Config.STAGE.Vegetative and plant.stage < Config.STAGE.Ripe
    if feeding and r.strength < H.HUNGRY_BELOW then
        Registry.applyPenalty(plant, H.HUNGRY_PER_HOUR * hours, "hungry")
    else
        plant.warnings.hungry = nil
    end

    -- Root rot: no air, old water or tainted water start it, and once started it keeps spreading.
    local stale = Hydro.isStale(r, now)
    local pumps = Hydro.pumpsOn(plant.x, plant.y, plant.z)
    plant.warnings.staleReservoir = stale or nil
    plant.warnings.pumpOff = (not pumps) or nil
    local risk = 0
    if not pumps then risk = risk + H.ROT_NO_AIR end
    if stale then risk = risk + H.ROT_STALE end
    if r.tainted then risk = risk + H.ROT_TAINTED end
    if r.rot > 0 then risk = risk + H.ROT_SPREAD end
    r.rot = math.min(H.ROT_DEAD, r.rot + risk * hours * (Config.sandbox("RootRotRisk") or 1))
    plant.rootRot = r.rot
    plant.hydro = { level = r.level, cap = Hydro.capacity(r.kind), strength = r.strength, nutrient = r.nutrient, stale = stale }
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
    local def = Config.GrowBag[plant.bag]
    local r = Hydro.get(plant.x, plant.y, plant.z, def and def.hydro)
    if r.level <= 0 then return "noWater" end
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

--- The hydro plot a player is acting on, its kind and reservoir, after checking they're close enough.
local function hydroPlot(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or not SC.isNear(player, x, y, z) then return nil end
    local kind = Registry.getBag(x, y, z)
    if not Config.isHydro(kind) then return nil end
    local luaObject = Farming.getVanilla(x, y, z)
    if not luaObject then return nil end
    return luaObject, kind, Hydro.get(x, y, z, Config.GrowBag[kind].hydro)
end

commands.hydroAddMedium = function(player, args)
    local luaObject, kind, r = hydroPlot(player, args)
    local itemType = H.MEDIUM_ITEMS[args.medium]
    if not (luaObject and itemType) then return end
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
    local luaObject, kind, r = hydroPlot(player, args)
    if not luaObject then return end
    local room = Hydro.capacity(r.kind) - r.level
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
    Net.notify(player, string.format("Topped up the reservoir: %.1f of %d L", r.level, Hydro.capacity(r.kind))
        .. (tainted and " (tainted water)" or ""))
end

commands.hydroChange = function(player, args)
    local luaObject, kind, r = hydroPlot(player, args)
    if not luaObject then return end
    local cap = Hydro.capacity(r.kind)
    local poured, tainted = pourWater(player, cap)
    if poured <= 0 then
        Net.notify(player, "You need water to refill it")
        return
    end
    r.level, r.strength, r.nutrient = poured, 0, nil
    r.tainted = tainted
    r.changedAt = Registry.nowHours()
    Net.notify(player, string.format("Drained and refilled the reservoir: %.1f of %d L. Add nutrients.", poured, cap))
end

commands.hydroBleach = function(player, args)
    local luaObject, kind, r = hydroPlot(player, args)
    if not luaObject then return end
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
    r.rot = 0
    r.tainted = false
    Net.notify(player, "Treated the reservoir with bleach: the roots will recover")
end

commands.hydroCheck = function(player, args)
    local luaObject, kind, r = hydroPlot(player, args)
    if not luaObject then return end
    local parts = { string.format("%.1f of %d L", r.level, Hydro.capacity(r.kind)) }
    if r.nutrient and r.strength > 0 then
        parts[#parts + 1] = string.format("%s nutrients at %d%%", r.nutrient, math.floor(r.strength * 100 + 0.5))
    else
        parts[#parts + 1] = "no nutrients"
    end
    local age = (Registry.nowHours() - (r.changedAt or 0)) / 24
    parts[#parts + 1] = string.format("%.0f days old", age) .. (Hydro.isStale(r, Registry.nowHours()) and " (stale)" or "")
    if r.tainted then parts[#parts + 1] = "tainted" end
    if not Hydro.pumpsOn(luaObject.x, luaObject.y, luaObject.z) then parts[#parts + 1] = "pumps off" end
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
    if r then r.rot = 0 end
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

--- A kit for testing hydro: two DWC buckets, rockwool, clay pebbles, nutrients and bleach.
commands.debugHydroKit = function(player, args)
    if not (isDebugEnabled() or (player.getAccessLevel and player:getAccessLevel() ~= "None")) then return end
    Farming.giveItems(player, "CannabisMod.DWCBucket", 2)
    Farming.giveItems(player, H.MEDIUM_ITEMS.rockwool, 2)
    Farming.giveItems(player, H.MEDIUM_ITEMS.pebbles, 1)
    Farming.giveItems(player, Config.NUTRIENT_ITEMS.Veg, 2)
    Farming.giveItems(player, Config.NUTRIENT_ITEMS.Bloom, 2)
    Farming.giveItems(player, "Base.Bleach", 1)
    Net.notify(player, "Gave 2 DWC buckets, 2 rockwool cubes, clay pebbles, nutrients and bleach. Bring your own water.")
end
