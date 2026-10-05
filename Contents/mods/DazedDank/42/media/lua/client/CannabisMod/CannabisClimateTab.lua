-- The Climate tab of the grow room panel: the room's air against its targets, and each kind of equipment with Auto / On / Off.

require "ISUI/ISPanel"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local ClimateTab = ISPanel:derive("CannabisClimateTab")
CannabisMod.ClimateTab = ClimateTab

local ROW_Y, ROW_H = 168, 34
local STATES = { { "Auto", "auto" }, { "On", "on" }, { "Off", "off" } }

function ClimateTab:new(x, y, w, h, info, actions)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.info = info
    o.actions = actions
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

--- The equipment kinds the room has, in display order.
function ClimateTab:fitted()
    local climate = self.info.climate or {}
    local out = {}
    for _, kind in ipairs(Config.Rooms.EQUIPMENT_ORDER) do
        if (climate.present or {})[kind] then out[#out + 1] = kind end
    end
    return out
end

function ClimateTab:createChildren()
    -- The game and the window code may both ask for the children; build them once.
    if self.built then return end
    self.built = true
    ISPanel.createChildren(self)
    local choice = CannabisMod.RoomPanel.choiceButton
    local override = (self.info.climate or {}).override or {}
    for i, kind in ipairs(self:fitted()) do
        local y = ROW_Y + (i - 1) * ROW_H
        for s, state in ipairs(STATES) do
            local active = (override[kind] or "auto") == state[2]
            choice(self, 330 + (s - 1) * 72, y, 66, state[1], active, function() self.actions.override(kind, state[2]) end)
        end
    end
end

--- A reading with its comfortable range, green inside the range and amber outside.
function ClimateTab:drawReading(label, value, lo, hi, unit, y)
    local font = UIFont.Small
    self:drawText(label, 12, y, 1, 1, 1, 1, font)
    if not value then
        self:drawText("waiting for the next reading", 130, y, 0.7, 0.7, 0.7, 1, font)
        return
    end
    local ok = value >= lo and value <= hi
    local r, g, b = 0.5, 0.95, 0.5
    if not ok then r, g, b = 1, 0.75, 0.35 end
    self:drawText(string.format("%.1f%s", value, unit), 130, y, r, g, b, 1, font)
    self:drawText(string.format("target %d to %d%s", lo, hi, unit), 220, y, 0.7, 0.7, 0.75, 1, font)
end

function ClimateTab:render()
    local info = self.info
    local climate = info.climate or {}
    local font = UIFont.Small
    self:drawText("Climate", 12, 8, 0.75, 0.55, 1, 1, UIFont.Medium)
    if not climate.enabled then
        self:drawText("Room climate is switched off in the sandbox options: the air stays at the targets.", 12, 34, 0.8, 0.8, 0.85, 1, font)
        return
    end
    local targets = climate.targets or { tLo = 0, tHi = 0, hLo = 0, hHi = 0 }
    self:drawReading("Temperature", climate.temp, targets.tLo, targets.tHi, " C", 38)
    self:drawReading("Humidity", climate.hum, targets.hLo, targets.hHi, "%", 62)
    if climate.outT then
        self:drawText(string.format("Outdoors %.0f C, %.0f%% humidity", climate.outT, climate.outH or 0), 12, 86, 0.7, 0.7, 0.75, 1, font)
    end
    local power = info.powered and "Equipment runs from the panel's power." or "NO POWER: all equipment is off."
    if info.powered then self:drawText(power, 12, 110, 0.5, 0.9, 0.5, 1, font)
    else self:drawText(power, 12, 110, 1, 0.4, 0.4, 1, font) end
    self:drawText("Equipment", 12, 142, 0.75, 0.55, 1, 1, font)
    self:drawRect(12, 160, self.width - 24, 1, 1, 0.4, 0.3, 0.6)
    local fitted = self:fitted()
    if #fitted == 0 then
        self:drawText("None yet. Place fans, a heater, a dehumidifier or a humidifier in the room and the panel finds them.", 12, ROW_Y + 8, 0.7, 0.7, 0.7, 1, font)
    end
    local running, override = climate.running or {}, climate.override or {}
    for i, kind in ipairs(fitted) do
        local y = ROW_Y + (i - 1) * ROW_H + 4
        self:drawText(Config.Rooms.EQUIPMENT_NAMES[kind] .. " x" .. tostring(climate.present[kind]), 12, y, 1, 1, 1, 1, font)
        local state, r, g, b = "Off", 0.7, 0.7, 0.7
        if running[kind] then state, r, g, b = "Running", 0.5, 0.95, 0.5 end
        self:drawText(state .. (override[kind] and " (manual)" or ""), 190, y, r, g, b, 1, font)
    end
    local notes = climate.notes or {}
    for i, note in ipairs(notes) do
        self:drawText("! " .. note, 12, self.height - 20 * (#notes - i + 1) - 4, 1, 0.75, 0.35, 1, font)
    end
end
