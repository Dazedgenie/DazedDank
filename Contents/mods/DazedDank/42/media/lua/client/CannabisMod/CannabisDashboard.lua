-- The Grow Room Panel window: draws the dashboard from CannabisDashboardLayout and turns clicks on it into room actions.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTextBox"
require "ISUI/ISContextMenu"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisDashboardLayout"
require "CannabisMod/CannabisUIDraw"
require "CannabisMod/CannabisLogTab"

local Config = CannabisMod.Config
local Dash = CannabisMod.DashboardLayout
local Draw = CannabisMod.UIDraw
local COLORS = CannabisMod.StatusLayout.COLORS

local FONTS = { Small = UIFont.Small, Medium = UIFont.Medium, Large = UIFont.Large }
local ICONS = { exhaust = "Item_ExhaustFan", intake = "Item_IntakeFan", heater = "Item_Heater",
    dehumidifier = "Item_Dehumidifier", humidifier = "Item_Humidifier", cooler = "Item_WallAC", circfan = "Item_CirculationFan",
    drip = "Item_DripTank" }
local STEP = Dash.CARD_W + Dash.CARD_GAP

local function fontHeight(name) return getTextManager():getFontHeight(FONTS[name] or UIFont.Small) end
local function measure(name, str) return getTextManager():MeasureStringX(FONTS[name] or UIFont.Small, str) end

local DashPanel = ISPanel:derive("CannabisDashPanel")
CannabisMod.DashPanel = DashPanel

local function send(command, args)
    local player = getPlayer()
    if player then sendClientCommand(player, Config.COMMAND_MODULE, command, args) end
end

--- Arguments for a room command: the panel's square plus `extra`.
function DashPanel:args(extra)
    local a = { x = self.info.x, y = self.info.y, z = self.info.z }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end

--- Take a fresh roomInfo reply, keeping the plant row's scroll where it can.
function DashPanel:setInfo(info)
    -- A reply to a Refresh click says so on the button for a moment.
    if self.refreshSent then
        self.refreshSent = nil
        info.refreshLabel, self.labelUntil = "Updated", getTimestampMs() + 1500
    end
    self.info = info
    self.scroll = math.max(0, math.min(self.scroll or 0, Dash.maxScroll(info)))
    self.model = Dash.build(info, self.scroll, fontHeight, measure)
end

function DashPanel:setScroll(value)
    value = math.max(0, math.min(value, Dash.maxScroll(self.info)))
    if value == self.scroll then return end
    self.scroll = value
    self.model = Dash.build(self.info, self.scroll, fontHeight, measure)
end

-- The layout draws in prerender, under the child buttons; render runs after children, so drawing there hid the close button.
function DashPanel:prerender()
    local g = COLORS.ground
    self:drawRect(0, 0, self.width, self.height, 1, g[1], g[2], g[3])
    for _, op in ipairs(self.model.ops) do
        local c = op.color
        if op.kind == "rect" then
            self:drawRect(op.x, op.y, op.w, op.h, op.a or 1, c[1], c[2], c[3])
        elseif op.kind == "card" then
            Draw.card(self, op.x, op.y, op.w, op.h, c, op.border)
        elseif op.kind == "pill" then
            Draw.pill(self, op.x, op.y, op.w, op.h, c)
        elseif op.kind == "tex" then
            Draw.tex(self, op.name, op.x, op.y, op.w, op.h, op.a)
        elseif op.kind == "plant" then
            pcall(Draw.plant, self, op.x, op.y, op.w, op.h, op.sprite, op.pot, op.lift, op.fit)
        elseif op.kind == "equip" then
            local t = ICONS[op.equipKind] and getTexture(ICONS[op.equipKind])
            -- Full tiles keep the icon at the left under the mode pill; narrow ones centre a smaller icon.
            local size = math.min(36, op.w - 12)
            local ix = op.w >= 70 and op.x + 8 or op.x + (op.w - size) / 2
            if t then self:drawTextureScaled(t, ix, op.y + 14, size, size, 1, 1, 1, 1) end
        elseif op.kind == "clip" then
            self:setStencilRect(op.x, op.y, op.w, op.h)
        elseif op.kind == "unclip" then
            self:clearStencilRect()
        elseif op.kind == "text" then
            local font = FONTS[op.font] or UIFont.Small
            if op.align == "right" then
                self:drawTextRight(op.text, op.x, op.y, c[1], c[2], c[3], 1, font)
            elseif op.align == "center" then
                self:drawTextCentre(op.text, op.x, op.y, c[1], c[2], c[3], 1, font)
            else
                self:drawText(op.text, op.x, op.y, c[1], c[2], c[3], 1, font)
            end
        end
    end
end

--- Show `label` on the Refresh button until `untilMs` (nil keeps it until changed).
function DashPanel:setLabel(label, untilMs)
    self.info.refreshLabel, self.labelUntil = label, untilMs
    self.model = Dash.build(self.info, self.scroll, fontHeight, measure)
end

--- Put the Refresh label back after a moment, or say "No reply" when the server never answered.
function DashPanel:updateLabel()
    local now = getTimestampMs()
    if self.refreshSent and now - self.refreshSent > 3000 then
        self.refreshSent = nil
        self:setLabel("No reply", now + 2500)
    elseif self.labelUntil and now > self.labelUntil then
        self:setLabel(nil, nil)
    end
end

function DashPanel:render()
    self:updateLabel()
    -- A faint wash over whatever the mouse would click, so the clickable parts can be found.
    local h = self:isMouseOver() and self:hitAt(self:getMouseX(), self:getMouseY())
    if h then
        local p = COLORS.purple
        self:drawRect(h.x, h.y, h.w, h.h, 0.07, p[1], p[2], p[3])
    end
end

--- The click region under a point, the last drawn first.
function DashPanel:hitAt(x, y)
    local hits = self.model.hits
    for i = #hits, 1, -1 do
        local h = hits[i]
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then return h end
    end
    return nil
end

-- The panel drags by its body, so a press only counts as a click when the mouse hardly moved.
function DashPanel:onMouseDown(x, y)
    self.pressAt = { getMouseX(), getMouseY() }
    return ISPanel.onMouseDown(self, x, y)
end

function DashPanel:onMouseUp(x, y)
    local press = self.pressAt
    self.pressAt = nil
    ISPanel.onMouseUp(self, x, y)
    if press and math.abs(getMouseX() - press[1]) + math.abs(getMouseY() - press[2]) <= 4 then
        local h = self:hitAt(x, y)
        if h then self:onHit(h.id, false) end
    end
    return true
end

function DashPanel:onRightMouseUp(x, y)
    local h = self:hitAt(x, y)
    if h then self:onHit(h.id, true) end
    return true
end

function DashPanel:onMouseWheel(del)
    local A = Dash.PLANT_AREA
    local mx, my = self:getMouseX(), self:getMouseY()
    if mx < A.x or mx > A.x + A.w or my < A.y or my > A.y + A.h then return false end
    self:setScroll(self.scroll + del * STEP)
    return true
end

--- A context menu at the mouse; `items` are { label, fn, checked, disabled }.
local function menu(items)
    local player = getPlayer()
    if not player then return end
    local context = ISContextMenu.get(player:getPlayerNum(), getMouseX(), getMouseY())
    for _, it in ipairs(items) do
        local option = context:addOption(it[1], nil, it[2])
        if it[3] and context.setOptionChecked then pcall(context.setOptionChecked, context, option, true) end
        if it[4] then option.notAvailable = true end
    end
end

--- Tint the floor under every listed square.
local function show(list)
    for _, e in ipairs(list) do CannabisMod.RoomPanel.highlight(e.x, e.y, e.z) end
end

function DashPanel:askRename()
    local player = getPlayer()
    if not player then return end
    local info = self.info
    local box = ISTextBox:new(300, 260, 280, 160, "Room name:", info.name, nil, function(_, button)
        if button.internal ~= "OK" then return end
        send("roomRename", self:args({ name = button.parent.entry:getText() }))
    end, player:getPlayerNum())
    box:initialise()
    box:addToUIManager()
end

--- The room log in its own small window.
function DashPanel:openLog()
    if self.logWindow then pcall(self.logWindow.removeFromUIManager, self.logWindow) end
    local titleH = ISCollapsableWindow.TitleBarHeight()
    local win = ISCollapsableWindow:new(self:getX() + 40, self:getY() + 60, 520, 360 + titleH)
    win:initialise()
    win:setTitle((self.info.name or "Grow Room") .. " - Log")
    win.resizable = false
    local view = CannabisMod.LogTab:new(0, titleH, 520, 360, self.info, {})
    view:initialise()
    view:createChildren()
    win:addChild(view)
    win:addToUIManager()
    self.logWindow = win
end

local function hydro(self, action, target, nutrient)
    send("roomHydro", self:args({ action = action, target = target, nutrient = nutrient }))
end

--- Turn a click on a region into an action; `right` is a right-click, which opens the fuller menu where there is one.
function DashPanel:onHit(id, right)
    local info = self.info
    if id == "rename" then
        self:askRename()
    elseif id == "mode" then
        local items = {}
        for _, mode in ipairs(Config.Rooms.MODES) do
            items[#items + 1] = { mode, function() send("roomSetMode", self:args({ mode = mode })) end, info.mode == mode }
        end
        menu(items)
    elseif id == "schedule" then
        local items = {}
        for _, s in ipairs(Config.Rooms.SCHEDULES) do
            items[#items + 1] = { "Lights " .. s, function() send("roomSetSchedule", self:args({ schedule = s })) end, info.schedule == s }
        end
        items[#items + 1] = { "Show lamps", function() show(info.lamps or {}) end }
        menu(items)
    elseif id == "scrollLeft" then
        self:setScroll(self.scroll - STEP)
    elseif id == "scrollRight" then
        self:setScroll(self.scroll + STEP)
    elseif id:sub(1, 6) == "plant:" then
        local p = (info.plants or {})[tonumber(id:sub(7))]
        if not p then return end
        local function inspect() send("roomInspectPlant", self:args({ px = p.x, py = p.y, pz = p.z })) end
        if right then
            menu({ { "Inspect", inspect }, { "Show in room", function() show({ p }) end } })
        else
            inspect()
        end
    elseif id == "topUpAll" then
        hydro(self, "topUp", "all")
    elseif id == "doseAll" then
        local fitted = info.floodTimer
        menu({
            { "Dose all with Veg food", function() hydro(self, "dose", "all", "Veg") end, info.mode ~= "Flower" },
            { "Dose all with Bloom food", function() hydro(self, "dose", "all", "Bloom") end, info.mode == "Flower" },
            { "Change all water", function() hydro(self, "change", "all") end },
            { "Treat all with bleach", function() hydro(self, "bleach", "all") end },
            { fitted and "Remove flood timer" or "Fit flood timer", function()
                send("roomFloodTimer", self:args({ mode = fitted and "remove" or "install" }))
            end },
        })
    elseif id:sub(1, 4) == "res:" then
        local r = (info.reservoirs or {})[tonumber(id:sub(5))]
        if not r then return end
        menu({
            { "Top up", function() hydro(self, "topUp", r.key) end },
            { "Change water", function() hydro(self, "change", r.key) end },
            { "Dose with Veg food", function() hydro(self, "dose", r.key, "Veg") end },
            { "Dose with Bloom food", function() hydro(self, "dose", r.key, "Bloom") end },
            { "Treat with bleach", function() hydro(self, "bleach", r.key) end },
            { "Show in room", function() show({ r }) end },
        })
    elseif id:sub(1, 6) == "equip:" then
        local kind = id:sub(7)
        local current = ((info.climate or {}).override or {})[kind] or "auto"
        local list = {}
        for _, e in ipairs(info.equipment or {}) do if e.kind == kind then list[#list + 1] = e end end
        local items = {}
        for _, s in ipairs({ { "Auto", "auto" }, { "Always on", "on" }, { "Off", "off" } }) do
            items[#items + 1] = { s[1], function() send("roomOverride", self:args({ kind = kind, state = s[2] })) end, current == s[2] }
        end
        items[#items + 1] = { "Show in room", function() show(list) end }
        menu(items)
    elseif id == "log" then
        self:openLog()
    elseif id == "refresh" then
        self.refreshSent = getTimestampMs()
        self:setLabel("...", nil)
        send("requestRoom", self:args())
    end
end

function DashPanel:close()
    if self.logWindow then pcall(self.logWindow.removeFromUIManager, self.logWindow) end
    self:removeFromUIManager()
end

--- Make the window at x, y for a roomInfo reply. The dark title bar is part of the layout, with a close button on it.
function DashPanel.create(info, x, y, onClose)
    local panel = DashPanel:new(x, y, Dash.WIDTH, Dash.HEIGHT)
    panel:initialise()
    panel.scroll = 0
    panel:setInfo(info)
    panel.background = false
    panel.moveWithMouse = true
    panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    local close = ISButton:new(Dash.WIDTH - 36, 6, 28, 28, "X", panel, function(p)
        p:close()
        if onClose then onClose(p) end
    end)
    close:initialise()
    close.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    close.backgroundColorMouseOver = { r = 1, g = 1, b = 1, a = 0.12 }
    close.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    close.textColor = { r = 1, g = 1, b = 1, a = 1 }
    close.font = UIFont.Medium
    panel:addChild(close)
    panel:addToUIManager()
    panel:setVisible(true)
    return panel
end

return DashPanel
