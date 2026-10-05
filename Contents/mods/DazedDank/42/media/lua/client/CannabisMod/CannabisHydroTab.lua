-- The Hydro tab of the grow room panel: every reservoir in the room with its water, food and roots, and buttons to tend each one or all of them.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRowsTab"

local Config = CannabisMod.Config

local HydroTab = CannabisMod.RowsTab:derive("CannabisHydroTab")
CannabisMod.HydroTab = HydroTab

-- Where each button sits along a row: { action, label, x, width }.
local COLUMNS = {
    { "topUp", "Top Up", 300, 52 }, { "change", "Change", 355, 52 }, { "dose", "Dose", 410, 42 },
    { "bleach", "Bleach", 455, 50 },
}

function HydroTab:new(x, y, w, h, info, actions)
    local o = CannabisMod.RowsTab.new(self, x, y, w, h, info, actions, 76, 44)
    return o
end

function HydroTab:rows() return self.info.reservoirs or {} end

--- The nutrient the Dose buttons use: bloom food for a flower room, veg food otherwise.
function HydroTab:nutrient()
    if self.info.mode == "Flower" then return "Bloom" end
    return "Veg"
end

function HydroTab:createChildren()
    -- The game and the window code may both ask for the children; build them once.
    if self.built then return end
    self.built = true
    CannabisMod.RowsTab.createChildren(self)
    local choice = CannabisMod.RoomPanel.choiceButton
    for _, col in ipairs(COLUMNS) do
        choice(self, col[3], 38, col[4], col[2], false, function() self.actions.hydro(col[1], "all", self:nutrient()) end)
    end
    local fitted = self.info.floodTimer
    choice(self, 12, self.height - 34, 150, fitted and "Remove Flood Timer" or "Fit Flood Timer", fitted, function()
        self.actions.floodTimer(fitted and "remove" or "install")
    end)
    self:rebuild()
end

function HydroTab:makeRow(row, y)
    local choice = CannabisMod.RoomPanel.choiceButton
    local out = {}
    for _, col in ipairs(COLUMNS) do
        out[#out + 1] = choice(self, col[3], y, col[4], col[2], false, function() self.actions.hydro(col[1], row.key, self:nutrient()) end)
    end
    out[#out + 1] = choice(self, 510, y, 40, "Show", false, function() self.actions.highlight(row.x, row.y, row.z) end)
    return out
end

function HydroTab:render()
    local font = UIFont.Small
    local info = self.info
    self:drawText("Reservoirs in this room", 12, 12, 0.75, 0.55, 1, 1, UIFont.Medium)
    self:drawText("Top row: every reservoir. Dose: " .. self:nutrient() .. " food", 12, 42, 0.8, 0.8, 0.85, 1, font)
    self:drawText("Water", 126, 62, 0.6, 0.6, 0.7, 1, font)
    self:drawText("Food", 186, 62, 0.6, 0.6, 0.7, 1, font)
    self:drawText("Roots", 226, 62, 0.6, 0.6, 0.7, 1, font)
    self:drawRect(12, 72, self.width - 24, 1, 1, 0.4, 0.3, 0.6)
    local rows = self:rows()
    if #rows == 0 then
        self:drawText("No reservoirs yet. Place a DWC bucket, RDWC control or flood reservoir in the room.", 12, 84, 0.7, 0.7, 0.7, 1, font)
    end
    for _, entry in ipairs(self:visibleRows()) do
        local r, y = entry.row, entry.y + 4
        self:drawText(r.name, 12, y, 1, 1, 1, 1, font)
        local wr, wg, wb = 0.6, 0.85, 1
        if r.level <= 0 then wr, wg, wb = 1, 0.5, 0.5 end
        self:drawText(string.format("%.0f/%d L", r.level, r.cap), 126, y, wr, wg, wb, 1, font)
        local food = r.strength > 0.05 and string.format("%d%%", r.strength * 100) or "none"
        self:drawText(food, 186, y, 0.85, 0.85, 0.85, 1, font)
        local roots, rr, rg, rb = "healthy", 0.5, 0.95, 0.5
        if r.rot > 0 then roots, rr, rg, rb = "rot " .. math.floor(r.rot) .. "%", 1, 0.5, 0.4 end
        if not r.pump then roots, rr, rg, rb = "NO POWER", 1, 0.4, 0.4 end
        self:drawText(roots, 226, y, rr, rg, rb, 1, font)
    end
    local timerText = info.floodTimer and "Flood timer: fitted, runs every flood reservoir in the room" or "Flood timer: none (flood by hand from a reservoir)"
    self:drawText(timerText, 172, self.height - 28, 0.8, 0.8, 0.85, 1, font)
    self:drawScrollNote()
end
