-- The plant status window: a draggable panel that draws the operations from CannabisStatusLayout.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISPanel"
require "CannabisMod/CannabisStatusLayout"
require "CannabisMod/CannabisUIDraw"

local Layout = CannabisMod.StatusLayout
local Draw = CannabisMod.UIDraw

local FONTS = { Small = UIFont.Small, Medium = UIFont.Medium }

local StatusWindow = {}
CannabisMod.StatusWindow = StatusWindow

local function fontHeight(name) return getTextManager():getFontHeight(FONTS[name] or UIFont.Small) end
local function measure(name, str) return getTextManager():MeasureStringX(FONTS[name] or UIFont.Small, str) end

local PlantPanel = ISPanel:derive("CannabisPlantPanel")

-- The layout draws in prerender, under the close button; render runs after children, so drawing there hid it.
function PlantPanel:prerender()
    local g = Layout.COLORS.ground
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
        else
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

--- Open the window for a plant info reply; returns it so the caller can close the old one.
-- The dark title bar is part of the layout, so the window is a plain panel dragged by its body, with a close button on the bar.
function StatusWindow.open(data)
    local model = Layout.build(data, fontHeight, measure)
    local x = math.max(0, math.min(200, getCore():getScreenWidth() - model.width))
    local y = math.max(0, math.min(120, getCore():getScreenHeight() - model.height))
    local panel = PlantPanel:new(x, y, model.width, model.height)
    panel:initialise()
    panel.model = model
    panel.background = false
    panel.moveWithMouse = true
    panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    local close = ISButton:new(model.width - 36, 6, 28, 28, "X", panel, function(p) p:removeFromUIManager() end)
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
