-- Vanilla crops in our containers (with the Dazed Dank: Garden Crops add-on). Vanilla grows them by its own rules;
-- on top of that, hydro containers water them from their reservoir and grow them 15% faster, a harvested or rotted
-- away plant leaves its container empty, and under vanilla's Kill Crops Grown Inside a lamp or grow room keeps them
-- alive indoors.

if isClient() then return end

require "Farming/SFarmingSystem"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisSchedule"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"

local Config   = CannabisMod.Config
local Registry = CannabisMod.Registry
local Farming  = CannabisMod.Farming
local H        = Config.Hydro
local CROP     = Config.CROP_TYPE

local VanillaCrops = {}
CannabisMod.VanillaCrops = VanillaCrops

VanillaCrops.HYDRO_SPEED = 0.85      -- a hydro crop waits this share of vanilla's time for each growth step
VanillaCrops.DRINK_PER_HOUR = 0.3    -- litres a vanilla crop takes from its reservoir each hour
local TICK_HOURS = 1 / 6

--- The vanilla crop in a container at a tile, as plot and container kind; nil when there is none.
function VanillaCrops.at(x, y, z)
    local bag = Registry.getBag(x, y, z)
    if not bag then return nil end
    local plot = Farming.getVanilla(x, y, z)
    if not plot or plot.state == "plow" or plot.typeOfSeed == CROP then return nil end
    return plot, bag
end

--- The water a hydro plot is held at while its roots reach water: vanilla's need for this stage, under its upper limit.
local function heldWater(plot)
    local want = math.max(H.PLOT_WATER, (plot.waterNeeded or 0) + 5)
    return math.min(want, plot.waterNeededMax or 100)
end

--- One 10-minute drink for a vanilla crop in hydro: watered while the reservoir has water (flood tables: while the
--- rockwool is wet), dry otherwise.
local function drink(plot, bag, now)
    local Hydro = CannabisMod.Hydro
    if not Hydro then return end
    local r, unknown = Hydro.reservoirOf(plot.x, plot.y, plot.z)
    -- A reservoir out of range: leave the plot as it was until it loads.
    if unknown then return end
    local wet = r ~= nil and r.level > 0
    if wet and bag == "ebb" then
        local site = Hydro.get(plot.x, plot.y, plot.z, "ebb")
        if Hydro.hasFloodTimer(r) and not Hydro.floodBlocker(r) then site.wetUntil = now + H.EBB_WET_HOURS end
        wet = (site.wetUntil or 0) > now
    end
    if wet then
        local rate = Config.sandbox("ReservoirUseRate") or 1
        r.level = math.max(0, math.min(r.level, Hydro.capacity(r)) - VanillaCrops.DRINK_PER_HOUR * TICK_HOURS * rate)
    end
    local water = wet and heldWater(plot) or H.DRY_PLOT_WATER
    if plot.waterLvl ~= water then
        plot.waterLvl = water
        pcall(plot.saveData, plot)
    end
end

--- Every 10 minutes: hydro crops drink, and containers whose plant was harvested or rotted away are emptied.
function VanillaCrops.tick()
    local GrowBags = CannabisMod.GrowBags
    local now = Registry.nowHours()
    local spent = {}
    for key in Registry.eachBag() do
        local x, y, z = Config.parseKey(key)
        local plot, bag = nil, nil
        if x then plot, bag = VanillaCrops.at(x, y, z) end
        if plot then
            if plot.state == "harvested" or plot.state == "destroyed" then
                spent[#spent + 1] = plot
            elseif Config.isHydro(bag) and plot:isAlive() then
                local ok, err = pcall(drink, plot, bag, now)
                if not ok then print("[DazedDank] vanilla crop drink failed at " .. key .. ": " .. tostring(err)) end
            end
        end
    end
    if GrowBags then
        for _, plot in ipairs(spent) do GrowBags.reset(plot) end
    end
end
CannabisMod.TenMinutes.set("vanillaCrops", VanillaCrops.tick)

-- Each growth step in hydro waits 15% less than vanilla's time.
local originalGrow = farming_vegetableconf.grow
farming_vegetableconf.grow = function(planting, nextGrowing, updateNbOfGrow)
    local result = originalGrow(planting, nextGrowing, updateNbOfGrow)
    local p = result or planting
    if p and p.typeOfSeed ~= CROP and p.state == "seeded" and Config.isHydro(Registry.getBag(p.x, p.y, p.z)) then
        local sys = SFarmingSystem.instance
        local now = sys and sys.hoursElapsed
        if now and p.nextGrowing and p.nextGrowing > now then
            p.nextGrowing = now + math.max(1, math.floor((p.nextGrowing - now) * VanillaCrops.HYDRO_SPEED + 0.5))
        end
    end
    return result
end

--- True when vanilla's indoor penalty would land on this plot: indoors, not a houseplant, not in a greenhouse.
local function vanillaPenalisesIndoors(plot)
    if plot.exterior then return false end
    local prop = farming_vegetableconf.props[plot.typeOfSeed]
    if prop and prop.isHouseplant then return false end
    local square = plot:getSquare()
    local room = square and square:getRoom()
    local def = room and room:getRoomDef()
    return not (def and string.find(string.lower(def:getName()), "greenhouse", 1, true))
end

--- True when a powered grow lamp reaches the tile or it stands in a grow room.
function VanillaCrops.keptAliveIndoors(x, y, z)
    local Rooms = CannabisMod.Rooms
    if Rooms and Rooms.keyAt(x, y, z) then return true end
    local Light = CannabisMod.Light
    local cap = Light and Light.findLamp(x, y, z)
    return cap ~= nil and cap > 0
end

-- Vanilla's Kill Crops Grown Inside: a crop in one of our containers is spared while a lamp or grow room looks after
-- it. Vanilla's penalty is given back afterwards, worked out the same way.
local originalChangeHealth = SFarmingSystem.changeHealth
function SFarmingSystem:changeHealth()
    originalChangeHealth(self)
    local opt = getSandboxOptions():getOptionByName("KillInsideCrops")
    if not (opt and opt:getValue() == true) then return end
    for key in Registry.eachBag() do
        local x, y, z = Config.parseKey(key)
        local plot = x and VanillaCrops.at(x, y, z)
        if plot and plot:isAlive() and type(plot.health) == "number" then
            local ok, spare = pcall(function()
                return vanillaPenalisesIndoors(plot) and VanillaCrops.keptAliveIndoors(x, y, z)
            end)
            if ok and spare then
                local bad = 1
                if plot.cursed then bad = bad * 2 end
                if plot.hasWeeds then bad = bad * 2 end
                if plot.naturalLight and plot.naturalLight > 0 then bad = bad / plot.naturalLight end
                plot.health = plot.health + bad
            end
        end
    end
end

return VanillaCrops
