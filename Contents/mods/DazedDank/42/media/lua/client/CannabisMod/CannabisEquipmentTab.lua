-- The Equipment tab of the grow room panel: every fan, heater, dehumidifier and humidifier in the room, where it hangs and whether it runs.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRowsTab"

local Config = CannabisMod.Config

local EquipmentTab = CannabisMod.RowsTab:derive("CannabisEquipmentTab")
CannabisMod.EquipmentTab = EquipmentTab

local MODES = { auto = "Auto", on = "On", off = "Off" }

function EquipmentTab:new(x, y, w, h, info, actions)
    return CannabisMod.RowsTab.new(self, x, y, w, h, info, actions, 76, 28)
end

function EquipmentTab:rows() return self.info.equipment or {} end

function EquipmentTab:createChildren()
    -- The game and the window code may both ask for the children; build them once.
    if self.built then return end
    self.built = true
    CannabisMod.RowsTab.createChildren(self)
    self:rebuild()
end

function EquipmentTab:makeRow(row, y)
    local choice = CannabisMod.RoomPanel.choiceButton
    return { choice(self, 500, y, 48, "Show", false, function() self.actions.highlight(row.x, row.y, row.z) end) }
end

--- How many of each kind the room has, as one line.
function EquipmentTab:summary()
    local counts = {}
    for _, row in ipairs(self:rows()) do counts[row.kind] = (counts[row.kind] or 0) + 1 end
    local parts = {}
    for _, kind in ipairs(Config.Rooms.EQUIPMENT_ORDER) do
        if counts[kind] then parts[#parts + 1] = counts[kind] .. " " .. string.lower(Config.Rooms.EQUIPMENT_NAMES[kind]) end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

function EquipmentTab:render()
    local font = UIFont.Small
    local info = self.info
    self:drawText("Equipment in this room", 12, 12, 0.75, 0.55, 1, 1, UIFont.Medium)
    local summary = self:summary()
    if summary then self:drawText(summary, 12, 40, 0.8, 0.8, 0.85, 1, font) end
    self:drawText("Auto / On / Off: see the Climate tab", 12, self.height - 20, 0.7, 0.7, 0.75, 1, font)
    self:drawText("Where", 150, 60, 0.6, 0.6, 0.7, 1, font)
    self:drawText("Mounted", 250, 60, 0.6, 0.6, 0.7, 1, font)
    self:drawText("State", 360, 60, 0.6, 0.6, 0.7, 1, font)
    self:drawRect(12, 72, self.width - 24, 1, 1, 0.4, 0.3, 0.6)
    local rows = self:rows()
    if #rows == 0 then
        self:drawText("None yet. Hang fans, a heater, a dehumidifier or a humidifier in the room and the panel finds them.", 12, 84, 0.7, 0.7, 0.7, 1, font)
    end
    for _, entry in ipairs(self:visibleRows()) do
        local r, y = entry.row, entry.y + 4
        self:drawText(r.name, 12, y, 1, 1, 1, 1, font)
        self:drawText(r.x .. ", " .. r.y, 150, y, 0.7, 0.7, 0.75, 1, font)
        self:drawText(r.mount, 250, y, 0.8, 0.8, 0.85, 1, font)
        local state, cr, cg, cb = "Idle", 0.8, 0.8, 0.5
        if not r.powered then state, cr, cg, cb = "No power", 1, 0.4, 0.4
        elseif r.running then state, cr, cg, cb = "Running", 0.5, 0.95, 0.5 end
        if r.mode ~= "auto" then state = state .. " (" .. MODES[r.mode] .. ")" end
        self:drawText(state, 360, y, cr, cg, cb, 1, font)
    end
    self:drawScrollNote()
end
