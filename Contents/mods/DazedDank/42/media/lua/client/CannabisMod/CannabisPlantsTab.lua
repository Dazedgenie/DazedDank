-- The Plants tab of the grow room panel: every plant in the room, showing only what the viewer's Agriculture level can read.

require "CannabisMod/CannabisRowsTab"

local PlantsTab = CannabisMod.RowsTab:derive("CannabisPlantsTab")
CannabisMod.PlantsTab = PlantsTab

function PlantsTab:new(x, y, w, h, info, actions)
    local o = CannabisMod.RowsTab.new(self, x, y, w, h, info, actions, 58, 28)
    o.rowH = 36   -- two lines: status, then strain and sex once Agriculture 3 can read them
    return o
end

function PlantsTab:rows() return self.info.plants or {} end

function PlantsTab:createChildren()
    -- The game and the window code may both ask for the children; build them once.
    if self.built then return end
    self.built = true
    CannabisMod.RowsTab.createChildren(self)
    self:rebuild()
end

function PlantsTab:makeRow(row, y)
    local choice = CannabisMod.RoomPanel.choiceButton
    return { choice(self, self.width - 76, y, 64, "Inspect", false, function() self.actions.inspect(row.x, row.y, row.z) end) }
end

function PlantsTab:render()
    local font = UIFont.Small
    self:drawText("Plants in this room", 12, 12, 0.75, 0.55, 1, 1, UIFont.Medium)
    self:drawText("Click Inspect for the full status. What you can read depends on your Agriculture level.", 12, 34, 0.8, 0.8, 0.85, 1, font)
    self:drawRect(12, 54, self.width - 24, 1, 1, 0.4, 0.3, 0.6)
    if #self:rows() == 0 then
        self:drawText("No plants in this room.", 12, 66, 0.7, 0.7, 0.7, 1, font)
    end
    for _, entry in ipairs(self:visibleRows()) do
        local p, y = entry.row, entry.y + 4
        self:drawText(p.x .. ", " .. p.y, 12, y, 0.7, 0.7, 0.75, 1, font)
        self:drawText(p.type or p.name, 80, y, 1, 1, 1, 1, font)
        self:drawText(tostring(p.stage), 170, y, 0.9, 0.9, 0.7, 1, font)
        self:drawText("Water " .. tostring(p.water), 290, y, 0.6, 0.85, 1, 1, font)
        if p.health then self:drawText(tostring(p.health), 390, y, 0.5, 0.95, 0.5, 1, font) end
        if p.warnings and p.warnings > 0 then self:drawText("! " .. p.warnings, 450, y, 1, 0.75, 0.35, 1, font) end
        local second = {}
        if p.strain then second[#second + 1] = p.strain end
        if p.sex then second[#second + 1] = p.sex end
        if #second > 0 then
            local male = p.sex == "Male" or p.sex == "Hermaphrodite"
            self:drawText(table.concat(second, "  -  "), 80, y + 15, male and 1 or 0.8, male and 0.65 or 0.7, male and 0.5 or 1, 1, font)
        end
    end
    self:drawScrollNote()
end
