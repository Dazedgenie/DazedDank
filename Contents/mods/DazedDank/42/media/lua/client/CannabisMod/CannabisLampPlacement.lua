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

    -- Floor gear a ceiling lamp may hang over even though its tile says BlocksPlacement: Dazed Dank pots and hydro,
    -- Dazed Plumbing pipes and tanks (every Plumbing tile carries the flag), and farm plots.
    local LOW_PREFIXES = { "dazeddank_", "dazedplumbing_", "vegetation_farming" }
    local function passable(name)
        for _, p in ipairs(LOW_PREFIXES) do
            if name:sub(1, #p) == p then return true end
        end
        return false
    end

    --- isFreeTile for a ceiling lamp: only a blocker that isn't floor gear we know of stops it.
    local function freeForLamp(_, sq)
        if not sq or sq:has(IsoFlagType.canBeCut) or sq:has("tree") then return false end
        if not sq:has("BlocksPlacement") or sq:has(IsoFlagType.canBeRemoved) then return true end
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            local sprite = objects:get(i):getSprite()
            local props = sprite and sprite:getProperties()
            if props and props:has("BlocksPlacement") and not passable(sprite:getName() or "") then return false end
        end
        return true
    end

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
        if lamp and not lamp.floor then
            -- Swap in the lamp's free-tile test for this one check, then put the class's back.
            self.isFreeTile = freeForLamp
            local ok, result = pcall(originalCanPlace, self, character, square, item)
            self.isFreeTile = nil
            return ok and result or false
        end
        return originalCanPlace(self, character, square, item)
    end
end
