-- A tab that shows a scrolling list of rows, each with its own buttons. The Hydro and Plants tabs build on it.

require "ISUI/ISPanel"
require "CannabisMod/CannabisConfig"

local RowsTab = ISPanel:derive("CannabisRowsTab")
CannabisMod.RowsTab = RowsTab

RowsTab.ROW_H = 26

function RowsTab:new(x, y, w, h, info, actions, top, bottom)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.info = info
    o.actions = actions
    o.top = top
    o.bottom = bottom or 8
    o.scroll = 0
    o.rowButtons = {}
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

--- The data rows of this tab. Subclasses return their list.
function RowsTab:rows() return {} end

--- How many rows fit between the top of the list and the bottom margin.
function RowsTab:visibleCount()
    return math.max(1, math.floor((self.height - self.top - self.bottom) / (self.rowH or RowsTab.ROW_H)))
end

--- The rows on screen now, as { row, y } pairs.
function RowsTab:visibleRows()
    local rows, out = self:rows(), {}
    for i = 1, self:visibleCount() do
        local row = rows[self.scroll + i]
        if not row then break end
        out[#out + 1] = { row = row, y = self.top + (i - 1) * (self.rowH or RowsTab.ROW_H) }
    end
    return out
end

--- Replace the row buttons to match the current scroll position.
function RowsTab:rebuild()
    for _, button in ipairs(self.rowButtons) do self:removeChild(button) end
    self.rowButtons = {}
    local maxScroll = math.max(0, #self:rows() - self:visibleCount())
    self.scroll = math.max(0, math.min(self.scroll, maxScroll))
    for _, entry in ipairs(self:visibleRows()) do
        for _, button in ipairs(self:makeRow(entry.row, entry.y)) do
            self.rowButtons[#self.rowButtons + 1] = button
        end
    end
end

--- Build the buttons for one row at height y and return them. Subclasses fill this in.
function RowsTab:makeRow(row, y) return {} end

function RowsTab:onMouseWheel(del)
    self.scroll = self.scroll + del
    self:rebuild()
    return true
end

--- Draw "n-m of total" under the list when it scrolls.
function RowsTab:drawScrollNote()
    local total = #self:rows()
    local shown = self:visibleCount()
    if total > shown then
        local text = string.format("%d-%d of %d (mouse wheel scrolls)", self.scroll + 1, math.min(total, self.scroll + shown), total)
        self:drawText(text, self.width - 230, self.height - 20, 0.7, 0.7, 0.75, 1, UIFont.Small)
    end
end
