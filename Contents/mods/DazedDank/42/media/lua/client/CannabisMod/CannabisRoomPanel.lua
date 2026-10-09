-- The Grow Room Panel: a right-click option on the wall panel opens the room dashboard; also blackout curtain options.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextBox"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisWorld"
require "CannabisMod/CannabisDashboard"

local Config = CannabisMod.Config
local Net = CannabisMod.Net

local RoomPanel = {}
CannabisMod.RoomPanel = RoomPanel

local PURPLE = { r = 0.57, g = 0.25, b = 0.93, a = 1 }
local PLAIN = { r = 0.15, g = 0.15, b = 0.18, a = 1 }

local window = nil
local marks = {}    -- floor squares being tinted for the Show buttons: { x, y, z, untilMs }

--- Tint the floor under a piece of equipment for a few seconds so the player can find it.
function RoomPanel.highlight(x, y, z)
    marks[#marks + 1] = { x = x, y = y, z = z, untilMs = getTimestampMs() + 4000 }
end

Events.OnTick.Add(function()
    if #marks == 0 then return end
    local now, cell = getTimestampMs(), getCell()
    for i = #marks, 1, -1 do
        local m = marks[i]
        local square = cell and cell:getGridSquare(m.x, m.y, m.z)
        local floor = square and square:getFloor()
        if floor and now < m.untilMs then
            pcall(function()
                floor:setHighlightColor(0.57, 0.25, 0.93, 0.8)
                floor:setHighlighted(true, true)
            end)
        else
            table.remove(marks, i)
        end
    end
end)

local function send(player, command, args)
    sendClientCommand(player, Config.COMMAND_MODULE, command, args)
end

--- Close the open panel window, keeping where it was so the next one opens in the same place.
local function closeWindow()
    if not window then return 200, 120 end
    local x, y = window:getX(), window:getY()
    pcall(window.close, window)
    window = nil
    return x, y
end

--- Make a button that sends a room command, shown in purple when it is the current setting.
local function choiceButton(parent, x, y, w, label, active, onClick)
    local button = ISButton:new(x, y, w, 24, label, parent, onClick)
    button:initialise()
    button:instantiate()
    button.backgroundColor = active and PURPLE or PLAIN
    button.borderColor = { r = 0.6, g = 0.6, b = 0.7, a = 1 }
    parent:addChild(button)
    return button
end
RoomPanel.choiceButton = choiceButton

--- Open the dashboard for a roomInfo reply, or refresh it in place when it already shows that room.
function RoomPanel.show(info)
    if not getPlayer() then return end
    if window and window:isVisible() and window.at and window.at.x == info.x and window.at.y == info.y and window.at.z == info.z then
        window:setInfo(info)
        return
    end
    local x, y = closeWindow()
    x = math.max(0, math.min(x, getCore():getScreenWidth() - CannabisMod.DashboardLayout.WIDTH))
    y = math.max(0, math.min(y, getCore():getScreenHeight() - CannabisMod.DashboardLayout.HEIGHT))
    window = CannabisMod.DashPanel.create(info, x, y, function(p) if window == p then window = nil end end)
    window.at = { x = info.x, y = info.y, z = info.z }
end

Net.clientHandlers.roomInfo = RoomPanel.show

-- Keep an open panel current: a lamp or piece of equipment placed or taken down near it asks for fresh room info.
local REFRESH_RANGE = 40
local refreshAt = nil

local function onLampChanged(obj, name, info)
    if not (info.lamp or info.gear) or not (window and window.at and window:isVisible()) then return end
    local sq = obj:getSquare()
    local near = sq ~= nil and sq:getZ() == window.at.z and math.abs(sq:getX() - window.at.x) <= REFRESH_RANGE
        and math.abs(sq:getY() - window.at.y) <= REFRESH_RANGE
    -- The removal event fires before the object leaves the square, so wait a moment before asking.
    if near then refreshAt = getTimestampMs() + 300 end
end
CannabisMod.World.onObjectRemoved("panel refresh", onLampChanged)
CannabisMod.World.onObjectAdded("panel refresh", onLampChanged)

Events.OnTick.Add(function()
    if not refreshAt or getTimestampMs() < refreshAt then return end
    refreshAt = nil
    local player = getPlayer()
    if player and window and window.at and window:isVisible() then
        send(player, "requestRoom", { x = window.at.x, y = window.at.y, z = window.at.z })
    end
end)

--- True when the object is a door or a window frame.
local function isFrame(obj)
    local ok, yes = pcall(function()
        return instanceof(obj, "IsoWindow") or instanceof(obj, "IsoDoor")
            or (instanceof(obj, "IsoThumpable") and (obj:isDoor() or obj:isWindow()))
            or instanceof(obj, "IsoWindowFrame")
    end)
    return ok and yes == true
end

--- True when a blackout curtain overlay hangs on this square's wall edge.
local function hasCurtain(square, dir)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        local name = sprite and sprite:getName()
        if name and (name == Config.Rooms.CURTAIN_SPRITES.door[dir] or name == Config.Rooms.CURTAIN_SPRITES.window[dir]) then return true end
    end
    return false
end

--- Which wall a door or window sits on: true for north, false for west, nil when it can't be told.
local function frameNorth(obj)
    for _, m in ipairs({ "getNorth", "isNorth" }) do
        if obj[m] then
            local ok, v = pcall(obj[m], obj)
            if ok and type(v) == "boolean" then return v end
        end
    end
    -- Fall back on the tile's own flags.
    local ok, v = pcall(function()
        local props = obj:getProperties()
        if props:Is(IsoFlagType.WindowN) or props:Is(IsoFlagType.doorN) or props:Is(IsoFlagType.DoorWallN) then return true end
        if props:Is(IsoFlagType.WindowW) or props:Is(IsoFlagType.doorW) or props:Is(IsoFlagType.DoorWallW) then return false end
        return nil
    end)
    if ok then return v end
    return nil
end

--- Offer to hang or take down a blackout curtain on a door or window frame.
local function addCurtainOption(player, context, obj)
    local square = obj:getSquare()
    local north = frameNorth(obj)
    if not square or north == nil then return end
    local dir = north and "N" or "W"
    local function act(command)
        print(string.format("[DazedDank] %s: frame %s at %d,%d,%d dir %s", command, tostring(obj), square:getX(), square:getY(), square:getZ(), dir))
        -- Walk up to the frame from whichever side the player is on, the way vanilla does for sheets.
        local walked = false
        if luautils.walkAdjWindowOrDoor then walked = luautils.walkAdjWindowOrDoor(player, square, obj) end
        if not walked then walked = luautils.walkAdj(player, square) end
        if walked then
            ISTimedActionQueue.add(ISGrowBagAction:new(player, square, command, { dir = dir }))
        else
            print("[DazedDank] " .. command .. ": could not walk next to the frame")
        end
    end
    if hasCurtain(square, dir) then
        context:addOption("Take Down Blackout Curtain", player, function() act("removeCurtain") end)
        return
    end
end

-- Blackout curtains are retired: ask the server to clear any left in this player's inventory.
Events.OnCreatePlayer.Add(function(_, player)
    if player then sendClientCommand(player, Config.COMMAND_MODULE, "retireCurtains", {}) end
end)

--- Add "Open Grow Room Panel" when the right-click lands on a panel.
local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test or not worldObjects then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    -- Like vanilla sheets, find a door or window on the clicked squares or on the walls of their south and east neighbours.
    local frame = nil
    local seen = {}
    local function look(sq)
        if frame or not sq or seen[sq] then return end
        seen[sq] = true
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            if isFrame(objects:get(i)) then frame = objects:get(i) return end
        end
    end
    for _, obj in ipairs(worldObjects) do
        if not frame and isFrame(obj) then frame = obj end
    end
    for _, obj in ipairs(worldObjects) do
        local sq = obj:getSquare()
        look(sq)
        if sq then
            local cell = getCell()
            look(cell:getGridSquare(sq:getX(), sq:getY() + 1, sq:getZ()))
            look(cell:getGridSquare(sq:getX() + 1, sq:getY(), sq:getZ()))
        end
    end
    if frame then addCurtainOption(player, context, frame) end
    for _, obj in ipairs(worldObjects) do
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if name and Config.Rooms.PANEL_SPRITES[name] then
            local square = obj:getSquare()
            context:addOption("Open Grow Room Panel", player, function()
                if luautils.walkAdj(player, square) then
                    local action = ISGrowBagAction:new(player, square, "requestRoom")
                    action.maxTime = 1
                    ISTimedActionQueue.add(action)
                end
            end)
            -- Debug: cut the room's power at the panel to test an outage; the server re-checks debug or admin.
            if isDebugEnabled() then
                local cut = obj:getModData().DDPowerCut == true
                context:addOption(cut and "[Debug] Restore grow room power" or "[Debug] Cut grow room power", player, function()
                    sendClientCommand(player, Config.COMMAND_MODULE, "debugRoomPower",
                        { x = square:getX(), y = square:getY(), z = square:getZ(), cut = not cut })
                end)
            end
            return
        end
    end
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
