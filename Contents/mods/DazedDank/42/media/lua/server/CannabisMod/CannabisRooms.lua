-- Grow rooms: a wall panel claims the connected indoor floor around it, and every lamp in that room runs the room's schedule.
-- Only the panels are saved; the tiles of each room are worked out again at load and whenever a wall or door changes.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisSchedule"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisServerCommands"
require "CannabisMod/CannabisLight"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisInfo"
require "CannabisMod/CannabisClimate"
require "CannabisMod/CannabisWeather"
require "CannabisMod/CannabisPlantTemp"
require "CannabisMod/CannabisDrying"
require "CannabisMod/CannabisWorld"
require "Moveables/ISMoveableSpriteProps"

local Config = CannabisMod.Config
local World = CannabisMod.World
local Net = CannabisMod.Net
local commands = CannabisMod.ServerCommands.handlers
local isNear = CannabisMod.ServerCommands.isNear

local Rooms = {}
CannabisMod.Rooms = Rooms

-- panels[panelKey] = { x, y, z, name, schedule, mode }, saved with the world.
local panels = nil
-- curtains[edgeKey] = true for every door or window frame with a blackout curtain on it, saved with the world.
local curtains = nil
-- openings[panelKey] = the room's doors and windows, rebuilt with the room.
local openings = {}
-- Rebuilt from the panels: tileRoom[tileKey] = panelKey, and tiles[panelKey] = { [tileKey] = true }.
local tileRoom, tiles = {}, {}
-- Built with tiles: tileList[panelKey] = { { x, y, z, key }... } so passes over a room never re-parse keys,
-- and bounds[panelKey] = { x1, y1, x2, y2, z } to tell whether a change is near the room.
local tileList, bounds = {}, {}
-- contents[panelKey] = what the room holds, read in one pass (see Rooms.contents); contentsVersion goes up when it may be stale.
local contents, contentsVersion = {}, 0
-- Rooms whose shape needs filling again after a construction change or a square loading near them.
local shapeDirty = {}
-- World hours of the last full rebuild; a slow safety pass refills every room this often.
local lastShapeAt = nil
Rooms.SHAPE_SAFETY_HOURS = 6
-- Goes up whenever tileRoom changes, so the per-room plant lists know when to rebuild.
local roomsVersion = 0
-- byRoom[panelKey] = every plant record (dead ones too) standing in that room, rebuilt when plants or rooms change.
local byRoom, byRoomPlants, byRoomRooms = {}, nil, nil

--- The plants of every room, from the shared lists (rebuilt only after a plant or room change).
local function plantsByRoom()
    local version = CannabisMod.Registry.version
    if byRoomPlants == version and byRoomRooms == roomsVersion then return byRoom end
    byRoom = {}
    for key, plant in CannabisMod.Registry.each() do
        local panelKey = tileRoom[key]
        if panelKey then
            local list = byRoom[panelKey]
            if not list then list = {} byRoom[panelKey] = list end
            list[#list + 1] = plant
        end
    end
    byRoomPlants, byRoomRooms = version, roomsVersion
    return byRoom
end

Events.OnInitGlobalModData.Add(function()
    panels = ModData.getOrCreate(Config.MODDATA_KEY .. "_Rooms")
    curtains = ModData.getOrCreate(Config.MODDATA_KEY .. "_Curtains")
end)

--- The saved curtain records (tests use this to stand in for a save from before curtains were retired).
function Rooms._curtainTable() return curtains end

--- Replace the saved panels (tests use this to start clean).
function Rooms._reset(tbl, curtainTbl)
    panels = tbl or {}
    curtains = curtainTbl or {}
    tileRoom, tiles, openings = {}, {}, {}
    tileList, bounds, contents, shapeDirty, lastShapeAt = {}, {}, {}, {}, nil
    roomsVersion = roomsVersion + 1
    contentsVersion = contentsVersion + 1
end

--- True when the way from square a to the next square b is shut by a wall, a door frame or a window frame.
function Rooms.edgeBlocked(a, b)
    local ok, shut = pcall(a.isBlockedTo, a, b)
    if ok and shut then return true end
    ok, shut = pcall(a.isDoorTo, a, b)
    if ok and shut then return true end
    ok, shut = pcall(a.isWindowTo, a, b)
    return ok and shut == true
end

local DIRS = { { 1, 0, "E" }, { -1, 0, "W" }, { 0, 1, "S" }, { 0, -1, "N" } }

--- The key of the wall edge on one side of a tile. Every edge is named from the tile that owns its N or W side, so both sides agree.
function Rooms.edgeKey(x, y, z, dir)
    if dir == "S" then y, dir = y + 1, "N" end
    if dir == "E" then x, dir = x + 1, "W" end
    return Config.tileKey(x, y, z) .. "_" .. dir
end

--- "door" or "window" when the edge between squares a and b is a door or window frame, else nil.
function Rooms.edgeKind(a, b)
    local ok, yes = pcall(a.isDoorTo, a, b)
    if ok and yes then return "door" end
    ok, yes = pcall(a.isWindowTo, a, b)
    if ok and yes then return "window" end
    return nil
end

--- True when a vanilla curtain on the window between a and b is drawn shut.
function Rooms.vanillaCovered(a, b)
    local ok, covered = pcall(function()
        local window = a:getWindowTo(b)
        local curtain = window and window:HasCurtains()
        return curtain ~= nil and curtain ~= false and not curtain:IsOpen()
    end)
    return ok and covered == true
end

--- The door between squares a and b and its state: open, and whether a sheet hung on it is drawn. Nil when there is none.
function Rooms.doorState(a, b)
    local door = nil
    for _, pair in ipairs({ { a, b }, { b, a } }) do
        local ok, d = pcall(pair[1].getDoorTo, pair[1], pair[2])
        if ok and d then door = d break end
    end
    -- Fallback: the door object standing on either square (the edge is already known to be a door frame).
    if not door then
        for _, sq in ipairs({ a, b }) do
            pcall(function()
                local objects = sq:getObjects()
                for i = 0, objects:size() - 1 do
                    local o = objects:get(i)
                    if not door and (instanceof(o, "IsoDoor") or (instanceof(o, "IsoThumpable") and o:isDoor())) then door = o end
                end
            end)
        end
    end
    if not door then return nil end
    local isOpen = false
    pcall(function() isOpen = door:IsOpen() == true end)
    -- A vanilla door's sheet is its own curtain object (as for windows); built doors answer for it themselves.
    local drawn = false
    pcall(function()
        local c = door:HasCurtains()
        if not c then return end
        if c ~= true and c.IsOpen then drawn = not c:IsOpen()
        elseif door.isCurtainOpen then drawn = not door:isCurtainOpen() end
    end)
    return isOpen, drawn == true
end

--- How much light an opening lets in, 0 (sealed) to 1 (open): a drawn curtain or sheet seals it,
--- and a closed door with no drawn sheet seeps the sandbox DoorLeak share round its edges.
function Rooms.leakOf(kind, sq, nb, edge)
    if curtains[edge] == true then return 0 end
    if kind == "window" then return Rooms.vanillaCovered(sq, nb) and 0 or 1 end
    local isOpen, drawn = Rooms.doorState(sq, nb)
    if isOpen == nil or isOpen then return 1 end
    if drawn then return 0 end
    return Config.clamp((tonumber(Config.sandbox("DoorLeak")) or 25) / 100, 0, 1)
end

--- Every door and window frame on a room's edge, with how much light it lets in; `list` is the room's tile list when known.
function Rooms.findOpenings(set, list)
    local cell = getCell()
    local out = {}
    if not list then
        list = {}
        for tileKey in pairs(set) do
            local x, y, z = Config.parseKey(tileKey)
            list[#list + 1] = { x = x, y = y, z = z, key = tileKey }
        end
    end
    for _, t in ipairs(list) do
        local x, y, z = t.x, t.y, t.z
        local sq = cell:getGridSquare(x, y, z)
        for _, d in ipairs(DIRS) do
            local nx, ny = x + d[1], y + d[2]
            if sq and not set[Config.tileKey(nx, ny, z)] then
                local nb = cell:getGridSquare(nx, ny, z)
                local kind = nb and Rooms.edgeKind(sq, nb)
                if kind then
                    local edge = Rooms.edgeKey(x, y, z, d[3])
                    local leak = Rooms.leakOf(kind, sq, nb, edge)
                    local outside = false
                    pcall(function() outside = nb:isOutside() == true end)
                    out[#out + 1] = { x = x, y = y, z = z, ox = nx, oy = ny, kind = kind, edge = edge, leak = leak,
                        covered = leak <= 0, seeps = leak > 0 and leak < 1, outside = outside }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        return a.edge < b.edge
    end)
    return out
end

--- The openings of a room by its panel key.
function Rooms.openingsOf(panelKey) return openings[panelKey] or {} end

--- How much of an outside lamp at (lx, ly) reaches a plant at (px, py) in the room: the leakiest opening near the plant
--- that the lamp shines on, 0 to 1.
function Rooms.lampLeak(panelKey, px, py, lx, ly, def, range)
    if not Config.sandbox("LightLeaks") then return 0 end
    local best = 0
    for _, o in ipairs(openings[panelKey] or {}) do
        local leak = o.leak or (o.covered and 0 or 1)
        if leak > best and math.abs(px - o.x) + math.abs(py - o.y) <= Config.Rooms.LEAK_NEAR
            and Config.Light.reaches(o.ox - lx, o.oy - ly, def.radius, range) then
            best = leak
        end
    end
    return best
end

--- True when an outside lamp shines into the room through a fully open opening, so it counts as the plant's light.
function Rooms.outsideLampReaches(panelKey, px, py, lx, ly, def, range)
    return Rooms.lampLeak(panelKey, px, py, lx, ly, def, range) >= 1
end

--- How much sunlight reaches a plant of a 12/12 room during its dark hours, 0 to 1: through an uncovered window,
--- or a door to the outside (open, or seeping round its edges when closed). False when none does.
function Rooms.sunLeakAt(panelKey, px, py, hour)
    local room = panels[panelKey]
    if not room or room.schedule ~= "12/12" or Config.Timer.isOn("12/12", hour) then return false end
    if hour < Config.Rooms.SUN_FROM or hour >= Config.Rooms.SUN_TO then return false end
    local best = 0
    for _, o in ipairs(openings[panelKey] or {}) do
        local leak = o.leak or (o.covered and 0 or 1)
        local sunny = o.kind == "window" or o.outside
        if sunny and leak > best and math.abs(px - o.x) + math.abs(py - o.y) <= Config.Rooms.LEAK_NEAR then best = leak end
    end
    return best > 0 and best or false
end

--- Log a line at most once every twelve hours per `kind`, so a steady problem doesn't flood the log.
function Rooms.noteOnce(panelKey, kind, text, now)
    local room = panels[panelKey]
    if not room then return end
    now = now or getGameTime():getWorldAgeHours()
    room.leakAt = room.leakAt or {}
    if now - (room.leakAt[kind] or -1000) >= 12 then
        room.leakAt[kind] = now
        Rooms.log(room, text, now)
    end
end

--- Log a leak at most once every twelve hours per kind of leak.
function Rooms.noteLeak(panelKey, text, now)
    Rooms.noteOnce(panelKey, text, text, now)
end

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

--- The indoor tiles connected to `square` without crossing a wall, door frame or window frame, on one floor.
--- Returns the set of tile keys, how many there are, and true when the cap cut it short (the set is then a radius around the panel).
--- The fourth result is the same tiles as a list of { x, y, z, key }.
function Rooms.fill(square, blocked)
    blocked = blocked or Rooms.edgeBlocked
    local cell = getCell()
    local z = square:getZ()
    local sx, sy = square:getX(), square:getY()
    local set, count = {}, 0
    local queue, head = { square }, 1
    local startKey = Config.tileKey(sx, sy, z)
    set[startKey] = true
    local list = { { x = sx, y = sy, z = z, key = startKey } }
    count = 1
    while head <= #queue do
        local sq = queue[head]
        head = head + 1
        local x, y = sq:getX(), sq:getY()
        for _, d in ipairs(NEIGHBOURS) do
            local nx, ny = x + d[1], y + d[2]
            local key = Config.tileKey(nx, ny, z)
            if not set[key] then
                local nb = cell:getGridSquare(nx, ny, z)
                if nb and not nb:isOutside() and not blocked(sq, nb) then
                    set[key] = true
                    count = count + 1
                    queue[#queue + 1] = nb
                    list[count] = { x = nx, y = ny, z = z, key = key }
                    if count > Config.Rooms.MAX_TILES then
                        local rset, rlist = Rooms.radiusFill(square)
                        return rset, count, true, rlist
                    end
                end
            end
        end
    end
    return set, count, false, list
end

--- The fallback for a very large space: every indoor tile within the fallback radius of the panel (set, then list).
function Rooms.radiusFill(square)
    local cell = getCell()
    local z, R = square:getZ(), Config.Rooms.FALLBACK_RADIUS
    local set, list = {}, {}
    for dx = -R, R do
        for dy = -R, R do
            local x, y = square:getX() + dx, square:getY() + dy
            local sq = cell:getGridSquare(x, y, z)
            if sq and not sq:isOutside() then
                local key = Config.tileKey(x, y, z)
                set[key] = true
                list[#list + 1] = { x = x, y = y, z = z, key = key }
            end
        end
    end
    return set, list
end

--- Store a room's tiles with their list and bounds (tileRoom is the caller's to update).
local function setRoomTiles(key, set, list)
    tiles[key], tileList[key] = set, list
    local b = nil
    for _, t in ipairs(list) do
        if not b then
            b = { x1 = t.x, y1 = t.y, x2 = t.x, y2 = t.y, z = t.z }
        else
            if t.x < b.x1 then b.x1 = t.x end
            if t.x > b.x2 then b.x2 = t.x end
            if t.y < b.y1 then b.y1 = t.y end
            if t.y > b.y2 then b.y2 = t.y end
        end
    end
    bounds[key] = b
    contentsVersion = contentsVersion + 1
end

--- Forget a room's tiles (its panel is gone or out of loaded range).
local function dropRoomTiles(key)
    tiles[key], tileList[key], bounds[key], contents[key], openings[key] = nil, nil, nil, nil, nil
    contentsVersion = contentsVersion + 1
end

--- Work tileRoom out again from every room's tiles.
local function rebuildTileRoom()
    tileRoom = {}
    for key, set in pairs(tiles) do
        for tileKey in pairs(set) do tileRoom[tileKey] = key end
    end
    roomsVersion = roomsVersion + 1
end

--- True when the object is one of the panel's wall sprites.
local function isPanelObject(obj)
    local sprite = obj:getSprite()
    local name = sprite and sprite:getName()
    return name ~= nil and Config.Rooms.PANEL_SPRITES[name] ~= nil
end

--- The panel object on a square, or nil.
function Rooms.panelObject(square)
    return (World.findIn(square, Config.Rooms.PANEL_SPRITES))
end

--- True when a panel object stands on the square.
local function panelOn(square)
    return World.findIn(square, Config.Rooms.PANEL_SPRITES) ~= nil
end

--- Hand every lamp in a room the room's schedule and give back any timer it carried.
--- With a player the freed timers go to them; otherwise they drop at the panel.
function Rooms.sync(panelKey, player)
    local Timers = CannabisMod.Timers
    local room, set = panels[panelKey], tiles[panelKey]
    if not (Timers and Timers.adoptRoom and room and set) then return 0 end
    local schedule = nil
    if room.schedule ~= "24/0" then schedule = room.schedule end
    local freed = Timers.adoptRoom(set, schedule, Rooms.contents(panelKey).lampTiles)
    if freed > 0 then
        if player then
            CannabisMod.Farming.giveItems(player, Config.Timer.ITEM, freed)
        else
            local square = getCell():getGridSquare(room.x, room.y, room.z)
            if square then
                for _ = 1, freed do pcall(square.AddWorldInventoryItem, square, Config.Timer.ITEM, 0.5, 0.5, 0) end
            end
        end
    end
    return freed
end

--- Work out every room's tiles again from the saved panels.
function Rooms.rebuild(blocked)
    tileRoom, tiles, openings = {}, {}, {}
    tileList, bounds, contents, shapeDirty = {}, {}, {}, {}
    roomsVersion = roomsVersion + 1
    contentsVersion = contentsVersion + 1
    if not panels then return end
    lastShapeAt = getGameTime():getWorldAgeHours()
    local cell = getCell()
    local gone = {}
    for key, panel in pairs(panels) do
        local square = cell:getGridSquare(panel.x, panel.y, panel.z)
        if square and not panelOn(square) then
            gone[#gone + 1] = key
        elseif square then
            local set, _, _, list = Rooms.fill(square, blocked)
            setRoomTiles(key, set, list)
            for tileKey in pairs(set) do tileRoom[tileKey] = key end
            openings[key] = Rooms.findOpenings(set, list)
            Rooms.sync(key)
        end
    end
    for _, key in ipairs(gone) do panels[key] = nil end
end

--- The ten-minute room pass: refill only rooms marked by a nearby change (all of them every few hours), drop rooms whose
--- panel went, and read every room's doors and windows again. Lamp schedules are handed out by Rooms.tick.
function Rooms.refresh(blocked)
    if not panels then return end
    local now = getGameTime():getWorldAgeHours()
    if not lastShapeAt or now - lastShapeAt >= Rooms.SHAPE_SAFETY_HOURS or now < lastShapeAt then
        return Rooms.rebuild(blocked)
    end
    local cell = getCell()
    local gone, changed = {}, false
    for key, panel in pairs(panels) do
        local square = cell:getGridSquare(panel.x, panel.y, panel.z)
        if square and not panelOn(square) then
            gone[#gone + 1] = key
        elseif not square then
            if tiles[key] then dropRoomTiles(key) changed = true end
        elseif shapeDirty[key] or not tiles[key] then
            local set, _, _, list = Rooms.fill(square, blocked)
            setRoomTiles(key, set, list)
            changed = true
        end
    end
    for _, key in ipairs(gone) do
        panels[key] = nil
        dropRoomTiles(key)
        changed = true
    end
    shapeDirty = {}
    if changed then rebuildTileRoom() end
    openings = {}
    for key, set in pairs(tiles) do openings[key] = Rooms.findOpenings(set, tileList[key]) end
end

--- Mark the rooms near a tile for refilling: on or beside their tiles, on their floor or the one above (a roof).
local function markNear(x, y, z)
    for key, b in pairs(bounds) do
        if (z == b.z or z == b.z + 1) and x >= b.x1 - 1 and x <= b.x2 + 1 and y >= b.y1 - 1 and y <= b.y2 + 1 then
            shapeDirty[key] = true
        end
    end
end

--- A wall, door, floor or anything else changed at an object's square.
local function objectChanged(obj)
    -- Nothing to do while no room is built (the loop body runs at most once).
    for _ in pairs(bounds) do
        local square = obj.getSquare and obj:getSquare()
        if square then markNear(square:getX(), square:getY(), square:getZ()) end
        return
    end
end

World.onAnyObjectAdded("room shape", objectChanged)
World.onAnyObjectRemoved("room shape", objectChanged)
if Events.OnTileRemoved then Events.OnTileRemoved.Add(function(obj) pcall(objectChanged, obj) end) end
-- A square loading on or beside a room may widen a room that was cut short by unloaded ground.
World.onSquareLoad("room shape", function(square)
    for _ in pairs(bounds) do
        if square.getX then markNear(square:getX(), square:getY(), square:getZ()) end
        return
    end
end, true)
-- Anything of ours placed or taken away means a room's contents must be read again.
local function contentsChanged() contentsVersion = contentsVersion + 1 end
World.onObjectAdded("room contents", contentsChanged)
World.onObjectRemoved("room contents", contentsChanged)

--- The room record covering a tile, or nil.
function Rooms.roomAt(x, y, z)
    local key = tileRoom[Config.tileKey(x, y, z)]
    return key and panels[key] or nil
end

--- The panel key a tile belongs to, or nil.
function Rooms.keyAt(x, y, z)
    return tileRoom[Config.tileKey(x, y, z)]
end

--- Add a line to a room's log, keeping only the newest few.
function Rooms.log(room, text, now)
    room.log = room.log or {}
    room.log[#room.log + 1] = { t = now or getGameTime():getWorldAgeHours(), text = text }
    while #room.log > Config.Rooms.LOG_KEEP do table.remove(room.log, 1) end
end

--- Add a log line to the room covering a tile (by tile key), if any room does.
function Rooms.logTile(key, text, now)
    local pk = key and tileRoom[key]
    local room = pk and panels[pk]
    if room then Rooms.log(room, text, now) end
end

--- Whether a room's panel has power on its square; a debug power cut counts as none.
function Rooms.panelPowered(room, square)
    if room.debugCut then return false end
    return square ~= nil and CannabisMod.Light.isPowered(square) == true
end

--- Whether the room covering a tile has power at its panel: nil when no room covers it, false during an outage.
function Rooms.poweredAt(x, y, z)
    local room = Rooms.roomAt(x, y, z)
    if not room then return nil end
    local square = getCell():getGridSquare(room.x, room.y, room.z)
    if square then return Rooms.panelPowered(room, square) end
    return room.powered ~= false
end

--- True when the panel of the room covering a tile holds a flood timer for every flood reservoir in it.
function Rooms.floodTimerAt(x, y, z)
    local room = Rooms.roomAt(x, y, z)
    return room ~= nil and room.floodTimer == true
end

--- The temperature and humidity of the room covering a tile, or nil outside a room or with room climate switched off.
function Rooms.climateAt(x, y, z)
    local room = Rooms.roomAt(x, y, z)
    if not room or room.temp == nil or not Config.sandbox("RoomClimate") then return nil end
    return room.temp, room.hum
end

--- The tile set of a room by its panel key.
function Rooms.tilesOf(panelKey) return tiles[panelKey] end

--- The tiles of a room as a list of { x, y, z, key }, or nil.
function Rooms.tileListOf(panelKey) return tileList[panelKey] end

--- For a lamp tile: whether a grow room rules it, and the schedule it runs (nil for 24/0).
function Rooms.scheduleAt(x, y, z)
    local room = Rooms.roomAt(x, y, z)
    if not room then return false, nil end
    if room.schedule == "24/0" then return true, nil end
    return true, room.schedule
end

--- Place a panel at a square. Returns true and how many lamp timers were handed back, or false and the reason (another panel already rules this room).
function Rooms.register(square, player, blocked)
    local key = Config.tileKey(square:getX(), square:getY(), square:getZ())
    if panels[key] then return false, "There is already a panel here" end
    if square:isOutside() then return false, "A grow room panel needs an indoor room" end
    local set, _, _, list = Rooms.fill(square, blocked)
    for otherKey, other in pairs(panels) do
        if set[otherKey] then
            return false, "This room already has a panel at " .. other.x .. ", " .. other.y
        end
    end
    panels[key] = {
        x = square:getX(), y = square:getY(), z = square:getZ(),
        name = "Grow Room", schedule = Config.Rooms.DEFAULT_SCHEDULE, mode = Config.Rooms.DEFAULT_MODE,
    }
    setRoomTiles(key, set, list)
    for tileKey in pairs(set) do tileRoom[tileKey] = key end
    roomsVersion = roomsVersion + 1
    openings[key] = Rooms.findOpenings(set, list)
    return true, Rooms.sync(key, player)
end

--- Take a panel away: its lamps go back to their own behaviour (24/0 until a timer is fitted again).
function Rooms.remove(panelKey)
    if not panels[panelKey] then return false end
    for tileKey in pairs(tiles[panelKey] or {}) do tileRoom[tileKey] = nil end
    roomsVersion = roomsVersion + 1
    dropRoomTiles(panelKey)
    panels[panelKey] = nil
    return true
end

--- True when the player may use the panel: vanilla safehouse rules, or free use outside a safehouse.
function Rooms.canUse(player, room)
    local ok, allowed = pcall(function()
        local safe = SafeHouse and SafeHouse.getSafeHouse(getCell():getGridSquare(room.x, room.y, room.z))
        if not safe then return true end
        return safe:playerAllowed(player)
    end)
    return not ok or allowed == true
end

--- Clean a typed room name: trimmed, limited in length, never empty.
function Rooms.cleanName(text)
    text = tostring(text or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    if #text == 0 then return "Grow Room" end
    return text:sub(1, Config.Rooms.NAME_MAX)
end

--- The panel a player is acting on: close enough, a real panel, and allowed to use it.
local function panelFor(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z and panels) then return nil end
    local key = Config.tileKey(x, y, z)
    local room = panels[key]
    if not room then
        Net.notify(player, "This panel has no grow room on record. Pick it up and place it again")
        return nil
    end
    -- The panel window stays open while you walk the room, so anywhere in the room counts, not just beside the panel.
    local here = Config.tileKey(math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ()))
    if not isNear(player, x, y, z) and tileRoom[here] ~= key then
        Net.notify(player, "Walk back into the grow room to use its panel")
        return nil
    end
    if not Rooms.canUse(player, room) then
        Net.notify(player, "This grow room belongs to someone else's safehouse")
        return nil
    end
    return room
end

commands.roomSetSchedule = function(player, args)
    local room = panelFor(player, args)
    local valid = false
    for _, s in ipairs(Config.Rooms.SCHEDULES) do if s == args.schedule then valid = true end end
    if not room or not valid then return end
    room.schedule = args.schedule
    Rooms.log(room, "Lights set to " .. args.schedule)
    Rooms.sync(Config.tileKey(room.x, room.y, room.z), player)
    Net.notify(player, room.name .. " lights set to " .. args.schedule)
    commands.requestRoom(player, args)
end

--- Debug: cut or restore a grow room's power at its panel, to test outages without touching the grid.
commands.debugRoomPower = function(player, args)
    if not (isDebugEnabled() or (player.getAccessLevel and player:getAccessLevel() ~= "None")) then return end
    local room = panelFor(player, args)
    if not room then return end
    local key = Config.tileKey(room.x, room.y, room.z)
    room.debugCut = args.cut == true or nil
    local square = getCell():getGridSquare(room.x, room.y, room.z)
    local panel = square and Rooms.panelObject(square)
    if panel then
        panel:getModData().DDPowerCut = room.debugCut
        pcall(panel.transmitModData, panel)
    end
    Rooms.checkPower(room, square, tiles[key] or {}, getGameTime():getWorldAgeHours(), getGameTime():getHour(), false,
        tiles[key] and Rooms.contents(key).lampTiles or nil)
    Net.notify(player, room.name .. (room.debugCut and ": power cut (debug)" or ": power back (debug)"))
    commands.requestRoom(player, args)
end

commands.roomSetMode = function(player, args)
    local room = panelFor(player, args)
    local valid = false
    for _, m in ipairs(Config.Rooms.MODES) do if m == args.mode then valid = true end end
    if not room or not valid then return end
    room.mode = args.mode
    Rooms.log(room, "Mode set to " .. args.mode)
    Net.notify(player, room.name .. " set to " .. args.mode)
    commands.requestRoom(player, args)
end

commands.roomRename = function(player, args)
    local room = panelFor(player, args)
    if not room then return end
    room.name = Rooms.cleanName(args.name)
    Rooms.log(room, "Renamed to " .. room.name)
    commands.requestRoom(player, args)
end

--- The online player nearest a tile, or nil (used to tell someone their panel was refused).
local function nearestPlayer(x, y, z)
    local best, bestDist = nil, 1e9
    local function consider(p)
        if p and math.floor(p:getZ()) == z then
            local d = math.abs(p:getX() - x) + math.abs(p:getY() - y)
            if d < bestDist then best, bestDist = p, d end
        end
    end
    if getOnlinePlayers then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do consider(list:get(i)) end
    elseif getPlayer then
        consider(getPlayer())
    end
    return best
end

--- A panel object was placed: register it, or take it back down and hand the item over when the room already has one.
function Rooms.onPlaced(obj)
    local square = obj:getSquare()
    if not square then return end
    local key = Config.tileKey(square:getX(), square:getY(), square:getZ())
    if panels[key] then return end
    local ok, why = Rooms.register(square, nil)
    if ok then return end
    pcall(square.RemoveTileObject, square, obj)
    pcall(square.transmitRemoveItemFromSquare, square, obj)
    pcall(square.AddWorldInventoryItem, square, "CannabisMod.GrowRoomPanel", 0.5, 0.5, 0)
    local player = nearestPlayer(square:getX(), square:getY(), square:getZ())
    if player then Net.notify(player, why) end
end

--- A panel the save kept without its room record (a crash between saves) is registered again; true when it was.
function Rooms.adoptPanel(obj)
    if not panels or not isPanelObject(obj) then return false end
    local square = obj:getSquare()
    if not square or panels[Config.tileKey(square:getX(), square:getY(), square:getZ())] then return false end
    return (Rooms.register(square, nil)) == true
end

World.onObjectAdded("panel placing", function(obj, name, info)
    if info.panel then Rooms.onPlaced(obj) end
end)

-- Every tile of a bar lamp, shared with the light timers.
local lampTiles = World.lampSquares

--- What a room holds, read in one pass over its tiles and shared by every reader at the same game moment:
--- lamps (every lamp object), lampTiles (the first lamp on each tile), gear (with each fan's wall factor), racks
--- (rack containers) and special[tileKey] = { control, flood, drip } for reservoir objects. `fresh` forces a new read.
function Rooms.contents(panelKey, fresh)
    local c = contents[panelKey]
    local now = getGameTime():getWorldAgeHours()
    if c and not fresh and c.at == now and c.version == contentsVersion then return c end
    c = { at = now, version = contentsVersion, lamps = {}, lampTiles = {}, gear = {}, racks = {}, special = {} }
    contents[panelKey] = c
    local list = tileList[panelKey]
    if not list then return c end
    local cell, info = getCell(), World.info
    local lamps, lampTilesOut, gear, racks, special = c.lamps, c.lampTiles, c.gear, c.racks, c.special
    for _, t in ipairs(list) do
        local square = cell:getGridSquare(t.x, t.y, t.z)
        if square then
            local objects = square:getObjects()
            local firstLamp = false
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                local sprite = obj:getSprite()
                local what = sprite and info(sprite:getName())
                if what then
                    if what.lamp then
                        lamps[#lamps + 1] = { square = square, obj = obj, def = what.lamp, t = t }
                        if not firstLamp then
                            firstLamp = true
                            lampTilesOut[#lampTilesOut + 1] = { square = square, obj = obj, t = t }
                        end
                    end
                    local g = what.gear
                    if g then
                        gear[#gear + 1] = { square = square, gear = g, t = t, factor = g.facing and Rooms.wallFactor(square, g.facing) or nil }
                    end
                    if what.rack then
                        local container = obj:getContainer()
                        if container then racks[#racks + 1] = container end
                    end
                    if what.control or what.flood or what.drip then
                        local sp = special[t.key]
                        if not sp then sp = {} special[t.key] = sp end
                        sp.control = sp.control or what.control
                        sp.flood = sp.flood or what.flood
                        sp.drip = sp.drip or what.drip
                    end
                end
            end
        end
    end
    return c
end

--- What the panel window shows: the room's settings, its size and every lamp in it.
function Rooms.info(panelKey, player)
    local room, set = panels[panelKey], tiles[panelKey]
    if not (room and set) then return nil end
    local cell = getCell()
    local hour = getGameTime():getHour()
    local schedule = nil
    if room.schedule ~= "24/0" then schedule = room.schedule end
    local lamps, counted = {}, {}
    local count = #(tileList[panelKey] or {})
    for _, l in ipairs(Rooms.contents(panelKey).lamps) do
        local t, square = l.t, l.square
        -- A bar lamp spans several tiles; list it once, at the first tile we reach.
        if not counted[t.key] then
            for _, member in ipairs(lampTiles(square, l.obj)) do
                counted[Config.tileKey(member:getX(), member:getY(), member:getZ())] = true
            end
            local powered = CannabisMod.Light.isPowered(square) and not room.debugCut
            lamps[#lamps + 1] = {
                name = l.def.name, x = t.x, y = t.y, z = t.z,
                powered = powered, lit = powered and Config.Timer.isOn(schedule, hour),
            }
        end
    end
    table.sort(lamps, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local panelSquare = cell:getGridSquare(room.x, room.y, room.z)
    -- Cold nights is worked out fresh, so the panel is right even straight after a mode or setting change.
    local now = getGameTime():getWorldAgeHours()
    local coldArmed = Rooms.coldNightsArmed(room, Rooms.plantsIn(panelKey), now)
    local coldActive = coldArmed and Rooms.isNight(room, hour)
    local coldNights = nil
    if Rooms.coldNightsAvailable(room) then
        local K = Config.Climate
        coldNights = { state = Rooms.coldNightsState(room), armed = coldArmed, active = coldActive,
            nightLo = K.COLD_NIGHT.tLo, nightHi = K.COLD_NIGHT.tHi }
    end
    return {
        x = room.x, y = room.y, z = room.z, name = room.name, schedule = room.schedule, mode = room.mode,
        tiles = count, lamps = lamps, hour = hour, openings = Rooms.openingsOf(panelKey),
        reservoirs = Rooms.reservoirRows(panelKey), equipment = Rooms.equipmentRows(panelKey), floodTimer = room.floodTimer == true,
        plants = Rooms.plantRows(panelKey, player and CannabisMod.ServerCommands.agricultureLevel(player) or 0, CannabisMod.Traits.reading(player)),
        log = room.log or {}, now = getGameTime():getWorldAgeHours(),
        powered = Rooms.panelPowered(room, panelSquare), debugCut = room.debugCut == true,
        climate = {
            enabled = Config.sandbox("RoomClimate") == true,
            temp = room.temp, hum = room.hum, outT = room.outT, outH = room.outH,
            targets = CannabisMod.Climate.targetsFor(room.mode, room.young == true, coldActive),
            present = room.present or {}, running = room.running or {},
            override = room.override or {}, notes = room.notes or {}, coldNights = coldNights,
        },
    }
end

--- Every hydro reservoir in a room as live records: { key, record, name }, nearest the panel first.
function Rooms.reservoirRecords(panelKey)
    local Hydro, Registry = CannabisMod.Hydro, CannabisMod.Registry
    local set, room = tiles[panelKey], panels[panelKey]
    local out = {}
    if not (Hydro and set and room) then return out end
    -- Control buckets, flood reservoirs and drip tanks come from the room's contents; DWC buckets from the bag records.
    local special = Rooms.contents(panelKey).special
    for _, t in ipairs(tileList[panelKey] or {}) do
        local x, y, z, key = t.x, t.y, t.z, t.key
        local r, name
        local bag = Registry.hasBagAt(x, y, z) and Registry.getBag(x, y, z) or nil
        local sp = special[key]
        if Config.hydroOf(bag) == "dwc" then r, name = Hydro.reservoirAt(x, y, z, "dwc"), (bag == "xldwc" and "XL DWC bucket" or "DWC bucket")
        elseif sp and sp.control then r, name = Hydro.reservoirOfObject(x, y, z, "rdwc"), "RDWC control"
        elseif sp and sp.flood then r, name = Hydro.reservoirOfObject(x, y, z, "ebb"), "Flood reservoir"
        elseif sp and sp.drip and Hydro.hasDrip then r, name = Hydro.reservoirOfObject(x, y, z, "drip"), "Drip tank" end
        if r then out[#out + 1] = { key = key, record = r, name = name, dist = math.abs(x - room.x) + math.abs(y - room.y) } end
    end
    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.key < b.key
    end)
    return out
end

--- A reservoir in the same room as `r` that has its own Dazed Plumbing line, so the room's line can refill `r`; nil when there is none.
function Rooms.lineFeeder(r)
    local pk = tileRoom[Config.tileKey(r.x, r.y, r.z)]
    if not pk then return nil end
    for _, e in ipairs(Rooms.reservoirRecords(pk)) do
        local o = e.record
        if o ~= r and CannabisMod.Plumbing.isPlumbedAt(o.x, o.y, o.z) then return o end
    end
    return nil
end

--- Mark `r` as waiting on its room's water line after a change.
function Rooms.waitOnLine(r)
    local pk = tileRoom[Config.tileKey(r.x, r.y, r.z)]
    local room = pk and panels[pk]
    if not room then return end
    room.lineWaiting = room.lineWaiting or {}
    room.lineWaiting[Config.tileKey(r.x, r.y, r.z)] = r.kind
end

--- True if `r` is waiting on its room's water line.
function Rooms.isWaitingOnLine(r)
    local pk = tileRoom[Config.tileKey(r.x, r.y, r.z)]
    local room = pk and panels[pk]
    return room ~= nil and room.lineWaiting ~= nil and room.lineWaiting[Config.tileKey(r.x, r.y, r.z)] ~= nil
end

--- The reservoirs a plumbed reservoir's line also refills: the others in its room still waiting on the room's line.
function Rooms.lineDependents(r)
    local pk = tileRoom[Config.tileKey(r.x, r.y, r.z)]
    local room = pk and panels[pk]
    local out = {}
    if not (room and room.lineWaiting) then return out end
    local Hydro = CannabisMod.Hydro
    for key, kind in pairs(room.lineWaiting) do
        local x, y, z = Config.parseKey(key)
        local o = Hydro.reservoirAt(x, y, z, kind)
        if o and o ~= r and o.fillPending then
            out[#out + 1] = o
        else
            room.lineWaiting[key] = nil
        end
    end
    return out
end

--- The reservoir rows the Hydro tab shows.
function Rooms.reservoirRows(panelKey)
    local Hydro, Registry = CannabisMod.Hydro, CannabisMod.Registry
    local now = Registry.nowHours()
    local rows = {}
    for _, e in ipairs(Rooms.reservoirRecords(panelKey)) do
        local r = e.record
        rows[#rows + 1] = {
            key = e.key, name = e.name, x = r.x, y = r.y, z = r.z, kind = r.kind,
            level = r.level, cap = Hydro.capacity(r), strength = r.strength, nutrient = r.nutrient,
            rot = r.rot, tainted = r.tainted == true, pump = Hydro.pumpState(r) == true,
            age = now - (r.changedAt or now), plants = #Hydro.servedPlants(r),
        }
    end
    return rows
end

--- The rows of the Equipment tab: every fan, heater, dehumidifier and humidifier in the room, nearest the panel first.
function Rooms.equipmentRows(panelKey)
    local room, set = panels[panelKey], tiles[panelKey]
    local rows = {}
    if not (room and set) then return rows end
    local Light = CannabisMod.Light
    local running, override = room.running or {}, room.override or {}
    local panelPowered = room.powered ~= false
    local WALLS = { S = "north wall", E = "west wall", N = "south wall", W = "east wall" }
    for _, g in ipairs(Rooms.contents(panelKey).gear) do
        local gear, t = g.gear, g.t
        local side = gear.facing or gear.wall
        local powered = panelPowered and Light.isPowered(g.square)
        rows[#rows + 1] = {
            x = t.x, y = t.y, z = t.z, kind = gear.kind, name = gear.name,
            mount = side and WALLS[side] or "floor", powered = powered,
            running = powered and running[gear.kind] == true, mode = override[gear.kind] or "auto",
        }
    end
    table.sort(rows, function(a, b)
        local da = math.abs(a.x - room.x) + math.abs(a.y - room.y)
        local db = math.abs(b.x - room.x) + math.abs(b.y - room.y)
        if da ~= db then return da < db end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return rows
end

--- The rows of the Plants tab: each plant in the room, with only what the viewer's Agriculture level lets them read.
function Rooms.plantRows(panelKey, level, reading)
    local Registry, Info = CannabisMod.Registry, CannabisMod.Info
    local set = tiles[panelKey]
    local rows = {}
    if not set then return rows end
    local now = Registry.nowHours()
    for _, plant in ipairs(plantsByRoom()[panelKey] or {}) do
        if not plant.dead then
            local d = Info.buildVisible(plant, level, now, reading)
            local water = d.water
            if type(water) == "number" then water = string.format("%d%%", water) end
            -- Cold nights slowing a plant is chosen, not a fault, so it isn't counted as a warning on the card.
            local warnings = 0
            for _, w in ipairs(d.warnings or {}) do if w ~= "coldNight" then warnings = warnings + 1 end end
            rows[#rows + 1] = {
                x = plant.x, y = plant.y, z = plant.z, name = d.name or "Cannabis Plant",
                stage = d.stage or d.stageRough or "?", water = water or d.waterRough or "?",
                health = d.healthBand, type = d.type, warnings = warnings,
                strain = d.strain, sex = d.sex, looks = d.looks, stageKey = d.stage,
            }
            -- Cold night hours toward purple, for flowering and ripe females, read at the same level as the strain.
            if d.strain and plant.sex == Config.SEX.FEMALE and plant.stage >= Config.STAGE.Flowering then
                rows[#rows].cold = { hours = plant.coldNightHours or 0, need = Config.Weather.PURPLE_HOURS,
                    rolled = plant.purpleRolled == true, purple = plant.purple == true }
            end
            -- The plant's sprites, so the dashboard card can show it as it stands.
            pcall(function()
                local plot = SFarmingSystem.instance:getLuaObjectAt(plant.x, plant.y, plant.z)
                if plot and CannabisMod.PotPlants then
                    local sprite, bag = CannabisMod.PotPlants.wanted(plot)
                    local row = rows[#rows]
                    row.sprite, row.pot, row.lift = sprite, plot.spriteName, bag and Config.PLANT_LIFT[bag] or 0
                end
            end)
        end
    end
    table.sort(rows, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return rows
end

local HYDRO_DONE = { topUp = "Topped up", change = "Drained", bleach = "Treated" }
local HYDRO_VERB = { topUp = "Topped up", change = "Changed", bleach = "Treated with bleach", dose = "Dosed" }

commands.roomHydro = function(player, args)
    local room = panelFor(player, args)
    local action = args.action
    if not room or not (HYDRO_VERB[action]) then return end
    local panelKey = Config.tileKey(room.x, room.y, room.z)
    local Hydro = CannabisMod.Hydro
    local targets = {}
    for _, e in ipairs(Rooms.reservoirRecords(panelKey)) do
        if args.target == "all" or args.target == e.key then targets[#targets + 1] = e end
    end
    if #targets == 0 then return end
    local nutrient = args.nutrient
    local itemType = Config.NUTRIENT_ITEMS[nutrient]
    if action == "dose" and not itemType then return end
    local done, last = 0, nil
    for _, e in ipairs(targets) do
        local r = e.record
        local say = function(text) last = text end
        if action == "dose" then
            if r.level > 0 then
                local bottle = CannabisMod.Seeds.findItem(player:getInventory(), function(item) return item:getFullType() == itemType end)
                if not bottle then last = "You have no " .. nutrient .. " nutrients" break end
                local container = bottle:getContainer()
                if container then
                    container:Remove(bottle)
                    sendRemoveItemFromContainer(container, bottle)
                end
                Hydro.dose(r, nutrient)
                done = done + 1
            else
                last = "The reservoir is empty: top it up first"
            end
        else
            Hydro[action](player, r, say)
            if last and last:sub(1, #HYDRO_DONE[action]) == HYDRO_DONE[action] then done = done + 1 end
        end
    end
    if #targets == 1 then
        Net.notify(player, last or "Done")
    else
        Net.notify(player, string.format("%s %d of %d reservoirs", HYDRO_VERB[action], done, #targets))
    end
    Rooms.log(room, string.format("%s %d of %d reservoirs", HYDRO_VERB[action], done, #targets))
    commands.requestRoom(player, args)
end

commands.roomFloodTimer = function(player, args)
    local room = panelFor(player, args)
    if not room then return end
    local itemType = Config.Hydro.FLOOD_TIMER_ITEM
    if args.mode == "install" and not room.floodTimer then
        local item = player:getInventory():getFirstTypeRecurse(itemType)
        if not item then Net.notify(player, "You need a flood timer") return end
        local container = item:getContainer()
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
        room.floodTimer = true
        Rooms.log(room, "Flood timer fitted to the panel")
        Net.notify(player, "Flood timer fitted: every flood reservoir in the room runs on it")
    elseif args.mode == "remove" and room.floodTimer then
        room.floodTimer = nil
        CannabisMod.Farming.giveItems(player, itemType, 1)
        Rooms.log(room, "Flood timer taken off the panel")
        Net.notify(player, "Flood timer removed")
    end
    commands.requestRoom(player, args)
end

commands.roomInspectPlant = function(player, args)
    local room = panelFor(player, args)
    if not room then return end
    local set = tiles[Config.tileKey(room.x, room.y, room.z)]
    local px, py, pz = tonumber(args.px), tonumber(args.py), tonumber(args.pz)
    if not (px and py and pz and set and set[Config.tileKey(px, py, pz)]) then return end
    CannabisMod.ServerCommands.sendPlantInfo(player, px, py, pz)
end

commands.requestRoom = function(player, args)
    local room = panelFor(player, args)
    if not room then return end
    local info = Rooms.info(Config.tileKey(room.x, room.y, room.z), player)
    if info then Net.toPlayer(player, "roomInfo", info) end
end

-- --------------------------------------------------------------------------
-- Climate
-- --------------------------------------------------------------------------

--- Outdoor temperature (C) and humidity (%): DazedCore's or the climate manager's readings, with plain fallbacks when the game API differs.
function Rooms.outdoor()
    local h = 60
    local t = CannabisMod.Weather.outdoor() or 15
    local found = false
    pcall(function()
        local v = getClimateManager():getHumidity()
        if type(v) == "number" then
            if v <= 1.5 then v = v * 100 end
            h, found = v, true
        end
    end)
    if not found then
        pcall(function()
            local c = getClimateManager()
            h = 45 + 25 * c:getCloudIntensity() + 30 * c:getRainIntensity()
        end)
    end
    return { t = t, h = Config.clamp(h, 5, 100) }
end

-- A fan faces into the room: the square on the far side of the wall it hangs on is one step the other way.
local FAN_WALL = { S = { 0, -1 }, E = { -1, 0 }, N = { 0, 1 }, W = { 1, 0 } }

--- How much air a fan on this square moves: full on an outside wall, a quarter on a wall to another indoor space.
function Rooms.wallFactor(square, facing)
    local off = FAN_WALL[facing]
    if not off then return 1 end
    local far = getCell():getGridSquare(square:getX() + off[1], square:getY() + off[2], square:getZ())
    if not far or far:isOutside() then return 1 end
    return Config.Climate.INSIDE_WALL_FACTOR
end

--- What a room holds that shapes its air: lamp heat, equipment by kind (count and fan air), wet plants on racks and reservoirs holding water.
function Rooms.scan(panelKey)
    local room, set = panels[panelKey], tiles[panelKey]
    local K = Config.Climate
    local out = { lampHeat = 0, count = {}, vent = { exhaust = 0, intake = 0 }, wet = 0, reservoirs = 0 }
    if not (room and set) then return out end
    local Light, Drying = CannabisMod.Light, CannabisMod.Drying
    local hour = getGameTime():getHour()
    local schedule = nil
    if room.schedule ~= "24/0" then schedule = room.schedule end
    local panelPowered = room.powered ~= false
    local c = Rooms.contents(panelKey)
    for _, l in ipairs(c.lamps) do
        local lamp = l.def
        if panelPowered and Light.isPowered(l.square) and Config.Timer.isOn(schedule, hour) then
            -- A bar lamp is one lamp over several tiles, so each tile gives its share.
            out.lampHeat = out.lampHeat + lamp.radius * K.LAMP_HEAT_PER_RADIUS / (lamp.tiles or 1)
        end
    end
    for _, g in ipairs(c.gear) do
        local gear = g.gear
        out.count[gear.kind] = (out.count[gear.kind] or 0) + 1
        if gear.facing then out.vent[gear.kind] = out.vent[gear.kind] + g.factor * K.VENT[gear.kind] end
    end
    if Drying then
        for _, rack in ipairs(c.racks) do out.wet = out.wet + Drying.wetCountIn(rack) end
    end
    for _, e in ipairs(Rooms.reservoirRecords(panelKey)) do
        if e.record.level > 0 then out.reservoirs = out.reservoirs + 1 end
    end
    return out
end

--- The living plants standing in one room.
function Rooms.plantsIn(panelKey)
    local list = {}
    if not tiles[panelKey] then return list end
    for _, plant in ipairs(plantsByRoom()[panelKey] or {}) do
        if not plant.dead then list[#list + 1] = plant end
    end
    return list
end

-- Cold nights: a Flower room setting that holds the lights-off hours cool in late flower to bring out purple.
-- The room record keeps coldNights ("off", "auto" or "on"; missing is off) and coldArmed for the arming log line.
Rooms.COLD_NIGHTS = { off = "Off", auto = "Late flower", on = "On" }

--- True when a room can run Cold nights: Flower mode, with purple buds and room climate switched on.
function Rooms.coldNightsAvailable(room)
    return room ~= nil and room.mode == "Flower" and Config.sandbox("PurpleBuds") == true and Config.sandbox("RoomClimate") == true
end

--- The stored Cold nights setting, "off" when it is missing or unknown (old saves).
function Rooms.coldNightsState(room)
    local s = room and room.coldNights
    if s == "auto" or s == "on" then return s end
    return "off"
end

--- True when a plant counts for the Late flower setting: living, rooted, female and in late flower.
local function coldNightPlant(plant, now)
    local PT = CannabisMod.PlantTemp
    return PT ~= nil and not plant.dead and not plant.rooting and plant.sex == Config.SEX.FEMALE and PT.lateFlower(plant, now)
end

--- True when Cold nights is armed: always on "on", and on "auto" while a plant in the room is in late flower.
--- A room that can't run it (not Flower mode, or the sandbox options off) is never armed, whatever is stored.
function Rooms.coldNightsArmed(room, plants, now)
    if not Rooms.coldNightsAvailable(room) then return false end
    local s = Rooms.coldNightsState(room)
    if s == "on" then return true end
    if s ~= "auto" then return false end
    now = now or getGameTime():getWorldAgeHours()
    for _, p in ipairs(plants or {}) do
        if coldNightPlant(p, now) then return true end
    end
    return false
end

--- True in a room's lights-off hours: its timer's dark hours, or the clock's night when its lamps run 24/0 (as PlantTemp.isNight).
function Rooms.isNight(room, hour)
    local schedule = room and room.schedule
    if schedule and Config.Timer.SCHEDULES[schedule] then return not Config.Timer.isOn(schedule, hour) end
    return CannabisMod.Weather.isNight(hour)
end

--- Rooms.isNight for the room covering a tile; nil when no room covers it.
function Rooms.isNightAt(x, y, z, hour)
    local room = Rooms.roomAt(x, y, z)
    if not room then return nil end
    return Rooms.isNight(room, hour)
end

--- One ten-minute step of the Cold nights cost: while `active`, flowering females ripen COLD_NIGHT_SLOW slower and carry a warning.
--- Ripe plants, males, rooting cuttings and plants whose clock a light stall already holds are left alone.
function Rooms.coldNightCost(plants, active)
    local slow = Config.Weather.COLD_NIGHT_SLOW / 6
    for _, p in ipairs(plants or {}) do
        local hit = active and p.stage == Config.STAGE.Flowering and p.sex == Config.SEX.FEMALE and not p.rooting and not p.lightStalled
        if hit and p.nextStageAt then p.nextStageAt = p.nextStageAt + slow end
        if hit or (p.warnings and p.warnings.coldNight) then
            p.warnings = p.warnings or {}
            p.warnings.coldNight = hit or nil
        end
    end
end

--- Work out a room's air and equipment. With `advance` the air moves a step and the plants feel it; without, only the equipment states are refreshed (after a manual override).
function Rooms.updateClimate(panelKey, plants, outdoor, advance, now)
    local room = panels[panelKey]
    if not room then return end
    local Climate, K = CannabisMod.Climate, Config.Climate
    plants = plants or {}
    local seedlings, flowering, growing = 0, 0, 0
    for _, p in ipairs(plants) do
        if p.stage < Config.STAGE.Vegetative then seedlings = seedlings + 1 end
        if p.stage >= Config.STAGE.Flowering then flowering = flowering + 1 else growing = growing + 1 end
    end
    local young = seedlings > 0 and room.mode ~= "Drying"
    room.young = young or nil
    now = now or getGameTime():getWorldAgeHours()
    -- While Cold nights is armed, the lights-off hours work to the cold band instead of the Flower range.
    local coldArmed = Rooms.coldNightsArmed(room, plants, now)
    local coldNight = coldArmed and Rooms.isNight(room, getGameTime():getHour())
    room.coldActive = coldNight or nil
    local targets = Climate.targetsFor(room.mode, young, coldNight)
    room.notes = {}
    if not Config.sandbox("RoomClimate") then
        room.temp, room.hum = (targets.tLo + targets.tHi) / 2, (targets.hLo + targets.hHi) / 2
        room.running, room.present = {}, {}
        if advance then Rooms.coldNightCost(plants, false) end
        return
    end
    outdoor = outdoor or Rooms.outdoor()
    room.outT, room.outH = outdoor.t, outdoor.h
    room.temp = room.temp or outdoor.t
    room.hum = room.hum or outdoor.h
    local scan = Rooms.scan(panelKey)
    local present = {}
    for kind, n in pairs(scan.count) do if n > 0 then present[kind] = true end end
    local running = Climate.control(room, targets, present, room.override)
    if room.powered == false then running = {} end
    room.running, room.present = running, scan.count
    -- Mismatches between what the room is set up for and what is in it.
    if room.mode == "Drying" and #plants > 0 then room.notes[#room.notes + 1] = "Living plants are in a Drying room" end
    if room.mode ~= "Drying" and scan.wet > 0 then room.notes[#room.notes + 1] = "Wet plants are drying in a " .. room.mode .. " room: set Drying mode" end
    if room.mode == "Flower" and seedlings > 0 then room.notes[#room.notes + 1] = "Seedlings are in a Flower room: set Veg mode" end
    if not advance then return end
    -- Note the Late flower setting arming once, when the first plant reaches late flower.
    if coldArmed and not room.coldArmed and Rooms.coldNightsState(room) == "auto" then
        Rooms.log(room, "Cold nights armed: plants in late flower", now)
    end
    room.coldArmed = coldArmed or nil
    Rooms.coldNightCost(plants, coldNight)
    Climate.step(room, {
        outT = outdoor.t, outH = outdoor.h, lampHeat = scan.lampHeat,
        moisture = growing * K.PLANT_HUMIDITY.veg + flowering * K.PLANT_HUMIDITY.flower
            + scan.reservoirs * K.RESERVOIR_HUMIDITY + scan.wet * K.WET_PLANT_HUMIDITY,
        exhaust = running.exhaust and scan.vent.exhaust or 0,
        intake = running.intake and scan.vent.intake or 0,
        heater = running.heater and scan.count.heater or 0,
        humidifier = running.humidifier and scan.count.humidifier or 0,
        dehumidifier = running.dehumidifier and scan.count.dehumidifier or 0,
        cooler = running.cooler and scan.count.cooler or 0,
        circfan = running.circfan and scan.count.circfan or 0,
    })
    local hotNow, wetNow = false, false
    for _, p in ipairs(plants) do
        local stress, hot, wet = Climate.plantStress(room.temp, room.hum, p.stage >= Config.STAGE.Flowering)
        if stress > 0 then p.stress = Config.clamp((p.stress or 0) + stress, 0, Config.Stress.MAX) end
        p.warnings = p.warnings or {}
        p.warnings.roomTemp = hot or nil
        p.warnings.roomHumid = wet or nil
        hotNow = hotNow or hot
        wetNow = wetNow or wet
    end
    if hotNow then
        Rooms.noteOnce(panelKey, "temp", string.format("Plants stressed: the room is at %d C", math.floor(room.temp + 0.5)), now)
    end
    if wetNow then
        Rooms.noteOnce(panelKey, "humid", string.format("Mold risk: %d%% humidity with flowering plants", math.floor(room.hum + 0.5)), now)
    end
    for _, note in ipairs(room.notes) do Rooms.noteOnce(panelKey, note, note, now) end
end

commands.roomOverride = function(player, args)
    local room = panelFor(player, args)
    local kind, state = args.kind, args.state
    if not room or not Config.Rooms.EQUIPMENT_NAMES[kind] then return end
    if state ~= "on" and state ~= "off" and state ~= "auto" then return end
    room.override = room.override or {}
    if state == "auto" then room.override[kind] = nil else room.override[kind] = state end
    local key = Config.tileKey(room.x, room.y, room.z)
    Rooms.updateClimate(key, Rooms.plantsIn(key), nil, false)
    Rooms.log(room, Config.Rooms.EQUIPMENT_NAMES[kind] .. " set to " .. state)
    commands.requestRoom(player, args)
end

commands.roomColdNights = function(player, args)
    local room = panelFor(player, args)
    local state = args.state
    if not room or type(state) ~= "string" or not Rooms.COLD_NIGHTS[state] then return end
    -- Kept in every mode; outside a Flower room it simply does nothing until the room flowers again.
    room.coldNights = state
    local key = Config.tileKey(room.x, room.y, room.z)
    Rooms.updateClimate(key, Rooms.plantsIn(key), nil, false)
    Rooms.log(room, "Cold nights set to " .. Rooms.COLD_NIGHTS[state])
    commands.requestRoom(player, args)
end

--- Add stress to every flowering plant in a room for the lit hours its power cut cost.
local function outagePenalty(panelKey, litHours)
    local stress = math.min(Config.Rooms.OUTAGE_STRESS_CAP, litHours * Config.Rooms.OUTAGE_STRESS_PER_LIT_HOUR)
    if stress <= 0 then return 0 end
    local hit = 0
    for _, plant in ipairs(plantsByRoom()[panelKey] or {}) do
        if plant.stage == Config.STAGE.Flowering then
            plant.stress = Config.clamp((plant.stress or 0) + stress, 0, Config.Stress.MAX)
            hit = hit + 1
        end
    end
    return hit
end

--- Note a power loss or return at a room's panel, and switch its lamps' glow to match. `tick` counts a lit hour lost.
function Rooms.checkPower(room, square, set, now, hour, tick, lamps)
    local powered = Rooms.panelPowered(room, square)
    local schedule = nil
    if room.schedule ~= "24/0" then schedule = room.schedule end
    if not powered and room.powered ~= false then
        room.powered, room.outage = false, { since = now, litHours = 0 }
        Rooms.log(room, room.debugCut and "Power cut (debug)" or "Power lost", now)
    end
    if tick and not powered and room.outage and Config.Timer.isOn(schedule, hour) then
        room.outage.litHours = room.outage.litHours + 1 / 6
    end
    if powered and room.powered == false then
        local lit = room.outage and room.outage.litHours or 0
        local hit = 0
        if Config.sandbox("RoomPowerPenalty") then hit = outagePenalty(Config.tileKey(room.x, room.y, room.z), lit) end
        Rooms.log(room, string.format("Power restored: %.1f lit hours lost%s", lit, hit > 0 and (", " .. hit .. " flowering plants stressed") or ""), now)
        room.powered, room.outage = nil, nil
    end
    if CannabisMod.Timers and CannabisMod.Timers.markRoomPower then
        CannabisMod.Timers.markRoomPower(set, room.powered == false, lamps)
    end
end

--- Every ten minutes: notice power going and coming back, count the lit hours lost, and pass the state on to the lamps.
function Rooms.tick(now)
    now = now or getGameTime():getWorldAgeHours()
    local hour = getGameTime():getHour()
    local cell = getCell()
    local outdoor = Rooms.outdoor()
    for key, room in pairs(panels or {}) do
        local square = cell:getGridSquare(room.x, room.y, room.z)
        local set = tiles[key]
        if square and set then
            -- One fresh read of the room's contents serves the lamp schedules, the power marks and the climate scan.
            local c = Rooms.contents(key, true)
            Rooms.sync(key)
            Rooms.checkPower(room, square, set, now, hour, true, c.lampTiles)
            Rooms.updateClimate(key, Rooms.plantsIn(key), outdoor, true, now)
        end
    end
end

--- The curtain overlay object on a square for one wall edge, or nil.
local function curtainObject(square, dir)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if name and (name == Config.Rooms.CURTAIN_SPRITES.door[dir] or name == Config.Rooms.CURTAIN_SPRITES.window[dir]) then return obj end
    end
    return nil
end

-- Blackout curtains are retired, so there is no hangCurtain command; frames hung before keep the take-down path below.
commands.removeCurtain = function(player, args)
    local x, y, z, dir = tonumber(args.x), tonumber(args.y), tonumber(args.z), args.dir
    if not (x and y and z) or (dir ~= "N" and dir ~= "W") or not curtains or not isNear(player, x, y, z) then return end
    local edge = Rooms.edgeKey(x, y, z, dir)
    if not curtains[edge] then return end
    local square = getCell():getGridSquare(x, y, z)
    local obj = square and curtainObject(square, dir)
    if obj then
        pcall(square.RemoveTileObject, square, obj)
        pcall(square.transmitRemoveItemFromSquare, square, obj)
    end
    curtains[edge] = nil
    CannabisMod.Farming.giveItems(player, Config.Rooms.CURTAIN_ITEM, 1)
    Rooms.rebuild()
    Net.notify(player, "Blackout curtain taken down")
end

-- --------------------------------------------------------------------------
-- Retired blackout curtains: vanilla sheets do the job now, so old curtains are cleared out of saves.
-- --------------------------------------------------------------------------

--- True when an object is a blackout curtain overlay.
function Rooms.isCurtainObject(obj)
    local name = World.safeSpriteName(obj)
    return name ~= nil and World.CURTAINS[name] == true
end

--- Remove every curtain overlay on a square; returns how many went.
function Rooms.clearCurtainsOn(square)
    local found = {}
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if Rooms.isCurtainObject(obj) then found[#found + 1] = obj end
    end
    for _, obj in ipairs(found) do
        pcall(square.RemoveTileObject, square, obj)
        pcall(square.transmitRemoveItemFromSquare, square, obj)
    end
    if #found > 0 then Config.debugLog("removed " .. #found .. " retired blackout curtain(s) at " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ()) end
    return #found
end

--- Forget every hung curtain, so the frames count by their doors and vanilla sheets alone.
function Rooms.forgetCurtains()
    if not curtains then return 0 end
    local keys = {}
    for k in pairs(curtains) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do curtains[k] = nil end
    return #keys
end

--- Take every blackout curtain out of a player's inventory and bags; returns how many went.
function Rooms.clearCurtainItems(player)
    local inv = player and player:getInventory()
    if not inv then return 0 end
    local removed = 0
    for _ = 1, 200 do
        local item = inv:getFirstTypeRecurse(Config.Rooms.CURTAIN_ITEM)
        if not item then break end
        local container = item:getContainer()
        if not container then break end
        container:Remove(item)
        pcall(sendRemoveItemFromContainer, container, item)
        removed = removed + 1
    end
    return removed
end

World.onSquareLoad("retired curtains", function(square, hits)
    for i = 1, hits.n do
        if hits.info[i].curtain then Rooms.clearCurtainsOn(square) return end
    end
end)

--- Sent by each client as its player loads: their old curtains are taken away.
commands.retireCurtains = function(player, args)
    local n = Rooms.clearCurtainItems(player)
    if n > 0 then Net.notify(player, "Blackout curtains are retired (hang a sheet instead): removed " .. n .. " from your inventory") end
end

-- Room shapes are filled again after nearby construction and every few hours; doors and windows are read every ten minutes.
CannabisMod.TenMinutes.set("roomsRebuild", function() Rooms.refresh() end)
CannabisMod.TenMinutes.set("roomsTick", function() Rooms.tick() end)
-- Set once the start-up pass has run with the saved tables loaded, so OnGameStart and OnServerStarted don't both run it.
local started = false

--- Forget that start-up ran (tests use this to replay a server start).
function Rooms._resetStart() started = false end

--- Start-up: drop retired curtain records and build every room. OnGameStart doesn't fire on a dedicated server, so OnServerStarted runs it there.
function Rooms.onStart()
    if started or not panels then return end
    started = true
    local n = Rooms.forgetCurtains()
    if n > 0 then print("[DazedDank] forgot " .. n .. " retired blackout curtain record(s)") end
    Rooms.rebuild()
end
Events.OnGameStart.Add(Rooms.onStart)
if Events.OnServerStarted then Events.OnServerStarted.Add(Rooms.onStart) end
