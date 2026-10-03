-- Tints the floor squares a grow lamp or drying fan will affect while it is being placed. CannabisLampPlacement feeds it the cursor target.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local RangePreview = {}
CannabisMod.RangePreview = RangePreview

local LAMP_COLOR = { 1.0, 0.5, 0.05, 0.6 }
local FAN_COLOR  = { 0.3, 0.7, 1.0, 0.45 }
local FRESH_TICKS = 8  -- keep drawing this long after the last cursor update

local preview = nil    -- { sprite, x, y, z, floors = { floor objects to tint }, color, age }

--- Radius, colour and shape for a sprite that has an area of effect, or nil.
--- Lamps light a round zone scaled by the LampRange setting; a fan dries a square box of fixed size.
local function rangeFor(spriteName)
    local lamp = Config.Light.SPRITES[spriteName]
    if lamp then return lamp.radius, LAMP_COLOR, true end
    if spriteName == Config.Drying.FAN_SPRITE then return Config.Drying.FAN_RADIUS, FAN_COLOR, false end
    return nil
end

--- Read a bar lamp's grid of squares into `out`.
local function gridSquares(props, square, out)
    local info = props:getSpriteGridInfo(square, false)
    if not info then return end
    for i = #out, 1, -1 do out[i] = nil end
    for _, member in ipairs(info) do out[#out + 1] = member.square end
end

--- Every square the item being placed covers (more than one for a bar lamp).
function RangePreview.coveredSquares(props, square)
    local out = { square }
    if props.isMultiSprite then pcall(gridSquares, props, square, out) end
    if #out == 0 then out[1] = square end
    return out
end

--- The floors within reach of the covered squares, each listed once.
local function floorsInRange(props, square, radius, round)
    local cell, reaches = getCell(), Config.Light.reaches
    local range = round and (Config.sandbox("LampRange") or 1) or 1
    local reach = math.ceil(radius * range)
    local seen, floors = {}, {}
    for _, origin in ipairs(RangePreview.coveredSquares(props, square)) do
        local ox, oy, oz = origin:getX(), origin:getY(), origin:getZ()
        for dx = -reach, reach do
            local x = ox + dx
            local column = seen[x]
            if not column then column = {} seen[x] = column end
            for dy = -reach, reach do
                local y = oy + dy
                if not column[y] and (not round or reaches(dx, dy, radius, range)) then
                    column[y] = true
                    local target = cell:getGridSquare(x, y, oz)
                    local floor = target and target:getFloor()
                    if floor then floors[#floors + 1] = floor end
                end
            end
        end
    end
    return floors
end

--- Called as the placement cursor moves over `square` with the item `props` describes.
--- The tiles in range are worked out only when the cursor reaches a new square or the item turns.
function RangePreview.note(props, square)
    local radius, color, round = rangeFor(props.spriteName)
    if not (radius and square) then return end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local p = preview
    if p and p.sprite == props.spriteName and p.x == x and p.y == y and p.z == z then
        p.age = 0
        return
    end
    preview = { sprite = props.spriteName, x = x, y = y, z = z, color = color, age = 0,
                floors = floorsInRange(props, square, radius, round) }
end

--- Tint one floor tile for this frame.
local function tint(floor, c)
    floor:setHighlightColor(c[1], c[2], c[3], c[4])
    floor:setHighlighted(true, true)
end

Events.OnTick.Add(function()
    local p = preview
    if not p then return end
    p.age = p.age + 1
    if p.age > FRESH_TICKS then preview = nil return end
    local c = p.color
    for _, floor in ipairs(p.floors) do pcall(tint, floor, c) end
end)
