-- The Grow Room Panel: a right-click option on the wall panel opens one window with a tab per system.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTabPanel"
require "ISUI/ISTextBox"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisLightsTab"
require "CannabisMod/CannabisHydroTab"
require "CannabisMod/CannabisPlantsTab"
require "CannabisMod/CannabisClimateTab"
require "CannabisMod/CannabisEquipmentTab"
require "CannabisMod/CannabisLogTab"

local Config = CannabisMod.Config
local Net = CannabisMod.Net

local RoomPanel = {}
CannabisMod.RoomPanel = RoomPanel

local WIDTH, HEIGHT = 560, 420
local PURPLE = { r = 0.57, g = 0.25, b = 0.93, a = 1 }
local PLAIN = { r = 0.15, g = 0.15, b = 0.18, a = 1 }

local window = nil
local lastTab = "Lights"
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
    local active = window.tabs and window.tabs.activeView
    if active and active.name then lastTab = active.name end
    pcall(window.removeFromUIManager, window)
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

--- Ask for a new room name in a small text box.
local function askRename(player, info)
    local box = ISTextBox:new(300, 260, 280, 160, "Room name:", info.name, nil, function(_, button)
        if button.internal ~= "OK" then return end
        local text = button.parent.entry:getText()
        send(player, "roomRename", { x = info.x, y = info.y, z = info.z, name = text })
    end, player:getPlayerNum())
    box:initialise()
    box:addToUIManager()
end

--- Open (or refresh) the window for a roomInfo reply.
function RoomPanel.show(info)
    local player = getPlayer()
    if not player then return end
    local x, y = closeWindow()
    local titleH = ISCollapsableWindow.TitleBarHeight()
    local win = ISCollapsableWindow:new(x, y, WIDTH, HEIGHT + titleH)
    win:initialise()
    win:setTitle(info.name .. " - Grow Room Panel")
    win.resizable = false

    local tabs = ISTabPanel:new(0, titleH, WIDTH, HEIGHT)
    tabs:initialise()
    tabs.tabPadX = 20
    win:addChild(tabs)

    local at = { x = info.x, y = info.y, z = info.z }
    local function panelArgs(extra)
        local args = { x = at.x, y = at.y, z = at.z }
        for k, v in pairs(extra) do args[k] = v end
        return args
    end
    local actions = {
        schedule = function(schedule) send(player, "roomSetSchedule", panelArgs({ schedule = schedule })) end,
        mode = function(mode) send(player, "roomSetMode", panelArgs({ mode = mode })) end,
        rename = function() askRename(player, info) end,
        hydro = function(action, target, nutrient) send(player, "roomHydro", panelArgs({ action = action, target = target, nutrient = nutrient })) end,
        floodTimer = function(mode) send(player, "roomFloodTimer", panelArgs({ mode = mode })) end,
        override = function(kind, state) send(player, "roomOverride", panelArgs({ kind = kind, state = state })) end,
        inspect = function(px, py, pz) send(player, "roomInspectPlant", panelArgs({ px = px, py = py, pz = pz })) end,
        highlight = RoomPanel.highlight,
    }
    local tabHeight = HEIGHT - 28
    for _, def in ipairs({ { "Lights", CannabisMod.LightsTab }, { "Hydro", CannabisMod.HydroTab }, { "Plants", CannabisMod.PlantsTab },
        { "Climate", CannabisMod.ClimateTab }, { "Equipment", CannabisMod.EquipmentTab }, { "Log", CannabisMod.LogTab } }) do
        local view = def[2]:new(0, 0, WIDTH, tabHeight, info, actions)
        view:initialise()
        view:createChildren()
        tabs:addView(def[1], view)
    end
    tabs:activateView(lastTab)
    win.tabs = tabs

    win:addToUIManager()
    win:setVisible(true)
    win.at = at
    window = win
end

Net.clientHandlers.roomInfo = RoomPanel.show

-- Keep an open panel current: a lamp or piece of equipment placed or taken down near it asks for fresh room info.
local REFRESH_RANGE = 40
local refreshAt = nil

local function onLampChanged(obj)
    if not (window and window.at and window:isVisible()) then return end
    local ok, near = pcall(function()
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if not (name and (Config.Light.SPRITES[name] or Config.Rooms.EQUIPMENT[name])) then return false end
        local sq = obj:getSquare()
        return sq ~= nil and sq:getZ() == window.at.z and math.abs(sq:getX() - window.at.x) <= REFRESH_RANGE
            and math.abs(sq:getY() - window.at.y) <= REFRESH_RANGE
    end)
    -- The removal event fires before the object leaves the square, so wait a moment before asking.
    if ok and near then refreshAt = getTimestampMs() + 300 end
end
if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(onLampChanged) end
Events.OnObjectAdded.Add(onLampChanged)

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
    local option = context:addOption("Hang Blackout Curtain", player, function() act("hangCurtain") end)
    if not player:getInventory():containsTypeRecurse(Config.Rooms.CURTAIN_ITEM) then
        option.notAvailable = true
        local tip = ISInventoryPaneContextMenu.addToolTip()
        tip.description = "You need a blackout curtain."
        option.toolTip = tip
    end
end

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
            return
        end
    end
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
