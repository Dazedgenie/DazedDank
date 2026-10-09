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

    --- isFreeTile for a ceiling lamp: only a blocker that isn't floor gear we know of stops it. Returns false plus the blocking sprite name.
    local function freeForLamp(_, sq)
        if not sq then return false, "no square" end
        if sq:has(IsoFlagType.canBeCut) then return false, "brush" end
        if sq:has("tree") then return false, "tree" end
        if not sq:has("BlocksPlacement") or sq:has(IsoFlagType.canBeRemoved) then return true end
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            local sprite = objects:get(i):getSprite()
            local props = sprite and sprite:getProperties()
            local name = sprite and sprite:getName() or ""
            if props and props:has("BlocksPlacement") and not passable(name) then return false, name end
        end
        return true
    end

    --- True when a ceiling grow lamp's sprite is already on this square.
    local function hasCeilingLamp(sq)
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            local sprite = objects:get(i):getSprite()
            local lamp = sprite and Config.Light.SPRITES[sprite:getName() or ""]
            if lamp and not lamp.floor then return true end
        end
        return false
    end

    -- One console line per refused square (at most every 2 s), so a lamp that won't place can be traced in console.txt.
    local traceAt, traceKey = 0, nil
    local function trace(sq, why)
        local now = getTimestampMs()
        local key = sq and (sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()) or "?"
        if key == traceKey and now - traceAt < 2000 then return end
        traceAt, traceKey = now, key
        local parts = {}
        pcall(function()
            local objects = sq:getObjects()
            for i = 0, objects:size() - 1 do
                local sprite = objects:get(i):getSprite()
                local props = sprite and sprite:getProperties()
                local flags = {}
                for _, f in ipairs({ "IsLow", "IsHigh", "BlocksPlacement", "IsTable", "IsTableTop" }) do
                    if props and props:has(f) then flags[#flags + 1] = f end
                end
                parts[#parts + 1] = tostring(sprite and sprite:getName()) .. (#flags > 0 and ("[" .. table.concat(flags, ",") .. "]") or "")
            end
        end)
        print("[DazedDank] lamp can't go at " .. key .. " (" .. why .. "): " .. table.concat(parts, " "))
    end

    --- The reason one covered square refuses a ceiling lamp, or nil when it is fine.
    local function squareRefusal(props, sq)
        if not sq then return "no square" end
        if not sq:getFloor() then return "no floor" end
        if sq:has(IsoFlagType.water) then return "water" end
        if sq:isVehicleIntersecting() then return "vehicle in the way" end
        if not indoorsOffTable(sq) then return "outdoors or on a table" end
        local free, blocker = freeForLamp(nil, sq)
        if not free then return "blocked by " .. tostring(blocker) end
        if hasCeilingLamp(sq) then return "lamp already here" end
        if props.isSquareAtTopOfStairs and props:isSquareAtTopOfStairs(sq) then return "top of stairs" end
        return nil
    end

    --- True when the player has the skill and tool vanilla asks for to place this; allowed when the checks can't run.
    local function playerCanPlace(props, character)
        if not (character and instanceof(character, "IsoPlayer")) then return true end
        if ISMoveableDefinitions and ISMoveableDefinitions.cheat then return true end
        if character.isMovablesCheat and character:isMovablesCheat() then return true end
        if not (props.hasRequiredSkill and props.hasTool) then return true end
        local hasSkill = props:hasRequiredSkill(character, "place")
        local hasTool = not props.placeTool or props:hasTool(character, "place")
        return (hasSkill and hasTool) and true or false
    end

    --- Our own placement check for a ceiling lamp, so vanilla's refusals over low hydro gear no longer apply.
    local function lampCanPlace(props, character, square)
        if not square then return false end
        for _, sq in ipairs(Preview.coveredSquares(props, square)) do
            local ok, why = pcall(squareRefusal, props, sq)
            if not ok then why = "check failed: " .. tostring(why) end
            if why then
                trace(sq, why)
                return false
            end
        end
        local ok, allowed = pcall(playerCanPlace, props, character)
        if ok and not allowed then
            trace(square, "needs skill or tool")
            return false
        end
        return true
    end

    -- Runs every frame while any furniture is being placed, so other items fall through after two table lookups.
    function ISMoveableSpriteProps:canPlaceMoveable(character, square, item)
        Preview.note(self, square)
        local lamp = Config.Light.SPRITES[self.spriteName]
        if lamp and not lamp.floor then
            -- Ceiling lamps hang high; other code reads isHigh.
            self.isHigh = true
            return lampCanPlace(self, character, square)
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
