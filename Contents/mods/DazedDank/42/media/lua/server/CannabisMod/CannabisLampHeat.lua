-- Lit grow lamps warm the room they hang in, and running wall ACs cool it, for the Dazed Climate mod's room temperatures.
-- Registered once with Dazed Climate when it is loaded; without it this file does nothing.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisLight"

local Config = CannabisMod.Config

local LampHeat = {}
CannabisMod.LampHeat = LampHeat

--- The lamp definition for an object's sprite, or nil when it isn't a grow lamp.
local function lampDef(obj)
    local ok, name = pcall(function()
        local sprite = obj:getSprite()
        return sprite and sprite:getName()
    end)
    return ok and name and Config.Light.SPRITES[name] or nil
end

--- True for a placed grow lamp (Dazed Climate asks this once per room read).
function LampHeat.match(obj)
    return lampDef(obj) ~= nil
end

--- True when a lamp is lit right now: powered (if lamps need power), its room's panel powered, and its timer on.
function LampHeat.isLit(obj)
    local ok, lit = pcall(function()
        local square = obj:getSquare()
        if not square then return false end
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local Rooms = CannabisMod.Rooms
        if Config.sandbox("LampsNeedPower") then
            if not CannabisMod.Light.isPowered(square) then return false end
            if Rooms and Rooms.poweredAt(x, y, z) == false then return false end
        end
        local Timers = CannabisMod.Timers
        local schedule = Timers and Timers.scheduleAt(x, y, z) or nil
        return Config.Timer.isOn(schedule, getGameTime():getHour())
    end)
    return ok and lit == true
end

--- Heat a lamp gives its room, in C x squares per hour: radius x 3 while lit, split across the tiles of a bar lamp.
function LampHeat.heat(obj)
    if not Config.sandbox("LampHeat") then return 0 end
    local def = lampDef(obj)
    if not def or not LampHeat.isLit(obj) then return 0 end
    return def.radius * Config.Weather.LAMP_HEAT_PER_RADIUS / (def.tiles or 1)
end

--- The equipment entry for an object's sprite, or nil.
local function gearOf(obj)
    local ok, name = pcall(function()
        local sprite = obj:getSprite()
        return sprite and sprite:getName()
    end)
    return ok and name and Config.Rooms.EQUIPMENT[name] or nil
end

--- True for a placed wall AC (Dazed Climate asks this once per room read).
function LampHeat.isCooler(obj)
    local gear = gearOf(obj)
    return gear ~= nil and gear.kind == "cooler"
end

--- A wall AC's pull on its Dazed Climate room: negative heat while its grow room panel has it running, else none.
function LampHeat.coolerHeat(obj)
    local ok, heat = pcall(function()
        local square = obj:getSquare()
        local Rooms = CannabisMod.Rooms
        local room = square and Rooms and Rooms.roomAt(square:getX(), square:getY(), square:getZ())
        if not (room and room.powered ~= false and room.running and room.running.cooler) then return 0 end
        return Config.Climate.COOLER_HEAT
    end)
    return ok and heat or 0
end

local registered = false

--- Hand the lamp source to Dazed Climate once, if it is loaded yet.
function LampHeat.register()
    if registered then return true end
    local rooms = DazedClimate and DazedClimate.Rooms
    if not (rooms and rooms.addObjectSource) then return false end
    rooms.addObjectSource({ match = LampHeat.match, heat = LampHeat.heat })
    rooms.addObjectSource({ match = LampHeat.isCooler, heat = LampHeat.coolerHeat })
    registered = true
    print("[DazedDank] Dazed Climate found: grow lamps warm their rooms")
    return true
end

-- Mods load in any order, so try now and again once the game or server has started.
LampHeat.register()
Events.OnGameStart.Add(LampHeat.register)
if Events.OnServerStarted then Events.OnServerStarted.Add(LampHeat.register) end
