--[[ Dazed Dank -- grow gear as Dazed Power loads, through Dazed Core's power registry (Core 1.8.4 and later).

     Dank never names Dazed Power. When Core's DC_Power has registerLoad and feeds, and Dazed Power is active, the lamps,
     fans, climate units and pumps register as loads (kinds growlight, dryfan, dankclimate, dankpump, all slotless). A
     piece of gear that is cabled to a Power controller then follows only its wire: Link.feeds(obj) is true (fed), false
     (cabled but cut: priority, low voltage, trip, offline) or nil (not cabled, or no link). Gear that is not cabled keeps
     today's square power. With Core or Power missing, Link.on stays false and every function here answers as it did before.

     The verdict is remembered per object for one game moment, so a wire is read at most once per object per ten-minute
     tick. On the server a change of verdict is stamped on the object (md.DDWire = "on" / "off") for the lamp glow. ]]

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisWorld"
pcall(require, "DazedCore/DC_Boot")

local Config = CannabisMod.Config
local World = CannabisMod.World

local Link = CannabisMod.PowerLink or {}
CannabisMod.PowerLink = Link

Link.on = false

-- Rated watts. Lamps by their name in Config.Light, gear by its kind in Config.Rooms.EQUIPMENT.
Link.LAMP_WATTS = {
    ["Basic grow lamp"] = 150, ["Pro grow lamp"] = 400, ["Large basic grow lamp"] = 300, ["Large pro grow lamp"] = 600,
    ["Flood grow light"] = 300, ["Pro flood grow light"] = 600,
}
Link.GEAR_WATTS = {
    exhaust = 120, intake = 120, circfan = 50,
    heater = 1200, cooler = 700, humidifier = 50, dehumidifier = 250,
}
Link.DRYING_FAN_WATTS = 60
Link.PUMP_WATTS = { control = 40, flood = 60, drip = 25 }

-- Gear kinds that bill as fans; every other kind of room gear is climate equipment.
local FAN_KINDS = { exhaust = true, intake = true, circfan = true }

local core = nil          -- DazedCore.Power while the link is on

-- --------------------------------------------------------------------------
-- The wire verdict
-- --------------------------------------------------------------------------

local NONE = 0            -- a remembered nil
local memoAt, memo = nil, {}

--- Forget every remembered verdict (a new game moment does this by itself).
function Link.reset() memoAt, memo = nil, {} end

local function nowHours()
    local ok, v = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok then return v end
    return nil
end

--- The tile of a bar lamp that stands for the whole lamp: the member with the lowest x, then the lowest y.
--- Other lamps and every other object are their own anchor.
local function anchorSquare(obj)
    local square = obj:getSquare()
    local name = World.safeSpriteName(obj)
    local def = name and Config.Light.SPRITES[name]
    if not (square and def and def.tiles) then return square end
    local ok, members = pcall(World.lampSquares, square, obj)
    if not (ok and members) then return square end
    local best = square
    for _, sq in ipairs(members) do
        if sq:getX() < best:getX() or (sq:getX() == best:getX() and sq:getY() < best:getY()) then best = sq end
    end
    return best
end

--- True when this lamp object is the anchor tile of its lamp (always true for a one-tile lamp).
function Link.isAnchor(obj)
    local square = obj:getSquare()
    if not square then return false end
    local best = anchorSquare(obj)
    return best:getX() == square:getX() and best:getY() == square:getY() and best:getZ() == square:getZ()
end

--- The object whose wire stands for this one: the anchor tile's lamp for a bar lamp tile, else the object itself.
local function wireObject(obj)
    local name = World.safeSpriteName(obj)
    local def = name and Config.Light.SPRITES[name]
    if not (def and def.tiles) then return obj end
    local square, best = obj:getSquare(), anchorSquare(obj)
    if not square or best == square then return obj end
    return World.findIn(best, Config.Light.SPRITES) or obj
end

local function stamp(obj, verdict)
    if isClient() then return end
    local want = nil
    if verdict == true then want = "on" elseif verdict == false then want = "off" end
    local md = obj:getModData()
    if md.DDWire == want then return end
    md.DDWire = want
    pcall(obj.transmitModData, obj)
end

--- True when the wire feeds the object, false when it is cabled but cut, nil when it is not cabled or the link is off.
function Link.feeds(obj)
    if not (Link.on and core and obj) then return nil end
    local now = nowHours()
    if now == nil or now ~= memoAt then memoAt, memo = now, {} end
    local hit = memo[obj]
    if hit ~= nil then
        if hit == NONE then return nil end
        return hit
    end
    local verdict = nil
    local ok, target = pcall(wireObject, obj)
    if ok and target then
        local fine, f = pcall(core.feeds, target)
        if fine and (f == true or f == false) then verdict = f end
    end
    memo[obj] = (verdict == nil) and NONE or verdict
    pcall(stamp, obj, verdict)
    return verdict
end

--- Has this object power? The wire decides for cabled gear; anything else uses the square it stands on, as always.
function Link.powered(obj, square)
    local f = Link.feeds(obj)
    if f ~= nil then return f end
    return World.isPowered(square)
end

-- --------------------------------------------------------------------------
-- A grow room fed by cable
-- --------------------------------------------------------------------------

local roomAt, roomMemo = nil, {}

--- Is any cabled load in this room fed (true), are all of its cabled loads cut (false), or is nothing cabled (nil)?
--- `c` is the room's contents (Rooms.contents). Remembered for the game moment.
function Link.roomFed(panelKey, c)
    if not Link.on then return nil end
    local now = nowHours()
    if now == nil or now ~= roomAt then roomAt, roomMemo = now, {} end
    local hit = roomMemo[panelKey]
    if hit ~= nil then
        if hit == NONE then return nil end
        return hit
    end
    local seen, fed = false, false
    local Rooms = CannabisMod.Rooms
    c = c or (Rooms and Rooms.contents(panelKey))
    if c then
        local groups = { c.lamps, c.gear, c.pumps }
        for g = 1, 3 do
            for _, e in ipairs(groups[g] or {}) do
                local f = e.obj and Link.feeds(e.obj)
                if f ~= nil then
                    seen = true
                    if f then fed = true end
                end
            end
        end
    end
    local out = nil
    if seen then out = fed end
    roomMemo[panelKey] = (out == nil) and NONE or out
    return out
end

-- --------------------------------------------------------------------------
-- Finding and describing the gear
-- --------------------------------------------------------------------------

local pumpSprites = nil

--- The pump object (RDWC control bucket, flood reservoir or drip tank) standing on a square, or nil.
function Link.pumpAt(square)
    if not pumpSprites then
        pumpSprites = {
            [Config.Hydro.CONTROL_SPRITE] = "control", [Config.Hydro.FLOOD_SPRITE] = "flood", [Config.Drip.SPRITE] = "drip",
        }
    end
    local obj, _, what = World.findIn(square, pumpSprites)
    return obj, what
end

local function squareOf(obj)
    local ok, sq = pcall(obj.getSquare, obj)
    if ok then return sq end
    return nil
end

local function roomOf(obj)
    local Rooms = CannabisMod.Rooms
    local sq = squareOf(obj)
    if not (Rooms and Rooms.roomAt and sq) then return nil end
    return Rooms.roomAt(sq:getX(), sq:getY(), sq:getZ())
end

--- What a piece of room gear is (Config.Rooms.EQUIPMENT entry) or nil.
local function gearOf(obj)
    local name = World.safeSpriteName(obj)
    return name and Config.Rooms.EQUIPMENT[name] or nil
end

local function lampWatts(obj)
    local name = World.safeSpriteName(obj)
    local def = name and Config.Light.SPRITES[name]
    return def and Link.LAMP_WATTS[def.name] or 0
end

-- working(obj): is the machine drawing its rated watts right now? Power asks on the server only.

local function lampWorking(obj)
    if isClient() or not Config.sandbox("LampsNeedPower") then return false end
    if Link.feeds(obj) ~= true then return false end
    local square = squareOf(obj)
    if not square then return false end
    if obj:getModData().DDRoomOff then return false end
    local Timers = CannabisMod.Timers
    local schedule = Timers and Timers.scheduleAt(square:getX(), square:getY(), square:getZ()) or nil
    return Config.Timer.isOn(schedule, getGameTime():getHour())
end

local function gearWorking(obj)
    if isClient() or Link.feeds(obj) ~= true then return false end
    local g = gearOf(obj)
    local room = roomOf(obj)
    if not (g and room) then return false end
    return room.powered ~= false and room.running ~= nil and room.running[g.kind] == true
end

local function dryingFanWorking(obj)
    return not isClient() and Link.feeds(obj) == true
end

local function pumpWorking(obj)
    if isClient() or not Config.sandbox("PumpsNeedPower") or Link.feeds(obj) ~= true then return false end
    local square = squareOf(obj)
    local Hydro = CannabisMod.Hydro
    local what = nil
    if square then what = select(2, Link.pumpAt(square)) end
    if what == "drip" and Hydro and Hydro.peek then
        local r = Hydro.peek(square:getX(), square:getY(), square:getZ())
        if r and r.dripOn == false then return false end
    end
    return true
end

local function pumpWatts(obj)
    local square = squareOf(obj)
    local what = nil
    if square then what = select(2, Link.pumpAt(square)) end
    return what and Link.PUMP_WATTS[what] or 0
end

-- --------------------------------------------------------------------------
-- Switching on
-- --------------------------------------------------------------------------

local function nameSet(set) return function(name) return set[name] ~= nil end end

--- Turn the link on when Core's power registry and Dazed Power are both here; otherwise leave it off. Safe to call again.
function Link.init()
    Link.on, core = false, nil
    local DC = DazedCore
    local W = DC and DC.Power
    local D = DC and DC.Detect
    if not (W and type(W.registerLoad) == "function" and type(W.feeds) == "function" and D and type(D.isActive) == "function") then
        return false
    end
    local ok, active = pcall(D.isActive, "DazedPower")
    if not (ok and active == true) then return false end
    core = W
    Link.reset()

    local pumpNames = {}
    for _, sprite in ipairs({ Config.Hydro.CONTROL_SPRITE, Config.Hydro.FLOOD_SPRITE, Config.Drip.SPRITE }) do pumpNames[sprite] = true end
    local fanSprites, climateSprites = {}, {}
    fanSprites[Config.Drying.FAN_SPRITE] = true
    for name, g in pairs(Config.Rooms.EQUIPMENT) do
        -- The drip tank is room equipment too (kind "drip"), but it is a pump: leave it to dazeddank_pump.
        if not pumpNames[name] then
            if FAN_KINDS[g.kind] then fanSprites[name] = true else climateSprites[name] = true end
        end
    end

    local lampItems = {}
    for item in pairs(Config.Light.ITEMS) do lampItems[#lampItems + 1] = item end
    table.sort(lampItems)

    W.registerLoad({ id = "dazeddank_light", kind = "growlight", slotless = true,
        prefix = World.PREFIX, matchName = nameSet(Config.Light.SPRITES), match = Link.isAnchor,
        watts = lampWatts, working = lampWorking,
        items = lampItems })
    W.registerLoad({ id = "dazeddank_fan", kind = "dryfan", slotless = true,
        prefix = World.PREFIX, matchName = nameSet(fanSprites), byName = true, match = function() return true end,
        watts = function(obj)
            if World.safeSpriteName(obj) == Config.Drying.FAN_SPRITE then return Link.DRYING_FAN_WATTS end
            local g = gearOf(obj)
            return g and Link.GEAR_WATTS[g.kind] or 0
        end,
        working = function(obj)
            if World.safeSpriteName(obj) == Config.Drying.FAN_SPRITE then return dryingFanWorking(obj) end
            return gearWorking(obj)
        end,
        items = { Config.Drying.FAN_ITEM, "CannabisMod.ExhaustFan", "CannabisMod.IntakeFan", "CannabisMod.CirculationFan" } })
    W.registerLoad({ id = "dazeddank_climate", kind = "dankclimate", slotless = true,
        prefix = World.PREFIX, matchName = nameSet(climateSprites), byName = true, match = function() return true end,
        watts = function(obj)
            local g = gearOf(obj)
            return g and Link.GEAR_WATTS[g.kind] or 0
        end,
        working = gearWorking,
        items = { "CannabisMod.Heater", "CannabisMod.WallAC", "CannabisMod.Humidifier", "CannabisMod.Dehumidifier" } })
    W.registerLoad({ id = "dazeddank_pump", kind = "dankpump", slotless = true,
        prefix = World.PREFIX, matchName = nameSet(pumpNames), byName = true, match = function() return true end,
        watts = pumpWatts, working = pumpWorking,
        items = { Config.Hydro.CONTROL_ITEM, Config.Hydro.FLOOD_ITEM, Config.Drip.ITEM } })
    Link.on = true
    return true
end

-- On OnGameBoot, so mod load order cannot matter (the same choice as Dazed Power's own hook).
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(Link.init) end

return Link
