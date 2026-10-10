-- The Log tab of the grow room panel: what happened in the room, newest first (power cuts, leaks, bad air, hydro jobs).

require "CannabisMod/CannabisRowsTab"
require "CannabisMod/CannabisWeather"

local Weather = CannabisMod.Weather

local LogTab = CannabisMod.RowsTab:derive("CannabisLogTab")
CannabisMod.LogTab = LogTab

function LogTab:new(x, y, w, h, info, actions)
    return CannabisMod.RowsTab.new(self, x, y, w, h, info, actions, 58, 28)
end

--- The log entries newest first.
function LogTab:rows()
    local log, out = self.info.log or {}, {}
    for i = #log, 1, -1 do out[#out + 1] = log[i] end
    return out
end

function LogTab:createChildren()
    -- The game and the window code may both ask for the children; build them once.
    if self.built then return end
    self.built = true
    CannabisMod.RowsTab.createChildren(self)
    self:rebuild()
end

--- How long ago an entry was, in the game's own time: "just now", "5 h ago", "2 d ago".
function LogTab.ago(hours)
    if hours < 1 then return "just now" end
    if hours < 48 then return string.format("%d h ago", math.floor(hours)) end
    return string.format("%d d ago", math.floor(hours / 24))
end

function LogTab:render()
    local font = UIFont.Small
    self:drawText("Room log", 12, 12, 0.75, 0.55, 1, 1, UIFont.Medium)
    self:drawText("The newest entries first. The panel keeps the last 30.", 12, 34, 0.8, 0.8, 0.85, 1, font)
    self:drawRect(12, 54, self.width - 24, 1, 1, 0.4, 0.3, 0.6)
    if #self:rows() == 0 then
        self:drawText("Nothing has happened here yet.", 12, 66, 0.7, 0.7, 0.7, 1, font)
    end
    local now = self.info.now or 0
    for _, entry in ipairs(self:visibleRows()) do
        local e, y = entry.row, entry.y + 4
        self:drawText(LogTab.ago(math.max(0, now - (e.t or now))), 12, y, 0.7, 0.7, 0.75, 1, font)
        self:drawText(Weather.localize(e.text), 100, y, 1, 1, 1, 1, font)
    end
    self:drawScrollNote()
end
