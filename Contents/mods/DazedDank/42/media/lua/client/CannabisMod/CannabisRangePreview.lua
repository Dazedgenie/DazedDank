-- Tints the floor squares a grow lamp or drying fan will affect while it is being placed. CannabisLampPlacement feeds it the cursor target.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local RangePreview = {}
CannabisMod.RangePreview = RangePreview

local LAMP_COLOR = { 1.0, 0.5, 0.05, 0.6 }
local FAN_COLOR  = { 0.3, 0.7, 1.0, 0.45 }
local FRESH_TICKS = 8  -- keep drawing this long after the last cursor update

local preview = nil    -- { squares = { {x, y, z}... }, radius, color, age }

--- Radius and colour for a sprite that has an area of effect, or nil.
local function rangeFor(spriteName)
    local lamp = Config.Light.SPRITES[spriteName]
    if lamp then return lamp.radius, LAMP_COLOR end
    if spriteName == Config.Drying.FAN_SPRITE then return Config.Drying.FAN_RADIUS, FAN_COLOR end
    return nil
end

--- Every square the item being placed covers (more than one for a bar lamp).
function RangePreview.coveredSquares(props, square)
    local out = { square }
    if props.isMultiSprite then
        pcall(function()
            local info = props:getSpriteGridInfo(square, false)
            if info then
                out = {}
                for _, member in ipairs(info) do out[#out + 1] = member.square end
            end
        end)
    end
    return out
end

--- Called as the placement cursor moves over `square` with the item `props` describes.
function RangePreview.note(props, square)
    local radius, color = rangeFor(props.spriteName)
    if not (radius and square) then return end
    local squares = {}
    for _, sq in ipairs(RangePreview.coveredSquares(props, square)) do
        squares[#squares + 1] = { sq:getX(), sq:getY(), sq:getZ() }
    end
    preview = { squares = squares, radius = radius, color = color, age = 0 }
end

Events.OnTick.Add(function()
    if not preview then return end
    preview.age = preview.age + 1
    if preview.age > FRESH_TICKS then preview = nil return end
    local cell, r, c = getCell(), preview.radius, preview.color
    local reach = math.ceil(r)
    local seen = {}
    for _, origin in ipairs(preview.squares) do
        for dx = -reach, reach do
            for dy = -reach, reach do
                local x, y, z = origin[1] + dx, origin[2] + dy, origin[3]
                local key = x .. "_" .. y
                if not seen[key] and Config.Light.reaches(dx, dy, r) then
                    seen[key] = true
                    local square = cell:getGridSquare(x, y, z)
                    local floor = square and square:getFloor()
                    if floor then
                        pcall(function()
                            floor:setHighlightColor(c[1], c[2], c[3], c[4])
                            floor:setHighlighted(true, true)
                        end)
                    end
                end
            end
        end
    end
end)
