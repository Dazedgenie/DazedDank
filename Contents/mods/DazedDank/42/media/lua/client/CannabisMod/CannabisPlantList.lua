-- The "All plants" window: one compact, sortable row per plant, opened from the dashboard's View all button.
-- It reuses the dashboard's drawing and click handling and routes a plant click to the dashboard's own Inspect action.

require "ISUI/ISButton"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisDashboard"
require "CannabisMod/CannabisPlantListLayout"

local PL = CannabisMod.PlantListLayout

local DashPanel = CannabisMod.DashPanel
local ListPanel = DashPanel:derive("CannabisPlantListPanel")
CannabisMod.PlantList = ListPanel

local function fontHeight(name) return getTextManager():getFontHeight(name == "Medium" and UIFont.Medium or UIFont.Small) end
local function measure(name, str) return getTextManager():MeasureStringX(name == "Medium" and UIFont.Medium or UIFont.Small, str) end

-- The list has no Refresh button, so it skips the dashboard's label timer.
function ListPanel:updateLabel() end

function ListPanel:rebuild()
    self.model = PL.build(self.info, self.sort, self.scroll, fontHeight, measure)
end

--- Take the dashboard's fresh info, keeping the sort and keeping the scroll where it still fits.
function ListPanel:setInfo(info)
    self.info = info
    local max = PL.metrics(#(info.plants or {}), fontHeight).maxScroll
    self.scroll = math.max(0, math.min(self.scroll or 0, max))
    self:rebuild()
end

function ListPanel:setScroll(value)
    value = math.max(0, math.min(value, self.model.maxScroll))
    if value == self.scroll then return end
    self.scroll = value
    self:rebuild()
end

function ListPanel:onMouseWheel(del)
    self:setScroll(self.scroll + del * self.model.area.rowH)
    return true
end

--- A header click sorts; a plant click does what the dashboard's plant card does, by the plant's index in info.plants.
function ListPanel:onHit(id, right)
    if id:sub(1, 5) == "sort:" then
        self.sort = PL.nextSort(self.sort, id:sub(6))
        self:rebuild()
    elseif id:sub(1, 6) == "plant:" then
        self.dash:onHit(id, right)
    end
end

function ListPanel:close()
    self:removeFromUIManager()
end

--- Make the window near the dashboard `dash`; `onClose(window)` runs when its X is clicked.
function ListPanel.create(dash, onClose)
    local x = math.max(0, math.min(dash:getX() + 40, getCore():getScreenWidth() - PL.WIDTH))
    local y = math.max(0, math.min(dash:getY() + 60, getCore():getScreenHeight() - PL.HEIGHT))
    local panel = ListPanel:new(x, y, PL.WIDTH, PL.HEIGHT)
    panel:initialise()
    panel.dash = dash
    panel.sort = PL.DEFAULT_SORT
    panel.scroll = 0
    panel:setInfo(dash.info)
    panel.background = false
    panel.moveWithMouse = true
    panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    local close = ISButton:new(PL.WIDTH - 36, 6, 28, 28, "X", panel, function(p)
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

return ListPanel
