-- Drip irrigation: a tank with a pump that holds soil pots at a set moisture with a slow drip, feeding them from the tank.
-- In a grow room it waters every soil pot in the room; outside one, the pots within a radius (sandbox DripRadius).

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisHydro"
require "CannabisMod/CannabisWorld"

local Config   = CannabisMod.Config
local Registry = CannabisMod.Registry
local Farming  = CannabisMod.Farming
local Hydro    = CannabisMod.Hydro
local K        = Config.Drip

local Drip = {}
CannabisMod.Drip = Drip

--- Tiles of soil plots the tank waters: every soil pot or cannabis plot in its grow room, else those within the radius.
function Drip.tilesOf(r)
    local Rooms = CannabisMod.Rooms
    local pk = Rooms and Rooms.keyAt(r.x, r.y, r.z)
    local set = pk and Rooms.tilesOf(pk)
    local out = {}
    local function consider(x, y, z)
        local bag = Registry.getBag(x, y, z)
        if Config.isHydro(bag) or (bag and not Registry.isBagSoiled(x, y, z)) then return end
        if bag or Registry.getPlant(x, y, z) then out[#out + 1] = { x, y, z } end
    end
    if set then
        for key in pairs(set) do
            local x, y, z = key:match("^(-?%d+)_(-?%d+)_(-?%d+)$")
            consider(tonumber(x), tonumber(y), tonumber(z))
        end
        return out
    end
    local R = math.max(1, math.floor(tonumber(Config.sandbox("DripRadius")) or 5))
    for x = r.x - R, r.x + R do
        for y = r.y - R, r.y + R do consider(x, y, r.z) end
    end
    return out
end

--- The living plants the tank waters (for the panel's reservoir row).
function Drip.plantsOf(r)
    local out = {}
    for _, t in ipairs(Drip.tilesOf(r)) do
        local plant = Registry.getPlant(t[1], t[2], t[3])
        if plant and not plant.dead then out[#out + 1] = plant end
    end
    return out
end

--- Whether the pump may run: power when pumps need it, and its grow room panel hasn't switched it off.
function Drip.running(r)
    local Rooms = CannabisMod.Rooms
    local room = Rooms and Rooms.roomAt(r.x, r.y, r.z)
    if room then
        if room.powered == false then return false end
        local forced = room.override and room.override.drip
        if forced == "off" then return false end
    end
    return Hydro.pumpsOn(r.x, r.y, r.z) ~= false
end

--- Feed a plant from the tank once per stage (and per feeding in held veg), as a hand feeding would.
local function fertigate(r, plant)
    if not (r.nutrient and (r.strength or 0) >= K.FEED_MIN) then return end
    if plant.stage < Config.STAGE.Vegetative or plant.stage >= Config.STAGE.Ripe then return end
    if (plant.fedThisStage or 0) > 0 then return end
    Registry.feed(plant, r.nutrient)
end

--- Drip into each pot that is under the target, as fast as the drip allows over `hours`, while the tank has water.
--- Returns the litres used.
function Drip.water(r, hours)
    local used = 0
    for _, t in ipairs(Drip.tilesOf(r)) do
        if r.level <= 0 then break end
        local luaObject = Farming.getVanilla(t[1], t[2], t[3])
        local water = luaObject and (luaObject.waterLvl or 0)
        if water and water < K.TARGET then
            local add = math.min(K.TARGET - water, K.RATE_PER_HOUR * hours, r.level / K.L_PER_POINT)
            if add > 0 then
                local litres = add * K.L_PER_POINT
                r.level = math.max(0, r.level - litres)
                used = used + litres
                luaObject.waterLvl = water + add
                pcall(function() luaObject:saveData() end)
                local plant = Registry.getPlant(t[1], t[2], t[3])
                if plant and not plant.dead then
                    plant.water = luaObject.waterLvl
                    fertigate(r, plant)
                end
            end
        end
    end
    return used
end

--- One drip tank's ten minutes: catch up on the time since its last run while its square is loaded.
function Drip.run(r, now)
    local hours = Config.clamp(now - (r.dripTick or now), 0, 24)
    r.dripTick = now
    if hours <= 0 or Hydro.hasDrip(r.x, r.y, r.z) ~= true then return 0 end
    r.dripOn = Drip.running(r)
    if not r.dripOn or r.level <= 0 then return 0 end
    return Drip.water(r, hours)
end

function Drip.tick()
    local now = Registry.nowHours()
    for _, r in Hydro.eachDrip() do Drip.run(r, now) end
end

--- A tank placed in the world gets its record at once, so it is ticked from the start.
function Drip.onObjectAdded(obj)
    local sprite = obj and obj.getSprite and obj:getSprite()
    if not (sprite and sprite:getName() == K.SPRITE) then return end
    local square = obj:getSquare()
    if not square then return end
    local r = Hydro.reservoirAt(square:getX(), square:getY(), square:getZ(), "drip")
    if r then r.dripTick = Registry.nowHours() end
end

Events.EveryTenMinutes.Add(Drip.tick)
CannabisMod.World.onObjectAdded("drip tank placing", function(obj, name, info)
    if info.drip then Drip.onObjectAdded(obj) end
end)

return Drip
