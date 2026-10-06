-- Optional Dazed Plumbing hookup: DWC buckets, RDWC control buckets and flood reservoirs take a water line from a tank.
-- The line fills a brand-new reservoir, refills one after "Change Reservoir", and fills one on "Top Up"; it never tops up on its own.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local Plumb = {}
CannabisMod.Plumbing = Plumb

Plumb.ID = "dazeddank_reservoir"
Plumb.LABEL = "ContextMenu_DazedDank_ReservoirLine"
Plumb.FULL_MARGIN = 0.05   -- litres short of full that still count as full

--- True when Dazed Plumbing is loaded and offers its machine registry.
function Plumb.available()
    return DazedPlumb ~= nil and DazedPlumb.Links ~= nil and DazedPlumb.Links.register ~= nil
end

--- Which reservoir an object is: "dwc" for a DWC bucket plot (standard or XL), "rdwc" for an RDWC control bucket, "ebb" for a flood reservoir, or nil.
function Plumb.kindOf(obj)
    local sprite = obj and obj.getSprite and obj:getSprite()
    local name = sprite and sprite:getName()
    if type(name) ~= "string" then return nil end
    if name == Config.Hydro.CONTROL_SPRITE then return "rdwc" end
    if name == Config.Hydro.FLOOD_SPRITE then return "ebb" end
    if Config.hydroOf(Config.bagFromSprite(name)) == "dwc" then return "dwc" end
    return nil
end

--- The pluggable reservoir object on a square, or nil.
function Plumb.objectAt(square)
    if not square then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if Plumb.kindOf(obj) then return obj end
    end
    return nil
end

--- True if this reservoir object has a water line on it (read from its synced ModData, so it works on clients too).
function Plumb.isPlumbed(obj)
    if not (obj and Plumb.available()) then return false end
    local ok, link = pcall(DazedPlumb.Links.linkOf, obj, Plumb.ID)
    return ok and link ~= nil
end

--- True if the reservoir at this tile has a water line.
function Plumb.isPlumbedAt(x, y, z)
    local square = getCell() and getCell():getGridSquare(x, y, z)
    return Plumb.isPlumbed(Plumb.objectAt(square))
end

--- The server's reservoir record for a plumbed object, or nil (clients have no Hydro module).
local function reservoir(obj)
    local Hydro = CannabisMod.Hydro
    local kind = Plumb.kindOf(obj)
    local square = obj and obj:getSquare()
    if not (Hydro and kind and square) then return nil end
    return Hydro.reservoirOfObject(square:getX(), square:getY(), square:getZ(), kind)
end

--- Litres a reservoir still takes from the line after a change, clearing its wait once it's full.
local function waiting(r)
    -- A reservoir that has never held water takes its first fill from the line.
    if not r.everFilled and not r.fillPending and (r.level or 0) <= Plumb.FULL_MARGIN then
        r.fillPending, r.everFilled = true, true
        if CannabisMod.Registry then r.changedAt = CannabisMod.Registry.nowHours() end
    end
    if not r.fillPending then return 0 end
    local room = CannabisMod.Hydro.capacity(r) - r.level
    if room <= Plumb.FULL_MARGIN then
        r.fillPending = nil
        return 0
    end
    return room
end

--- The reservoirs this line fills: its own, then the others in its grow room waiting on the room's line.
local function fedBy(r)
    local list = { r }
    local Rooms = CannabisMod.Rooms
    if Rooms and Rooms.lineDependents then
        for _, o in ipairs(Rooms.lineDependents(r)) do list[#list + 1] = o end
    end
    return list
end

--- Litres the line may pour in this minute: while a new, changed or topped-up reservoir is waiting to be filled.
function Plumb.room(obj)
    local r = reservoir(obj)
    if not r then return 0 end
    local total = 0
    for _, o in ipairs(fedBy(r)) do total = total + waiting(o) end
    return total
end

--- Take water from the line; tainted tank water taints what it fills. Returns the litres taken.
function Plumb.put(obj, amount, dirty)
    local r = reservoir(obj)
    if not r then return 0 end
    local left, took = amount or 0, 0
    for _, o in ipairs(fedBy(r)) do
        local add = math.max(0, math.min(left, waiting(o)))
        if add > 0 then
            o.level = o.level + add
            if dirty then o.tainted = true end
            left, took = left - add, took + add
            if o.level >= CannabisMod.Hydro.capacity(o) - Plumb.FULL_MARGIN then o.fillPending = nil end
        end
    end
    return took
end

--- Register with Dazed Plumbing once it has loaded; safe to call again.
function Plumb.register()
    if Plumb.registered or not Plumb.available() then return end
    Plumb.registered = DazedPlumb.Links.register({
        id = Plumb.ID, supplies = "water", label = Plumb.LABEL,
        match = function(obj) return Plumb.kindOf(obj) ~= nil end,
        room = Plumb.room, put = Plumb.put,
    }) == true
    if Plumb.registered then print("[DazedDank] Dazed Plumbing found: reservoirs can take a water line") end
end

-- Mods load in any order, so try now and again once every mod's Lua is in.
Plumb.register()
Events.OnGameBoot.Add(Plumb.register)
Events.OnInitGlobalModData.Add(Plumb.register)
