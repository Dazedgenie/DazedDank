-- Ceiling grow lamps need every tile indoors and off tables, floor flood lights can go anywhere, and hydro gear stays indoors. Also feeds the range preview.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRangePreview"
require "Moveables/ISMoveableSpriteProps"

local Config = CannabisMod.Config
local Preview = CannabisMod.RangePreview

if ISMoveableSpriteProps and ISMoveableSpriteProps.canPlaceMoveable then
    local originalCanPlace = ISMoveableSpriteProps.canPlaceMoveable

    --- True for an indoor square without a table on it.
    local function indoorsOffTable(sq) return sq ~= nil and not sq:isOutside() and not sq:has("IsTable") end
    --- True for an indoor square.
    local function indoors(sq) return sq ~= nil and not sq:isOutside() end

    -- Runs every frame while any furniture is being placed, so other items fall through after two table lookups.
    function ISMoveableSpriteProps:canPlaceMoveable(character, square, item)
        Preview.note(self, square)
        local lamp = Config.Light.SPRITES[self.spriteName]
        if lamp and not lamp.floor then
            -- Ceiling lamps hang high, so vanilla lets them go over low gear like the RDWC control bucket and flood reservoir.
            self.isHigh = true
            for _, sq in ipairs(Preview.coveredSquares(self, square)) do
                local ok, inside = pcall(indoorsOffTable, sq)
                if not (ok and inside) then return false end
            end
        end
        -- Hydro systems are indoor gear: the reservoir and pumps need shelter.
        local kind = Config.bagFromFurnSprite(self.spriteName)
        if (kind and Config.isHydro(kind)) or self.spriteName == Config.Hydro.CONTROL_SPRITE
                or self.spriteName == Config.Hydro.FLOOD_SPRITE then
            local ok, inside = pcall(indoors, square)
            if not (ok and inside) then return false end
        end
        return originalCanPlace(self, character, square, item)
    end
end
