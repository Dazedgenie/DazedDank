-- The Lights tab of the grow room panel: schedule and mode buttons, the room's size and power, and a list of its lamps.

require "ISUI/ISPanel"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local LightsTab = ISPanel:derive("CannabisLightsTab")
CannabisMod.LightsTab = LightsTab

local MAX_ROWS = 11

local DESCRIPTIONS = {
    ["24/0"] = "Lights on all day. Veg plants love it, but flowering needs a dark period.",
    ["18/6"] = "On 06:00 to 24:00. Holds plants in veg.",
    ["12/12"] = "On 06:00 to 18:00. Flips plants into flower.",
}

local function hourText(hour) return string.format("%02d:00", hour) end

function LightsTab:new(x, y, w, h, info, actions)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.info = info
    o.actions = actions
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

function LightsTab:createChildren()
    -- The game and the window code may both ask for the children; build them once.
    if self.built then return end
    self.built = true
    ISPanel.createChildren(self)
    local choice = CannabisMod.RoomPanel.choiceButton
    local info = self.info
    for i, schedule in ipairs(Config.Rooms.SCHEDULES) do
        choice(self, 130 + (i - 1) * 76, 38, 70, schedule, info.schedule == schedule, function() self.actions.schedule(schedule) end)
    end
    for i, mode in ipairs(Config.Rooms.MODES) do
        choice(self, 130 + (i - 1) * 76, 74, 70, mode, info.mode == mode, function() self.actions.mode(mode) end)
    end
    choice(self, self.width - 110, 6, 100, "Rename", false, function() self.actions.rename() end)
end

function LightsTab:render()
    local info = self.info
    local font = UIFont.Small
    self:drawText(info.name, 12, 8, 0.75, 0.55, 1, 1, UIFont.Medium)
    local power = info.powered and "Panel powered" or "NO POWER: lamps are off"
    local pr, pg, pb = 0.5, 0.9, 0.5
    if not info.powered then pr, pg, pb = 1, 0.4, 0.4 end
    self:drawText(info.tiles .. " tiles   " .. #info.lamps .. " lamps   " .. power .. "   " .. hourText(info.hour), 140, 12, pr, pg, pb, 1, font)
    self:drawText("Light schedule", 12, 42, 1, 1, 1, 1, font)
    self:drawText("Room mode", 12, 78, 1, 1, 1, 1, font)
    self:drawText(DESCRIPTIONS[info.schedule] or "", 12, 108, 0.8, 0.8, 0.85, 1, font)
    self:drawText("Lamps in this room", 12, 140, 0.75, 0.55, 1, 1, font)
    self:drawRect(12, 158, 320, 1, 1, 0.4, 0.3, 0.6)
    self:drawText("Doors and windows", 350, 140, 0.75, 0.55, 1, 1, font)
    self:drawRect(350, 158, self.width - 362, 1, 1, 0.4, 0.3, 0.6)
    local openings = info.openings or {}
    if #openings == 0 then
        self:drawText("None. No light can leak in.", 350, 166, 0.7, 0.7, 0.7, 1, font)
    end
    for i, o in ipairs(openings) do
        if i > MAX_ROWS then break end
        local y = 166 + (i - 1) * 20
        local kind = (o.kind == "window" and "Window " or "Door ") .. o.x .. ", " .. o.y
        self:drawText(kind, 350, y, 1, 1, 1, 1, font)
        if o.covered then self:drawText("Covered", 470, y, 0.5, 0.95, 0.5, 1, font)
        elseif o.seeps then self:drawText("Seeps: hang a sheet", 470, y, 1, 0.85, 0.45, 1, font)
        else self:drawText("OPEN", 470, y, 1, 0.75, 0.35, 1, font) end
    end
    if #info.lamps == 0 then
        self:drawText("No lamps yet. Hang one inside the room and it joins the schedule.", 12, 166, 0.7, 0.7, 0.7, 1, font)
        return
    end
    for i, lamp in ipairs(info.lamps) do
        if i > MAX_ROWS then
            self:drawText("+" .. (#info.lamps - MAX_ROWS) .. " more", 12, 166 + MAX_ROWS * 20, 0.7, 0.7, 0.7, 1, font)
            break
        end
        local y = 166 + (i - 1) * 20
        local state, r, g, b = "Lit", 0.5, 0.95, 0.5
        if not lamp.powered then state, r, g, b = "No power", 1, 0.4, 0.4
        elseif not lamp.lit then state, r, g, b = "Dark hours", 0.8, 0.8, 0.5 end
        self:drawText(lamp.name, 12, y, 1, 1, 1, 1, font)
        self:drawText(lamp.x .. ", " .. lamp.y, 170, y, 0.7, 0.7, 0.75, 1, font)
        self:drawText(state, 250, y, r, g, b, 1, font)
    end
end
