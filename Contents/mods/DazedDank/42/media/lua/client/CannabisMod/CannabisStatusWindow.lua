-- The plant status window: a draggable panel that draws the operations from CannabisStatusLayout.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "CannabisMod/CannabisStatusLayout"

local Layout = CannabisMod.StatusLayout

local FONTS = { Small = UIFont.Small, Medium = UIFont.Medium }

local StatusWindow = {}
CannabisMod.StatusWindow = StatusWindow

local function fontHeight(name) return getTextManager():getFontHeight(FONTS[name] or UIFont.Small) end
local function measure(name, str) return getTextManager():MeasureStringX(FONTS[name] or UIFont.Small, str) end

local PlantPanel = ISPanel:derive("CannabisPlantPanel")

function PlantPanel:render()
    for _, op in ipairs(self.model.ops) do
        local c = op.color
        if op.kind == "rect" then
            self:drawRect(op.x, op.y, op.w, op.h, op.a or 1, c[1], c[2], c[3])
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
function StatusWindow.open(data)
    local model = Layout.build(data, fontHeight, measure)
    local titleH = ISCollapsableWindow.TitleBarHeight()
    local win = ISCollapsableWindow:new(200, 200, model.width, model.height + titleH)
    win:initialise()
    win:setTitle("Cannabis Plant")
    win.resizable = false
    local panel = PlantPanel:new(0, titleH, model.width, model.height)
    panel:initialise()
    panel.model = model
    panel.background = false
    panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    win:addChild(panel)
    win:addToUIManager()
    win:setVisible(true)
    return win
end
