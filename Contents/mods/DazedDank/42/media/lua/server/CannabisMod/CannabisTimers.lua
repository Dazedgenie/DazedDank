-- Light timers installed on placed lamps. The server keeps them in global ModData by tile, and copies the schedule onto the lamp object so clients can show it.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"
require "Moveables/ISMoveableSpriteProps"

local Config = CannabisMod.Config
local Net = CannabisMod.Net
local commands = CannabisMod.ServerCommands.handlers
local isNear = CannabisMod.ServerCommands.isNear

local Timers = {}
CannabisMod.Timers = Timers

-- timers[tileKey] = { s = schedule, item = true on the one tile that holds the timer item }
local timers = nil

Events.OnInitGlobalModData.Add(function()
    timers = ModData.getOrCreate(Config.MODDATA_KEY .. "_Timers")
end)

--- Replace the saved table (tests use this to start clean).
function Timers._reset(tbl) timers = tbl or {} end

--- The schedule of the timer on a lamp tile, or nil when it has none (24/0).
function Timers.scheduleAt(x, y, z)
    local Rooms = CannabisMod.Rooms
    if Rooms then
        local ruled, schedule = Rooms.scheduleAt(x, y, z)
        if ruled then return schedule end
    end
    local entry = timers and timers[Config.tileKey(x, y, z)]
    return entry and entry.s or nil
end

--- The lamp object on a square, or nil.
local function lampObject(square)
    local objects = square:getObjects()
    local sprites = Config.Light.SPRITES
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if name and sprites[name] then return obj end
    end
    return nil
end

--- Every square of the lamp on `square`: all tiles of a bar lamp, or just this one.
local function lampSquares(square, obj)
    local out = { square }
    pcall(function()
        local props = ISMoveableSpriteProps.fromObject(obj)
        if props and props.isMultiSprite then
            local info = props:getSpriteGridInfo(square, true)
            if info and #info > 0 then
                out = {}
                for _, member in ipairs(info) do out[#out + 1] = member.square end
            end
        end
    end)
    return out
end

--- The schedule the lamp object carries for clients, or nil.
local function objectSchedule(obj)
    return obj:getModData().DDTimer
end

--- Copy the schedule onto the lamp object so the client's menu can read it.
local function markObject(square, schedule)
    local obj = lampObject(square)
    if not obj then return end
    pcall(function()
        obj:getModData().DDTimer = schedule
        obj:transmitModData()
    end)
end

--- Set (or with nil, clear) the timer on every tile of the lamp at `square`; the clicked tile holds the item.
local function setLamp(square, obj, schedule)
    for _, sq in ipairs(lampSquares(square, obj)) do
        local key = Config.tileKey(sq:getX(), sq:getY(), sq:getZ())
        if schedule then
            timers[key] = { s = schedule, item = (sq == square) or nil }
        else
            timers[key] = nil
        end
        markObject(sq, schedule)
    end
end

--- The tile of this lamp that holds the timer item, so removal and moves give back exactly one.
local function itemTile(square, obj)
    for _, sq in ipairs(lampSquares(square, obj)) do
        local entry = timers[Config.tileKey(sq:getX(), sq:getY(), sq:getZ())]
        if entry and entry.item then return sq end
    end
    return square
end

--- Put a grow room's schedule on every lamp in `tileSet` and clear any timer of their own.
--- Returns how many timer items were freed, for the caller to hand back.
function Timers.adoptRoom(tileSet, schedule)
    if not timers then return 0 end
    local cell = getCell()
    local freed = 0
    for key in pairs(tileSet) do
        local entry = timers[key]
        if entry then
            timers[key] = nil
            if entry.item then freed = freed + 1 end
        end
        local x, y, z = key:match("^(-?%d+)_(-?%d+)_(-?%d+)$")
        local square = x and cell:getGridSquare(tonumber(x), tonumber(y), tonumber(z))
        local lamp = square and lampObject(square)
        if lamp and objectSchedule(lamp) ~= schedule then markObject(square, schedule) end
    end
    return freed
end

--- Mark every lamp in `tileSet` as dead (or alive again) so clients stop (or restart) its glow when the room's panel loses power.
function Timers.markRoomPower(tileSet, off)
    local cell = getCell()
    for key in pairs(tileSet) do
        local x, y, z = key:match("^(-?%d+)_(-?%d+)_(-?%d+)$")
        local square = x and cell:getGridSquare(tonumber(x), tonumber(y), tonumber(z))
        local lamp = square and lampObject(square)
        if lamp and (lamp:getModData().DDRoomOff == true) ~= off then
            lamp:getModData().DDRoomOff = off or nil
            pcall(lamp.transmitModData, lamp)
        end
    end
end

--- Look up the lamp a player is acting on, after checking they're close enough.
local function lampFor(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z and timers) or not isNear(player, x, y, z) then return nil end
    local square = getCell():getGridSquare(x, y, z)
    local obj = square and lampObject(square)
    if not obj then return nil end
    return square, obj
end

commands.installTimer = function(player, args)
    local square, obj = lampFor(player, args)
    if not square then return end
    if CannabisMod.Rooms and CannabisMod.Rooms.keyAt(square:getX(), square:getY(), square:getZ()) then
        Net.notify(player, "The grow room panel sets this lamp's schedule")
        return
    end
    if Timers.scheduleAt(square:getX(), square:getY(), square:getZ()) then
        Net.notify(player, "That lamp already has a timer")
        return
    end
    local item = player:getInventory():getFirstTypeRecurse(Config.Timer.ITEM)
    if not item then
        Net.notify(player, "You need a light timer")
        return
    end
    local container = item:getContainer()
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    setLamp(square, obj, Config.Timer.DEFAULT)
    Net.notify(player, "Timer installed: " .. Config.Timer.DEFAULT)
end

commands.setTimer = function(player, args)
    local square, obj = lampFor(player, args)
    if not square or not Config.Timer.SCHEDULES[args.schedule] then return end
    if CannabisMod.Rooms and CannabisMod.Rooms.keyAt(square:getX(), square:getY(), square:getZ()) then
        Net.notify(player, "The grow room panel sets this lamp's schedule")
        return
    end
    if not Timers.scheduleAt(square:getX(), square:getY(), square:getZ()) then return end
    local holder = itemTile(square, obj)
    setLamp(holder, obj, args.schedule)
    Net.notify(player, "Light timer set to " .. args.schedule)
end

commands.removeTimer = function(player, args)
    local square, obj = lampFor(player, args)
    if not square then return end
    if CannabisMod.Rooms and CannabisMod.Rooms.keyAt(square:getX(), square:getY(), square:getZ()) then
        Net.notify(player, "The grow room panel sets this lamp's schedule")
        return
    end
    if not Timers.scheduleAt(square:getX(), square:getY(), square:getZ()) then return end
    setLamp(square, obj, nil)
    CannabisMod.Farming.giveItems(player, Config.Timer.ITEM, 1)
    Net.notify(player, "Timer removed: the lamp now runs 24/0")
end

--- Drop the timer on the floor when its lamp has been picked up, so it is never lost.
--- Also re-copies each schedule onto its lamp object, so lamps whose copy is missing or stale stop glowing in their dark hours.
function Timers.cleanup()
    if not timers then return end
    local any = false
    for _ in pairs(timers) do any = true break end
    if not any then return end
    local cell = getCell()
    local gone = {}
    for key, entry in pairs(timers) do
        local x, y, z = key:match("^(-?%d+)_(-?%d+)_(-?%d+)$")
        local square = x and cell:getGridSquare(tonumber(x), tonumber(y), tonumber(z))
        local lamp = square and lampObject(square)
        if square and not lamp then
            gone[#gone + 1] = key
            if entry.item then
                pcall(function() square:AddWorldInventoryItem(Config.Timer.ITEM, 0.5, 0.5, 0) end)
            end
        elseif lamp and objectSchedule(lamp) ~= entry.s then
            markObject(square, entry.s)
        end
    end
    for _, key in ipairs(gone) do timers[key] = nil end
end

Events.EveryTenMinutes.Add(Timers.cleanup)
Events.OnGameStart.Add(Timers.cleanup)
