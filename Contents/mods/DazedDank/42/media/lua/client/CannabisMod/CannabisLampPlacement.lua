-- Ceiling grow lamps need every tile indoors and off tables, while floor flood lights can go anywhere. Also feeds the range preview.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRangePreview"
require "Moveables/ISMoveableSpriteProps"

local Config = CannabisMod.Config
local Preview = CannabisMod.RangePreview

if ISMoveableSpriteProps and ISMoveableSpriteProps.canPlaceMoveable then
    local originalCanPlace = ISMoveableSpriteProps.canPlaceMoveable

    function ISMoveableSpriteProps:canPlaceMoveable(character, square, item)
        Preview.note(self, square)
        local lamp = Config.Light.SPRITES[self.spriteName]
        if lamp and not lamp.floor then
            for _, sq in ipairs(Preview.coveredSquares(self, square)) do
                local ok, indoors = pcall(function()
                    return sq ~= nil and not sq:isOutside() and not sq:has("IsTable")
                end)
                if not (ok and indoors) then return false end
            end
        end
        return originalCanPlace(self, character, square, item)
    end
end
